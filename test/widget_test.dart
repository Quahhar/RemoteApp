import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote/main.dart';
import 'package:remote/state/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('boots to the Remote tab with all destinations', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const RemoteApp(),
      ),
    );
    await tester.pump();

    // The Remote screen header from the mockup.
    expect(find.text('Remote Control'), findsOneWidget);

    // Frosted bottom-nav destinations are present.
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Touchpad'), findsOneWidget);
    expect(find.text('Keyboard'), findsOneWidget);

    // With nothing saved, the device card shows the empty state.
    expect(find.textContaining('No TV selected'), findsOneWidget);
  });
}
