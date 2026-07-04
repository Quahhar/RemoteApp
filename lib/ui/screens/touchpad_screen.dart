import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../controllers/remote_controller.dart';
import '../../models/connection_status.dart';
import '../../models/remote_key.dart';
import '../../purchases/purchase_controller.dart';
import '../../state/active_device_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/preferences_provider.dart';
import '../../theme/app_colors.dart';
import '../remote_actions.dart';
import '../snackbar.dart';
import '../widgets/upgrade_button.dart';
import 'settings_screen.dart';

/// The Trackpad tab — matches the mockup: a dotted "TOUCHPAD AREA" you drag on
/// (tap to click) with a cursor that follows your finger, LEFT/RIGHT click
/// buttons, and a mic + "Type to send to TV" bar. The pad drives the pointer
/// when the active controller supports one, otherwise translates swipes into
/// D-pad keys (tap = select). Decided from [Capabilities], never the brand. The
/// trackpad is a Pro feature; the type bar stays the existing Pro/free gating.
class TouchpadScreen extends ConsumerWidget {
  const TouchpadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(activeControllerProvider);
    final device = ref.watch(activeDeviceProvider);
    final status = ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;
    final pointer = controller?.capabilities.supportsPointer ?? false;
    // Repaint on palette flips (AppColors getters aren't reactive on their own).
    ref.watch(effectiveDarkModeProvider);
    // The trackpad/mouse is a Pro feature; the type bar below stays free-ish
    // (its own gating in _SendBar).
    final locked = !ref.watch(isProProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            connected: status == ConnectionStatus.connected,
            deviceName: device?.name,
            onSettings: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _TrackpadArea(
              pointer: pointer,
              locked: locked,
              onLocked: () => UpgradeButton.open(context),
              onMove: (dx, dy) => _move(ref, dx, dy),
              onTap: () => _primary(context, ref, pointer),
              onSwipe: (key) => pressKey(context, ref, key),
            ),
          ),
          const SizedBox(height: 12),
          _ClickRow(
            locked: locked,
            onLocked: () => UpgradeButton.open(context),
            onLeft: () => _primary(context, ref, pointer),
            onRight: () => pressKey(context, ref, RemoteKey.back),
          ),
          const SizedBox(height: 12),
          const _SendBar(),
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
      showSnack(messenger, e.message);
    } catch (_) {
      showSnack(messenger, 'Couldn’t send that command');
    }
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.connected,
    required this.deviceName,
    required this.onSettings,
  });

  final bool connected;
  final String? deviceName;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          _GearButton(onTap: onSettings),
          const SizedBox(width: 12),
          Text(
            'Trackpad',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (deviceName != null)
            _ConnChip(connected: connected, name: deviceName!)
          else
            const UpgradeButton(),
        ],
      ),
    );
  }
}

class _ConnChip extends StatelessWidget {
  const _ConnChip({required this.connected, required this.name});
  final bool connected;
  final String name;

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppColors.accent : AppColors.hintFaint;
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GearButton extends StatelessWidget {
  const _GearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.settings, size: 22, color: AppColors.dpadArrow),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trackpad surface
// ---------------------------------------------------------------------------

class _TrackpadArea extends StatefulWidget {
  const _TrackpadArea({
    required this.pointer,
    required this.locked,
    required this.onLocked,
    required this.onMove,
    required this.onTap,
    required this.onSwipe,
  });

  final bool pointer;

  /// When true (free user), the pad doesn't move the pointer — any touch calls
  /// [onLocked] (which opens the upgrade screen) instead. No visual change.
  final bool locked;
  final VoidCallback onLocked;
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
  bool _prompting = false;
  double _dx = 0;
  double _dy = 0;

  /// Free user touched the pad: open the upgrade screen once (guarded so a drag
  /// can't reopen it repeatedly).
  void _prompt() {
    if (_prompting) return;
    _prompting = true;
    widget.onLocked();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _prompting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        if (widget.locked) return;
        setState(() {
          _pos = d.localPosition;
          _started = true;
        });
      },
      onTap: widget.locked ? _prompt : widget.onTap,
      onPanStart: (d) {
        if (widget.locked) {
          _prompt();
          return;
        }
        _dx = 0;
        _dy = 0;
        setState(() {
          _pos = d.localPosition;
          _started = true;
          _active = true;
        });
      },
      onPanUpdate: (d) {
        if (widget.locked) return;
        if (widget.pointer) {
          widget.onMove(d.delta.dx, d.delta.dy);
        } else {
          _dx += d.delta.dx;
          _dy += d.delta.dy;
        }
        setState(() => _pos = d.localPosition);
      },
      onPanEnd: (_) {
        if (widget.locked) return;
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
          color: AppColors.inset,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.fieldBorder),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app, size: 52, color: AppColors.hintFaint),
                    const SizedBox(height: 12),
                    Text(
                      'TOUCHPAD AREA',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3,
                        color: AppColors.hintFaint,
                      ),
                    ),
                  ],
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
                      color: const Color(0x2EF5A623), // accent @ .18
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

// ---------------------------------------------------------------------------
// Left / Right click
// ---------------------------------------------------------------------------

class _ClickRow extends StatelessWidget {
  const _ClickRow({
    required this.locked,
    required this.onLocked,
    required this.onLeft,
    required this.onRight,
  });

  final bool locked;
  final VoidCallback onLocked;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ClickButton(
            label: 'LEFT CLICK',
            onTap: locked ? onLocked : onLeft,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ClickButton(
            label: 'RIGHT CLICK',
            onTap: locked ? onLocked : onRight,
          ),
        ),
      ],
    );
  }
}

class _ClickButton extends StatefulWidget {
  const _ClickButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_ClickButton> createState() => _ClickButtonState();
}

class _ClickButtonState extends State<_ClickButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _down ? AppColors.accentSoft : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: _down ? AppColors.accentText : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mic + type-to-send bar
// ---------------------------------------------------------------------------

/// The "Type to send to TV" bar. Sends on the Send button or keyboard submit;
/// disabled with a clear message when the controller can't accept text. The mic
/// button focuses the field (no on-device voice backend yet).
class _SendBar extends ConsumerStatefulWidget {
  const _SendBar();

  @override
  ConsumerState<_SendBar> createState() => _SendBarState();
}

class _SendBarState extends ConsumerState<_SendBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final SpeechToText _speech = SpeechToText();
  Future<void> _queue = Future<void>.value();
  bool _speechReady = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _speech.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Toggle voice dictation: start listening and stream the recognised words
  /// into the field (the user reviews, then taps send), or stop if already
  /// listening. Degrades to a clear message when voice isn't available or the
  /// mic permission is declined.
  Future<void> _toggleMic() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (s) {
          if (mounted && (s == 'done' || s == 'notListening')) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    }
    if (!_speechReady) {
      showSnack(messenger, 'Voice input isn’t available on this device.');
      return;
    }
    _focus.unfocus(); // don't let the keyboard fight the mic
    if (ref.read(hapticsEnabledProvider)) HapticFeedback.selectionClick();
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        _controller.text = r.recognizedWords;
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
        if (r.finalResult) setState(() => _listening = false);
      },
      listenOptions: SpeechListenOptions(partialResults: true),
    );
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
    if (ref.read(hapticsEnabledProvider)) HapticFeedback.selectionClick();
    _queue = _queue.then((_) async {
      try {
        await controller.sendText(text);
      } on RemoteException catch (e) {
        showSnack(messenger, e.message);
      } catch (_) {
        showSnack(messenger, 'Couldn’t send text');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(activeControllerProvider);
    final supported = controller?.capabilities.supportsTextInput ?? false;
    // The keyboard is a Pro feature: a free user tapping it opens the upgrade
    // screen. When the protocol can't accept text at all, keep the plain
    // "not supported" state instead (buying wouldn't help there).
    final locked = supported && !ref.watch(isProProvider);

    final bar = Row(
      children: [
        _MicButton(
          enabled: supported,
          listening: _listening,
          onTap: _toggleMic,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _focus.hasFocus ? AppColors.accentSoft : AppColors.fieldBg,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: _focus.hasFocus ? AppColors.accent : AppColors.fieldBorder,
              ),
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
              style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: supported
                    ? 'Type to send to TV'
                    : 'Keyboard not supported on this device',
                hintStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _SendButton(onTap: supported ? _send : null),
      ],
    );

    if (!locked) return bar;
    // Intercept any tap and show the paywall; the bar itself can't be focused.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => UpgradeButton.open(context),
      child: IgnorePointer(child: bar),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.enabled,
    required this.listening,
    required this.onTap,
  });
  final bool enabled;
  final bool listening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (!enabled) {
      bg = AppColors.fieldBg;
      fg = AppColors.hintFaint;
    } else if (listening) {
      bg = AppColors.accentSoft;
      fg = AppColors.accentText;
    } else {
      bg = AppColors.fieldBg;
      fg = AppColors.textMuted;
    }
    return Material(
      color: bg,
      shape: CircleBorder(
        side: BorderSide(
          color: listening ? AppColors.accent : AppColors.fieldBorder,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(Icons.mic, size: 22, color: fg),
        ),
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
      color: enabled ? AppColors.accent : AppColors.hintFaint,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 50,
          height: 50,
          child: Icon(Icons.arrow_upward, size: 21, color: Colors.white),
        ),
      ),
    );
  }
}
