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
  });

  /// Supports free pointer/touchpad movement (relative cursor moves + click).
  final bool supportsPointer;

  /// Supports sending arbitrary text (and backspace/enter) to the TV.
  final bool supportsTextInput;

  /// Exposes dedicated channel up/down controls.
  final bool channelButtons;

  /// Supports a 0-9 number pad for direct channel entry.
  final bool numberPad;

  @override
  bool operator ==(Object other) =>
      other is Capabilities &&
      other.supportsPointer == supportsPointer &&
      other.supportsTextInput == supportsTextInput &&
      other.channelButtons == channelButtons &&
      other.numberPad == numberPad;

  @override
  int get hashCode =>
      Object.hash(supportsPointer, supportsTextInput, channelButtons, numberPad);
}
