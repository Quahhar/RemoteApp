import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/lan_scan.dart';
import 'package:remote/models/protocol_type.dart';

void main() {
  group('TV discovery port map', () {
    test('every protocol is auto-discoverable by its default port', () {
      // Guard: adding a ProtocolType without a discovery port means new TVs of
      // that brand would never appear in Scan. If this fails, add the port to
      // kTvDiscoveryPorts.
      for (final p in ProtocolType.values) {
        expect(
          kTvDiscoveryPorts.containsKey(p.defaultPort),
          isTrue,
          reason: '${p.name} default port ${p.defaultPort} is not probed',
        );
      }
    });

    test('signature ports map to the expected protocol', () {
      expect(kTvDiscoveryPorts[8060], ProtocolType.roku);
      expect(kTvDiscoveryPorts[3000], ProtocolType.webos);
      expect(kTvDiscoveryPorts[8002], ProtocolType.tizen);
      expect(kTvDiscoveryPorts[6467], ProtocolType.androidtv);
      expect(kTvDiscoveryPorts[36669], ProtocolType.vidaa);
    });

    test('covers all five supported protocols', () {
      expect(
        kTvDiscoveryPorts.values.toSet(),
        containsAll(<ProtocolType>[
          ProtocolType.roku,
          ProtocolType.webos,
          ProtocolType.tizen,
          ProtocolType.androidtv,
          ProtocolType.vidaa,
        ]),
      );
    });
  });
}
