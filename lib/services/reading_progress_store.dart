import 'package:shared_preferences/shared_preferences.dart';

import '../models/volume.dart';

/// Remembers which chapter the reader last had open, per volume.
///
/// This is intentionally lightweight (chapter index only). Finer-grained
/// position (scroll offset within a chapter) and library-wide reading stats
/// can move to a proper database in a later step.
class ReadingProgressStore {
  static const _prefix = 'reading_chapter:';

  String _key(Volume volume) =>
      '$_prefix${volume.seriesOpdsId}/${volume.fileName}';

  /// The last-read chapter index for [volume], or 0 if never opened.
  Future<int> chapterIndexFor(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key(volume)) ?? 0;
  }

  Future<void> saveChapterIndex(Volume volume, int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(volume), index);
  }
}
