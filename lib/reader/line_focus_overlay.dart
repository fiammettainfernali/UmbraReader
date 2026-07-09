import 'package:flutter/material.dart';

/// The reading ruler: dims the page except for a horizontal band of a few
/// lines, with a feathered edge so a line crossing the boundary fades
/// gently instead of being sliced.
///
/// Two positioning modes:
///  - scroll: the band sits at a fixed viewport fraction ([bandCentre],
///    the teleprompter position) and the text scrolls through it;
///  - paged: the page is static, so the band itself steps down the page —
///    the reader passes an explicit [bandTop] that advances tap by tap.
///
/// The dimming is asymmetric on purpose: text ABOVE the band (already
/// read) is a light ghost for orientation, text BELOW (not yet read) is
/// veiled more strongly so it can't pull the eye ahead. Scrims use the
/// page background colour so dimmed text stays legible on any theme.
class LineFocusOverlay extends StatelessWidget {
  const LineFocusOverlay({
    super.key,
    required this.background,
    required this.bandHeight,
    this.bandCentre = 0.42,
    this.bandTop,
    this.dimAbove = 0.5,
    this.dimBelow = 0.78,
  });

  /// The active reading theme's page colour — the scrim tint.
  final Color background;

  /// Height of the clear band, in logical pixels (a few line-heights).
  final double bandHeight;

  /// Where the band's centre sits vertically, as a fraction of the height.
  /// Used when [bandTop] is null (scroll mode).
  final double bandCentre;

  /// Explicit band top in logical pixels (paged mode's stepping band).
  final double? bandTop;

  /// Dim strength for already-read text above the band (light ghost).
  final double dimAbove;

  /// Dim strength for unread text below the band (stronger veil).
  final double dimBelow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (height <= 0) return const SizedBox.shrink();
        final top = (bandTop ?? (height * bandCentre - bandHeight / 2)).clamp(
          0.0,
          height,
        );
        final bottom = (top + bandHeight).clamp(0.0, height);
        const feather = 14.0;
        final above = background.withValues(alpha: dimAbove);
        final below = background.withValues(alpha: dimBelow);
        final clear = background.withValues(alpha: 0);

        double frac(double y) => (y / height).clamp(0.0, 1.0);
        // Monotonic gradient stops: ghost → clear band → veil, feathered.
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
              colors: [above, above, clear, clear, below, below],
              stops: raw,
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
