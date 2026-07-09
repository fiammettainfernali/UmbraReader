import 'package:flutter/material.dart';

/// The reading ruler: dims the page except for a horizontal band of a few
/// lines at the teleprompter position (matching where read-aloud follow
/// keeps the spoken line). The band is fixed on screen — text scrolls or
/// pages through it — so the eye always has one bright home row.
///
/// Pure overlay: pointer-transparent, no layout impact, and the scrims use
/// the page background colour so dimmed text ghosts through legibly on any
/// theme, light or dark.
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
        final top = (height * bandCentre - bandHeight / 2).clamp(
          0.0,
          height,
        );
        final bottom = (top + bandHeight).clamp(0.0, height);
        final scrim = background.withValues(alpha: dimOpacity);
        final edge = Theme.of(context).colorScheme.outline.withValues(
          alpha: 0.25,
        );
        return Column(
          children: [
            // Above the band.
            SizedBox(
              height: top,
              width: double.infinity,
              child: ColoredBox(color: scrim),
            ),
            Container(
              height: 1,
              color: edge,
            ),
            SizedBox(height: (bottom - top - 2).clamp(0.0, height)),
            Container(
              height: 1,
              color: edge,
            ),
            // Below the band.
            Expanded(
              child: ColoredBox(color: scrim),
            ),
          ],
        );
      },
    );
  }
}
