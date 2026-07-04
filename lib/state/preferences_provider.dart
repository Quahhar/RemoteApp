import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_providers.dart';

/// A persisted boolean preference. Subclasses set the key (and the default,
/// which is `true` unless overridden).
abstract class _BoolPrefNotifier extends Notifier<bool> {
  String get key;

  bool get defaultValue => true;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  bool build() => _prefs.getBool(key) ?? defaultValue;

  Future<void> set(bool value) async {
    state = value;
    await _prefs.setBool(key, value);
  }

  Future<void> toggle() => set(!state);
}

/// Haptic feedback on button presses (default on).
final hapticsEnabledProvider =
    NotifierProvider<HapticsNotifier, bool>(HapticsNotifier.new);

class HapticsNotifier extends _BoolPrefNotifier {
  @override
  String get key => 'pref_haptics_enabled';
}

/// Slow "lava lamp" animated background vs. a static gradient (default on).
final animatedBackgroundProvider =
    NotifierProvider<AnimatedBackgroundNotifier, bool>(
  AnimatedBackgroundNotifier.new,
);

class AnimatedBackgroundNotifier extends _BoolPrefNotifier {
  @override
  String get key => 'pref_animated_background';
}

/// Dark colour palette instead of the light paper one (default off).
final darkModeProvider =
    NotifierProvider<DarkModeNotifier, bool>(DarkModeNotifier.new);

class DarkModeNotifier extends _BoolPrefNotifier {
  @override
  String get key => 'pref_dark_mode';

  @override
  bool get defaultValue => false;
}

/// Follow the local clock instead of the manual dark-mode switch (default on):
/// dark between [nightStartHour] and [nightEndHour]. Flipping the manual
/// switch in settings turns this off.
final autoDarkModeProvider =
    NotifierProvider<AutoDarkModeNotifier, bool>(AutoDarkModeNotifier.new);

class AutoDarkModeNotifier extends _BoolPrefNotifier {
  @override
  String get key => 'pref_auto_dark_mode';
}

/// Whether the dark palette is active *right now*: the time-based schedule
/// while [autoDarkModeProvider] is on, otherwise the manual switch. This is
/// the provider the UI watches; a timer re-evaluates it at the next 7 AM/7 PM
/// boundary so an open app flips by itself.
final effectiveDarkModeProvider =
    NotifierProvider<EffectiveDarkModeNotifier, bool>(
  EffectiveDarkModeNotifier.new,
);

class EffectiveDarkModeNotifier extends Notifier<bool> {
  /// Dark from 7 PM through 7 AM local time.
  static const int nightStartHour = 19;
  static const int nightEndHour = 7;

  static bool isNight(DateTime now) =>
      now.hour >= nightStartHour || now.hour < nightEndHour;

  /// The next moment the schedule changes state after [now].
  static DateTime nextBoundary(DateTime now) {
    final boundaryHour = isNight(now) ? nightEndHour : nightStartHour;
    var boundary = DateTime(now.year, now.month, now.day, boundaryHour);
    if (!boundary.isAfter(now)) {
      boundary = DateTime(now.year, now.month, now.day + 1, boundaryHour);
    }
    return boundary;
  }

  @override
  bool build() {
    final auto = ref.watch(autoDarkModeProvider);
    final manual = ref.watch(darkModeProvider);
    if (!auto) return manual;

    final now = DateTime.now();
    // A second past the boundary so the re-check lands on the far side even
    // if the timer fires marginally early.
    final timer = Timer(
      nextBoundary(now).difference(now) + const Duration(seconds: 1),
      () => ref.invalidateSelf(),
    );
    ref.onDispose(timer.cancel);
    return isNight(now);
  }
}
