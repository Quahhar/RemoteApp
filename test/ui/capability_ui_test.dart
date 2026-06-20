import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/remote_controller.dart';
import 'package:remote/models/capabilities.dart';
import 'package:remote/models/connection_status.dart';
import 'package:remote/models/device.dart';
import 'package:remote/models/protocol_type.dart';
import 'package:remote/models/remote_key.dart';
import 'package:remote/state/active_device_provider.dart';
import 'package:remote/ui/screens/touchpad_screen.dart';

class FakeController extends RemoteController {
  FakeController(this._capabilities);
  final Capabilities _capabilities;

  @override
  ProtocolType get protocol => ProtocolType.roku;

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
  Future<void> sendKey(RemoteKey key) async {}
}

Future<void> _pump(WidgetTester tester, Capabilities caps) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeControllerProvider.overrideWithValue(FakeController(caps)),
      ],
      child: const MaterialApp(home: Scaffold(body: TouchpadScreen())),
    ),
  );
}

void main() {
  group('Touchpad send bar gating', () {
    testWidgets('shows a clear message when text input is unsupported',
        (tester) async {
      await _pump(tester, const Capabilities(supportsTextInput: false));
      await tester.pump();
      expect(
        find.text('Keyboard not supported on this device'),
        findsOneWidget,
      );
    });

    testWidgets('is ready to type when text input is supported',
        (tester) async {
      await _pump(tester, const Capabilities(supportsTextInput: true));
      await tester.pump();
      expect(find.text('Type to send to TV'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('Touchpad surface gating', () {
    testWidgets('pointer surface when the controller supports a pointer',
        (tester) async {
      await _pump(tester, const Capabilities(supportsPointer: true));
      await tester.pump();
      expect(find.text('TOUCHPAD AREA'), findsOneWidget);
    });

    testWidgets('swipe fallback when the controller has no pointer',
        (tester) async {
      await _pump(tester, const Capabilities(supportsPointer: false));
      await tester.pump();
      expect(find.text('SWIPE TO NAVIGATE'), findsOneWidget);
    });
  });
}
