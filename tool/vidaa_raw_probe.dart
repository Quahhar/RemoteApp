// Raw MQTT-over-TLS probe for MODERN VIDAA: syncs to the TV's clock + brand
// (read from its UPnP HTTP descriptor) and tries candidate brands to find which
// dynamic credential the broker accepts (CONNACK rc=0), then triggers the PIN.
//   dart run tool/vidaa_raw_probe.dart [ip]
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:remote/controllers/vidaa_credentials.dart';

const port = 36669;
final certPath = Platform.environment['VIDAA_CERT'] ??
    'assets/certs/vidaa_client_cert.pem';
final keyPath =
    Platform.environment['VIDAA_KEY'] ?? 'assets/certs/vidaa_client_key.pem';
var uuid = 'A1:B2:C3:D4:E5:F6';

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
  // Match the real VIDAA app exactly: flags 0xCE = username+password+
  // will(QoS1)+clean, keepalive 36, Will topic "/will" message "dieout".
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

List<int> buildPublish(String topic, String payload) => [
      0x30,
      ...encodeLen(mqttStr(topic).length + utf8.encode(payload).length),
      ...mqttStr(topic),
      ...utf8.encode(payload),
    ];

Future<({int epoch, String brand, int proto})?> fetchDescriptor(
    String host) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    for (final p in [38400, 18400]) {
      try {
        final req = await client.getUrl(
            Uri.parse('http://$host:$p/MediaServer/rendererdevicedesc.xml'));
        final resp = await req.close().timeout(const Duration(seconds: 5));
        final dateHdr = resp.headers.value('date');
        final body = await resp.transform(utf8.decoder).join();
        var epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (dateHdr != null) {
          epoch = HttpDate.parse(dateHdr).millisecondsSinceEpoch ~/ 1000;
        }
        final brandM = RegExp(r'brand=(\w+)').firstMatch(body);
        final protoM = RegExp(r'transport_protocol=(\d+)').firstMatch(body);
        return (
          epoch: epoch,
          brand: brandM?.group(1) ?? 'his',
          proto: int.tryParse(protoM?.group(1) ?? '') ?? 0,
        );
      } catch (_) {}
    }
  } finally {
    client.close();
  }
  return null;
}

late SecurityContext ctx;

/// Connects with [creds]; returns CONNACK rc. If accepted and [pair], triggers
/// the PIN and listens for replies.
Future<int> attempt(String host, VidaaCredentials creds,
    {bool pair = false}) async {
  print('\n--- try clientId=${creds.clientId}');
  SecureSocket socket;
  try {
    socket = await SecureSocket.connect(host, port,
        context: ctx, onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 8));
  } catch (e) {
    print('   TLS FAILED: ${e.runtimeType}: $e');
    return -2;
  }
  var rc = -1;
  var closed = false;
  final connack = Completer<int>();
  final buffer = <int>[];
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
        rc = pkt.length >= 2 ? pkt[1] : -1;
        print('   <= CONNACK rc=$rc'
            '${rc == 0 ? " ACCEPTED ***" : rc == 5 ? " notAuthorized" : ""}');
        if (!connack.isCompleted) connack.complete(rc);
      } else if (type == 0x30) {
        final tlen = (pkt[0] << 8) | pkt[1];
        final topic = utf8.decode(pkt.sublist(2, 2 + tlen));
        final pl = utf8.decode(pkt.sublist(2 + tlen), allowMalformed: true);
        print('   <= PUBLISH $topic : $pl');
      }
    }
  }, onDone: () {
    closed = true;
    if (!connack.isCompleted) connack.complete(-1);
  });

  socket.add(buildConnect(creds.clientId, creds.username, creds.password));
  await socket.flush();
  rc = await connack.future
      .timeout(const Duration(seconds: 6), onTimeout: () => -1);

  if (pair && !closed) {
    final c = creds.clientId;
    print('   (rc=$rc, socket open) subscribing + vidaa_app_connect '
        '(WATCH THE TV FOR A 4-DIGIT PIN)...');
    for (final t in [
      '/remoteapp/mobile/$c/ui_service/data/authentication',
      '/remoteapp/mobile/$c/ui_service/data/authenticationcode',
      '/remoteapp/mobile/$c/platform_service/data/tokenissuance',
      '/remoteapp/mobile/broadcast/ui_service/state',
    ]) {
      socket.add(buildSubscribe(t));
    }
    socket.add(buildPublish(
      '/remoteapp/tv/ui_service/$c/actions/vidaa_app_connect',
      jsonEncode(
          {'app_version': 2, 'connect_result': 0, 'device_type': 'Mobile App'}),
    ));
    await socket.flush();
    await Future<void>.delayed(const Duration(seconds: 12));
  }
  await socket.close();
  return rc;
}

void main(List<String> args) async {
  // args: [host] [timestampOverride] [brandOverride]
  final host = args.isNotEmpty ? args.first : '192.168.18.6';
  final tsOverride = args.length > 1 ? int.tryParse(args[1]) : null;
  final brandOverride = args.length > 2 ? args[2] : null;
  if (args.length > 3 && args[3].isNotEmpty) uuid = args[3];
  final desc = await fetchDescriptor(host);
  final brand = brandOverride ?? desc?.brand ?? 'ksj';
  final ts = tsOverride ??
      desc?.epoch ??
      (DateTime.now().millisecondsSinceEpoch ~/ 1000);
  print('host=$host brand=$brand ts=$ts (desc=${desc?.epoch})');

  ctx = SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);

  final creds = generateVidaaCredentials(
      uuid: uuid, brand: brand, operation: 'secure', timestamp: ts);
  final rc = await attempt(host, creds, pair: true);
  print(rc == 0
      ? '\n*** ACCEPTED (rc=0) — credentials valid! ***'
      : '\nrc=$rc');
  exit(0);
}
