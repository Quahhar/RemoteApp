import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/capabilities.dart';
import '../models/connection_status.dart';
import '../models/device.dart';
import '../models/protocol_type.dart';
import '../models/remote_key.dart';
import '../persistence/vidaa_identity_store.dart';
import 'lan_scan.dart';
import 'remote_controller.dart';

/// Hisense / VIDAA TVs (and rebrands such as "Kenstar") via their MQTT-over-TLS
/// remote service on port 36669.
///
/// One TLS MQTT session does everything:
///  - pairing: [beginPairing] connects and asks for TV state, which makes the TV
///    show a 4-digit code; [completePairing] submits the code and waits for the
///    `result == 1` acknowledgement.
///  - control: [connect] re-opens the session (the TV remembers our identity)
///    and [sendKey] publishes `KEY_*` strings to the sendkey topic.
///
/// The client identity (a stable per-install pseudo-MAC → `device_topic`) lives
/// app-globally in [VidaaIdentityStore]; a [Device] is "paired" once its
/// [Device.authToken] is the [pairedMarker].
class HisenseController extends RemoteController {
  HisenseController({
    required this.identity,
    this.connectTimeout = const Duration(seconds: 8),
    MqttServerClient Function(String host, int port, String clientId)?
        clientFactory,
  }) : _clientFactory = clientFactory ?? _defaultClientFactory;

  final VidaaIdentityStore identity;
  final Duration connectTimeout;
  final MqttServerClient Function(String, int, String) _clientFactory;

  /// Well-known credentials the VIDAA broker expects from a remote client.
  static const String username = 'hisenseservice';
  static const String password = 'multimqttservice';
  static const String pairedMarker = 'paired';

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;
  String? _deviceTopic;
  String? _credential;
  Completer<bool>? _authResult;

  /// RemoteKey -> VIDAA key name. Every [RemoteKey] is mapped (verified by unit
  /// tests). Note `back` -> `KEY_RETURNS` (VIDAA's navigation back; `KEY_BACK`
  /// is media-rewind), and `menu` -> `KEY_MENU`.
  static const Map<RemoteKey, String> keyNames = {
    RemoteKey.power: 'KEY_POWER',
    RemoteKey.up: 'KEY_UP',
    RemoteKey.down: 'KEY_DOWN',
    RemoteKey.left: 'KEY_LEFT',
    RemoteKey.right: 'KEY_RIGHT',
    RemoteKey.ok: 'KEY_OK',
    RemoteKey.back: 'KEY_RETURNS',
    RemoteKey.home: 'KEY_HOME',
    RemoteKey.menu: 'KEY_MENU',
    RemoteKey.volumeUp: 'KEY_VOLUMEUP',
    RemoteKey.volumeDown: 'KEY_VOLUMEDOWN',
    RemoteKey.mute: 'KEY_MUTE',
    RemoteKey.channelUp: 'KEY_CHANNELUP',
    RemoteKey.channelDown: 'KEY_CHANNELDOWN',
    RemoteKey.play: 'KEY_PLAY',
    RemoteKey.pause: 'KEY_PAUSE',
  };

  @override
  ProtocolType get protocol => ProtocolType.vidaa;

  @override
  Capabilities get capabilities => const Capabilities(
        supportsPointer: false, // key-based remote, no pointer
        supportsTextInput: false, // no documented text channel
        channelButtons: true,
        numberPad: true,
        requiresPairingCode: true, // 4-digit on-screen code
      );

  @override
  String? get authToken => _credential;

  // --- Discovery: any host with 36669 open is a VIDAA TV. --------------------

  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) =>
      scanSubnetForOpenPort(ProtocolType.vidaa.defaultPort, timeout: timeout)
          .map(
        (host) => Device(
          id: 'vidaa-$host',
          name: 'Hisense / VIDAA TV ($host)',
          host: host,
          protocol: ProtocolType.vidaa,
        ),
      );

  // --- Topic helpers (pure; exposed for unit tests) --------------------------

  @visibleForTesting
  static String deviceTopicFor(String mac) => '$mac\$normal';

  @visibleForTesting
  static String keyTopic(String deviceTopic) =>
      '/remoteapp/tv/remote_service/$deviceTopic/actions/sendkey';

  @visibleForTesting
  static String authCodeTopic(String deviceTopic) =>
      '/remoteapp/tv/ui_service/$deviceTopic/actions/authenticationcode';

  @visibleForTesting
  static String stateTopic(String deviceTopic) =>
      '/remoteapp/tv/ui_service/$deviceTopic/actions/gettvstate';

  @visibleForTesting
  static String mobileSubscription(String deviceTopic) =>
      '/remoteapp/mobile/$deviceTopic/#';

  @visibleForTesting
  static String authCodePayload(String code) =>
      jsonEncode({'authNum': code.trim()});

  /// Reads the `result` integer from a TV reply, or null if absent/not JSON.
  @visibleForTesting
  static int? resultFromJson(String text) {
    try {
      final obj = jsonDecode(text);
      if (obj is Map && obj['result'] is int) return obj['result'] as int;
    } catch (_) {}
    return null;
  }

  // --- Session lifecycle -----------------------------------------------------

  Future<void> _openSession(Device device) async {
    final mac = await identity.ensure();
    _deviceTopic = deviceTopicFor(mac);
    final clientId = 'RemoteApp/${_randomHex(8)}';
    final client = _clientFactory(
      device.host,
      device.port ?? ProtocolType.vidaa.defaultPort,
      clientId,
    )
      ..secure = true
      ..onBadCertificate = ((cert) => true)
      ..keepAlivePeriod = 60
      ..setProtocolV311()
      ..logging(on: false)
      ..connectionMessage = (MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(username, password)
          .startClean());

    try {
      await client.connect().timeout(connectTimeout);
    } catch (_) {
      client.disconnect();
      throw const NotReachableException();
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw const NotReachableException();
    }
    _client = client;
    client.subscribe(mobileSubscription(_deviceTopic!), MqttQos.atMostOnce);
    _updates = client.updates?.listen(_onMessages);
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final message = event.payload;
      if (message is! MqttPublishMessage) continue;
      final text =
          MqttPublishPayload.bytesToStringAsString(message.payload.message);
      final result = resultFromJson(text);
      if (result != null && _authResult != null && !_authResult!.isCompleted) {
        _authResult!.complete(result == 1);
      }
    }
  }

  void _publish(String topic, String payload) {
    final client = _client;
    if (client == null) return;
    final builder = MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
  }

  // --- Pairing ---------------------------------------------------------------

  @override
  Future<void> beginPairing(Device device) async {
    emitStatus(ConnectionStatus.connecting);
    try {
      await _openSession(device);
    } catch (_) {
      emitStatus(ConnectionStatus.error);
      rethrow;
    }
    // Touching ui_service on an unauthorized client makes the TV show the code.
    _publish(stateTopic(_deviceTopic!), '');
  }

  @override
  Future<void> completePairing(String code) async {
    if (_client == null || _deviceTopic == null) {
      throw const PairingRequiredException('Start pairing first');
    }
    _authResult = Completer<bool>();
    _publish(authCodeTopic(_deviceTopic!), authCodePayload(code));

    bool ok;
    try {
      ok = await _authResult!.future.timeout(connectTimeout);
    } catch (_) {
      await _closeSession();
      emitStatus(ConnectionStatus.error);
      throw const PairingRejectedException('TV did not confirm the code');
    } finally {
      _authResult = null;
    }
    if (!ok) {
      await _closeSession();
      emitStatus(ConnectionStatus.error);
      throw const PairingRejectedException("That code didn't match — try again");
    }
    _credential = pairedMarker;
    await _closeSession();
    emitStatus(ConnectionStatus.disconnected);
  }

  // --- Control ---------------------------------------------------------------

  @override
  Future<void> connect(Device device) async {
    if (device.authToken != pairedMarker) {
      emitStatus(ConnectionStatus.error);
      throw const PairingRequiredException();
    }
    emitStatus(ConnectionStatus.connecting);
    try {
      await _openSession(device);
    } catch (_) {
      emitStatus(ConnectionStatus.error);
      rethrow;
    }
    _credential = pairedMarker;
    emitStatus(ConnectionStatus.connected);
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (_client == null || _deviceTopic == null) {
      throw const RemoteException('Hisense TV is not connected');
    }
    final name = keyNames[key];
    if (name == null) {
      throw RemoteException('Unsupported key: ${key.name}');
    }
    _publish(keyTopic(_deviceTopic!), name);
  }

  @override
  Future<void> disconnect() async {
    await _closeSession();
    emitStatus(ConnectionStatus.disconnected);
  }

  Future<void> _closeSession() async {
    await _updates?.cancel();
    _updates = null;
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
  }

  @override
  void dispose() {
    _closeSession();
    super.dispose();
  }

  static String _randomHex(int bytes) {
    final r = Random();
    final sb = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      sb.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static MqttServerClient _defaultClientFactory(
    String host,
    int port,
    String clientId,
  ) =>
      MqttServerClient.withPort(host, clientId, port);
}
