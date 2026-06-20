import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/remote_controller.dart';
import '../../state/active_device_provider.dart';
import '../remote_actions.dart';
import '../widgets/dpad.dart';

/// Gesture surface that drives pointer moves when the active controller
/// supports them, and transparently falls back to the D-pad otherwise. Decides
/// purely from [Capabilities.pointer] — never from the brand.
class TouchpadScreen extends ConsumerWidget {
  const TouchpadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(activeControllerProvider);

    if (controller == null) {
      return const _Centered(
        icon: Icons.touch_app_outlined,
        text: 'Select a device to use the touchpad.',
      );
    }

    if (!controller.capabilities.pointer) {
      // Fallback: D-pad keys, with a note explaining why.
      return SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'This device has no pointer — using the D-pad instead.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Dpad(onKey: (key) => pressKey(context, ref, key)),
          ],
        ),
      );
    }

    return _PointerSurface(
      onMove: (dx, dy) async {
        try {
          await controller.movePointer(dx, dy);
        } on RemoteException {
          // Ignore transient pointer errors; clicks surface failures instead.
        }
      },
      onClick: () async {
        HapticFeedback.selectionClick();
        final messenger = ScaffoldMessenger.of(context);
        try {
          await controller.click();
        } on RemoteException catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
        }
      },
    );
  }
}

class _PointerSurface extends StatelessWidget {
  const _PointerSurface({required this.onMove, required this.onClick});

  final Future<void> Function(double dx, double dy) onMove;
  final Future<void> Function() onClick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          onPanUpdate: (d) => onMove(d.delta.dx, d.delta.dy),
          onTap: onClick,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app,
                      size: 48, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    'Drag to move · tap to click',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
