// Tests for the moving parts of the look: they have to run when allowed, stop
// completely when not, and never get between a finger and what's underneath.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/app_motion.dart';
import 'package:umbra_reader/widgets/living_surfaces.dart';

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: child),
  ),
);

bool _running(WidgetTester tester, Type type) =>
    (tester.state(find.byType(type)) as SlowClock).clockRunning;

void main() {
  tearDown(() => AppMotion.reduceAnimations.value = false);

  testWidgets('the backdrop runs when motion is allowed', (tester) async {
    await tester.pumpWidget(_app(const EmberBackdrop()));
    expect(_running(tester, EmberBackdrop), isTrue);
  });

  testWidgets('it asks for no frames between beats', (tester) async {
    // A ticker would ask for every frame the screen can show. That was what
    // kept the app busy at rest, even with little to draw.
    await tester.pumpWidget(_app(const EmberBackdrop()));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets("the phone's Reduce Motion stops the backdrop", (tester) async {
    await tester.pumpWidget(
      _app(const EmberBackdrop(), disableAnimations: true),
    );
    expect(_running(tester, EmberBackdrop), isFalse);
  });

  testWidgets('the in-app switch stops the backdrop while it is showing', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const EmberBackdrop()));
    AppMotion.reduceAnimations.value = true;
    await tester.pump();
    expect(_running(tester, EmberBackdrop), isFalse);
    AppMotion.reduceAnimations.value = false;
    await tester.pump();
    expect(_running(tester, EmberBackdrop), isTrue);
  });

  testWidgets('a screen pushed on top pauses it, and leaving resumes it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const EmberBackdrop()));
    final context = tester.element(find.byType(EmberBackdrop));
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const Text('The reader')));
    await tester.pumpAndSettle();
    expect(find.text('The reader'), findsOneWidget);
    expect(
      (tester.state(find.byType(EmberBackdrop, skipOffstage: false))
              as SlowClock)
          .clockRunning,
      isFalse,
    );
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(_running(tester, EmberBackdrop), isTrue);
  });

  testWidgets('a panel obeys both Reduce Motion and the in-app switch', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const PanelGlow(), disableAnimations: true));
    expect(_running(tester, PanelGlow), isFalse);
    await tester.pumpWidget(_app(const PanelGlow()));
    expect(_running(tester, PanelGlow), isTrue);
    AppMotion.reduceAnimations.value = true;
    await tester.pump();
    expect(_running(tester, PanelGlow), isFalse);
  });

  testWidgets('under Reduce Motion a cover appears at once', (tester) async {
    await tester.pumpWidget(
      _app(const RiseIn(child: Text('Cover')), disableAnimations: true),
    );
    expect(find.byType(Opacity), findsNothing);
    expect(find.text('Cover'), findsOneWidget);
  });

  testWidgets('a cover finishes rising and leaves nothing running', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const RiseIn(child: Text('Cover'))));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  testWidgets('pressing still reaches a tap and a long-press underneath', (
    tester,
  ) async {
    var taps = 0;
    var holds = 0;
    const target = Key('target');
    await tester.pumpWidget(
      _app(
        Center(
          child: PressScale(
            child: GestureDetector(
              key: target,
              onTap: () => taps++,
              onLongPress: () => holds++,
              child: const ColoredBox(
                color: Colors.red,
                child: SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(target));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(target));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(holds, 1);
  });
}
