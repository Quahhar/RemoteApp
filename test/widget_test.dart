import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/controller_registry.dart';
import 'package:remote/controllers/remote_controller.dart';
import 'package:remote/main.dart';
import 'package:remote/models/capabilities.dart';
import 'package:remote/models/device.dart';
import 'package:remote/models/protocol_type.dart';
import 'package:remote/models/remote_key.dart';
import 'package:remote/state/app_providers.dart';
import 'package:remote/state/navigation_provider.dart';
import 'package:remote/ui/home_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake controller whose discovery emits nothing, so the auto-scan triggered by
/// the no-device flow completes immediately without opening real sockets.
class _SilentController extends RemoteController {
  @override
  ProtocolType get protocol => ProtocolType.roku;
  @override
  Capabilities get capabilities => const Capabilities();
  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) =>
      const Stream<Device>.empty();
  @override
  Future<void> connect(Device device) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> sendKey(RemoteKey key) async {}
}

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

    // The shared header from the mockups.
    expect(find.text('Remote Control'), findsOneWidget);

    // Frosted bottom-nav destinations are present (Remote/Touchpad/Devices).
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Touchpad'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);

    // With nothing saved, the device card shows the empty state.
    expect(find.textContaining('No TV selected'), findsOneWidget);
  });

  testWidgets('pressing a control with no device jumps to Devices and scans',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = ControllerRegistry({ProtocolType.roku: _SilentController.new});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          controllerRegistryProvider.overrideWithValue(registry),
        ],
        child: const RemoteApp(),
      ),
    );
    await tester.pump();

    // On the Remote tab, no device is connected. Tap OK.
    await tester.tap(find.text('OK'));
    await tester.pump(); // run the handler
    await tester.pump(); // settle the tab switch + snackbar

    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    expect(container.read(selectedTabProvider), HomeTab.devices);
    expect(find.textContaining('No device connected'), findsOneWidget);
    // The Devices tab is now showing (its manual-add FAB is on screen).
    expect(find.text('Add manually'), findsOneWidget);
  });
}
