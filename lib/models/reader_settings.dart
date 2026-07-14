import '../services/tts_engine.dart';
import '../services/tts_skip.dart';
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
    required this.letterSpacing,
    required this.wordSpacing,
    required this.paragraphSpacing,
    required this.margin,
    required this.speechRate,
    required this.voiceName,
    required this.voiceLocale,
    required this.boldText,
    required this.italicText,
    required this.brightness,
    required this.textAlign,
    required this.autoScroll,
    required this.lineFocus,
    required this.focusParagraph,
    required this.fixationAnchors,
    required this.orientation,
    required this.tvMode,
    required this.centeredColumn,
    required this.keepAwake,
    required this.reduceAnimations,
    required this.hapticFeedback,
    required this.sessionMinutes,
    required this.exactNumbers,
    required this.autoPageSeconds,
    required this.ttsEngine,
    required this.ttsServerUrl,
    required this.ttsServerToken,
    required this.ttsSkips,
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

  /// Extra spacing between letters, in logical px (0 = default). A crowding
  /// aid — some dyslexic/low-vision readers track text far better with air
  /// between glyphs.
  final double letterSpacing;

  /// Extra spacing between words, in logical px (0 = default).
  final double wordSpacing;

  /// Extra vertical space below each paragraph, in logical px, on top of
  /// the fixed base gap (0 = default).
  final double paragraphSpacing;

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

  /// The reading ruler: dims everything except a band of a few lines at
  /// the teleprompter position, so the eye can't wander — a focus aid for
  /// ADHD/visual-stress readers. Text scrolls/pages through the fixed band.
  final bool lineFocus;

  /// Focus-paragraph mode: one paragraph at a time, centred; tap advances.
  /// Chunking for readers a full page overwhelms.
  final bool focusParagraph;

  /// Fixation anchors (Bionic-style): bold the first letters of each word
  /// as saccade targets.
  final bool fixationAnchors;

  /// Locks the reader to a fixed orientation, or follows the system's
  /// auto-rotate setting when [ReaderOrientation.auto].
  final ReaderOrientation orientation;

  /// "TV mode" — reading laid out for a TV via iOS screen mirroring:
  /// landscape, paged, two columns per spread, with chrome hidden. The
  /// phone is intended to mirror to a TV while you sit back; use the
  /// brightness slider to dim the phone itself.
  final bool tvMode;

  /// Constrains body text to a comfortable centred column with wide side
  /// margins. Great on big/wide displays (and XR glasses, whose lenses are
  /// sharpest in the centre).
  final bool centeredColumn;

  /// Keeps the screen awake while reading — important when the phone is the
  /// source display for XR glasses or auto-advance is running.
  final bool keepAwake;

  /// When true, page turns and scrolls jump instead of animating — an
  /// in-app Reduce Motion, independent of (and additive to) the OS setting.
  final bool reduceAnimations;

  /// When false, the reader fires no haptic taps on page turns / advances —
  /// a sensory-load control.
  final bool hapticFeedback;

  /// Opt-in reading-session length in minutes (0 = off). A quiet progress
  /// fill tracks toward it; passing it offers a gentle between-chapters
  /// break check-in — never an alarm.
  final int sessionMinutes;

  /// Precise counts instead of approximations: page N of M, percentages
  /// and minutes to one decimal, no "~" — many autistic readers strongly
  /// prefer exact over vague.
  final bool exactNumbers;

  /// Seconds between automatic page turns in paged mode (the paged analogue
  /// of auto-scroll). 0 disables it.
  final int autoPageSeconds;

  /// Which read-aloud engine to use: the on-device iOS voices, or the
  /// self-hosted Kokoro neural voice server.
  final TtsEngineKind ttsEngine;

  /// Base URL of the Kokoro voice server (e.g. `https://host`); empty until
  /// configured. Used only when [ttsEngine] is [TtsEngineKind.kokoro].
  final String ttsServerUrl;

  /// Bearer token for the Kokoro voice server.
  final String ttsServerToken;

  /// Content categories the read-aloud voice skips over (parentheses, URLs,
  /// citations, headings, …).
  final Set<TtsSkip> ttsSkips;

  static const defaults = ReaderSettings(
    mode: ReadingMode.scroll,
    themeId: 'dark',
    fontFamily: '',
    fontSize: 18,
    lineHeight: 1.62,
    letterSpacing: 0,
    wordSpacing: 0,
    paragraphSpacing: 0,
    margin: 20,
    speechRate: 0.5,
    voiceName: '',
    voiceLocale: '',
    boldText: false,
    italicText: false,
    brightness: 1.0,
    textAlign: ReaderTextAlign.left,
    autoScroll: false,
    lineFocus: false,
    focusParagraph: false,
    fixationAnchors: false,
    orientation: ReaderOrientation.auto,
    tvMode: false,
    centeredColumn: false,
    keepAwake: false,
    reduceAnimations: false,
    hapticFeedback: true,
    sessionMinutes: 0,
    exactNumbers: false,
    autoPageSeconds: 0,
    ttsEngine: TtsEngineKind.system,
    ttsServerUrl: '',
    ttsServerToken: '',
    ttsSkips: <TtsSkip>{},
  );

  ReaderThemePreset get theme => readerThemeById(themeId);

  ReaderSettings copyWith({
    ReadingMode? mode,
    String? themeId,
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    double? wordSpacing,
    double? paragraphSpacing,
    double? margin,
    double? speechRate,
    String? voiceName,
    String? voiceLocale,
    bool? boldText,
    bool? italicText,
    double? brightness,
    ReaderTextAlign? textAlign,
    bool? autoScroll,
    bool? lineFocus,
    bool? focusParagraph,
    bool? fixationAnchors,
    ReaderOrientation? orientation,
    bool? tvMode,
    bool? centeredColumn,
    bool? keepAwake,
    bool? reduceAnimations,
    bool? hapticFeedback,
    int? sessionMinutes,
    bool? exactNumbers,
    int? autoPageSeconds,
    TtsEngineKind? ttsEngine,
    String? ttsServerUrl,
    String? ttsServerToken,
    Set<TtsSkip>? ttsSkips,
  }) {
    return ReaderSettings(
      mode: mode ?? this.mode,
      themeId: themeId ?? this.themeId,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      margin: margin ?? this.margin,
      speechRate: speechRate ?? this.speechRate,
      voiceName: voiceName ?? this.voiceName,
      voiceLocale: voiceLocale ?? this.voiceLocale,
      boldText: boldText ?? this.boldText,
      italicText: italicText ?? this.italicText,
      brightness: brightness ?? this.brightness,
      textAlign: textAlign ?? this.textAlign,
      autoScroll: autoScroll ?? this.autoScroll,
      lineFocus: lineFocus ?? this.lineFocus,
      focusParagraph: focusParagraph ?? this.focusParagraph,
      fixationAnchors: fixationAnchors ?? this.fixationAnchors,
      orientation: orientation ?? this.orientation,
      tvMode: tvMode ?? this.tvMode,
      centeredColumn: centeredColumn ?? this.centeredColumn,
      keepAwake: keepAwake ?? this.keepAwake,
      reduceAnimations: reduceAnimations ?? this.reduceAnimations,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      sessionMinutes: sessionMinutes ?? this.sessionMinutes,
      exactNumbers: exactNumbers ?? this.exactNumbers,
      autoPageSeconds: autoPageSeconds ?? this.autoPageSeconds,
      ttsEngine: ttsEngine ?? this.ttsEngine,
      ttsServerUrl: ttsServerUrl ?? this.ttsServerUrl,
      ttsServerToken: ttsServerToken ?? this.ttsServerToken,
      ttsSkips: ttsSkips ?? this.ttsSkips,
    );
  }
}
