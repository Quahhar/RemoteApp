@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Verifies the bundled Hisense/VIDAA client cert + key actually parse in Dart's
/// TLS engine (BoringSSL — the same one Flutter uses on device). If this throws,
/// the runtime would silently fall back to no client cert, which looks exactly
/// like "could not open a remote session". Runs without any TV.
void main() {
  test('bundled VIDAA client cert + key load into a SecurityContext', () {
    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChain('assets/certs/vidaa_client_cert.pem');
    ctx.usePrivateKey('assets/certs/vidaa_client_key.pem');
  });
}
