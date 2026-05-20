import 'package:shared_preferences/shared_preferences.dart';

import '../models/volume.dart';

/// A saved reading position within a volume.
class ReadingProgress {
  const ReadingProgress({required this.chapterIndex, required this.blockIndex});

  final int chapterIndex;

  /// Index of the paragraph/heading block at the top of the view.
  final int blockIndex;

  static const start = ReadingProgress(chapterIndex: 0, blockIndex: 0);
}

/// Remembers the reading position per volume.
///
/// Position is stored as a chapter index plus a block (paragraph) index —
/// not a pixel offset or page number — so it stays correct across font,
/// margin, screen-size and reading-mode changes.
class ReadingProgressStore {
  static const _chapterPrefix = 'reading_chapter:';
  static const _blockPrefix = 'reading_block:';

  String _key(Volume volume) => '${volume.seriesOpdsId}/${volume.fileName}';

  Future<ReadingProgress> load(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(volume);
    return ReadingProgress(
      chapterIndex: prefs.getInt('$_chapterPrefix$key') ?? 0,
      blockIndex: prefs.getInt('$_blockPrefix$key') ?? 0,
    );
  }

  Future<void> save(Volume volume, ReadingProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(volume);
    await prefs.setInt('$_chapterPrefix$key', progress.chapterIndex);
    await prefs.setInt('$_blockPrefix$key', progress.blockIndex);
  }
}
