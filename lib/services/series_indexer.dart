// Keeping the semantic index up to date with the library.
//
// Runs after the library loads, never before it shows: the index is what
// makes suggestions good, and nobody opens a reader to wait for suggestions.
// A first pass over 1,016 books is about a minute of phone; every pass after
// that is however many blurbs actually changed, which is normally none.

import 'dart:typed_data';

import '../models/series.dart';
import 'semantic_log.dart';
import 'series_vector_store.dart';
import 'text_embedder.dart';

/// What a pass did, so a caller can say something true about it.
class IndexOutcome {
  const IndexOutcome({
    required this.embedded,
    required this.pruned,
    required this.remaining,
    required this.failed,
  });

  /// Books embedded this pass.
  final int embedded;

  /// Stale rows dropped — series gone from the library, or another model's.
  final int pruned;

  /// Books still waiting, when a budget cut the pass short.
  final int remaining;

  /// Books whose text came back with no vector at all.
  final int failed;

  bool get isComplete => remaining == 0;
}

class SeriesIndexer {
  SeriesIndexer({
    required this.embed,
    SeriesVectorStore? store,
    void Function(String message)? log,
  })  : store = store ?? SeriesVectorStore(),
        log = log ?? semanticLog;

  /// Injected rather than constructed so the logic here — what needs
  /// doing, in what order, and when to stop — can be tested without
  /// loading 23MB of model into a unit test.
  final Future<Float32List?> Function(String text) embed;

  final SeriesVectorStore store;

  /// Where this pass narrates itself. Injected so a test can stay quiet,
  /// and so the breadcrumb below is a real line on a real device.
  final void Function(String message) log;

  /// Brings the index up to date, embedding at most [budget] books.
  ///
  /// The budget exists so a first run on a large library can be spread over
  /// several launches instead of holding a background task open for a
  /// minute: each pass does a slice and reports what is left. Newest books
  /// go first, because the shelf a reader is about to look at matters more
  /// than the one they filled two years ago.
  Future<IndexOutcome> indexLibrary(
    List<Series> library, {
    int budget = 250,
    void Function(int done, int total)? onProgress,
  }) async {
    final clock = Stopwatch()..start();
    final pruned = await store.prune({for (final s in library) s.opdsId});
    final known = await store.indexedHashes();

    final pending = <(Series, String, String)>[];
    for (final series in library) {
      final text = embeddingTextFor(series);
      if (text.trim().isEmpty) continue;
      final fingerprint = textFingerprint(text);
      if (known[series.opdsId] == fingerprint) continue;
      pending.add((series, text, fingerprint));
    }
    // Newest first, and undated last rather than dropped.
    pending.sort((a, b) {
      final at = a.$1.addedAt;
      final bt = b.$1.addedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    var embedded = 0;
    var failed = 0;
    final slice = pending.take(budget).toList();
    log('scan in ${formatElapsed(clock.elapsed)}: ${library.length} books, '
        '${known.length} already indexed, ${pending.length} to do, '
        '$pruned pruned — embedding ${slice.length} this pass');

    final embedClock = Stopwatch()..start();
    for (var i = 0; i < slice.length; i++) {
      final (series, text, fingerprint) = slice[i];
      // Written BEFORE the inference, not after. An abort inside the native
      // runtime leaves no exception and no further output, so the last line
      // in the log is the name of the book that caused it.
      log('embed ${i + 1}/${slice.length} ${series.opdsId} '
          '"${_short(series.title)}" ${text.length} chars');
      final vector = await embed(text);
      if (vector == null) {
        failed++;
        log('  no vector for ${series.opdsId}');
      } else {
        await store.put(series.opdsId, vector, fingerprint);
        embedded++;
      }
      onProgress?.call(i + 1, slice.length);
    }

    final remaining = pending.length - slice.length;
    final each = embedded == 0
        ? ''
        : ', ${(embedClock.elapsedMilliseconds / embedded).round()}ms each';
    log('pass done in ${formatElapsed(clock.elapsed)}: embedded $embedded, '
        'failed $failed, pruned $pruned, $remaining left$each');

    return IndexOutcome(
      embedded: embedded,
      pruned: pruned,
      remaining: remaining,
      failed: failed,
    );
  }

  /// Enough of a title to recognise the book in a log, not enough to wrap.
  static String _short(String title) {
    final clean = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    return clean.length <= 48 ? clean : '${clean.substring(0, 47)}…';
  }
}
