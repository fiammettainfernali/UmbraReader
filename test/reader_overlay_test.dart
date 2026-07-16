// Irlen-style colour overlays.
//
// The design claim is that a tint modelled as a MULTIPLY filter behaves like
// the physical sheet of coloured acetate it imitates: it absorbs light from
// the glaring background while leaving dark text dark. If that claim breaks,
// the feature is actively harmful — someone reaching for an overlay to read
// more comfortably would instead lose text contrast. Hence the contrast bar
// below is the load-bearing test, not a nicety.

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/models/reader_theme.dart';

/// WCAG 2.x contrast ratio between two colours (1..21).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

ReaderOverlayTint _tint(String id) => overlayTintById(id);

void main() {
  group('withOverlay', () {
    final light = readerThemeById('light');

    test('no-op cases return the theme untouched', () {
      expect(
        identical(light.withOverlay(_tint(kOverlayTintNone), 1.0), light),
        isTrue,
        reason: 'the "none" tint must not allocate a washed copy',
      );
      expect(
        identical(light.withOverlay(_tint('blue'), 0), light),
        isTrue,
        reason: 'zero severity must not allocate a washed copy',
      );
    });

    test('unknown tint id falls back to no wash', () {
      expect(overlayTintById('nonsense').id, kOverlayTintNone);
    });

    test('a wash pulls the background toward the tint', () {
      final washed = light.withOverlay(_tint('blue'), 1.0);
      // Blue acetate absorbs red and passes blue.
      expect(washed.background.b, greaterThan(washed.background.r));
      expect(
        washed.background.r,
        lessThan(light.background.r),
        reason: 'the wash should absorb light, not add it',
      );
    });

    test('severity scales the wash monotonically', () {
      double redAt(double s) => light.withOverlay(_tint('blue'), s).background.r;
      // More blue acetate = less red getting through.
      expect(redAt(0.25), greaterThan(redAt(0.5)));
      expect(redAt(0.5), greaterThan(redAt(1.0)));
    });

    test('severity is clamped to sane bounds', () {
      expect(
        light.withOverlay(_tint('blue'), 5.0).background,
        light.withOverlay(_tint('blue'), 1.0).background,
      );
      expect(identical(light.withOverlay(_tint('blue'), -1), light), isTrue);
    });

    test('alpha survives the wash', () {
      expect(light.withOverlay(_tint('rose'), 1.0).background.a, 1.0);
    });
  });

  // The point of the exercise: cutting glare must not cost legibility.
  group('body text keeps WCAG AA through any wash', () {
    for (final theme in kReaderThemes) {
      for (final tint in kOverlayTints) {
        test('${theme.name} + ${tint.name} at full strength', () {
          final washed = theme.withOverlay(tint, 1.0);
          final ratio = _contrast(washed.text, washed.background);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${theme.name} washed with ${tint.name} gives '
                '${ratio.toStringAsFixed(2)}:1 — below WCAG AA (4.5:1). '
                'Pick a lighter tint rather than deleting this test.',
          );
        });

        // A wash compresses mid-tone secondary text hardest; withOverlay
        // lifts it back to the bar. Untinted Black + Violet bottoms out
        // near 2.25:1 without that correction.
        test('${theme.name} + ${tint.name} keeps secondary legible', () {
          final washed = theme.withOverlay(tint, 1.0);
          final ratio = _contrast(washed.secondary, washed.background);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                '${theme.name} washed with ${tint.name} gives secondary '
                '${ratio.toStringAsFixed(2)}:1 — below 3:1',
          );
        });
      }
    }
  });

  group('ReaderSettings', () {
    test('defaults to no overlay', () {
      const d = ReaderSettings.defaults;
      expect(d.overlayTint, kOverlayTintNone);
      expect(d.overlaySeverity, 0);
      expect(d.theme.background, readerThemeById(d.themeId).background);
    });

    test('theme getter applies the wash', () {
      final tinted = ReaderSettings.defaults.copyWith(
        themeId: 'light',
        overlayTint: 'green',
        overlaySeverity: 1.0,
      );
      expect(
        tinted.theme.background,
        readerThemeById('light').withOverlay(_tint('green'), 1.0).background,
      );
      expect(
        tinted.theme.background,
        isNot(readerThemeById('light').background),
      );
    });

    test('copyWith round-trips both fields', () {
      final s = ReaderSettings.defaults.copyWith(
        overlayTint: 'aqua',
        overlaySeverity: 0.4,
      );
      expect(s.overlayTint, 'aqua');
      expect(s.overlaySeverity, 0.4);
      expect(s.copyWith().overlayTint, 'aqua');
      expect(s.copyWith().overlaySeverity, 0.4);
    });
  });
}
