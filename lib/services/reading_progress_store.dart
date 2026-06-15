import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/volume.dart';
import 'cloud_sync_service.dart';

/// A saved reading position within a volume.
class ReadingProgress {
  const ReadingProgress({
    required this.chapterIndex,
    required this.blockIndex,
    this.chapterCount = 0,
    this.updatedAt,
  });

  final int chapterIndex;

  /// Index of the paragraph/heading block at the top of the view.
  final int blockIndex;

  /// Total chapters in the book — 0 when not recorded (legacy entries).
  final int chapterCount;

  /// When this position was last saved, or null for legacy entries.
  final DateTime? updatedAt;

  /// True once the book has been opened past its very first paragraph.
  bool get isStarted => chapterIndex > 0 || blockIndex > 0;

  /// True when the reader has reached the last chapter.
  bool get isFinished => chapterCount > 0 && chapterIndex >= chapterCount - 1;

  /// Fraction (0..1) of the book read, by chapter — 0 when unknown.
  double get fraction => chapterCount > 1
      ? (chapterIndex / (chapterCount - 1)).clamp(0.0, 1.0)
      : 0;

  static const start = ReadingProgress(chapterIndex: 0, blockIndex: 0);
}

/// A volume paired with its saved reading position.
class ReadingEntry {
  const ReadingEntry({required this.volume, required this.progress});

  final Volume volume;
  final ReadingProgress progress;
}

/// Remembers the reading position per volume.
///
/// Position is stored as a chapter index plus a block (paragraph) index —
/// not a pixel offset or page number — so it stays correct across font,
/// margin, screen-size and reading-mode changes. Alongside the position,
/// each entry records the book's chapter count, the last-read time, and a
/// snapshot of the [Volume] so the home screen can list books in progress.
class ReadingProgressStore {
  static const _chapterPrefix = 'reading_chapter:';
  static const _blockPrefix = 'reading_block:';
  static const _countPrefix = 'reading_count:';
  static const _timePrefix = 'reading_time:';
  static const _volumePrefix = 'reading_volume:';

  /// Volume keys the user has hidden from the Continue Reading shelf. The
  /// saved position is kept; the book just stops surfacing on the home shelf
  /// until it's read again.
  static const _hiddenKey = 'continue_hidden';

  String _key(Volume volume) => '${volume.seriesOpdsId}/${volume.fileName}';

  Future<ReadingProgress> load(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(volume);
    return ReadingProgress(
      chapterIndex: prefs.getInt('$_chapterPrefix$key') ?? 0,
      blockIndex: prefs.getInt('$_blockPrefix$key') ?? 0,
      chapterCount: prefs.getInt('$_countPrefix$key') ?? 0,
      updatedAt: DateTime.tryParse(prefs.getString('$_timePrefix$key') ?? ''),
    );
  }

  Future<void> save(Volume volume, ReadingProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(volume);
    await prefs.setInt('$_chapterPrefix$key', progress.chapterIndex);
    await prefs.setInt('$_blockPrefix$key', progress.blockIndex);
    await prefs.setInt('$_countPrefix$key', progress.chapterCount);
    await prefs.setString('$_timePrefix$key', DateTime.now().toIso8601String());
    await prefs.setString('$_volumePrefix$key', jsonEncode(volume.toJson()));
    // Reading a volume again un-hides it from the Continue shelf.
    final hidden = prefs.getStringList(_hiddenKey);
    if (hidden != null && hidden.remove(key)) {
      await prefs.setStringList(_hiddenKey, hidden);
    }
    CloudSyncService().pushReadingProgressSoon();
  }

  /// Forgets the saved position for [volume] so it reopens from the start.
  Future<void> clear(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(volume);
    await prefs.remove('$_chapterPrefix$key');
    await prefs.remove('$_blockPrefix$key');
    await prefs.remove('$_countPrefix$key');
    await prefs.remove('$_timePrefix$key');
    await prefs.remove('$_volumePrefix$key');
    CloudSyncService().pushReadingProgress();
  }

  /// Volume keys currently hidden from the Continue Reading shelf.
  Future<Set<String>> hiddenFromContinue() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_hiddenKey) ?? const []).toSet();
  }

  /// Hides [volume] from the Continue Reading shelf without forgetting its
  /// saved place. Reopening (and reading) it un-hides it again.
  Future<void> hideFromContinue(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_hiddenKey) ?? const []).toSet()
      ..add(_key(volume));
    await prefs.setStringList(_hiddenKey, set.toList());
  }

  /// Every volume with a saved position, newest first. Legacy entries saved
  /// before volume snapshots were recorded are skipped — they can't be
  /// reopened without the volume metadata.
  Future<List<ReadingEntry>> allEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <ReadingEntry>[];
    for (final fullKey in prefs.getKeys()) {
      if (!fullKey.startsWith(_chapterPrefix)) continue;
      final key = fullKey.substring(_chapterPrefix.length);
      final volumeJson = prefs.getString('$_volumePrefix$key');
      if (volumeJson == null) continue;
      final Volume volume;
      try {
        final decoded = jsonDecode(volumeJson);
        if (decoded is! Map<String, dynamic>) continue;
        volume = Volume.fromJson(decoded);
      } on FormatException {
        continue;
      }
      entries.add(
        ReadingEntry(
          volume: volume,
          progress: ReadingProgress(
            chapterIndex: prefs.getInt('$_chapterPrefix$key') ?? 0,
            blockIndex: prefs.getInt('$_blockPrefix$key') ?? 0,
            chapterCount: prefs.getInt('$_countPrefix$key') ?? 0,
            updatedAt: DateTime.tryParse(
              prefs.getString('$_timePrefix$key') ?? '',
            ),
          ),
        ),
      );
    }
    entries.sort((a, b) {
      final at = a.progress.updatedAt;
      final bt = b.progress.updatedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return entries;
  }

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  /// Serialises every saved position to a JSON blob for the cloud, keyed by
  /// the same `seriesId/fileName` used locally, carrying each entry's
  /// `updatedAt` so the other device can resolve conflicts by recency.
  Future<String> exportSyncBlob() async {
    final entries = await allEntries();
    final map = <String, dynamic>{
      for (final e in entries)
        _key(e.volume): {
          'chapterIndex': e.progress.chapterIndex,
          'blockIndex': e.progress.blockIndex,
          'chapterCount': e.progress.chapterCount,
          'updatedAt': e.progress.updatedAt?.toIso8601String(),
          'volume': e.volume.toJson(),
        },
    };
    return jsonEncode(map);
  }

  /// Merges a cloud blob into local storage, last-write-wins per volume by
  /// `updatedAt`. Returns true if any local entry was created or updated.
  /// Writes raw keys directly (not via [save]) so the merged entry keeps the
  /// cloud timestamp instead of stamping "now".
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    final prefs = await SharedPreferences.getInstance();
    var changed = false;
    for (final entry in decoded.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! Map) continue;
      final cloudUpdated = DateTime.tryParse(value['updatedAt'] as String? ?? '');
      if (cloudUpdated == null) continue;
      final localUpdated = DateTime.tryParse(
        prefs.getString('$_timePrefix$key') ?? '',
      );
      if (localUpdated != null && !cloudUpdated.isAfter(localUpdated)) continue;
      final volume = value['volume'];
      if (volume is! Map) continue;
      await prefs.setInt(
        '$_chapterPrefix$key',
        (value['chapterIndex'] as num?)?.toInt() ?? 0,
      );
      await prefs.setInt(
        '$_blockPrefix$key',
        (value['blockIndex'] as num?)?.toInt() ?? 0,
      );
      await prefs.setInt(
        '$_countPrefix$key',
        (value['chapterCount'] as num?)?.toInt() ?? 0,
      );
      await prefs.setString('$_timePrefix$key', cloudUpdated.toIso8601String());
      await prefs.setString('$_volumePrefix$key', jsonEncode(volume));
      changed = true;
    }
    return changed;
  }
}
