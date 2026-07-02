import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/collection.dart';
import 'cloud_sync_service.dart';

/// Persists user-defined library shelves ("Favourites", "Save for later",
/// etc.) in SQLite ([AppDatabase]) — one row per collection.
///
/// Collections saved before the SQLite move (a single JSON list under the
/// `collections` SharedPreferences key) are imported once on first use; the
/// old keys stay behind untouched. The legacy shape remains the interchange
/// format for iCloud sync blobs and backups, and merging stays whole-set
/// last-write-wins driven by the modified timestamp.
class CollectionStore {
  /// Legacy SharedPreferences keys — import, sync and backup format.
  static const _key = 'collections';
  static const _modifiedKey = 'collections_modified_at';

  /// Set once the legacy prefs data has been imported into SQLite.
  static const _kMigrated = 'collections_in_sqlite_v1';

  static Future<void>? _migration;
  static final _rng = Random();

  AppDatabase get _db => AppDatabase.instance;
  $CollectionRowsTable get _table => _db.collectionRows;

  Collection _fromRow(CollectionRow row) {
    List<int> ids = const [];
    try {
      final decoded = jsonDecode(row.seriesIdsJson);
      if (decoded is List) {
        ids = decoded.whereType<num>().map((n) => n.toInt()).toList();
      }
    } on FormatException {
      // corrupt membership list — treat as empty rather than crash
    }
    return Collection(
      id: row.id,
      name: row.name,
      seriesIds: ids,
      createdAt:
          DateTime.tryParse(row.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  CollectionRowsCompanion _toRow(Collection c) => CollectionRowsCompanion(
    id: Value(c.id),
    name: Value(c.name),
    seriesIdsJson: Value(jsonEncode(c.seriesIds)),
    createdAt: Value(c.createdAt.toIso8601String()),
  );

  /// All collections, ordered by creation time (oldest first).
  Future<List<Collection>> list() async {
    await _ensureMigrated();
    final rows = await _db.select(_table).get();
    final out = rows.map(_fromRow).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  /// Creates a new collection with [name] and returns it.
  Future<Collection> create(String name) async {
    await _ensureMigrated();
    final clean = name.trim();
    // Microseconds + a random suffix so two creates fired within the same
    // clock tick still get distinct ids.
    final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
        '-${_rng.nextInt(1 << 32).toRadixString(16)}';
    final mark = Collection(
      id: id,
      name: clean.isEmpty ? 'Untitled' : clean,
      seriesIds: const [],
      createdAt: DateTime.now(),
    );
    await _db.into(_table).insert(_toRow(mark));
    await _touch();
    return mark;
  }

  Future<void> rename(String id, String name) async {
    await _ensureMigrated();
    final clean = name.trim();
    if (clean.isEmpty) return;
    await (_db.update(_table)..where((t) => t.id.equals(id))).write(
      CollectionRowsCompanion(name: Value(clean)),
    );
    await _touch();
  }

  Future<void> delete(String id) async {
    await _ensureMigrated();
    await (_db.delete(_table)..where((t) => t.id.equals(id))).go();
    await _touch();
  }

  /// Toggles [seriesId] in/out of [collectionId].
  Future<void> setMembership(
    String collectionId,
    int seriesId, {
    required bool member,
  }) async {
    await _ensureMigrated();
    final row = await (_db.select(
      _table,
    )..where((t) => t.id.equals(collectionId))).getSingleOrNull();
    if (row == null) return;
    final c = _fromRow(row);
    final ids = [...c.seriesIds];
    final has = ids.contains(seriesId);
    if (member && !has) ids.add(seriesId);
    if (!member && has) ids.removeWhere((id) => id == seriesId);
    await (_db.update(_table)..where((t) => t.id.equals(collectionId))).write(
      CollectionRowsCompanion(seriesIdsJson: Value(jsonEncode(ids))),
    );
    await _touch();
  }

  /// Set of collection ids that already contain [seriesId].
  Future<Set<String>> collectionsContaining(int seriesId) async {
    final all = await list();
    return {
      for (final c in all)
        if (c.seriesIds.contains(seriesId)) c.id,
    };
  }

  /// Stamps the whole-set modified time (drives last-write-wins sync) and
  /// pushes to iCloud.
  Future<void> _touch() async {
    await _db.kvSet(_modifiedKey, DateTime.now().toIso8601String());
    CloudSyncService().pushCollections();
  }

  // ── one-time import from SharedPreferences ──────────────────────────────

  Future<void> _ensureMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrated) ?? false) return;
    _migration ??= _importFromPrefs(prefs).whenComplete(() => _migration = null);
    await _migration;
  }

  Future<void> _importFromPrefs(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final rows = [
            for (final entry in decoded)
              if (entry is Map<String, dynamic>)
                _toRow(Collection.fromJson(entry)),
          ];
          await _db.batch(
            (b) => b.insertAll(_table, rows, mode: InsertMode.insertOrIgnore),
          );
        }
      } on FormatException {
        // corrupt legacy list — nothing to import
      }
    }
    final modified = prefs.getString(_modifiedKey);
    if (modified != null && await _db.kvGet(_modifiedKey) == null) {
      await _db.kvSet(_modifiedKey, modified);
    }
    await prefs.setBool(_kMigrated, true);
  }

  // ── iCloud sync + backup (legacy prefs shape as interchange) ────────────

  /// Serialises the whole collection set plus its last-modified time for the
  /// cloud. Merging is whole-set last-write-wins, so the timestamp travels
  /// with the data.
  Future<String> exportSyncBlob() async {
    final all = await list();
    return jsonEncode({
      'modifiedAt': await _db.kvGet(_modifiedKey) ?? '',
      'collections': [for (final c in all) c.toJson()],
    });
  }

  /// Backup entries in the legacy prefs shape (`collections` JSON list plus
  /// the modified timestamp). Empty on a store that was never touched, so
  /// untouched installs don't pad the backup.
  Future<Map<String, Object>> exportBackupEntries() async {
    final all = await list();
    final modified = await _db.kvGet(_modifiedKey);
    if (all.isEmpty && modified == null) return const {};
    return {
      _key: jsonEncode([for (final c in all) c.toJson()]),
      _modifiedKey: ?modified,
    };
  }

  /// Replaces the local collection set with the cloud copy when the cloud's
  /// modified time is newer. Returns true if local data changed.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    final cloudModified = DateTime.tryParse(
      decoded['modifiedAt'] as String? ?? '',
    );
    if (cloudModified == null) return false;
    await _ensureMigrated();
    final localModified = DateTime.tryParse(
      await _db.kvGet(_modifiedKey) ?? '',
    );
    if (localModified != null && !cloudModified.isAfter(localModified)) {
      return false;
    }
    final collections = decoded['collections'];
    if (collections is! List) return false;
    await _db.batch((b) {
      b.deleteAll(_table);
      b.insertAll(_table, [
        for (final entry in collections)
          if (entry is Map<String, dynamic>) _toRow(Collection.fromJson(entry)),
      ]);
    });
    await _db.kvSet(_modifiedKey, cloudModified.toIso8601String());
    return true;
  }
}
