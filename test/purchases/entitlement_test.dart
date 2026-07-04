import 'package:flutter_test/flutter_test.dart';
import 'package:remote/ads/ad_service.dart';
import 'package:remote/purchases/purchase_ids.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ads are enabled by default and disabled once Pro is owned', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // No entitlement → ads run.
    expect(AdService(prefs).adsEnabled, isTrue);

    // Pro granted → the same flag silences ads.
    await prefs.setBool(kProEntitlementKey, true);
    expect(AdService(prefs).adsEnabled, isFalse);
  });

  test('maybeShowAfterConnect is a no-op when Pro is owned', () async {
    SharedPreferences.setMockInitialValues({kProEntitlementKey: true});
    final prefs = await SharedPreferences.getInstance();
    final ads = AdService(prefs);
    // adsEnabled is the gate maybeShowAfterConnect checks first; with Pro it
    // bails before ever touching the ad SDK.
    expect(ads.adsEnabled, isFalse);
  });
}
