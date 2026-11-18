import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../models/download_record.dart';
import '../models/volume.dart';

/// Owns the on-device file layout for downloaded books.
///
/// Layout: `<app documents>/library/<seriesOpdsId>/<fileName>.epub` — series
/// are foldered automatically, so the user never creates folders by hand.
class LibraryStorage {
  Directory? _root;

  Future<Directory> _libraryRoot() async {
    final cached = _root;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/library');
    await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  /// Absolute path where a volume's EPUB is (or would be) stored.
  Future<String> epubPath(Volume volume) async {
    final root = await _libraryRoot();
    return '${root.path}/${volume.seriesOpdsId}/${volume.fileName}';
  }

  Future<File> epubFile(Volume volume) async => File(await epubPath(volume));

  /// Path of the JSON manifest that records downloaded volumes.
  Future<String> manifestPath() async {
    final root = await _libraryRoot();
    return '${root.path}/downloads.json';
  }

  /// Path of the JSON cache of library metadata (for offline browsing).
  Future<String> cachePath() async {
    final root = await _libraryRoot();
    return '${root.path}/library_cache.json';
  }

  /// Absolute path of the cached cover image for a series.
  Future<String> coverPath(int seriesId) async {
    final root = await _libraryRoot();
    return '${root.path}/covers/$seriesId';
  }

  /// Deletes a volume's EPUB, and its series folder if that leaves it empty.
  Future<void> deleteEpub(Volume volume) async {
    final file = await epubFile(volume);
    if (file.existsSync()) await file.delete();
    final parent = file.parent;
    if (parent.existsSync() && parent.listSync().isEmpty) {
      await parent.delete();
    }
  }
}

/// Persists which volumes are downloaded, as a JSON manifest on disk.
///
/// The full record map is held in memory after [load]; mutations rewrite the
/// whole file. Downloads run several at a time, so writes take turns, and
/// each goes to a side file first that replaces the manifest only once it
/// is whole: an unreadable manifest loads as empty, and the app would then
/// believe nothing was downloaded.
class DownloadStore {
  DownloadStore(this._storage);

  final LibraryStorage _storage;
  final Map<String, DownloadRecord> _records = {};
  bool _loaded = false;

  String _key(int seriesId, String fileName) => '$seriesId/$fileName';

  /// Reads the manifest from disk. Safe to call more than once.
  Future<void> load() async {
    if (_loaded) return;
    final file = File(await _storage.manifestPath());
    if (file.existsSync()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) {
          raw.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              _records[key] = DownloadRecord.fromJson(value);
            }
          });
        }
      } on Exception {
        // Corrupt manifest — start clean rather than crash.
        _records.clear();
      }
    }
    _loaded = true;
  }

  DownloadRecord? recordFor(Volume volume) =>
      _records[_key(volume.seriesOpdsId, volume.fileName)];

  bool isDownloaded(Volume volume) => recordFor(volume) != null;

  /// Every download record, keyed by `seriesOpdsId/fileName`.
  Map<String, DownloadRecord> get allRecords => Map.unmodifiable(_records);

  /// Every download record belonging to a series.
  Iterable<DownloadRecord> recordsForSeries(int seriesId) {
    final prefix = '$seriesId/';
    return [
      for (final entry in _records.entries)
        if (entry.key.startsWith(prefix)) entry.value,
    ];
  }

  Future<void> put(Volume volume, DownloadRecord record) async {
    _records[_key(volume.seriesOpdsId, volume.fileName)] = record;
    await _flush();
  }

  Future<void> remove(Volume volume) async {
    _records.remove(_key(volume.seriesOpdsId, volume.fileName));
    await _flush();
  }

  Future<void>? _writing;

  /// One write at a time, of the records as they are when asked.
  Future<void> _flush() {
    final map = _records.map((key, value) => MapEntry(key, value.toJson()));
    final previous = _writing ?? Future<void>.value();
    final mine = previous.then((_) async {
      final path = await _storage.manifestPath();
      final text = await _encodeAside(map);
      final part = File('$path.part');
      await part.writeAsString(text, flush: true);
      await part.rename(path);
    });
    _writing = mine.whenComplete(() {
      if (identical(_writing, mine)) _writing = null;
    });
    return mine;
  }

  /// The manifest as text, off the thread that draws the screen: it grows
  /// with every volume downloaded, and is rewritten after each one.
  static Future<String> _encodeAside(Map<String, dynamic> map) async {
    try {
      return await Isolate.run(() => jsonEncode(map));
    } on Object {
      return jsonEncode(map);
    }
  }
}
