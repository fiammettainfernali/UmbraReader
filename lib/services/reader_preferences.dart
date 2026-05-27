import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_settings.dart';
import '../models/volume.dart';

/// Loads and saves the reader's [ReaderSettings] via [SharedPreferences].
///
/// Settings are stored two ways: a single global set under un-prefixed keys
/// (used by default for every book) and an optional *per-volume override*
/// stored under keys prefixed with the volume's key. When an override exists
/// for a volume, opening it loads those settings instead — handy for the
/// odd book that reads better with, say, a different font or wider margins.
class ReaderPreferences {
  static const _kMode = 'reader_mode';
  static const _kThemeId = 'reader_theme';
  static const _kFontFamily = 'reader_font';
  static const _kFontSize = 'reader_font_size';
  static const _kLineHeight = 'reader_line_height';
  static const _kMargin = 'reader_margin';
  static const _kSpeechRate = 'reader_speech_rate';
  static const _kVoiceName = 'reader_voice_name';
  static const _kVoiceLocale = 'reader_voice_locale';
  static const _kBoldText = 'reader_bold_text';
  static const _kItalicText = 'reader_italic_text';
  static const _kBrightness = 'reader_brightness';
  static const _kTextAlign = 'reader_text_align';
  static const _kAutoScroll = 'reader_auto_scroll';

  /// Marker key telling us a per-volume override has been opted into.
  static const _kOverrideMarker = 'reader_override_marker';

  /// Per-volume keys are global keys prefixed with this + the volume's id
  /// (e.g. `book:42/Lord-of-the-Mysteries-Vol-03.epub/reader_font_size`).
  String _volumePrefix(Volume v) => 'book:${v.seriesOpdsId}/${v.fileName}/';

  Future<ReaderSettings> load({Volume? volume}) async {
    final prefs = await SharedPreferences.getInstance();
    const d = ReaderSettings.defaults;
    final p = volume != null && prefs.getBool(
              '${_volumePrefix(volume)}$_kOverrideMarker',
            ) == true
        ? _volumePrefix(volume)
        : '';
    return ReaderSettings(
      mode: prefs.getString('$p$_kMode') == 'paged'
          ? ReadingMode.paged
          : ReadingMode.scroll,
      themeId: prefs.getString('$p$_kThemeId') ?? d.themeId,
      fontFamily: prefs.getString('$p$_kFontFamily') ?? d.fontFamily,
      fontSize: prefs.getDouble('$p$_kFontSize') ?? d.fontSize,
      lineHeight: prefs.getDouble('$p$_kLineHeight') ?? d.lineHeight,
      margin: prefs.getDouble('$p$_kMargin') ?? d.margin,
      speechRate: prefs.getDouble('$p$_kSpeechRate') ?? d.speechRate,
      voiceName: prefs.getString('$p$_kVoiceName') ?? d.voiceName,
      voiceLocale: prefs.getString('$p$_kVoiceLocale') ?? d.voiceLocale,
      boldText: prefs.getBool('$p$_kBoldText') ?? d.boldText,
      italicText: prefs.getBool('$p$_kItalicText') ?? d.italicText,
      brightness: prefs.getDouble('$p$_kBrightness') ?? d.brightness,
      textAlign: ReaderTextAlign.values.firstWhere(
        (a) => a.name == prefs.getString('$p$_kTextAlign'),
        orElse: () => d.textAlign,
      ),
      autoScroll: prefs.getBool('$p$_kAutoScroll') ?? d.autoScroll,
    );
  }

  Future<void> save(ReaderSettings settings, {Volume? volume}) async {
    final prefs = await SharedPreferences.getInstance();
    final p = volume != null && await hasOverride(volume)
        ? _volumePrefix(volume)
        : '';
    await prefs.setString('$p$_kMode', settings.mode.name);
    await prefs.setString('$p$_kThemeId', settings.themeId);
    await prefs.setString('$p$_kFontFamily', settings.fontFamily);
    await prefs.setDouble('$p$_kFontSize', settings.fontSize);
    await prefs.setDouble('$p$_kLineHeight', settings.lineHeight);
    await prefs.setDouble('$p$_kMargin', settings.margin);
    await prefs.setDouble('$p$_kSpeechRate', settings.speechRate);
    await prefs.setString('$p$_kVoiceName', settings.voiceName);
    await prefs.setString('$p$_kVoiceLocale', settings.voiceLocale);
    await prefs.setBool('$p$_kBoldText', settings.boldText);
    await prefs.setBool('$p$_kItalicText', settings.italicText);
    await prefs.setDouble('$p$_kBrightness', settings.brightness);
    await prefs.setString('$p$_kTextAlign', settings.textAlign.name);
    await prefs.setBool('$p$_kAutoScroll', settings.autoScroll);
  }

  Future<bool> hasOverride(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${_volumePrefix(volume)}$_kOverrideMarker') == true;
  }

  /// Seeds a per-volume override with [settings] and flips the marker on.
  /// Subsequent saves go to this volume's keys until the override is cleared.
  Future<void> enableOverride(Volume volume, ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '${_volumePrefix(volume)}$_kOverrideMarker',
      true,
    );
    await save(settings, volume: volume);
  }

  /// Removes the per-volume override and all of its stored keys, so the
  /// volume falls back to the global settings.
  Future<void> clearOverride(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    final p = _volumePrefix(volume);
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(p)) {
        await prefs.remove(key);
      }
    }
  }
}
