import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/tizen_controller.dart';

void main() {
  group('TizenController.channelUri', () {
    final name = Uri.encodeQueryComponent(base64.encode(utf8.encode('Remote')));

    test('uses wss for the secure 8002 endpoint', () {
      expect(
        TizenController.channelUri('1.2.3.4', 8002, 'Remote', null),
        'wss://1.2.3.4:8002/api/v2/channels/samsung.remote.control?name=$name',
      );
    });

    test('uses ws for the legacy 8001 endpoint', () {
      expect(
        TizenController.channelUri('1.2.3.4', 8001, 'Remote', null),
        startsWith('ws://1.2.3.4:8001/'),
      );
    });

    test('omits the token param when there is no token', () {
      expect(
        TizenController.channelUri('1.2.3.4', 8002, 'Remote', null),
        isNot(contains('token=')),
      );
    });

    test('percent-encodes a token with special characters', () {
      final url = TizenController.channelUri('1.2.3.4', 8002, 'Remote', 'a&b=c');
      expect(url, contains('&token=a%26b%3Dc'));
      // The raw, unescaped form must not leak into the query string.
      expect(url, isNot(contains('token=a&b=c')));
    });

    test('encodes the base64 name param so it stays well-formed', () {
      // An appName whose base64 contains '+' / '/' must be escaped.
      final url = TizenController.channelUri('1.2.3.4', 8002, '~~~~~?', null);
      final raw = base64.encode(utf8.encode('~~~~~?'));
      expect(raw, anyOf(contains('+'), contains('/')));
      expect(url, contains('name=${Uri.encodeQueryComponent(raw)}'));
    });
  });
}
