import 'reader_theme.dart';

/// How chapter content is laid out in the reader.
enum ReadingMode {
  /// Continuous vertical scrolling.
  scroll,

  /// Discrete pages, turned horizontally.
  paged,
}

/// Horizontal alignment of body text in the reader.
enum ReaderTextAlign {
  /// A ragged right edge.
  left,

  /// Spread to both margins.
  justify,
}

/// Locks the reader to a chosen device orientation, or follows the
/// system's auto-rotate setting.
enum ReaderOrientation {
  auto,
  portrait,
  landscape,
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
    required this.textAlign,
    required this.autoScroll,
    required this.orientation,
    required this.tvMode,
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

  /// Horizontal alignment of body paragraphs.
  final ReaderTextAlign textAlign;

  /// Whether the scroll-mode reader slowly auto-scrolls for hands-free
  /// reading. Crosses chapters automatically when it reaches the bottom.
  final bool autoScroll;

  /// Locks the reader to a fixed orientation, or follows the system's
  /// auto-rotate setting when [ReaderOrientation.auto].
  final ReaderOrientation orientation;

  /// "TV mode" — reading laid out for a TV via iOS screen mirroring:
  /// landscape, paged, two columns per spread, with chrome hidden. The
  /// phone is intended to mirror to a TV while you sit back; use the
  /// brightness slider to dim the phone itself.
  final bool tvMode;

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
    textAlign: ReaderTextAlign.left,
    autoScroll: false,
    orientation: ReaderOrientation.auto,
    tvMode: false,
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
    ReaderTextAlign? textAlign,
    bool? autoScroll,
    ReaderOrientation? orientation,
    bool? tvMode,
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
      textAlign: textAlign ?? this.textAlign,
      autoScroll: autoScroll ?? this.autoScroll,
      orientation: orientation ?? this.orientation,
      tvMode: tvMode ?? this.tvMode,
    );
  }
}
