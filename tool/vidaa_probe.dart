// Standalone diagnostic: reproduce the app's Hisense/VIDAA MQTT-over-TLS connect
// from this PC (same LAN as the TV) so we can see the real failure directly.
// Run from the package root:  dart run tool/vidaa_probe.dart [ip]
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

const port = 36669;
const user = 'hisenseservice';
const pass = 'multimqttservice';
const certPath = 'assets/certs/vidaa_client_cert.pem';
const keyPath = 'assets/certs/vidaa_client_key.pem';

late String host;

SecurityContext? buildCtx() {
  try {
    return SecurityContext(withTrustedRoots: false)
      ..useCertificateChain(certPath)
      ..usePrivateKey(keyPath);
  } catch (e) {
    print('   cert load FAILED: $e');
    return null;
  }
}

Future<MqttServerClient?> attempt({
  required String label,
  required bool useCert,
  required bool v311,
}) async {
  print('\n=== $label ===');
  final id = 'remoteapp-${DateTime.now().millisecondsSinceEpoch}';
  final c = MqttServerClient.withPort(host, id, port)
    ..secure = true
    ..onBadCertificate = ((Object cert) => true)
    ..keepAlivePeriod = 60
    ..logging(on: false)
    ..connectionMessage = (MqttConnectMessage()
        .withClientIdentifier(id)
        .authenticateAs(user, pass)
        .startClean());
  if (v311) {
    c.setProtocolV311();
  } else {
    c.setProtocolV31();
  }
  if (useCert) {
    final ctx = buildCtx();
    if (ctx == null) return null;
    c.securityContext = ctx;
  }
  try {
    await c.connect().timeout(const Duration(seconds: 8));
  } catch (e) {
    print('   -> ${e.runtimeType}: $e');
    print('      status=${c.connectionStatus}');
    c.disconnect();
    return null;
  }
  final s = c.connectionStatus;
  if (s?.state == MqttConnectionState.connected) {
    print('   -> CONNECTED  rc=${s?.returnCode}');
    return c;
  }
  print('   -> NOT CONNECTED state=${s?.state} rc=${s?.returnCode}');
  c.disconnect();
  return null;
}

Future<void> tryPair(MqttServerClient c) async {
  const mac = 'AA:BB:CC:DD:EE:FF';
  final dt = '$mac\$normal';
  c.updates?.listen((events) {
    for (final e in events) {
      final m = e.payload;
      if (m is MqttPublishMessage) {
        final t = MqttPublishPayload.bytesToStringAsString(m.payload.message);
        print('   <= ${e.topic}: $t');
      }
    }
  });
  c.subscribe('/remoteapp/mobile/$dt/#', MqttQos.atMostOnce);
  final b = MqttClientPayloadBuilder()..addString('');
  c.publishMessage(
    '/remoteapp/tv/ui_service/$dt/actions/gettvstate',
    MqttQos.atMostOnce,
    b.payload!,
  );
  print('   published gettvstate; waiting 8s for replies / on-TV code...');
  await Future<void>.delayed(const Duration(seconds: 8));
  c.disconnect();
}

Future<void> main(List<String> args) async {
  host = args.isNotEmpty ? args.first : '192.168.18.6';
  print('Probing $host:$port');

  final a = await attempt(
      label: 'A: client-cert + MQTT 3.1.1', useCert: true, v311: true);
  if (a != null) {
    await tryPair(a);
    exit(0);
  }
  final b = await attempt(
      label: 'B: client-cert + MQTT 3.1', useCert: true, v311: false);
  if (b != null) {
    await tryPair(b);
    exit(0);
  }
  final d = await attempt(
      label: 'C: NO client-cert + MQTT 3.1.1', useCert: false, v311: true);
  if (d != null) {
    await tryPair(d);
    exit(0);
  }
  print('\nAll attempts failed.');
  exit(0);
}
