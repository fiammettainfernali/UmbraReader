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

class _StillScreen extends StatefulWidget {
  const _StillScreen();

  @override
  State<_StillScreen> createState() => _StillScreenState();
}

class _StillScreenState extends State<_StillScreen> with HoldsMotionStill {
  @override
  Widget build(BuildContext context) => const Text('Reading');
}

bool _running(WidgetTester tester, Type type) =>
    (tester.state(find.byType(type)) as SlowClock).clockRunning;

void main() {
  tearDown(() {
    AppMotion.reduceAnimations.value = false;
    AppMotion.stillScreens.value = 0;
  });

  testWidgets('every pushed screen gets embers and a clear scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.black,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {TargetPlatform.android: LivingPageTransitions()},
          ),
        ),
        home: const Scaffold(body: Text('Home')),
      ),
    );
    expect(find.byType(EmberBackdrop), findsOneWidget);
    final context = tester.element(find.text('Home'));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Details')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    expect(find.byType(EmberBackdrop), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Details'))).scaffoldBackgroundColor,
      Colors.transparent,
    );
    // Only the screen on show keeps its clock running.
    expect(_running(tester, EmberBackdrop), isTrue);
  });

  testWidgets('a screen that holds still stops everything until it closes', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const EmberBackdrop()));
    final context = tester.element(find.byType(EmberBackdrop));
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const _StillScreen()));
    await tester.pumpAndSettle();
    expect(AppMotion.stillScreens.value, 1);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(AppMotion.stillScreens.value, 0);
    expect(_running(tester, EmberBackdrop), isTrue);
  });

  testWidgets('a backdrop opened beneath a still screen stays stopped', (
    tester,
  ) async {
    AppMotion.stillScreens.value = 1;
    await tester.pumpWidget(_app(const EmberBackdrop()));
    expect(_running(tester, EmberBackdrop), isFalse);
    AppMotion.stillScreens.value = 0;
    await tester.pump();
    expect(_running(tester, EmberBackdrop), isTrue);
  });

  testWidgets('a hidden tab keeps nothing moving', (tester) async {
    Widget tabs(int index) => _app(
      IndexedStack(
        index: index,
        children: const [
          SizedBox(key: Key('library')),
          Twinkle(child: SizedBox()),
        ],
      ),
    );
    await tester.pumpWidget(tabs(0));
    expect(
      (tester.state(find.byType(Twinkle, skipOffstage: false)) as SlowClock)
          .clockRunning,
      isFalse,
    );
    await tester.pumpWidget(tabs(1));
    expect(_running(tester, Twinkle), isTrue);
  });

  testWidgets('a screenful of moving pieces costs one frame per beat', (
    tester,
  ) async {
    var frames = 0;
    await tester.pumpWidget(
      _app(
        Column(
          children: const [
            Twinkle(child: SizedBox()),
            Twinkle(phase: 1, child: SizedBox()),
            Twinkle(phase: 2, child: SizedBox()),
            BreathingGlow(borderRadius: BorderRadius.zero, child: SizedBox()),
          ],
        ),
      ),
    );
    tester.binding.addPersistentFrameCallback((_) => frames++);
    // A frame is asked for by each change: with a timer each, they'd arrive
    // apart and this would see one per piece per beat.
    await tester.pump(const Duration(milliseconds: 41));
    final afterOneBeat = frames;
    await tester.pump(const Duration(milliseconds: 41));
    expect(frames - afterOneBeat, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a section waits its turn before rising', (tester) async {
    await tester.pumpWidget(
      _app(const RiseIn(delayMs: 200, child: Text('Later'))),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

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
