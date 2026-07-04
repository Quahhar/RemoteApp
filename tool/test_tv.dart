// Direct TV test: try both gettvstate and vidaa_app_connect approaches
// to find which one triggers the PIN on this specific Kenstar TV.
//   dart run tool/test_tv.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:remote/controllers/vidaa_credentials.dart';

late String host; // set from argv in main()
const port = 36669;
const certPath = 'assets/certs/vidaa_client_cert.pem';
const keyPath = 'assets/certs/vidaa_client_key.pem';

String randomMac() {
  final r = Random();
  return List.generate(
    6,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase(),
  ).join(':');
}

Future<({int epoch, String brand, int proto})?> fetchDescriptor() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    for (final p in [38400, 18400]) {
      try {
        final req = await client.getUrl(
          Uri.parse('http://$host:$p/MediaServer/rendererdevicedesc.xml'),
        );
        final resp = await req.close().timeout(const Duration(seconds: 5));
        final dateHdr = resp.headers.value('date');
        final body = await resp.transform(utf8.decoder).join();
        var epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (dateHdr != null) {
          epoch = HttpDate.parse(dateHdr).millisecondsSinceEpoch ~/ 1000;
        }
        final brandM = RegExp(r'brand=(\w+)').firstMatch(body);
        final protoM = RegExp(r'transport_protocol=(\d+)').firstMatch(body);
        final brand = brandM?.group(1) ?? 'ksj';
        final proto = int.tryParse(protoM?.group(1) ?? '') ?? 0;
        return (epoch: epoch, brand: brand, proto: proto);
      } catch (_) {}
    }
  } finally {
    client.close();
  }
  return null;
}

List<int> mqttStr(String s) {
  final b = utf8.encode(s);
  return [b.length >> 8, b.length & 0xFF, ...b];
}

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

Future<void> test(String operation) async {
  _pid = 1;
  final uuid = randomMac();
  final desc = await fetchDescriptor();
  print('\n=== Test with operation="$operation" ===');
  print(
    '  uuid=$uuid  brand=${desc?.brand ?? 'ksj'}  proto=${desc?.proto ?? '?'}',
  );

  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final creds = generateVidaaCredentials(
    uuid: uuid,
    brand: desc?.brand ?? 'ksj',
    operation: operation,
    authMethod: vidaaAuthMethodFor(desc?.proto ?? 0),
    timestamp: ts,
  );
  final c = creds.clientId;
  print('  clientId=$c');
  print('  username=${creds.username}');
  print('  password=${creds.password}');

  final ctx = SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);

  SecureSocket socket;
  try {
    socket = await SecureSocket.connect(
      host,
      port,
      context: ctx,
      onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 8),
    );
  } catch (e) {
    print('  TLS FAILED: $e');
    return;
  }
  print('  TLS connected.');

  final buffer = <int>[];
  final connack = Completer<int>();
  var rc = -1;

  socket.listen(
    (data) {
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
          rc = pkt.length >= 2 ? pkt[1] : -1;
          print('  <= CONNACK rc=$rc');
          if (!connack.isCompleted) connack.complete(rc);
        } else if (type == 0x30) {
          final tlen = (pkt[0] << 8) | pkt[1];
          final topic = utf8.decode(pkt.sublist(2, 2 + tlen));
          final pl = utf8.decode(pkt.sublist(2 + tlen), allowMalformed: true);
          print('  <= PUBLISH $topic : $pl');
        }
      }
    },
    onDone: () {
      if (!connack.isCompleted) connack.complete(-1);
    },
  );

  socket.add(buildConnect(c, creds.username, creds.password));
  await socket.flush();
  rc = await connack.future.timeout(
    const Duration(seconds: 6),
    onTimeout: () => -1,
  );

  if (rc != 0) {
    print('  CONNECT failed (rc=$rc), skipping trigger.');
    await socket.close();
    return;
  }

  print('  CONNECT accepted! Sending triggers...');

  // Subscribe to response topics
  for (final t in [
    '/remoteapp/mobile/$c/ui_service/data/authentication',
    '/remoteapp/mobile/$c/ui_service/data/authenticationcode',
    '/remoteapp/mobile/$c/#',
  ]) {
    socket.add(buildSubscribe(t));
  }

  // Send BOTH triggers
  socket.add(
    buildPublish('/remoteapp/tv/ui_service/$c/actions/gettvstate', ''),
  );
  socket.add(
    buildPublish(
      '/remoteapp/tv/ui_service/$c/actions/vidaa_app_connect',
      jsonEncode({
        'app_version': 2,
        'connect_result': 0,
        'device_type': 'Mobile App',
      }),
    ),
  );
  await socket.flush();

  print('  Waiting 8s for replies...');
  await Future<void>.delayed(const Duration(seconds: 8));
  await socket.close();
  print('  done.');
}

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tool/test_tv.dart <tv-ip>');
    exit(64); // EX_USAGE
  }
  host = args.first;
  print('Testing TV at $host:$port\n');
  await test('vidaacommon');
  await test('secure');
  exit(0);
}
