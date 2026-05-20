import 'reader_theme.dart';

/// How chapter content is laid out in the reader.
enum ReadingMode {
  /// Continuous vertical scrolling.
  scroll,

  /// Discrete pages, turned horizontally.
  paged,
}

/// All reader preferences: layout mode, colour theme, and typography.
class ReaderSettings {
  const ReaderSettings({
    required this.mode,
    required this.themeId,
    required this.fontFamily,
    required this.fontSize,
    required this.lineHeight,
    required this.margin,
  });

  final ReadingMode mode;

  /// Id of the active [ReaderThemePreset].
  final String themeId;

  /// Google Fonts family name; an empty string means the system font.
  final String fontFamily;

  /// Body text size in logical pixels.
  final double fontSize;

  /// Line-height multiplier.
  final double lineHeight;

  /// Horizontal page margin in logical pixels.
  final double margin;

  static const defaults = ReaderSettings(
    mode: ReadingMode.scroll,
    themeId: 'dark',
    fontFamily: '',
    fontSize: 18,
    lineHeight: 1.62,
    margin: 20,
  );

  ReaderThemePreset get theme => readerThemeById(themeId);

  ReaderSettings copyWith({
    ReadingMode? mode,
    String? themeId,
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? margin,
  }) {
    return ReaderSettings(
      mode: mode ?? this.mode,
      themeId: themeId ?? this.themeId,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      margin: margin ?? this.margin,
    );
  }
}
