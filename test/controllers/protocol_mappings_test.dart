import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote/controllers/androidtv_controller.dart';
import 'package:remote/controllers/tizen_controller.dart';
import 'package:remote/controllers/webos_controller.dart';
import 'package:remote/models/remote_key.dart';

void main() {
  group('LG webOS button mapping', () {
    test('every RemoteKey maps to a non-empty button name', () {
      for (final key in RemoteKey.values) {
        expect(WebosController.buttonNames[key], isNotNull,
            reason: 'missing ${key.name}');
        expect(WebosController.buttonNames[key], isNotEmpty);
      }
      expect(WebosController.buttonNames.length, RemoteKey.values.length);
    });

    test('representative mappings', () {
      expect(WebosController.buttonNames[RemoteKey.ok], 'ENTER');
      expect(WebosController.buttonNames[RemoteKey.back], 'BACK');
      expect(WebosController.buttonNames[RemoteKey.volumeUp], 'VOLUMEUP');
      expect(WebosController.buttonNames[RemoteKey.channelDown], 'CHANNELDOWN');
    });
  });

  group('Samsung Tizen key mapping', () {
    test('every RemoteKey maps to a KEY_ code', () {
      for (final key in RemoteKey.values) {
        final code = TizenController.keyCodes[key];
        expect(code, isNotNull, reason: 'missing ${key.name}');
        expect(code, startsWith('KEY_'));
      }
      expect(TizenController.keyCodes.length, RemoteKey.values.length);
    });

    test('representative mappings', () {
      expect(TizenController.keyCodes[RemoteKey.ok], 'KEY_ENTER');
      expect(TizenController.keyCodes[RemoteKey.back], 'KEY_RETURN');
      expect(TizenController.keyCodes[RemoteKey.volumeUp], 'KEY_VOLUP');
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

  group('Android TV keycode mapping', () {
    test('every RemoteKey maps to an Android keycode', () {
      for (final key in RemoteKey.values) {
        expect(AndroidTvController.keyCodes[key], isNotNull,
            reason: 'missing ${key.name}');
      }
      expect(AndroidTvController.keyCodes.length, RemoteKey.values.length);
    });

    test('representative keycodes match Android constants', () {
      expect(AndroidTvController.keyCodes[RemoteKey.ok], 23); // DPAD_CENTER
      expect(AndroidTvController.keyCodes[RemoteKey.up], 19); // DPAD_UP
      expect(AndroidTvController.keyCodes[RemoteKey.back], 4); // BACK
      expect(AndroidTvController.keyCodes[RemoteKey.power], 26); // POWER
    });
  });
}
