import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/androidtv/atv_crypto.dart';

/// Persists the app-global Android TV client identity (one self-signed cert +
/// key reused for every Android TV pairing). Generated lazily on first pairing.
class AtvIdentityStore {
  AtvIdentityStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _certKey = 'atv_client_cert_pem';
  static const String _keyKey = 'atv_client_key_pem';

  AtvIdentity? load() {
    final cert = _prefs.getString(_certKey);
    final key = _prefs.getString(_keyKey);
    if (cert == null || key == null) return null;
    return AtvIdentity(certPem: cert, keyPem: key);
  }

  /// Return the stored identity, generating and persisting one if absent.
  /// Generation is CPU-heavy (RSA-2048) and runs synchronously — only happens
  /// once, during the first pairing.
  Future<AtvIdentity> ensure() async {
    final existing = load();
    if (existing != null) return existing;
    final identity = AtvCrypto.generateIdentity();
    await _prefs.setString(_certKey, identity.certPem);
    await _prefs.setString(_keyKey, identity.keyPem);
    return identity;
  }
}
