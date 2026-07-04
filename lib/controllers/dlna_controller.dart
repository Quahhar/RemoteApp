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
import 'lan_scan.dart';
import 'remote_controller.dart';
import 'ssdp.dart';

/// UPnP/DLNA MediaRenderer control over SOAP/HTTP.
///
/// This is the protocol of last resort that nonetheless works on a huge range of
/// TVs — including modern Hisense/VIDAA sets whose MQTT remote (port 36669) is
/// firmware-locked to the official app. The TV's media stack exposes an
/// unauthenticated `MediaRenderer` device (on VIDAA: port 18400) with two useful
/// services:
///  - `RenderingControl` — volume + mute.
///  - `AVTransport`      — play/pause/stop/seek and "cast a URL to the TV"
///    (`SetAVTransportURI`).
///
/// There is **no** D-pad / navigation / power / app-launch here — UPnP simply
/// doesn't model those — so [sendKey] supports only the volume/mute/transport
/// subset and throws for the rest. Importantly, on some TVs the renderer's
/// volume/transport only take effect while a cast session it started is active
/// (the live-TV UI keeps its own state); casting (push a URL + play) is the most
/// universally reliable capability.
///
/// Like Roku ECP, this is stateless HTTP: [connect] resolves the per-service
/// control URLs from the device descriptor and verifies reachability; commands
/// are one-shot SOAP POSTs.
class DlnaController extends RemoteController {
  DlnaController({
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 5),
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
  Uri? _renderingControl;
  Uri? _avTransport;
  Uri? _descriptorUri;

  /// Like Roku, DLNA is stateless HTTP, so a periodic GET of the descriptor is
  /// what detects the TV going offline and flips the status to `error`.
  Timer? _heartbeat;

  /// Serializes volume/mute read-modify-write cycles so concurrent key presses
  /// don't race on GetVolume → SetVolume (or GetMute → SetMute).
  final _VolumeLock _volumeLock = _VolumeLock();

  static const String renderingControlType =
      'urn:schemas-upnp-org:service:RenderingControl:1';
  static const String avTransportType =
      'urn:schemas-upnp-org:service:AVTransport:1';
  static const String _mediaRendererTarget =
      'urn:schemas-upnp-org:device:MediaRenderer:1';

  /// How much each volume key press moves the absolute volume (UPnP has no
  /// relative-volume action on most renderers, so we read-modify-write).
  static const int volumeStep = 2;

  /// Descriptor locations to probe, in order. VIDAA's renderer descriptor lives
  /// at the first path; the rest cover common DMR layouts so the same controller
  /// drives other brands discovered by SSDP.
  static const List<String> _descriptorPaths = [
    '/MediaServer/rendererdevicedesc.xml',
    '/description.xml',
    '/dmr.xml',
    '/MediaRenderer/desc.xml',
    '/rootDesc.xml',
    '/dd.xml',
    '/',
  ];

  @override
  ProtocolType get protocol => ProtocolType.dlna;

  @override
  Capabilities get capabilities => const Capabilities(
    supportsPointer: false,
    supportsTextInput: false,
    channelButtons: false, // UPnP renderers have no channel control
    numberPad: false,
    supportsNavigation: false, // no D-pad/OK/back/home/menu in UPnP
    supportsPower: false, // no power action in UPnP
  );

  // --- Discovery -------------------------------------------------------------

  /// Finds MediaRenderers two ways and merges them: SSDP multicast (carries a
  /// friendly name) and a targeted scan of the VIDAA renderer port, which still
  /// works on Wi-Fi that blocks multicast (AP isolation) — the same belt-and-
  /// braces approach the cross-protocol port scan uses.
  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) {
    final out = StreamController<Device>();
    final seen = <String>{};
    var pending = 2;

    void onSourceDone() {
      pending -= 1;
      if (pending == 0 && !out.isClosed) out.close();
    }

    Future<void> resolveAndAdd(String host, int port) async {
      if (!seen.add(host)) return;
      final device = await _describe(host, port);
      if (!out.isClosed) out.add(device);
    }

    final ssdpSub =
        ssdpSearch(searchTarget: _mediaRendererTarget, timeout: timeout).listen(
          (resp) {
            final location = resp.header('LOCATION');
            final uri = location == null ? null : Uri.tryParse(location);
            final host = (uri != null && uri.host.isNotEmpty)
                ? uri.host
                : resp.address;
            final port = (uri != null && uri.hasPort)
                ? uri.port
                : ProtocolType.dlna.defaultPort;
            resolveAndAdd(host, port);
          },
          onError: (_) {},
          onDone: onSourceDone,
          cancelOnError: false,
        );

    final scanSub =
        scanSubnetForAnyPort({
          ProtocolType.dlna.defaultPort,
        }, timeout: timeout).listen(
          (hit) => resolveAndAdd(hit.host, hit.port),
          onError: (_) {},
          onDone: onSourceDone,
          cancelOnError: false,
        );

    out.onCancel = () {
      ssdpSub.cancel();
      scanSub.cancel();
    };
    return out.stream;
  }

  Future<Device> _describe(String host, int port) async {
    final portOverride = port == ProtocolType.dlna.defaultPort ? null : port;
    var name = 'Cast TV ($host)';
    var id = 'dlna-$host';
    try {
      final desc = await _fetchDescriptor(host, port);
      final friendly = tag(desc.body, 'friendlyName');
      final udn = tag(desc.body, 'UDN');
      if (friendly != null && friendly.trim().isNotEmpty) {
        name = friendly.trim();
      }
      if (udn != null && udn.trim().isNotEmpty) id = udn.trim();
    } catch (_) {
      // Keep host-based fallback so the user can still try to connect.
    }
    return Device(
      id: id,
      name: name,
      host: host,
      protocol: ProtocolType.dlna,
      port: portOverride,
    );
  }

  // --- Connection ------------------------------------------------------------

  @override
  Future<void> connect(Device device) async {
    emitStatus(ConnectionStatus.connecting);
    _device = device;
    try {
      final desc = await _fetchDescriptor(device.host, device.effectivePort);
      final services = parseControlUrls(desc.body, desc.descriptor);
      _renderingControl = services[renderingControlType];
      _avTransport = services[avTransportType];
      if (_renderingControl == null && _avTransport == null) {
        throw const NotReachableException(
          'This device has no controllable media-renderer services.',
        );
      }
      _descriptorUri = desc.descriptor;
      emitStatus(ConnectionStatus.connected);
      _startHeartbeat();
    } on RemoteException {
      emitStatus(ConnectionStatus.error);
      rethrow;
    } catch (_) {
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException();
    }
  }

  /// Whether the renderer's descriptor still answers — a cheap liveness check
  /// for the heartbeat.
  Future<bool> _reachable() async {
    final uri = _descriptorUri;
    if (uri == null) return false;
    try {
      final res = await _client.get(uri).timeout(_requestTimeout);
      return res.statusCode == 200;
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
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
      if (_device == null || probing) return;
      probing = true;
      try {
        final reachable = await _reachable();
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
    _renderingControl = null;
    _avTransport = null;
    _descriptorUri = null;
    emitStatus(ConnectionStatus.disconnected);
  }

  /// Tries each candidate descriptor path until one returns a UPnP device
  /// document; returns the resolved descriptor URI (for relative-URL resolution)
  /// plus its body.
  Future<({Uri descriptor, String body})> _fetchDescriptor(
    String host,
    int port,
  ) async {
    for (final path in _descriptorPaths) {
      final uri = Uri.parse('http://$host:$port$path');
      try {
        final res = await _client.get(uri).timeout(_requestTimeout);
        if (res.statusCode == 200 && res.body.contains('serviceType')) {
          return (descriptor: uri, body: res.body);
        }
      } on TimeoutException {
        // try next path
      } on SocketException {
        // try next path
      } on http.ClientException {
        // try next path
      }
    }
    throw const NotReachableException(
      'Could not read the TV\u2019s media-renderer description.',
    );
  }

  // --- Control ---------------------------------------------------------------

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (_device == null) {
      throw const RemoteException('No active device');
    }
    switch (key) {
      case RemoteKey.volumeUp:
        await _nudgeVolume(volumeStep);
      case RemoteKey.volumeDown:
        await _nudgeVolume(-volumeStep);
      case RemoteKey.mute:
        await _toggleMute();
      case RemoteKey.play:
        await _avAction('Play', const {'InstanceID': '0', 'Speed': '1'});
      case RemoteKey.pause:
        await _avAction('Pause', const {'InstanceID': '0'});
      case RemoteKey.stop:
        await _avAction('Stop', const {'InstanceID': '0'});
      default:
        // Key-agnostic on purpose: the message must not change per button, so
        // tapping different unsupported keys shows one stable (de-duped) banner.
        throw const RemoteException(
          'That button isn\u2019t available over Cast on this TV.',
        );
    }
  }

  /// Stop the current cast playback. (No [RemoteKey] maps to stop, so it is a
  /// direct method for the cast UI.)
  Future<void> stop() => _avAction('Stop', const {'InstanceID': '0'});

  /// Push a media [url] to the TV and start playing it — the DLNA "cast"
  /// gesture. [contentType] tunes the DIDL metadata so the TV picks the right
  /// player (video/audio/image).
  Future<void> castUrl(
    String url, {
    String title = 'Cast',
    String contentType = 'video/mp4',
  }) async {
    await _avAction('SetAVTransportURI', {
      'InstanceID': '0',
      'CurrentURI': url,
      'CurrentURIMetaData': didlMetadata(url, title, contentType),
    });
    await _avAction('Play', const {'InstanceID': '0', 'Speed': '1'});
  }

  Future<void> _nudgeVolume(int delta) async {
    // Guard against overlapping volume read-modify-write cycles (rapid button
    // presses or multiple remotes). Without this, two concurrent nudges both
    // read the same current value and the second write clobbers the first.
    await _volumeLock.acquire();
    try {
      final current = await _currentVolume();
      final next = (current + delta).clamp(0, 100).toInt();
      await _rcAction('SetVolume', {
        'InstanceID': '0',
        'Channel': 'Master',
        'DesiredVolume': '$next',
      });
    } finally {
      _volumeLock.release();
    }
  }

  Future<int> _currentVolume() async {
    final body = await _rcAction('GetVolume', const {
      'InstanceID': '0',
      'Channel': 'Master',
    });
    return intTag(body, 'CurrentVolume') ?? 0;
  }

  Future<void> _toggleMute() async {
    // Same guard as _nudgeVolume: prevent lost updates on concurrent toggles.
    await _volumeLock.acquire();
    try {
      final body = await _rcAction('GetMute', const {
        'InstanceID': '0',
        'Channel': 'Master',
      });
      final muted = intTag(body, 'CurrentMute') == 1;
      await _rcAction('SetMute', {
        'InstanceID': '0',
        'Channel': 'Master',
        'DesiredMute': muted ? '0' : '1',
      });
    } finally {
      _volumeLock.release();
    }
  }

  Future<String> _rcAction(String action, Map<String, String> args) {
    final url = _renderingControl;
    if (url == null) {
      throw const RemoteException('Volume control is unavailable on this TV.');
    }
    return _soap(url, renderingControlType, action, args);
  }

  Future<String> _avAction(String action, Map<String, String> args) {
    final url = _avTransport;
    if (url == null) {
      throw const RemoteException(
        'Playback control is unavailable on this TV.',
      );
    }
    return _soap(url, avTransportType, action, args);
  }

  Future<String> _soap(
    Uri control,
    String serviceType,
    String action,
    Map<String, String> args,
  ) async {
    try {
      final res = await _client
          .post(
            control,
            headers: {
              'Content-Type': 'text/xml; charset=utf-8',
              'SOAPACTION': '"$serviceType#$action"',
            },
            body: buildSoapBody(serviceType, action, args),
          )
          .timeout(_requestTimeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (!status.isConnected) emitStatus(ConnectionStatus.connected);
        return res.body;
      }
      // A SOAP fault is delivered as HTTP 500 with a UPnP errorCode/description.
      throw RemoteException(
        faultMessage(res.body) ??
            'The TV rejected $action (HTTP ${res.statusCode}).',
      );
    } on TimeoutException {
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException();
    } on SocketException {
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException();
    } on http.ClientException {
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException();
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  // --- Pure helpers (exposed for unit tests) ---------------------------------

  /// XML escape a string for SOAP body text and DIDL metadata values.
  /// Uses dart:convert HtmlEscape which produces the five standard XML entities.
  static final XmlEscape _xmlEscape = XmlEscape();

  /// Build the SOAP 1.1 envelope for a UPnP action. Argument values are
  /// XML-escaped, so structured values like DIDL metadata can be passed as-is.
  @visibleForTesting
  static String buildSoapBody(
    String serviceType,
    String action,
    Map<String, String> args,
  ) {
    final argsXml = args.entries
        .map((e) => '<${e.key}>${_xmlEscape.convert(e.value)}</${e.key}>')
        .join();
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="$serviceType">$argsXml</u:$action></s:Body>'
        '</s:Envelope>';
  }

  /// Minimal DIDL-Lite item describing a single media resource for
  /// `SetAVTransportURI`. The `upnp:class` is chosen from [contentType] so the
  /// TV launches the right player.
  @visibleForTesting
  static String didlMetadata(String url, String title, String contentType) {
    final upnpClass = contentType.startsWith('audio')
        ? 'object.item.audioItem.musicTrack'
        : contentType.startsWith('image')
        ? 'object.item.imageItem.photo'
        : 'object.item.videoItem';
    final esc = _xmlEscape.convert;
    return '<DIDL-Lite '
        'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>${esc(title)}</dc:title>'
        '<upnp:class>$upnpClass</upnp:class>'
        '<res protocolInfo="http-get:*:$contentType:*">'
        '${esc(url)}</res>'
        '</item></DIDL-Lite>';
  }

  /// Map each `<service>`'s `serviceType` to its absolute control URL, resolving
  /// relative `controlURL`s against `<URLBase>` (if present) or the descriptor
  /// URL.
  @visibleForTesting
  static Map<String, Uri> parseControlUrls(String xml, Uri descriptorUri) {
    final base = _urlBase(xml, descriptorUri);
    final out = <String, Uri>{};
    for (final match in RegExp(
      r'<service>(.*?)</service>',
      dotAll: true,
    ).allMatches(xml)) {
      final block = match.group(1)!;
      final type = tag(block, 'serviceType');
      final control = tag(block, 'controlURL');
      if (type != null && control != null) {
        out[type.trim()] = base.resolve(control.trim());
      }
    }
    return out;
  }

  /// Read an integer-valued flat tag (e.g. `<CurrentVolume>9</CurrentVolume>`).
  @visibleForTesting
  static int? intTag(String xml, String name) {
    final raw = tag(xml, name);
    return raw == null ? null : int.tryParse(raw.trim());
  }

  /// Extract the text of a flat `<name>...</name>` tag; case-insensitive.
  @visibleForTesting
  static String? tag(String xml, String name) => RegExp(
    '<$name[^>]*>(.*?)</$name>',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(xml)?.group(1);

  /// Turn a UPnP SOAP fault body into a readable message, or null if it isn't
  /// one.
  @visibleForTesting
  static String? faultMessage(String body) {
    final code = tag(body, 'errorCode');
    final desc = tag(body, 'errorDescription');
    if (code == null && desc == null) return null;
    return 'TV refused the command (UPnP ${code ?? '?'}'
        '${desc == null ? '' : ': ${desc.trim()}'}).';
  }

  static Uri _urlBase(String xml, Uri descriptorUri) {
    final base = tag(xml, 'URLBase');
    if (base != null && base.trim().isNotEmpty) {
      final parsed = Uri.tryParse(base.trim());
      if (parsed != null && parsed.hasAuthority) return parsed;
    }
    return descriptorUri;
  }
}

/// Simple non-reentrant async lock that serializes critical sections without
/// blocking the event loop. Acquisitions are granted in FIFO order: each
/// [acquire] resolves once every earlier holder has [release]d.
///
/// The earlier version completed the newest waiter's completer on release
/// instead of the current holder's, so a second overlapping acquire waited on a
/// completer that was never completed and hung forever. This queue hands the
/// lock straight to the next waiter, keeping it held across the handoff.
class _VolumeLock {
  bool _held = false;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() {
    if (!_held) {
      _held = true;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(); // stays held; next waiter now owns it
    } else {
      _held = false;
    }
  }
}

/// Produces the five standard XML/HTML named entities (& < > " ').
class XmlEscape extends Converter<String, String> {
  const XmlEscape();

  static final String _amp = _entity(38); // &
  static final String _lt = _entity(60); // <
  static final String _gt = _entity(62); // >
  static final String _quot = _entity(34); // "
  static final String _apos = _entity(39); // '

  static String _entity(int code) {
    return String.fromCharCode(0x26) + // '&'
        switch (code) {
          38 => 'amp',
          60 => 'lt',
          62 => 'gt',
          34 => 'quot',
          39 => 'apos',
          _ => throw ArgumentError('unexpected entity char $code'),
        } +
        String.fromCharCode(0x3B); // ';'
  }

  @override
  String convert(String input) {
    final buf = StringBuffer();
    for (final code in input.codeUnits) {
      switch (code) {
        case 38:
          buf.write(_amp);
          break;
        case 60:
          buf.write(_lt);
          break;
        case 62:
          buf.write(_gt);
          break;
        case 34:
          buf.write(_quot);
          break;
        case 39:
          buf.write(_apos);
          break;
        default:
          buf.writeCharCode(code);
      }
    }
    return buf.toString();
  }
}
