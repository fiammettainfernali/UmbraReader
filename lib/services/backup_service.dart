import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import 'bookmark_store.dart';
import 'collection_store.dart';
import 'reading_activity_store.dart';
import 'reading_progress_store.dart';

/// Reads / writes a JSON backup of the app's data. Used for "Backup &
/// restore" — the user's only safety net since Umbra Reader otherwise holds
/// reading progress, bookmarks, collections, settings and feedback in
/// per-device storage that an uninstall would wipe.
///
/// The backup file keeps the original SharedPreferences-shaped format even
/// though several stores now live in SQLite: on export, those stores
/// serialise back into their legacy prefs keys (fresh from the database, so
/// the stale prefs copies left behind by the one-time imports are dropped);
/// on restore, the database is cleared and the stores re-import from the
/// restored keys on next use. Old backup files restore unchanged.
class BackupService {
  static const _formatVersion = 1;

  /// Legacy key families owned by SQLite-backed stores. Their prefs copies
  /// are stale after migration, so exports replace them with fresh
  /// database-derived values and imports hand them back to the stores.
  static const _dbKeyPrefixes = [
    'bookmarks:',
    'reading_chapter:',
    'reading_block:',
    'reading_count:',
    'reading_time:',
    'reading_volume:',
    'reading_end:',
    'tts_resume:',
  ];
  static const _dbKeys = [
    'continue_hidden',
    'collections',
    'collections_modified_at',
    'reading_activity',
  ];

  /// Store migration flags ("data already imported into SQLite") end with
  /// this. They are stripped from exports and cleared on import so a restore
  /// always re-imports the restored keys.
  static const _migratedFlagSuffix = '_in_sqlite_v1';

  static bool _ownedByDatabase(String key) =>
      _dbKeys.contains(key) ||
      key.endsWith(_migratedFlagSuffix) ||
      _dbKeyPrefixes.any(key.startsWith);

  /// Marker key Umbra writes into the JSON so [importFromJson] can validate
  /// the file came from this app.
  static const _signature = 'umbra_reader_backup';

  /// Marker for the smaller annotations-only export: just bookmarks and
  /// highlights, importable on top of an existing install without nuking
  /// anything else.
  static const _annotationSignature = 'umbra_reader_annotations';

  /// SharedPreferences key prefix the BookmarkStore uses — everything starting
  /// with this is a bookmark/highlight entry for some volume.
  static const _annotationKeyPrefix = 'bookmarks:';

  /// Writes a backup JSON file to the app's temp directory and returns the
  /// file path. Caller is expected to hand the file to the system share
  /// sheet so the user can save it wherever (Files, iCloud Drive, AirDrop).
  Future<File> exportToFile() async {
    final json = await exportToJson();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/umbra-reader-backup-$stamp.json');
    await file.writeAsString(json);
    return file;
  }

  /// Builds the backup JSON string from current SharedPreferences contents
  /// plus the SQLite-backed stores (serialised into their legacy prefs
  /// shape).
  Future<String> exportToJson() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (_ownedByDatabase(key)) continue; // stale copy — DB versions win
      data[key] = prefs.get(key);
    }
    data.addAll(await ReadingProgressStore().exportBackupEntries());
    data.addAll(await BookmarkStore().exportBackupEntries());
    data.addAll(await CollectionStore().exportBackupEntries());
    data.addAll(await ReadingActivityStore().exportBackupEntries());
    final envelope = {
      _signature: _formatVersion,
      'timestamp': DateTime.now().toIso8601String(),
      'preferences': data,
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Replaces every SharedPreferences value with the ones in [raw]. Returns
  /// the count of keys restored. Throws [BackupException] when the input
  /// isn't a valid Umbra Reader backup.
  Future<int> importFromJson(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw BackupException('The backup text is empty.');
    }
    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        throw BackupException('That doesn\'t look like an Umbra Reader '
            'backup file.');
      }
      envelope = decoded;
    } on FormatException {
      throw BackupException('Couldn\'t read the JSON — make sure you pasted '
          'the whole backup file.');
    }
    if (!envelope.containsKey(_signature)) {
      throw BackupException('Not an Umbra Reader backup — missing the '
          'expected "$_signature" marker.');
    }
    final prefsData = envelope['preferences'];
    if (prefsData is! Map<String, dynamic>) {
      throw BackupException('Backup is malformed — no "preferences" section.');
    }

    final prefs = await SharedPreferences.getInstance();
    // Wipe first so keys removed by the user don't linger from before.
    for (final existing in prefs.getKeys()) {
      await prefs.remove(existing);
    }
    var restored = 0;
    for (final entry in prefsData.entries) {
      final key = entry.key;
      // Never restore migration flags (backups from older builds may carry
      // them) — the whole point of the restore is to re-import below.
      if (key.endsWith(_migratedFlagSuffix)) continue;
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        // SharedPreferences only stores List<String>.
        await prefs.setStringList(
          key,
          [for (final v in value) v.toString()],
        );
      } else {
        // Unknown type — skip without crashing.
        continue;
      }
      restored++;
    }
    // The restored legacy keys are now the source of truth: clear the
    // database so each store's one-time import runs again from them.
    await AppDatabase.instance.clearStoreData();
    return restored;
  }

  /// Writes a JSON snapshot of only the bookmark / highlight keys to a
  /// temp file. Suitable for sharing as a focused "just my annotations"
  /// archive — separate from (and smaller than) the full backup.
  Future<File> exportAnnotationsToFile() async {
    final json = await exportAnnotationsToJson();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/umbra-reader-annotations-$stamp.json');
    await file.writeAsString(json);
    return file;
  }

  Future<String> exportAnnotationsToJson() async {
    final data = await BookmarkStore().exportBackupEntries();
    final envelope = {
      _annotationSignature: _formatVersion,
      'timestamp': DateTime.now().toIso8601String(),
      'preferences': data,
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Merges annotations from [raw] into SharedPreferences without wiping
  /// anything else (unlike [importFromJson] which replaces the entire
  /// preferences store). Accepts both annotation-only exports and full
  /// backups (in which case only the bookmark keys are pulled out).
  Future<int> importAnnotations(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw BackupException('The annotations text is empty.');
    }
    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        throw BackupException('That doesn\'t look like an Umbra Reader '
            'annotations file.');
      }
      envelope = decoded;
    } on FormatException {
      throw BackupException('Couldn\'t read the JSON — make sure you pasted '
          'the whole file.');
    }
    if (!envelope.containsKey(_annotationSignature) &&
        !envelope.containsKey(_signature)) {
      throw BackupException('Not an Umbra Reader file — missing the expected '
          'marker.');
    }
    final prefsData = envelope['preferences'];
    if (prefsData is! Map<String, dynamic>) {
      throw BackupException('File is malformed — no "preferences" section.');
    }
    // Re-shape into the sync-blob format (values as decoded lists) and let
    // the store's union-by-id merge do the work — nothing local is lost.
    final blob = <String, dynamic>{};
    var volumes = 0;
    for (final entry in prefsData.entries) {
      final key = entry.key;
      if (!key.startsWith(_annotationKeyPrefix)) continue;
      final value = entry.value;
      if (value is! String || value.isEmpty) continue;
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          blob[key] = decoded;
          volumes++;
        }
      } on FormatException {
        continue; // skip a corrupt entry, import the rest
      }
    }
    await BookmarkStore().mergeSyncBlob(jsonEncode(blob));
    return volumes;
  }
}

/// Raised when an import payload is missing, malformed, or not from this app.
class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
