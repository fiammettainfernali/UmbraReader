import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_settings.dart';

/// Loads and saves the reader's [ReaderSettings] via [SharedPreferences].
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

  Future<ReaderSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const d = ReaderSettings.defaults;
    return ReaderSettings(
      mode: prefs.getString(_kMode) == 'paged'
          ? ReadingMode.paged
          : ReadingMode.scroll,
      themeId: prefs.getString(_kThemeId) ?? d.themeId,
      fontFamily: prefs.getString(_kFontFamily) ?? d.fontFamily,
      fontSize: prefs.getDouble(_kFontSize) ?? d.fontSize,
      lineHeight: prefs.getDouble(_kLineHeight) ?? d.lineHeight,
      margin: prefs.getDouble(_kMargin) ?? d.margin,
      speechRate: prefs.getDouble(_kSpeechRate) ?? d.speechRate,
      voiceName: prefs.getString(_kVoiceName) ?? d.voiceName,
      voiceLocale: prefs.getString(_kVoiceLocale) ?? d.voiceLocale,
      boldText: prefs.getBool(_kBoldText) ?? d.boldText,
      italicText: prefs.getBool(_kItalicText) ?? d.italicText,
    );
  }

  Future<void> save(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, settings.mode.name);
    await prefs.setString(_kThemeId, settings.themeId);
    await prefs.setString(_kFontFamily, settings.fontFamily);
    await prefs.setDouble(_kFontSize, settings.fontSize);
    await prefs.setDouble(_kLineHeight, settings.lineHeight);
    await prefs.setDouble(_kMargin, settings.margin);
    await prefs.setDouble(_kSpeechRate, settings.speechRate);
    await prefs.setString(_kVoiceName, settings.voiceName);
    await prefs.setString(_kVoiceLocale, settings.voiceLocale);
    await prefs.setBool(_kBoldText, settings.boldText);
    await prefs.setBool(_kItalicText, settings.italicText);
  }
}
