import 'package:flutter/material.dart';

/// The message currently on screen, tracked so we never stack duplicates.
String? _activeSnack;

/// Clear the de-duplication tracker. Call when switching tabs so the same
/// error message is allowed to show again on the new page.
void clearSnackTracker() {
  _activeSnack = null;
}

/// Show [message] as a SnackBar, de-duplicated:
///  - If the *same* message is already showing, it's left in place — tapping a
///    failing action 1000 times shows one SnackBar, held until it times out,
///    not 1000 stacked ones.
///  - A *different* message replaces whatever is showing, so the banner always
///    reflects the latest distinct result.
///
/// Takes a [ScaffoldMessengerState] (not a BuildContext) so callers can capture
/// it before an `await` and use it safely across async gaps.
void showSnack(ScaffoldMessengerState messenger, String message) {
  if (_activeSnack == message) return; // already showing this — keep it
  _activeSnack = message;
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(content: Text(message))).closed.then((_) {
    // Only clear the tracker if a newer message hasn't taken over.
    if (_activeSnack == message) _activeSnack = null;
  });
}
