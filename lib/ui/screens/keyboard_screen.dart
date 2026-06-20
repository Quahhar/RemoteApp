import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/remote_controller.dart';
import '../../controllers/text_input.dart';
import '../../state/active_device_provider.dart';

/// On-screen keyboard. While the field is focused, typed and pasted text is
/// routed to the active controller via `sendText`; deletions become backspaces
/// and submit sends enter. Disabled with a clear message when the active
/// controller can't accept text. NOTE: functional layout pending the keyboard
/// design mockup.
class KeyboardScreen extends ConsumerStatefulWidget {
  const KeyboardScreen({super.key});

  @override
  ConsumerState<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends ConsumerState<KeyboardScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Last text we observed, to diff against for incremental sends.
  String _last = '';

  /// Guards programmatic edits so they don't echo back as user input.
  bool _suppress = false;

  /// Serializes sends so characters arrive at the TV in order.
  Future<void> _queue = Future<void>.value();

  static final String _backspaceStr = String.fromCharCode(kBackspace);
  static const String _enterStr = '\n';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (_suppress) return;
    final last = _last;
    _last = value;

    // Common prefix, then send backspaces for the removed tail + the new tail.
    var prefix = 0;
    final minLen = last.length < value.length ? last.length : value.length;
    while (prefix < minLen && last.codeUnitAt(prefix) == value.codeUnitAt(prefix)) {
      prefix++;
    }
    final removed = last.length - prefix;
    final added = value.substring(prefix);

    final payload = StringBuffer();
    for (var i = 0; i < removed; i++) {
      payload.write(_backspaceStr);
    }
    payload.write(added);
    _enqueue(payload.toString());
  }

  void _onSubmitted(String _) {
    _enqueue(_enterStr);
    _resetField();
    _focus.requestFocus();
  }

  void _backspace() {
    final text = _controller.text;
    if (text.isNotEmpty) {
      final next = text.substring(0, text.length - 1);
      _suppress = true;
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      _suppress = false;
      _last = next;
    }
    _enqueue(_backspaceStr);
  }

  void _resetField() {
    _suppress = true;
    _controller.clear();
    _suppress = false;
    _last = '';
  }

  void _enqueue(String payload) {
    if (payload.isEmpty) return;
    _queue = _queue.then((_) => _send(payload));
  }

  Future<void> _send(String text) async {
    final controller = ref.read(activeControllerProvider);
    if (controller == null) return;
    HapticFeedback.selectionClick();
    try {
      await controller.sendText(text);
    } on RemoteException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Failed to send text');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(activeControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    if (controller == null) {
      return const _Centered(
        icon: Icons.keyboard_outlined,
        text: 'Select a device to use the keyboard.',
      );
    }
    if (!controller.capabilities.supportsTextInput) {
      return const _Centered(
        icon: Icons.keyboard_hide_outlined,
        text: 'Keyboard not supported on this device.',
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Type here — characters are sent to your TV as you go.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.send,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Search or type…',
              ),
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _backspace,
                    icon: const Icon(Icons.backspace_outlined),
                    label: const Text('Backspace'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _onSubmitted(_controller.text),
                    icon: const Icon(Icons.keyboard_return),
                    label: const Text('Enter'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
