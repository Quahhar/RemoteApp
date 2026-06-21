import 'package:flutter/foundation.dart';

/// Declares what a given [RemoteController] can do, so the UI can adapt without
/// ever naming a brand. e.g. the Touchpad screen shows a pointer surface when
/// [supportsPointer] is true and the Keyboard screen enables its field only
/// when [supportsTextInput] is true.
@immutable
class Capabilities {
  const Capabilities({
    this.supportsPointer = false,
    this.supportsTextInput = false,
    this.channelButtons = true,
    this.numberPad = false,
    this.requiresPairingCode = false,
  });

  /// Supports free pointer/touchpad movement (relative cursor moves + click).
  final bool supportsPointer;

  /// Supports sending arbitrary text (and backspace/enter) to the TV.
  final bool supportsTextInput;

  /// Exposes dedicated channel up/down controls.
  final bool channelButtons;

  /// Supports a 0-9 number pad for direct channel entry.
  final bool numberPad;

  /// Pairing requires entering a code shown on the TV (e.g. Android TV). The
  /// Devices flow runs [RemoteController.beginPairing]/[RemoteController.completePairing]
  /// before connecting. (LG/Samsung pair by accepting a prompt on the TV, so
  /// they leave this false.)
  final bool requiresPairingCode;

  @override
  bool operator ==(Object other) =>
      other is Capabilities &&
      other.supportsPointer == supportsPointer &&
      other.supportsTextInput == supportsTextInput &&
      other.channelButtons == channelButtons &&
      other.numberPad == numberPad &&
      other.requiresPairingCode == requiresPairingCode;

  @override
  int get hashCode => Object.hash(supportsPointer, supportsTextInput,
      channelButtons, numberPad, requiresPairingCode);
}
