import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads / writes a JSON snapshot of every value in SharedPreferences. Used
/// for "Backup & restore" — the user's only safety net since Umbra Reader
/// otherwise holds reading progress, bookmarks, collections, settings and
/// feedback in per-device storage that an uninstall would wipe.
class BackupService {
  static const _formatVersion = 1;

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

  /// Builds the backup JSON string from current SharedPreferences contents.
  Future<String> exportToJson() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      data[key] = prefs.get(key);
    }
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
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_annotationKeyPrefix)) {
        data[key] = prefs.get(key);
      }
    }
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
    final prefs = await SharedPreferences.getInstance();
    var restored = 0;
    for (final entry in prefsData.entries) {
      final key = entry.key;
      if (!key.startsWith(_annotationKeyPrefix)) continue;
      final value = entry.value;
      if (value is String) {
        await prefs.setString(key, value);
        restored++;
      }
    }
    return restored;
  }
}

/// Raised when an import payload is missing, malformed, or not from this app.
class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
