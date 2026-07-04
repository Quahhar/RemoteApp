import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ad_service.dart';
import '../../models/connection_status.dart';
import '../../models/remote_key.dart';
import '../../purchases/purchase_controller.dart';
import '../../state/active_device_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/preferences_provider.dart';
import '../../theme/app_colors.dart';
import '../remote_actions.dart';
import '../widgets/more_sheet.dart';
import '../widgets/upgrade_button.dart';
import 'settings_screen.dart';

/// The Remote tab — a native reimplementation of the "WiFi Remote" mockup's
/// remote page: a device card with a coral power button, a 3D D-pad dial,
/// VOL/CH rocker pills, and a Back/Home/Menu/More row. The More button opens the
/// extended-controls sheet (Pro-gated). Talks only to the active controller via
/// [pressKey]; buttons gate on the active controller's [Capabilities].
class RemoteScreen extends ConsumerWidget {
  const RemoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(activeDeviceProvider);
    final status = ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;

    // Repaint on palette flips (AppColors getters aren't reactive on their own).
    ref.watch(effectiveDarkModeProvider);
    final caps = ref.watch(activeControllerProvider)?.capabilities;
    final navOn = caps?.supportsNavigation ?? true;
    final powerOn = caps?.supportsPower ?? true;
    final chOn = caps?.channelButtons ?? true;

    void onKey(RemoteKey k) => pressKey(context, ref, k);

    void openMore() {
      // The sheet opens for everyone; free users see every control but a tap
      // redirects to the upgrade page (gating happens inside the sheet).
      showMoreSheet(context, ref, locked: !ref.read(isProProvider));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        children: [
          _Header(
            onSettings: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _DeviceCard(
            name: device?.name ?? 'No TV selected',
            subtitle: device?.protocol.label,
            status: status,
            hasDevice: device != null,
            powerEnabled: powerOn,
            onPower: () => onKey(RemoteKey.power),
            // The ad countdown lives in the service so it keeps running across
            // tab switches; the power button just paints whatever it holds.
            adCountdown: ref.read(adServiceProvider).countdown,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _DpadDial(onKey: onKey, enabled: navOn),
                  const SizedBox(height: 24),
                  _Rockers(onKey: onKey, channelEnabled: chOn),
                  const SizedBox(height: 24),
                  _BottomRow(onKey: onKey, navEnabled: navOn, onMore: openMore),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          _GearButton(onTap: onSettings),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Remote',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const UpgradeButton(),
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
// Device card
// ---------------------------------------------------------------------------

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.name,
    required this.subtitle,
    required this.status,
    required this.hasDevice,
    required this.powerEnabled,
    required this.onPower,
    required this.adCountdown,
  });

  final String name;
  final String? subtitle;
  final ConnectionStatus status;
  final bool hasDevice;
  final bool powerEnabled;
  final VoidCallback onPower;
  final ValueListenable<int?> adCountdown;

  @override
  Widget build(BuildContext context) {
    final (Color dot, String label, bool pulse) = switch (status) {
      ConnectionStatus.connected => (AppColors.accent, 'Connected', true),
      ConnectionStatus.connecting => (AppColors.accent, 'Connecting…', false),
      ConnectionStatus.error => (AppColors.hintFaint, 'Disconnected', false),
      ConnectionStatus.disconnected => (
          AppColors.hintFaint,
          hasDevice ? 'Not connected' : 'Tap Devices to connect',
          false
        ),
    };
    final statusLine = subtitle == null ? label : '$label · $subtitle';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D46377A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _StatusDot(color: dot, pulse: pulse),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        statusLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _PowerButton(
            enabled: powerEnabled,
            onTap: onPower,
            countdown: adCountdown,
          ),
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
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: widget.color.withValues(alpha: 0.18), spreadRadius: 3),
        ],
      ),
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
  const _PowerButton({
    required this.enabled,
    required this.onTap,
    required this.countdown,
  });
  final bool enabled;
  final VoidCallback onTap;

  /// `null` while idle (normal power button); a remaining-seconds value while an
  /// ad counts down, in which case the button becomes a non-interactive number.
  final ValueListenable<int?> countdown;

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: widget.countdown,
      builder: (context, seconds, _) =>
          seconds != null ? _countdown(seconds) : _power(),
    );
  }

  /// The coral circle, same size/shadow as the power button, holding the
  /// remaining seconds. Inert: the ad fires on its own when it reaches zero.
  Widget _countdown(int seconds) {
    return _PowerCircle(
      color: AppColors.powerSoftBg,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Text(
          '$seconds',
          key: ValueKey(seconds),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.powerRed,
          ),
        ),
      ),
    );
  }

  Widget _power() {
    final visual = AnimatedScale(
      scale: _down ? 0.92 : 1,
      duration: const Duration(milliseconds: 90),
      child: _PowerCircle(
        color: _down ? AppColors.powerSoftPressed : AppColors.powerSoftBg,
        child: Icon(Icons.power_settings_new,
            size: 27, color: AppColors.powerRed),
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

/// The 58px coral disc shared by the power glyph and the ad countdown.
class _PowerCircle extends StatelessWidget {
  const _PowerCircle({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x38E07856),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// D-pad dial
// ---------------------------------------------------------------------------

class _DpadDial extends StatelessWidget {
  const _DpadDial({required this.onKey, required this.enabled});
  final void Function(RemoteKey) onKey;
  final bool enabled;

  static const double _size = 236;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The 3D dial face: a soft radial gradient with a drop shadow
            // (raised light plastic in light mode, dark slate in dark mode).
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 0.85,
                  colors: AppColors.isDark
                      ? const [
                          Color(0xFF34333B),
                          Color(0xFF28272E),
                          Color(0xFF1F1E24),
                        ]
                      : const [
                          Color(0xFFFFFFFF),
                          Color(0xFFF1EFEB),
                          Color(0xFFE8E5E0),
                        ],
                  stops: const [0, 0.6, 1],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F281E50),
                    blurRadius: 32,
                    spreadRadius: -8,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
            ),
            // Inner ring highlight.
            Container(
              width: 204,
              height: 204,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.isDark
                      ? const Color(0x22FFFFFF)
                      : const Color(0x66FFFFFF),
                  width: 1,
                ),
              ),
            ),
            Positioned(
              top: 14,
              child: _DialArrow(
                icon: Icons.keyboard_arrow_up,
                enabled: enabled,
                onTap: () => onKey(RemoteKey.up),
              ),
            ),
            Positioned(
              bottom: 14,
              child: _DialArrow(
                icon: Icons.keyboard_arrow_down,
                enabled: enabled,
                onTap: () => onKey(RemoteKey.down),
              ),
            ),
            Positioned(
              left: 14,
              child: _DialArrow(
                icon: Icons.keyboard_arrow_left,
                enabled: enabled,
                onTap: () => onKey(RemoteKey.left),
              ),
            ),
            Positioned(
              right: 14,
              child: _DialArrow(
                icon: Icons.keyboard_arrow_right,
                enabled: enabled,
                onTap: () => onKey(RemoteKey.right),
              ),
            ),
            _OkButton(enabled: enabled, onTap: () => onKey(RemoteKey.ok)),
          ],
        ),
      ),
    );
  }
}

class _DialArrow extends StatefulWidget {
  const _DialArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_DialArrow> createState() => _DialArrowState();
}

class _DialArrowState extends State<_DialArrow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: 62,
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _down ? AppColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(
        widget.icon,
        size: 34,
        color: _down ? AppColors.accentText : AppColors.dpadArrow,
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
      width: 92,
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: _down
            ? null
            : RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 0.9,
                colors: AppColors.isDark
                    ? const [Color(0xFF3C3B44), Color(0xFF2C2B33)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF4F2EE)],
              ),
        color: _down ? AppColors.accent : null,
        boxShadow: [
          BoxShadow(
            color: _down
                ? const Color(0x47B47A00)
                : const Color(0x22281E50),
            blurRadius: 18,
            spreadRadius: -2,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Text(
        'OK',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
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
// VOL / CH rocker pills
// ---------------------------------------------------------------------------

class _Rockers extends StatelessWidget {
  const _Rockers({required this.onKey, required this.channelEnabled});
  final void Function(RemoteKey) onKey;
  final bool channelEnabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RockerPill(
          label: 'VOL',
          topIcon: Icons.add,
          bottomIcon: Icons.remove,
          onTop: () => onKey(RemoteKey.volumeUp),
          onBottom: () => onKey(RemoteKey.volumeDown),
        ),
        const SizedBox(width: 26),
        _RockerPill(
          label: 'CH',
          topIcon: Icons.keyboard_arrow_up,
          bottomIcon: Icons.keyboard_arrow_down,
          enabled: channelEnabled,
          onTop: () => onKey(RemoteKey.channelUp),
          onBottom: () => onKey(RemoteKey.channelDown),
        ),
      ],
    );
  }
}

class _RockerPill extends StatelessWidget {
  const _RockerPill({
    required this.label,
    required this.topIcon,
    required this.bottomIcon,
    required this.onTop,
    required this.onBottom,
    this.enabled = true,
  });

  final String label;
  final IconData topIcon;
  final IconData bottomIcon;
  final VoidCallback onTop;
  final VoidCallback onBottom;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        width: 80,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1246377A),
              blurRadius: 16,
              spreadRadius: -6,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RockerHalf(
              icon: topIcon,
              enabled: enabled,
              onTap: onTop,
              radius: const BorderRadius.vertical(
                top: Radius.circular(34),
                bottom: Radius.circular(14),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: AppColors.textFaint,
                ),
              ),
            ),
            _RockerHalf(
              icon: bottomIcon,
              enabled: enabled,
              onTap: onBottom,
              radius: const BorderRadius.vertical(
                top: Radius.circular(14),
                bottom: Radius.circular(34),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RockerHalf extends StatefulWidget {
  const _RockerHalf({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.radius,
  });

  final IconData icon;
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
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _down ? AppColors.accentSoft : Colors.transparent,
        borderRadius: widget.radius,
      ),
      child: Icon(
        widget.icon,
        size: 26,
        color: _down ? AppColors.accentText : AppColors.dpadArrow,
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
// Back / Home / Menu / More
// ---------------------------------------------------------------------------

class _BottomRow extends StatelessWidget {
  const _BottomRow({
    required this.onKey,
    required this.navEnabled,
    required this.onMore,
  });
  final void Function(RemoteKey) onKey;
  final bool navEnabled;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CircleButton(
          icon: Icons.arrow_back_ios_new,
          label: 'Back',
          enabled: navEnabled,
          onTap: () => onKey(RemoteKey.back),
        ),
        _CircleButton(
          icon: Icons.home_outlined,
          label: 'Home',
          enabled: navEnabled,
          onTap: () => onKey(RemoteKey.home),
        ),
        _CircleButton(
          icon: Icons.tune,
          label: 'Menu',
          enabled: navEnabled,
          onTap: () => onKey(RemoteKey.menu),
        ),
        _CircleButton(
          icon: Icons.more_horiz,
          label: 'More',
          enabled: true,
          onTap: onMore,
        ),
      ],
    );
  }
}

class _CircleButton extends StatefulWidget {
  const _CircleButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _down ? AppColors.accentSoft : AppColors.card,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(
        widget.icon,
        size: 23,
        color: _down ? AppColors.accentText : AppColors.textPrimary,
      ),
    );

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(opacity: widget.enabled ? 1 : 0.4, child: circle),
        const SizedBox(height: 5),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppColors.textFaint,
          ),
        ),
      ],
    );

    if (!widget.enabled) return column;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: column,
    );
  }
}
