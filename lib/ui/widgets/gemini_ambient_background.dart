import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'ambient_top_glow.dart';

/// Full-screen background: the light [AmbientTopGlow] wash over the flat paper
/// colour, with [child] composited on top. The band spans the top ~65% of the
/// screen so the colour dissolves out around 60% down, matching the Gemini
/// reference video (`Asset/screenr1.mp4`).
///
/// `home_shell` renders this behind a transparent scaffold when the animated-
/// background preference is on; when off it uses the plain paper colour instead.
class GeminiAmbientBackground extends StatelessWidget {
  const GeminiAmbientBackground({
    super.key,
    required this.child,
    this.animate = true,
  });

  final Widget child;

  /// When `false` the glow is painted as a still gradient (no drift animation).
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AmbientTopGlow(
              height: MediaQuery.of(context).size.height * 0.65,
              animate: animate,
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
