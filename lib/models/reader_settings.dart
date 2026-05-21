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
    required this.speechRate,
    required this.voiceName,
    required this.voiceLocale,
    required this.boldText,
    required this.italicText,
    required this.brightness,
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

  /// Read-aloud speech rate, 0–1 (flutter_tts scale; ~0.5 is normal).
  final double speechRate;

  /// Chosen read-aloud voice; empty strings mean the system default.
  final String voiceName;
  final String voiceLocale;

  /// When true, all body text is rendered in a heavier weight.
  final bool boldText;

  /// When true, all body text is rendered italic.
  final bool italicText;

  /// Screen brightness for the reader, 0.15–1.0. Below 1.0 a dimming overlay
  /// darkens the page — useful for night reading below the system minimum.
  final double brightness;

  static const defaults = ReaderSettings(
    mode: ReadingMode.scroll,
    themeId: 'dark',
    fontFamily: '',
    fontSize: 18,
    lineHeight: 1.62,
    margin: 20,
    speechRate: 0.5,
    voiceName: '',
    voiceLocale: '',
    boldText: false,
    italicText: false,
    brightness: 1.0,
  );

  ReaderThemePreset get theme => readerThemeById(themeId);

  ReaderSettings copyWith({
    ReadingMode? mode,
    String? themeId,
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? margin,
    double? speechRate,
    String? voiceName,
    String? voiceLocale,
    bool? boldText,
    bool? italicText,
    double? brightness,
  }) {
    return ReaderSettings(
      mode: mode ?? this.mode,
      themeId: themeId ?? this.themeId,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      margin: margin ?? this.margin,
      speechRate: speechRate ?? this.speechRate,
      voiceName: voiceName ?? this.voiceName,
      voiceLocale: voiceLocale ?? this.voiceLocale,
      boldText: boldText ?? this.boldText,
      italicText: italicText ?? this.italicText,
      brightness: brightness ?? this.brightness,
    );
  }
}
