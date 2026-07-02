import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/bookmark.dart';
import '../models/volume.dart';
import 'cloud_sync_service.dart';

/// Persists user bookmarks per volume, in SQLite ([AppDatabase]) — one row
/// per bookmark, keyed (volumeKey, bookmarkId).
///
/// Bookmarks saved before the SQLite move (one JSON list per volume under
/// `bookmarks:<key>` SharedPreferences keys) are imported once on first use;
/// the old keys are left behind untouched as a safety net. That legacy shape
/// is still the interchange format for iCloud sync blobs and backups.
class BookmarkStore {
  /// Legacy SharedPreferences key prefix — import, sync and backup format.
  static const _prefix = 'bookmarks:';

  /// Set once the legacy prefs data has been imported into SQLite.
  static const _kMigrated = 'bookmarks_in_sqlite_v1';

  static Future<void>? _migration;

  AppDatabase get _db => AppDatabase.instance;
  $BookmarkRowsTable get _table => _db.bookmarkRows;

  String _volumeKey(Volume volume) =>
      '${volume.seriesOpdsId}/${volume.fileName}';

  Bookmark _fromRow(BookmarkRow row) => Bookmark(
    id: row.bookmarkId,
    chapterIndex: row.chapterIndex,
    blockIndex: row.blockIndex,
    chapterTitle: row.chapterTitle,
    snippet: row.snippet,
    createdAt:
        DateTime.tryParse(row.createdAt) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    isHighlight: row.isHighlight,
    note: row.note,
    color: HighlightColor.fromName(row.color),
  );

  BookmarkRowsCompanion _toRow(String volumeKey, Bookmark b) =>
      BookmarkRowsCompanion(
        volumeKey: Value(volumeKey),
        bookmarkId: Value(b.id),
        chapterIndex: Value(b.chapterIndex),
        blockIndex: Value(b.blockIndex),
        chapterTitle: Value(b.chapterTitle),
        snippet: Value(b.snippet),
        createdAt: Value(b.createdAt.toIso8601String()),
        isHighlight: Value(b.isHighlight),
        note: Value(b.note),
        color: Value(b.color.name),
      );

  /// Bookmarks for [volume], newest-first.
  Future<List<Bookmark>> list(Volume volume) async {
    await _ensureMigrated();
    final rows = await (_db.select(
      _table,
    )..where((t) => t.volumeKey.equals(_volumeKey(volume)))).get();
    final marks = rows.map(_fromRow).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return marks;
  }

  /// Adds [bookmark] to [volume] (idempotent on id — re-adding replaces).
  Future<void> add(Volume volume, Bookmark bookmark) async {
    await _ensureMigrated();
    await _db
        .into(_table)
        .insertOnConflictUpdate(_toRow(_volumeKey(volume), bookmark));
    CloudSyncService().pushBookmarks();
  }

  /// Removes the bookmark with [id] from [volume]'s list.
  Future<void> remove(Volume volume, String id) async {
    await _ensureMigrated();
    await (_db.delete(_table)..where(
          (t) =>
              t.volumeKey.equals(_volumeKey(volume)) & t.bookmarkId.equals(id),
        ))
        .go();
    CloudSyncService().pushBookmarks();
  }

  /// Drops every bookmark for [volume] — useful when reading progress is
  /// reset on the same volume.
  Future<void> clear(Volume volume) async {
    await _ensureMigrated();
    await (_db.delete(
      _table,
    )..where((t) => t.volumeKey.equals(_volumeKey(volume)))).go();
  }

  // ── one-time import from SharedPreferences ──────────────────────────────

  Future<void> _ensureMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrated) ?? false) return;
    _migration ??= _importFromPrefs(prefs).whenComplete(() => _migration = null);
    await _migration;
  }

  /// Copies every legacy `bookmarks:` prefs list into SQLite (insertOrIgnore
  /// so rows SQLite already has win). The prefs keys stay behind untouched.
  Future<void> _importFromPrefs(SharedPreferences prefs) async {
    final rows = <BookmarkRowsCompanion>[];
    for (final fullKey in prefs.getKeys()) {
      if (!fullKey.startsWith(_prefix)) continue;
      final volumeKey = fullKey.substring(_prefix.length);
      final raw = prefs.getString(fullKey);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        for (final entry in decoded) {
          if (entry is Map<String, dynamic>) {
            final mark = Bookmark.fromJson(entry);
            if (mark.id.isEmpty) continue;
            rows.add(_toRow(volumeKey, mark));
          }
        }
      } on FormatException {
        continue; // skip a corrupt entry, keep importing the rest
      }
    }
    await _db.batch(
      (b) => b.insertAll(_table, rows, mode: InsertMode.insertOrIgnore),
    );
    await prefs.setBool(_kMigrated, true);
  }

  // ── iCloud sync + backup (legacy prefs shape as interchange) ────────────

  /// All bookmarks across every volume as one JSON blob, keyed by the same
  /// `bookmarks:<seriesId>/<fileName>` keys the prefs era used.
  Future<String> exportSyncBlob() async {
    await _ensureMigrated();
    final rows = await _db.select(_table).get();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      grouped
          .putIfAbsent('$_prefix${row.volumeKey}', () => [])
          .add(_fromRow(row).toJson());
    }
    return jsonEncode(grouped);
  }

  /// Backup entries in the legacy prefs shape: one JSON-encoded list per
  /// `bookmarks:<key>`. Restoring writes these back to prefs, and the
  /// one-time import picks them up again.
  Future<Map<String, Object>> exportBackupEntries() async {
    await _ensureMigrated();
    final rows = await _db.select(_table).get();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      grouped
          .putIfAbsent('$_prefix${row.volumeKey}', () => [])
          .add(_fromRow(row).toJson());
    }
    return {
      for (final entry in grouped.entries) entry.key: jsonEncode(entry.value),
    };
  }

  /// Union-by-id merge: every bookmark id present on either device is kept.
  /// Returns true if any volume gained entries. (Deletions are not
  /// propagated — this never loses a highlight, at the cost of a deleted one
  /// possibly reappearing from the other device.)
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
      final cloudList = entry.value;
      if (key is! String || !key.startsWith(_prefix) || cloudList is! List) {
        continue;
      }
      final volumeKey = key.substring(_prefix.length);
      final existing = (await (_db.select(
        _table,
      )..where((t) => t.volumeKey.equals(volumeKey))).get())
          .map((r) => r.bookmarkId)
          .toSet();
      for (final m in cloudList) {
        if (m is! Map<String, dynamic> || m['id'] is! String) continue;
        final mark = Bookmark.fromJson(m);
        if (mark.id.isEmpty || existing.contains(mark.id)) continue;
        await _db
            .into(_table)
            .insert(
              _toRow(volumeKey, mark),
              mode: InsertMode.insertOrIgnore,
            );
        changed = true;
      }
    }
    return changed;
  }
}
