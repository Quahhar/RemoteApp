import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_status.dart';
import '../../purchases/purchase_controller.dart';
import '../../state/active_device_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/preferences_provider.dart';
import '../../state/saved_devices_provider.dart';
import '../../theme/app_colors.dart';
import '../widgets/upgrade_button.dart';
import 'devices_screen.dart' show protocolIcon;

/// Settings: the active connection, disconnect, forget-all, haptics, and app
/// info. Reached from the gear in the Devices header. Styled to match the flat
/// mockup palette.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeDeviceProvider);
    final status = ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;
    final savedCount = ref.watch(savedDevicesProvider).length;
    final isPro = ref.watch(isProProvider);
    // Rebuild the whole page when the palette flips (AppColors getters aren't
    // reactive on their own).
    ref.watch(effectiveDarkModeProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          children: [
            _SectionLabel('Connection'),
            _Card(
              child: active == null
                  ? ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.tv_off, color: AppColors.textMuted),
                      title: const Text('No device connected'),
                      subtitle: const Text(
                          'Add and select a TV from the Devices tab.'),
                    )
                  : Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(protocolIcon(active.protocol),
                              color: AppColors.accent),
                          title: Text(active.name),
                          subtitle: Text(
                            '${active.protocol.label} · ${active.host}:${active.effectivePort}\n'
                            'Status: ${status.name}',
                          ),
                          isThreeLine: true,
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                ref.read(activeDeviceProvider.notifier).clear(),
                            icon: const Icon(Icons.link_off),
                            label: const Text('Disconnect'),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            _SectionLabel('Omnix Pro'),
            _Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(
                  isPro ? Icons.workspace_premium : Icons.lock_open_outlined,
                  color: AppColors.gold,
                ),
                title: Text(isPro ? 'Pro is active' : 'Upgrade to Pro'),
                subtitle: Text(
                  isPro
                      ? 'Ads off · trackpad · keyboard · more'
                      : 'Remove ads, unlock the trackpad and keyboard',
                ),
                trailing:
                    Icon(Icons.chevron_right, color: AppColors.textMuted),
                onTap: () => UpgradeButton.open(context),
              ),
            ),
            const SizedBox(height: 18),
            _SectionLabel('Preferences'),
            _Card(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    secondary:
                        Icon(Icons.vibration, color: AppColors.textMuted),
                    title: const Text('Haptic feedback'),
                    subtitle: const Text('Vibrate on button presses'),
                    activeThumbColor: AppColors.accent,
                    value: ref.watch(hapticsEnabledProvider),
                    onChanged: (v) =>
                        ref.read(hapticsEnabledProvider.notifier).set(v),
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppColors.divider,
                  ),
                  SwitchListTile(
                    secondary:
                        Icon(Icons.gradient, color: AppColors.textMuted),
                    title: const Text('Animated background'),
                    subtitle: const Text('Ambient gradient aura behind the app'),
                    activeThumbColor: AppColors.accent,
                    value: ref.watch(animatedBackgroundProvider),
                    onChanged: (v) =>
                        ref.read(animatedBackgroundProvider.notifier).set(v),
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppColors.divider,
                  ),
                  ListTile(
                    leading: Icon(Icons.dark_mode_outlined,
                        color: AppColors.textMuted),
                    title: const Text('Dark mode'),
                    subtitle: Text(
                      ref.watch(autoDarkModeProvider)
                          ? 'Automatic · dark 7 PM – 7 AM'
                          : 'Dark surfaces, same amber accent',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          activeThumbColor: AppColors.accent,
                          value: ref.watch(effectiveDarkModeProvider),
                          onChanged: (v) async {
                            // A manual flip takes over from the schedule.
                            await ref
                                .read(autoDarkModeProvider.notifier)
                                .set(false);
                            await ref.read(darkModeProvider.notifier).set(v);
                          },
                        ),
                        PopupMenuButton<void>(
                          icon: Icon(Icons.more_vert,
                              color: AppColors.textMuted),
                          tooltip: 'Dark mode options',
                          itemBuilder: (context) => [
                            CheckedPopupMenuItem<void>(
                              checked: ref.read(autoDarkModeProvider),
                              onTap: () => ref
                                  .read(autoDarkModeProvider.notifier)
                                  .toggle(),
                              child:
                                  const Text('Automatic (dark 7 PM – 7 AM)'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SectionLabel('Devices'),
            _Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.delete_sweep_outlined,
                    color: AppColors.textMuted),
                title: const Text('Forget all devices'),
                subtitle: Text('$savedCount saved'),
                enabled: savedCount > 0,
                onTap: savedCount == 0
                    ? null
                    : () => _confirmForgetAll(context, ref),
              ),
            ),
            const SizedBox(height: 18),
            _SectionLabel('About'),
            _Card(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(Icons.info_outline, color: AppColors.textMuted),
                    title: const Text('Omnix'),
                    subtitle: const Text('Universal Wi-Fi TV remote · v1.0.0'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.devices_other,
                        color: AppColors.textMuted),
                    title: const Text('Supported'),
                    subtitle: const Text(
                        'Roku · LG webOS · Samsung · Android TV · Hisense/VIDAA · Cast/DLNA'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmForgetAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Forget all devices?'),
        content: const Text(
          'This removes every saved device and disconnects the current one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(activeDeviceProvider.notifier).clear();
    final saved = [...ref.read(savedDevicesProvider)];
    for (final device in saved) {
      await ref.read(savedDevicesProvider.notifier).remove(device.id);
    }
  }
}

// _Card and _SectionLabel read AppColors in build, so instantiations above are
// deliberately non-const: a const instance would be reused across rebuilds and
// keep the old palette after a dark-mode toggle.

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            spreadRadius: -6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          letterSpacing: 0.3,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
