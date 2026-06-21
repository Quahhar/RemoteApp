import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/remote_controller.dart';
import '../../models/remote_key.dart';
import '../../state/active_device_provider.dart';
import '../../theme/app_colors.dart';
import '../remote_actions.dart';

/// Touchpad + inline keyboard, matching the Canvas mockup. The gesture surface
/// drives the pointer when the active controller supports one and otherwise
/// translates swipes into D-pad keys (tap = select). LEFT/RIGHT CLICK map to a
/// primary click and the context menu. The send bar routes text via `sendText`
/// and disables itself with a clear message when text isn't supported. Decided
/// from [Capabilities], never the brand.
class TouchpadScreen extends ConsumerWidget {
  const TouchpadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(activeControllerProvider);
    final pointer = controller?.capabilities.supportsPointer ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: Column(
        children: [
          Expanded(
            child: _TouchpadArea(
              pointer: pointer,
              onMove: (dx, dy) => _move(ref, dx, dy),
              onTap: () => _primary(context, ref, pointer),
              onSwipe: (key) => pressKey(context, ref, key),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ClickButton(
                  label: 'LEFT CLICK',
                  onTap: () => _primary(context, ref, pointer),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ClickButton(
                  label: 'RIGHT CLICK',
                  onTap: () => pressKey(context, ref, RemoteKey.menu),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _SendBar(),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  void _move(WidgetRef ref, double dx, double dy) {
    final controller = ref.read(activeControllerProvider);
    if (controller == null) return;
    // Fire-and-forget; transient move errors are ignored (a click surfaces them).
    controller.movePointer(dx, dy).catchError((_) {});
  }

  /// Primary action: a pointer click when supported, otherwise select (OK).
  Future<void> _primary(BuildContext context, WidgetRef ref, bool pointer) async {
    if (!pointer) {
      await pressKey(context, ref, RemoteKey.ok);
      return;
    }
    final controller = ref.read(activeControllerProvider);
    if (controller == null) {
      promptNoDevice(context, ref);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.selectionClick();
    try {
      await controller.click();
    } on RemoteException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _TouchpadArea extends StatefulWidget {
  const _TouchpadArea({
    required this.pointer,
    required this.onMove,
    required this.onTap,
    required this.onSwipe,
  });

  final bool pointer;
  final void Function(double dx, double dy) onMove;
  final VoidCallback onTap;
  final void Function(RemoteKey key) onSwipe;

  @override
  State<_TouchpadArea> createState() => _TouchpadAreaState();
}

class _TouchpadAreaState extends State<_TouchpadArea> {
  static const double _swipeThreshold = 24;
  double _dx = 0;
  double _dy = 0;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label) = widget.pointer
        ? (Icons.touch_app, 'TOUCHPAD AREA')
        : (Icons.swipe, 'SWIPE TO NAVIGATE');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onPanStart: widget.pointer
          ? null
          : (_) {
              _dx = 0;
              _dy = 0;
            },
      onPanUpdate: (d) {
        if (widget.pointer) {
          widget.onMove(d.delta.dx, d.delta.dy);
        } else {
          _dx += d.delta.dx;
          _dy += d.delta.dy;
        }
      },
      onPanEnd: widget.pointer
          ? null
          : (_) {
              if (_dx.abs() < _swipeThreshold && _dy.abs() < _swipeThreshold) {
                return;
              }
              if (_dx.abs() >= _dy.abs()) {
                widget.onSwipe(_dx > 0 ? RemoteKey.right : RemoteKey.left);
              } else {
                widget.onSwipe(_dy > 0 ? RemoteKey.down : RemoteKey.up);
              }
            },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardFill,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1A463778), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 58, color: const Color(0xFF8B88A0)),
              const SizedBox(height: 18),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                  color: Color(0xFF9A98AA),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClickButton extends StatelessWidget {
  const _ClickButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x99FFFFFF),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x99FFFFFF)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: AppColors.icon,
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline "Type to send to TV" bar. Sends on the Send button or keyboard
/// submit; disabled with a clear message when the controller can't accept text.
class _SendBar extends ConsumerStatefulWidget {
  const _SendBar();

  @override
  ConsumerState<_SendBar> createState() => _SendBarState();
}

class _SendBarState extends ConsumerState<_SendBar> {
  final _controller = TextEditingController();
  Future<void> _queue = Future<void>.value();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.isEmpty) return;
    final controller = ref.read(activeControllerProvider);
    if (controller == null) {
      promptNoDevice(context, ref);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    _controller.clear();
    HapticFeedback.selectionClick();
    _queue = _queue.then((_) async {
      try {
        await controller.sendText(text);
      } on RemoteException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to send text')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(activeControllerProvider);
    final supported = controller?.capabilities.supportsTextInput ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0x99FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x99FFFFFF)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14463778), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.keyboard, size: 24, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: supported,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontSize: 17, color: AppColors.icon),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: supported
                    ? 'Type to send to TV'
                    : 'Keyboard not supported on this device',
                hintStyle: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _SendButton(onTap: supported ? _send : null),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.accent : const Color(0xFFC2C0CE),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: const SizedBox(
          width: 50,
          height: 50,
          child: Icon(Icons.send, size: 24, color: Colors.white),
        ),
      ),
    );
  }
}
