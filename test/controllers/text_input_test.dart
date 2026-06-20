import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/roku_controller.dart';
import 'package:remote/controllers/text_input.dart';
import 'package:remote/controllers/tizen_controller.dart';
import 'package:remote/controllers/webos_controller.dart';

/// Backspace (BS) control character the keyboard encodes deletions as.
final String bs = String.fromCharCode(0x08);

void main() {
  group('tokenizeInput', () {
    test('plain text is a single run', () {
      expect(tokenizeInput('abc'), [const TextRun('abc')]);
    });

    test('empty string yields no segments', () {
      expect(tokenizeInput(''), isEmpty);
    });

    test('newline splits runs and becomes an enter edit', () {
      expect(tokenizeInput('ab\nc'), [
        const TextRun('ab'),
        const TextEdit(TextEditKey.enter),
        const TextRun('c'),
      ]);
    });

    test('backspace becomes a backspace edit', () {
      expect(tokenizeInput('a$bs'), [
        const TextRun('a'),
        const TextEdit(TextEditKey.backspace),
      ]);
    });

    test('mixed sequence preserves order', () {
      expect(tokenizeInput('hi\n${bs}x'), [
        const TextRun('hi'),
        const TextEdit(TextEditKey.enter),
        const TextEdit(TextEditKey.backspace),
        const TextRun('x'),
      ]);
    });
  });

  group('Roku text -> ECP keys', () {
    test('printable characters become per-char Lit_ keys', () {
      expect(RokuController.textKeyNames('aB1'),
          ['Lit_a', 'Lit_B', 'Lit_1']);
    });

    test('special characters are URL-encoded', () {
      expect(RokuController.textKeyNames(' '), ['Lit_%20']);
      expect(RokuController.textKeyNames('&'), ['Lit_%26']);
    });

    test('enter and backspace map to ECP keys', () {
      expect(RokuController.textKeyNames('a\nb'),
          ['Lit_a', 'Enter', 'Lit_b']);
      expect(RokuController.textKeyNames('a$bs'),
          ['Lit_a', 'Backspace']);
    });
  });

  group('Samsung text -> input frames', () {
    Map<String, dynamic> params(String frame) =>
        (jsonDecode(frame) as Map<String, dynamic>)['params']
            as Map<String, dynamic>;

    test('a printable run becomes one base64 SendInputString', () {
      final frames = TizenController.inputFrames('hello');
      expect(frames, hasLength(1));
      final p = params(frames.single);
      expect(p['TypeOfRemote'], 'SendInputString');
      expect(p['DataOfCmd'], 'base64');
      expect(utf8.decode(base64.decode(p['Cmd'] as String)), 'hello');
    });

    test('enter and backspace become KEY_ENTER / KEY_DELETE', () {
      final frames = TizenController.inputFrames('a\n$bs');
      expect(frames, hasLength(3));
      expect(params(frames[0])['TypeOfRemote'], 'SendInputString');
      expect(params(frames[1])['DataOfCmd'], 'KEY_ENTER');
      expect(params(frames[2])['DataOfCmd'], 'KEY_DELETE');
    });
  });

  group('LG webOS text -> IME requests', () {
    test('a printable run becomes one insertText', () {
      final reqs = WebosController.imeRequests('hello');
      expect(reqs, hasLength(1));
      expect(reqs.single.uri, 'ssap://com.webos.service.ime/insertText');
      expect(reqs.single.payload, {'text': 'hello', 'replace': 0});
    });

    test('enter and backspace map to IME requests', () {
      final reqs = WebosController.imeRequests('a\n$bs');
      expect(reqs[0].uri, 'ssap://com.webos.service.ime/insertText');
      expect(reqs[1].uri, 'ssap://com.webos.service.ime/sendEnterKey');
      expect(reqs[1].payload, isNull);
      expect(reqs[2].uri, 'ssap://com.webos.service.ime/deleteCharacters');
      expect(reqs[2].payload, {'count': 1});
    });
  });
}
