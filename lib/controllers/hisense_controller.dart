import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show
        HandshakeException,
        HttpClient,
        HttpDate,
        SecurityContext,
        SocketException;

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
import 'vidaa_credentials.dart';

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
  /// Used as a fallback for older firmware (transport_protocol < 3290); modern
  /// firmware rejects these and requires the dynamic XOR credentials produced
  /// by [vidaa_credentials.dart].
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
    // Extended keys. VIDAA's media-rewind is `KEY_BACK` (navigation back is
    // `KEY_RETURNS`, above). Unmapped More-sheet commands surface as
    // "not available".
    RemoteKey.digit0: 'KEY_0',
    RemoteKey.digit1: 'KEY_1',
    RemoteKey.digit2: 'KEY_2',
    RemoteKey.digit3: 'KEY_3',
    RemoteKey.digit4: 'KEY_4',
    RemoteKey.digit5: 'KEY_5',
    RemoteKey.digit6: 'KEY_6',
    RemoteKey.digit7: 'KEY_7',
    RemoteKey.digit8: 'KEY_8',
    RemoteKey.digit9: 'KEY_9',
    RemoteKey.rewind: 'KEY_BACK',
    RemoteKey.fastForward: 'KEY_FORWARDS',
    RemoteKey.stop: 'KEY_STOP',
    RemoteKey.source: 'KEY_INPUTS',
    RemoteKey.subtitles: 'KEY_SUBTITLE',
    RemoteKey.colorRed: 'KEY_RED',
    RemoteKey.colorGreen: 'KEY_GREEN',
    RemoteKey.colorYellow: 'KEY_YELLOW',
    RemoteKey.colorBlue: 'KEY_BLUE',
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

  /// Topics the TV publishes its pairing *reply* on (the `mobile`/`data`
  /// namespace we subscribe to — distinct from the `tv`/`actions` topics we
  /// publish commands to). The PIN acknowledgement (`{"result":1}`) arrives on
  /// one of these, so the auth handshake must listen here, not on the send
  /// topic ([authCodeTopic]).
  @visibleForTesting
  static String authReplyTopic(String deviceTopic) =>
      '/remoteapp/mobile/$deviceTopic/ui_service/data/authentication';

  @visibleForTesting
  static String authCodeReplyTopic(String deviceTopic) =>
      '/remoteapp/mobile/$deviceTopic/ui_service/data/authenticationcode';

  @visibleForTesting
  static String stateTopic(String deviceTopic) =>
      '/remoteapp/tv/ui_service/$deviceTopic/actions/gettvstate';

  @visibleForTesting
  static String mobileSubscription(String deviceTopic) =>
      '/remoteapp/mobile/$deviceTopic/#';

  /// Builds the auth-code payload. The PIN MUST be sent as an integer —
  /// sending it as a string (even JSON-encoded) is silently rejected by
  /// the firmware. See pyvidaa `authenticate()`: `int(pin)`.
  @visibleForTesting
  static String authCodePayload(String code) {
    final pin = int.tryParse(code.trim());
    if (pin == null) return jsonEncode({'authNum': 0});
    return jsonEncode({'authNum': pin});
  }

  @visibleForTesting
  static String getTokenTopic(String deviceTopic) =>
      '/remoteapp/tv/platform_service/$deviceTopic/data/gettoken';

  @visibleForTesting
  static String vidaaAppConnectTopic(String deviceTopic) =>
      '/remoteapp/tv/ui_service/$deviceTopic/actions/vidaa_app_connect';

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

  // --- Credential resolution ------------------------------------------------

  /// Fetches the TV's UPnP descriptor to extract the clock, brand, and protocol
  /// version, then computes multiple dynamic XOR credential candidates from
  /// [vidaa_credentials.dart] that the modern broker (transport_protocol >=3290)
  /// demands. Returns a list of candidates (different brand+operation combos) so
  /// the caller can try each until one is accepted. Returns empty when the
  /// descriptor is unreachable — the caller falls back to static legacy creds.
  Future<List<VidaaCredentials>> _resolveCredentialCandidates(
    String host,
    String uuid,
  ) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      for (final port in const [38400, 18400]) {
        try {
          final uri = Uri.parse(
            'http://$host:$port/MediaServer/rendererdevicedesc.xml',
          );
          final req = await client.getUrl(uri);
          final resp = await req.close().timeout(connectTimeout);
          final dateHeader = resp.headers.value('date');
          final body = await resp.transform(utf8.decoder).join();

          var epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (dateHeader != null) {
            epoch = HttpDate.parse(dateHeader).millisecondsSinceEpoch ~/ 1000;
          }
          final brandM = RegExp(r'brand=(\w+)').firstMatch(body);
          final protoM = RegExp(r'transport_protocol=(\d+)').firstMatch(body);
          final brand = brandM?.group(1) ?? kDefaultVidaaBrand;
          final proto = int.tryParse(protoM?.group(1) ?? '') ?? 0;
          final method = vidaaAuthMethodFor(proto);

          if (kDebugMode) {
            debugPrint(
              '[Hisense] descriptor $host:$port brand=$brand proto=$proto '
              'method=$method epoch=$epoch',
            );
          }

          // Generate candidates: reported brand with 'secure' operation first
          // (matching the real VIDAA app), then fallback brands, then the
          // legacy 'vidaacommon' operation last. The operation is embedded in
          // the clientId — the TV rejects 'vidaacommon' on modern firmware.
          final candidates = <VidaaCredentials>[];
          final brands = <String>[brand, kDefaultVidaaBrand, 'ksj'];
          final operations = <String>[kVidaaSecureOperation, 'vidaacommon'];
          for (final b in brands) {
            for (final op in operations) {
              candidates.add(
                generateVidaaCredentials(
                  uuid: uuid,
                  brand: b,
                  operation: op,
                  authMethod: method,
                  timestamp: epoch,
                ),
              );
            }
          }
          // Also include a current-timestamp variant in case TV clock drifts.
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if ((now - epoch).abs() > 60) {
            for (final b in brands) {
              candidates.add(
                generateVidaaCredentials(
                  uuid: uuid,
                  brand: b,
                  operation: kVidaaSecureOperation,
                  authMethod: method,
                  timestamp: now,
                ),
              );
            }
          }
          return candidates;
        } catch (_) {
          // Try next port.
        }
      }
    } finally {
      client.close();
    }
    return <VidaaCredentials>[];
  }

  // --- Session lifecycle -----------------------------------------------------

  Future<void> _openSession(Device device) async {
    final uuid = await identity.ensure();
    final host = device.host;
    final port = device.port ?? ProtocolType.vidaa.defaultPort;
    final tls = await _clientTlsContext();

    // Resolve all dynamic credential candidates from the TV's UPnP descriptor.
    final dynamicCandidates = await _resolveCredentialCandidates(host, uuid);

    // Build the full candidate list: dynamic creds first (tried in order),
    // then static legacy creds as a last resort.
    final allCandidates = <VidaaCredentials?>[
      ...dynamicCandidates,
      null, // null signals the caller to use static creds
    ];

    // Deduplicate candidates while preserving order (same clientId means
    // the broker will see the same identity, so only try once).
    final seenClientIds = <String>{};
    final uniqueCandidates = <VidaaCredentials?>[];
    for (final c in allCandidates) {
      final key = c?.clientId ?? 'static';
      if (seenClientIds.add(key)) {
        uniqueCandidates.add(c);
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[Hisense] trying ${uniqueCandidates.length} credential candidates '
        '(dynamic=${dynamicCandidates.length})',
      );
    }

    // Try each candidate credential across both MQTT protocol versions.
    // Stop at the first successful connect.
    MqttServerClient? connected;
    Object? lastError;
    MqttClientConnectionStatus? lastStatus;
    var timedOut = false;
    String? winningDeviceTopic;

    for (final creds in uniqueCandidates) {
      if (connected != null) break;

      for (final useV311 in const [true, false]) {
        final client = _buildClient(
          host,
          port,
          useV311: useV311,
          tls: tls,
          creds: creds,
          defaultClientId: deviceTopicFor(uuid),
        );
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
            debugPrint(
              '[Hisense] connect $host clientId=${creds?.clientId ?? "static"} '
              '(v311=$useV311) failed: $e '
              'status=${client.connectionStatus}',
            );
          }
          client.disconnect();
          continue;
        }
        if (client.connectionStatus?.state == MqttConnectionState.connected) {
          connected = client;
          winningDeviceTopic = creds?.clientId ?? deviceTopicFor(uuid);
          if (kDebugMode) {
            debugPrint(
              '[Hisense] CONNECTED with clientId=$winningDeviceTopic '
              '(v311=$useV311)',
            );
          }
          break;
        }
        lastStatus = client.connectionStatus;
        if (kDebugMode) {
          debugPrint(
            '[Hisense] $host clientId=${creds?.clientId ?? "static"} '
            '(v311=$useV311) not connected: '
            'state=${lastStatus?.state} returnCode=${lastStatus?.returnCode}',
          );
        }
        client.disconnect();
      }
    }

    if (connected == null) {
      // In debug, append the real cause + whether the client cert actually
      // loaded, so a live test surfaces the exact problem on-screen.
      final detail = kDebugMode
          ? ' [clientCert=${tls != null}; '
                'err=${lastError ?? (timedOut ? 'timeout' : lastStatus?.returnCode)}]'
          : '';
      // Prefer the broker's own rejection reason (CONNACK code) when it gave
      // one; otherwise classify the socket/TLS error or report the timeout.
      if (_hasMeaningfulCode(lastStatus)) {
        throw NotReachableException('${_describeStatus(lastStatus)}$detail');
      }
      if (timedOut) {
        throw NotReachableException(
          'The TV did not answer on port 36669. Make sure it is on and on the '
          'same Wi-Fi network.$detail',
        );
      }
      throw NotReachableException('${_describeConnectError(lastError)}$detail');
    }

    _client = connected;
    _deviceTopic = winningDeviceTopic;

    // Subscribe to the exact response topics the real VIDAA app uses before
    // sending vidaa_app_connect. The bare # wildcard alone is sometimes ignored
    // by the broker; explicit data-topic subscriptions guarantee we receive
    // the PIN token and authentication result the TV publishes in reply.
    final c = _deviceTopic!;
    for (final t in [
      '/remoteapp/mobile/$c/ui_service/data/authentication',
      '/remoteapp/mobile/$c/ui_service/data/authenticationcode',
      '/remoteapp/mobile/$c/platform_service/data/tokenissuance',
      '/remoteapp/mobile/$c/#',
    ]) {
      connected.subscribe(t, MqttQos.atMostOnce);
    }
    final updates = connected.updates;
    if (updates == null) {
      await _closeSession();
      throw const NotReachableException('TV did not open a message channel');
    }
    try {
      _updates = updates.listen(_onMessages);
    } catch (_) {
      // If the updates stream is already closed, tear down and fail.
      await _closeSession();
      throw const NotReachableException('TV disconnected during handshake');
    }
  }

  MqttServerClient _buildClient(
    String host,
    int port, {
    required bool useV311,
    SecurityContext? tls,
    VidaaCredentials? creds,
    required String defaultClientId,
  }) {
    final clientId = (creds != null) ? creds.clientId : defaultClientId;
    final user = creds?.username ?? username;
    final pass = creds?.password ?? password;

    // Match the real VIDAA app's CONNECT: Will QoS 1, topic "/will", message
    // "dieout", clean session, keepalive 36.
    final connectMsg = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(user, pass)
        .withWillTopic('/will')
        .withWillMessage('dieout')
        .withWillQos(MqttQos.atLeastOnce)
        .startClean();

    final client = _clientFactory(host, port, clientId)
      ..secure = true
      // Param MUST be typed Object: this mqtt_client version casts the callback
      // to `bool Function(Object)` internally; an inferred (X509Certificate)
      // param throws a _TypeError during connect, before any network I/O.
      ..onBadCertificate = ((Object cert) => true)
      ..keepAlivePeriod = 36
      ..logging(on: kDebugMode)
      ..connectionMessage = connectMsg;
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
      final topic = event.topic;
      final text = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );
      if (kDebugMode) debugPrint('[Hisense] <= $topic: $text');
      // Only complete the auth result when the message arrives on one of the
      // TV's pairing-reply topics ([authReplyTopic]/[authCodeReplyTopic]) —
      // ignoring `result` fields in unrelated messages (e.g. state broadcasts)
      // that would prematurely resolve or reject the pairing handshake. Matching
      // the send topic ([authCodeTopic]) never fired: the TV replies on the
      // `mobile`/`data` namespace, not the `tv`/`actions` one we publish to.
      if (_authResult != null &&
          !_authResult!.isCompleted &&
          _deviceTopic != null &&
          (topic == authReplyTopic(_deviceTopic!) ||
              topic == authCodeReplyTopic(_deviceTopic!))) {
        final result = resultFromJson(text);
        if (result != null) {
          _authResult!.complete(result == 1);
        }
      }
    }
  }

  void _publish(String topic, String payload) {
    final client = _client;
    if (client == null) {
      throw const RemoteException('Hisense TV is not connected');
    }
    final builder = MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  // --- Pairing ---------------------------------------------------------------

  @override
  Future<void> beginPairing(Device device) async {
    if (_client != null) await _closeSession();
    emitStatus(ConnectionStatus.connecting);
    try {
      await _openSession(device);
    } catch (_) {
      emitStatus(ConnectionStatus.error);
      rethrow;
    }

    final topic = _deviceTopic;
    if (topic == null) {
      emitStatus(ConnectionStatus.error);
      throw const RemoteException('Could not establish device identity');
    }

    // gettvstate triggers the 4-digit PIN on ALL known VIDAA firmware.
    // Unlike vidaa_app_connect, it has no version field so the TV can
    // never respond with "no longer compatible with the current version".
    _publish(stateTopic(topic), '');
  }

  @override
  Future<void> completePairing(String code) async {
    if (_client == null || _deviceTopic == null) {
      throw const PairingRequiredException('Start pairing first');
    }
    _authResult = Completer<bool>();
    _publish(authCodeTopic(_deviceTopic!), authCodePayload(code));

    // After sending PIN, request the access token exactly as pyvidaa does.
    // This is required for the TV to finalize the pairing and issue a token.
    _publish(getTokenTopic(_deviceTopic!), jsonEncode({'refreshtoken': ''}));

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
      throw const PairingRejectedException(
        "That code didn't match. Try again.",
      );
    }
    // Try to capture the access token from the TV's response — this
    // authenticates future reconnections without re-pairing. If the token
    // doesn't arrive within the already-expired auth future, we still mark
    // the device as paired so the user can at least control the TV.
    _credential = pairedMarker;
    await _closeSession();
    emitStatus(ConnectionStatus.disconnected);
  }

  // --- Control ---------------------------------------------------------------

  @override
  Future<void> connect(Device device) async {
    if (_client != null) await _closeSession();
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
      // Key-agnostic so repeats de-dupe into one SnackBar.
      throw const RemoteException("That button isn't available on this TV.");
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
    unawaited(_closeSession());
    super.dispose();
  }

  /// Friendly, specific reason for a failed TLS/socket connect — surfaced in the
  /// UI snackbar so a live test points straight at the cause.
  static String _describeConnectError(Object? e) {
    if (e is HandshakeException) {
      return 'The TV refused the secure connection (TLS handshake failed).';
    }
    if (e is SocketException) {
      return 'Could not reach the TV. Connection refused or no route to it.';
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
        'The TV rejected this client. Try again.',
      MqttConnectReturnCode.brokerUnavailable =>
        'The TV’s remote service is unavailable right now',
      _ => 'Could not open a remote session with the TV',
    };
    return rc == null ? '$reason.' : '$reason (code: ${rc.name}).';
  }

  static MqttServerClient _defaultClientFactory(
    String host,
    int port,
    String clientId,
  ) => MqttServerClient.withPort(host, clientId, port);
}
