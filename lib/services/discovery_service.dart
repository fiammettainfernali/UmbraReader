import 'control_client.dart';
import 'recommendation_engine.dart';

/// One novel found on a source site by a taste-driven search, with the
/// taste connection that surfaced it.
class DiscoveryPick {
  const DiscoveryPick({required this.hit, required this.reason});

  final SearchHit hit;

  /// The taste line that produced this pick ("More by the author of X").
  final String reason;
}

/// Turns the taste profile's [TasteQuery]s into live source-site searches
/// through Novel Grabber, returning novels that are NOT already in the
/// library — the app-side discovery loop (Phase 7 follow-on, "option 1").
///
/// Pure orchestration: the search function is injected so tests never touch
/// the network, and the caller supplies the site list (from ControlStatus).
/// Requests run sequentially and stop early once [maxResults] picks exist —
/// source sites sit behind anti-bot layers, so the budget stays small and
/// the whole thing only ever runs on an explicit user tap.
class DiscoveryService {
  const DiscoveryService({
    this.maxResults = 12,
    this.maxSitesPerQuery = 2,
    this.maxHitsPerSearch = 5,
  });

  final int maxResults;

  /// How many source sites each taste query is sent to.
  final int maxSitesPerQuery;

  /// How many hits a single search may contribute (keeps one prolific
  /// query from monopolising the shelf).
  final int maxHitsPerSearch;

  Future<List<DiscoveryPick>> discover({
    required List<TasteQuery> queries,
    required List<String> sites,
    required Future<List<SearchHit>> Function(String query, String site)
        search,
    required Iterable<String> libraryTitles,
  }) async {
    if (queries.isEmpty || sites.isEmpty) return const [];
    final have = {for (final t in libraryTitles) _normalize(t)};
    final seen = <String>{};
    // Per-query buckets so the final shelf interleaves taste angles instead
    // of being all one query's results.
    final buckets = [for (final _ in queries) <DiscoveryPick>[]];

    var total = 0;
    outer:
    for (var qi = 0; qi < queries.length; qi++) {
      final query = queries[qi];
      for (final site in sites.take(maxSitesPerQuery)) {
        final List<SearchHit> hits;
        try {
          hits = await search(query.query, site);
        } on Exception {
          continue; // one slow/blocked source must not sink the rest
        }
        for (final hit in hits.take(maxHitsPerSearch)) {
          if (hit.title.trim().isEmpty || hit.url.isEmpty) continue;
          final key = _normalize(hit.title);
          if (key.isEmpty || seen.contains(key) || have.contains(key)) {
            continue;
          }
          seen.add(key);
          buckets[qi].add(DiscoveryPick(hit: hit, reason: query.reason));
          total++;
          if (total >= maxResults) break outer;
        }
      }
    }

    // Round-robin across queries: variety over volume.
    final result = <DiscoveryPick>[];
    var added = true;
    var round = 0;
    while (added && result.length < maxResults) {
      added = false;
      for (final bucket in buckets) {
        if (round < bucket.length) {
          result.add(bucket[round]);
          added = true;
          if (result.length >= maxResults) break;
        }
      }
      round++;
    }
    return result;
  }

  /// Title identity across sites and the library: lowercase alphanumerics
  /// only, so "The Beginning After The End" == "the-beginning-after-the-end".
  static String _normalize(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
