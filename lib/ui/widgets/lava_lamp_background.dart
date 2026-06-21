import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/preferences_provider.dart';
import '../../theme/app_colors.dart';

/// App-wide background: the static mockup gradient with, by default, a few
/// large soft blobs drifting slowly like a lava lamp. Users can switch the
/// motion off in Settings, leaving just the gradient.
class AppBackground extends ConsumerStatefulWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends ConsumerState<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animated = ref.watch(animatedBackgroundProvider);
    // Run the ticker only while motion is enabled.
    if (animated && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animated && _controller.isAnimating) {
      _controller.stop();
    }

    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
          ),
        ),
        if (animated)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => CustomPaint(
                painter: _LavaPainter(_controller.value),
              ),
            ),
          ),
        widget.child,
      ],
    );
  }
}

class _Blob {
  const _Blob(this.color, this.baseX, this.baseY, this.phase, this.radius);
  final Color color;
  final double baseX;
  final double baseY;
  final double phase;
  final double radius; // fraction of shortest side
}

class _LavaPainter extends CustomPainter {
  _LavaPainter(this.t);

  final double t; // 0..1

  static const List<_Blob> _blobs = [
    _Blob(Color(0xFFE26FC4), 0.25, 0.28, 0.00, 0.66),
    _Blob(Color(0xFF9A6BF2), 0.78, 0.42, 0.34, 0.74),
    _Blob(Color(0xFF5E9BF0), 0.50, 0.82, 0.67, 0.70),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final blob in _blobs) {
      final angle = 2 * math.pi * (t + blob.phase);
      final cx = (blob.baseX + 0.18 * math.sin(angle)) * size.width;
      final cy = (blob.baseY + 0.18 * math.cos(angle * 0.8)) * size.height;
      final radius = blob.radius * size.shortestSide;
      final paint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            blob.color.withValues(alpha: 0.55),
            blob.color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_LavaPainter oldDelegate) => oldDelegate.t != t;
}
