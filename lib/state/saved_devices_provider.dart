import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../persistence/device_store.dart';
import 'app_providers.dart';

/// The user's saved devices, persisted via [DeviceStore]. Sorted most-recently
/// connected first for display.
final savedDevicesProvider =
    NotifierProvider<SavedDevicesNotifier, List<Device>>(
  SavedDevicesNotifier.new,
);

class SavedDevicesNotifier extends Notifier<List<Device>> {
  DeviceStore get _store => ref.read(deviceStoreProvider);

  @override
  List<Device> build() => _sorted(_store.loadDevices());

  /// Add a new device or replace an existing one with the same id, then persist.
  Future<void> upsert(Device device) async {
    final next = [...state];
    final index = next.indexWhere((d) => d.id == device.id);
    if (index >= 0) {
      next[index] = device;
    } else {
      next.add(device);
    }
    state = _sorted(next);
    await _store.saveDevices(state);
  }

  /// Remove the device with [id] and persist.
  Future<void> remove(String id) async {
    state = state.where((d) => d.id != id).toList(growable: false);
    await _store.saveDevices(state);
  }

  Device? byId(String id) {
    for (final device in state) {
      if (device.id == id) return device;
    }
    return null;
  }

  static List<Device> _sorted(List<Device> devices) {
    final list = [...devices];
    list.sort((a, b) {
      final at = a.lastConnected;
      final bt = b.lastConnected;
      if (at == null && bt == null) return a.name.compareTo(b.name);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return List.unmodifiable(list);
  }
}
