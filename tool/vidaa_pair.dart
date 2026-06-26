// Interactive VIDAA pairing proof: connect (tolerate rc=5), keep the socket
// open, trigger the on-TV 4-digit PIN, wait for the user to drop it into
// %TEMP%\vidaa_pin.txt, submit it, then send real keys to prove full control.
//   dart run tool/vidaa_pair.dart [ip]
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const port = 36669;
const certPath = 'assets/certs/vidaa_client_cert.pem';
const keyPath = 'assets/certs/vidaa_client_key.pem';
const pinFile = r'C:\Users\x\AppData\Local\Temp\vidaa_pin.txt';

// Stable identity for this pairing attempt.
const mac = 'AA:BB:CC:DD:EE:01';
const deviceTopic = '$mac\$normal';
const clientId = 'remoteapp-aabbccdd01';
const user = 'hisenseservice';
const pass = 'multimqttservice';

List<int> encodeLen(int len) {
  final out = <int>[];
  var l = len;
  do {
    var b = l % 128;
    l = l ~/ 128;
    if (l > 0) b |= 0x80;
    out.add(b);
  } while (l > 0);
  return out;
}

List<int> mqttStr(String s) {
  final b = utf8.encode(s);
  return [b.length >> 8, b.length & 0xFF, ...b];
}

List<int> buildConnect() {
  // flags 0xCE = username+password+will(QoS1)+clean, keepalive 36 (0x24).
  final vh = <int>[...mqttStr('MQTT'), 0x04, 0xCE, 0x00, 0x24];
  final payload = <int>[
    ...mqttStr(clientId),
    ...mqttStr('/will'),
    ...mqttStr('dieout'),
    ...mqttStr(user),
    ...mqttStr(pass),
  ];
  final body = [...vh, ...payload];
  return [0x10, ...encodeLen(body.length), ...body];
}

var _pid = 1;
List<int> buildSubscribe(String topic) {
  final body = <int>[_pid >> 8, _pid & 0xFF, ...mqttStr(topic), 0x00];
  _pid++;
  return [0x82, ...encodeLen(body.length), ...body];
}

List<int> buildPublish(String topic, String payload) {
  final body = [...mqttStr(topic), ...utf8.encode(payload)];
  return [0x30, ...encodeLen(body.length), ...body];
}

const pingreq = [0xC0, 0x00];

void main(List<String> args) async {
  final host = args.isNotEmpty ? args.first : '192.168.18.6';
  try {
    File(pinFile).deleteSync();
  } catch (_) {}
  print('host=$host deviceTopic=$deviceTopic');
  print('cert=$certPath');

  final ctx = SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);

  SecureSocket socket;
  try {
    socket = await SecureSocket.connect(host, port,
        context: ctx,
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 8));
  } catch (e) {
    print('TLS FAILED: ${e.runtimeType}: $e');
    exit(1);
  }
  print('TLS connected.');

  final buffer = <int>[];
  var authed = false;
  var triggered = false;
  void triggerPairing() {
    if (triggered) return;
    triggered = true;
    socket.add(buildSubscribe('/remoteapp/mobile/$deviceTopic/#'));
    print('>> gettvstate (WATCH THE TV — a 4-digit PIN should appear)');
    socket.add(buildPublish(
        '/remoteapp/tv/ui_service/$deviceTopic/actions/gettvstate', ''));
    socket.flush();
  }

  socket.listen((data) {
    buffer.addAll(data);
    while (buffer.length >= 2) {
      var mult = 1, value = 0, i = 1, eb = 0;
      var incomplete = false;
      do {
        if (i >= buffer.length) {
          incomplete = true;
          break;
        }
        eb = buffer[i];
        value += (eb & 0x7F) * mult;
        mult *= 128;
        i++;
      } while ((eb & 0x80) != 0);
      if (incomplete) break;
      final total = i + value;
      if (buffer.length < total) break;
      final type = buffer[0] & 0xF0;
      final pkt = buffer.sublist(i, total);
      buffer.removeRange(0, total);
      if (type == 0x20) {
        final rc = pkt.length >= 2 ? pkt[1] : -1;
        print('<= CONNACK rc=$rc'
            '${rc == 0 ? " ACCEPTED" : rc == 5 ? " notAuthorized (expected pre-pair)" : ""}');
        triggerPairing(); // fire instantly before the TV can drop an rc=5 socket
      } else if (type == 0x30) {
        final tlen = (pkt[0] << 8) | pkt[1];
        final topic = utf8.decode(pkt.sublist(2, 2 + tlen));
        final pl = utf8.decode(pkt.sublist(2 + tlen), allowMalformed: true);
        print('<= PUBLISH $topic : $pl');
        if (pl.contains('"result"')) {
          if (pl.contains('"result":1') || pl.contains('"result":"1"')) {
            authed = true;
            print('*** AUTHENTICATED (result==1) ***');
          }
        }
      }
    }
  }, onDone: () => print('socket closed'));

  // 1) CONNECT — the CONNACK handler triggers the PIN instantly.
  socket.add(buildConnect());
  await socket.flush();

  // keepalive pings so the broker holds the socket while we wait for the PIN
  final ping = Timer.periodic(const Duration(seconds: 18), (_) {
    socket.add(pingreq);
    socket.flush();
  });

  // 3) wait for the PIN to be written to the file
  print('Waiting for PIN in $pinFile (up to 150s)...');
  String? pin;
  for (var t = 0; t < 150; t++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      final f = File(pinFile);
      if (f.existsSync()) {
        final v = f.readAsStringSync().trim();
        if (RegExp(r'^\d{4}$').hasMatch(v)) {
          pin = v;
          break;
        }
      }
    } catch (_) {}
  }
  if (pin == null) {
    print('No PIN provided — aborting.');
    ping.cancel();
    await socket.close();
    exit(2);
  }
  print('>> submitting authNum=$pin');

  // 4) submit the code (try string form, matching our controller)
  socket.add(buildPublish(
    '/remoteapp/tv/ui_service/$deviceTopic/actions/authenticationcode',
    jsonEncode({'authNum': pin}),
  ));
  await socket.flush();
  await Future<void>.delayed(const Duration(seconds: 3));

  // 5) prove control — send a few keys with gaps so the user can watch
  print('>> sending KEY_VOLUMEUP x2, then KEY_MENU (watch the TV)');
  for (final key in ['KEY_VOLUMEUP', 'KEY_VOLUMEUP', 'KEY_MENU']) {
    socket.add(buildPublish(
        '/remoteapp/tv/remote_service/$deviceTopic/actions/sendkey', key));
    await socket.flush();
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  print(authed
      ? '\nRESULT: paired + sent keys. Did the TV react?'
      : '\nRESULT: no explicit result==1 seen; did the TV still react to the keys?');
  await Future<void>.delayed(const Duration(seconds: 2));
  ping.cancel();
  await socket.close();
  exit(0);
}
