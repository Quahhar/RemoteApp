import 'dart:convert';
import 'dart:typed_data';

/// Minimal protobuf wire writer (only the wire types the Android TV v2 protocol
/// uses: varint and length-delimited). Proto3 semantics — zero-valued scalar
/// fields are omitted; callers pass only fields they intend to send.
class ProtoWriter {
  final BytesBuilder _b = BytesBuilder();

  Uint8List toBytes() => _b.toBytes();

  void _varint(int value) {
    var v = value;
    while (true) {
      if ((v & ~0x7f) == 0) {
        _b.addByte(v);
        return;
      }
      _b.addByte((v & 0x7f) | 0x80);
      v = v >>> 7;
    }
  }

  void _tag(int field, int wire) => _varint((field << 3) | wire);

  /// varint scalar (int32 / enum). Omitted when zero (proto3 default).
  void int32(int field, int value) {
    if (value == 0) return;
    _tag(field, 0);
    _varint(value);
  }

  void bytes(int field, List<int> value) {
    _tag(field, 2);
    _varint(value.length);
    _b.add(value);
  }

  void string(int field, String value) {
    if (value.isEmpty) return;
    bytes(field, utf8.encode(value));
  }

  /// Embed a sub-message (length-delimited).
  void message(int field, Uint8List sub) {
    _tag(field, 2);
    _varint(sub.length);
    _b.add(sub);
  }
}

/// Parses a flat protobuf message into a field-number -> value map. Varint
/// fields decode to int; length-delimited fields decode to Uint8List. Repeated
/// fields keep the last value (sufficient for the messages we read).
Map<int, Object> parseProto(Uint8List data) {
  final out = <int, Object>{};
  var pos = 0;

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = data[pos++];
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  while (pos < data.length) {
    final tag = readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch (wire) {
      case 0: // varint
        out[field] = readVarint();
      case 2: // length-delimited
        final len = readVarint();
        out[field] = Uint8List.sublistView(data, pos, pos + len);
        pos += len;
      case 5: // 32-bit
        pos += 4;
      case 1: // 64-bit
        pos += 8;
      default:
        throw FormatException('Unsupported protobuf wire type $wire');
    }
  }
  return out;
}

/// Encode [message] as a varint-length-delimited frame (length prefix + bytes),
/// the framing both Android TV channels use.
Uint8List frame(Uint8List message) {
  final out = BytesBuilder();
  var len = message.length;
  while (true) {
    if ((len & ~0x7f) == 0) {
      out.addByte(len);
      break;
    }
    out.addByte((len & 0x7f) | 0x80);
    len = len >>> 7;
  }
  out.add(message);
  return out.toBytes();
}

/// Incremental de-framer: feed raw socket bytes, yields complete message
/// payloads as their varint length prefixes complete.
class FrameReader {
  final List<int> _buf = [];

  Iterable<Uint8List> add(List<int> chunk) sync* {
    _buf.addAll(chunk);
    while (true) {
      final header = _tryReadLength();
      if (header == null) return;
      final (length, headerLen) = header;
      if (_buf.length - headerLen < length) return; // wait for more
      final start = headerLen;
      final msg = Uint8List.fromList(_buf.sublist(start, start + length));
      _buf.removeRange(0, start + length);
      yield msg;
    }
  }

  /// Reads the leading varint length without consuming, returning (value, byteLen).
  (int, int)? _tryReadLength() {
    var result = 0;
    var shift = 0;
    var i = 0;
    while (i < _buf.length) {
      final b = _buf[i];
      result |= (b & 0x7f) << shift;
      i++;
      if ((b & 0x80) == 0) return (result, i);
      shift += 7;
      if (shift > 35) throw const FormatException('varint too long');
    }
    return null; // incomplete
  }
}
