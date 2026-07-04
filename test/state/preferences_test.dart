import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote/state/app_providers.dart';
import 'package:remote/state/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('haptics defaults on and persists across containers', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c1 = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c1.dispose);

    expect(c1.read(hapticsEnabledProvider), isTrue);
    await c1.read(hapticsEnabledProvider.notifier).set(false);
    expect(c1.read(hapticsEnabledProvider), isFalse);

    final c2 = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c2.dispose);
    expect(c2.read(hapticsEnabledProvider), isFalse);
  });

  test('animated background defaults on and toggles', () async {
    final c = await container();
    expect(c.read(animatedBackgroundProvider), isTrue);
    await c.read(animatedBackgroundProvider.notifier).toggle();
    expect(c.read(animatedBackgroundProvider), isFalse);
  });

  test('automatic dark mode defaults on; effective follows the clock', () async {
    final c = await container();
    expect(c.read(autoDarkModeProvider), isTrue);
    expect(
      c.read(effectiveDarkModeProvider),
      EffectiveDarkModeNotifier.isNight(DateTime.now()),
    );
  });

  test('with automatic off, effective mirrors the manual switch', () async {
    final c = await container();
    await c.read(autoDarkModeProvider.notifier).set(false);
    expect(c.read(effectiveDarkModeProvider), isFalse); // manual default off
    await c.read(darkModeProvider.notifier).set(true);
    expect(c.read(effectiveDarkModeProvider), isTrue);
  });

  test('night window: dark 7 PM – 7 AM local time', () {
    bool nightAt(int hour, [int minute = 0]) =>
        EffectiveDarkModeNotifier.isNight(DateTime(2026, 7, 2, hour, minute));
    expect(nightAt(19), isTrue); // 7 PM sharp
    expect(nightAt(23), isTrue);
    expect(nightAt(0), isTrue);
    expect(nightAt(6, 59), isTrue);
    expect(nightAt(7), isFalse); // 7 AM sharp
    expect(nightAt(12), isFalse);
    expect(nightAt(18, 59), isFalse);
  });

  test('nextBoundary is the upcoming 7 AM/7 PM flip', () {
    expect(
      EffectiveDarkModeNotifier.nextBoundary(DateTime(2026, 7, 2, 10)),
      DateTime(2026, 7, 2, 19), // daytime -> tonight 7 PM
    );
    expect(
      EffectiveDarkModeNotifier.nextBoundary(DateTime(2026, 7, 2, 21)),
      DateTime(2026, 7, 3, 7), // evening -> tomorrow 7 AM
    );
    expect(
      EffectiveDarkModeNotifier.nextBoundary(DateTime(2026, 7, 2, 3)),
      DateTime(2026, 7, 2, 7), // small hours -> this morning 7 AM
    );
  });
}
