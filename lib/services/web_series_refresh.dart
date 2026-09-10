// Asking followed sites whether anything new has appeared.
//
// Deliberately shaped like StreamedCountRefresh, and for the same reason
// that one had to be reshaped: it is one GET per series against a site that
// may be unreachable, and away from a good connection those do not fail
// fast. So it is capped, it is stale-gated, it never throws, and it must
// never be awaited before a shelf is drawn — the shelf is built from what
// is already on the device, and this updates it afterwards if anything
// actually moved.

import 'web_series_metadata.dart';
import 'web_series_store.dart';

class WebSeriesRefresh {
  WebSeriesRefresh({WebSeriesStore? store, WebSeriesMetadata? metadata})
    : _store = store ?? WebSeriesStore(),
      _metadata = metadata ?? WebSeriesMetadata();

  final WebSeriesStore _store;
  final WebSeriesMetadata _metadata;

  /// How many sites one refresh will speak to.
  ///
  /// A library of forty followed comics must not answer a pull-to-refresh
  /// with forty requests before anything can be shown.
  static const int maxPerPass = 8;

  /// How long a check stays good for. Comics update daily at best, and the
  /// library is refreshed far more often than that.
  static const Duration staleAfter = Duration(hours: 6);

  /// Checks the [maxPerPass] most stale of [series]. Returns how many
  /// learned about a chapter they did not already know about.
  Future<int> run(List<WebSeries> series, {DateTime? now}) async {
    final at = now ?? DateTime.now().toUtc();
    final due = series.where((s) => _isDue(s, at)).toList()
      ..sort((a, b) {
        // Never-checked first, then oldest check first.
        final ac = a.checkedAt;
        final bc = b.checkedAt;
        if (ac == null && bc == null) return 0;
        if (ac == null) return -1;
        if (bc == null) return 1;
        return ac.compareTo(bc);
      });

    var learned = 0;
    for (final entry in due.take(maxPerPass)) {
      final url = Uri.tryParse(entry.url);
      if (url == null) continue;
      final info = await _metadata.fetch(url);
      // Unreachable, or a page that says nothing: leave the row alone
      // rather than recording an absence as an answer.
      if (info == null || info.isEmpty) continue;
      final found = info.latestChapterNumber;
      final known = entry.latestChapter;
      if (found != null && (known == null || found > known)) learned++;
      await _store.noteCheck(entry.url, info);
    }
    return learned;
  }

  static bool _isDue(WebSeries series, DateTime now) {
    final checked = series.checkedAt;
    if (checked == null) return true;
    return now.difference(checked) >= staleAfter;
  }
}
