import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_status.dart';
import '../../state/active_device_provider.dart';
import '../../state/connection_provider.dart';

/// Compact "● Connected · Living Room" status line driven by the active device
/// and its live connection status. Brand-agnostic.
class ConnectionIndicator extends ConsumerWidget {
  const ConnectionIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(activeDeviceProvider);
    final status = ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;
    final scheme = Theme.of(context).colorScheme;

    final (Color color, String label) = switch (status) {
      ConnectionStatus.connected => (Colors.greenAccent, 'Connected'),
      ConnectionStatus.connecting => (Colors.amberAccent, 'Connecting…'),
      ConnectionStatus.error => (scheme.error, 'Disconnected'),
      ConnectionStatus.disconnected => (scheme.onSurfaceVariant, 'Not connected'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            device == null ? label : '$label · ${device.name}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
