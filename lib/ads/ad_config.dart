import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;

/// Ad unit ids.
///
/// Release builds serve the app's **real** AdMob interstitials. Debug builds
/// (running from your IDE / `flutter run`) automatically serve Google's test
/// ads instead, so you can tap them freely while developing without risking an
/// invalid-traffic ban. The matching app ids live in AndroidManifest.xml and
/// ios/Runner/Info.plist.
class AdConfig {
  const AdConfig._();

  // Real interstitial unit ids (used in release builds).
  static const String _interstitialAndroid =
      'ca-app-pub-6204416864963157/8992249376';
  static const String _interstitialIos =
      'ca-app-pub-6204416864963157/4125111673';

  // Google's official test interstitial unit ids (used in debug builds). These
  // always serve test ads, earn nothing, and are safe to tap.
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  /// The interstitial unit id for the current platform. Test ids in debug
  /// builds, real ids in release builds.
  static String get interstitialUnitId {
    if (kDebugMode) {
      return Platform.isIOS ? _testInterstitialIos : _testInterstitialAndroid;
    }
    return Platform.isIOS ? _interstitialIos : _interstitialAndroid;
  }

  /// Minimum gap between two ads. The cap is measured in wall-clock time from a
  /// persisted timestamp, so it keeps counting while the app is backgrounded,
  /// the screen is off, or the app is killed.
  static const Duration minGapBetweenAds = Duration(minutes: 5);

  /// How long the courtesy heads-up counts down before the ad shows.
  static const Duration countdown = Duration(seconds: 3);
}
