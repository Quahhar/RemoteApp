import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

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

  /// The mDNS service Android TVs advertise their Remote v2 endpoint under.
  static const String _mdnsService = '_androidtvremote2._tcp';

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
    // Extended keys — Android `KeyEvent` keycodes. The richest set of the six
    // protocols; unmapped More-sheet commands still surface as "not available".
    RemoteKey.digit0: 7,
    RemoteKey.digit1: 8,
    RemoteKey.digit2: 9,
    RemoteKey.digit3: 10,
    RemoteKey.digit4: 11,
    RemoteKey.digit5: 12,
    RemoteKey.digit6: 13,
    RemoteKey.digit7: 14,
    RemoteKey.digit8: 15,
    RemoteKey.digit9: 16,
    RemoteKey.previous: 88, // MEDIA_PREVIOUS
    RemoteKey.next: 87, // MEDIA_NEXT
    RemoteKey.rewind: 89, // MEDIA_REWIND
    RemoteKey.fastForward: 90, // MEDIA_FAST_FORWARD
    RemoteKey.stop: 86, // MEDIA_STOP
    RemoteKey.record: 130, // MEDIA_RECORD
    RemoteKey.liveTv: 170, // TV
    RemoteKey.guide: 172, // GUIDE
    RemoteKey.source: 178, // TV_INPUT
    RemoteKey.subtitles: 175, // CAPTIONS
    RemoteKey.sleep: 223, // SLEEP
    RemoteKey.audioTrack: 222, // MEDIA_AUDIO_TRACK
    RemoteKey.colorRed: 183, // PROG_RED
    RemoteKey.colorGreen: 184, // PROG_GREEN
    RemoteKey.colorYellow: 185, // PROG_YELLOW
    RemoteKey.colorBlue: 186, // PROG_BLUE
    RemoteKey.inputHdmi1: 243, // TV_INPUT_HDMI_1
    RemoteKey.inputHdmi2: 244, // TV_INPUT_HDMI_2
    RemoteKey.inputHdmi3: 245, // TV_INPUT_HDMI_3
    RemoteKey.inputAv: 247, // TV_INPUT_COMPOSITE_1
    RemoteKey.inputTv: 170, // TV
    RemoteKey.settings: 176, // SETTINGS
    RemoteKey.search: 84, // SEARCH
    RemoteKey.voiceAssist: 231, // VOICE_ASSIST
    RemoteKey.notifications: 83, // NOTIFICATION
  };

  @override
  ProtocolType get protocol => ProtocolType.androidtv;

  @override
  Capabilities get capabilities => const Capabilities(
    supportsPointer: false, // v2 is key-based; no pointer
    supportsTextInput: true,
    channelButtons: true,
    numberPad: true,
    requiresPairingCode: true,
  );

  @override
  String? get authToken => _credential;

  /// Auto-discovers Android TVs by browsing the `_androidtvremote2._tcp` mDNS
  /// service the TV advertises, yielding each with its on-TV friendly name. The
  /// cross-protocol LAN port scan also finds them (as a generic "Android TV
  /// (ip)") as a fallback; these named results win de-duplication because the
  /// port scan starts a moment later. Best-effort: any mDNS failure (e.g. a
  /// platform without a multicast lock) just yields nothing and leaves the port
  /// scan to cover it.
  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) {
    final out = StreamController<Device>();
    final seen = <String>{};
    final client = _mdnsClient();
    var started = false;
    var stopped = false;

    void stop() {
      if (started && !stopped) {
        stopped = true;
        client.stop();
      }
    }

    Future<void> run() async {
      try {
        await client.start();
        started = true;
      } catch (_) {
        try {
          client.stop();
        } catch (_) {}
        if (!out.isClosed) await out.close();
        return;
      }
      try {
        await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer('$_mdnsService.local'),
          timeout: timeout,
        )) {
          final name = instanceName(ptr.domainName);
          await for (final srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: timeout,
          )) {
            await for (final ip in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
              timeout: timeout,
            )) {
              final host = ip.address.address;
              if (!seen.add(host)) continue;
              if (out.isClosed) return;
              out.add(
                Device(
                  id: 'androidtv-$host',
                  name: name.isEmpty ? 'Android TV ($host)' : name,
                  host: host,
                  protocol: ProtocolType.androidtv,
                ),
              );
            }
          }
        }
      } catch (_) {
        // Best-effort; the LAN port scan is the fallback.
      } finally {
        stop();
        if (!out.isClosed) await out.close();
      }
    }

    out.onListen = run;
    out.onCancel = stop;
    return out.stream;
  }

  /// Builds an [MDnsClient] that binds without `reusePort` (which Windows — used
  /// for desktop testing — doesn't support); the default would throw there.
  static MDnsClient _mdnsClient() => MDnsClient(
    rawDatagramSocketFactory:
        (
          dynamic host,
          int port, {
          bool reuseAddress = true,
          bool reusePort = true,
          int ttl = 1,
        }) => RawDatagramSocket.bind(
          host,
          port,
          reuseAddress: reuseAddress,
          reusePort: false,
          ttl: ttl,
        ),
  );

  /// Extracts the human-readable instance (friendly) name from an mDNS PTR
  /// domain like `Living Room TV._androidtvremote2._tcp.local`, DNS-SD-unescaping
  /// the instance label (`\DDD` decimal escapes and `\x` literal escapes such as
  /// `\.`, `\\`, `\ `). Returns '' when the domain isn't this service.
  @visibleForTesting
  static String instanceName(String ptrDomain) {
    var s = ptrDomain.endsWith('.')
        ? ptrDomain.substring(0, ptrDomain.length - 1)
        : ptrDomain;
    final marker = '.$_mdnsService';
    final idx = s.indexOf(marker);
    if (idx < 0) return '';
    final label = s.substring(0, idx);

    final sb = StringBuffer();
    var i = 0;
    while (i < label.length) {
      final ch = label[i];
      if (ch == r'\' && i + 1 < label.length) {
        final rest = label.substring(i + 1);
        final dec = RegExp(r'^[0-9]{3}').firstMatch(rest);
        if (dec != null) {
          sb.writeCharCode(int.parse(dec.group(0)!));
          i += 4;
          continue;
        }
        sb.write(label[i + 1]);
        i += 2;
        continue;
      }
      sb.write(ch);
      i++;
    }
    return sb.toString();
  }

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
    // Re-entry guard: close any pairing socket still open from a prior attempt
    // so a second beginPairing doesn't leak it (mirrors connect()/_closeRemote).
    if (_pairing != null) await _closePairing();
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
      // Pairing is where first contact happens, so be specific: the usual
      // culprits are standby (the pairing service sleeps with the screen), a
      // different network, or Android TV's cooldown after failed attempts.
      throw const NotReachableException(
        "Couldn't reach the TV to start pairing. Make sure the TV is fully on "
        '(not standby) and on the same Wi-Fi. After several failed attempts, '
        'Android TV pauses pairing for a minute — wait, then try again.',
      );
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
      throw const PairingRejectedException(
        'That code didn\'t match. Try again.',
      );
    }
    _secretAck = Completer<void>();
    _send(_pairing!, AtvMessages.pairingSecret(secret));
    try {
      await _secretAck!.future.timeout(connectTimeout);
    } catch (_) {
      await _closePairing();
      emitStatus(ConnectionStatus.error);
      throw const PairingRejectedException(
        'The TV rejected the code. Start pairing again and retype the code '
        'exactly as shown on the TV.',
      );
    }
    _credential = pairedMarker;
    await _closePairing();
    emitStatus(ConnectionStatus.disconnected);
  }

  void _failPairing(Object error) {
    // Only flip to error when a handshake was genuinely in flight. _failPairing
    // is also reached via onDone after a *successful* pair (completePairing
    // closes the socket); an unconditional emit would clobber that success.
    final wasPending = (_codeReady != null && !_codeReady!.isCompleted) ||
        (_secretAck != null && !_secretAck!.isCompleted);
    _failOnce(_codeReady);
    _failOnce(_secretAck);
    _codeReady = null;
    _secretAck = null;
    _closePairing();
    if (wasPending) emitStatus(ConnectionStatus.error);
  }

  void _failOnce(Completer<void>? c) {
    if (c != null && !c.isCompleted) {
      c.completeError(const PairingRejectedException());
    }
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
    if (_remote != null) await _closeRemote();
    if (device.authToken != pairedMarker) {
      emitStatus(ConnectionStatus.error);
      throw const PairingRequiredException();
    }
    final id = identity.load();
    if (id == null) {
      emitStatus(ConnectionStatus.error);
      throw const PairingRequiredException('Pairing was lost. Pair again.');
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
          _completeOnce(_active);
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
      // Key-agnostic so repeats de-dupe into one SnackBar.
      throw const RemoteException("That button isn't available on this TV.");
    }
    _send(socket, AtvMessages.remoteKeyInject(code));
  }

  @override
  Future<void> sendText(String text) async {
    // No-op on empty input so we never emit a zero-length text-inject frame.
    if (text.isEmpty) return;
    final socket = _remote;
    if (socket == null) {
      throw const RemoteException('Android TV is not connected');
    }
    _send(socket, AtvMessages.remoteTextInject(text));
  }

  void _failRemote() {
    if (_active != null && !_active!.isCompleted) {
      _active!.completeError(const ConnectionLostException());
    }
    _active = null;
    // Always emit error when the socket drops — even during connecting, so the
    // UI doesn't stay stuck on "connecting" forever.
    if (status == ConnectionStatus.connecting ||
        status == ConnectionStatus.connected) {
      emitStatus(ConnectionStatus.error);
    }
    _closeRemote();
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
