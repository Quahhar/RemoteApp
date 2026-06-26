// Fully-logged Android TV Remote v2 probe: pair (6467) then run the control
// handshake (6466) and inject keys, printing every message both ways so we can
// see exactly where control breaks.
//   dart run tool/atv_probe.dart <tv-ip>
// Read the 6-digit code off the TV and drop it in %TEMP%\atv_pin.txt.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:remote/controllers/androidtv/atv_crypto.dart';
import 'package:remote/controllers/androidtv/atv_messages.dart';
import 'package:remote/controllers/androidtv/atv_proto.dart';

const pairingPort = 6467;
const remotePort = 6466;
const pinFile = r'C:\Users\x\AppData\Local\Temp\atv_pin.txt';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

void main(List<String> args) async {
  final host = args.isNotEmpty ? args.first : '192.168.18.6';
  try {
    File(pinFile).deleteSync();
  } catch (_) {}

  final id = AtvCrypto.generateIdentity();
  final clientDer = AtvCrypto.pemToDer(id.certPem);
  final ctx = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(Uint8List.fromList(id.certPem.codeUnits))
    ..usePrivateKeyBytes(Uint8List.fromList(id.keyPem.codeUnits));

  // ---- PAIRING (6467) ----
  print('=== PAIRING on $host:$pairingPort ===');
  final pair = await SecureSocket.connect(host, pairingPort,
      context: ctx, onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 8));
  final serverDer = pair.peerCertificate!.der;
  final pframes = FrameReader();
  final codeReady = Completer<void>();
  final secretAck = Completer<void>();

  pair.listen((data) {
    for (final msg in pframes.add(data)) {
      final m = AtvMessages.parsePairing(msg);
      print('  PAIR <= type=${m.type} status=${m.status} raw=${hex(msg)}');
      if (!m.ok) {
        print('  PAIR error status ${m.status}');
        continue;
      }
      switch (m.type) {
        case PairingType.requestAck:
          print('  PAIR => option');
          pair.add(frame(AtvMessages.pairingOption()));
        case PairingType.option:
          print('  PAIR => configuration');
          pair.add(frame(AtvMessages.pairingConfiguration()));
        case PairingType.configurationAck:
          if (!codeReady.isCompleted) codeReady.complete();
        case PairingType.secretAck:
          if (!secretAck.isCompleted) secretAck.complete();
        case PairingType.unknown:
          break;
      }
    }
  }, onError: (Object e) => print('  PAIR socket error: $e'), onDone: () => print('  PAIR socket closed'));

  print('  PAIR => pairing_request');
  pair.add(frame(AtvMessages.pairingRequest('Flutter Remote Probe')));
  await codeReady.future.timeout(const Duration(seconds: 60));

  print('\n*** A 6-DIGIT CODE should be on the TV. Put it in $pinFile ***');
  String? code;
  for (var t = 0; t < 120; t++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      final v = File(pinFile).readAsStringSync().trim();
      if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(v)) {
        code = v;
        break;
      }
    } catch (_) {}
  }
  if (code == null) {
    print('No code provided — aborting.');
    await pair.close();
    exit(2);
  }

  final secret = AtvCrypto.computeSecret(
      clientCertDer: clientDer, serverCertDer: serverDer, code: code);
  print('  PAIR => secret (code=$code)');
  pair.add(frame(AtvMessages.pairingSecret(secret)));
  await secretAck.future.timeout(const Duration(seconds: 10));
  print('  PAIR: secret acknowledged — PAIRED.');
  await pair.close();

  // ---- CONTROL (6466) ----
  print('\n=== CONTROL on $host:$remotePort ===');
  final remote = await SecureSocket.connect(host, remotePort,
      context: ctx, onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 8));
  final rframes = FrameReader();
  var active = false;

  remote.listen((data) {
    for (final msg in rframes.add(data)) {
      final fields = parseProto(msg);
      print('  CTRL <= fields=${fields.keys.toList()} raw=${hex(msg)}');
      final m = AtvMessages.parseRemote(msg);
      switch (m.type) {
        case RemoteType.configure:
          print('  CTRL => remote_configure');
          remote.add(frame(AtvMessages.remoteConfigure()));
        case RemoteType.setActive:
          print('  CTRL => remote_set_active');
          remote.add(frame(AtvMessages.remoteSetActive()));
          active = true;
        case RemoteType.start:
          print('  CTRL <= remote_start (ready)');
          active = true;
        case RemoteType.pingRequest:
          remote.add(frame(AtvMessages.remotePingResponse(m.pingVal1)));
        case RemoteType.other:
          break;
      }
    }
  }, onError: (Object e) => print('  CTRL socket error: $e'), onDone: () => print('  CTRL socket closed'));

  // wait for the handshake to settle
  await Future<void>.delayed(const Duration(seconds: 4));
  print('  CTRL active=$active');

  // Send navigation keys with gaps — WATCH THE TV.
  const keyDown = 20, keyUp = 19, keyOk = 23;
  for (final entry in [
    ('DPAD_DOWN', keyDown),
    ('DPAD_DOWN', keyDown),
    ('DPAD_UP', keyUp),
    ('OK', keyOk),
  ]) {
    print('  CTRL => key ${entry.$1} (${entry.$2}) SHORT');
    remote.add(frame(AtvMessages.remoteKeyInject(entry.$2)));
    await remote.flush();
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  print('\nDone. Did the TV menu move / select?');
  await Future<void>.delayed(const Duration(seconds: 2));
  await remote.close();
  exit(0);
}
