import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_providers.dart';

/// A persisted boolean preference (default true). Subclasses set the key.
abstract class _BoolPrefNotifier extends Notifier<bool> {
  String get key;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  bool build() => _prefs.getBool(key) ?? true;

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
