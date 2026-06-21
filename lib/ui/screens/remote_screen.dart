import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_status.dart';
import '../../models/remote_key.dart';
import '../../state/active_device_provider.dart';
import '../../state/connection_provider.dart';
import '../../theme/app_colors.dart';
import '../remote_actions.dart';

/// The home/Remote screen — a native reimplementation of the Remote Control
/// mockup. The shared header/gear is provided by the shell. Talks only to the
/// active controller via [pressKey]; no brand logic.
class RemoteScreen extends ConsumerWidget {
  const RemoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(activeDeviceProvider);
    final status = ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _DeviceCard(
              name: device?.name ?? 'No TV selected',
              status: status,
              hasDevice: device != null,
              onPower: () => pressKey(context, ref, RemoteKey.power),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80),
            child: _Dpad(onKey: (k) => pressKey(context, ref, k)),
          ),
          const SizedBox(height: 34),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _VolChRow(onKey: (k) => pressKey(context, ref, k)),
          ),
          const SizedBox(height: 34),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _NavRow(onKey: (k) => pressKey(context, ref, k)),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.name,
    required this.status,
    required this.hasDevice,
    required this.onPower,
  });

  final String name;
  final ConnectionStatus status;
  final bool hasDevice;
  final VoidCallback onPower;

  @override
  Widget build(BuildContext context) {
    final connected = status == ConnectionStatus.connected;
    final (Color dot, Color halo, String label) = switch (status) {
      ConnectionStatus.connected => (
          AppColors.statusGreen,
          AppColors.statusHaloGreen,
          'Connected'
        ),
      ConnectionStatus.connecting => (
          const Color(0xFFE0A93B),
          const Color(0x33E0A93B),
          'Connecting…'
        ),
      ConnectionStatus.error => (AppColors.statusGrey, Colors.transparent, 'Disconnected'),
      ConnectionStatus.disconnected => (
          AppColors.statusGrey,
          Colors.transparent,
          hasDevice ? 'Not connected' : 'Tap Devices to connect'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x8CFFFFFF), Color(0x52FFFFFF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: const [
          // Light highlight (top-left) + soft depth (bottom-right) = raised panel.
          BoxShadow(
              color: Color(0x80FFFFFF), blurRadius: 12, offset: Offset(-5, -5)),
          BoxShadow(
              color: Color(0x1F463778), blurRadius: 18, offset: Offset(6, 8)),
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
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: halo, blurRadius: 0, spreadRadius: 3),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _PressableCircle(
            diameter: 62,
            onTap: onPower,
            topColor: const Color(0xFFFFF4F0),
            baseColor: AppColors.powerBg,
            child: Icon(
              Icons.power_settings_new,
              size: 28,
              color: connected ? AppColors.powerRed : AppColors.statusGrey,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dpad extends StatelessWidget {
  const _Dpad({required this.onKey});
  final void Function(RemoteKey key) onKey;

  @override
  Widget build(BuildContext context) {
    Widget pad(RemoteKey key, IconData icon, Alignment align) {
      return Align(
        alignment: align,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: _PressableCircle(
            diameter: 56,
            onTap: () => onKey(key),
            child: Icon(icon, size: 28, color: AppColors.icon),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        // A softly raised "dish" the buttons sit on, for layered depth.
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(0, -0.1),
            radius: 0.82,
            colors: [Color(0x33FFFFFF), Color(0x66FFFFFF)],
          ),
          boxShadow: [
            BoxShadow(
                color: Color(0x66FFFFFF), blurRadius: 16, offset: Offset(-7, -7)),
            BoxShadow(
                color: Color(0x1F463778), blurRadius: 22, offset: Offset(9, 11)),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            pad(RemoteKey.up, Icons.keyboard_arrow_up_rounded,
                Alignment.topCenter),
            pad(RemoteKey.down, Icons.keyboard_arrow_down_rounded,
                Alignment.bottomCenter),
            pad(RemoteKey.left, Icons.keyboard_arrow_left_rounded,
                Alignment.centerLeft),
            pad(RemoteKey.right, Icons.keyboard_arrow_right_rounded,
                Alignment.centerRight),
            _PressableCircle(
              diameter: 84,
              onTap: () => onKey(RemoteKey.ok),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round, raised button with a soft neumorphic look that depresses when
/// pressed — gives the D-pad / power keys a tactile "button feel".
class _PressableCircle extends StatefulWidget {
  const _PressableCircle({
    required this.diameter,
    required this.onTap,
    required this.child,
    this.topColor = Colors.white,
    this.baseColor = const Color(0xF2FFFFFF),
  });

  final double diameter;
  final VoidCallback onTap;
  final Widget child;
  final Color topColor;
  final Color baseColor;

  @override
  State<_PressableCircle> createState() => _PressableCircleState();
}

class _PressableCircleState extends State<_PressableCircle> {
  bool _down = false;

  static const List<BoxShadow> _raised = [
    BoxShadow(color: Color(0xCCFFFFFF), blurRadius: 8, offset: Offset(-4, -4)),
    BoxShadow(color: Color(0x33463778), blurRadius: 14, offset: Offset(5, 6)),
  ];
  static const List<BoxShadow> _pressed = [
    BoxShadow(color: Color(0x22463778), blurRadius: 4, offset: Offset(1, 2)),
  ];

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) {
        _set(false);
        widget.onTap();
      },
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: widget.diameter,
          height: widget.diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [widget.topColor, widget.baseColor],
            ),
            boxShadow: _down ? _pressed : _raised,
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

class _VolChRow extends StatelessWidget {
  const _VolChRow({required this.onKey});
  final void Function(RemoteKey key) onKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StepperCard(
            label: 'VOL',
            topIcon: Icons.add,
            bottomIcon: Icons.remove,
            onTop: () => onKey(RemoteKey.volumeUp),
            onBottom: () => onKey(RemoteKey.volumeDown),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _StepperCard(
            label: 'CH',
            topIcon: Icons.keyboard_arrow_up_rounded,
            bottomIcon: Icons.keyboard_arrow_down_rounded,
            onTop: () => onKey(RemoteKey.channelUp),
            onBottom: () => onKey(RemoteKey.channelDown),
          ),
        ),
      ],
    );
  }
}

class _StepperCard extends StatelessWidget {
  const _StepperCard({
    required this.label,
    required this.topIcon,
    required this.bottomIcon,
    required this.onTop,
    required this.onBottom,
  });

  final String label;
  final IconData topIcon;
  final IconData bottomIcon;
  final VoidCallback onTop;
  final VoidCallback onBottom;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback onTap) => InkResponse(
          onTap: onTap,
          radius: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 18),
            child: Icon(icon, size: 26, color: AppColors.icon),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardFill,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x80FFFFFF)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14463778), blurRadius: 22, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          btn(topIcon, onTop),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: AppColors.label,
            ),
          ),
          const SizedBox(height: 10),
          btn(bottomIcon, onBottom),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.onKey});
  final void Function(RemoteKey key) onKey;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, RemoteKey key) => InkResponse(
          onTap: () => onKey(key),
          radius: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
            child: Icon(icon, size: 24, color: AppColors.icon),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.softFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          btn(Icons.arrow_back, RemoteKey.back),
          btn(Icons.home_outlined, RemoteKey.home),
          btn(Icons.menu, RemoteKey.menu),
        ],
      ),
    );
  }
}
