import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// The app-global client identity used for every Android TV pairing: a
/// self-signed RSA certificate + its private key, both PEM-encoded.
@immutable
class AtvIdentity {
  const AtvIdentity({required this.certPem, required this.keyPem});
  final String certPem;
  final String keyPem;
}

/// An RSA public key's raw numbers (used by the pairing-secret hash).
@immutable
class RsaPub {
  const RsaPub(this.modulus, this.exponent);
  final BigInt modulus;
  final BigInt exponent;
}

/// Crypto for Android TV Remote v2: client cert generation, parsing a cert's
/// RSA public key, and the pairing-secret hash. All pure/static so it can be
/// unit-tested without a TV.
class AtvCrypto {
  AtvCrypto._();

  /// Generate a fresh client identity (RSA-2048 + self-signed cert). Slow
  /// (a second or two) — done once and persisted.
  static AtvIdentity generateIdentity({int keySize = 2048}) {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: keySize);
    final priv = pair.privateKey as RSAPrivateKey;
    final pub = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'atvremote', 'O': 'Omnix'},
      priv,
      pub,
    );
    final certPem = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
    return AtvIdentity(certPem: certPem, keyPem: keyPem);
  }

  /// Strip PEM armor and base64-decode to DER (tolerates CRLF / spaces).
  static Uint8List pemToDer(String pem) {
    final body = pem
        .replaceAll(RegExp('-----[A-Z ]+-----'), '')
        .replaceAll(RegExp(r'\s'), '');
    return base64.decode(body);
  }

  /// Extract the RSA modulus/exponent from an X.509 certificate DER.
  static RsaPub parseCertPublicKey(Uint8List der) {
    final cert = ASN1Parser(der).nextObject() as ASN1Sequence;
    final tbs = cert.elements.first as ASN1Sequence;
    // SubjectPublicKeyInfo = SEQUENCE { AlgorithmIdentifier SEQUENCE, BIT STRING }
    ASN1Sequence? spki;
    for (final el in tbs.elements) {
      if (el is ASN1Sequence &&
          el.elements.length == 2 &&
          el.elements[0] is ASN1Sequence &&
          el.elements[1] is ASN1BitString) {
        spki = el;
        break;
      }
    }
    if (spki == null) {
      throw const FormatException('No SubjectPublicKeyInfo in certificate');
    }
    final bitString = spki.elements[1] as ASN1BitString;
    var body = bitString.valueBytes();
    // BIT STRING content begins with an "unused bits" octet (0) before the key.
    if (body.isNotEmpty && body[0] == 0x00) {
      body = Uint8List.sublistView(body, 1);
    }
    final rsa = ASN1Parser(body).nextObject() as ASN1Sequence;
    final modulus = (rsa.elements[0] as ASN1Integer).valueAsBigInteger;
    final exponent = (rsa.elements[1] as ASN1Integer).valueAsBigInteger;
    return RsaPub(modulus, exponent);
  }

  /// Minimal big-endian unsigned bytes of [v] (no leading zero) — matches how
  /// the reference implementations feed modulus/exponent into the hash.
  static Uint8List bigIntToBytes(BigInt v) {
    var hex = v.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static Uint8List hexDecode(String s) {
    final clean = s.trim();
    if (clean.isEmpty) return Uint8List(0);
    if (clean.length.isOdd) {
      throw const FormatException('Pairing code must have even length');
    }
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// SHA-256 over client modulus/exponent, server modulus/exponent, and the
  /// code tail (everything after the first code byte).
  @visibleForTesting
  static Uint8List hashForTail(
    Uint8List clientCertDer,
    Uint8List serverCertDer,
    List<int> codeTail,
  ) {
    final client = parseCertPublicKey(clientCertDer);
    final server = parseCertPublicKey(serverCertDer);
    final input =
        (BytesBuilder()
              ..add(bigIntToBytes(client.modulus))
              ..add(bigIntToBytes(client.exponent))
              ..add(bigIntToBytes(server.modulus))
              ..add(bigIntToBytes(server.exponent))
              ..add(codeTail))
            .toBytes();
    return SHA256Digest().process(input);
  }

  /// Compute the PairingSecret payload for the on-screen [code] (hex string).
  /// Throws [FormatException] if the code's check byte doesn't match.
  static Uint8List computeSecret({
    required Uint8List clientCertDer,
    required Uint8List serverCertDer,
    required String code,
  }) {
    final codeBytes = hexDecode(code);
    if (codeBytes.isEmpty) {
      throw const FormatException('Empty pairing code');
    }
    final hash = hashForTail(
      clientCertDer,
      serverCertDer,
      codeBytes.sublist(1),
    );
    if (hash[0] != codeBytes[0]) {
      throw const FormatException('Pairing code did not match');
    }
    return hash;
  }
}
