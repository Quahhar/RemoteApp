import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/controller_registry.dart';
import 'package:remote/controllers/remote_controller.dart';
import 'package:remote/models/capabilities.dart';
import 'package:remote/models/connection_status.dart';
import 'package:remote/models/device.dart';
import 'package:remote/models/protocol_type.dart';
import 'package:remote/models/remote_key.dart';
import 'package:remote/persistence/device_store.dart';
import 'package:remote/state/active_device_provider.dart';
import 'package:remote/state/app_providers.dart';
import 'package:remote/state/discovery_provider.dart';
import 'package:remote/state/saved_devices_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _devA = Device(
  id: 'roku-A',
  name: 'Bedroom',
  host: '10.0.0.5',
  protocol: ProtocolType.roku,
);
const _devB = Device(
  id: 'roku-B',
  name: 'Kitchen',
  host: '10.0.0.6',
  protocol: ProtocolType.roku,
);

/// In-memory controller so state tests never touch the network.
class FakeController extends RemoteController {
  FakeController({this.emit = const [], this.connectError});

  final List<Device> emit;
  final RemoteException? connectError;
  final List<RemoteKey> sentKeys = [];
  int connectCount = 0;
  int disconnectCount = 0;

  @override
  ProtocolType get protocol => ProtocolType.roku;

  @override
  Capabilities get capabilities => const Capabilities();

  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) async* {
    for (final d in emit) {
      yield d;
    }
  }

  @override
  Future<void> connect(Device device) async {
    connectCount++;
    emitStatus(ConnectionStatus.connecting);
    if (connectError != null) {
      emitStatus(ConnectionStatus.error);
      throw connectError!;
    }
    emitStatus(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    emitStatus(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendKey(RemoteKey key) async => sentKeys.add(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  ProviderContainer makeContainer(
    SharedPreferences prefs, {
    ControllerRegistry? registry,
  }) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (registry != null)
          controllerRegistryProvider.overrideWithValue(registry),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('Device JSON round-trips (including auth token)', () {
    const d = Device(
      id: 'x',
      name: 'Name',
      host: '1.2.3.4',
      protocol: ProtocolType.webos,
      port: 3001,
      authToken: 'client-key-123',
    );
    final back = Device.fromJson(d.toJson());
    expect(back, d); // equality is by id
    expect(back.host, '1.2.3.4');
    expect(back.protocol, ProtocolType.webos);
    expect(back.port, 3001);
    expect(back.authToken, 'client-key-123');
    expect(back.isPaired, isTrue);
  });

  test('DeviceStore round-trips devices and active id', () async {
    final prefs = await freshPrefs();
    final store = DeviceStore(prefs);
    expect(store.loadDevices(), isEmpty);
    expect(store.loadActiveId(), isNull);

    await store.saveDevices([_devA, _devB]);
    expect(store.loadDevices().map((d) => d.id), [_devA.id, _devB.id]);

    await store.saveActiveId(_devA.id);
    expect(store.loadActiveId(), _devA.id);
    await store.saveActiveId(null);
    expect(store.loadActiveId(), isNull);
  });

  test('savedDevices upsert replaces by id and persists across containers',
      () async {
    final prefs = await freshPrefs();
    final c1 = makeContainer(prefs);
    final notifier = c1.read(savedDevicesProvider.notifier);
    await notifier.upsert(_devA);
    await notifier.upsert(_devB);
    await notifier.upsert(_devA.copyWith(name: 'Bedroom TV')); // replace, not add
    expect(c1.read(savedDevicesProvider), hasLength(2));
    expect(c1.read(savedDevicesProvider.notifier).byId('roku-A')?.name,
        'Bedroom TV');

    // A new container backed by the same prefs sees the persisted devices.
    final c2 = makeContainer(prefs);
    expect(c2.read(savedDevicesProvider), hasLength(2));

    await c2.read(savedDevicesProvider.notifier).remove('roku-A');
    expect(c2.read(savedDevicesProvider).map((d) => d.id), ['roku-B']);
  });

  test('discovery fan-out accumulates and de-dupes by id', () async {
    final prefs = await freshPrefs();
    final fake = FakeController(emit: const [_devA, _devA, _devB]);
    final registry = ControllerRegistry({ProtocolType.roku: () => fake});
    final c = makeContainer(prefs, registry: registry);

    await c.read(discoveryProvider.notifier).scan(timeout: const Duration(seconds: 1));
    await pumpEventQueue();

    final found = c.read(discoveryProvider);
    expect(found.scanning, isFalse);
    expect(found.devices.map((d) => d.id), unorderedEquals(['roku-A', 'roku-B']));
  });

  test('select() saves, persists active id, and connects via the controller',
      () async {
    final prefs = await freshPrefs();
    final fake = FakeController();
    final registry = ControllerRegistry({ProtocolType.roku: () => fake});
    final c = makeContainer(prefs, registry: registry);

    await c.read(activeDeviceProvider.notifier).select(_devA);

    expect(c.read(activeDeviceProvider)?.id, 'roku-A');
    expect(fake.status, ConnectionStatus.connected);
    expect(prefs.getString('active_device_id'), 'roku-A');
    expect(c.read(savedDevicesProvider).map((d) => d.id), contains('roku-A'));

    // The UI talks only to the active controller.
    await c.read(activeControllerProvider)!.sendKey(RemoteKey.ok);
    expect(fake.sentKeys, [RemoteKey.ok]);
  });

  test('select() surfaces a connect failure as a RemoteException', () async {
    final prefs = await freshPrefs();
    final fake = FakeController(connectError: const NotReachableException());
    final registry = ControllerRegistry({ProtocolType.roku: () => fake});
    final c = makeContainer(prefs, registry: registry);

    await expectLater(
      c.read(activeDeviceProvider.notifier).select(_devA),
      throwsA(isA<NotReachableException>()),
    );
    expect(fake.status, ConnectionStatus.error);
  });

  test('re-selecting the active device disconnects before reconnecting (no leak)',
      () async {
    final prefs = await freshPrefs();
    final fake = FakeController();
    final registry = ControllerRegistry({ProtocolType.roku: () => fake});
    final c = makeContainer(prefs, registry: registry);

    final notifier = c.read(activeDeviceProvider.notifier);
    await notifier.select(_devA); // first connect, nothing to disconnect
    await notifier.select(_devA); // re-select the same device

    expect(fake.connectCount, 2);
    expect(fake.disconnectCount, 1, reason: 'old session torn down before reconnect');
    expect(fake.status, ConnectionStatus.connected);
  });

  test('a failed select() does not persist a phantom device', () async {
    final prefs = await freshPrefs();
    final fake = FakeController(connectError: const NotReachableException());
    final registry = ControllerRegistry({ProtocolType.roku: () => fake});
    final c = makeContainer(prefs, registry: registry);

    await expectLater(
      c.read(activeDeviceProvider.notifier).select(_devA),
      throwsA(isA<NotReachableException>()),
    );
    expect(c.read(savedDevicesProvider), isEmpty);
    expect(prefs.getString('active_device_id'), isNull);
  });

  group('connectViaDlnaFallback()', () {
    const vidaaDev = Device(
      id: 'vidaa-10.0.0.9',
      name: 'Living Room TV',
      host: '10.0.0.9',
      protocol: ProtocolType.vidaa,
    );

    test('brings up DLNA on the same host and makes it active', () async {
      final prefs = await freshPrefs();
      final dlna = FakeController();
      final registry = ControllerRegistry({ProtocolType.dlna: () => dlna});
      final c = makeContainer(prefs, registry: registry);

      final result = await c
          .read(activeDeviceProvider.notifier)
          .connectViaDlnaFallback(vidaaDev);

      expect(result, isNotNull);
      expect(result!.protocol, ProtocolType.dlna);
      expect(result.host, '10.0.0.9');
      expect(c.read(activeDeviceProvider)?.id, 'dlna-10.0.0.9');
      expect(c.read(activeDeviceProvider)?.protocol, ProtocolType.dlna);
      expect(dlna.status, ConnectionStatus.connected);
      expect(prefs.getString('active_device_id'), 'dlna-10.0.0.9');
      expect(c.read(savedDevicesProvider).map((d) => d.id),
          contains('dlna-10.0.0.9'));
    });

    test('replaces the dead native entry instead of duplicating it', () async {
      final prefs = await freshPrefs();
      final dlna = FakeController();
      final registry = ControllerRegistry({ProtocolType.dlna: () => dlna});
      final c = makeContainer(prefs, registry: registry);

      // The TV was previously saved under its (now failing) native protocol.
      await c.read(savedDevicesProvider.notifier).upsert(vidaaDev);

      await c
          .read(activeDeviceProvider.notifier)
          .connectViaDlnaFallback(vidaaDev);

      final ids = c.read(savedDevicesProvider).map((d) => d.id).toList();
      expect(ids, contains('dlna-10.0.0.9'));
      expect(ids, isNot(contains('vidaa-10.0.0.9')),
          reason: 'one card per TV — the dead native entry is removed');
    });

    test('returns null and changes nothing when no renderer is present',
        () async {
      final prefs = await freshPrefs();
      final dlna = FakeController(connectError: const NotReachableException());
      final registry = ControllerRegistry({ProtocolType.dlna: () => dlna});
      final c = makeContainer(prefs, registry: registry);

      final result = await c
          .read(activeDeviceProvider.notifier)
          .connectViaDlnaFallback(vidaaDev);

      expect(result, isNull);
      expect(c.read(activeDeviceProvider), isNull);
      expect(prefs.getString('active_device_id'), isNull);
    });

    test('does not retry a DLNA origin (no recursion)', () async {
      final prefs = await freshPrefs();
      final dlna = FakeController(connectError: const NotReachableException());
      final registry = ControllerRegistry({ProtocolType.dlna: () => dlna});
      final c = makeContainer(prefs, registry: registry);

      const dlnaOrigin = Device(
        id: 'dlna-10.0.0.9',
        name: 'X',
        host: '10.0.0.9',
        protocol: ProtocolType.dlna,
      );

      final result = await c
          .read(activeDeviceProvider.notifier)
          .connectViaDlnaFallback(dlnaOrigin);

      expect(result, isNull);
      expect(dlna.status, ConnectionStatus.disconnected); // never attempted
    });
  });
}
