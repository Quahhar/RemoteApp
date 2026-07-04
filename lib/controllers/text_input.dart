import 'package:flutter/foundation.dart';

/// One piece of a `sendText` payload: either a run of printable characters or a
/// single editing key (enter / backspace). [tokenizeInput] splits a raw string
/// into these so each controller maps them to its own wire format (Roku ECP
/// keys, webOS IME requests, Tizen input frames, …).
///
/// The keyboard UI encodes enter as newline and backspace as the BS/DEL control
/// character inside the string it passes to `sendText`, which keeps the public
/// surface at the single `sendText(String)` method while still routing edits.
@immutable
sealed class TextSegment {
  const TextSegment();
}

class TextRun extends TextSegment {
  const TextRun(this.text);
  final String text;

  @override
  bool operator ==(Object other) => other is TextRun && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TextRun("$text")';
}

enum TextEditKey { enter, backspace }

class TextEdit extends TextSegment {
  const TextEdit(this.key);
  final TextEditKey key;

  @override
  bool operator ==(Object other) => other is TextEdit && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'TextEdit(${key.name})';
}

/// Control characters the keyboard uses to encode edit keys. Built from code
/// points to avoid embedding raw control characters in source.
const int kBackspace = 0x08; // BS
const int kDelete = 0x7f; // DEL
const int kLineFeed = 0x0a; // \n
const int kCarriageReturn = 0x0d; // \r

/// Splits [text] into printable runs and edit keys, preserving order.
List<TextSegment> tokenizeInput(String text) {
  final segments = <TextSegment>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isNotEmpty) {
      segments.add(TextRun(buffer.toString()));
      buffer.clear();
    }
  }

  var lastWasCr = false;
  for (final code in text.runes) {
    if (code == kCarriageReturn) {
      flush();
      segments.add(const TextEdit(TextEditKey.enter));
      lastWasCr = true;
    } else if (code == kLineFeed) {
      if (lastWasCr) {
        // CR+LF: already emitted enter for CR, skip the LF.
        lastWasCr = false;
        continue;
      }
      flush();
      segments.add(const TextEdit(TextEditKey.enter));
    } else {
      if (code == kBackspace || code == kDelete) {
        flush();
        segments.add(const TextEdit(TextEditKey.backspace));
      } else {
        buffer.writeCharCode(code);
      }
      lastWasCr = false;
    }
  }
  flush();
  return segments;
}
