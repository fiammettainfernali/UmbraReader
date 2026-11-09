import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../models/series.dart';
import '../models/volume.dart';
import 'library_storage.dart';

/// Bumped whenever a sync rewrites the cached series list.
///
/// The library screen owns fetching, but it is no longer the only screen
/// showing the library: Discover reads the same cache from its own
/// instance. Without a signal, its shelves stayed at whatever was on disk
/// when the tab was first built — it never learned that a sync had landed,
/// so "recently updated" simply stopped moving.
///
/// Series only. Volume writes happen once per series during a sync and
/// don't feed any shelf, so bumping on those would be hundreds of wake-ups
/// to redraw the same thing.
final ValueNotifier<int> libraryCacheRevision = ValueNotifier<int>(0);

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
    libraryCacheRevision.value++;
  }

  Future<void> saveVolumes(int seriesId, List<Volume> volumes) async {
    _volumes[seriesId] = volumes;
    await _flush();
  }

  /// [saveVolumes] for a run that saves many series: kept now, written
  /// at most once per [stageWindow], and by [flush] at the end.
  ///
  /// Writing the whole cache — every series and every volume list, about
  /// 2 MB on a 1,104-novel library — after each series was what made the
  /// library lag through a whole-library check: 1,104 rewrites, each
  /// turning the lot into text on the thread that draws the screen.
  void stageVolumes(int seriesId, List<Volume> volumes) {
    _volumes[seriesId] = volumes;
    _staged ??= Timer(stageWindow, () {
      _staged = null;
      unawaited(_flush());
    });
  }

  /// Writes anything [stageVolumes] is still holding.
  Future<void> flush() async {
    if (_staged == null) return _writing ?? Future<void>.value();
    _staged!.cancel();
    _staged = null;
    await _flush();
  }

  /// How long staged volume lists wait before being written.
  static const stageWindow = Duration(seconds: 3);

  Timer? _staged;
  Future<void>? _writing;

  /// One write at a time: several used to run at once against the same
  /// file, which could leave it half one and half another.
  Future<void> _flush() {
    final data = {
      'series': _series.map((s) => s.toJson()).toList(),
      'volumes': _volumes.map(
        (id, list) => MapEntry('$id', list.map((v) => v.toJson()).toList()),
      ),
    };
    final previous = _writing ?? Future<void>.value();
    final mine = previous.then((_) async {
      final file = File(await _storage.cachePath());
      await file.writeAsString(await _encode(data));
    });
    _writing = mine.whenComplete(() {
      if (identical(_writing, mine)) _writing = null;
    });
    return mine;
  }

  /// Turning the cache into text, off the thread that draws the screen.
  static Future<String> _encode(Map<String, Object> data) async {
    try {
      return await Isolate.run(() => jsonEncode(data));
    } on Object {
      // Somewhere isolates aren't available: do it here, as before.
      return jsonEncode(data);
    }
  }
}
