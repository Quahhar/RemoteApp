import 'package:flutter/material.dart';

/// A round, labelled remote key. Visual only — the caller wires the action
/// (haptics + send happen in [pressKey]).
class RemoteButton extends StatelessWidget {
  const RemoteButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.size = 64,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;
  final double size;

  /// When true the button uses the accent fill (e.g. power, OK).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final bg = filled
        ? scheme.primary
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final fg = filled ? scheme.onPrimary : scheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: fg, size: size * 0.42),
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(
            label!,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
