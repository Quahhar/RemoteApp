import 'dart:async';

import '../models/capabilities.dart';
import '../models/connection_status.dart';
import '../models/device.dart';
import '../models/protocol_type.dart';
import '../models/remote_key.dart';
import 'remote_controller.dart';

/// Android TV / Google TV via the "Remote v2" protocol.
///
/// The full transport is a two-phase TLS exchange: a pairing channel
/// (port 6467) where the user confirms a 6-digit code shown on the TV — which
/// yields a client certificate we persist — followed by a remote channel
/// (port 6466) carrying length-prefixed protobuf key events. That handshake
/// (X.509 client-cert generation + protobuf framing + the code-derived secret)
/// is the one piece that must be validated against real hardware, so it is not
/// wired into this build yet.
///
/// Everything else conforms to the shared interface: the registry resolves it,
/// the key map is complete (the exact Android keycodes the protocol transmits),
/// and [connect] fails with a clear, actionable message instead of pretending.
class AndroidTvController extends RemoteController {
  /// RemoteKey -> Android `KeyEvent` keycode (the integer the v2 remote channel
  /// sends). Verified against the standard Android keycode constants.
  static const Map<RemoteKey, int> keyCodes = {
    RemoteKey.power: 26, // KEYCODE_POWER
    RemoteKey.up: 19, // KEYCODE_DPAD_UP
    RemoteKey.down: 20, // KEYCODE_DPAD_DOWN
    RemoteKey.left: 21, // KEYCODE_DPAD_LEFT
    RemoteKey.right: 22, // KEYCODE_DPAD_RIGHT
    RemoteKey.ok: 23, // KEYCODE_DPAD_CENTER
    RemoteKey.back: 4, // KEYCODE_BACK
    RemoteKey.home: 3, // KEYCODE_HOME
    RemoteKey.menu: 82, // KEYCODE_MENU
    RemoteKey.volumeUp: 24, // KEYCODE_VOLUME_UP
    RemoteKey.volumeDown: 25, // KEYCODE_VOLUME_DOWN
    RemoteKey.mute: 164, // KEYCODE_VOLUME_MUTE
    RemoteKey.channelUp: 166, // KEYCODE_CHANNEL_UP
    RemoteKey.channelDown: 167, // KEYCODE_CHANNEL_DOWN
    RemoteKey.play: 126, // KEYCODE_MEDIA_PLAY
    RemoteKey.pause: 127, // KEYCODE_MEDIA_PAUSE
  };

  @override
  ProtocolType get protocol => ProtocolType.androidtv;

  @override
  Capabilities get capabilities => const Capabilities(
        pointer: false,
        textInput: true,
        channelButtons: true,
        numberPad: true,
      );

  /// Discovery is mDNS (`_androidtvremote2._tcp`); until that and the pairing
  /// handshake land, devices are added manually by IP. Emits nothing for now.
  @override
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)}) =>
      const Stream<Device>.empty();

  @override
  Future<void> connect(Device device) async {
    emitStatus(ConnectionStatus.connecting);
    emitStatus(ConnectionStatus.error);
    throw const PairingRequiredException(
      'Android TV pairing needs the 6-digit code shown on the TV. '
      'This handshake is not enabled in this build yet.',
    );
  }

  @override
  Future<void> sendKey(RemoteKey key) async =>
      throw const RemoteException('Android TV is not connected');

  @override
  Future<void> disconnect() async => emitStatus(ConnectionStatus.disconnected);
}
