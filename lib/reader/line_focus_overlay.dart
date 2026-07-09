import 'package:flutter/material.dart';

/// The reading ruler: dims the page except for a horizontal band of a few
/// lines at the teleprompter position (matching where read-aloud follow
/// keeps the spoken line). The band is fixed on screen — text scrolls or
/// pages through it — so the eye always has one bright home row.
///
/// Pure overlay: pointer-transparent, no layout impact. Implemented as one
/// full-size vertical gradient so both scrims are guaranteed to paint and
/// the band edges are feathered — a line crossing the boundary fades gently
/// instead of being sliced in half. Scrims use the page background colour so
/// dimmed text ghosts through legibly on any theme.
class LineFocusOverlay extends StatelessWidget {
  const LineFocusOverlay({
    super.key,
    required this.background,
    required this.bandHeight,
    this.bandCentre = 0.42,
    this.dimOpacity = 0.72,
  });

  /// The active reading theme's page colour — the scrim tint.
  final Color background;

  /// Height of the clear band, in logical pixels (a few line-heights).
  final double bandHeight;

  /// Where the band's centre sits vertically, as a fraction of the height.
  final double bandCentre;

  /// How strongly the out-of-band text is dimmed (0..1).
  final double dimOpacity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (height <= 0) return const SizedBox.shrink();
        final top = (height * bandCentre - bandHeight / 2).clamp(0.0, height);
        final bottom = (top + bandHeight).clamp(0.0, height);
        const feather = 14.0;
        final scrim = background.withValues(alpha: dimOpacity);
        final clear = background.withValues(alpha: 0);

        double frac(double y) => (y / height).clamp(0.0, 1.0);
        // Monotonic gradient stops: scrim → clear band → scrim, with a
        // feathered transition on both edges.
        final raw = [
          0.0,
          frac(top - feather),
          frac(top + feather),
          frac(bottom - feather),
          frac(bottom + feather),
          1.0,
        ];
        for (var i = 1; i < raw.length; i++) {
          if (raw[i] < raw[i - 1]) raw[i] = raw[i - 1];
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [scrim, scrim, clear, clear, scrim, scrim],
              stops: raw,
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
