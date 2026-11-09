import 'dart:async';

import '../db/app_database.dart';
import '../models/volume.dart';
import 'control_client.dart';
import 'library_cache.dart';
import 'library_storage.dart';
import 'opds_client.dart';
import 'reading_progress_store.dart';
import 'settings_service.dart';

/// Reading places between this phone and the computer: newest wins.
///
/// A place travels as the novel, the volume file and the chapter file in it,
/// how far through the chapter (0 to 1), and when it was read. The computer
/// turns that into its own chapter number; each side keeps its own finer
/// position and turns the share back into a paragraph of its own.
///
/// Runs after the library is fetched, on returning to the app, and a few
/// seconds after the reader stops on a new place. "When it was read" is when
/// the place last moved, so opening a book where you already were never
/// outranks newer reading on the computer.
class PcProgressSync {
  PcProgressSync._();

  static final PcProgressSync instance = PcProgressSync._();

  static const _kSince = 'pc_progress_since';

  /// How long after the last move before sending it.
  static const settleFor = Duration(seconds: 4);

  OpdsSettings? _settings;
  Future<bool>? _running;
  Timer? _soon;

  /// After a place moved: send it once the reader has settled. Only once a
  /// sync has reached the computer; until then there is nowhere to send it,
  /// and the next library fetch takes it anyway.
  void syncSoon() {
    if (_settings == null) return;
    _soon?.cancel();
    _soon = Timer(settleFor, () {
      final settings = _settings;
      if (settings != null) unawaited(sync(settings));
    });
  }

  /// Exchanges places with the computer. True if any place here changed.
  /// Never throws: a computer that can't be reached is tried next time.
  Future<bool> sync(OpdsSettings settings) {
    return _running ??= _sync(settings)
        .catchError((Object _) => false)
        .whenComplete(() => _running = null);
  }

  Future<bool> _sync(OpdsSettings settings) async {
    if (!settings.isConfigured || !settings.hasAuth) return false;
    final db = AppDatabase.instance;
    final client = ControlClient(settings);
    final store = ReadingProgressStore();
    final page = await client.progress(since: await db.kvGet(_kSince) ?? '');
    _settings = settings;
    final local = await store.latestPerSeries();
    var changed = false;
    final taken = <int>{};

    // The computer's newer places.
    for (final place in page.places) {
      final mine = local[place.novel];
      final mineAt = mine?.$1.progress.updatedAt;
      if (mineAt != null && !place.at.isAfter(mineAt)) continue;
      if (await _adopt(settings, store, place)) {
        changed = true;
        taken.add(place.novel);
      }
    }

    // Ours the computer hasn't had: the latest per novel, once each.
    for (final (entry, share) in local.values) {
      final at = entry.progress.updatedAt;
      final path = entry.progress.chapterPath;
      if (at == null || path == null || taken.contains(entry.volume.seriesOpdsId)) continue;
      if (await store.pushedAt(entry.volume) == at.toIso8601String()) continue;
      final reply = await client.pushProgress(PcPlace(
        novel: entry.volume.seriesOpdsId,
        file: entry.volume.fileName,
        path: path,
        share: share,
        at: at,
      ));
      await store.markPushed(entry.volume, at);
      final newer = reply.newer;
      if (!reply.applied && newer != null && newer.at.isAfter(at)) {
        if (await _adopt(settings, store, newer)) changed = true;
      }
    }

    if (page.now.isNotEmpty) await db.kvSet(_kSince, page.now);
    return changed;
  }

  /// Takes the computer's place, if this phone knows the volume it's in.
  Future<bool> _adopt(OpdsSettings settings, ReadingProgressStore store, PcPlace place) async {
    final volume = await _volume(settings, place.novel, place.file);
    if (volume == null) return false;
    final number = RegExp(r'chapter_(\d+)\.xhtml$').firstMatch(place.path);
    await store.adoptRemote(
      volume,
      chapterPath: place.path,
      // The reader finds the chapter by its path; the index is only a fallback.
      chapterIndex: number == null ? 0 : (int.parse(number.group(1)!) - 1).clamp(0, 1 << 20),
      share: place.share,
      at: place.at,
    );
    return true;
  }

  Future<Volume?> _volume(OpdsSettings settings, int novel, String file) async {
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    var volumes = cache.volumesFor(novel);
    if (volumes == null || !volumes.any((v) => v.fileName == file)) {
      try {
        volumes = await OpdsClient(settings).fetchVolumes(novel);
        await cache.saveVolumes(novel, volumes);
      } on OpdsException {
        return null;
      }
    }
    for (final v in volumes) {
      if (v.fileName == file) return v;
    }
    return null;
  }
}
