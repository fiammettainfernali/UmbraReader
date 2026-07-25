import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/widgets/glass_nav_bar.dart';

/// The glass bar only works because the shell hands its tabs the bar's
/// footprint as `padding.bottom`, and each tab pads its scroll view by that.
/// Both halves of that contract are easy to break silently — the symptom is
/// the last row of covers sitting unreachably under the bar — so they are
/// asserted here rather than discovered on device.
void main() {
  const destinations = [
    NavigationDestination(icon: Icon(Icons.book), label: 'A'),
    NavigationDestination(icon: Icon(Icons.star), label: 'B'),
  ];

  testWidgets('a tab sees the bar height added to its bottom padding', (
    tester,
  ) async {
    const homeIndicator = 34.0;
    late double seen;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: homeIndicator),
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final mq = MediaQuery.of(context);
              return Scaffold(
                extendBody: true,
                body: MediaQuery(
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(
                      bottom: mq.padding.bottom + GlassNavBar.barHeight,
                    ),
                  ),
                  // A tab is itself a Scaffold; the inset has to survive that
                  // nesting to reach the scroll view inside it.
                  child: Scaffold(
                    body: Builder(
                      builder: (inner) {
                        seen = MediaQuery.of(inner).padding.bottom;
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                bottomNavigationBar: GlassNavBar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                  destinations: destinations,
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(seen, homeIndicator + GlassNavBar.barHeight);
  });

  testWidgets('barHeight matches what the bar actually occupies', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
            bottomNavigationBar: GlassNavBar(
              selectedIndex: 0,
              onDestinationSelected: _ignore,
              destinations: destinations,
            ),
          ),
        ),
      ),
    );

    // With no home-indicator inset the bar is exactly barHeight tall; if the
    // Material default ever moves, the padding handed to the tabs is wrong.
    expect(
      tester.getSize(find.byType(GlassNavBar)).height,
      GlassNavBar.barHeight,
    );
  });

  testWidgets('blurs by default, and goes solid under Increase Contrast', (
    tester,
  ) async {
    Future<void> pumpWith({required bool highContrast}) => tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(highContrast: highContrast),
        child: MaterialApp(
          home: Scaffold(
            body: const SizedBox.shrink(),
            bottomNavigationBar: GlassNavBar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: destinations,
            ),
          ),
        ),
      ),
    );

    await pumpWith(highContrast: false);
    expect(
      find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    await pumpWith(highContrast: true);
    expect(
      find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });
}

void _ignore(int _) {}
