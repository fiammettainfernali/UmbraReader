// The geometry of a folding page turn.
//
// The fold's whole reason for existing is paint order — the page being left
// has to be drawn above the one being revealed — so what is pinned here is
// which page is folding at any moment, and how far. Get that wrong by one
// and the reader folds the page you are turning *to*, which looks like the
// book going backwards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/reader/page_fold.dart';

void main() {
  group('foldFrameFor', () {
    test('a settled pager is not folding', () {
      // The common case by far, and the one that has to cost nothing: at
      // rest the reader must be exactly what it is with folding off.
      expect(foldFrameFor(0), isNull);
      expect(foldFrameFor(3), isNull);
    });

    test('nothing to fold before the pager has been laid out', () {
      expect(foldFrameFor(null), isNull);
    });

    test('a NaN position folds nothing rather than throwing', () {
      expect(foldFrameFor(double.nan), isNull);
      expect(foldFrameFor(double.infinity), isNull);
    });

    test('mid-turn, the page being left is the one that folds', () {
      // Going forward from page 3: the pager reads 3.4, and it is page 3 —
      // the one you are leaving — that lifts. Page 4 lies flat underneath.
      final frame = foldFrameFor(3.4);
      expect(frame, isNotNull);
      expect(frame!.index, 3);
      expect(frame.turn, closeTo(0.4, 1e-9));
    });

    test('turning back folds the page settling down again', () {
      // Coming back from page 4 towards 3, the pager passes 3.8: the sheet
      // in motion is page 3, on its way to lying flat.
      final frame = foldFrameFor(3.8);
      expect(frame!.index, 3);
      expect(frame.turn, closeTo(0.8, 1e-9));
    });

    test('a hair off an integer is not a turn', () {
      // A pager at rest does not report an exact integer. Folding on that
      // would keep the overlay alive forever, building a page twice for a
      // fold of a fraction of a degree.
      expect(foldFrameFor(2.0005), isNull);
      expect(foldFrameFor(2.9995), isNull);
    });

    test('the fold runs the whole way across the gap', () {
      // Every position between two pages folds something, so the sheet
      // never blinks out partway through the turn.
      for (var t = 0.01; t < 1.0; t += 0.01) {
        expect(foldFrameFor(5 + t), isNotNull, reason: 'at 5+$t');
      }
    });
  });

  group('FoldingPage', () {
    test('sweeps through a right angle, flat to edge-on', () {
      expect(FoldingPage.angleFor(0), 0);
      expect(FoldingPage.angleFor(1), closeTo(-1.5707963, 1e-6));
      // Negative: the free edge sweeps away from the reader, towards the
      // spine on the left. A positive angle would swing it out of the screen.
      expect(FoldingPage.angleFor(0.5), lessThan(0));
    });

    test('shading deepens with the turn but never reaches black', () {
      expect(FoldingPage.shadeFor(0), 0);
      expect(FoldingPage.shadeFor(1), lessThan(0.5));
      expect(FoldingPage.shadeFor(1), greaterThan(FoldingPage.shadeFor(0.5)));
    });

    test('out-of-range turns are clamped rather than exaggerated', () {
      // A pager can overshoot on a fling; the sheet must not spin past
      // edge-on or invert its shading.
      expect(FoldingPage.angleFor(1.4), FoldingPage.angleFor(1));
      expect(FoldingPage.shadeFor(-0.2), 0);
    });

    testWidgets('renders its page', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FoldingPage(turn: 0.5, child: Text('mid-turn')),
          ),
        ),
      );
      expect(find.text('mid-turn'), findsOneWidget);
    });
  });

  group('FoldingPager', () {
    testWidgets('with folding off it is a plain PageView', (tester) async {
      // The unfolded path stays the long-proven one: paging is what every
      // reading session runs through, so switching the setting back has to
      // return the reader to exactly what it was.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoldingPager(
              controller: PageController(),
              itemCount: 3,
              folding: false,
              itemBuilder: (context, i) => Text('page $i'),
            ),
          ),
        ),
      );
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('page 0'), findsOneWidget);
    });

    testWidgets('a settled folding pager shows one page, once', (
      tester,
    ) async {
      // The overlay draws the folding page a second time. At rest nothing is
      // folding, so nothing may be doubled — a duplicate here would show as
      // bolded text where two copies overlap.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoldingPager(
              controller: PageController(),
              itemCount: 3,
              itemBuilder: (context, i) => Text('page $i'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('page 0'), findsOneWidget);
    });

    testWidgets('turning a page arrives at the next one', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoldingPager(
              controller: controller,
              itemCount: 3,
              itemBuilder: (context, i) => Text('page $i'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(find.text('page 1'), findsOneWidget);
      expect(find.text('page 0'), findsNothing);
    });

    testWidgets('mid-turn both pages are on screen, each once', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoldingPager(
              controller: controller,
              itemCount: 3,
              itemBuilder: (context, i) => Text('page $i'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag halfway and hold, which is where the fold lives.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();

      // The lifting sheet (drawn by the overlay) and the page being
      // uncovered (drawn by the pager) — one copy each. Two copies of page 0
      // would mean the pager is still painting the page the overlay took.
      expect(find.text('page 0'), findsOneWidget);
      expect(find.text('page 1'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('reading the pager position', () {
    test('an unattached controller has no position', () {
      final controller = PageController();
      addTearDown(controller.dispose);
      expect(pagerPage(controller), isNull);
    });

    testWidgets('a controller attached to two pagers has no position', (
      tester,
    ) async {
      // Unfolding the phone rebuilds the reader, and for one frame the old
      // pager and the new one are both attached to the controller.
      // ScrollController.position asserts on anything but exactly one, so
      // reading it there took the reader down mid-unfold. hasClients is true
      // in that moment and is not enough.
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: PageView(
                      controller: controller,
                      children: const [Text('a'), Text('b')],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      expect(controller.hasClients, isTrue);
      expect(pagerPage(controller), isNull);
    });

    testWidgets('a single settled pager reports its page', (tester) async {
      final controller = PageController(initialPage: 1);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: controller,
              children: const [Text('a'), Text('b'), Text('c')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(pagerPage(controller), 1);
    });
  });

  group('the setting', () {
    test('folds by default', () {
      expect(ReaderSettings.defaults.pageFold, isTrue);
    });

    test('migraine mode stops it, by stopping page animation', () {
      // The fold is gated on pageAnimations, which the comfort preset turns
      // off along with every other motion.
      expect(ReaderSettings.defaults.migraineAdjusted().pageAnimations,
          isFalse);
    });
  });
}
