import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_status.dart';
import '../../models/remote_key.dart';
import '../../state/active_device_provider.dart';
import '../../state/connection_provider.dart';
import '../../theme/app_colors.dart';
import '../remote_actions.dart';

/// The Remote tab — a native reimplementation of the "WiFi Remote" mockup's
/// remote page. Talks only to the active controller via [pressKey]; no brand
/// logic. Buttons gate on the active controller's [Capabilities].
class RemoteScreen extends ConsumerWidget {
  const RemoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(activeDeviceProvider);
    final status = ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;

    final caps = ref.watch(activeControllerProvider)?.capabilities;
    final navOn = caps?.supportsNavigation ?? true;
    final powerOn = caps?.supportsPower ?? true;
    final chOn = caps?.channelButtons ?? true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
      child: Column(
        children: [
          _ConnectedBar(
            name: device?.name ?? 'No TV selected',
            status: status,
            hasDevice: device != null,
            powerEnabled: powerOn,
            onPower: () => pressKey(context, ref, RemoteKey.power),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DpadRing(
                      onKey: (k) => pressKey(context, ref, k),
                      enabled: navOn,
                    ),
                    const SizedBox(height: 26),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: _NavRow(
                        onKey: (k) => pressKey(context, ref, k),
                        enabled: navOn,
                      ),
                    ),
                    const SizedBox(height: 26),
                    _Rockers(
                      onKey: (k) => pressKey(context, ref, k),
                      channelEnabled: chOn,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connected bar
// ---------------------------------------------------------------------------

class _ConnectedBar extends StatelessWidget {
  const _ConnectedBar({
    required this.name,
    required this.status,
    required this.hasDevice,
    required this.powerEnabled,
    required this.onPower,
  });

  final String name;
  final ConnectionStatus status;
  final bool hasDevice;
  final bool powerEnabled;
  final VoidCallback onPower;

  @override
  Widget build(BuildContext context) {
    final (Color dot, String label, bool pulse) = switch (status) {
      ConnectionStatus.connected => (AppColors.green, 'Connected', true),
      ConnectionStatus.connecting => (
          const Color(0xFFE0A93B),
          'Connecting…',
          false
        ),
      ConnectionStatus.error => (AppColors.textFaint, 'Disconnected', false),
      ConnectionStatus.disconnected => (
          AppColors.textFaint,
          hasDevice ? 'Not connected' : 'Tap Devices to connect',
          false
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
      child: Row(
        children: [
          _StatusDot(color: dot, pulse: pulse),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _PowerButton(enabled: powerEnabled, onTap: onPower),
        ],
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulse && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.4).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: dot,
    );
  }
}

class _PowerButton extends StatefulWidget {
  const _PowerButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final visual = AnimatedScale(
      scale: _down ? 0.92 : 1,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _down ? AppColors.powerSoftBg : AppColors.card,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.power_settings_new,
            size: 20, color: AppColors.powerRed),
      ),
    );
    if (!widget.enabled) return Opacity(opacity: 0.4, child: visual);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: visual,
    );
  }
}

// ---------------------------------------------------------------------------
// D-pad ring
// ---------------------------------------------------------------------------

enum _Dir { up, down, left, right }

class _DpadRing extends StatelessWidget {
  const _DpadRing({required this.onKey, required this.enabled});
  final void Function(RemoteKey) onKey;
  final bool enabled;

  static const double _size = 236;

  @override
  Widget build(BuildContext context) {
    Widget arrow(_Dir dir, RemoteKey key) {
      return Positioned.fromRect(
        rect: _arrowRect(dir),
        child: _DpadArrow(
          dir: dir,
          enabled: enabled,
          onTap: () => onKey(key),
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 30,
                    spreadRadius: -8,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
            ),
            // Crosshair lines.
            const Positioned(
              left: _size / 2 - 0.5,
              top: 24,
              bottom: 24,
              child: SizedBox(
                width: 1,
                child: ColoredBox(color: AppColors.divider),
              ),
            ),
            const Positioned(
              top: _size / 2 - 0.5,
              left: 24,
              right: 24,
              child: SizedBox(
                height: 1,
                child: ColoredBox(color: AppColors.divider),
              ),
            ),
            arrow(_Dir.up, RemoteKey.up),
            arrow(_Dir.down, RemoteKey.down),
            arrow(_Dir.left, RemoteKey.left),
            arrow(_Dir.right, RemoteKey.right),
            Positioned(
              top: 68,
              left: 68,
              child: _OkButton(
                enabled: enabled,
                onTap: () => onKey(RemoteKey.ok),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 70×70 hit areas hugging each edge, matching the mockup's absolute layout.
  static Rect _arrowRect(_Dir dir) => switch (dir) {
        _Dir.up => const Rect.fromLTWH(83, 4, 70, 70),
        _Dir.down => const Rect.fromLTWH(83, _size - 74, 70, 70),
        _Dir.left => const Rect.fromLTWH(4, 83, 70, 70),
        _Dir.right => const Rect.fromLTWH(_size - 74, 83, 70, 70),
      };
}

class _DpadArrow extends StatefulWidget {
  const _DpadArrow({
    required this.dir,
    required this.enabled,
    required this.onTap,
  });

  final _Dir dir;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_DpadArrow> createState() => _DpadArrowState();
}

class _DpadArrowState extends State<_DpadArrow> {
  bool _down = false;

  BorderRadius get _radius => switch (widget.dir) {
        _Dir.up => const BorderRadius.vertical(top: Radius.circular(35)),
        _Dir.down => const BorderRadius.vertical(bottom: Radius.circular(35)),
        _Dir.left => const BorderRadius.horizontal(left: Radius.circular(35)),
        _Dir.right => const BorderRadius.horizontal(right: Radius.circular(35)),
      };

  Alignment get _align => switch (widget.dir) {
        _Dir.up => Alignment.topCenter,
        _Dir.down => Alignment.bottomCenter,
        _Dir.left => Alignment.centerLeft,
        _Dir.right => Alignment.centerRight,
      };

  EdgeInsets get _pad => switch (widget.dir) {
        _Dir.up => const EdgeInsets.only(top: 12),
        _Dir.down => const EdgeInsets.only(bottom: 12),
        _Dir.left => const EdgeInsets.only(left: 12),
        _Dir.right => const EdgeInsets.only(right: 12),
      };

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(
        color: _down ? AppColors.accentSoft : Colors.transparent,
        borderRadius: _radius,
      ),
      alignment: _align,
      padding: _pad,
      child: CustomPaint(
        size: const Size(16, 10),
        painter: _TrianglePainter(widget.dir, AppColors.arrowGrey),
      ),
    );

    if (!widget.enabled) return body;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: body,
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.dir, this.color);
  final _Dir dir;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    final path = Path();
    switch (dir) {
      case _Dir.up:
        path
          ..moveTo(0, h)
          ..lineTo(w, h)
          ..lineTo(w / 2, 0);
      case _Dir.down:
        path
          ..moveTo(0, 0)
          ..lineTo(w, 0)
          ..lineTo(w / 2, h);
      case _Dir.left:
        path
          ..moveTo(h, 0)
          ..lineTo(h, w)
          ..lineTo(0, w / 2);
      case _Dir.right:
        path
          ..moveTo(0, 0)
          ..lineTo(0, w)
          ..lineTo(h, w / 2);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) =>
      old.dir != dir || old.color != color;
}

class _OkButton extends StatefulWidget {
  const _OkButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_OkButton> createState() => _OkButtonState();
}

class _OkButtonState extends State<_OkButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: _down ? AppColors.accent : const Color(0xFFFBFBFD),
        shape: BoxShape.circle,
        border: Border.all(
          color: _down ? AppColors.accent : AppColors.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 14,
            spreadRadius: -4,
            offset: Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'OK',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: _down ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );

    if (!widget.enabled) return body;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Back / Home / Menu
// ---------------------------------------------------------------------------

class _NavRow extends StatelessWidget {
  const _NavRow({required this.onKey, required this.enabled});
  final void Function(RemoteKey) onKey;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Row(
        children: [
          Expanded(
            child: _Pill(
              label: 'Back',
              enabled: enabled,
              onTap: () => onKey(RemoteKey.back),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Pill(
              label: 'Home',
              enabled: enabled,
              onTap: () => onKey(RemoteKey.home),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Pill(
              label: 'Menu',
              enabled: enabled,
              onTap: () => onKey(RemoteKey.menu),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill({
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedScale(
      scale: _down ? 0.96 : 1,
      duration: const Duration(milliseconds: 90),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _down ? AppColors.accentSoft : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _down ? AppColors.accent : AppColors.textPrimary,
          ),
        ),
      ),
    );

    if (!widget.enabled) return body;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// VOL / MUTE / CH rockers
// ---------------------------------------------------------------------------

class _Rockers extends StatelessWidget {
  const _Rockers({required this.onKey, required this.channelEnabled});
  final void Function(RemoteKey) onKey;
  final bool channelEnabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Stepper(
          label: 'VOL',
          onTop: () => onKey(RemoteKey.volumeUp),
          onBottom: () => onKey(RemoteKey.volumeDown),
        ),
        const SizedBox(width: 18),
        // Mute is a blind toggle on most TVs (no state read-back), so the button
        // doesn't pretend to know whether the TV is currently muted.
        _MuteButton(onTap: () => onKey(RemoteKey.mute)),
        const SizedBox(width: 18),
        _Stepper(
          label: 'CH',
          enabled: channelEnabled,
          onTop: () => onKey(RemoteKey.channelUp),
          onBottom: () => onKey(RemoteKey.channelDown),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.onTop,
    required this.onBottom,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTop;
  final VoidCallback onBottom;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Column(
        children: [
          Container(
            width: 84,
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 14,
                  spreadRadius: -4,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(
                  child: _RockerHalf(
                    glyph: '+',
                    enabled: enabled,
                    onTap: onTop,
                    radius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                ),
                const SizedBox(
                  height: 1,
                  child: ColoredBox(color: AppColors.divider),
                ),
                Expanded(
                  child: _RockerHalf(
                    glyph: '−', // minus sign
                    enabled: enabled,
                    onTap: onBottom,
                    radius:
                        const BorderRadius.vertical(bottom: Radius.circular(24)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _RockerHalf extends StatefulWidget {
  const _RockerHalf({
    required this.glyph,
    required this.enabled,
    required this.onTap,
    required this.radius,
  });

  final String glyph;
  final bool enabled;
  final VoidCallback onTap;
  final BorderRadius radius;

  @override
  State<_RockerHalf> createState() => _RockerHalfState();
}

class _RockerHalfState extends State<_RockerHalf> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _down ? AppColors.accentSoft : Colors.transparent,
        borderRadius: widget.radius,
      ),
      alignment: Alignment.center,
      child: Text(
        widget.glyph,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w300,
          color: _down ? AppColors.accent : AppColors.textPrimary,
        ),
      ),
    );

    if (!widget.enabled) return body;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: body,
    );
  }
}

class _MuteButton extends StatefulWidget {
  const _MuteButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_MuteButton> createState() => _MuteButtonState();
}

class _MuteButtonState extends State<_MuteButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedScale(
      scale: _down ? 0.92 : 1,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: 68,
        height: 68,
        decoration: const BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 14,
              spreadRadius: -4,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.volume_off,
          size: 26,
          color: AppColors.textPrimary,
        ),
      ),
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: Column(
        children: [
          body,
          const SizedBox(height: 8),
          const Text(
            'MUTE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
