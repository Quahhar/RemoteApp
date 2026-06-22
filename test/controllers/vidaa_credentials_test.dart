import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/vidaa_credentials.dart';

void main() {
  group('VIDAA dynamic credentials', () {
    // Known-good vector captured from the official VIDAA app via logcat
    // (pyvidaa credentials.py __main__). If the port drifts, this fails.
    test('matches the reference vector exactly', () {
      final c = generateVidaaCredentials(
        uuid: '56:b8:88:4e:f7:19',
        timestamp: 1766974704,
      );
      expect(c.clientId, '56:b8:88:4e:f7:19\$his\$256DBF_vidaacommon_001');
      expect(c.username, 'his\$6239759786168176024');
      expect(c.password, 'C3BA44782E18ABF4892AC44D79A622D2');
    });

    // Captured live from the working VIDAA app's own log (brand ksj, the user's
    // Kenstar TV). Proves the algorithm + brand are exactly right for this TV.
    test('matches the live ksj app capture exactly', () {
      final c = generateVidaaCredentials(
        uuid: '00:08:22:19:4F:A4',
        brand: 'ksj',
        timestamp: 1782115664,
      );
      expect(c.clientId, '00:08:22:19:4F:A4\$ksj\$BA7990_vidaacommon_001');
      expect(c.username, 'ksj\$6239759786149889080');
      expect(c.password, 'F5D274ADADE7E78EB71058B06537BBCE');
    });

    test('an access token replaces the computed password', () {
      final c = generateVidaaCredentials(
        uuid: '56:b8:88:4e:f7:19',
        timestamp: 1766974704,
        accessToken: 'tok-123',
      );
      // client_id + username are unchanged; password is the token.
      expect(c.clientId, '56:b8:88:4e:f7:19\$his\$256DBF_vidaacommon_001');
      expect(c.username, 'his\$6239759786168176024');
      expect(c.password, 'tok-123');
    });

    test('different timestamps yield different username + password', () {
      final a = generateVidaaCredentials(uuid: 'AA:BB:CC:DD:EE:FF', timestamp: 1000);
      final b = generateVidaaCredentials(uuid: 'AA:BB:CC:DD:EE:FF', timestamp: 2000);
      expect(a.username, isNot(b.username));
      expect(a.password, isNot(b.password));
      expect(a.clientId, b.clientId); // client_id is time-independent
    });
  });
}
