// Raw MQTT-over-TLS probe: bypasses mqtt_client to test whether the VIDAA broker
// keeps the socket open after a notAuthorized CONNACK (so we can submit the PIN
// on the same connection, like pyvidaa/paho does). Run from package root:
//   dart run tool/vidaa_raw_probe.dart [ip]
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const port = 36669;
const user = 'hisenseservice';
const pass = 'multimqttservice';
const certPath = 'assets/certs/vidaa_client_cert.pem';
const keyPath = 'assets/certs/vidaa_client_key.pem';
const mac = 'AA:BB:CC:DD:EE:FF';

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

List<int> buildConnect(String clientId) {
  final vh = <int>[...mqttStr('MQTT'), 0x04, 0xC2, 0x00, 0x3C];
  final payload = <int>[
    ...mqttStr(clientId),
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
  final body = <int>[...mqttStr(topic), ...utf8.encode(payload)];
  return [0x30, ...encodeLen(body.length), ...body];
}

void main(List<String> args) async {
  final host = args.isNotEmpty ? args.first : '192.168.18.6';
  final dt = '$mac\$normal';
  print('Raw MQTT probe -> $host:$port');

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
    print('TLS connect FAILED: ${e.runtimeType}: $e');
    exit(1);
  }
  print('TLS connected: ${socket.selectedProtocol ?? "(tls ok)"}');

  var closed = false;
  final buffer = <int>[];
  socket.listen(
    (data) {
      buffer.addAll(data);
      while (true) {
        if (buffer.length < 2) break;
        var multiplier = 1, value = 0, i = 1, eb = 0;
        var incomplete = false;
        do {
          if (i >= buffer.length) {
            incomplete = true;
            break;
          }
          eb = buffer[i];
          value += (eb & 0x7F) * multiplier;
          multiplier *= 128;
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
          print('<= CONNACK rc=$rc  ${rc == 0 ? "(accepted)" : rc == 5 ? "(notAuthorized)" : ""}');
        } else if (type == 0x30) {
          final tlen = (pkt[0] << 8) | pkt[1];
          final topic = utf8.decode(pkt.sublist(2, 2 + tlen));
          final payload = utf8.decode(pkt.sublist(2 + tlen), allowMalformed: true);
          print('<= PUBLISH $topic : $payload');
        } else if (type == 0x90) {
          print('<= SUBACK');
        } else {
          print('<= packet type 0x${type.toRadixString(16)}');
        }
      }
    },
    onError: (e) => print('socket error: $e'),
    onDone: () {
      closed = true;
      print('** socket CLOSED by TV **');
    },
  );

  socket.add(buildConnect('remoteapp-rawprobe'));
  await socket.flush();
  await Future<void>.delayed(const Duration(seconds: 2));
  print('socket still open after CONNACK? ${!closed}');

  if (!closed) {
    print('=> subscribing + publishing gettvstate (TV should show a PIN)...');
    socket.add(buildSubscribe('/remoteapp/mobile/$dt/#'));
    socket.add(buildPublish(
        '/remoteapp/tv/ui_service/$dt/actions/gettvstate', ''));
    await socket.flush();
    await Future<void>.delayed(const Duration(seconds: 8));
  }
  print('done. socket closed=$closed');
  await socket.close();
  exit(0);
}
