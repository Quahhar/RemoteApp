import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/remote_controller.dart';
import 'package:remote/models/capabilities.dart';
import 'package:remote/models/connection_status.dart';
import 'package:remote/models/device.dart';
import 'package:remote/models/protocol_type.dart';
import 'package:remote/models/remote_key.dart';
import 'package:remote/purchases/purchase_controller.dart';
import 'package:remote/state/active_device_provider.dart';
import 'package:remote/state/app_providers.dart';
import 'package:remote/ui/screens/remote_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeController extends RemoteController {
  FakeController(this._capabilities);
  final Capabilities _capabilities;
  final List<RemoteKey> sentKeys = [];

  @override
  ProtocolType get protocol => ProtocolType.dlna;

  @override
  Capabilities get capabilities => _capabilities;

  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) =>
      const Stream<Device>.empty();

  @override
  Future<void> connect(Device device) async =>
      emitStatus(ConnectionStatus.connected);

  @override
  Future<void> disconnect() async => emitStatus(ConnectionStatus.disconnected);

  @override
  Future<void> sendKey(RemoteKey key) async => sentKeys.add(key);
}

Future<FakeController> _pump(WidgetTester tester, Capabilities caps) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final fake = FakeController(caps);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activeControllerProvider.overrideWithValue(fake),
        // Pro so the header UpgradeButton hides and the More path stays inert.
        isProProvider.overrideWithValue(true),
      ],
      child: const MaterialApp(home: Scaffold(body: RemoteScreen())),
    ),
  );
  await tester.pump();
  return fake;
}

void main() {
  group('Remote screen capability gating', () {
    testWidgets('media-renderer (no navigation) disables OK while volume '
        'still sends', (tester) async {
      final fake = await _pump(
        tester,
        const Capabilities(
          supportsNavigation: false,
          supportsPower: false,
          channelButtons: false,
        ),
      );

      // OK is greyed out (no gesture handler): tapping it is expected to miss
      // and sends nothing.
      await tester.ensureVisible(find.text('OK'));
      await tester.tap(find.text('OK'), warnIfMissed: false);
      await tester.pump();
      expect(fake.sentKeys, isNot(contains(RemoteKey.ok)));

      // The VOL rocker stays live on a renderer-only link (it isn't gated by
      // navigation). (Don't pumpAndSettle: the status dot can pulse.)
      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(fake.sentKeys, contains(RemoteKey.volumeUp));
    });

    testWidgets('full remote shows no hint and OK works', (tester) async {
      final fake = await _pump(tester, const Capabilities());

      expect(find.textContaining('Connected over Cast'), findsNothing);

      await tester.ensureVisible(find.text('OK'));
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(fake.sentKeys, contains(RemoteKey.ok));
    });
  });
}
