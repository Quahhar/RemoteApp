import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/controller_registry.dart';
import '../controllers/remote_controller.dart';
import '../models/device.dart';
import '../models/protocol_type.dart';
import '../persistence/device_store.dart';
import 'app_providers.dart';
import 'saved_devices_provider.dart';

/// The currently selected device (or null). Restored from persistence on start
/// but NOT auto-connected — call [ActiveDeviceNotifier.connect] (e.g. when the
/// Remote screen mounts) to establish the link.
final activeDeviceProvider =
    NotifierProvider<ActiveDeviceNotifier, Device?>(ActiveDeviceNotifier.new);

class ActiveDeviceNotifier extends Notifier<Device?> {
  ControllerRegistry get _registry => ref.read(controllerRegistryProvider);
  DeviceStore get _store => ref.read(deviceStoreProvider);

  @override
  Device? build() {
    final id = _store.loadActiveId();
    if (id == null) return null;
    return ref.read(savedDevicesProvider.notifier).byId(id);
  }

  /// Make [device] active and connect, persisting it only once the connection
  /// succeeds. Rethrows a [RemoteException] if the connection fails so the UI can
  /// show the message (and the device is *not* saved — no phantom entries).
  Future<void> select(Device device) async {
    // Always tear down the previous controller first — even when re-selecting the
    // same device — so a fresh connect() never orphans the old socket.
    final previous = state;
    if (previous != null) {
      await _registry.controllerFor(previous.protocol).disconnect();
    }
    state = device; // connect() reads state
    await connect(); // throws on failure → nothing below runs, nothing persisted
    // connect() already upserted the device with a fresh lastConnected on success.
    await _store.saveActiveId(device.id);
  }

  /// Connect (or reconnect) to the active device, updating its lastConnected
  /// timestamp on success. No-op when nothing is selected.
  Future<void> connect() async {
    final device = state;
    if (device == null) return;
    final controller = _registry.controllerFor(device.protocol);
    await controller.connect(device);
    // Persist a freshly-obtained pairing credential (LG/Samsung/Android TV) so
    // the next connect skips the on-TV prompt.
    final credential = controller.authToken;
    var updated = device.copyWith(lastConnected: DateTime.now());
    if (credential != null && credential != device.authToken) {
      updated = updated.copyWith(authToken: credential);
    }
    state = updated;
    await ref.read(savedDevicesProvider.notifier).upsert(updated);
  }

  /// Fallback when a TV's primary protocol won't connect: many TVs — including
  /// modern Hisense/VIDAA sets whose MQTT remote is firmware-locked — still
  /// expose an unauthenticated DLNA media renderer on the same host. Tries to
  /// bring that up for [origin]'s host; on success it becomes the active device
  /// (persisted, like [select]) and is returned, otherwise returns null and
  /// nothing changes. Never recurses: a DLNA [origin] is not retried.
  Future<Device?> connectViaDlnaFallback(Device origin) async {
    if (origin.protocol == ProtocolType.dlna) return null;
    final controller = _registry.controllerFor(ProtocolType.dlna);
    final candidate = Device(
      id: 'dlna-${origin.host}',
      name: origin.name,
      host: origin.host,
      protocol: ProtocolType.dlna,
    );
    try {
      await controller.connect(candidate);
    } on RemoteException {
      return null; // no usable renderer on this host
    }
    final previous = state;
    if (previous != null && previous.id != candidate.id) {
      await _registry.controllerFor(previous.protocol).disconnect();
    }
    final connected = candidate.copyWith(lastConnected: DateTime.now());
    state = connected;
    await _store.saveActiveId(connected.id);
    final saved = ref.read(savedDevicesProvider.notifier);
    // Replace, don't duplicate: the origin TV's native protocol just failed, so
    // drop its (now dead) saved entry in favour of this working Cast one.
    if (origin.id != candidate.id) {
      await saved.remove(origin.id);
    }
    await saved.upsert(connected);
    return connected;
  }

  /// Disconnect and clear the active selection.
  Future<void> clear() async {
    final device = state;
    if (device != null) {
      await _registry.controllerFor(device.protocol).disconnect();
    }
    state = null;
    await _store.saveActiveId(null);
  }
}

/// The [RemoteController] for the active device, or null when none is selected.
/// This is the single handle the UI uses to send keys / pointer input — it is
/// resolved purely from the active device's protocol, so widgets never name a
/// brand.
final activeControllerProvider = Provider<RemoteController?>((ref) {
  final device = ref.watch(activeDeviceProvider);
  if (device == null) return null;
  return ref.watch(controllerRegistryProvider).controllerFor(device.protocol);
});
