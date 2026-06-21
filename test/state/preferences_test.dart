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
}
