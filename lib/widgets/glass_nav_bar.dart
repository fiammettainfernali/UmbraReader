import 'dart:ui';

import 'package:flutter/material.dart';

/// The app's bottom bar, drawn as translucent glass over whatever is scrolling
/// beneath it.
///
/// Flutter paints its own widgets rather than hosting UIKit, so Apple's real
/// Liquid Glass material isn't something it can simply adopt — the Cupertino
/// rebuild that will bring it is tracked in flutter/flutter#170310 and isn't
/// expected before late 2026. This is the approximation that needs no native
/// platform views and no new dependency: the content behind the bar is
/// blurred, a translucent tint sits over it, and a hairline catches the light
/// along the top edge. What it doesn't do is refract or throw specular
/// highlights, which is the part only a shader or a real UIKit view gives you.
///
/// It only reads as glass because covers pass *under* it, so the shell sets
/// `extendBody` and hands its tabs [barHeight] as bottom padding — otherwise
/// there is nothing behind the bar to blur and it is just a tinted strip.
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
  /// Matches [NavigationBar]'s default so the bar is the same size it was
  /// before it became glass.
  static const double barHeight = 80;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Increase Contrast is the closest signal Flutter exposes to iOS's Reduce
    // Transparency, and people turn both on for the same reason: text over a
    // blurred backdrop is harder to read. Give them a solid bar instead.
    final opaque = MediaQuery.of(context).highContrast;

    final bar = NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
    );

    if (opaque) {
      return ColoredBox(color: scheme.surfaceContainer, child: bar);
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Dark and heavy enough that labels stay legible over a bright
            // cover, sheer enough that you can see one move past.
            color: scheme.surface.withValues(alpha: 0.62),
            border: Border(
              top: BorderSide(
                color: scheme.onSurface.withValues(alpha: 0.10),
                width: 0.5,
              ),
            ),
          ),
          child: bar,
        ),
      ),
    );
  }
}
