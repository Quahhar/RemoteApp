import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/remote_key.dart';
import '../../state/active_device_provider.dart';
import '../remote_actions.dart';
import '../widgets/dpad.dart';
import '../widgets/remote_button.dart';

/// Functional remote. This is a placeholder layout that sends real keys; it
/// will be restyled to match the supplied design mockup. It only ever talks to
/// the active controller via [pressKey] — no brand logic here.
class RemoteScreen extends ConsumerWidget {
  const RemoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDevice = ref.watch(activeDeviceProvider) != null;

    RemoteButton keyBtn(
      RemoteKey key,
      IconData icon, {
      String? label,
      bool filled = false,
      double size = 64,
    }) {
      return RemoteButton(
        icon: icon,
        label: label,
        filled: filled,
        size: size,
        onPressed: () => pressKey(context, ref, key),
      );
    }

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                if (!hasDevice) const _NoDeviceHint(),
                Align(
                  alignment: Alignment.centerRight,
                  child: keyBtn(
                    RemoteKey.power,
                    Icons.power_settings_new,
                    label: 'Power',
                    filled: true,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 20),
                Dpad(onKey: (key) => pressKey(context, ref, key)),
                const SizedBox(height: 28),
                _Row(children: [
                  keyBtn(RemoteKey.back, Icons.arrow_back, label: 'Back'),
                  keyBtn(RemoteKey.home, Icons.home_outlined, label: 'Home'),
                  keyBtn(RemoteKey.menu, Icons.menu, label: 'Menu'),
                ]),
                const SizedBox(height: 18),
                _Row(children: [
                  keyBtn(RemoteKey.volumeDown, Icons.volume_down, label: 'Vol −'),
                  keyBtn(RemoteKey.mute, Icons.volume_off, label: 'Mute'),
                  keyBtn(RemoteKey.volumeUp, Icons.volume_up, label: 'Vol +'),
                ]),
                const SizedBox(height: 18),
                _Row(children: [
                  keyBtn(RemoteKey.channelDown, Icons.remove, label: 'Ch −'),
                  keyBtn(RemoteKey.play, Icons.play_arrow, label: 'Play'),
                  keyBtn(RemoteKey.pause, Icons.pause, label: 'Pause'),
                  keyBtn(RemoteKey.channelUp, Icons.add, label: 'Ch +'),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: children,
    );
  }
}

class _NoDeviceHint extends StatelessWidget {
  const _NoDeviceHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No TV selected. Open the Devices tab to scan and connect.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
