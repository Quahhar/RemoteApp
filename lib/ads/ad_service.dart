import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../purchases/purchase_ids.dart';
import '../state/app_providers.dart';
import 'ad_config.dart';
import 'ad_gate.dart';

/// App-wide ad service: one interstitial, shown only at a natural break (after a
/// successful TV connect), always behind a short courtesy countdown, capped to
/// one per [AdConfig.minGapBetweenAds]. No banners.
///
/// The countdown lives **here**, not in any widget: it drives [countdown] (a
/// plain notifier the power button paints as a number) and shows the ad itself
/// when it reaches zero. Because an interstitial presents full-screen without a
/// [BuildContext], the countdown keeps ticking — and the ad still shows — even
/// if the user switches tabs while it runs.
///
/// Decoupled on purpose: the whole feature lives under `lib/ads/`. The UI only
/// touches it in three spots — [init] (once at startup), [maybeShowAfterConnect]
/// (after a connect) and [countdown] (watched by the power button) — so the
/// rest of the app can be redesigned freely.
final adServiceProvider = Provider<AdService>(
  (ref) => AdService(ref.read(sharedPreferencesProvider)),
);

class AdService {
  AdService(this._prefs);

  final SharedPreferences _prefs;

  static const String _lastShownKey = 'ads_last_shown_epoch_ms';

  /// Live courtesy countdown before the next interstitial: `null` when idle,
  /// else the remaining whole seconds. The power button watches this and paints
  /// the number in place of its glyph. Owned here (not by any widget) so it
  /// survives tab switches.
  final ValueNotifier<int?> countdown = ValueNotifier<int?>(null);

  /// Ads run unless the user owns Pro. Read from the persisted entitlement flag
  /// (set by the purchase flow) so it needs no dependency on the purchase layer
  /// and goes quiet the instant Pro is granted.
  bool get adsEnabled => !(_prefs.getBool(kProEntitlementKey) ?? false);

  InterstitialAd? _interstitial;
  bool _loading = false;
  bool _initialised = false;
  Timer? _countdownTimer;

  DateTime? get _lastShown {
    final ms = _prefs.getInt(_lastShownKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Initialise the SDK (best-effort consent first), then preload. Safe to call
  /// more than once. Never throws.
  Future<void> init() async {
    if (_initialised || !adsEnabled) return;
    _initialised = true;
    try {
      await _requestConsent();
      await MobileAds.instance.initialize();
      _loadInterstitial();
    } catch (_) {
      // Ads are best-effort; the app must never fail to start because of them.
    }
  }

  /// If due and an ad is ready, start the courtesy countdown; the ad presents
  /// itself when it hits zero. Does nothing (and just preloads for next time)
  /// when an ad isn't ready, so the user never sees a countdown that leads to no
  /// ad. Fire-and-forget: needs no [BuildContext] and is safe to call from
  /// anywhere.
  void maybeShowAfterConnect() {
    if (!adsEnabled) return;
    if (_countdownTimer != null) return; // already counting down
    if (!shouldShowAd(_lastShown, DateTime.now())) return;

    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial(); // not ready — prepare for next time, show nothing now
      return;
    }
    _startCountdown(ad);
  }

  void _startCountdown(InterstitialAd ad) {
    var remaining = AdConfig.countdown.inSeconds;
    countdown.value = remaining;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining -= 1;
      if (remaining <= 0) {
        timer.cancel();
        _countdownTimer = null;
        countdown.value = null;
        _show(ad);
      } else {
        countdown.value = remaining;
      }
    });
  }

  Future<void> _show(InterstitialAd ad) async {
    // The ad may have been disposed/replaced while the countdown ran.
    if (_interstitial != ad) return;

    // Record the show time up front (wall-clock cap) and hand off the ad.
    await _prefs.setInt(_lastShownKey, DateTime.now().millisecondsSinceEpoch);
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _loadInterstitial();
      },
    );
    await ad.show();
  }

  void _loadInterstitial() {
    if (_loading || _interstitial != null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loading = false;
        },
        onAdFailedToLoad: (_) {
          _interstitial = null;
          _loading = false;
        },
      ),
    );
  }

  /// Best-effort UMP consent (GDPR/EEA). Never blocks ads for long or throws.
  Future<void> _requestConsent() async {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        } catch (_) {
          // ignore — proceed with non-personalised ads
        }
        finish();
      },
      (_) => finish(),
    );
    return done.future
        .timeout(const Duration(seconds: 5), onTimeout: finish);
  }
}
