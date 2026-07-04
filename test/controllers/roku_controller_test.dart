import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote/controllers/remote_controller.dart';
import 'package:remote/controllers/roku_controller.dart';
import 'package:remote/models/connection_status.dart';
import 'package:remote/models/device.dart';
import 'package:remote/models/protocol_type.dart';
import 'package:remote/models/remote_key.dart';

const _device = Device(
  id: 'test-roku',
  name: 'Test Roku',
  host: '192.168.1.50',
  protocol: ProtocolType.roku,
);

const _deviceInfoXml = '''
<?xml version="1.0" encoding="UTF-8" ?>
<device-info>
  <udn>015e5108-9000-1046-8035-b0a737964dfb</udn>
  <serial-number>YH00C123456</serial-number>
  <device-id>S01234567890</device-id>
  <model-name>Roku Ultra</model-name>
  <friendly-device-name>Roku Ultra - Living Room</friendly-device-name>
  <user-device-name>Living Room TV</user-device-name>
</device-info>
''';

void main() {
  group('RemoteKey -> Roku ECP key mapping', () {
    test('every core RemoteKey maps to a non-empty Roku key name', () {
      for (final key in RemoteKey.core) {
        final name = RokuController.keyNames[key];
        expect(name, isNotNull, reason: 'No Roku mapping for ${key.name}');
        expect(name, isNotEmpty, reason: 'Empty Roku mapping for ${key.name}');
      }
    });

    test('every mapped key has a non-empty ECP name', () {
      for (final entry in RokuController.keyNames.entries) {
        expect(entry.value, isNotEmpty, reason: 'Empty mapping for ${entry.key}');
      }
    });

    test('documented special-case mappings are correct', () {
      expect(RokuController.keyNames[RemoteKey.ok], 'Select');
      expect(RokuController.keyNames[RemoteKey.menu], 'Info');
      expect(RokuController.keyNames[RemoteKey.mute], 'VolumeMute');
      // Roku has no discrete pause; both transport keys use Play.
      expect(RokuController.keyNames[RemoteKey.play], 'Play');
      expect(RokuController.keyNames[RemoteKey.pause], 'Play');
    });

    // Each mapped key must POST to /keypress/{KeyName} on the device.
    for (final key in RokuController.keyNames.keys) {
      test('sendKey(${key.name}) POSTs /keypress/${RokuController.keyNames[key]}',
          () async {
        final requests = <http.Request>[];
        final client = MockClient((req) async {
          requests.add(req);
          return http.Response('', 200);
        });
        final controller = RokuController(client: client);
        await controller.connect(_device);
        requests.clear(); // discard the connect() device-info probe
        await controller.sendKey(key);
        controller.dispose();

        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.url.scheme, 'http');
        expect(requests.single.url.host, '192.168.1.50');
        expect(requests.single.url.port, 8060);
        expect(
          requests.single.url.path,
          '/keypress/${RokuController.keyNames[key]}',
        );
      });
    }
  });

  group('unsupported extended keys', () {
    test('an unmapped More-sheet key throws a RemoteException', () async {
      final client = MockClient((req) async => http.Response('', 200));
      final controller = RokuController(client: client);
      await controller.connect(_device);
      // Roku ECP has no colour buttons.
      await expectLater(
        controller.sendKey(RemoteKey.colorRed),
        throwsA(isA<RemoteException>()),
      );
      controller.dispose();
    });
  });

  group('connect()', () {
    test('200 from device-info -> connected', () async {
      final client = MockClient((req) async => http.Response(_deviceInfoXml, 200));
      final controller = RokuController(client: client);
      await controller.connect(_device);
      expect(controller.status, ConnectionStatus.connected);
      controller.dispose();
    });

    test('non-200 -> "control blocked" RemoteException + error status',
        () async {
      // The TV answered HTTP, so it IS reachable — the refusal means its
      // "Control by mobile apps" setting is off. The error must say so
      // (with the on-TV fix) rather than claim the TV is unreachable.
      final client = MockClient((req) async => http.Response('', 403));
      final controller = RokuController(client: client);
      await expectLater(
        controller.connect(_device),
        throwsA(
          isA<RemoteException>()
              .having((e) => e, 'type', isNot(isA<NotReachableException>()))
              .having(
                (e) => e.message,
                'message',
                RokuController.controlBlockedMessage,
              ),
        ),
      );
      expect(controller.status, ConnectionStatus.error);
      controller.dispose();
    });

    test('socket failure -> NotReachableException', () async {
      final client = MockClient((req) async => throw const SocketException('down'));
      final controller = RokuController(client: client);
      await expectLater(
        controller.connect(_device),
        throwsA(isA<NotReachableException>()),
      );
      controller.dispose();
    });

    test('heartbeat tracks the TV going offline and back (self-healing)',
        () async {
      var online = true;
      final client = MockClient((req) async {
        if (!online) throw const SocketException('offline');
        return http.Response(_deviceInfoXml, 200);
      });
      final controller = RokuController(
        client: client,
        heartbeatInterval: const Duration(milliseconds: 20),
      );
      await controller.connect(_device);
      expect(controller.status, ConnectionStatus.connected);

      online = false; // TV drops off the network
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(controller.status, ConnectionStatus.error);

      online = true; // TV returns — heartbeat must recover on its own
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(controller.status, ConnectionStatus.connected);
      controller.dispose();
    });
  });

  group('sendKey()', () {
    test('without an active device throws RemoteException', () async {
      final client = MockClient((req) async => http.Response('', 200));
      final controller = RokuController(client: client);
      await expectLater(
        controller.sendKey(RemoteKey.ok),
        throwsA(isA<RemoteException>()),
      );
      controller.dispose();
    });

    test('transport failure surfaces NotReachableException after retry',
        () async {
      var posts = 0;
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          posts++;
          throw const SocketException('refused');
        }
        return http.Response('', 200); // connect probe succeeds
      });
      final controller = RokuController(
        client: client,
        requestTimeout: const Duration(milliseconds: 200),
      );
      await controller.connect(_device);
      await expectLater(
        controller.sendKey(RemoteKey.home),
        throwsA(isA<NotReachableException>()),
      );
      expect(posts, 2, reason: 'should attempt twice (1 retry)');
      expect(controller.status, ConnectionStatus.error);
      controller.dispose();
    });
  });

  group('parsing helpers', () {
    test('xmlTag prefers user-device-name and reads udn', () {
      expect(
        RokuController.xmlTag(_deviceInfoXml, 'user-device-name'),
        'Living Room TV',
      );
      expect(
        RokuController.xmlTag(_deviceInfoXml, 'udn'),
        '015e5108-9000-1046-8035-b0a737964dfb',
      );
      expect(RokuController.xmlTag(_deviceInfoXml, 'no-such-tag'), isNull);
    });

    test('ssdpHeader reads LOCATION case-insensitively', () {
      const response = 'HTTP/1.1 200 OK\r\n'
          'Cache-Control: max-age=3600\r\n'
          'ST: roku:ecp\r\n'
          'location: http://192.168.1.50:8060/\r\n'
          'USN: uuid:roku:ecp:YH00C123456\r\n\r\n';
      expect(
        RokuController.ssdpHeader(response, 'LOCATION'),
        'http://192.168.1.50:8060/',
      );
      expect(RokuController.ssdpHeader(response, 'ST'), 'roku:ecp');
      expect(RokuController.ssdpHeader(response, 'missing'), isNull);
    });
  });
}
