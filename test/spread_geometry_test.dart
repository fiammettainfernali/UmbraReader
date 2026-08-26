// The two-page spread used to be gated on "is this landscape?", which an
// unfolded foldable fails: it is tablet-sized and nearly square, so it
// reports as portrait and never opened the spread it has room for. These
// pin the geometry — including that no iOS viewport changed behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/reader/reader_layout.dart';

void main() {
  group('phones never spread', () {
    test('a large phone in landscape is wide but far too short', () {
      // The case the old shortest-side gate existed to exclude, and which
      // splitting on width alone would have broken.
      expect(shouldUseSpread(const Size(932, 430)), isFalse);
    });

    test('a phone in portrait does not spread', () {
      expect(shouldUseSpread(const Size(430, 932)), isFalse);
    });
  });

  group('iOS behaviour is unchanged', () {
    test('an iPad in landscape still spreads', () {
      expect(shouldUseSpread(const Size(1133, 744)), isTrue);
    });

    test('an iPad in portrait still does not', () {
      // 0.66 — comfortably below the threshold, so this stays single-page
      // exactly as it did before the rule changed.
      expect(shouldUseSpread(const Size(744, 1133)), isFalse);
    });

    test('a split-view pane is too narrow to be a tablet', () {
      expect(shouldUseSpread(const Size(507, 1366)), isFalse);
    });
  });

  group('square-ish tablets — the foldable case', () {
    test('an unfolded, nearly square panel spreads despite being portrait', () {
      // Taller than it is wide, so the old landscape flag refused it.
      expect(shouldUseSpread(const Size(840, 900)), isTrue);
    });

    test('exactly square spreads', () {
      expect(shouldUseSpread(const Size(800, 800)), isTrue);
    });
  });

  test('the threshold is the boundary it claims to be', () {
    // Guards the constant itself: a viewport just inside spreads, just
    // outside does not, so a careless edit to either number shows up here.
    const height = 1000.0;
    expect(
      shouldUseSpread(Size(kSpreadMinAspectRatio * height, height)),
      isTrue,
    );
    expect(
      shouldUseSpread(Size(kSpreadMinAspectRatio * height - 1, height)),
      isFalse,
    );
  });

  test('a zero-height viewport does not divide by zero', () {
    expect(shouldUseSpread(const Size(800, 0)), isFalse);
  });
}
