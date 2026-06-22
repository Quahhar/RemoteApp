// One-off: verify our credential math reproduces the app's captured SECURE
// connect (operation "secure"). ignore_for_file: avoid_print
// ignore_for_file: avoid_print
import 'package:remote/controllers/vidaa_credentials.dart';

void main() {
  // Captured from the real VIDAA app's on-the-wire MQTT CONNECT:
  //   clientId 29:88:D0:1B:35:18$ksj$6F027F_secure_001
  //   username ksj$6239759786149848970
  //   password 0C453436CA4A662EFF3A5ADE7EBDA853
  const xorTime = 6239759786149848970;
  const k = 0x569814772b03a968;
  final time = xorTime ^ k;
  print('decoded time = $time');

  final c = generateVidaaCredentials(
    uuid: '29:88:D0:1B:35:18',
    brand: 'ksj',
    operation: 'secure',
    timestamp: time,
  );
  print('clientId : ${c.clientId}');
  print('  expect : 29:88:D0:1B:35:18\$ksj\$6F027F_secure_001');
  print('username : ${c.username}');
  print('  expect : ksj\$6239759786149848970');
  print('password : ${c.password}');
  print('  expect : 0C453436CA4A662EFF3A5ADE7EBDA853');
  final ok = c.password == '0C453436CA4A662EFF3A5ADE7EBDA853' &&
      c.clientId == '29:88:D0:1B:35:18\$ksj\$6F027F_secure_001' &&
      c.username == 'ksj\$6239759786149848970';
  print(ok ? 'MATCH: our algorithm reproduces the app exactly.'
      : 'MISMATCH: the secure connect uses different math.');
}
