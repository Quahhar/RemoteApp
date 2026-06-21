import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/capabilities.dart';
import '../models/connection_status.dart';
import '../models/device.dart';
import '../models/protocol_type.dart';
import '../models/remote_key.dart';
import '../persistence/atv_identity_store.dart';
import 'androidtv/atv_crypto.dart';
import 'androidtv/atv_messages.dart';
import 'androidtv/atv_proto.dart';
import 'remote_controller.dart';

/// Android TV / Google TV via the Remote v2 protocol.
///
/// Two TLS channels share one app-global client certificate:
///  - pairing (6467): the 6-digit on-screen code handshake — [beginPairing]
///    connects and waits until the TV shows the code, then [completePairing]
///    sends the derived secret and persists the pairing.
///  - remote (6466): [connect] does the configure/set-active handshake and
///    answers pings; [sendKey] injects Android key events.
///
/// A device is "paired" once its [Device.authToken] is the `paired` marker; the
/// actual certificate lives app-globally in [AtvIdentityStore].
class AndroidTvController extends RemoteController {
  AndroidTvController({
    required this.identity,
    this.connectTimeout = const Duration(seconds: 8),
    this.pairingTimeout = const Duration(seconds: 60),
  });

  final AtvIdentityStore identity;
  final Duration connectTimeout;
  final Duration pairingTimeout;

  static const int _pairingPort = 6467;
  static const int _remotePort = 6466;
  static const String pairedMarker = 'paired';

  SecureSocket? _remote;
  FrameReader _remoteFrames = FrameReader();
  Completer<void>? _active;

  SecureSocket? _pairing;
  FrameReader _pairingFrames = FrameReader();
  Completer<void>? _codeReady;
  Completer<void>? _secretAck;
  Uint8List? _clientCertDer;
  Uint8List? _serverCertDer;

  String? _credential;

  /// RemoteKey -> Android `KeyEvent` keycode (the value the v2 channel sends).
  static const Map<RemoteKey, int> keyCodes = {
    RemoteKey.power: 26,
    RemoteKey.up: 19,
    RemoteKey.down: 20,
    RemoteKey.left: 21,
    RemoteKey.right: 22,
    RemoteKey.ok: 23,
    RemoteKey.back: 4,
    RemoteKey.home: 3,
    RemoteKey.menu: 82,
    RemoteKey.volumeUp: 24,
    RemoteKey.volumeDown: 25,
    RemoteKey.mute: 164,
    RemoteKey.channelUp: 166,
    RemoteKey.channelDown: 167,
    RemoteKey.play: 126,
    RemoteKey.pause: 127,
  };

  @override
  ProtocolType get protocol => ProtocolType.androidtv;

  @override
  Capabilities get capabilities => const Capabilities(
        supportsPointer: false, // v2 is key-based; no pointer
        supportsTextInput: false, // IME text is a later addition
        channelButtons: true,
        numberPad: true,
        requiresPairingCode: true,
      );

  @override
  String? get authToken => _credential;

  /// mDNS discovery is a later addition; add devices manually for now.
  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) =>
      const Stream<Device>.empty();

  SecurityContext _securityContext(AtvIdentity id) {
    return SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(id.certPem))
      ..usePrivateKeyBytes(utf8.encode(id.keyPem));
  }

  void _send(SecureSocket socket, Uint8List message) =>
      socket.add(frame(message));

  // --- Pairing ---------------------------------------------------------------

  @override
  Future<void> beginPairing(Device device) async {
    emitStatus(ConnectionStatus.connecting);
    final id = await identity.ensure();
    _clientCertDer = AtvCrypto.pemToDer(id.certPem);
    try {
      _pairing = await SecureSocket.connect(
        device.host,
        device.port ?? _pairingPort,
        context: _securityContext(id),
        onBadCertificate: (_) => true,
      ).timeout(connectTimeout);
    } catch (_) {
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException();
    }
    _serverCertDer = _pairing!.peerCertificate?.der;
    if (_serverCertDer == null) {
      await _closePairing();
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException('No certificate from TV');
    }
    _pairingFrames = FrameReader();
    _codeReady = Completer<void>();
    _pairing!.listen(
      _onPairingData,
      onError: (Object e) => _failPairing(e),
      onDone: () => _failPairing('connection closed'),
      cancelOnError: true,
    );
    _send(_pairing!, AtvMessages.pairingRequest('Flutter Remote'));

    await _codeReady!.future.timeout(
      pairingTimeout,
      onTimeout: () {
        _closePairing();
        throw const PairingRequiredException('Timed out reaching the TV');
      },
    );
  }

  void _onPairingData(Uint8List chunk) {
    for (final msg in _pairingFrames.add(chunk)) {
      final m = AtvMessages.parsePairing(msg);
      if (!m.ok) {
        _failPairing('TV returned status ${m.status}');
        return;
      }
      switch (m.type) {
        case PairingType.requestAck:
          _send(_pairing!, AtvMessages.pairingOption());
        case PairingType.option:
          _send(_pairing!, AtvMessages.pairingConfiguration());
        case PairingType.configurationAck:
          _completeOnce(_codeReady);
        case PairingType.secretAck:
          _completeOnce(_secretAck);
        case PairingType.unknown:
          break;
      }
    }
  }

  @override
  Future<void> completePairing(String code) async {
    if (_pairing == null || _serverCertDer == null || _clientCertDer == null) {
      throw const PairingRequiredException('Start pairing first');
    }
    final Uint8List secret;
    try {
      secret = AtvCrypto.computeSecret(
        clientCertDer: _clientCertDer!,
        serverCertDer: _serverCertDer!,
        code: code.trim(),
      );
    } on FormatException {
      throw const PairingRejectedException('That code didn\'t match — try again');
    }
    _secretAck = Completer<void>();
    _send(_pairing!, AtvMessages.pairingSecret(secret));
    try {
      await _secretAck!.future.timeout(connectTimeout);
    } catch (_) {
      await _closePairing();
      emitStatus(ConnectionStatus.error);
      throw const PairingRejectedException();
    }
    _credential = pairedMarker;
    await _closePairing();
    emitStatus(ConnectionStatus.disconnected);
  }

  void _failPairing(Object error) {
    _codeReady?.completeError(const PairingRejectedException());
    _secretAck?.completeError(const PairingRejectedException());
    _codeReady = null;
    _secretAck = null;
  }

  Future<void> _closePairing() async {
    try {
      await _pairing?.close();
    } catch (_) {}
    _pairing = null;
  }

  // --- Remote (control) ------------------------------------------------------

  @override
  Future<void> connect(Device device) async {
    if (device.authToken != pairedMarker) {
      emitStatus(ConnectionStatus.error);
      throw const PairingRequiredException();
    }
    final id = identity.load();
    if (id == null) {
      emitStatus(ConnectionStatus.error);
      throw const PairingRequiredException('Pairing was lost — pair again');
    }
    emitStatus(ConnectionStatus.connecting);
    try {
      _remote = await SecureSocket.connect(
        device.host,
        _remotePort,
        context: _securityContext(id),
        onBadCertificate: (_) => true,
      ).timeout(connectTimeout);
    } catch (_) {
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException();
    }
    _remoteFrames = FrameReader();
    _active = Completer<void>();
    _remote!.listen(
      _onRemoteData,
      onError: (Object _) => _failRemote(),
      onDone: _failRemote,
      cancelOnError: true,
    );
    try {
      await _active!.future.timeout(connectTimeout);
    } catch (_) {
      await _closeRemote();
      emitStatus(ConnectionStatus.error);
      throw const NotReachableException('TV did not complete the handshake');
    }
    _credential = pairedMarker;
    emitStatus(ConnectionStatus.connected);
  }

  void _onRemoteData(Uint8List chunk) {
    for (final msg in _remoteFrames.add(chunk)) {
      final m = AtvMessages.parseRemote(msg);
      switch (m.type) {
        case RemoteType.configure:
          _send(_remote!, AtvMessages.remoteConfigure());
        case RemoteType.setActive:
          _send(_remote!, AtvMessages.remoteSetActive());
          _completeOnce(_active); // ready once active
        case RemoteType.start:
          _completeOnce(_active);
        case RemoteType.pingRequest:
          _send(_remote!, AtvMessages.remotePingResponse(m.pingVal1));
        case RemoteType.other:
          break;
      }
    }
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    final socket = _remote;
    if (socket == null) {
      throw const RemoteException('Android TV is not connected');
    }
    final code = keyCodes[key];
    if (code == null) {
      throw RemoteException('Unsupported key: ${key.name}');
    }
    _send(socket, AtvMessages.remoteKeyInject(code));
  }

  void _failRemote() {
    if (_active != null && !_active!.isCompleted) {
      _active!.completeError(const ConnectionLostException());
    }
    if (status == ConnectionStatus.connected) {
      emitStatus(ConnectionStatus.error);
    }
  }

  Future<void> _closeRemote() async {
    try {
      await _remote?.close();
    } catch (_) {}
    _remote = null;
  }

  @override
  Future<void> disconnect() async {
    await _closeRemote();
    await _closePairing();
    emitStatus(ConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    _remote?.destroy();
    _pairing?.destroy();
    super.dispose();
  }

  void _completeOnce(Completer<void>? c) {
    if (c != null && !c.isCompleted) c.complete();
  }
}
