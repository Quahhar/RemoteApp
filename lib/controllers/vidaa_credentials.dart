import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Dynamic MQTT credentials for modern Hisense / VIDAA TVs (transport protocol
/// >= 3290). Ported from pyvidaa, which reverse-engineered `libmqttcrypt.so`
/// from the official VIDAA app.
///
/// The TV embeds a Unix timestamp in the username/password and validates it
/// against its own clock, so [timestamp] must be close to real time — static
/// credentials (`hisenseservice`/`multimqttservice`) are rejected with
/// CONNACK `notAuthorized` (rc=5) on this firmware. After pairing, the issued
/// access token is reused as the password to skip the on-screen PIN.
class VidaaCredentials {
  const VidaaCredentials({
    required this.clientId,
    required this.username,
    required this.password,
  });

  /// Full MQTT client id, also used as the `{client}` segment in every topic.
  final String clientId;
  final String username;
  final String password;
}

/// Credential variant, selected by the TV's `transport_protocol` version.
/// MODERN (>=3290): XOR username + modern suffix. MIDDLE (3000-3289): XOR
/// username + legacy suffix. LEGACY (<3000): plain username + legacy suffix.
enum VidaaAuthMethod { modern, middle, legacy }

// Constants recovered from libmqttcrypt.so (see pyvidaa config/constants.py).
const String _pattern = '38D65DC30F45109A369A86FCE866A85B';
const String _valueSuffixModern = 'h!i@s#\$v%i^d&a*a'; // protocol >= 3290
const String _valueSuffixLegacy = 'h*i&s%e!r^v0i1c9'; // protocol < 3290
const int _timeXorConstant = 0x569814772b03a968;
const String _operation = 'vidaacommon';

/// Picks the auth variant for a `transport_protocol` version.
VidaaAuthMethod vidaaAuthMethodFor(int protocolVersion) {
  if (protocolVersion >= 3290) return VidaaAuthMethod.modern;
  if (protocolVersion >= 3000) return VidaaAuthMethod.middle;
  return VidaaAuthMethod.legacy;
}

/// Default brand code. Rebrands report their own (e.g. Kenstar = `ksj`) in the
/// UPnP descriptor's `brand=` field; the brand feeds the client_id, username
/// AND password, so the wrong one is rejected with `notAuthorized`.
const String kDefaultVidaaBrand = 'his';

String _md5Upper(String s) =>
    md5.convert(utf8.encode(s)).toString().toUpperCase();

int _sumDigits(int n) {
  var sum = 0;
  for (final code in n.abs().toString().codeUnits) {
    sum += code - 0x30; // '0'
  }
  return sum;
}

/// Builds the modern dynamic credentials for [uuid] (a stable per-install
/// MAC-style id in colon format, case preserved) at [timestamp] (Unix seconds,
/// default now). For control of an already-paired TV, pass the stored
/// [accessToken] — it replaces the computed password and skips the PIN.
VidaaCredentials generateVidaaCredentials({
  required String uuid,
  String brand = kDefaultVidaaBrand,
  VidaaAuthMethod authMethod = VidaaAuthMethod.modern,
  int? timestamp,
  String? accessToken,
}) {
  final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final race = '$_pattern\$$uuid';
  final raceMd5 = _md5Upper(race).substring(0, 6);
  final clientId = '$uuid\$$brand\$${raceMd5}_${_operation}_001';

  // LEGACY uses a plain timestamp; MIDDLE/MODERN XOR it.
  final String username;
  if (authMethod == VidaaAuthMethod.legacy) {
    username = '$brand\$$ts';
  } else {
    username = '$brand\$${ts ^ _timeXorConstant}';
  }

  String password;
  if (accessToken != null && accessToken.isNotEmpty) {
    password = accessToken;
  } else {
    final suffix = authMethod == VidaaAuthMethod.modern
        ? _valueSuffixModern
        : _valueSuffixLegacy;
    final remainder = _sumDigits(ts) % 10;
    final value = '$brand$remainder$suffix';
    final valueMd5 = _md5Upper(value).substring(0, 6);
    password = _md5Upper('$ts\$$valueMd5');
  }

  return VidaaCredentials(
    clientId: clientId,
    username: username,
    password: password,
  );
}
