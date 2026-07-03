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
