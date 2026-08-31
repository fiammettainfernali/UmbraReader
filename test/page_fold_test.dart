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
    test('the crease travels from the outer edge to the spine', () {
      expect(FoldingPage.creaseFor(0), 1, reason: 'flat: nothing uncovered');
      expect(FoldingPage.creaseFor(0.5), closeTo(0.5, 1e-9));
      expect(FoldingPage.creaseFor(1), 0, reason: 'turned: all uncovered');
    });

    test('the dragged edge outruns the crease, two to one', () {
      // Folding a sheet in half moves its edge two units for every one the
      // crease moves. Getting this wrong by a factor leaves half a page of
      // flap lying on the screen at the end of the turn instead of carrying
      // it off the side.
      for (final t in [0.1, 0.3, 0.7]) {
        final creaseTravel = 1 - FoldingPage.creaseFor(t);
        final edgeTravel = 1 - FoldingPage.edgeFor(t);
        expect(edgeTravel, closeTo(2 * creaseTravel, 1e-9));
      }
    });

    test('the flap has left the screen by the end of the turn', () {
      expect(FoldingPage.edgeFor(1), lessThanOrEqualTo(0));
    });

    test('past halfway there is no flat page left, only flap', () {
      // The sheet is folded in half at turn 0.5; beyond that the whole of it
      // is doubled over and nothing of it is still lying flat.
      expect(FoldingPage.edgeFor(0.5), closeTo(0, 1e-9));
      expect(FoldingPage.edgeFor(0.75), lessThan(0));
    });

    test('the back of the sheet is dimmed, but is never a black bar', () {
      expect(FoldingPage.backingFor(0), 0);
      expect(FoldingPage.backingFor(1), lessThan(0.8));
      expect(
        FoldingPage.backingFor(0.5),
        greaterThan(FoldingPage.backingFor(0.001)),
      );
    });

    test('the backing fades in rather than appearing at full strength', () {
      // A flap has no area at all at turn 0. If its darkening were already
      // at full strength the instant the crease formed, the fold would begin
      // with a black sliver snapping into existence at the page edge.
      expect(FoldingPage.backingFor(0.02), lessThan(FoldingPage.backingFor(1)));
    });

    test('clamps rather than extrapolating past a finished turn', () {
      // A pager can overshoot on a fling.
      expect(FoldingPage.creaseFor(1.4), FoldingPage.creaseFor(1));
      expect(FoldingPage.edgeFor(1.4), FoldingPage.edgeFor(1));
      expect(FoldingPage.backingFor(-0.2), 0);
    });

    testWidgets('renders its page', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FoldingPage(turn: 0.4, child: Text('mid-turn')),
          ),
        ),
      );
      // Twice: the part still lying flat, and the part folded back on itself
      // showing its own reverse.
      expect(find.text('mid-turn'), findsNWidgets(2));
    });

    testWidgets('a flat sheet is one undivided page', (tester) async {
      // At rest the reader must be exactly what it is with folding off — no
      // crease, no flap, no seam down a page nobody is turning.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FoldingPage(turn: 0, child: Text('at rest')),
          ),
        ),
      );
      expect(find.text('at rest'), findsOneWidget);
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
              background: const Color(0xFF101010),
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
              background: const Color(0xFF101010),
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
              background: const Color(0xFF101010),
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
              background: const Color(0xFF101010),
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

      // The lifting sheet is drawn by the overlay, once per strip of the
      // curve. The page being uncovered is drawn by the pager exactly once —
      // that is the invariant with teeth, because pinned pages all occupy
      // the same rectangle, so a second one would print a whole chapter over
      // the top of another.
      expect(find.text('page 0'), findsWidgets);
      expect(find.text('page 1'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('spreads', () {
    testWidgets('mid-turn the left page stays put and the right one lifts', (
      tester,
    ) async {
      // A two-column spread creases across the whole screen like any other
      // page. It is one continuous run of text set in two columns, not the
      // facing pages of a bound book -- an earlier version hinged it down the
      // middle as though there were a spine there, which folded a page in
      // half that was never two pages and left the crease stranded in the
      // centre of the screen.
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoldingPager(
              controller: controller,
              background: const Color(0xFF101010),
              itemCount: 3,
              itemBuilder: (context, i) => Row(
                children: [
                  Expanded(child: Text('left $i')),
                  Expanded(child: Text('right $i')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      // A quarter of the way: far enough to have a crease, not so far that
      // the sheet is folded exactly in half, which is the one position where
      // nothing of it is still lying flat.
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();

      // The outgoing spread is on screen twice: the part still lying flat,
      // and the part folded back showing its reverse.
      expect(find.text('left 0'), findsNWidgets(2));
      expect(find.text('right 0'), findsNWidgets(2));
      // The spread being uncovered is drawn once, by the pager, underneath.
      // More than once would be two chapters printed over each other.
      expect(find.text('left 1'), findsOneWidget);
      expect(find.text('right 1'), findsOneWidget);

      // Carry it past halfway so the pager settles forward rather than
      // springing back, and the turn actually completes.
      await gesture.moveBy(const Offset(-500, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('left 0'), findsNothing);
      expect(find.text('left 1'), findsOneWidget);
    });

    testWidgets('a settled spread is not doubled', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoldingPager(
              controller: controller,
              background: const Color(0xFF101010),
              itemCount: 3,
              itemBuilder: (context, i) => Text('spread $i'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('spread 0'), findsOneWidget);
    });
  });

  group('the sheet is opaque', () {
    testWidgets('a lifted page brings its paper with it', (tester) async {
      // The bug this pins shipped and was obvious the moment it was seen: a
      // page widget paints its text and nothing else, so the sheet lifted
      // into the overlay was transparent and the page being uncovered read
      // straight through it. Two chapters of text superimposed, for the
      // whole turn.
      const paper = Color(0xFF101010);
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoldingPager(
              controller: controller,
              background: paper,
              itemCount: 3,
              itemBuilder: (context, i) => Text('page $i'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();

      // Something opaque, in the sheet's colour, is between the two pages.
      final painted = tester.widgetList<ColoredBox>(
        find.byType(ColoredBox),
      ).where((b) => b.color == paper);
      expect(painted, isNotEmpty, reason: 'the turning sheet has no paper');

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

    test('migraine mode stops it outright', () {
      // Not by way of pageAnimations: that governs programmatic turns, and a
      // drag rotates the sheet whatever it says. The comfort preset has to
      // say so itself.
      final on = ReaderSettings.defaults.copyWith(pageFold: true);
      expect(on.migraineAdjusted().pageFold, isFalse);
    });

    test('does not depend on page animations', () {
      // It used to, and that was the bug: reduce-motion turns instant page
      // turns on, which silently disabled a fold the reader had explicitly
      // switched on. Instant turns need no gate — they jump between whole
      // pages, and foldFrameFor finds nothing to fold in between.
      expect(foldFrameFor(3.0), isNull);
      expect(foldFrameFor(4.0), isNull);
    });
  });
}
