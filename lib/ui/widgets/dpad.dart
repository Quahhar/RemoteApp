import 'package:flutter/material.dart';

import '../../models/remote_key.dart';

/// Directional pad: up/down/left/right around a centre OK. Reused by the Remote
/// screen and as the Touchpad fallback when a device has no pointer support.
class Dpad extends StatelessWidget {
  const Dpad({super.key, required this.onKey, this.size = 248});

  final void Function(RemoteKey key) onKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget arrow(RemoteKey key, IconData icon) => InkResponse(
          onTap: () => onKey(key),
          radius: size * 0.2,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(icon, size: 32, color: scheme.onSurface),
          ),
        );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.40),
        shape: BoxShape.circle,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          arrow(RemoteKey.up, Icons.keyboard_arrow_up_rounded),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              arrow(RemoteKey.left, Icons.keyboard_arrow_left_rounded),
              _OkButton(diameter: size * 0.3, onTap: () => onKey(RemoteKey.ok)),
              arrow(RemoteKey.right, Icons.keyboard_arrow_right_rounded),
            ],
          ),
          arrow(RemoteKey.down, Icons.keyboard_arrow_down_rounded),
        ],
      ),
    );
  }
}

class _OkButton extends StatelessWidget {
  const _OkButton({required this.diameter, required this.onTap});

  final double diameter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Center(
            child: Text(
              'OK',
              style: TextStyle(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
                fontSize: diameter * 0.26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
