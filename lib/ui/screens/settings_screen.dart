import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_status.dart';
import '../../state/active_device_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/preferences_provider.dart';
import '../../state/saved_devices_provider.dart';
import 'devices_screen.dart' show protocolIcon;

/// Settings: the active connection, disconnect, forget-all, and app info.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeDeviceProvider);
    final status = ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;
    final savedCount = ref.watch(savedDevicesProvider).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            const _Header('Connection'),
            if (active == null)
              const ListTile(
                leading: Icon(Icons.tv_off),
                title: Text('No device connected'),
                subtitle: Text('Add and select a TV from the Devices tab.'),
              )
            else ...[
              ListTile(
                leading: Icon(protocolIcon(active.protocol)),
                title: Text(active.name),
                subtitle: Text(
                  '${active.protocol.label} · ${active.host}:${active.effectivePort}\n'
                  'Status: ${status.name}',
                ),
                isThreeLine: true,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(activeDeviceProvider.notifier).clear(),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ),
            ],
            const Divider(height: 32),
            const _Header('Preferences'),
            SwitchListTile(
              secondary: const Icon(Icons.vibration),
              title: const Text('Haptic feedback'),
              subtitle: const Text('Vibrate on button presses'),
              value: ref.watch(hapticsEnabledProvider),
              onChanged: (v) =>
                  ref.read(hapticsEnabledProvider.notifier).set(v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.gradient),
              title: const Text('Animated background'),
              subtitle: const Text('Slow lava-lamp motion (off = static)'),
              value: ref.watch(animatedBackgroundProvider),
              onChanged: (v) =>
                  ref.read(animatedBackgroundProvider.notifier).set(v),
            ),
            const Divider(height: 32),
            const _Header('Devices'),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Forget all devices'),
              subtitle: Text('$savedCount saved'),
              enabled: savedCount > 0,
              onTap: savedCount == 0
                  ? null
                  : () => _confirmForgetAll(context, ref),
            ),
            const Divider(height: 32),
            const _Header('About'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Remote'),
              subtitle: Text('Universal Wi-Fi TV remote · v1.0.0'),
            ),
            const ListTile(
              leading: Icon(Icons.devices_other),
              title: Text('Supported'),
              subtitle: Text('Roku · LG webOS · Samsung Tizen · Android TV'),
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

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
