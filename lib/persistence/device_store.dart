import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';

/// Thin persistence layer over shared_preferences: the saved-device list and
/// the active-device selection. Corrupt entries are skipped rather than
/// crashing the app on load.
class DeviceStore {
  DeviceStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _devicesKey = 'saved_devices';
  static const String _activeKey = 'active_device_id';

  List<Device> loadDevices() {
    final raw = _prefs.getStringList(_devicesKey) ?? const [];
    final devices = <Device>[];
    for (final entry in raw) {
      try {
        devices.add(Device.fromJson(jsonDecode(entry) as Map<String, dynamic>));
      } catch (_) {
        // Skip a corrupt/incompatible entry instead of failing the whole load.
      }
    }
    return devices;
  }

  Future<void> saveDevices(List<Device> devices) {
    final raw = devices.map((d) => jsonEncode(d.toJson())).toList();
    return _prefs.setStringList(_devicesKey, raw);
  }

  String? loadActiveId() => _prefs.getString(_activeKey);

  Future<void> saveActiveId(String? id) =>
      id == null ? _prefs.remove(_activeKey) : _prefs.setString(_activeKey, id);
}
