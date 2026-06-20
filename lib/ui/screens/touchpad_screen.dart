import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/remote_controller.dart';
import '../../models/remote_key.dart';
import '../../state/active_device_provider.dart';
import '../remote_actions.dart';
import '../widgets/remote_button.dart';
import '../widgets/screen_header.dart';

/// Gesture surface. When the active controller advertises a pointer it drives
/// `movePointer`/`click`; otherwise it translates swipes into D-pad keys and a
/// tap into select. Below the surface are media controls (play/pause/back).
/// Everything is decided from [Capabilities], never the brand. NOTE: functional
/// layout pending the touchpad design mockup.
class TouchpadScreen extends ConsumerWidget {
  const TouchpadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(activeControllerProvider);

    final Widget body;
    if (controller == null) {
      body = const _Centered(
        icon: Icons.touch_app_outlined,
        text: 'Select a device to use the touchpad.',
      );
    } else {
      final pointer = controller.capabilities.supportsPointer;
      body = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            Expanded(
              child: pointer
                  ? _PointerSurface(
                      onMove: (dx, dy) => _pointerMove(controller, dx, dy),
                      onClick: () => _pointerClick(context, controller),
                    )
                  : _SwipeSurface(
                      onKey: (key) => pressKey(context, ref, key),
                    ),
            ),
            const SizedBox(height: 16),
            _MediaControls(onKey: (key) => pressKey(context, ref, key)),
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const ScreenHeader('Touchpad'),
          Expanded(child: body),
        ],
      ),
    );
  }

  Future<void> _pointerMove(
      RemoteController controller, double dx, double dy) async {
    try {
      await controller.movePointer(dx, dy);
    } on RemoteException {
      // Ignore transient move errors; a failed click surfaces the message.
    }
  }

  Future<void> _pointerClick(
      BuildContext context, RemoteController controller) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.click();
    } on RemoteException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Pointer mode: drag moves the cursor, tap clicks.
class _PointerSurface extends StatelessWidget {
  const _PointerSurface({required this.onMove, required this.onClick});

  final Future<void> Function(double dx, double dy) onMove;
  final Future<void> Function() onClick;

  @override
  Widget build(BuildContext context) {
    return _SurfaceFrame(
      icon: Icons.touch_app,
      label: 'Drag to move · tap to click',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onMove(d.delta.dx, d.delta.dy),
        onTap: onClick,
      ),
    );
  }
}

/// Fallback mode (no pointer): a swipe sends the matching D-pad key, a tap
/// sends select.
class _SwipeSurface extends StatefulWidget {
  const _SwipeSurface({required this.onKey});

  final void Function(RemoteKey key) onKey;

  @override
  State<_SwipeSurface> createState() => _SwipeSurfaceState();
}

class _SwipeSurfaceState extends State<_SwipeSurface> {
  static const double _threshold = 24;
  double _dx = 0;
  double _dy = 0;

  @override
  Widget build(BuildContext context) {
    return _SurfaceFrame(
      icon: Icons.swipe,
      label: 'Swipe to navigate · tap to select',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onKey(RemoteKey.ok),
        onPanStart: (_) {
          _dx = 0;
          _dy = 0;
        },
        onPanUpdate: (d) {
          _dx += d.delta.dx;
          _dy += d.delta.dy;
        },
        onPanEnd: (_) {
          if (_dx.abs() < _threshold && _dy.abs() < _threshold) return;
          if (_dx.abs() >= _dy.abs()) {
            widget.onKey(_dx > 0 ? RemoteKey.right : RemoteKey.left);
          } else {
            widget.onKey(_dy > 0 ? RemoteKey.down : RemoteKey.up);
          }
        },
      ),
    );
  }
}

/// Shared bordered surface with a centered hint behind the gesture child.
class _SurfaceFrame extends StatelessWidget {
  const _SurfaceFrame({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _MediaControls extends StatelessWidget {
  const _MediaControls({required this.onKey});

  final void Function(RemoteKey key) onKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        RemoteButton(
          icon: Icons.arrow_back,
          label: 'Back',
          onPressed: () => onKey(RemoteKey.back),
        ),
        RemoteButton(
          icon: Icons.play_arrow,
          label: 'Play',
          onPressed: () => onKey(RemoteKey.play),
        ),
        RemoteButton(
          icon: Icons.pause,
          label: 'Pause',
          onPressed: () => onKey(RemoteKey.pause),
        ),
      ],
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
