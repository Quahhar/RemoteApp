import 'dart:typed_data';

import 'atv_proto.dart';

/// Which pairing message the TV sent (identified by oneof field presence).
enum PairingType { requestAck, option, configurationAck, secretAck, unknown }

class PairingIncoming {
  PairingIncoming(this.type, this.status);
  final PairingType type;
  final int status; // PairingMessage.Status; 200 = OK
  bool get ok => status == 0 || status == 200;
}

/// Which remote message the TV sent.
enum RemoteType { configure, setActive, pingRequest, start, other }

class RemoteIncoming {
  RemoteIncoming(this.type, {this.pingVal1 = 0});
  final RemoteType type;
  final int pingVal1;
}

/// Builders + parsers for the Android TV v2 pairing (6467) and remote (6466)
/// protobuf messages. Field numbers per the protocol reference.
class AtvMessages {
  AtvMessages._();

  static const int _protocolVersion = 2;
  static const int _statusOk = 200;
  static const int directionShort = 3; // RemoteDirection.SHORT
  static const int _deviceId = 622; // arbitrary handshake id used by clients

  // --- Pairing (PairingMessage: protocol_version=1, status=2) ----------------

  static Uint8List pairingRequest(String clientName) {
    final req = (ProtoWriter()
          ..string(1, 'androidtv-remote') // service_name
          ..string(2, clientName)) // client_name
        .toBytes();
    return _pairingEnvelope(10, req);
  }

  static Uint8List pairingOption() {
    final encoding = (ProtoWriter()
          ..int32(1, 3) // type = HEXADECIMAL
          ..int32(2, 6)) // symbol_length
        .toBytes();
    final option = (ProtoWriter()
          ..message(1, encoding) // input_encodings (repeated; one entry)
          ..int32(3, 1)) // preferred_role = INPUT
        .toBytes();
    return _pairingEnvelope(20, option);
  }

  static Uint8List pairingConfiguration() {
    final encoding = (ProtoWriter()
          ..int32(1, 3)
          ..int32(2, 6))
        .toBytes();
    final config = (ProtoWriter()
          ..message(1, encoding) // encoding
          ..int32(2, 1)) // client_role = INPUT
        .toBytes();
    return _pairingEnvelope(30, config);
  }

  static Uint8List pairingSecret(Uint8List hash) {
    final secret = (ProtoWriter()..bytes(1, hash)).toBytes();
    return _pairingEnvelope(40, secret);
  }

  static Uint8List _pairingEnvelope(int field, Uint8List body) {
    return (ProtoWriter()
          ..int32(1, _protocolVersion)
          ..int32(2, _statusOk)
          ..message(field, body))
        .toBytes();
  }

  static PairingIncoming parsePairing(Uint8List data) {
    final f = parseProto(data);
    final status = (f[2] as int?) ?? 0;
    final PairingType type;
    if (f.containsKey(11)) {
      type = PairingType.requestAck;
    } else if (f.containsKey(20)) {
      type = PairingType.option;
    } else if (f.containsKey(31)) {
      type = PairingType.configurationAck;
    } else if (f.containsKey(41)) {
      type = PairingType.secretAck;
    } else {
      type = PairingType.unknown;
    }
    return PairingIncoming(type, status);
  }

  // --- Remote (RemoteMessage) ------------------------------------------------

  static Uint8List remoteConfigure() {
    final deviceInfo = (ProtoWriter()
          ..string(1, 'Remote') // model
          ..string(2, 'Flutter') // vendor
          ..int32(3, 1) // unknown1
          ..int32(4, 1) // unknown2
          ..string(5, 'com.remote.app') // package_name
          ..string(6, '1.0.0')) // app_version
        .toBytes();
    final configure = (ProtoWriter()
          ..int32(1, _deviceId) // code1
          ..message(2, deviceInfo))
        .toBytes();
    return (ProtoWriter()..message(1, configure)).toBytes(); // remote_configure
  }

  static Uint8List remoteSetActive() {
    final active = (ProtoWriter()..int32(1, _deviceId)).toBytes();
    return (ProtoWriter()..message(2, active)).toBytes(); // remote_set_active
  }

  static Uint8List remotePingResponse(int val1) {
    final ping = (ProtoWriter()..int32(1, val1)).toBytes();
    return (ProtoWriter()..message(9, ping)).toBytes(); // remote_ping_response
  }

  static Uint8List remoteKeyInject(int keyCode, {int direction = directionShort}) {
    final inject = (ProtoWriter()
          ..int32(1, keyCode) // key_code
          ..int32(2, direction)) // direction
        .toBytes();
    return (ProtoWriter()..message(10, inject)).toBytes(); // remote_key_inject
  }

  static RemoteIncoming parseRemote(Uint8List data) {
    final f = parseProto(data);
    if (f.containsKey(1)) return RemoteIncoming(RemoteType.configure);
    if (f.containsKey(2)) return RemoteIncoming(RemoteType.setActive);
    if (f.containsKey(8)) {
      final sub = parseProto(f[8] as Uint8List);
      return RemoteIncoming(RemoteType.pingRequest,
          pingVal1: (sub[1] as int?) ?? 0);
    }
    if (f.containsKey(40)) return RemoteIncoming(RemoteType.start);
    return RemoteIncoming(RemoteType.other);
  }
}
