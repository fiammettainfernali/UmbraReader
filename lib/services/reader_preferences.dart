import 'package:shared_preferences/shared_preferences.dart';

/// How chapter content is laid out in the reader.
enum ReadingMode {
  /// Continuous vertical scrolling.
  scroll,

  /// Discrete pages, turned horizontally.
  paged,
}

/// Persists reader preferences. Currently just the reading mode; Phase 4's
/// theme engine will extend this with font, size, spacing and colours.
class ReaderPreferences {
  static const _kMode = 'reader_mode';

  Future<ReadingMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMode) == 'paged'
        ? ReadingMode.paged
        : ReadingMode.scroll;
  }

  Future<void> saveMode(ReadingMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, mode.name);
  }
}
