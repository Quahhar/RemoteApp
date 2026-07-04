// Interactive MODERN-VIDAA pairing: dynamic "secure" credentials (TV clock +
// brand) → connect (rc=5, socket stays open) → vidaa_app_connect triggers the
// on-TV PIN → user drops it in %TEMP%\vidaa_pin.txt → authenticationcode →
// gettoken → send a real key to prove control.
//   dart run tool/vidaa_pair_secure.dart [ip]
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:remote/controllers/vidaa_credentials.dart';

const port = 36669;
const certPath = 'assets/certs/vidaa_client_cert.pem';
const keyPath = 'assets/certs/vidaa_client_key.pem';
const pinFile = r'C:\Users\x\AppData\Local\Temp\vidaa_pin.txt';
const uuid = 'A1:B2:C3:D4:E5:F6';

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

List<int> buildConnect(String clientId, String user, String pass) {
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

Future<({int epoch, String brand})> descriptor(String host) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    for (final p in [38400, 18400]) {
      try {
        final req = await client.getUrl(Uri.parse(
            'http://$host:$p/MediaServer/rendererdevicedesc.xml'));
        final resp = await req.close().timeout(const Duration(seconds: 5));
        final dateHdr = resp.headers.value('date');
        final body = await resp.transform(utf8.decoder).join();
        final epoch = dateHdr != null
            ? HttpDate.parse(dateHdr).millisecondsSinceEpoch ~/ 1000
            : DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final brand = RegExp(r'brand=(\w+)').firstMatch(body)?.group(1) ?? 'ksj';
        return (epoch: epoch, brand: brand);
      } catch (_) {}
    }
  } finally {
    client.close();
  }
  return (epoch: DateTime.now().millisecondsSinceEpoch ~/ 1000, brand: 'ksj');
}

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tool/vidaa_pair_secure.dart <tv-ip>');
    exit(64); // EX_USAGE
  }
  final host = args.first;
  try {
    File(pinFile).deleteSync();
  } catch (_) {}
  final d = await descriptor(host);
  print('host=$host brand=${d.brand} ts=${d.epoch}');

  final creds = generateVidaaCredentials(
      uuid: uuid, brand: d.brand, operation: 'secure', timestamp: d.epoch);
  final c = creds.clientId; // device identity for all topics
  print('clientId=$c');

  final ctx = SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);

  SecureSocket socket;
  try {
    socket = await SecureSocket.connect(host, port,
        context: ctx, onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 8));
  } catch (e) {
    print('TLS FAILED: $e');
    exit(1);
  }
  print('TLS connected.');

  final buffer = <int>[];
  var authed = false;
  var triggered = false;
  String? accessToken;

  void trigger() {
    if (triggered) return;
    triggered = true;
    for (final t in [
      '/remoteapp/mobile/$c/ui_service/data/authentication',
      '/remoteapp/mobile/$c/ui_service/data/authenticationcode',
      '/remoteapp/mobile/$c/platform_service/data/tokenissuance',
      '/remoteapp/mobile/$c/#',
    ]) {
      socket.add(buildSubscribe(t));
    }
    print('>> vidaa_app_connect (WATCH THE TV FOR A 4-DIGIT PIN)');
    socket.add(buildPublish(
      '/remoteapp/tv/ui_service/$c/actions/vidaa_app_connect',
      jsonEncode(
          {'app_version': 2, 'connect_result': 0, 'device_type': 'Mobile App'}),
    ));
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
        print('<= CONNACK rc=$rc${rc == 0 ? " ACCEPTED" : ""}');
        trigger();
      } else if (type == 0x30) {
        final tlen = (pkt[0] << 8) | pkt[1];
        final topic = utf8.decode(pkt.sublist(2, 2 + tlen));
        final pl = utf8.decode(pkt.sublist(2 + tlen), allowMalformed: true);
        print('<= PUBLISH $topic : $pl');
        if (pl.contains('"result":1') || pl.contains('"result":"1"')) {
          authed = true;
          print('*** AUTHENTICATED ***');
        }
        final m = RegExp(r'"accesstoken"\s*:\s*"([^"]+)"').firstMatch(pl);
        if (m != null) accessToken = m.group(1);
      }
    }
  }, onDone: () => print('socket closed'));

  socket.add(buildConnect(c, creds.username, creds.password));
  await socket.flush();

  final ping = Timer.periodic(const Duration(seconds: 18), (_) {
    socket.add(pingreq);
    socket.flush();
  });

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

  // authNum as an INT (modern firmware expects a number)
  print('>> authenticationcode authNum=$pin');
  socket.add(buildPublish(
    '/remoteapp/tv/ui_service/$c/actions/authenticationcode',
    jsonEncode({'authNum': int.parse(pin)}),
  ));
  await socket.flush();
  await Future<void>.delayed(const Duration(seconds: 3));

  socket.add(buildPublish(
    '/remoteapp/tv/ui_service/$c/actions/gettoken',
    jsonEncode({'refreshtoken': ''}),
  ));
  await socket.flush();
  await Future<void>.delayed(const Duration(seconds: 2));

  print('>> sendkey KEY_VOLUMEUP x2 then KEY_MENU (watch the TV)');
  for (final key in ['KEY_VOLUMEUP', 'KEY_VOLUMEUP', 'KEY_MENU']) {
    socket.add(buildPublish(
        '/remoteapp/tv/remote_service/$c/actions/sendkey', key));
    await socket.flush();
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  print(authed
      ? '\nRESULT: authenticated; token=${accessToken ?? "(none captured)"}'
      : '\nRESULT: no result==1 seen — did the TV react to the keys anyway?');
  await Future<void>.delayed(const Duration(seconds: 2));
  ping.cancel();
  await socket.close();
  exit(0);
}
