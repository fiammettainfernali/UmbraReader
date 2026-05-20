import 'dart:convert';
import 'dart:io';

import '../models/series.dart';
import '../models/volume.dart';
import 'library_storage.dart';

/// Caches library metadata on disk so the library can be browsed — and
/// downloaded books opened — while the OPDS server is unreachable.
///
/// Holds the series list and, per series, its volume list. Both are refreshed
/// after a successful sync and fall back to the cached copy when offline.
class LibraryCache {
  LibraryCache(this._storage);

  final LibraryStorage _storage;

  List<Series> _series = const [];
  final Map<int, List<Volume>> _volumes = {};
  bool _loaded = false;

  /// Reads the cache from disk. Never throws — a missing, corrupt or
  /// unavailable cache simply yields an empty library. Safe to call twice.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = File(await _storage.cachePath());
      if (!file.existsSync()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        final series = raw['series'];
        if (series is List) {
          _series = series
              .whereType<Map<String, dynamic>>()
              .map(Series.fromJson)
              .toList();
        }
        final volumes = raw['volumes'];
        if (volumes is Map<String, dynamic>) {
          volumes.forEach((key, value) {
            final id = int.tryParse(key);
            if (id != null && value is List) {
              _volumes[id] = value
                  .whereType<Map<String, dynamic>>()
                  .map(Volume.fromJson)
                  .toList();
            }
          });
        }
      }
    } on Exception {
      _series = const [];
      _volumes.clear();
    }
  }

  List<Series> get series => _series;

  List<Volume>? volumesFor(int seriesId) => _volumes[seriesId];

  Future<void> saveSeries(List<Series> series) async {
    _series = series;
    await _flush();
  }

  Future<void> saveVolumes(int seriesId, List<Volume> volumes) async {
    _volumes[seriesId] = volumes;
    await _flush();
  }

  Future<void> _flush() async {
    final file = File(await _storage.cachePath());
    final data = {
      'series': _series.map((s) => s.toJson()).toList(),
      'volumes': _volumes.map(
        (id, list) => MapEntry('$id', list.map((v) => v.toJson()).toList()),
      ),
    };
    await file.writeAsString(jsonEncode(data));
  }
}
