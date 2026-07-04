import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/lan_scan.dart';
import 'package:remote/models/protocol_type.dart';

void main() {
  group('TV discovery port map', () {
    test('every protocol is auto-discoverable by its default port', () {
      // Guard: adding a ProtocolType without a discovery port means new TVs of
      // that brand would never appear in Scan. If this fails, add the port to
      // kTvDiscoveryPorts.
      //
      // `dlna` is the deliberate exception: it runs its OWN discovery
      // (DlnaController.discover — SSDP MediaRenderer plus a targeted 18400
      // scan) instead of joining the shared port map. The shared scan emits only
      // the first open port per host, so listing 18400 there would make a VIDAA
      // TV (36669 *and* 18400 open) flip nondeterministically between its locked
      // MQTT entry and its working DLNA entry. Keeping DLNA separate lets the
      // same TV surface reliably under both protocols.
      for (final p in ProtocolType.values) {
        if (p == ProtocolType.dlna) continue;
        expect(
          kTvDiscoveryPorts.containsKey(p.defaultPort),
          isTrue,
          reason: '${p.name} default port ${p.defaultPort} is not probed',
        );
      }
    });

    test('dlna is intentionally excluded from the shared port map', () {
      expect(kTvDiscoveryPorts.values, isNot(contains(ProtocolType.dlna)));
    });

    test('signature ports map to the expected protocol', () {
      expect(kTvDiscoveryPorts[8060], ProtocolType.roku);
      expect(kTvDiscoveryPorts[3000], ProtocolType.webos);
      expect(kTvDiscoveryPorts[8002], ProtocolType.tizen);
      expect(kTvDiscoveryPorts[6466], ProtocolType.androidtv);
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
