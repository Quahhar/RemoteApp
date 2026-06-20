import 'package:flutter/foundation.dart';

/// Declares what a given [RemoteController] can do, so the UI can adapt without
/// ever naming a brand. e.g. the Touchpad screen shows a pointer surface when
/// [pointer] is true and falls back to D-pad keys otherwise.
@immutable
class Capabilities {
  const Capabilities({
    this.pointer = false,
    this.textInput = false,
    this.channelButtons = true,
    this.numberPad = false,
  });

  /// Supports free pointer/touchpad movement (relative cursor moves + click).
  final bool pointer;

  /// Supports sending arbitrary text (a soft keyboard) to the TV.
  final bool textInput;

  /// Exposes dedicated channel up/down controls.
  final bool channelButtons;

  /// Supports a 0-9 number pad for direct channel entry.
  final bool numberPad;

  @override
  bool operator ==(Object other) =>
      other is Capabilities &&
      other.pointer == pointer &&
      other.textInput == textInput &&
      other.channelButtons == channelButtons &&
      other.numberPad == numberPad;

  @override
  int get hashCode => Object.hash(pointer, textInput, channelButtons, numberPad);
}
