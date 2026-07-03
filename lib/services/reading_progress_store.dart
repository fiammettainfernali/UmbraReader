import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/volume.dart';
import 'cloud_sync_service.dart';

/// A saved reading position within a volume.
class ReadingProgress {
  const ReadingProgress({
    required this.chapterIndex,
    required this.blockIndex,
    this.chapterCount = 0,
    this.updatedAt,
    this.endReached = false,
  });

  final int chapterIndex;

  /// Index of the paragraph/heading block at the top of the view.
  final int blockIndex;

  /// Total chapters in the book — 0 when not recorded (legacy entries).
  final int chapterCount;

  /// When this position was last saved, or null for legacy entries.
  final DateTime? updatedAt;

  /// True once the reader has actually reached the end of the final chapter —
  /// the real "finished" signal. Being *on* the last chapter isn't enough,
  /// since you can stop mid-way through it.
  final bool endReached;

  /// True once the book has been opened past its very first paragraph.
  bool get isStarted => chapterIndex > 0 || blockIndex > 0;

  /// True only when the reader has read through to the end of the last
  /// chapter. (Just being on the last chapter no longer counts — that
  /// dropped mid-final-chapter books off the Continue Reading shelf.)
  bool get isFinished => endReached;

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

/// Remembers the reading position per volume, in SQLite ([AppDatabase]).
///
/// Position is stored as a chapter index plus a block (paragraph) index —
/// not a pixel offset or page number — so it stays correct across font,
/// margin, screen-size and reading-mode changes. Alongside the position,
/// each row records the book's chapter count, the last-read time, a snapshot
/// of the [Volume] for the home shelves, the Continue-shelf hidden flag and
/// the read-aloud resume point.
///
/// Data saved before the SQLite move (loose SharedPreferences keys) is
/// imported once on first use; the import is non-destructive — the old prefs
/// keys are left in place as a safety net.
class ReadingProgressStore {
  // ── legacy SharedPreferences keys (one-time import only) ────────────────
  static const _chapterPrefix = 'reading_chapter:';
  static const _blockPrefix = 'reading_block:';
  static const _countPrefix = 'reading_count:';
  static const _timePrefix = 'reading_time:';
  static const _volumePrefix = 'reading_volume:';
  static const _endPrefix = 'reading_end:';
  static const _resumePrefix = 'tts_resume:';
  static const _hiddenKey = 'continue_hidden';

  /// Set once the legacy prefs data has been imported into SQLite.
  static const _kMigrated = 'reading_progress_in_sqlite_v1';

  /// In-flight import, so concurrent first calls import exactly once.
  static Future<void>? _migration;

  AppDatabase get _db => AppDatabase.instance;
  $ReadingProgressRowsTable get _table => _db.readingProgressRows;

  String _key(Volume volume) => '${volume.seriesOpdsId}/${volume.fileName}';

  ReadingProgress _fromRow(ReadingProgressRow row) => ReadingProgress(
    chapterIndex: row.chapterIndex,
    blockIndex: row.blockIndex,
    chapterCount: row.chapterCount,
    updatedAt: DateTime.tryParse(row.updatedAt ?? ''),
    endReached: row.endReached,
  );

  Future<ReadingProgressRow?> _row(String key) => (_db.select(
    _table,
  )..where((t) => t.volumeKey.equals(key))).getSingleOrNull();

  Future<ReadingProgress> load(Volume volume) async {
    await _ensureMigrated();
    final row = await _row(_key(volume));
    return row == null ? ReadingProgress.start : _fromRow(row);
  }

  /// Saves the reading position. By default an actual read un-hides the volume
  /// from the Continue shelf; pass [unhide] = false for background writes (e.g.
  /// refreshing the chapter count after a re-download) so a volume the user
  /// removed from the shelf stays hidden even when it gains chapters.
  Future<void> save(
    Volume volume,
    ReadingProgress progress, {
    bool unhide = true,
  }) async {
    await _ensureMigrated();
    // Finishing is sticky per edition: once a book has been read to the
    // end, re-opening it or scrolling around must not flip it back to
    // in-progress. Only a chapter-count change (new chapters compiled in)
    // resets the flag — at which point there genuinely is more to read.
    var endReached = progress.endReached;
    if (!endReached) {
      final existing = await _row(_key(volume));
      if (existing != null &&
          existing.endReached &&
          existing.chapterCount == progress.chapterCount) {
        endReached = true;
      }
    }
    // hidden is absent on background writes (and on the update arm) so the
    // shelf state survives; ttsResume is always absent so a position save
    // never wipes the read-aloud resume point.
    final companion = ReadingProgressRowsCompanion(
      volumeKey: Value(_key(volume)),
      chapterIndex: Value(progress.chapterIndex),
      blockIndex: Value(progress.blockIndex),
      chapterCount: Value(progress.chapterCount),
      updatedAt: Value(DateTime.now().toIso8601String()),
      endReached: Value(endReached),
      volumeJson: Value(jsonEncode(volume.toJson())),
      hidden: unhide ? const Value(false) : const Value.absent(),
    );
    await _db
        .into(_table)
        .insert(companion, onConflict: DoUpdate((_) => companion));
    CloudSyncService().pushReadingProgressSoon();
  }

  /// Marks [volume] as read to the end without touching the position —
  /// the user-facing "Mark as finished" on the Continue shelf.
  Future<void> markFinished(Volume volume) async {
    final current = await load(volume);
    await save(
      volume,
      ReadingProgress(
        chapterIndex: current.chapterIndex,
        blockIndex: current.blockIndex,
        chapterCount: current.chapterCount,
        updatedAt: current.updatedAt,
        endReached: true,
      ),
    );
  }

  /// Forgets the saved position for [volume] so it reopens from the start.
  Future<void> clear(Volume volume) async {
    await _ensureMigrated();
    await (_db.delete(
      _table,
    )..where((t) => t.volumeKey.equals(_key(volume)))).go();
    CloudSyncService().pushReadingProgress();
  }

  /// Volume keys currently hidden from the Continue Reading shelf.
  Future<Set<String>> hiddenFromContinue() async {
    await _ensureMigrated();
    final rows = await (_db.select(
      _table,
    )..where((t) => t.hidden.equals(true))).get();
    return rows.map((r) => r.volumeKey).toSet();
  }

  /// Hides [volume] from the Continue Reading shelf without forgetting its
  /// saved place. Reopening (and reading) it un-hides it again.
  Future<void> hideFromContinue(Volume volume) async {
    await _ensureMigrated();
    await _db
        .into(_table)
        .insert(
          ReadingProgressRowsCompanion(
            volumeKey: Value(_key(volume)),
            hidden: const Value(true),
          ),
          onConflict: DoUpdate(
            (_) => const ReadingProgressRowsCompanion(hidden: Value(true)),
          ),
        );
  }

  /// Records the word-level resume point ([blockIndex], [charOffset]) reached
  /// while reading [volume] aloud.
  Future<void> saveResumeOffset(
    Volume volume,
    int blockIndex,
    int charOffset,
  ) async {
    await _ensureMigrated();
    final resume = Value<String?>('$blockIndex:$charOffset');
    await _db
        .into(_table)
        .insert(
          ReadingProgressRowsCompanion(
            volumeKey: Value(_key(volume)),
            ttsResume: resume,
          ),
          onConflict: DoUpdate(
            (_) => ReadingProgressRowsCompanion(ttsResume: resume),
          ),
        );
  }

  /// The saved (blockIndex, charOffset) resume point for [volume], or null.
  Future<(int, int)?> resumeOffset(Volume volume) async {
    await _ensureMigrated();
    final raw = (await _row(_key(volume)))?.ttsResume;
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final block = int.tryParse(parts[0]);
    final offset = int.tryParse(parts[1]);
    if (block == null || offset == null) return null;
    return (block, offset);
  }

  /// Every volume with a saved position, newest first. Rows without a volume
  /// snapshot are skipped — they can't be reopened without the metadata.
  Future<List<ReadingEntry>> allEntries() async {
    await _ensureMigrated();
    final rows = await (_db.select(
      _table,
    )..where((t) => t.volumeJson.isNotNull())).get();
    final entries = <ReadingEntry>[];
    for (final row in rows) {
      final Volume volume;
      try {
        final decoded = jsonDecode(row.volumeJson!);
        if (decoded is! Map<String, dynamic>) continue;
        volume = Volume.fromJson(decoded);
      } on FormatException {
        continue;
      }
      entries.add(ReadingEntry(volume: volume, progress: _fromRow(row)));
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

  // ── one-time import from SharedPreferences ──────────────────────────────

  Future<void> _ensureMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrated) ?? false) return;
    _migration ??= _importFromPrefs(prefs).whenComplete(() => _migration = null);
    await _migration;
  }

  /// Reads the stored end-reached flag from the legacy keys, falling back
  /// for entries saved before the flag existed to "on the last chapter" so
  /// books finished under the old scheme stay finished.
  bool _legacyEndReached(SharedPreferences prefs, String key) {
    final stored = prefs.getBool('$_endPrefix$key');
    if (stored != null) return stored;
    final chapter = prefs.getInt('$_chapterPrefix$key') ?? 0;
    final count = prefs.getInt('$_countPrefix$key') ?? 0;
    return count > 0 && chapter >= count - 1;
  }

  /// Copies every legacy prefs entry into SQLite. insertOrIgnore keeps any
  /// row SQLite already has (it can only be newer), and the prefs keys are
  /// deliberately left behind untouched as a rollback safety net.
  Future<void> _importFromPrefs(SharedPreferences prefs) async {
    final hidden = (prefs.getStringList(_hiddenKey) ?? const []).toSet();
    final keys = <String>{...hidden};
    for (final full in prefs.getKeys()) {
      if (full.startsWith(_chapterPrefix)) {
        keys.add(full.substring(_chapterPrefix.length));
      } else if (full.startsWith(_resumePrefix)) {
        keys.add(full.substring(_resumePrefix.length));
      }
    }
    final rows = [
      for (final key in keys)
        ReadingProgressRowsCompanion.insert(
          volumeKey: key,
          chapterIndex: Value(prefs.getInt('$_chapterPrefix$key') ?? 0),
          blockIndex: Value(prefs.getInt('$_blockPrefix$key') ?? 0),
          chapterCount: Value(prefs.getInt('$_countPrefix$key') ?? 0),
          updatedAt: Value(prefs.getString('$_timePrefix$key')),
          endReached: Value(_legacyEndReached(prefs, key)),
          volumeJson: Value(prefs.getString('$_volumePrefix$key')),
          hidden: Value(hidden.contains(key)),
          ttsResume: Value(prefs.getString('$_resumePrefix$key')),
        ),
    ];
    await _db.batch(
      (b) => b.insertAll(_table, rows, mode: InsertMode.insertOrIgnore),
    );
    await prefs.setBool(_kMigrated, true);
  }

  /// Backup entries in the legacy prefs shape — the same per-volume
  /// `reading_*:` keys, hidden list and resume keys the prefs era wrote, so
  /// old and new backup files are interchangeable and restore re-imports.
  Future<Map<String, Object>> exportBackupEntries() async {
    await _ensureMigrated();
    final rows = await _db.select(_table).get();
    final out = <String, Object>{};
    final hidden = <String>[];
    for (final row in rows) {
      final key = row.volumeKey;
      out['$_chapterPrefix$key'] = row.chapterIndex;
      out['$_blockPrefix$key'] = row.blockIndex;
      out['$_countPrefix$key'] = row.chapterCount;
      out['$_endPrefix$key'] = row.endReached;
      if (row.updatedAt != null) out['$_timePrefix$key'] = row.updatedAt!;
      if (row.volumeJson != null) out['$_volumePrefix$key'] = row.volumeJson!;
      if (row.ttsResume != null) out['$_resumePrefix$key'] = row.ttsResume!;
      if (row.hidden) hidden.add(key);
    }
    if (hidden.isNotEmpty) out[_hiddenKey] = hidden;
    return out;
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
          'endReached': e.progress.endReached,
          'volume': e.volume.toJson(),
        },
    };
    return jsonEncode(map);
  }

  /// Merges a cloud blob into local storage, last-write-wins per volume by
  /// `updatedAt`. Returns true if any local entry was created or updated.
  /// Only the progress columns are written, so the local hidden flag and
  /// read-aloud resume point survive a merge.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    await _ensureMigrated();
    var changed = false;
    for (final entry in decoded.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! Map) continue;
      final cloudUpdated = DateTime.tryParse(
        value['updatedAt'] as String? ?? '',
      );
      if (cloudUpdated == null) continue;
      final volume = value['volume'];
      if (volume is! Map) continue;
      final local = await _row(key);
      final localUpdated = DateTime.tryParse(local?.updatedAt ?? '');
      if (localUpdated != null && !cloudUpdated.isAfter(localUpdated)) {
        continue;
      }
      final companion = ReadingProgressRowsCompanion(
        volumeKey: Value(key),
        chapterIndex: Value((value['chapterIndex'] as num?)?.toInt() ?? 0),
        blockIndex: Value((value['blockIndex'] as num?)?.toInt() ?? 0),
        chapterCount: Value((value['chapterCount'] as num?)?.toInt() ?? 0),
        updatedAt: Value(cloudUpdated.toIso8601String()),
        endReached: Value(value['endReached'] == true),
        volumeJson: Value(jsonEncode(volume)),
      );
      await _db
          .into(_table)
          .insert(companion, onConflict: DoUpdate((_) => companion));
      changed = true;
    }
    return changed;
  }
}
