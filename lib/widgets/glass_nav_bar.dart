import 'package:flutter/material.dart';

import '../services/app_motion.dart';

/// The app's bottom bar: solid black, with a hairline along its top edge
/// and the desktop's glowing pill on the chosen tab.
///
/// It used to blur whatever passed beneath it. With embers moving behind every
/// tab that blur had to be worked out again on every beat, which made it the
/// most expensive thing on the screen, so the tint now does the job alone. The
/// shell still sets `extendBody` and hands its tabs [barHeight] as bottom
/// padding, so covers scroll under the bar's edge rather than stop at it.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  /// The bar's own height, above the home-indicator inset it adds on top.
  ///
  /// Matches [NavigationBar]'s default.
  static const double barHeight = 80;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final count = destinations.length;
    final bar = Stack(
      children: [
        // The desktop's nav pill: dark red, a bright edge and a glow, sliding
        // to the chosen tab with a little overshoot.
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          height: 36,
          child: IgnorePointer(
            child: AnimatedAlign(
              alignment: Alignment(-1 + 2 * selectedIndex / (count - 1), 0),
              duration: AppMotion.isReduced(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 620),
              curve: const Cubic(0.34, 1.4, 0.64, 1),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: Center(
                  child: Container(
                    width: 74,
                    decoration: BoxDecoration(
                      color: const Color(0x66A50D18),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5121F)),
                      boxShadow: const [
                        BoxShadow(color: Color(0x99E5121F), blurRadius: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: destinations,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          elevation: 0,
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0506),
        border: Border(
          top: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.10),
            width: 0.5,
          ),
        ),
      ),
      child: bar,
    );
  }
}
