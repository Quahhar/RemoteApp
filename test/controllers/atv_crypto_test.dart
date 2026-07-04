import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/androidtv/atv_crypto.dart';

/// Generate a small (fast) self-signed cert and return (pem, der, publicKey).
({String pem, Uint8List der, RSAPublicKey pub}) _makeCert() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 1024);
  final priv = pair.privateKey as RSAPrivateKey;
  final pub = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem({'CN': 'test'}, priv, pub);
  final pem = X509Utils.generateSelfSignedCertificate(priv, csr, 365);
  return (pem: pem, der: AtvCrypto.pemToDer(pem), pub: pub);
}

void main() {
  test('parseCertPublicKey recovers the modulus and exponent', () {
    final cert = _makeCert();
    final parsed = AtvCrypto.parseCertPublicKey(cert.der);
    expect(parsed.modulus, cert.pub.modulus);
    expect(parsed.exponent, cert.pub.exponent);
  });

  test('bigIntToBytes is minimal big-endian (e.g. exponent 65537)', () {
    expect(AtvCrypto.bigIntToBytes(BigInt.from(65537)),
        Uint8List.fromList([0x01, 0x00, 0x01]));
    expect(AtvCrypto.bigIntToBytes(BigInt.from(255)),
        Uint8List.fromList([0xFF]));
  });

  test('computeSecret returns the hash when the check byte matches', () {
    final client = _makeCert();
    final server = _makeCert();
    const tail = [0x12, 0x34];

    // Derive the matching full code: first byte = hash[0] over the tail.
    final hash = AtvCrypto.hashForTail(client.der, server.der, tail);
    final code = _hex([hash[0], tail[0], tail[1]]);

    final secret = AtvCrypto.computeSecret(
      clientCertDer: client.der,
      serverCertDer: server.der,
      code: code,
    );
    expect(secret, hash);
  });

  test('computeSecret rejects a code with the wrong check byte', () {
    final client = _makeCert();
    final server = _makeCert();
    const tail = [0xAB, 0xCD];
    final hash = AtvCrypto.hashForTail(client.der, server.der, tail);
    final badCode = _hex([hash[0] ^ 0xFF, tail[0], tail[1]]);

    expect(
      () => AtvCrypto.computeSecret(
        clientCertDer: client.der,
        serverCertDer: server.der,
        code: badCode,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('computeSecret rejects odd-length / non-hex codes (no RangeError)', () {
    final client = _makeCert();
    final server = _makeCert();
    Object? run(String code) => AtvCrypto.computeSecret(
          clientCertDer: client.der,
          serverCertDer: server.der,
          code: code,
        );
    expect(() => run('abc'), throwsA(isA<FormatException>())); // odd length
    expect(() => run('zz'), throwsA(isA<FormatException>())); // non-hex
    expect(() => run(''), throwsA(isA<FormatException>())); // empty
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
