import 'dart:math';

import '../models/series.dart';
import '../models/volume.dart';
import 'reading_progress_store.dart';
import 'rec_outcome_store.dart';
import 'recommendation_feedback_store.dart';

/// One recommended series with the score that produced it.
class Recommendation {
  const Recommendation(
    this.series,
    this.score, {
    this.reason = '',
    this.isWildcard = false,
  });

  final Series series;
  final double score;

  /// Human-readable "Because…" line: the dominant thing connecting this pick
  /// to something the user actually read. Empty when there's nothing to say.
  final String reason;

  /// True for the deliberate out-of-taste exploration pick.
  final bool isWildcard;
}

/// Behavioural signals beyond chapter fractions — everything the app already
/// knows about HOW the user read, folded into the affinity weights. All
/// fields are optional; a missing signal contributes nothing, so the engine
/// degrades gracefully to fraction-only scoring.
class RecSignals {
  const RecSignals({
    this.volumeSeconds = const {},
    this.volumeWords = const {},
    this.highlightsPerSeries = const {},
    this.hiddenVolumeKeys = const {},
    this.collectionSeriesIds = const {},
    this.outcomes = const {},
    this.statusOverrides = const {},
  });

  /// Reading seconds per volume (`seriesOpdsId/fileName`), from the
  /// activity ledger. Time-in-book is the strongest implicit like there is.
  final Map<String, int> volumeSeconds;

  /// Words read per volume (same keys) — re-read-proof consumption.
  final Map<String, int> volumeWords;

  /// Saved highlight/bookmark count per series — highlight density is love.
  final Map<int, int> highlightsPerSeries;

  /// Volume keys hidden from the Continue shelf — a mild "enough of this".
  final Set<String> hiddenVolumeKeys;

  /// Series the user filed into a collection — explicit curation interest.
  final Set<int> collectionSeriesIds;

  /// Impression/tap outcomes per series: candidates that keep being shown
  /// and ignored get softened so the shelf doesn't go stale.
  final Map<int, RecOutcome> outcomes;

  /// The user's own in-app reading status per series, overriding the
  /// server-side `Series.readingStatus`. Engine vocabulary: 'completed'
  /// (a full like, even with zero in-app reading — e.g. a series listened
  /// to entirely in an external reader and marked caught-up), 'dropped'
  /// (strong negative), 'ongoing' (neutral).
  final Map<int, String> statusOverrides;

  static const none = RecSignals();
}

/// Per-user weights over the engine's feature groups — how much an author
/// match, genre similarity, keyword similarity or length match counts for
/// THIS user. [prior] encodes the old hand-tuned behaviour (author ≈ double
/// a genre) and is the cold-start default; the learner nudges them from
/// recommendation outcomes.
class RecWeights {
  const RecWeights({
    required this.author,
    required this.genre,
    required this.keyword,
    required this.length,
  });

  final double author;
  final double genre;
  final double keyword;
  final double length;

  static const prior = RecWeights(
    author: 2.0,
    genre: 1.0,
    keyword: 1.0,
    length: 0.5,
  );

  Map<String, dynamic> toJson() => {
    'author': author,
    'genre': genre,
    'keyword': keyword,
    'length': length,
  };

  factory RecWeights.fromJson(Map<String, dynamic> json) => RecWeights(
    author: (json['author'] as num?)?.toDouble() ?? prior.author,
    genre: (json['genre'] as num?)?.toDouble() ?? prior.genre,
    keyword: (json['keyword'] as num?)?.toDouble() ?? prior.keyword,
    length: (json['length'] as num?)?.toDouble() ?? prior.length,
  );
}

/// A candidate's per-group affinity to the user's taste profile, each
/// squashed to (-1, 1) so the learner sees bounded features and no single
/// runaway tag dominates.
class RecGroupScores {
  const RecGroupScores({
    required this.author,
    required this.genre,
    required this.keyword,
    required this.length,
  });

  final double author;
  final double genre;
  final double keyword;
  final double length;

  /// The learner's feature vector, in a fixed order.
  List<double> get features => [author, genre, keyword, length];

  double weighted(RecWeights w) =>
      author * w.author +
      genre * w.genre +
      keyword * w.keyword +
      length * w.length;
}

/// The user's taste, distilled: signed affinity per content tag plus the
/// library-wide IDF that discounts ubiquitous tags (a genre 80% of the
/// library shares says almost nothing; a rare shared one says a lot).
/// Built once per recommend() pass and reused by the weight learner as its
/// feature extractor, so training and serving can never disagree.
class RecTasteProfile {
  const RecTasteProfile._({
    required Map<String, double> tagScore,
    required Map<String, double> tagIdf,
    required Map<int, List<String>> keywords,
    required Map<String, int> tagTopSeed,
    required Map<int, String> seedTitles,
    required this.engagedIds,
    required this.hasHistory,
  }) : _tagScore = tagScore,
       _tagIdf = tagIdf,
       _keywords = keywords,
       _tagTopSeed = tagTopSeed,
       _seedTitles = seedTitles;

  final Map<String, double> _tagScore;
  final Map<String, double> _tagIdf;
  final Map<int, List<String>> _keywords;

  /// For each tag, the positively-contributing seed series that carries it
  /// hardest — the "like X" part of a reason line.
  final Map<String, int> _tagTopSeed;
  final Map<int, String> _seedTitles;

  /// Series the user has engaged with (read, filed, judged) — never
  /// candidates.
  final Set<int> engagedIds;

  /// False when there is no reading history at all (cold start).
  final bool hasHistory;

  double _affinity(String tag) =>
      (_tagScore[tag] ?? 0) * (_tagIdf[tag] ?? 1.0);

  /// Squash to (-1, 1): monotonic, sign-preserving, bounded.
  static double _squash(double x) => x / (1 + x.abs());

  /// The per-group affinity of [series] to this profile.
  RecGroupScores groupsFor(Series series) {
    final author = series.author.trim().toLowerCase();
    final authorScore = (author.isEmpty || author == 'unknown')
        ? 0.0
        : _affinity('a:$author');

    var genreSum = 0.0;
    var genreCount = 0;
    for (final raw in series.genres) {
      final key = raw.trim().toLowerCase();
      if (key.isEmpty) continue;
      genreSum += _affinity('g:$key');
      genreCount++;
    }

    var keywordSum = 0.0;
    var keywordCount = 0;
    for (final kw in _keywords[series.opdsId] ?? const <String>[]) {
      keywordSum += _affinity('k:$kw');
      keywordCount++;
    }

    final bucket = lengthBucket(series.totalChapters);
    final lengthScore = bucket == null ? 0.0 : _affinity('l:$bucket');

    // √count normalization: a candidate listing six genres shouldn't out-sum
    // a single-genre candidate on volume alone.
    return RecGroupScores(
      author: _squash(authorScore),
      genre: _squash(genreCount == 0 ? 0 : genreSum / sqrt(genreCount)),
      keyword: _squash(
        keywordCount == 0 ? 0 : keywordSum / sqrt(keywordCount),
      ),
      length: _squash(lengthScore),
    );
  }

  String? _seedTitleFor(String tag) {
    final id = _tagTopSeed[tag];
    if (id == null) return null;
    return _seedTitles[id];
  }

  /// A human "Because…" line for [series]: names the dominant positive
  /// connection under [w] — same author, a shared genre, or shared themes —
  /// and the read that drove it. Empty when nothing positive connects.
  String reasonFor(Series series, RecWeights w) {
    final g = groupsFor(series);

    // Author connection.
    final author = series.author.trim();
    final authorTag = 'a:${author.toLowerCase()}';
    final authorPart = g.author > 0 ? g.author * w.author : 0.0;

    // Strongest positively-shared genre.
    String? topGenre;
    var topGenreAffinity = 0.0;
    for (final raw in series.genres) {
      final key = raw.trim();
      if (key.isEmpty) continue;
      final affinity = _affinity('g:${key.toLowerCase()}');
      if (affinity > topGenreAffinity) {
        topGenreAffinity = affinity;
        topGenre = key;
      }
    }
    final genrePart = g.genre > 0 ? g.genre * w.genre : 0.0;
    final keywordPart = g.keyword > 0 ? g.keyword * w.keyword : 0.0;

    // Strongest positively-shared keyword (for the seed attribution).
    String? topKeywordTag;
    var topKeywordAffinity = 0.0;
    for (final kw in _keywords[series.opdsId] ?? const <String>[]) {
      final affinity = _affinity('k:$kw');
      if (affinity > topKeywordAffinity) {
        topKeywordAffinity = affinity;
        topKeywordTag = 'k:$kw';
      }
    }

    final best = [authorPart, genrePart, keywordPart].reduce(max);
    if (best <= 0) return '';
    if (best == authorPart) {
      final seed = _seedTitleFor(authorTag);
      return seed == null
          ? 'By $author, an author you read'
          : 'By the author of “$seed”';
    }
    if (best == genrePart && topGenre != null) {
      final seed = _seedTitleFor('g:${topGenre.toLowerCase()}');
      return seed == null ? topGenre : '$topGenre, like “$seed”';
    }
    final seed = topKeywordTag == null ? null : _seedTitleFor(topKeywordTag);
    return seed == null ? 'Similar themes to your reads' : 'Echoes “$seed”';
  }
}

/// The length-affinity bucket for a chapter count, or null when the count is
/// unknown — unknown must not be a matchable tag (two series with missing
/// metadata don't "match").
String? lengthBucket(int chapters) {
  if (chapters <= 0) return null;
  if (chapters < 100) return 'short';
  if (chapters < 500) return 'medium';
  if (chapters < 2000) return 'long';
  return 'huge';
}

/// Builds a ranked list of "you might also like" suggestions from the user's
/// reading history, the explicit reading status they've set per series, and
/// content features (genre, author, length, description keywords).
///
/// Strategy: every series the user has engaged with contributes a *signed*
/// affinity to its content tags — finished/long-read books push positive,
/// dropped books push negative. Time decay (30-day half-life) makes recent
/// reads dominate so the shelf naturally drifts with current taste. The
/// final ranking applies a diversity guard so a single author or genre can't
/// monopolise the shelf, and falls back to recently-updated series when
/// there's no history yet.
class RecommendationEngine {
  const RecommendationEngine({
    this.halfLifeDays = 30,
    this.maxResults = 12,
    this.maxPerAuthor = 2,
    this.maxPerGenre = 3,
    this.keywordsPerSeries = 12,
  });

  /// Days for a like's weight to halve.
  final int halfLifeDays;

  /// Cap on the number of recommendations returned.
  final int maxResults;

  /// Max picks by the same author in the result.
  final int maxPerAuthor;

  /// Max picks sharing the same primary genre in the result.
  final int maxPerGenre;

  /// Top-K TF-IDF keywords pulled from each series description.
  final int keywordsPerSeries;

  /// Returns the top-scored series the user hasn't engaged with, best first.
  /// [feedback] folds in explicit "no thanks" signals (dismissed cards, reset
  /// reading progress) as negative weight. [now] is overridable for tests.
  /// [explore] appends one daily-rotating out-of-taste wildcard pick — the
  /// library shelf's exploration slot. Off by default so "similar to X" and
  /// other callers stay purely taste-driven.
  List<Recommendation> recommend({
    required List<Series> allSeries,
    required List<ReadingEntry> readingEntries,
    Map<int, RecommendationFeedback>? feedback,
    RecSignals signals = RecSignals.none,
    RecWeights? weights,
    bool explore = false,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    if (allSeries.isEmpty) return const [];

    final profile = buildProfile(
      allSeries: allSeries,
      readingEntries: readingEntries,
      feedback: feedback,
      signals: signals,
      now: clock,
    );

    // Cold start: nothing engaged → recommend recently-updated series so the
    // shelf isn't blank on a fresh install.
    if (!profile.hasHistory) {
      final fallback = allSeries.toList()
        ..sort((a, b) {
          final at = a.updatedAt;
          final bt = b.updatedAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      return [
        for (final s in fallback.take(maxResults)) Recommendation(s, 0),
      ];
    }

    final w = weights ?? RecWeights.prior;

    // Score every series the user hasn't engaged with: per-group affinity
    // to the taste profile, combined under the (possibly learned) weights.
    final scored = <Recommendation>[];
    for (final series in allSeries) {
      if (profile.engagedIds.contains(series.opdsId)) continue;
      var score = profile.groupsFor(series).weighted(w);
      // Shown-and-ignored decay: a candidate that has sat on the shelf for
      // several distinct days without ever being opened gets progressively
      // softened (floor 35%), so the shelf rotates instead of going stale.
      final ignored = signals.outcomes[series.opdsId]?.ignored ?? 0;
      if (ignored > 2) {
        score *= max(0.35, pow(0.85, ignored - 2).toDouble());
      }
      if (score > 0) {
        scored.add(
          Recommendation(series, score, reason: profile.reasonFor(series, w)),
        );
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Diversity guard: cap by author and by primary genre.
    final authorTaken = <String, int>{};
    final genreTaken = <String, int>{};
    final result = <Recommendation>[];
    for (final rec in scored) {
      if (result.length >= maxResults) break;
      final author = rec.series.author.trim().toLowerCase();
      final primaryGenre = rec.series.genres.isNotEmpty
          ? rec.series.genres.first.trim().toLowerCase()
          : '';
      if (author.isNotEmpty && (authorTaken[author] ?? 0) >= maxPerAuthor) {
        continue;
      }
      if (primaryGenre.isNotEmpty &&
          (genreTaken[primaryGenre] ?? 0) >= maxPerGenre) {
        continue;
      }
      result.add(rec);
      if (author.isNotEmpty) {
        authorTaken.update(author, (c) => c + 1, ifAbsent: () => 1);
      }
      if (primaryGenre.isNotEmpty) {
        genreTaken.update(primaryGenre, (c) => c + 1, ifAbsent: () => 1);
      }
    }

    // Exploration wildcard: one pick from OUTSIDE the taste vector (zero or
    // negative affinity), rotated daily, so the shelf occasionally stretches
    // taste instead of only converging on it. Its outcome (read/liked vs
    // dismissed/ignored) feeds the same feedback + learning loops, which
    // makes exploration cheap and informative.
    if (explore && result.isNotEmpty) {
      final inResult = {for (final r in result) r.series.opdsId};
      final outside = [
        for (final series in allSeries)
          if (!profile.engagedIds.contains(series.opdsId) &&
              !inResult.contains(series.opdsId) &&
              profile.groupsFor(series).weighted(w) <= 0)
            series,
      ];
      if (outside.isNotEmpty) {
        final daySeed =
            clock.year * 10000 + clock.month * 100 + clock.day;
        final pick = outside[Random(daySeed).nextInt(outside.length)];
        result.add(
          Recommendation(
            pick,
            0,
            reason: 'Something different',
            isWildcard: true,
          ),
        );
      }
    }
    return result;
  }

  /// Distils the user's taste from history + signals into a [RecTasteProfile]
  /// — the shared feature extractor for both serving (recommend/similarTo)
  /// and training (RecWeightLearner), so the two can never disagree.
  /// [excludeSeriesIds] omits those series' own contributions from the
  /// profile — used when building TRAINING features, where a labeled series
  /// must not see its own affinity reflected back (label leakage).
  RecTasteProfile buildProfile({
    required List<Series> allSeries,
    required List<ReadingEntry> readingEntries,
    Map<int, RecommendationFeedback>? feedback,
    RecSignals signals = RecSignals.none,
    Set<int> excludeSeriesIds = const {},
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final byId = {for (final s in allSeries) s.opdsId: s};
    final keywords = _computeKeywords(allSeries);

    // Library-wide IDF per tag: log(1 + N/df). A tag every series carries is
    // discounted (but never zeroed); a rare shared one counts extra.
    final docFreq = <String, int>{};
    for (final s in allSeries) {
      for (final tag in _tagsFor(s, keywords[s.opdsId] ?? const []).toSet()) {
        docFreq.update(tag, (c) => c + 1, ifAbsent: () => 1);
      }
    }
    final n = max(allSeries.length, 1);
    final tagIdf = <String, double>{
      for (final e in docFreq.entries) e.key: log(1 + n / e.value),
    };

    // Group reading entries by series so multiple volumes of one series fold
    // into a single signal.
    final entriesBySeries = <int, List<ReadingEntry>>{};
    for (final entry in readingEntries) {
      entriesBySeries
          .putIfAbsent(entry.volume.seriesOpdsId, () => <ReadingEntry>[])
          .add(entry);
    }

    // The user's median seconds/words per touched volume — the yardstick
    // that turns raw time-in-book into "more/less than usual for you".
    final medianSeconds = _medianOver(readingEntries, signals.volumeSeconds);
    final medianWords = _medianOver(readingEntries, signals.volumeWords);

    final engagedIds = <int>{...entriesBySeries.keys};
    final signedSeries = <int, double>{};

    for (final series in allSeries) {
      if (excludeSeriesIds.contains(series.opdsId)) continue;
      // The user's own in-app status outranks the server-side one.
      final status = (signals.statusOverrides[series.opdsId] ??
              series.readingStatus)
          .trim()
          .toLowerCase();
      final entries = entriesBySeries[series.opdsId];
      final userFeedback = feedback?[series.opdsId];
      double? signed;
      if (entries != null) {
        // Sum per-volume like weights, then dampen with √n so a 10-volume
        // binge doesn't drown out single-volume favourites.
        var aggregated = 0.0;
        for (final entry in entries) {
          aggregated += _likeWeight(
            entry,
            clock,
            signals: signals,
            medianSeconds: medianSeconds,
            medianWords: medianWords,
          );
        }
        if (entries.length > 1) {
          aggregated = aggregated * sqrt(entries.length) / entries.length;
        }
        if (status == 'completed') {
          // User-marked complete → at least a full "like" even if the
          // chapter-count guess says otherwise.
          if (aggregated < 1.0) aggregated = 1.0;
        }
        signed = aggregated;
      } else if (status == 'completed') {
        // Marked caught-up with ZERO in-app reading entries — the
        // listened-elsewhere binge (e.g. Share-story → an external reader).
        // Consuming everything available is a full like; without a read
        // timestamp it doesn't decay, matching the finished-favourite floor
        // in spirit.
        signed = 1.0;
        engagedIds.add(series.opdsId);
      }
      // Highlight density: saved passages are a strong love signal, worth up
      // to +0.3 on top of whatever the read itself earned.
      final highlights = signals.highlightsPerSeries[series.opdsId] ?? 0;
      if (highlights > 0) {
        signed = (signed ?? 0) + min(0.3, 0.1 * highlights);
        engagedIds.add(series.opdsId);
      }
      // Curating a series into a collection is explicit interest.
      if (signals.collectionSeriesIds.contains(series.opdsId)) {
        signed = (signed ?? 0) + 0.25;
        engagedIds.add(series.opdsId);
      }
      // Hiding from the Continue shelf is a mild "enough of this for now".
      if (entries != null &&
          entries.any(
            (e) => signals.hiddenVolumeKeys.contains(_volumeKey(e.volume)),
          )) {
        signed = (signed ?? 0) - 0.15;
      }
      if (status == 'dropped') {
        // User-marked dropped → flip to a negative signal.
        signed = -(((signed ?? 0).abs()).clamp(0.5, double.infinity));
        engagedIds.add(series.opdsId);
      }
      // Explicit per-card feedback: reset is the strongest "no thanks",
      // dismiss a milder one; a 👍 is a full extra like on top of the read
      // history (an explicit like also supersedes an earlier negative);
      // snoozed just leaves the engaged set to keep the series off shelves.
      switch (userFeedback) {
        case RecommendationFeedback.reset:
          signed = -0.7;
          engagedIds.add(series.opdsId);
        case RecommendationFeedback.dismissed:
          // Genuine re-engagement outranks a card-level "not interested":
          // if they've substantially READ it since, the read wins.
          if ((signed ?? 0) < 0.5) signed = -0.3;
          engagedIds.add(series.opdsId);
        case RecommendationFeedback.liked:
          signed = max(signed ?? 0, 0) + 1.0;
          engagedIds.add(series.opdsId);
        case RecommendationFeedback.snoozed:
          engagedIds.add(series.opdsId);
        case null:
          break;
      }
      if (signed != null && signed != 0) {
        signedSeries[series.opdsId] = signed;
      }
    }

    // Accumulate signed affinity per content tag, remembering which positive
    // seed carries each tag hardest (for "like X" reason lines).
    final tagScore = <String, double>{};
    final tagTopSeed = <String, int>{};
    final tagTopContribution = <String, double>{};
    final seedTitles = <int, String>{};
    signedSeries.forEach((id, score) {
      final series = byId[id];
      if (series == null) return;
      if (score > 0) seedTitles[id] = series.title;
      for (final tag in _tagsFor(series, keywords[id] ?? const [])) {
        tagScore.update(tag, (s) => s + score, ifAbsent: () => score);
        if (score > (tagTopContribution[tag] ?? 0)) {
          tagTopContribution[tag] = score;
          tagTopSeed[tag] = id;
        }
      }
    });

    return RecTasteProfile._(
      tagScore: tagScore,
      tagIdf: tagIdf,
      keywords: keywords,
      tagTopSeed: tagTopSeed,
      seedTitles: seedTitles,
      engagedIds: engagedIds,
      hasHistory: signedSeries.isNotEmpty,
    );
  }

  /// Iterates every affinity tag for a series. Group weighting is no longer
  /// baked in here (the old author double-yield) — [RecWeights] owns how much
  /// each group counts.
  Iterable<String> _tagsFor(Series series, List<String> keywords) sync* {
    for (final raw in series.genres) {
      final key = raw.trim().toLowerCase();
      if (key.isNotEmpty) yield 'g:$key';
    }
    final author = series.author.trim().toLowerCase();
    if (author.isNotEmpty && author != 'unknown') {
      yield 'a:$author';
    }
    final bucket = lengthBucket(series.totalChapters);
    if (bucket != null) yield 'l:$bucket';
    for (final kw in keywords) {
      yield 'k:$kw';
    }
  }

  /// TF-IDF over series descriptions: each series gets the [keywordsPerSeries]
  /// most distinctive words from its description. Distinctive = high TF in
  /// this description, low document frequency across the whole library.
  Map<int, List<String>> _computeKeywords(List<Series> allSeries) {
    final docTokens = <int, List<String>>{};
    final docFreq = <String, int>{};
    for (final s in allSeries) {
      final tokens = _tokenize(s.description);
      docTokens[s.opdsId] = tokens;
      for (final t in tokens.toSet()) {
        docFreq.update(t, (c) => c + 1, ifAbsent: () => 1);
      }
    }
    final n = max(allSeries.length, 1);
    final result = <int, List<String>>{};
    docTokens.forEach((id, tokens) {
      if (tokens.isEmpty) {
        result[id] = const [];
        return;
      }
      final tf = <String, int>{};
      for (final t in tokens) {
        tf.update(t, (c) => c + 1, ifAbsent: () => 1);
      }
      final scored = <MapEntry<String, double>>[];
      tf.forEach((t, count) {
        final df = docFreq[t] ?? 0;
        if (df <= 0) return;
        final idf = log(n / df);
        if (idf <= 0) return;
        scored.add(MapEntry(t, count * idf));
      });
      scored.sort((a, b) => b.value.compareTo(a.value));
      result[id] = [
        for (final e in scored.take(keywordsPerSeries)) e.key,
      ];
    });
    return result;
  }

  static const _stopwords = <String>{
    'the', 'a', 'an', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at',
    'by', 'for', 'with', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'it', 'its', 'this', 'that', 'these', 'those', 'from', 'as', 'his',
    'her', 'their', 'they', 'he', 'she', 'him', 'them', 'you', 'your',
    'we', 'our', 'us', 'will', 'have', 'has', 'had', 'can', 'could',
    'would', 'should', 'not', 'one', 'two', 'also', 'than', 'then', 'so',
    'who', 'what', 'when', 'where', 'why', 'how', 'about', 'out',
    'over', 'under', 'more', 'most', 'some', 'any', 'all', 'only', 'very',
    'just', 'into', 'through', 'after', 'before', 'because', 'while',
    'during', 'novel', 'story', 'chapter', 'chapters', 'book', 'series',
    // 3-letter function words admitted by the shorter minimum.
    'get', 'got', 'now', 'off', 'own', 'per', 'too',
    'via', 'yet', 'did', 'don', 'end', 'few', 'lot', 'new', 'old', 'once',
    'said', 'say', 'see', 'set', 'use', 'way', 'even', 'ever',
  };

  /// Splits [text] into keyword tokens: single words of 3+ letters (short
  /// enough to keep webnovel staples like war/god/sect) plus bigrams of
  /// adjacent kept words, so "martial arts" and "video game" survive as
  /// concepts instead of dissolving into their halves.
  List<String> _tokenize(String text) {
    final tokens = <String>[];
    String? prev;
    for (final raw in text.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      if (raw.length < 3 || _stopwords.contains(raw)) {
        prev = null; // a bigram must be two ADJACENT kept words
        continue;
      }
      tokens.add(raw);
      if (prev != null) tokens.add('$prev $raw');
      prev = raw;
    }
    return tokens;
  }

  /// Recommends series similar to a single [source] series — used by the
  /// "More like this" shelf on a series detail screen. The source is treated
  /// as a fresh, fully-completed read, so its content tags drive the picks.
  List<Recommendation> similarTo({
    required Series source,
    required List<Series> allSeries,
    int maxResults = 6,
    Map<int, RecommendationFeedback>? feedback,
    RecSignals signals = RecSignals.none,
    RecWeights? weights,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final fakeEntry = ReadingEntry(
      volume: Volume(
        seriesOpdsId: source.opdsId,
        title: '',
        fileName: '',
        downloadUrl: '',
        fileSizeBytes: 0,
        updatedAt: null,
      ),
      progress: ReadingProgress(
        chapterIndex: 99,
        blockIndex: 0,
        chapterCount: 100,
        updatedAt: clock,
      ),
    );
    // The SOURCE's own dropped-status or reset/dismiss feedback must not
    // apply to the seed entry — it would flip the seed's tag contribution
    // negative and turn "More like this" into anti-recommendations. Feed the
    // engine a status-neutral copy of the source and strip its feedback.
    final neutralSource = Series.fromJson({
      ...source.toJson(),
      'readingStatus': 'ongoing',
    });
    final seriesPool = [
      for (final s in allSeries)
        s.opdsId == source.opdsId ? neutralSource : s,
    ];
    final scopedFeedback = feedback == null
        ? null
        : (Map<int, RecommendationFeedback>.of(feedback)
          ..remove(source.opdsId));
    // Status overrides are used for candidate EXCLUSION only — a dropped or
    // already-caught-up series doesn't belong on "More like this". They are
    // deliberately NOT fed into the profile: the similarity seed must stay
    // the source alone, not the user's whole taste.
    final excluded = {
      for (final e in signals.statusOverrides.entries)
        if (e.key != source.opdsId &&
            (e.value == 'dropped' || e.value == 'completed'))
          e.key,
    };
    final picks = recommend(
      allSeries: seriesPool,
      readingEntries: [fakeEntry],
      feedback: scopedFeedback,
      weights: weights,
      now: clock,
    )
        // "More like this" means LIKE this — the exploration wildcard
        // belongs on the library shelf only.
        .where((r) => !r.isWildcard && !excluded.contains(r.series.opdsId))
        .toList();
    if (picks.length <= maxResults) return picks;
    return picks.sublist(0, maxResults);
  }

  /// How strongly a single reading entry counts as a "like": the chapter
  /// fraction sets the base, actual time/words spent scale it (a book you
  /// lived in for 30 hours beats one you skimmed to the same fraction),
  /// recency decays it — but finished reads keep a floor so an all-time
  /// favourite never rots to zero — and a shallow start abandoned for months
  /// tapers into a soft negative ("bounced off it").
  double _likeWeight(
    ReadingEntry entry,
    DateTime now, {
    RecSignals signals = RecSignals.none,
    double medianSeconds = 0,
    double medianWords = 0,
  }) {
    final p = entry.progress;
    final updated = p.updatedAt;
    final ageDays = updated == null ? 0 : now.difference(updated).inDays;

    // Stall taper: started shallow and untouched for 60+ days means the
    // book failed to hold them — a soft negative, strengthening to -0.2.
    if (!p.isFinished && p.isStarted && p.fraction < 0.3 && ageDays >= 60) {
      return -min(0.2, 0.1 + (ageDays - 60) / 600);
    }

    final double base;
    if (p.isFinished) {
      base = 1.0;
    } else if (p.fraction >= 0.5) {
      base = 0.7;
    } else if (p.fraction >= 0.2) {
      base = 0.4;
    } else if (p.isStarted) {
      base = 0.1;
    } else {
      base = 0;
    }
    if (base == 0) return 0;

    // Engagement multiplier: time (and words) in THIS volume vs the user's
    // own median volume. sqrt keeps it gentle; neutral (1.0) at the median
    // or when the ledger has nothing for this volume.
    final key = _volumeKey(entry.volume);
    var ratioSum = 0.0;
    var ratioCount = 0;
    final secs = signals.volumeSeconds[key] ?? 0;
    if (secs > 0 && medianSeconds > 0) {
      ratioSum += secs / medianSeconds;
      ratioCount++;
    }
    final words = signals.volumeWords[key] ?? 0;
    if (words > 0 && medianWords > 0) {
      ratioSum += words / medianWords;
      ratioCount++;
    }
    final engagement = ratioCount == 0
        ? 1.0
        : sqrt(ratioSum / ratioCount).clamp(0.6, 1.5);

    final weighted = base * engagement;
    if (updated == null || ageDays <= 0) return weighted;
    final decayed = weighted * pow(0.5, ageDays / halfLifeDays).toDouble();
    // Finished favourites decay toward a floor, not to nothing: the canon
    // should keep steering taste even when the read is a year old.
    if (p.isFinished) return max(decayed, 0.15 * weighted);
    return decayed;
  }

  /// Median ledger value across the volumes the user has actually touched —
  /// 0 when the ledger has no data for any of them.
  double _medianOver(List<ReadingEntry> entries, Map<String, int> ledger) {
    final values = <int>[
      for (final e in entries)
        if ((ledger[_volumeKey(e.volume)] ?? 0) > 0) ledger[_volumeKey(e.volume)]!,
    ]..sort();
    if (values.isEmpty) return 0;
    final mid = values.length ~/ 2;
    return values.length.isOdd
        ? values[mid].toDouble()
        : (values[mid - 1] + values[mid]) / 2.0;
  }

  static String _volumeKey(Volume v) => '${v.seriesOpdsId}/${v.fileName}';
}
