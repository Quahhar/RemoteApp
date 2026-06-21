import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SecurityContext, SocketException;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/capabilities.dart';
import '../models/connection_status.dart';
import '../models/device.dart';
import '../models/protocol_type.dart';
import '../models/remote_key.dart';
import '../persistence/vidaa_identity_store.dart';
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

  /// RemoteCA-signed client certificate + key (bundled assets). Modern VIDAA
  /// TVs demand mutual TLS — the broker drops the MQTT session unless we present
  /// this client identity, even though the TLS handshake itself tolerates none.
  static const String _certAsset = 'assets/certs/vidaa_client_cert.pem';
  static const String _keyAsset = 'assets/certs/vidaa_client_key.pem';

  /// Loaded once and reused; the cert/key are constant for all VIDAA TVs.
  static Future<SecurityContext?>? _tlsContextFuture;

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

  /// Discovery is handled centrally by the cross-protocol LAN port scan
  /// (`discoverTvsByPortScan`), which probes 36669 for us — see [kTvDiscoveryPorts].
  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) =>
      const Stream<Device>.empty();

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

  /// Reads the `result` from a TV reply as an int, or null if absent/not JSON.
  /// The firmware is inconsistent: `result` may arrive as a JSON number (`1`)
  /// or as a string (`"1"`), so we coerce both — the canonical library does the
  /// same with `int(payload["result"])`. Accepting only `int` here was silently
  /// dropping string acknowledgements, so a correct PIN looked like a failure.
  @visibleForTesting
  static int? resultFromJson(String text) {
    try {
      final obj = jsonDecode(text);
      if (obj is Map) {
        final raw = obj['result'];
        if (raw is int) return raw;
        if (raw is num) return raw.toInt();
        if (raw is String) return int.tryParse(raw.trim());
      }
    } catch (_) {}
    return null;
  }

  // --- Session lifecycle -----------------------------------------------------

  Future<void> _openSession(Device device) async {
    final mac = await identity.ensure();
    _deviceTopic = deviceTopicFor(mac);
    final host = device.host;
    final port = device.port ?? ProtocolType.vidaa.defaultPort;
    final tls = await _clientTlsContext();

    // Firmware varies: most speak MQTT 3.1.1, some only the older 3.1. Try the
    // common one first, then fall back before giving up.
    MqttServerClient? connected;
    Object? lastError;
    MqttClientConnectionStatus? lastStatus;
    var timedOut = false;

    for (final useV311 in const [true, false]) {
      final client = _buildClient(host, port, useV311: useV311, tls: tls);
      try {
        await client.connect().timeout(connectTimeout);
      } on TimeoutException {
        timedOut = true;
        lastStatus = client.connectionStatus;
        client.disconnect();
        continue;
      } catch (e) {
        lastError = e;
        lastStatus = client.connectionStatus;
        if (kDebugMode) {
          debugPrint('[Hisense] connect $host (v311=$useV311) failed: $e '
              'status=${client.connectionStatus}');
        }
        client.disconnect();
        continue;
      }
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        connected = client;
        break;
      }
      lastStatus = client.connectionStatus;
      if (kDebugMode) {
        debugPrint('[Hisense] $host (v311=$useV311) not connected: '
            'state=${lastStatus?.state} returnCode=${lastStatus?.returnCode}');
      }
      client.disconnect();
    }

    if (connected == null) {
      // Prefer the broker's own rejection reason (CONNACK code) when it gave
      // one; otherwise classify the socket/TLS error or report the timeout.
      if (_hasMeaningfulCode(lastStatus)) {
        throw NotReachableException(_describeStatus(lastStatus));
      }
      if (timedOut) {
        throw const NotReachableException(
          'The TV did not answer on port 36669 — make sure it is on and on the '
          'same Wi-Fi network.',
        );
      }
      throw NotReachableException(_describeConnectError(lastError));
    }

    _client = connected;
    connected.subscribe(mobileSubscription(_deviceTopic!), MqttQos.atMostOnce);
    _updates = connected.updates?.listen(_onMessages);
  }

  MqttServerClient _buildClient(
    String host,
    int port, {
    required bool useV311,
    SecurityContext? tls,
  }) {
    // No '/' or other special chars — some Hisense brokers reject such IDs.
    final clientId = 'remoteapp-${_randomHex(8)}';
    final client = _clientFactory(host, port, clientId)
      ..secure = true
      ..onBadCertificate = ((cert) => true)
      ..keepAlivePeriod = 60
      ..logging(on: kDebugMode)
      ..connectionMessage = (MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(username, password)
          .startClean());
    // Present our client cert for the TV's mutual-TLS broker (when available).
    if (tls != null) client.securityContext = tls;
    if (useV311) {
      client.setProtocolV311();
    } else {
      client.setProtocolV31();
    }
    return client;
  }

  /// Loads the bundled RemoteCA client cert/key into a [SecurityContext] for
  /// mutual TLS, once. Returns null (and we connect without a client cert) if
  /// the assets can't be read, so non-mutual-TLS firmware still works.
  Future<SecurityContext?> _clientTlsContext() {
    return _tlsContextFuture ??= () async {
      try {
        final cert = await rootBundle.load(_certAsset);
        final key = await rootBundle.load(_keyAsset);
        return SecurityContext(withTrustedRoots: false)
          ..useCertificateChainBytes(cert.buffer.asUint8List())
          ..usePrivateKeyBytes(key.buffer.asUint8List());
      } catch (e) {
        if (kDebugMode) debugPrint('[Hisense] client cert load failed: $e');
        return null;
      }
    }();
  }

  /// True when the broker actually returned a CONNACK rejection code (so we can
  /// report a precise reason) rather than a generic/absent one.
  static bool _hasMeaningfulCode(MqttClientConnectionStatus? status) {
    final rc = status?.returnCode;
    return rc != null &&
        rc != MqttConnectReturnCode.connectionAccepted &&
        rc != MqttConnectReturnCode.noneSpecified;
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final message = event.payload;
      if (message is! MqttPublishMessage) continue;
      final text =
          MqttPublishPayload.bytesToStringAsString(message.payload.message);
      if (kDebugMode) debugPrint('[Hisense] <= ${event.topic}: $text');
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

  /// Friendly, specific reason for a failed TLS/socket connect — surfaced in the
  /// UI snackbar so a live test points straight at the cause.
  static String _describeConnectError(Object? e) {
    if (e is HandshakeException) {
      return 'The TV refused the secure connection (TLS handshake failed).';
    }
    if (e is SocketException) {
      return 'Could not reach the TV — connection refused or no route to it.';
    }
    return 'Could not open a remote session with the TV.';
  }

  /// Friendly reason when the socket connected but the MQTT login was rejected.
  /// The raw CONNACK code is appended so a live test can tell us exactly which
  /// rejection it is (e.g. notAuthorized = wrong credentials for this firmware).
  static String _describeStatus(MqttClientConnectionStatus? status) {
    final rc = status?.returnCode;
    final reason = switch (rc) {
      MqttConnectReturnCode.notAuthorized ||
      MqttConnectReturnCode.badUsernameOrPassword =>
        'The TV rejected the remote sign-in',
      MqttConnectReturnCode.identifierRejected =>
        'The TV rejected this client — try again',
      MqttConnectReturnCode.brokerUnavailable =>
        'The TV’s remote service is unavailable right now',
      _ => 'Could not open a remote session with the TV',
    };
    return rc == null ? '$reason.' : '$reason (code: ${rc.name}).';
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
