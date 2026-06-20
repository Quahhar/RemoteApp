import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/capabilities.dart';
import '../models/connection_status.dart';
import '../models/device.dart';
import '../models/protocol_type.dart';
import '../models/remote_key.dart';
import 'remote_controller.dart';
import 'ssdp.dart';
import 'text_input.dart';

/// Samsung Tizen via the `samsung.remote.control` WebSocket channel.
///
/// Connects to `wss://{host}:8002/...` (TLS, self-signed cert accepted). On the
/// first connect the TV shows an Allow/Deny prompt; on Allow it returns a
/// `token` we persist so later sessions skip the prompt. Older sets that expose
/// the plain `ws://{host}:8001` endpoint are supported by setting the device
/// port to 8001.
class TizenController extends RemoteController {
  TizenController({
    this.appName = 'Remote',
    this.connectTimeout = const Duration(seconds: 8),
    this.pairingTimeout = const Duration(seconds: 45),
  });

  final String appName;
  final Duration connectTimeout;

  /// How long to wait for the user to accept the on-TV Allow prompt.
  final Duration pairingTimeout;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Completer<void>? _connect;
  String? _token;

  /// RemoteKey -> Samsung key code (sent as `DataOfCmd`).
  static const Map<RemoteKey, String> keyCodes = {
    RemoteKey.power: 'KEY_POWER',
    RemoteKey.up: 'KEY_UP',
    RemoteKey.down: 'KEY_DOWN',
    RemoteKey.left: 'KEY_LEFT',
    RemoteKey.right: 'KEY_RIGHT',
    RemoteKey.ok: 'KEY_ENTER',
    RemoteKey.back: 'KEY_RETURN',
    RemoteKey.home: 'KEY_HOME',
    RemoteKey.menu: 'KEY_MENU',
    RemoteKey.volumeUp: 'KEY_VOLUP',
    RemoteKey.volumeDown: 'KEY_VOLDOWN',
    RemoteKey.mute: 'KEY_MUTE',
    RemoteKey.channelUp: 'KEY_CHUP',
    RemoteKey.channelDown: 'KEY_CHDOWN',
    RemoteKey.play: 'KEY_PLAY',
    RemoteKey.pause: 'KEY_PAUSE',
  };

  /// The JSON frame Samsung expects for a key press. Pure + exposed for tests.
  static String commandFor(RemoteKey key) => keyFrame(keyCodes[key]!);

  /// A raw `SendRemoteKey` frame for an arbitrary Samsung key code.
  static String keyFrame(String keyCode) => jsonEncode({
        'method': 'ms.remote.control',
        'params': {
          'Cmd': 'Click',
          'DataOfCmd': keyCode,
          'Option': 'false',
          'TypeOfRemote': 'SendRemoteKey',
        },
      });

  /// A `SendInputString` frame carrying base64-encoded text for the on-TV IME.
  static String inputStringFrame(String text) => jsonEncode({
        'method': 'ms.remote.control',
        'params': {
          'Cmd': base64.encode(utf8.encode(text)),
          'DataOfCmd': 'base64',
          'TypeOfRemote': 'SendInputString',
        },
      });

  /// Ordered wire frames for [text]: a `SendInputString` per printable run,
  /// plus `KEY_ENTER` / `KEY_DELETE` for edit keys. Pure + exposed for tests.
  @visibleForTesting
  static List<String> inputFrames(String text) {
    final frames = <String>[];
    for (final segment in tokenizeInput(text)) {
      switch (segment) {
        case TextRun(:final text):
          frames.add(inputStringFrame(text));
        case TextEdit(key: TextEditKey.enter):
          frames.add(keyFrame('KEY_ENTER'));
        case TextEdit(key: TextEditKey.backspace):
          frames.add(keyFrame('KEY_DELETE'));
      }
    }
    return frames;
  }

  @override
  ProtocolType get protocol => ProtocolType.tizen;

  @override
  Capabilities get capabilities => const Capabilities(
        supportsPointer: false,
        supportsTextInput: true, // SendInputString, where the model's IME allows
        channelButtons: true,
        numberPad: true,
      );

  @override
  String? get authToken => _token;

  // --- Discovery -------------------------------------------------------------

  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) {
    final seen = <String>{};
    final client = http.Client();
    final out = StreamController<Device>();

    final sub = ssdpSearch(
      searchTarget: 'urn:samsung.com:device:RemoteControlReceiver:1',
      timeout: timeout,
    ).listen(
      (resp) async {
        final host = resp.host;
        if (!seen.add(host)) return;
        final device = await _describe(client, host);
        if (!out.isClosed) out.add(device);
      },
      onError: (_) {},
      onDone: () {
        client.close();
        out.close();
      },
      cancelOnError: false,
    );
    out.onCancel = () {
      sub.cancel();
      client.close();
    };
    return out.stream;
  }

  Future<Device> _describe(http.Client client, String host) async {
    var name = 'Samsung TV ($host)';
    var id = 'tizen-$host';
    try {
      final res =
          await client.get(Uri.parse('http://$host:8001/api/v2/')).timeout(connectTimeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final device = body['device'] as Map<String, dynamic>?;
      final n = device?['name'] as String?;
      final i = device?['id'] as String?;
      if (n != null && n.trim().isNotEmpty) name = n.trim();
      if (i != null && i.trim().isNotEmpty) id = i.trim();
    } catch (_) {
      // Keep host-based fallback.
    }
    return Device(id: id, name: name, host: host, protocol: ProtocolType.tizen);
  }

  // --- Connection ------------------------------------------------------------

  @override
  Future<void> connect(Device device) async {
    emitStatus(ConnectionStatus.connecting);
    _token = device.authToken;
    final nameParam = base64.encode(utf8.encode(appName));
    final port = device.effectivePort;
    final scheme = port == 8001 ? 'ws' : 'wss';
    final tokenParam = _token == null ? '' : '&token=$_token';
    final url =
        '$scheme://${device.host}:$port/api/v2/channels/samsung.remote.control'
        '?name=$nameParam$tokenParam';

    try {
      final WebSocket socket;
      if (scheme == 'wss') {
        // Samsung TVs present a self-signed certificate.
        final httpClient = HttpClient()
          ..badCertificateCallback = (_, _, _) => true;
        socket = await WebSocket.connect(url, customClient: httpClient)
            .timeout(connectTimeout);
      } else {
        socket = await WebSocket.connect(url).timeout(connectTimeout);
      }
      _channel = IOWebSocketChannel(socket);
      final completer = Completer<void>();
      _connect = completer;
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _fail(),
        onDone: _fail,
        cancelOnError: true,
      );

      await completer.future.timeout(
        pairingTimeout,
        onTimeout: () => throw const PairingRequiredException(
          'Pairing timed out — choose Allow on your Samsung TV',
        ),
      );
      emitStatus(ConnectionStatus.connected);
    } on RemoteException {
      await _teardown();
      emitStatus(ConnectionStatus.error);
      rethrow;
    } on TimeoutException {
      await _teardown();
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException();
    } catch (_) {
      await _teardown();
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException();
    }
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (message['event']) {
      case 'ms.channel.connect':
        final token = (message['data'] as Map?)?['token'];
        if (token != null) _token = token.toString();
        _connect?.complete();
        _connect = null;
      case 'ms.channel.unauthorized':
        _connect?.completeError(const PairingRejectedException());
        _connect = null;
    }
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    final channel = _channel;
    if (channel == null) throw const RemoteException('Not connected');
    channel.sink.add(commandFor(key));
  }

  @override
  Future<void> sendText(String text) async {
    final channel = _channel;
    if (channel == null) throw const RemoteException('Not connected');
    for (final frame in inputFrames(text)) {
      channel.sink.add(frame);
    }
  }

  void _fail() {
    if (_connect != null && !_connect!.isCompleted) {
      _connect!.completeError(const ConnectionLostException());
      _connect = null;
    }
    if (status == ConnectionStatus.connected) {
      emitStatus(ConnectionStatus.error);
    }
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  Future<void> disconnect() async {
    await _teardown();
    emitStatus(ConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
