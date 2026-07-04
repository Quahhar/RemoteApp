import 'package:flutter_test/flutter_test.dart';
import 'package:remote/ads/ad_config.dart';
import 'package:remote/ads/ad_gate.dart';

void main() {
  group('shouldShowAd', () {
    final now = DateTime(2026, 6, 27, 12, 0, 0);

    test('shows when no ad has ever been shown', () {
      expect(shouldShowAd(null, now), isTrue);
    });

    test('blocks within the minimum gap', () {
      final justNow = now.subtract(const Duration(minutes: 2));
      expect(shouldShowAd(justNow, now), isFalse);
    });

    test('allows once the gap has elapsed', () {
      final old = now.subtract(AdConfig.minGapBetweenAds);
      expect(shouldShowAd(old, now), isTrue);
    });

    test('allows well past the gap (e.g. after a long background)', () {
      final longAgo = now.subtract(const Duration(hours: 3));
      expect(shouldShowAd(longAgo, now), isTrue);
    });

    test('boundary: exactly one second short still blocks', () {
      final almost =
          now.subtract(AdConfig.minGapBetweenAds - const Duration(seconds: 1));
      expect(shouldShowAd(almost, now), isFalse);
    });
  });
}
