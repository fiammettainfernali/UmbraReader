import 'package:http/http.dart' as http;

import 'epub_parser.dart';
import 'library_storage.dart';
import 'opds_client.dart';
import 'remote_epub_source.dart';
import 'reading_progress_store.dart';
import 'settings_service.dart';
import '../models/series.dart';
import '../models/volume.dart';

/// Keeps a streamed book's chapter count current without opening it.
///
/// A downloaded volume learns its own size: downloading it re-reads the
/// EPUB and writes the count. A streamed volume is never downloaded, so
/// nothing re-reads it — its count is whatever it was the last time it was
/// opened. New chapters arrive on the hub and the shelf goes on saying
/// "Chapter 12 of 76" until you go in and look, which is the one thing the
/// shelf exists to save you.
///
/// The feed's own chapter count cannot stand in for this. It counts the
/// novel's chapters; the reader counts spine entries, and a compiled book
/// carries one more of those than it has chapters — a front-matter page. A
/// number off by one against the reader's own display is a different bug,
/// not a fix.
///
/// So the real thing is read, and it is cheap: the container names the
/// package file and the package file lists the spine. Two requests, and
/// only for a book whose EPUB has actually been rebuilt since its position
/// was saved.
class StreamedCountRefresh {
  StreamedCountRefresh({
    required this.settings,
    ReadingProgressStore? progress,
    DownloadStore? downloads,
    this.client,
  }) : _progress = progress ?? ReadingProgressStore(),
       _downloads = downloads;

  final OpdsSettings settings;
  final ReadingProgressStore _progress;
  final DownloadStore? _downloads;

  /// The transport, for tests. Null means one per book, as in the app.
  ///
  /// A seam rather than an abstraction: without it the only assertion this
  /// class could carry was "it did nothing or something", which is not an
  /// assertion.
  final http.Client? client;

  /// The most books to re-measure in one pass.
  ///
  /// A ceiling rather than a queue: this runs on a library refresh, and a
  /// library that has just had fifty books recompiled should not answer by
  /// making a hundred requests before the shelf will draw. What it misses
  /// it picks up next time.
  static const maxPerPass = 8;

  /// Re-reads counts for started, streamed books whose EPUB is newer than
  /// their saved position. Returns how many were updated.
  ///
  /// Never throws: a shelf that cannot refresh a number is still a shelf.
  Future<int> run(
    List<ReadingEntry> entries,
    List<Series> library,
  ) async {
    final rebuiltAt = <int, DateTime?>{
      for (final s in library) s.opdsId: s.updatedAt,
    };
    var updated = 0;
    for (final entry in entries) {
      if (updated >= maxPerPass) break;
      if (!_worthRefreshing(entry, rebuiltAt[entry.volume.seriesOpdsId])) {
        continue;
      }
      final count = await _countFor(entry.volume);
      if (count == null || count == entry.progress.chapterCount) continue;
      await _progress.save(
        entry.volume,
        ReadingProgress(
          chapterIndex: entry.progress.chapterIndex.clamp(0, count - 1),
          blockIndex: entry.progress.blockIndex,
          blockChar: entry.progress.blockChar,
          chapterPath: entry.progress.chapterPath,
          chapterCount: count,
          // Deliberately false rather than carried over. Finishing is
          // sticky, and save() re-applies it for anything whose chapter
          // count has not moved — so passing false here asks that rule the
          // question instead of answering it. A book that has grown comes
          // back unfinished, which is true; one that merely got a new cover
          // never reaches here, because the count did not change.
          endReached: false,
        ),
        // A book the reader removed from the shelf stays removed. Learning
        // its size is not a reason to put it back.
        unhide: false,
      );
      updated++;
    }
    return updated;
  }

  bool _worthRefreshing(ReadingEntry entry, DateTime? rebuiltAt) {
    if (rebuiltAt == null) return false;
    // Nothing read yet: there is no position whose denominator is wrong.
    if (!entry.progress.isStarted) return false;
    // A downloaded book measures itself when it is downloaded.
    if (_downloads?.isDownloaded(entry.volume) ?? false) return false;
    final savedAt = entry.progress.updatedAt;
    if (savedAt != null && !rebuiltAt.isAfter(savedAt)) return false;
    return true;
  }

  Future<int?> _countFor(Volume volume) async {
    final source = RemoteEpubSource(
      baseUrl: settings.baseUrl,
      novelId: volume.seriesOpdsId,
      fileName: volume.fileName,
      headers: OpdsClient(settings).authHeaders,
      client: client,
    );
    try {
      await source.warmUp();
      final book = await EpubParser().openSource(source);
      return book.chapters.isEmpty ? null : book.chapters.length;
    } on Exception {
      // Offline, asleep, refused — the count simply stays as it was.
      return null;
    } finally {
      source.dispose();
    }
  }
}
