import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/preferences_provider.dart';
import '../../theme/app_colors.dart';

/// App-wide background: the static mockup gradient with, by default, a few
/// large soft blobs drifting slowly like a lava lamp. Users can switch the
/// motion off in Settings, leaving just the gradient.
///
/// The motion is driven by a free-running [Ticker] (a monotonically increasing
/// clock), not a looping controller, and each blob moves on its own pair of
/// non-harmonic frequencies. So there is no loop boundary to snap at — the
/// pattern drifts indefinitely and never visibly restarts. Only the painter
/// repaints each frame (via the [ValueListenableBuilder] + [RepaintBoundary]),
/// never the app content layered on top.
class AppBackground extends ConsumerStatefulWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends ConsumerState<AppBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  /// Elapsed seconds since the ticker started — the painter's only input.
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);

  void _onTick(Duration elapsed) {
    _seconds.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animated = ref.watch(animatedBackgroundProvider);
    // Run the ticker only while motion is enabled.
    if (animated && !_ticker.isActive) {
      _ticker.start();
    } else if (!animated && _ticker.isActive) {
      _ticker.stop();
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
            child: RepaintBoundary(
              child: ValueListenableBuilder<double>(
                valueListenable: _seconds,
                builder: (_, t, _) => CustomPaint(painter: _LavaPainter(t)),
              ),
            ),
          ),
        widget.child,
      ],
    );
  }
}

class _Blob {
  const _Blob(
    this.color,
    this.baseX,
    this.baseY,
    this.ampX,
    this.ampY,
    this.freqX,
    this.freqY,
    this.phaseX,
    this.phaseY,
    this.radius,
  );

  final Color color;
  final double baseX; // centre, fraction of width
  final double baseY; // centre, fraction of height
  final double ampX; // drift amplitude, fraction of width
  final double ampY; // drift amplitude, fraction of height
  final double freqX; // radians per second
  final double freqY; // radians per second
  final double phaseX;
  final double phaseY;
  final double radius; // fraction of shortest side
}

class _LavaPainter extends CustomPainter {
  _LavaPainter(this.t);

  final double t; // seconds, monotonically increasing

  // Frequencies are deliberately non-harmonic (no small whole-number ratios),
  // so the combined motion has no short common period — it never visibly loops.
  static const List<_Blob> _blobs = [
    _Blob(Color(0xFFE26FC4), 0.25, 0.30, 0.16, 0.14, 0.130, 0.171, 0.0, 1.7,
        0.66),
    _Blob(Color(0xFF9A6BF2), 0.78, 0.40, 0.15, 0.16, 0.109, 0.193, 2.3, 0.5,
        0.74),
    _Blob(Color(0xFF5E9BF0), 0.50, 0.80, 0.17, 0.13, 0.167, 0.121, 4.1, 3.3,
        0.70),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final blob in _blobs) {
      final cx =
          (blob.baseX + blob.ampX * math.sin(t * blob.freqX + blob.phaseX)) *
              size.width;
      final cy =
          (blob.baseY + blob.ampY * math.cos(t * blob.freqY + blob.phaseY)) *
              size.height;
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
