import 'ad_config.dart';

/// Whether an ad is allowed to show now, given when the last one was shown.
///
/// Pure (no SDK, no I/O) so it's trivially unit-testable. The comparison is
/// against real wall-clock time from a persisted timestamp, so the gap keeps
/// counting while the app is backgrounded, the screen is off, or the app is
/// killed.
bool shouldShowAd(
  DateTime? lastShown,
  DateTime now, {
  Duration minGap = AdConfig.minGapBetweenAds,
}) {
  if (lastShown == null) return true;
  return now.difference(lastShown) >= minGap;
}
