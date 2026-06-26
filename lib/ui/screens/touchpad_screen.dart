import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/remote_controller.dart';
import '../../models/remote_key.dart';
import '../../state/active_device_provider.dart';
import '../../state/preferences_provider.dart';
import '../../theme/app_colors.dart';
import '../remote_actions.dart';

/// The Trackpad tab — matches the mockup: a dotted pad you drag on (tap to
/// click) with a cursor dot that follows your finger, plus a "Type on TV" card.
/// The pad drives the pointer when the active controller supports one and
/// otherwise translates swipes into D-pad keys (tap = select). Decided from
/// [Capabilities], never the brand.
class TouchpadScreen extends ConsumerWidget {
  const TouchpadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(activeControllerProvider);
    final pointer = controller?.capabilities.supportsPointer ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trackpad',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Drag to move • tap to click',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _TrackpadArea(
              pointer: pointer,
              onMove: (dx, dy) => _move(ref, dx, dy),
              onTap: () => _primary(context, ref, pointer),
              onSwipe: (key) => pressKey(context, ref, key),
            ),
          ),
          const SizedBox(height: 16),
          const _SendCard(),
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
  Future<void> _primary(
      BuildContext context, WidgetRef ref, bool pointer) async {
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
    if (ref.read(hapticsEnabledProvider)) HapticFeedback.selectionClick();
    try {
      await controller.click();
    } on RemoteException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _TrackpadArea extends StatefulWidget {
  const _TrackpadArea({
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
  State<_TrackpadArea> createState() => _TrackpadAreaState();
}

class _TrackpadAreaState extends State<_TrackpadArea> {
  static const double _swipeThreshold = 24;
  Offset _pos = Offset.zero;
  bool _active = false;
  bool _started = false;
  double _dx = 0;
  double _dy = 0;

  void _setPos(Offset p) => setState(() {
        _pos = p;
        _started = true;
      });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _setPos(d.localPosition),
      onTap: widget.onTap,
      onPanStart: (d) {
        _dx = 0;
        _dy = 0;
        setState(() {
          _pos = d.localPosition;
          _started = true;
          _active = true;
        });
      },
      onPanUpdate: (d) {
        if (widget.pointer) {
          widget.onMove(d.delta.dx, d.delta.dy);
        } else {
          _dx += d.delta.dx;
          _dy += d.delta.dy;
        }
        setState(() => _pos = d.localPosition);
      },
      onPanEnd: (_) {
        setState(() => _active = false);
        if (widget.pointer) return;
        if (_dx.abs() < _swipeThreshold && _dy.abs() < _swipeThreshold) return;
        if (_dx.abs() >= _dy.abs()) {
          widget.onSwipe(_dx > 0 ? RemoteKey.right : RemoteKey.left);
        } else {
          widget.onSwipe(_dy > 0 ? RemoteKey.down : RemoteKey.up);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 20,
              spreadRadius: -8,
              offset: Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: _DotGridPainter()),
            ),
            Center(
              child: AnimatedOpacity(
                opacity: _started ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: const Text(
                  'Move your finger here',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.hintFaint,
                  ),
                ),
              ),
            ),
            Positioned(
              left: _pos.dx - 15,
              top: _pos.dy - 15,
              child: AnimatedOpacity(
                opacity: _started ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: AnimatedScale(
                  scale: _active ? 1.3 : 1,
                  duration: const Duration(milliseconds: 80),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0x2E2F6BF6), // accent @ .18
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.dotGrid;
    const step = 22.0;
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => false;
}

/// The "Type on TV" card. Sends on the Send button or keyboard submit; disabled
/// with a clear message when the controller can't accept text.
class _SendCard extends ConsumerStatefulWidget {
  const _SendCard();

  @override
  ConsumerState<_SendCard> createState() => _SendCardState();
}

class _SendCardState extends ConsumerState<_SendCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Future<void> _queue = Future<void>.value();
  String _sent = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final controller = ref.read(activeControllerProvider);
    if (controller == null) {
      promptNoDevice(context, ref);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    _controller.clear();
    setState(() => _sent = text);
    if (ref.read(hapticsEnabledProvider)) HapticFeedback.selectionClick();
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            spreadRadius: -6,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 9),
            child: Text(
              'TYPE ON TV',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: _focus.hasFocus
                        ? AppColors.accentSoft
                        : AppColors.fieldBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    enabled: supported,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: supported
                          ? 'Search or enter text…'
                          : 'Keyboard not supported on this device',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _SendButton(onTap: supported ? _send : null),
            ],
          ),
          if (_sent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 11, 4, 2),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMuted),
                  children: [
                    const TextSpan(text: 'Sent to TV: '),
                    TextSpan(
                      text: '"$_sent"',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const SizedBox(
          width: 46,
          height: 46,
          child: Icon(Icons.arrow_forward, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}
