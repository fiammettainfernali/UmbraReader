import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// A reading colour theme — page background, body text, and a dim accent
/// (used for dividers and secondary text in the reader).
class ReaderThemePreset {
  const ReaderThemePreset({
    required this.id,
    required this.name,
    required this.background,
    required this.text,
    required this.secondary,
    required this.highlight,
  });

  final String id;
  final String name;
  final Color background;
  final Color text;
  final Color secondary;

  /// Background colour for the sentence being read aloud.
  final Color highlight;

  /// True when the background is light enough to need dark foreground/status
  /// elements.
  bool get isLight => background.computeLuminance() > 0.5;

  /// This theme washed with [tint] at [severity] (0 = off, 1 = full).
  ///
  /// Returns `this` untouched when the wash would be a no-op, so the common
  /// case allocates nothing.
  ReaderThemePreset withOverlay(ReaderOverlayTint tint, double severity) {
    final s = severity.clamp(0.0, 1.0);
    if (s == 0 || tint.id == kOverlayTintNone) return this;
    // White is multiply's identity, so lerping the tint away from white
    // gives a continuous strength dial from "no glass" to "full glass".
    final wash = Color.lerp(const Color(0xFFFFFFFF), tint.color, s)!;
    final washedBackground = _multiply(background, wash);
    final washedText = _multiply(text, wash);
    return ReaderThemePreset(
      id: id,
      name: name,
      background: washedBackground,
      text: washedText,
      secondary: _liftToContrast(
        _multiply(secondary, wash),
        washedBackground,
        washedText,
      ),
      highlight: _multiply(highlight, wash),
    );
  }
}

/// Contrast floor for secondary text against the page — WCAG AA for large
/// text, matching the bar the untinted palettes are tuned to.
const double _kSecondaryContrastFloor = 3.0;

/// WCAG 2.x contrast ratio between two colours (1..21).
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Nudges [c] toward [toward] until it clears [_kSecondaryContrastFloor]
/// against [bg].
///
/// Body text survives a wash because it sits at one end of the range and
/// multiply keeps near-black near-black, but mid-tone secondary text gets
/// compressed toward the background and can fall under the bar. Physical
/// acetate really does wash out low-contrast print this way; we are not
/// obliged to reproduce the flaw, since the point of the overlay is comfort,
/// not fidelity. [toward] is the washed body colour, which already clears
/// AA, so the walk always terminates on something legible.
Color _liftToContrast(Color c, Color bg, Color toward) {
  if (_contrastRatio(c, bg) >= _kSecondaryContrastFloor) return c;
  for (var k = 0.05; k < 1.0; k += 0.05) {
    final candidate = Color.lerp(c, toward, k)!;
    if (_contrastRatio(candidate, bg) >= _kSecondaryContrastFloor) {
      return candidate;
    }
  }
  return toward;
}

/// Multiplies [base] by [wash] per channel, preserving [base]'s alpha.
Color _multiply(Color base, Color wash) => Color.fromARGB(
  (base.a * 255).round(),
  (base.r * wash.r * 255).round(),
  (base.g * wash.g * 255).round(),
  (base.b * wash.b * 255).round(),
);

/// Id of the "no wash" tint.
const String kOverlayTintNone = 'none';

/// An Irlen-style colour wash laid over the page.
///
/// Modelled on the physical thing it imitates: a transparent coloured sheet
/// resting on paper. That is a *subtractive* filter, so the tint MULTIPLIES
/// the page rather than being painted over it. The distinction matters — an
/// alpha overlay drags text and background toward the tint alike and eats
/// contrast, whereas multiply absorbs light from the bright background while
/// leaving near-black text near-black. Cutting glare must not cost legibility,
/// which is the whole reason someone reaches for an overlay.
class ReaderOverlayTint {
  const ReaderOverlayTint({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;

  /// The wash at full severity. White is multiply's identity, hence
  /// [kOverlayTintNone] being plain white.
  final Color color;
}

/// The selectable overlay tints, in display order. Hues follow the families
/// used by physical overlay sets (blue/aqua through rose/violet, plus a
/// neutral grey for glare without colour).
const List<ReaderOverlayTint> kOverlayTints = [
  ReaderOverlayTint(
    id: kOverlayTintNone,
    name: 'None',
    color: Color(0xFFFFFFFF),
  ),
  ReaderOverlayTint(id: 'blue', name: 'Blue', color: Color(0xFF7FB2E5)),
  ReaderOverlayTint(id: 'aqua', name: 'Aqua', color: Color(0xFF7FD8D0)),
  ReaderOverlayTint(id: 'green', name: 'Green', color: Color(0xFF9BD9A0)),
  ReaderOverlayTint(id: 'yellow', name: 'Yellow', color: Color(0xFFF2D97F)),
  ReaderOverlayTint(id: 'peach', name: 'Peach', color: Color(0xFFF5B78A)),
  ReaderOverlayTint(id: 'rose', name: 'Rose', color: Color(0xFFF29FB5)),
  ReaderOverlayTint(id: 'violet', name: 'Violet', color: Color(0xFFB79FE0)),
  ReaderOverlayTint(id: 'grey', name: 'Grey', color: Color(0xFFB0B0B0)),
];

/// Looks up an overlay tint by id, defaulting to no wash.
ReaderOverlayTint overlayTintById(String id) {
  for (final tint in kOverlayTints) {
    if (tint.id == id) return tint;
  }
  return kOverlayTints[0];
}

/// The built-in reading themes, in display order.
const List<ReaderThemePreset> kReaderThemes = [
  ReaderThemePreset(
    id: 'light',
    name: 'Light',
    background: Color(0xFFFBFAF8),
    text: Color(0xFF1B1A18),
    secondary: Color(0xFF8C8983),
    highlight: Color(0xFFFCE3A3),
  ),
  ReaderThemePreset(
    id: 'sepia',
    name: 'Sepia',
    background: Color(0xFFFBF0D9),
    text: Color(0xFF5B4636),
    // Nudged from 0xFFA28B68 (2.89:1) to clear the 3:1 contrast bar --
    // visually identical, see theme_contrast_test.dart.
    secondary: Color(0xFF9D8663),
    highlight: Color(0xFFEAD49C),
  ),
  ReaderThemePreset(
    id: 'dark',
    name: 'Dark',
    background: Color(0xFF222426),
    text: Color(0xFFD7D5D1),
    secondary: Color(0xFF7E7C78),
    highlight: Color(0xFF3C4A5A),
  ),
  ReaderThemePreset(
    id: 'grey',
    name: 'Grey',
    background: Color(0xFF44464A),
    text: Color(0xFFFFFFFF),
    secondary: Color(0xFFA6A7AB),
    highlight: Color(0xFF5C6878),
  ),
  ReaderThemePreset(
    id: 'black',
    name: 'Black',
    background: Color(0xFF000000),
    text: Color(0xFFC4C2BE),
    secondary: Color(0xFF6C6A67),
    highlight: Color(0xFF333338),
  ),
];

/// User-defined themes loaded at app start, searched in addition to the
/// built-ins by [readerThemeById]. Populated via [setAdditionalThemes] from
/// the custom-theme store; kept here so the lookup stays synchronous.
List<ReaderThemePreset> _additionalThemes = const [];

/// Replaces the registered list of user-defined themes.
void setAdditionalThemes(List<ReaderThemePreset> themes) {
  _additionalThemes = themes;
}

/// Looks up a theme by id, defaulting to Dark.
ReaderThemePreset readerThemeById(String id) {
  for (final theme in kReaderThemes) {
    if (theme.id == id) return theme;
  }
  for (final theme in _additionalThemes) {
    if (theme.id == id) return theme;
  }
  return kReaderThemes[2];
}
