import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/controller_registry.dart';
import '../controllers/remote_controller.dart';
import '../models/device.dart';
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

  /// Persist [device] to saved devices, make it active, and connect. Rethrows a
  /// [RemoteException] if the connection fails so the UI can show the message.
  Future<void> select(Device device) async {
    await ref.read(savedDevicesProvider.notifier).upsert(device);
    final previous = state;
    if (previous != null && previous.id != device.id) {
      await _registry.controllerFor(previous.protocol).disconnect();
    }
    state = device;
    await _store.saveActiveId(device.id);
    await connect();
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
