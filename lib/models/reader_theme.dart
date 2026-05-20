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
  });

  final String id;
  final String name;
  final Color background;
  final Color text;
  final Color secondary;

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
  ),
  ReaderThemePreset(
    id: 'sepia',
    name: 'Sepia',
    background: Color(0xFFFBF0D9),
    text: Color(0xFF5B4636),
    secondary: Color(0xFFA28B68),
  ),
  ReaderThemePreset(
    id: 'dark',
    name: 'Dark',
    background: Color(0xFF222426),
    text: Color(0xFFD7D5D1),
    secondary: Color(0xFF7E7C78),
  ),
  ReaderThemePreset(
    id: 'black',
    name: 'Black',
    background: Color(0xFF000000),
    text: Color(0xFFC4C2BE),
    secondary: Color(0xFF6C6A67),
  ),
];

/// Looks up a theme by id, defaulting to Dark.
ReaderThemePreset readerThemeById(String id) {
  for (final theme in kReaderThemes) {
    if (theme.id == id) return theme;
  }
  return kReaderThemes[2];
}
