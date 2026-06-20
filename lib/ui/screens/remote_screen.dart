import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_status.dart';
import '../../models/remote_key.dart';
import '../../state/active_device_provider.dart';
import '../../state/connection_provider.dart';
import '../../theme/app_colors.dart';
import '../remote_actions.dart';
import 'settings_screen.dart';

/// The home/Remote screen — a native reimplementation of the Remote Control
/// mockup. Talks only to the active controller via [pressKey]; no brand logic.
class RemoteScreen extends ConsumerWidget {
  const RemoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(activeDeviceProvider);
    final status = ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _Header(
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkResponse(
              onTap: onSettings,
              radius: 24,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.settings_outlined,
                    size: 26, color: AppColors.textPrimary),
              ),
            ),
          ),
          const Text(
            'Remote Control',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
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
        color: AppColors.cardFill,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A463778), blurRadius: 24, offset: Offset(0, 8)),
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
          InkResponse(
            onTap: onPower,
            radius: 36,
            child: Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: AppColors.powerBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Color(0x2EDC5A46),
                      blurRadius: 14,
                      offset: Offset(0, 4)),
                ],
              ),
              child: Icon(
                Icons.power_settings_new,
                size: 28,
                color: connected ? AppColors.powerRed : AppColors.statusGrey,
              ),
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
    Widget chevron(RemoteKey key, IconData icon, Alignment align, EdgeInsets pad) {
      return Align(
        alignment: align,
        child: Padding(
          padding: pad,
          child: InkResponse(
            onTap: () => onKey(key),
            radius: 28,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 30, color: AppColors.icon),
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(0, -0.16),
            radius: 0.72,
            colors: [Color(0x9EFFFFFF), Color(0x4DFFFFFF)],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            chevron(RemoteKey.up, Icons.keyboard_arrow_up_rounded,
                Alignment.topCenter, const EdgeInsets.only(top: 10)),
            chevron(RemoteKey.down, Icons.keyboard_arrow_down_rounded,
                Alignment.bottomCenter, const EdgeInsets.only(bottom: 10)),
            chevron(RemoteKey.left, Icons.keyboard_arrow_left_rounded,
                Alignment.centerLeft, const EdgeInsets.only(left: 6)),
            chevron(RemoteKey.right, Icons.keyboard_arrow_right_rounded,
                Alignment.centerRight, const EdgeInsets.only(right: 6)),
            _OkButton(onTap: () => onKey(RemoteKey.ok)),
          ],
        ),
      ),
    );
  }
}

class _OkButton extends StatelessWidget {
  const _OkButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.okFill,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      shadowColor: const Color(0x33463778),
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 84,
          height: 84,
          child: Center(
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
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
