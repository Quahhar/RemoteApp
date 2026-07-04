import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/hisense_controller.dart';

void main() {
  group('VIDAA MQTT topics', () {
    const mac = 'AA:BB:CC:DD:EE:FF';
    final deviceTopic = HisenseController.deviceTopicFor(mac);

    test('device topic appends the \$normal suffix', () {
      expect(deviceTopic, 'AA:BB:CC:DD:EE:FF\$normal');
    });

    test('sendkey topic', () {
      expect(
        HisenseController.keyTopic(deviceTopic),
        '/remoteapp/tv/remote_service/AA:BB:CC:DD:EE:FF\$normal/actions/sendkey',
      );
    });

    test('authentication-code topic', () {
      expect(
        HisenseController.authCodeTopic(deviceTopic),
        '/remoteapp/tv/ui_service/AA:BB:CC:DD:EE:FF\$normal/actions/authenticationcode',
      );
    });

    test('gettvstate (pairing trigger) topic', () {
      expect(
        HisenseController.stateTopic(deviceTopic),
        '/remoteapp/tv/ui_service/AA:BB:CC:DD:EE:FF\$normal/actions/gettvstate',
      );
    });

    test('pairing reply topics are the mobile/data namespace, not the send '
        'topic', () {
      // The TV publishes its PIN acknowledgement on mobile/.../data, NOT on the
      // tv/.../actions topic the app sends the code to. Listening on the send
      // topic (authCodeTopic) never fired, so pairing always timed out.
      expect(
        HisenseController.authReplyTopic(deviceTopic),
        '/remoteapp/mobile/AA:BB:CC:DD:EE:FF\$normal/ui_service/data/authentication',
      );
      expect(
        HisenseController.authCodeReplyTopic(deviceTopic),
        '/remoteapp/mobile/AA:BB:CC:DD:EE:FF\$normal/ui_service/data/authenticationcode',
      );
      expect(
        HisenseController.authReplyTopic(deviceTopic),
        isNot(HisenseController.authCodeTopic(deviceTopic)),
      );
    });

    test('mobile subscription is a wildcard under our device topic', () {
      expect(
        HisenseController.mobileSubscription(deviceTopic),
        '/remoteapp/mobile/AA:BB:CC:DD:EE:FF\$normal/#',
      );
    });
  });

  group('pairing payload + result parsing', () {
    test('auth-code payload is JSON {authNum: <integer code>}', () {
      // pyvidaa sends int(pin) — the TV rejects string authNum.
      final payload = HisenseController.authCodePayload('  1234 ');
      expect(jsonDecode(payload), {'authNum': 1234});
    });

    test('resultFromJson reads a numeric result field', () {
      expect(HisenseController.resultFromJson('{"result":1}'), 1);
      expect(HisenseController.resultFromJson('{"result":0,"info":"x"}'), 0);
    });

    test('resultFromJson coerces a string result ("1") to int', () {
      // Some firmware returns the result as a string; treating that as a miss
      // made a correct PIN look like a failed pairing.
      expect(HisenseController.resultFromJson('{"result":"1"}'), 1);
      expect(HisenseController.resultFromJson('{"result":" 0 "}'), 0);
    });

    test('resultFromJson is null for non-result / non-JSON payloads', () {
      expect(HisenseController.resultFromJson('{"state":"normal"}'), isNull);
      expect(HisenseController.resultFromJson('{"result":"abc"}'), isNull);
      expect(HisenseController.resultFromJson('not json'), isNull);
    });
  });
}
