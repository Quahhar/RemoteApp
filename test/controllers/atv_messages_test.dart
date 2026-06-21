import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/androidtv/atv_messages.dart';
import 'package:remote/controllers/androidtv/atv_proto.dart';

void main() {
  test('remoteKeyInject puts key_code + SHORT direction under field 10', () {
    final top = parseProto(AtvMessages.remoteKeyInject(23)); // OK/DPAD_CENTER
    expect(top.containsKey(10), isTrue);
    final inject = parseProto(top[10] as Uint8List);
    expect(inject[1], 23); // key_code
    expect(inject[2], 3); // direction = SHORT
  });

  test('remote configure/set-active/ping use the right top-level fields', () {
    expect(parseProto(AtvMessages.remoteConfigure()).containsKey(1), isTrue);
    expect(parseProto(AtvMessages.remoteSetActive()).containsKey(2), isTrue);
    final ping = parseProto(AtvMessages.remotePingResponse(7));
    expect(ping.containsKey(9), isTrue);
    expect(parseProto(ping[9] as Uint8List)[1], 7); // echoes val1
  });

  test('parseRemote classifies a ping request and reads val1', () {
    final inner = (ProtoWriter()
          ..int32(1, 42)
          ..int32(2, 9))
        .toBytes();
    final msg = (ProtoWriter()..message(8, inner)).toBytes();
    final parsed = AtvMessages.parseRemote(msg);
    expect(parsed.type, RemoteType.pingRequest);
    expect(parsed.pingVal1, 42);
  });

  test('pairing envelope carries protocol_version=2, status=200, body field', () {
    final top = parseProto(AtvMessages.pairingRequest('X'));
    expect(top[1], 2); // protocol_version
    expect(top[2], 200); // status STATUS_OK
    expect(top.containsKey(10), isTrue); // pairing_request
  });

  test('parsePairing classifies acks by their oneof field number', () {
    Uint8List env(int field) => (ProtoWriter()
          ..int32(1, 2)
          ..int32(2, 200)
          ..message(field, Uint8List(0)))
        .toBytes();
    expect(AtvMessages.parsePairing(env(11)).type, PairingType.requestAck);
    expect(AtvMessages.parsePairing(env(31)).type, PairingType.configurationAck);
    expect(AtvMessages.parsePairing(env(41)).type, PairingType.secretAck);
  });
}
