import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the app-global client identity used to talk to Hisense/VIDAA TVs.
///
/// The VIDAA MQTT remote keys its authorization to the client's `device_topic`
/// (`<MAC>$normal`). We generate one stable pseudo-MAC per install and reuse it
/// for every VIDAA TV, so each TV remembers the 4-digit pairing across sessions.
/// The MAC is an identity string only — VIDAA does not validate its format.
class VidaaIdentityStore {
  VidaaIdentityStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _macKey = 'vidaa_client_mac';

  String? load() => _prefs.getString(_macKey);

  /// Return the stored pseudo-MAC, generating and persisting one if absent.
  Future<String> ensure() async {
    final existing = load();
    if (existing != null) return existing;
    final mac = _generateMac();
    await _prefs.setString(_macKey, mac);
    return mac;
  }

  static String _generateMac() {
    final r = Random();
    return List.generate(
      6,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase(),
    ).join(':');
  }
}
