import 'dart:async';
import 'dart:convert';

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

/// LG webOS via SSAP over WebSocket (`ws://{host}:3000`).
///
/// Pairing: send a `register` request; on the first pairing the TV shows an
/// on-screen prompt and, once accepted, returns a `client-key` we persist so
/// later sessions reconnect silently. Buttons (D-pad/nav/transport) and the
/// Magic-Remote pointer go through the secondary "pointer input socket"; power
/// uses the SSAP `system/turnOff` request.
class WebosController extends RemoteController {
  WebosController({
    this.connectTimeout = const Duration(seconds: 8),
    this.pairingTimeout = const Duration(seconds: 45),
  });

  final Duration connectTimeout;

  /// How long to wait for the user to accept the on-TV pairing prompt.
  final Duration pairingTimeout;

  WebSocketChannel? _main;
  WebSocketChannel? _input;
  StreamSubscription<dynamic>? _mainSub;
  String? _clientKey;
  int _msgId = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  /// RemoteKey -> webOS input-socket button name. `power` is listed for
  /// completeness but is actually sent via SSAP `system/turnOff`.
  static const Map<RemoteKey, String> buttonNames = {
    RemoteKey.power: 'POWER',
    RemoteKey.up: 'UP',
    RemoteKey.down: 'DOWN',
    RemoteKey.left: 'LEFT',
    RemoteKey.right: 'RIGHT',
    RemoteKey.ok: 'ENTER',
    RemoteKey.back: 'BACK',
    RemoteKey.home: 'HOME',
    RemoteKey.menu: 'MENU',
    RemoteKey.volumeUp: 'VOLUMEUP',
    RemoteKey.volumeDown: 'VOLUMEDOWN',
    RemoteKey.mute: 'MUTE',
    RemoteKey.channelUp: 'CHANNELUP',
    RemoteKey.channelDown: 'CHANNELDOWN',
    RemoteKey.play: 'PLAY',
    RemoteKey.pause: 'PAUSE',
  };

  static const List<String> _permissions = [
    'LAUNCH', 'LAUNCH_WEBAPP', 'APP_TO_APP', 'CLOSE',
    'CONTROL_AUDIO', 'CONTROL_DISPLAY', 'CONTROL_INPUT_JOYSTICK',
    'CONTROL_INPUT_MEDIA_RECORDING', 'CONTROL_INPUT_MEDIA_PLAYBACK',
    'CONTROL_INPUT_TV', 'CONTROL_POWER', 'CONTROL_INPUT_TEXT',
    'CONTROL_MOUSE_AND_KEYBOARD', 'READ_APP_STATUS', 'READ_CURRENT_CHANNEL',
    'READ_INPUT_DEVICE_LIST', 'READ_NETWORK_STATE', 'READ_RUNNING_APPS',
    'READ_TV_CHANNEL_LIST', 'WRITE_NOTIFICATION_TOAST', 'READ_POWER_STATE',
    'READ_COUNTRY_INFO',
  ];

  @override
  ProtocolType get protocol => ProtocolType.webos;

  @override
  Capabilities get capabilities => const Capabilities(
        supportsPointer: true, // Magic Remote pointer via the input socket
        supportsTextInput: true, // webOS IME requests
        channelButtons: true,
        numberPad: true,
      );

  @override
  String? get authToken => _clientKey;

  // --- Discovery -------------------------------------------------------------

  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) {
    final seen = <String>{};
    final client = http.Client();
    final controller = StreamController<Device>();

    final sub = ssdpSearch(
      searchTarget: 'urn:lge-com:service:webos-second-screen:1',
      timeout: timeout,
    ).listen(
      (resp) async {
        final host = resp.host;
        if (!seen.add(host)) return;
        final device = await _describe(client, host, resp.header('LOCATION'));
        if (!controller.isClosed) controller.add(device);
      },
      onError: (_) {},
      onDone: () {
        client.close();
        controller.close();
      },
      cancelOnError: false,
    );
    controller.onCancel = () {
      sub.cancel();
      client.close();
    };
    return controller.stream;
  }

  Future<Device> _describe(http.Client client, String host, String? location) async {
    var name = 'LG webOS ($host)';
    var id = 'webos-$host';
    if (location != null) {
      try {
        final res = await client.get(Uri.parse(location)).timeout(connectTimeout);
        final friendly = _xmlTag(res.body, 'friendlyName');
        final udn = _xmlTag(res.body, 'UDN');
        if (friendly != null && friendly.trim().isNotEmpty) name = friendly.trim();
        if (udn != null && udn.trim().isNotEmpty) id = udn.trim();
      } catch (_) {
        // Keep host-based fallback.
      }
    }
    return Device(id: id, name: name, host: host, protocol: ProtocolType.webos);
  }

  static String? _xmlTag(String xml, String tag) => RegExp(
        '<$tag[^>]*>(.*?)</$tag>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(xml)?.group(1);

  // --- Connection ------------------------------------------------------------

  @override
  Future<void> connect(Device device) async {
    emitStatus(ConnectionStatus.connecting);
    _clientKey = device.authToken;
    try {
      final url = 'ws://${device.host}:${device.effectivePort}';
      final channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        connectTimeout: connectTimeout,
      );
      _main = channel;
      _mainSub = channel.stream.listen(
        _onMainMessage,
        onError: (_) => _fail(),
        onDone: _fail,
        cancelOnError: true,
      );

      await _register();
      await _openInputSocket();
      emitStatus(ConnectionStatus.connected);
    } on RemoteException {
      await _teardown();
      emitStatus(ConnectionStatus.error);
      rethrow;
    } catch (_) {
      await _teardown();
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException();
    }
  }

  Future<void> _register() async {
    final completer = Completer<Map<String, dynamic>>();
    _pending['register'] = completer;
    _send(_main!, {
      'type': 'register',
      'id': 'register',
      'payload': {
        'forcePairing': false,
        'pairingType': 'PROMPT',
        if (_clientKey != null) 'client-key': _clientKey,
        'manifest': {
          'manifestVersion': 1,
          'appVersion': '1.1',
          'permissions': _permissions,
        },
      },
    });

    final response = await completer.future.timeout(
      pairingTimeout,
      onTimeout: () => throw const PairingRequiredException(
        'Pairing timed out — accept the prompt on your LG TV',
      ),
    );
    final type = response['type'];
    if (type == 'error') {
      throw const PairingRejectedException();
    }
    final key = (response['payload'] as Map?)?['client-key'] as String?;
    if (key != null) _clientKey = key;
  }

  Future<void> _openInputSocket() async {
    final response = await _request(
      'ssap://com.webos.service.networkinput/getPointerInputSocket',
    );
    final path = (response['payload'] as Map?)?['socketPath'] as String?;
    if (path == null) return; // pointer optional; buttons still work via SSAP
    _input = IOWebSocketChannel.connect(
      Uri.parse(path),
      connectTimeout: connectTimeout,
    );
  }

  void _onMainMessage(dynamic raw) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    // The register flow may emit an interim "response" (prompt) then a final
    // "registered"; only complete on the terminal message.
    final id = message['id'] as String?;
    final type = message['type'] as String?;
    if (id == 'register' && type == 'response') return; // still waiting
    if (id != null && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(message);
    }
  }

  // --- Control ---------------------------------------------------------------

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (_main == null) throw const RemoteException('Not connected');
    if (key == RemoteKey.power) {
      await _request('ssap://system/turnOff');
      return;
    }
    final input = _input;
    if (input == null) {
      throw const RemoteException('Pointer input socket unavailable');
    }
    input.sink.add('type:button\nname:${buttonNames[key]}\n\n');
  }

  @override
  Future<void> movePointer(double dx, double dy) async {
    final input = _input;
    if (input == null) throw const RemoteException('Pointer unavailable');
    input.sink.add(
      'type:move\ndx:${dx.round()}\ndy:${dy.round()}\ndown:0\n\n',
    );
  }

  @override
  Future<void> click() async {
    final input = _input;
    if (input == null) throw const RemoteException('Pointer unavailable');
    input.sink.add('type:click\n\n');
  }

  @override
  Future<void> sendText(String text) async {
    if (_main == null) throw const RemoteException('Not connected');
    for (final req in imeRequests(text)) {
      await _request(req.uri, payload: req.payload);
    }
  }

  /// The ordered webOS IME requests for [text]: one `insertText` per printable
  /// run (batched), plus `sendEnterKey` / `deleteCharacters` for edit keys.
  /// Pure + exposed for unit tests.
  @visibleForTesting
  static List<({String uri, Map<String, dynamic>? payload})> imeRequests(
    String text,
  ) {
    final requests = <({String uri, Map<String, dynamic>? payload})>[];
    for (final segment in tokenizeInput(text)) {
      switch (segment) {
        case TextRun(:final text):
          requests.add((
            uri: 'ssap://com.webos.service.ime/insertText',
            payload: {'text': text, 'replace': 0},
          ));
        case TextEdit(key: TextEditKey.enter):
          requests.add((
            uri: 'ssap://com.webos.service.ime/sendEnterKey',
            payload: null,
          ));
        case TextEdit(key: TextEditKey.backspace):
          requests.add((
            uri: 'ssap://com.webos.service.ime/deleteCharacters',
            payload: {'count': 1},
          ));
      }
    }
    return requests;
  }

  Future<Map<String, dynamic>> _request(
    String uri, {
    Map<String, dynamic>? payload,
  }) async {
    final id = 'req_${_msgId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send(_main!, {
      'type': 'request',
      'id': id,
      'uri': uri,
      'payload': ?payload,
    });
    return completer.future.timeout(
      connectTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw const NotReachableException();
      },
    );
  }

  void _send(WebSocketChannel channel, Map<String, dynamic> message) {
    channel.sink.add(jsonEncode(message));
  }

  void _fail() {
    if (status == ConnectionStatus.connected) {
      emitStatus(ConnectionStatus.error);
    }
  }

  Future<void> _teardown() async {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(const ConnectionLostException());
    }
    _pending.clear();
    await _mainSub?.cancel();
    _mainSub = null;
    await _input?.sink.close();
    await _main?.sink.close();
    _input = null;
    _main = null;
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
