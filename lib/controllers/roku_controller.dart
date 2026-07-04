import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/capabilities.dart';
import '../models/connection_status.dart';
import '../models/device.dart';
import '../models/protocol_type.dart';
import '../models/remote_key.dart';
import 'remote_controller.dart';
import 'text_input.dart';

/// Roku — the proof-of-concept protocol.
///
/// Discovery: SSDP M-SEARCH for `roku:ecp` over UDP multicast, then a
/// `/query/device-info` fetch to resolve a friendly name and a stable id.
/// Control: `POST http://{host}:8060/keypress/{KeyName}` (ECP). No auth.
///
/// Roku ECP is stateless HTTP, so "connect" just verifies reachability and
/// "disconnect" is local bookkeeping.
class RokuController extends RemoteController {
  RokuController({
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 4),
    Duration heartbeatInterval = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _requestTimeout = requestTimeout,
       _heartbeatInterval = heartbeatInterval;

  final http.Client _client;
  final bool _ownsClient;
  final Duration _requestTimeout;
  final Duration _heartbeatInterval;

  Device? _device;

  /// Stateless ECP has no persistent socket, so a periodic reachability probe is
  /// what flips the status to `error` when the TV goes offline (otherwise it
  /// would read "Connected" until the next failed keypress).
  Timer? _heartbeat;

  static const String _ssdpAddress = '239.255.255.250';
  static const int _ssdpPort = 1900;
  static const String _searchTarget = 'roku:ecp';

  /// RemoteKey -> Roku ECP key name. Every [RemoteKey] is mapped (verified by
  /// unit tests). Notes:
  ///  - `menu` -> `Info` (Roku's `*` options button).
  ///  - `pause` -> `Play` (Roku has no discrete pause; `Play` toggles).
  ///  - volume/channel keys only act on Roku TVs; boxes ignore them harmlessly.
  static const Map<RemoteKey, String> keyNames = {
    RemoteKey.power: 'Power',
    RemoteKey.up: 'Up',
    RemoteKey.down: 'Down',
    RemoteKey.left: 'Left',
    RemoteKey.right: 'Right',
    RemoteKey.ok: 'Select',
    RemoteKey.back: 'Back',
    RemoteKey.home: 'Home',
    RemoteKey.menu: 'Info',
    RemoteKey.volumeUp: 'VolumeUp',
    RemoteKey.volumeDown: 'VolumeDown',
    RemoteKey.mute: 'VolumeMute',
    RemoteKey.channelUp: 'ChannelUp',
    RemoteKey.channelDown: 'ChannelDown',
    RemoteKey.play: 'Play',
    RemoteKey.pause: 'Play',
    // Extended keys Roku ECP genuinely supports. The rest of the More-sheet
    // commands have no ECP equivalent and surface as "not available".
    RemoteKey.rewind: 'Rev',
    RemoteKey.fastForward: 'Fwd',
    RemoteKey.search: 'Search',
    RemoteKey.inputHdmi1: 'InputHDMI1',
    RemoteKey.inputHdmi2: 'InputHDMI2',
    RemoteKey.inputHdmi3: 'InputHDMI3',
    RemoteKey.inputAv: 'InputAV1',
    RemoteKey.inputTv: 'InputTuner',
  };

  @override
  ProtocolType get protocol => ProtocolType.roku;

  @override
  Capabilities get capabilities => const Capabilities(
    supportsPointer: false, // Roku ECP has no pointer
    supportsTextInput: true, // via Lit_ literal-character keypresses
    channelButtons: true,
    numberPad: false,
  );

  // --- Discovery -------------------------------------------------------------

  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) {
    late final StreamController<Device> out;
    RawDatagramSocket? socket;
    Timer? resend;
    Timer? stop;
    final seenHosts = <String>{};
    var cleanedUp = false;

    void cleanup() {
      if (cleanedUp) return;
      cleanedUp = true;
      resend?.cancel();
      stop?.cancel();
      socket?.close();
    }

    Future<void> start() async {
      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } on SocketException catch (e) {
        out.addError(NotReachableException('Discovery failed: ${e.message}'));
        await out.close();
        return;
      }
      socket!.broadcastEnabled = true;
      final target = InternetAddress(_ssdpAddress);
      final payload = utf8.encode(_mSearch());

      socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final location = ssdpHeader(text, 'LOCATION');
        final uri = location == null ? null : Uri.tryParse(location);
        final host = (uri != null && uri.host.isNotEmpty)
            ? uri.host
            : datagram.address.address;
        if (!seenHosts.add(host)) return;
        final port = (uri != null && uri.hasPort)
            ? uri.port
            : ProtocolType.roku.defaultPort;
        _resolveDevice(host, port).then((device) {
          if (!out.isClosed) out.add(device);
        });
      });

      void send() {
        try {
          socket!.send(payload, target, _ssdpPort);
        } catch (_) {
          // Transient send failure (e.g. interface flap); the resend timer
          // will try again within the discovery window.
        }
      }

      send();
      resend = Timer.periodic(const Duration(seconds: 1), (_) => send());
      stop = Timer(timeout, () {
        cleanup();
        out.close();
      });
    }

    out = StreamController<Device>(onListen: start, onCancel: cleanup);
    return out.stream;
  }

  String _mSearch() => const [
    'M-SEARCH * HTTP/1.1',
    'HOST: $_ssdpAddress:$_ssdpPort',
    'MAN: "ssdp:discover"',
    'ST: $_searchTarget',
    'MX: 3',
    '',
    '',
  ].join('\r\n');

  /// Fetch `/query/device-info` to build a named [Device]; on any failure,
  /// still return a usable host-keyed fallback so the user can add it manually.
  Future<Device> _resolveDevice(String host, int port) async {
    final portOverride = port == ProtocolType.roku.defaultPort ? null : port;
    try {
      final res = await _client
          .get(Uri.parse('http://$host:$port/query/device-info'))
          .timeout(_requestTimeout);
      if (res.statusCode == 200) {
        final body = res.body;
        final name =
            (xmlTag(body, 'user-device-name') ??
                    xmlTag(body, 'friendly-device-name') ??
                    xmlTag(body, 'default-device-name') ??
                    xmlTag(body, 'model-name') ??
                    'Roku')
                .trim();
        final id =
            xmlTag(body, 'udn') ??
            xmlTag(body, 'serial-number') ??
            xmlTag(body, 'device-id') ??
            'roku-$host';
        return Device(
          id: id,
          name: name.isEmpty ? 'Roku' : name,
          host: host,
          protocol: ProtocolType.roku,
          port: portOverride,
        );
      }
    } catch (_) {
      // Fall through to fallback device below.
    }
    return Device(
      id: 'roku-$host',
      name: 'Roku ($host)',
      host: host,
      protocol: ProtocolType.roku,
      port: portOverride,
    );
  }

  // --- Connection ------------------------------------------------------------

  /// Shown when the Roku answers HTTP but refuses control — its "Control by
  /// mobile apps" setting is off, which no app can work around.
  static const String controlBlockedMessage =
      'Your Roku is blocking app control. On the TV, set Settings → System → '
      'Advanced system settings → Control by mobile apps → Network access '
      'to "Default", then try again.';

  @override
  Future<void> connect(Device device) async {
    emitStatus(ConnectionStatus.connecting);
    _device = device;
    final code = await _probeStatus(device);
    if (code == 200) {
      emitStatus(ConnectionStatus.connected);
      _startHeartbeat();
      return;
    }
    emitStatus(ConnectionStatus.error);
    // The TV answered but refused — that's the mobile-apps setting, not the
    // network, so tell the user the fix instead of "TV not reachable".
    if (code != null) throw const RemoteException(controlBlockedMessage);
    throw const NotReachableException();
  }

  /// Whether the Roku still answers `/query/device-info`. Used both by [connect]
  /// and the heartbeat.
  Future<bool> _reachable(Device device) async =>
      await _probeStatus(device) == 200;

  /// GET `/query/device-info` and return the HTTP status code, or null when
  /// the TV couldn't be reached at all (timeout / refused / no route).
  Future<int?> _probeStatus(Device device) async {
    try {
      final res = await _client
          .get(_uri(device, '/query/device-info'))
          .timeout(_requestTimeout);
      return res.statusCode;
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on http.ClientException {
      return null;
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    // Self-healing + non-self-cancelling: keep probing while a device is set so
    // the dot tracks the TV both ways — error when it drops, connected when it
    // returns. Only emit on a real transition (emitStatus doesn't de-dupe). The
    // `probing` guard skips a tick if the previous probe is still in flight.
    var probing = false;
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) async {
      final device = _device;
      if (device == null || probing) return;
      probing = true;
      try {
        final reachable = await _reachable(device);
        if (reachable && !status.isConnected) {
          emitStatus(ConnectionStatus.connected);
        } else if (!reachable && status.isConnected) {
          emitStatus(ConnectionStatus.error);
        }
      } finally {
        probing = false;
      }
    });
  }

  @override
  Future<void> disconnect() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _device = null;
    emitStatus(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    final device = _device;
    if (device == null) {
      throw const RemoteException('No active Roku device');
    }
    final name = keyNames[key];
    if (name == null) {
      // Extended More-sheet keys Roku ECP can't send. Key-agnostic message so
      // repeats de-dupe into one SnackBar.
      throw const RemoteException("That button isn't available on this TV.");
    }
    await _postWithRetry(_uri(device, '/keypress/$name'));
  }

  @override
  Future<void> sendText(String text) async {
    final device = _device;
    if (device == null) {
      throw const RemoteException('No active Roku device');
    }
    for (final key in textKeyNames(text)) {
      await _postWithRetry(_uri(device, '/keypress/$key'));
    }
  }

  /// The ordered ECP keypress names for [text]: one `Lit_<urlencoded char>` per
  /// printable character, plus `Enter`/`Backspace` for edit keys. Pure +
  /// exposed for unit tests.
  @visibleForTesting
  static List<String> textKeyNames(String text) {
    final keys = <String>[];
    for (final segment in tokenizeInput(text)) {
      switch (segment) {
        case TextRun(:final text):
          for (final rune in text.runes) {
            keys.add('Lit_${Uri.encodeComponent(String.fromCharCode(rune))}');
          }
        case TextEdit(key: TextEditKey.enter):
          keys.add('Enter');
        case TextEdit(key: TextEditKey.backspace):
          keys.add('Backspace');
      }
    }
    return keys;
  }

  /// POST with one retry on transient transport errors, honoring the timeout.
  /// Non-2xx responses (including 5xx server errors) are NOT retried — they
  /// indicate the TV is reachable but rejected the command, so a different
  /// exception is thrown.
  Future<void> _postWithRetry(Uri uri, {int attempts = 2}) async {
    // ignore: literal_only_throw_errors
    Object lastError = const RemoteException('No active Roku device');
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final res = await _client.post(uri).timeout(_requestTimeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          if (!status.isConnected) emitStatus(ConnectionStatus.connected);
          return;
        }
        // Server returned a non-transient error — don't retry.
        emitStatus(ConnectionStatus.error);
        throw RemoteException(
          res.statusCode == 403
              ? controlBlockedMessage
              : 'Roku rejected the command (HTTP ${res.statusCode}).',
        );
      } on RemoteException {
        rethrow; // don't retry explicit failures
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
    }
    emitStatus(ConnectionStatus.error);
    if (lastError is SocketException || lastError is http.ClientException) {
      throw const NotReachableException();
    }
    throw const NotReachableException();
  }

  Uri _uri(Device device, String path) =>
      Uri.parse('http://${device.host}:${device.effectivePort}$path');

  @override
  void dispose() {
    _heartbeat?.cancel();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  // --- Parsing helpers (exposed for unit tests) ------------------------------

  /// Extract the text content of a flat `<tag>...</tag>` from device-info XML.
  /// Case-insensitive; returns null if absent.
  @visibleForTesting
  static String? xmlTag(String xml, String tag) {
    final match = RegExp(
      '<$tag[^>]*>(.*?)</$tag>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(xml);
    return match?.group(1);
  }

  /// Read a single header value from a raw SSDP/HTTP response. Case-insensitive
  /// on the header name; returns null if not present.
  @visibleForTesting
  static String? ssdpHeader(String response, String name) {
    final wanted = name.toUpperCase();
    for (final line in const LineSplitter().convert(response)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      if (line.substring(0, idx).trim().toUpperCase() == wanted) {
        return line.substring(idx + 1).trim();
      }
    }
    return null;
  }
}
