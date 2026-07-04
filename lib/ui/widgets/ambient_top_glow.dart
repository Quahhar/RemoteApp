import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// A light, airy ambient wash anchored to the top of the screen — a faithful
/// copy of the Gemini "thinking" gradient (reference: `Asset/screenr1.mp4`).
///
/// The whole wash sweeps through the full colour wheel once every six seconds
/// — sky blue → aqua → mint green → butter yellow → blush pink → lavender →
/// back to blue — while gently swelling and relaxing, and dissolves into the
/// page around 60% of the way down the screen with no visible edge. Both the
/// six-second hue cadence and the pastel stops are sampled frame-by-frame from
/// the reference video.
///
/// A few soft blobs carry the colour, each painted "pre-blurred": an oversized
/// radial gradient whose alpha falls off on a Gaussian-shaped curve, so
/// overlapping blobs melt into one organic wash. (An earlier version blurred
/// hard-edged blobs with a per-frame sigma-85 [ImageFiltered], but re-rendering
/// a full-screen Gaussian blur every frame flickers on many phone GPUs — the
/// gradient falloff gives the same look with a plain draw.) The palette phase
/// is *global* — every blob reads the same rotating hue ring, offset only
/// slightly per blob — so the screen reads as one colour at a time with a
/// subtle two-tone shimmer, exactly like the reference.
///
/// It draws nothing below the fade, so paint it *behind* your content:
///
/// ```dart
/// Stack(children: [
///   Positioned(top: 0, left: 0, right: 0,
///     child: AmbientTopGlow(height: MediaQuery.of(context).size.height * 0.65)),
///   Positioned.fill(child: yourContent),
/// ])
/// ```
///
/// Performance: the animated layer is fenced under a [RepaintBoundary] and is
/// the only thing rebuilt each frame; all motion is pure trig over a single
/// controller, using whole-number cycle counts so the loop is perfectly
/// seamless.
class AmbientTopGlow extends StatefulWidget {
  const AmbientTopGlow({super.key, required this.height, this.animate = true});

  /// Height of the glow band. Colour is concentrated in roughly its top third
  /// and fades to transparent before the bottom edge.
  final double height;

  /// When `false` the sweep/colour animation is paused into a still gradient.
  final bool animate;

  @override
  State<AmbientTopGlow> createState() => _AmbientTopGlowState();
}

class _AmbientTopGlowState extends State<AmbientTopGlow>
    with SingleTickerProviderStateMixin {
  /// Hue ring sampled one-per-second from the six-second colour sweep in
  /// `Asset/screenr1.mp4`, in playback order. These are the saturated blob
  /// cores; after the blur and the white page underneath they land on the
  /// video's pastels (`#a2c0ee` blue, `#d1f2f3` aqua, `#e4f7e6` mint,
  /// `#fdf4d6` yellow, `#f7dde8` pink, `#e3d7f8` lavender).
  static const List<Color> _hueRing = [
    Color(0xFF5E8FE8), // sky blue
    Color(0xFF5FCEDC), // aqua
    Color(0xFF7ED98F), // mint green
    Color(0xFFEDD463), // butter yellow
    Color(0xFFF29FBE), // blush pink
    Color(0xFFA98BEA), // lavender
  ];

  /// One controller loop is 18 s = [_hueRotations] complete six-second colour
  /// sweeps (the cadence measured from the video). Whole-number rotation and
  /// breath counts are what keep the loop seamless.
  static const Duration _period = Duration(seconds: 18);
  static const int _hueRotations = 3;

  /// The wash swells and relaxes as it changes colour in the reference —
  /// deep saturated blue one pass, barely-there blue the next. Two breaths
  /// per loop puts successive passes of the same hue at opposite ends of the
  /// swell, reproducing that.
  static const int _breathCycles = 2;

  // How far past its nominal size each blob's gradient reaches — stands in for
  // the spread the old sigma-85 blur added around every blob.
  static const double _spread = 1.55;

  /// Blobs clustered along the top edge. `cycles*` are integers, which is
  /// what keeps the loop seamless; `ringOffset` nudges each blob a few
  /// degrees around the shared hue ring for the reference's faint two-tone
  /// shimmer (one side of the screen runs slightly ahead of the other).
  static const List<_GlowBlob> _blobs = [
    _GlowBlob(
      ringOffset: 0.0,
      baseX: 0.10, baseY: 0.04, size: 1.15,
      driftX: 0.06, driftY: 0.05,
      cyclesX: 1, cyclesY: 2, cyclesScale: 1,
      scaleAmp: 0.10, phase: 0,
    ),
    _GlowBlob(
      ringOffset: 0.05,
      baseX: 0.90, baseY: 0.02, size: 1.2,
      driftX: 0.06, driftY: 0.05,
      cyclesX: 1, cyclesY: 1, cyclesScale: 2,
      scaleAmp: 0.12, phase: math.pi / 2,
    ),
    _GlowBlob(
      ringOffset: 0.02,
      baseX: 0.50, baseY: 0.06, size: 1.0,
      driftX: 0.08, driftY: 0.06,
      cyclesX: 2, cyclesY: 1, cyclesScale: 1,
      scaleAmp: 0.10, phase: math.pi,
    ),
    // Sits lower than the rest so a faint tint carries down to roughly half
    // the screen before the mask dissolves it, as in the reference.
    _GlowBlob(
      ringOffset: 0.07,
      baseX: 0.35, baseY: 0.30, size: 0.95,
      driftX: 0.07, driftY: 0.06,
      cyclesX: 1, cyclesY: 2, cyclesScale: 2,
      scaleAmp: 0.11, phase: 3 * math.pi / 2,
    ),
  ];

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _period);

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AmbientTopGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            // Alpha ramp: solid across the top ~quarter of the band, gone
            // before the bottom edge, so the wash dissolves into the page
            // with no hard line (the video's colour is fully gone ~60% down
            // the screen).
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0.0, 0.25, 0.96],
            ).createShader(rect),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = _controller.value; // 0..1, wraps seamlessly
                    final sweep = 2 * math.pi * t;
                    // Whole wash swells and relaxes together, like the video.
                    final breath =
                        0.78 + 0.22 * math.sin(sweep * _breathCycles);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final blob in _blobs)
                          _blobAt(blob, t, breath, w, h),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Colour at position [u] (in ring revolutions, wraps) around [_hueRing].
  static Color _ringColor(double u) {
    final x = (u % 1.0) * _hueRing.length;
    final i = x.floor();
    final f = x - i;
    return Color.lerp(_hueRing[i], _hueRing[(i + 1) % _hueRing.length], f)!;
  }

  /// Places one blob for the current loop phase [t] (0..1). Drift and
  /// breathing are `sin`/`cos` of the `2π` sweep times the blob's integer
  /// cycle counts, so every path closes exactly on loop; colour comes from
  /// the shared hue ring rotating [_hueRotations] times per loop.
  Widget _blobAt(_GlowBlob blob, double t, double breath, double w, double h) {
    final sweep = 2 * math.pi * t;
    final dx = blob.driftX * w * math.sin(sweep * blob.cyclesX + blob.phase);
    final dy = blob.driftY * h * math.cos(sweep * blob.cyclesY + blob.phase);
    final scale =
        1 + blob.scaleAmp * math.sin(sweep * blob.cyclesScale + blob.phase);
    final diameter = blob.size * w * scale * _spread;
    final centerX = blob.baseX * w + dx;
    final centerY = blob.baseY * h + dy;
    final color = _ringColor(t * _hueRotations + blob.ringOffset);
    // Over the light paper the wash blends towards white like the reference;
    // over the dark background the same alpha would read neon, so it's dialled
    // down into a softer aurora glow. (Read per frame, so a dark-mode toggle
    // takes effect immediately.)
    final base = AppColors.isDark ? 0.5 : 0.85;

    return Positioned(
      left: centerX - diameter / 2,
      top: centerY - diameter / 2,
      child: _BlobCircle(
        color: color,
        diameter: diameter,
        coreAlpha: base * breath,
      ),
    );
  }
}

/// Immutable description of one glow blob. Centre/drift are fractions of the
/// band; [size] is a fraction of band width. The `cycles*` fields must be
/// integers to keep the loop seamless.
@immutable
class _GlowBlob {
  const _GlowBlob({
    required this.ringOffset,
    required this.baseX,
    required this.baseY,
    required this.size,
    required this.driftX,
    required this.driftY,
    required this.cyclesX,
    required this.cyclesY,
    required this.cyclesScale,
    required this.scaleAmp,
    required this.phase,
  });

  final double ringOffset; // hue-ring lead/lag, fraction of a revolution
  final double baseX; // resting centre X, fraction of band width
  final double baseY; // resting centre Y, fraction of band height
  final double size; // base diameter, fraction of band width
  final double driftX; // horizontal drift radius, fraction of width
  final double driftY; // vertical drift radius, fraction of height
  final int cyclesX; // whole horizontal loops per period (seamless)
  final int cyclesY; // whole vertical loops per period (seamless)
  final int cyclesScale; // whole breathing pulses per period (seamless)
  final double scaleAmp; // breathing amplitude (fraction of base size)
  final double phase; // radians offset so blobs don't move in lockstep
}

/// A single soft radial-gradient circle. Its alpha falls off on a roughly
/// Gaussian curve, so it reads as an already-blurred spot of colour and
/// overlapping blobs fuse into one wash — no image filter needed. Trivial to
/// paint, so a handful per frame stays cheap.
class _BlobCircle extends StatelessWidget {
  const _BlobCircle({
    required this.color,
    required this.diameter,
    required this.coreAlpha,
  });

  final Color color;
  final double diameter;
  final double coreAlpha; // saturation of the blob core (the wash's swell)

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            // Gaussian-shaped falloff: saturated core dissolving smoothly to
            // nothing, standing in for the heavy blur the old version applied.
            colors: [
              color.withValues(alpha: coreAlpha),
              color.withValues(alpha: coreAlpha * 0.86),
              color.withValues(alpha: coreAlpha * 0.55),
              color.withValues(alpha: coreAlpha * 0.24),
              color.withValues(alpha: coreAlpha * 0.07),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.22, 0.45, 0.65, 0.83, 1.0],
          ),
        ),
      ),
    );
  }
}
