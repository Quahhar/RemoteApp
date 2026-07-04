import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/androidtv_controller.dart';
import 'package:remote/controllers/hisense_controller.dart';
import 'package:remote/controllers/tizen_controller.dart';
import 'package:remote/controllers/webos_controller.dart';
import 'package:remote/models/remote_key.dart';

void main() {
  group('LG webOS button mapping', () {
    test('every core RemoteKey maps to a non-empty button name', () {
      for (final key in RemoteKey.core) {
        expect(WebosController.buttonNames[key], isNotNull,
            reason: 'missing ${key.name}');
        expect(WebosController.buttonNames[key], isNotEmpty);
      }
    });

    test('representative mappings (core + extended)', () {
      expect(WebosController.buttonNames[RemoteKey.ok], 'ENTER');
      expect(WebosController.buttonNames[RemoteKey.back], 'BACK');
      expect(WebosController.buttonNames[RemoteKey.volumeUp], 'VOLUMEUP');
      expect(WebosController.buttonNames[RemoteKey.channelDown], 'CHANNELDOWN');
      expect(WebosController.buttonNames[RemoteKey.digit5], '5');
      expect(WebosController.buttonNames[RemoteKey.colorRed], 'RED');
    });

    test('buttonFrame is the exact input-socket wire format', () {
      expect(WebosController.buttonFrame(RemoteKey.up), 'type:button\nname:UP\n\n');
      expect(
          WebosController.buttonFrame(RemoteKey.ok), 'type:button\nname:ENTER\n\n');
    });
  });

  group('Samsung Tizen key mapping', () {
    test('every core RemoteKey maps to a KEY_ code', () {
      for (final key in RemoteKey.core) {
        final code = TizenController.keyCodes[key];
        expect(code, isNotNull, reason: 'missing ${key.name}');
        expect(code, startsWith('KEY_'));
      }
    });

    test('every mapped key uses a KEY_ code', () {
      for (final code in TizenController.keyCodes.values) {
        expect(code, startsWith('KEY_'));
      }
    });

    test('representative mappings (core + extended)', () {
      expect(TizenController.keyCodes[RemoteKey.ok], 'KEY_ENTER');
      expect(TizenController.keyCodes[RemoteKey.back], 'KEY_RETURN');
      expect(TizenController.keyCodes[RemoteKey.volumeUp], 'KEY_VOLUP');
      expect(TizenController.keyCodes[RemoteKey.digit0], 'KEY_0');
      expect(TizenController.keyCodes[RemoteKey.colorBlue], 'KEY_BLUE');
    });

    test('commandFor produces the SendRemoteKey frame', () {
      final frame = jsonDecode(TizenController.commandFor(RemoteKey.home))
          as Map<String, dynamic>;
      expect(frame['method'], 'ms.remote.control');
      final params = frame['params'] as Map<String, dynamic>;
      expect(params['Cmd'], 'Click');
      expect(params['DataOfCmd'], 'KEY_HOME');
      expect(params['TypeOfRemote'], 'SendRemoteKey');
    });
  });

  group('Hisense / VIDAA key mapping', () {
    test('every core RemoteKey maps to a KEY_ name', () {
      for (final key in RemoteKey.core) {
        final name = HisenseController.keyNames[key];
        expect(name, isNotNull, reason: 'missing ${key.name}');
        expect(name, startsWith('KEY_'));
      }
    });

    test('every mapped key uses a KEY_ name', () {
      for (final name in HisenseController.keyNames.values) {
        expect(name, startsWith('KEY_'));
      }
    });

    test('representative mappings (core + extended)', () {
      expect(HisenseController.keyNames[RemoteKey.ok], 'KEY_OK');
      // VIDAA's navigation back is KEY_RETURNS (KEY_BACK is media-rewind).
      expect(HisenseController.keyNames[RemoteKey.back], 'KEY_RETURNS');
      expect(HisenseController.keyNames[RemoteKey.menu], 'KEY_MENU');
      expect(HisenseController.keyNames[RemoteKey.volumeUp], 'KEY_VOLUMEUP');
      // VIDAA reuses KEY_BACK for media rewind.
      expect(HisenseController.keyNames[RemoteKey.rewind], 'KEY_BACK');
    });
  });

  group('Android TV keycode mapping', () {
    test('every core RemoteKey maps to an Android keycode', () {
      for (final key in RemoteKey.core) {
        expect(AndroidTvController.keyCodes[key], isNotNull,
            reason: 'missing ${key.name}');
      }
    });

    test('representative keycodes match Android constants', () {
      expect(AndroidTvController.keyCodes[RemoteKey.ok], 23); // DPAD_CENTER
      expect(AndroidTvController.keyCodes[RemoteKey.up], 19); // DPAD_UP
      expect(AndroidTvController.keyCodes[RemoteKey.back], 4); // BACK
      expect(AndroidTvController.keyCodes[RemoteKey.power], 26); // POWER
      expect(AndroidTvController.keyCodes[RemoteKey.digit0], 7); // KEYCODE_0
      expect(AndroidTvController.keyCodes[RemoteKey.colorRed], 183); // PROG_RED
    });
  });
}
