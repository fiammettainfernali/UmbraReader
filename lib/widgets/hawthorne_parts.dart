import 'package:flutter/material.dart';

import '../services/app_motion.dart';
import 'living_surfaces.dart';

/// The pieces the desktop program's screens are built from: a big heading, dark
/// bordered panels, figure tiles and bars that grow into place.

const _red = Color(0xFFE5121F);
const _hot = Color(0xFFFF4B4B);
const _amberFrom = Color(0xFFB35A1E);
const _amberTo = Color(0xFFFFB347);
const _panel = Color(0xFF10060A);
const _edge = Color(0x3DFF5A5A);
const _track = Color(0xFF241114);

/// What every panel looks like.
BoxDecoration panelDecoration({double radius = 18}) => BoxDecoration(
  color: _panel,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: _edge),
);

/// A screen's title, as at the top of each desktop screen.
class ScreenHeading extends StatelessWidget {
  const ScreenHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 12),
  });

  final String title;
  final String? subtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RiseIn(
      child: Padding(
        padding: padding,
        child: Wrap(
          spacing: 10,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 29,
                fontWeight: FontWeight.w800,
                height: 1.1,
                shadows: const [
                  Shadow(color: Color(0x8CE5121F), blurRadius: 22),
                ],
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A dark bordered panel.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: panelDecoration(),
      child: child,
    );
  }
}

/// One figure in a panel: the value large, what it is small beneath.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.warm = false,
    this.delayMs = 0,
  });

  final String value;
  final String label;
  final IconData? icon;

  /// Picks it out in amber, as the desktop does for streaks.
  final bool warm;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RiseIn(
      delayMs: delayMs,
      child: PressScale(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: panelDecoration(radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: warm ? _amberTo : _hot),
                const SizedBox(height: 9),
              ],
              // A set height, so tiles side by side stay level when a long
              // figure has to shrink to fit.
              SizedBox(
                height: 34,
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: warm ? _amberTo : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded bar that grows to [fraction] when it first appears.
class GrowingBar extends StatelessWidget {
  const GrowingBar({
    super.key,
    required this.fraction,
    this.warm = false,
    this.height = 8,
  });

  final double fraction;
  final bool warm;
  final double height;

  @override
  Widget build(BuildContext context) {
    final target = fraction.clamp(0.0, 1.0);
    final reduced = AppMotion.isReduced(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        // Always the full width: left to its own size in a column, the track
        // shrank to the filled part, and an empty bar wasn't there at all.
        width: double.infinity,
        height: height,
        child: ColoredBox(
          color: _track,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 950),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: child,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: warm
                      ? const [_amberFrom, _amberTo]
                      : const [_red, _hot],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label, a growing bar and a number, as in the desktop's Stats.
class MeterRow extends StatelessWidget {
  const MeterRow({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    this.warm = false,
  });

  final String label;
  final String value;
  final double fraction;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: GrowingBar(fraction: fraction, warm: warm),
          ),
          SizedBox(
            width: 52,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The desktop's download bar: red, with stripes running along it. With no
/// [value], the whole bar runs, for work that can't say how far along it is.
class StripedBar extends StatefulWidget {
  const StripedBar({super.key, this.value, this.height = 8});

  final double? value;
  final double height;

  @override
  State<StripedBar> createState() => _StripedBarState();
}

class _StripedBarState extends State<StripedBar> with SlowClock {
  @override
  Widget build(BuildContext context) {
    final height = widget.height;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: ColoredBox(
          color: _track,
          child: AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            alignment: Alignment.centerLeft,
            widthFactor: (widget.value ?? 1).clamp(0.0, 1.0),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _StripesPainter(seconds),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StripesPainter extends CustomPainter {
  _StripesPainter(this.seconds) : super(repaint: seconds);

  final ValueNotifier<double> seconds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _red);
    const spacing = 22.0;
    final shift = (seconds.value * 26) % spacing;
    final stripe = Paint()..color = const Color(0x40FFFFFF);
    final h = size.height;
    for (var x = -spacing + shift; x < size.width + spacing; x += spacing) {
      canvas.drawPath(
        Path()
          ..moveTo(x, h)
          ..lineTo(x + h, 0)
          ..lineTo(x + h + spacing / 2, 0)
          ..lineTo(x + spacing / 2, h)
          ..close(),
        stripe,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter oldDelegate) => false;
}
