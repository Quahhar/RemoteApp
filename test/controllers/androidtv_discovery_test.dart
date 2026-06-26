import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/androidtv_controller.dart';

void main() {
  group('AndroidTvController.instanceName', () {
    test('extracts a plain friendly name', () {
      expect(
        AndroidTvController.instanceName(
            'Living Room TV._androidtvremote2._tcp.local'),
        'Living Room TV',
      );
    });

    test('tolerates a trailing dot (FQDN form)', () {
      expect(
        AndroidTvController.instanceName(
            'Shield._androidtvremote2._tcp.local.'),
        'Shield',
      );
    });

    test('unescapes a literal dot (\\.)', () {
      expect(
        AndroidTvController.instanceName(
            r'Bob\.s TV._androidtvremote2._tcp.local'),
        'Bob.s TV',
      );
    });

    test('unescapes a decimal escape (\\032 = space)', () {
      expect(
        AndroidTvController.instanceName(
            r'Living\032Room._androidtvremote2._tcp.local'),
        'Living Room',
      );
    });

    test('unescapes a literal backslash (\\\\)', () {
      expect(
        AndroidTvController.instanceName(
            r'A\\B._androidtvremote2._tcp.local'),
        r'A\B',
      );
    });

    test('returns empty string for a non-matching service domain', () {
      expect(AndroidTvController.instanceName('printer._ipp._tcp.local'), '');
      expect(AndroidTvController.instanceName('nonsense'), '');
    });
  });
}
