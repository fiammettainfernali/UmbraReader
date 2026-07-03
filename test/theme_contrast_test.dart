// WCAG contrast for the built-in reading themes.
//
// Body text must meet AA for normal text (4.5:1) on every preset — this is
// a *reading* app; text contrast is the product. Secondary text (chapter
// labels, dividers) is decorative/short and gets the AA large-text bar
// (3:1). If a new theme fails here, adjust the palette, don't delete the
// test.

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/reader_theme.dart';

/// WCAG 2.x contrast ratio between two colours (1..21).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  for (final theme in kReaderThemes) {
    test('theme "${theme.name}" meets contrast bars', () {
      final body = _contrast(theme.text, theme.background);
      expect(
        body,
        greaterThanOrEqualTo(4.5),
        reason:
            '${theme.name}: body text contrast is ${body.toStringAsFixed(2)}'
            ':1 — below WCAG AA (4.5:1)',
      );
      final secondary = _contrast(theme.secondary, theme.background);
      expect(
        secondary,
        greaterThanOrEqualTo(3.0),
        reason:
            '${theme.name}: secondary contrast is '
            '${secondary.toStringAsFixed(2)}:1 — below 3:1',
      );
    });
  }
}
