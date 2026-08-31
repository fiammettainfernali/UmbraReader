// Swiping past the end of a chapter should reach the next one — on both
// platforms' scroll physics.
//
// The bug this pins: the detector originally read only the scroll metrics,
// which is a live signal under iOS bouncing physics and a permanently-zero
// one under Android clamping physics. The gesture worked on the phone it was
// written on and did nothing at all on the other, with no error anywhere —
// the chapter just refused to turn until you tapped instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/reader/edge_crossing.dart';

/// One drag under clamping physics: the position is pinned at [at], and every
/// delta comes back as refused.
void dragClamped(EdgeCrossDetector d, double distance, {double at = 500}) {
  const step = 10.0;
  final steps = (distance.abs() / step).ceil();
  for (var i = 0; i < steps; i++) {
    d.noteRefused(distance.sign * step);
    // The metrics never move: that is the whole point of clamping physics.
    d.noteMetrics(pixels: at, minExtent: 0, maxExtent: at);
  }
}

/// One drag under bouncing physics: no refusals, the position leaves the
/// content and is reported in the metrics.
void dragBouncing(EdgeCrossDetector d, double distance, {double max = 500}) {
  const step = 10.0;
  final steps = (distance.abs() / step).ceil();
  for (var i = 1; i <= steps; i++) {
    d.noteMetrics(
      pixels: max + distance.sign * step * i,
      minExtent: 0,
      maxExtent: max,
    );
  }
}

void main() {
  group('clamping physics (Android)', () {
    test('a firm drag past the end asks for the next chapter', () {
      final d = EdgeCrossDetector();
      dragClamped(d, 200);
      expect(d.settle(), ChapterCross.next);
    });

    test('a firm drag past the start asks for the previous chapter', () {
      final d = EdgeCrossDetector();
      dragClamped(d, -200, at: 0);
      expect(d.settle(), ChapterCross.previous);
    });

    test('a short drag is not a crossing', () {
      final d = EdgeCrossDetector();
      dragClamped(d, 40);
      expect(d.settle(), ChapterCross.none);
    });

    test('dragging out and back again is not a crossing', () {
      final d = EdgeCrossDetector();
      dragClamped(d, 200);
      dragClamped(d, -200);
      expect(d.settle(), ChapterCross.none);
    });
  });

  group('bouncing physics (iOS)', () {
    test('a firm drag past the end asks for the next chapter', () {
      final d = EdgeCrossDetector();
      dragBouncing(d, 200);
      expect(d.settle(), ChapterCross.next);
    });

    test('a firm drag past the start asks for the previous chapter', () {
      final d = EdgeCrossDetector();
      dragBouncing(d, -200, max: 0);
      expect(d.settle(), ChapterCross.previous);
    });

    test('a short drag is not a crossing', () {
      final d = EdgeCrossDetector();
      dragBouncing(d, 40);
      expect(d.settle(), ChapterCross.none);
    });

    test('springing back after release keeps the peak', () {
      // Release lets the position travel back in through smaller values.
      // Those must not erase what the finger already did.
      final d = EdgeCrossDetector();
      dragBouncing(d, 200);
      for (var p = 690.0; p >= 500; p -= 10) {
        d.noteMetrics(pixels: p, minExtent: 0, maxExtent: 500);
      }
      expect(d.settle(), ChapterCross.next);
    });
  });

  group('housekeeping', () {
    test('settling clears the gesture', () {
      final d = EdgeCrossDetector();
      dragClamped(d, 200);
      expect(d.settle(), ChapterCross.next);
      // A second settle with no new drag must not cross again — this is what
      // stops one long swipe from walking several chapters forward.
      expect(d.settle(), ChapterCross.none);
    });

    test('reset abandons travel recorded so far', () {
      final d = EdgeCrossDetector();
      dragClamped(d, 200);
      d.reset();
      expect(d.settle(), ChapterCross.none);
    });

    test('scrolling inside the content records nothing', () {
      final d = EdgeCrossDetector();
      for (var p = 0.0; p <= 500; p += 25) {
        d.noteMetrics(pixels: p, minExtent: 0, maxExtent: 500);
      }
      expect(d.travel, 0);
      expect(d.settle(), ChapterCross.none);
    });

    test('the threshold is honoured on both sides', () {
      // Just under and just over, to pin the boundary rather than assume it.
      final under = EdgeCrossDetector(threshold: 100);
      dragClamped(under, 90);
      expect(under.settle(), ChapterCross.none);

      final over = EdgeCrossDetector(threshold: 100);
      dragClamped(over, 110);
      expect(over.settle(), ChapterCross.next);
    });
  });
}
