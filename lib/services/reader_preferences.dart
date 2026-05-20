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
  }
}
