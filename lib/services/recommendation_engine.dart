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

  /// The user's own in-app reading status per series — the one status the
  /// engine trusts unconditionally. Vocabulary: 'completed' (a full like,
  /// even with zero in-app reading — e.g. a series listened to entirely in
  /// an external reader and marked caught-up), 'dropped' (strong negative),
  /// 'ongoing' (neutral).
  ///
  /// `Series.readingStatus` is the *server's* field and does not mean the
  /// same thing. Its 'completed' says the novel has finished PUBLISHING,
  /// and a one-time Novel Grabber migration stamped it on shelves of books
  /// that were never opened anywhere — so the engine honours a server
  /// 'completed' only when an in-app read backs it up. Its 'dropped' does
  /// come from a real user-facing picker, and is taken at face value.
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

  /// Weights for "more like THIS book", which is a different question from
  /// "what should this reader be shown next".
  ///
  /// The learned vector answers the second. It is fitted on which feature
  /// group predicts this reader ACTING on a shelf pick, and it is free to
  /// turn genre right down if genre is not what moves them — perfectly
  /// reasonable for a shelf, and wrong for a similarity list, where it
  /// stops similarity being about similarity. Worse on an install still
  /// carrying the collapsed vector the old learner could produce (genre
  /// 0.0, length 0.0): ranking fell back to author matches and
  /// description-keyword noise, which is how an action cultivation novel
  /// came to suggest age regression.
  ///
  /// Genre leads keywords here deliberately. Two books sharing a genre are
  /// alike in the way a reader means by "similar"; two sharing a word in
  /// their blurb very often are not.
  static const similarity = RecWeights(
    author: 2.0,
    genre: 1.5,
    keyword: 0.6,
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

  double _affinity(String tag) => (_tagScore[tag] ?? 0) * (_tagIdf[tag] ?? 1.0);

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
      keyword: _squash(keywordCount == 0 ? 0 : keywordSum / sqrt(keywordCount)),
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
/// dropped books push negative. That history is decayed on TWO timescales
/// at once — a settled "core" lane and a week-long "fast" lane — and the
/// two are blended by how far apart they have actually drifted, so a real
/// change of heart moves the shelf within days while a quiet week leaves it
/// alone. The final ranking applies a diversity guard so a single author or
/// genre can't monopolise the shelf, and falls back to recently-updated
/// series when there's no history yet.
class RecommendationEngine {
  const RecommendationEngine({
    this.halfLifeDays = 60,
    this.fastHalfLifeDays = 7,
    this.maxResults = 12,
    this.maxPerAuthor = 2,
    this.maxPerGenre = 3,
    this.keywordsPerSeries = 12,
  });

  /// Days for a like's weight to halve in the settled "core" lane. The
  /// finished-favourite floor lives in this lane, so the canon keeps
  /// steering taste for as long as it is the canon.
  final int halfLifeDays;

  /// Days for a like's weight to halve in the "fast" lane — about a week,
  /// so this lane is essentially "what are they reading right now". It
  /// carries no floor; see [_blendLanes] for why that matters.
  final int fastHalfLifeDays;

  /// Cap on the number of recommendations returned.
  final int maxResults;

  /// Max picks by the same author in the result.
  final int maxPerAuthor;

  /// Max picks sharing the same primary genre in the result.
  final int maxPerGenre;

  /// Top-K TF-IDF keywords pulled from each series description.
  final int keywordsPerSeries;

  /// Chapters at which the depth term in [_likeWeight] reaches half its
  /// ceiling.
  ///
  /// Public because the learner has to agree with the engine about what
  /// counts as having read something: two copies of this number would drift
  /// apart, and the symptom would be a book the ranking treats as read and
  /// the learner treats as untouched.
  static const depthHalfChapters = 60;

  /// The band the fast lane's share of the blended taste vector moves in.
  /// Never below the floor — some recency always counts — and never above
  /// the ceiling, so a strange fortnight can reorder the shelf but can
  /// never erase years of reading.
  ///
  /// Derived at SERIES granularity, the only granularity that means
  /// anything here: a series' volumes are summed and then divided by
  /// √(contributing volumes), so a twelve-volume favourite is worth about
  /// √12 ≈ 3.5 single-volume reads rather than twelve of them — and this
  /// reader's webnovels are multi-volume as a rule, so counting volumes
  /// would overstate the settled side by up to √n.
  ///
  /// The worked case: twelve fantasy series finished ~200 days ago all sit
  /// on the core lane's 0.15 floor, so g:fantasy = 12 × 0.15 = 1.80 in the
  /// core lane and ≈0 in the fast one. Four sci-fi series opened this week
  /// at a dozen chapters each contribute 4 × 0.167 × 0.97 ≈ 0.64 to the
  /// core lane and 4 × 0.167 × 0.74 ≈ 0.50 to the fast one. With the fast
  /// lane rescaled onto the core's magnitude (×4.3 for that split), sci-fi
  /// passes fantasy at α ≈ 0.35 before IDF and sooner after it. The drift
  /// measured for that split is ≈0.66, which lands α ≈ 0.51 — comfortably
  /// past the crossing, and still a minority share.
  static const _driftAlphaMin = 0.15;
  static const _driftAlphaMax = 0.70;

  /// A fast-lane value at least this big still means "read lately" — about
  /// three weeks of a solid read, or one week of a skim, at a 7-day
  /// half-life.
  static const _recentLaneFloor = 0.05;

  /// Distinct recent series needed before the measured drift is allowed to
  /// scale the blend. Below this the fast lane is one or two books and its
  /// direction is noise, so the blend is pinned to [_driftAlphaMin]: one
  /// odd night must not repaint the whole shelf.
  static const _minRecentSeries = 3;

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
      // Dismissed, snoozed and reset cards are in [engagedIds] even with
      // nothing read yet, and the fallback is the one path that never
      // consulted it — so on a fresh library the card you just sent away
      // came straight back at the top of the shelf.
      final fallback =
          [
            for (final s in allSeries)
              if (!profile.engagedIds.contains(s.opdsId)) s,
          ]..sort((a, b) {
            final at = a.updatedAt;
            final bt = b.updatedAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
      return [for (final s in fallback.take(maxResults)) Recommendation(s, 0)];
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
        final daySeed = clock.year * 10000 + clock.month * 100 + clock.day;
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

    // Engaged means STARTED, not merely touched. The reader writes a
    // progress row the instant a book is opened, so building this from the
    // existence of a row banned a series from recommendations for good
    // because it was opened once and closed on the first page — a peek that
    // contributed no taste at all bought a permanent exclusion.
    final startedIds = <int>{
      for (final e in entriesBySeries.entries)
        if (e.value.any((entry) => entry.progress.isStarted)) e.key,
    };
    final engagedIds = <int>{...startedIds};

    // The same history decayed on two timescales at once. `core` is the
    // settled taste (see [halfLifeDays], finished favourites floored);
    // `fast` is this week's ([fastHalfLifeDays], no floor). Everything that
    // is not a decay — statuses, highlights, collections, card feedback —
    // is applied identically to both, so the only thing the lanes can
    // disagree about is age, which is exactly what the drift measure below
    // is supposed to read.
    final signedCore = <int, double>{};
    final signedFast = <int, double>{};
    // The fast lane's READ component alone, per series, before any floor or
    // judgement is layered on. Only a dated read can say "lately", so this
    // is what the recency count below is allowed to look at.
    final fastRead = <int, double>{};

    for (final series in allSeries) {
      if (excludeSeriesIds.contains(series.opdsId)) continue;
      final entries = entriesBySeries[series.opdsId];
      // The user's own in-app status outranks the server-side one. The
      // server's 'completed' is a different fact — the NOVEL has finished
      // publishing — and a Novel Grabber migration seeded it onto books
      // that were never opened; read as a verdict it handed those an
      // undecaying +1.0, several times louder than a genuinely finished
      // read, and banned them from the shelf as "engaged". So it only
      // counts once an in-app read backs it up. Every other server status
      // ('dropped' above all, which comes from a real picker) is honoured.
      final override = signals.statusOverrides[series.opdsId];
      final serverStatus = series.readingStatus.trim().toLowerCase();
      final backed = entries?.any((e) => e.progress.isStarted) ?? false;
      final status =
          override?.trim().toLowerCase() ??
          (serverStatus == 'completed' && !backed ? '' : serverStatus);
      final userFeedback = feedback?[series.opdsId];
      var core = 0.0;
      var fast = 0.0;
      if (entries != null) {
        // Sum per-volume like weights, then dampen with √n so a 10-volume
        // binge doesn't drown out single-volume favourites.
        var aggCore = 0.0;
        var aggFast = 0.0;
        var contributing = 0;
        for (final entry in entries) {
          final weight = _likeWeight(
            entry,
            clock,
            halfLife: halfLifeDays,
            keepFinishedFloor: true,
            signals: signals,
            medianSeconds: medianSeconds,
            medianWords: medianWords,
          );
          aggCore += weight;
          aggFast += _likeWeight(
            entry,
            clock,
            halfLife: fastHalfLifeDays,
            keepFinishedFloor: false,
            signals: signals,
            medianSeconds: medianSeconds,
            medianWords: medianWords,
          );
          // The two lanes differ only by decay, which cannot change a
          // sign, so counting contributors once off the core lane keeps
          // the damping identical in both.
          if (weight > 0) contributing++;
        }
        // Only volumes that actually earned something count towards the
        // damping. Dividing by every row instead meant one volume read out
        // of twenty downloaded scored ~0.22 rather than ~1.0, so a series
        // the user is really reading steered taste less than a skim of a
        // single-volume book. Stalled volumes are excluded too: they are
        // already negative in the sum, and putting them in the divisor
        // would shrink the penalty they are there to apply. `> 1` also
        // keeps the divisor away from zero when nothing contributed.
        if (contributing > 1) {
          final damping = sqrt(contributing) / contributing;
          aggCore *= damping;
          aggFast *= damping;
        }
        // What the READING alone says on the fast lane, kept before the
        // floors and judgements below. Recency is counted off this: a
        // status mark carries no timestamp, so letting it through would
        // report a series as read-this-week forever and freeze the blend.
        if (aggFast > 0) fastRead[series.opdsId] = aggFast;
        if (status == 'completed') {
          // User-marked complete → at least a full "like" even if the
          // chapter-count guess says otherwise.
          if (aggCore < 1.0) aggCore = 1.0;
          if (aggFast < 1.0) aggFast = 1.0;
          // Caught-up means done with it, so it must not be recommended
          // back. Membership used to come free from the progress row's
          // existence; now that engagement means real progress, a series
          // marked caught-up after a single unstarted open needs saying.
          engagedIds.add(series.opdsId);
        }
        core = aggCore;
        fast = aggFast;
      } else if (status == 'completed') {
        // Marked caught-up with ZERO in-app reading entries — the
        // listened-elsewhere binge (e.g. Share-story → an external reader).
        // Only the user's own override can reach here now; an unbacked
        // server 'completed' was neutralised above.
        // Consuming everything available is a full like; without a read
        // timestamp it doesn't decay, matching the finished-favourite floor
        // in spirit.
        core = 1.0;
        fast = 1.0;
        engagedIds.add(series.opdsId);
      }
      // Everything from here down is a judgement, not a read: it happened
      // at no particular timescale, so both lanes get the same value and
      // the same verdict (decided off the core lane). Letting the lanes
      // disagree about a dropped or dismissed series would have shown up
      // as fake drift and pushed the blend around for no reason.
      //
      // Highlight density: saved passages are a strong love signal, worth up
      // to +0.3 on top of whatever the read itself earned.
      final highlights = signals.highlightsPerSeries[series.opdsId] ?? 0;
      if (highlights > 0) {
        final bonus = min(0.3, 0.1 * highlights);
        core += bonus;
        fast += bonus;
        engagedIds.add(series.opdsId);
      }
      // Curating a series into a collection is explicit interest.
      if (signals.collectionSeriesIds.contains(series.opdsId)) {
        core += 0.25;
        fast += 0.25;
        engagedIds.add(series.opdsId);
      }
      // Hiding from the Continue shelf is a mild "enough of this for now".
      if (entries != null &&
          entries.any(
            (e) => signals.hiddenVolumeKeys.contains(_volumeKey(e.volume)),
          )) {
        core -= 0.15;
        fast -= 0.15;
      }
      if (status == 'dropped') {
        // User-marked dropped → flip to a negative signal.
        final flipped = -(core.abs().clamp(0.5, double.infinity));
        core = flipped;
        fast = flipped;
        engagedIds.add(series.opdsId);
      }
      // Explicit per-card feedback: reset is the strongest "no thanks",
      // dismiss a milder one; a 👍 is a full extra like on top of the read
      // history (an explicit like also supersedes an earlier negative);
      // snoozed just leaves the engaged set to keep the series off shelves.
      switch (userFeedback) {
        case RecommendationFeedback.reset:
          core = -0.7;
          fast = -0.7;
          engagedIds.add(series.opdsId);
        case RecommendationFeedback.dismissed:
          // Genuine re-engagement outranks a card-level "not interested":
          // if they've substantially READ it since, the read wins.
          if (core < 0.5) {
            core = -0.3;
            fast = -0.3;
          }
          engagedIds.add(series.opdsId);
        case RecommendationFeedback.liked:
          final liked = max(core, 0) + 1.0;
          core = liked;
          fast = liked;
          engagedIds.add(series.opdsId);
        case RecommendationFeedback.snoozed:
          engagedIds.add(series.opdsId);
        case null:
          break;
      }
      if (core != 0) signedCore[series.opdsId] = core;
      if (fast != 0) signedFast[series.opdsId] = fast;
    }

    // Accumulate signed affinity per content tag, remembering which positive
    // seed carries each tag hardest (for "like X" reason lines). Reason
    // lines are drawn from the CORE lane on purpose: "like X" should name a
    // book they know they love, not whatever they happened to open on
    // Tuesday.
    final coreTags = <String, double>{};
    final tagTopSeed = <String, int>{};
    final tagTopContribution = <String, double>{};
    final seedTitles = <int, String>{};
    signedCore.forEach((id, score) {
      final series = byId[id];
      if (series == null) return;
      if (score > 0) seedTitles[id] = series.title;
      for (final tag in _tagsFor(series, keywords[id] ?? const [])) {
        coreTags.update(tag, (s) => s + score, ifAbsent: () => score);
        if (score > (tagTopContribution[tag] ?? 0)) {
          tagTopContribution[tag] = score;
          tagTopSeed[tag] = id;
        }
      }
    });
    final fastTags = <String, double>{};
    signedFast.forEach((id, score) {
      final series = byId[id];
      if (series == null) return;
      for (final tag in _tagsFor(series, keywords[id] ?? const [])) {
        fastTags.update(tag, (s) => s + score, ifAbsent: () => score);
      }
    });

    // How much of the blended taste vector the fast lane gets, decided by
    // the divergence actually measured between the lanes rather than by a
    // constant: a constant either ignores a real change of heart or churns
    // the shelf when nothing has changed.
    var recentSeries = 0;
    for (final value in fastRead.values) {
      if (value >= _recentLaneFloor) recentSeries++;
    }
    final double alpha;
    if (recentSeries == 0) {
      // Nothing read lately at all. Skip the blend outright — the fast
      // lane is then numerical dust from year-old reads, and rescaling
      // dust onto the core lane's magnitude would amplify it into a
      // direction the reader never took.
      alpha = 0.0;
    } else if (recentSeries < _minRecentSeries) {
      alpha = _driftAlphaMin;
    } else {
      alpha =
          _driftAlphaMin +
          (_driftAlphaMax - _driftAlphaMin) * _genreDrift(fastTags, coreTags);
    }

    return RecTasteProfile._(
      tagScore: _blendLanes(coreTags, fastTags, alpha),
      tagIdf: tagIdf,
      keywords: keywords,
      tagTopSeed: tagTopSeed,
      seedTitles: seedTitles,
      engagedIds: engagedIds,
      // Something read, or something liked — not merely a non-empty map.
      // Card feedback writes a negative, so a reader with nothing read who
      // dismissed one card counted as having history, took the scoring path
      // and got an empty shelf: every score there needs a positive affinity
      // to clear, and a lone "no thanks" supplies none.
      //
      // A started read counts however it is signed, though. Reading a book
      // and then resetting it leaves one negative value and no positives,
      // and that reader HAS a taste — a negative one, which the scoring
      // path is exactly what honours.
      hasHistory: startedIds.isNotEmpty || signedCore.values.any((v) => v > 0),
    );
  }

  /// 1 − cosine between the two lanes' GENRE vectors, clamped to 0..1: how
  /// far this week points away from the settled taste.
  ///
  /// Genres only. At a seven-day window the keyword tags are mostly the
  /// vocabulary of one or two blurbs, and the author and length tags move
  /// with the genres anyway — including them would measure the same drift
  /// three times and drown the one dimension that means something.
  double _genreDrift(Map<String, double> fast, Map<String, double> core) {
    var dot = 0.0;
    var fastSq = 0.0;
    var coreSq = 0.0;
    for (final tag in {...fast.keys, ...core.keys}) {
      if (!tag.startsWith('g:')) continue;
      final f = fast[tag] ?? 0.0;
      final c = core[tag] ?? 0.0;
      dot += f * c;
      fastSq += f * f;
      coreSq += c * c;
    }
    if (fastSq <= 0 || coreSq <= 0) return 0.0;
    return (1 - dot / (sqrt(fastSq) * sqrt(coreSq))).clamp(0.0, 1.0);
  }

  /// Mixes the lanes into the single tag map the scorer reads: [alpha]
  /// parts fast to (1 − [alpha]) parts core.
  ///
  /// The fast lane is rescaled onto the core lane's magnitude first.
  /// Without that, [alpha] would not be a mix at all — this reader has 883
  /// books behind them and a week in front, so the core sums are an order
  /// of magnitude larger and the fast lane stays a rounding error however
  /// high [alpha] goes. Rescaled, [alpha] means what it says: this share of
  /// the taste vector is what they are reading now.
  ///
  /// This happens BEFORE `RecTasteProfile._squash`. Either lane saturates
  /// past a pre-squash sum of about 10, so mixing squashed values would
  /// have flattened the fast lane into invisibility exactly when it had
  /// most to say.
  ///
  /// When the lanes agree the core lane comes back untouched: entries read
  /// today decay to the same value on both timescales, so identical lanes
  /// give a scale of 1 and a blend that is the identity.
  Map<String, double> _blendLanes(
    Map<String, double> core,
    Map<String, double> fast,
    double alpha,
  ) {
    if (alpha <= 0) return core;
    final coreNorm = _norm(core.values);
    final fastNorm = _norm(fast.values);
    if (coreNorm <= 0 || fastNorm <= 0) return core;
    final scale = coreNorm / fastNorm;
    final blended = <String, double>{};
    for (final tag in {...core.keys, ...fast.keys}) {
      final c = core[tag] ?? 0.0;
      final f = fast[tag] ?? 0.0;
      blended[tag] = (1 - alpha) * c + alpha * scale * f;
    }
    return blended;
  }

  static double _norm(Iterable<double> values) {
    var sum = 0.0;
    for (final value in values) {
      sum += value * value;
    }
    return sqrt(sum);
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
      result[id] = [for (final e in scored.take(keywordsPerSeries)) e.key];
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
  ///
  /// Ranks under [RecWeights.similarity] unless told otherwise, NOT under
  /// the reader's learned vector: see that constant for why handing this
  /// the shelf's weights makes it answer the wrong question.
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
      for (final s in allSeries) s.opdsId == source.opdsId ? neutralSource : s,
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
    // Without the diversity guard, which is a variety rule — and variety is
    // the opposite of what this list is for. recommend() caps picks at
    // maxPerGenre (3) and maxPerAuthor (2) so the Discover shelf cannot
    // become six of the same thing; applied here it guaranteed that half of
    // a six-pick "more like this" came from OTHER genres however well the
    // top three matched. On an action cultivation novel that is three
    // cultivation novels and then whatever scored next, which is how age
    // regression arrived on the shelf. Same author and same genre are the
    // two best answers to "what else is like this", so neither is throttled.
    final similarity = RecommendationEngine(
      halfLifeDays: halfLifeDays,
      fastHalfLifeDays: fastHalfLifeDays,
      maxResults: this.maxResults,
      maxPerAuthor: this.maxResults,
      maxPerGenre: this.maxResults,
      keywordsPerSeries: keywordsPerSeries,
    );
    final picks = similarity
        .recommend(
          allSeries: seriesPool,
          readingEntries: [fakeEntry],
          feedback: scopedFeedback,
          weights: weights ?? RecWeights.similarity,
          now: clock,
        )
        // "More like this" means LIKE this — the exploration wildcard
        // belongs on the library shelf only.
        .where((r) => !r.isWildcard && !excluded.contains(r.series.opdsId))
        .toList();
    if (picks.length <= maxResults) return picks;
    return picks.sublist(0, maxResults);
  }

  /// How strongly a single reading entry counts as a "like" on ONE
  /// timescale: how much of the book they actually consumed sets the base,
  /// actual time/words spent scale it (a book you lived in for 30 hours
  /// beats one you skimmed to the same fraction), [halfLife] decays it —
  /// with a floor under finished reads when [keepFinishedFloor], so an
  /// all-time favourite never rots to zero — and a shallow start abandoned
  /// for months tapers into a soft, fading negative ("bounced off it").
  double _likeWeight(
    ReadingEntry entry,
    DateTime now, {
    required int halfLife,
    required bool keepFinishedFloor,
    RecSignals signals = RecSignals.none,
    double medianSeconds = 0,
    double medianWords = 0,
  }) {
    final p = entry.progress;
    final updated = p.updatedAt;
    final ageDays = updated == null ? 0 : now.difference(updated).inDays;

    // Engagement multiplier: time (and words) in THIS volume vs the user's
    // own median volume. Computed before the stall taper because it is the
    // evidence that decides whether an untouched book was abandoned or is
    // merely waiting.
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
    final ratio = ratioCount == 0 ? 0.0 : ratioSum / ratioCount;
    // sqrt keeps it gentle; neutral (1.0) at the median or when the ledger
    // has nothing for this volume. The ceiling is 2.5 rather than the old
    // 1.5 because at 1.5 the fraction always decided: a volume the reader
    // spent four times their usual evening in could still not out-weigh a
    // skim that happened to reach a higher percentage.
    final engagement = ratioCount == 0 ? 1.0 : sqrt(ratio).clamp(0.6, 2.5);

    // Depth: chapters actually read, independent of how long the book is.
    // x/(x+60) — 7 chapters ≈ 0.1 (the old shallow-start tier), 40 ≈ 0.4,
    // 60 = 0.5, a whole 250-chapter Novel Grabber volume ≈ 0.81, never
    // reaching the 1.0 that finishing earns. Without it, forty chapters of
    // a packed volume scored 0.1 — the same as opening chapter two and
    // leaving — because 40 of 250 is still a small fraction, and the
    // engagement multiplier was capped too low to say otherwise.
    final chaptersRead = p.chapterIndex;
    final depth = chaptersRead / (chaptersRead + depthHalfChapters);

    final double fractionBase;
    if (p.isFinished) {
      fractionBase = 1.0;
    } else if (p.fraction >= 0.5) {
      fractionBase = 0.7;
    } else if (p.fraction >= 0.2) {
      fractionBase = 0.4;
    } else if (p.isStarted) {
      fractionBase = 0.1;
    } else {
      fractionBase = 0;
    }
    final base = max(fractionBase, depth);
    if (base == 0) return 0;

    // Stall taper: started, still shallow, untouched for 60+ days — the
    // book failed to hold them. Two cases that look identical from outside
    // are deliberately spared, because for this reader both are routine:
    //
    //  • A long favourite paused between chapter drops. 300 chapters into
    //    a 1500-chapter novel is a 0.2 fraction, which used to taper into
    //    a negative against the reader's own favourite genre; the depth
    //    term now carries `base` well clear of the threshold.
    //  • A book they sank real time into before drifting off. That is
    //    gated on POSITIVE evidence (`ratioCount > 0`), never on
    //    `engagement`, which falls back to 1.0 whenever the ledger has no
    //    row for the volume — gating on the multiplier would have spared
    //    every volume the ledger never saw, which is most of them, and
    //    disabled the taper altogether.
    //
    // The negative also fades with age now (90-day half-life from its -0.1
    // peak) instead of growing to a permanent -0.2: under the old curve a
    // book set aside two years ago shouted twice as loud as one set aside
    // last month, so old mistakes only ever got louder.
    if (!p.isFinished &&
        p.isStarted &&
        base < 0.3 &&
        ageDays >= 60 &&
        !(ratioCount > 0 && ratio >= 1.0)) {
      return -0.1 * pow(0.5, (ageDays - 60) / 90).toDouble();
    }

    final weighted = base * engagement;
    if (updated == null || ageDays <= 0) return weighted;
    final decayed = weighted * pow(0.5, ageDays / halfLife).toDouble();
    // Finished favourites decay toward a floor, not to nothing: the canon
    // should keep steering taste even when the read is a year old. The fast
    // lane passes keepFinishedFloor: false — a floor there would pin the
    // canon permanently into the lane whose whole job is to say what has
    // changed, leaving no divergence left to measure.
    if (p.isFinished && keepFinishedFloor) return max(decayed, 0.15 * weighted);
    return decayed;
  }

  /// Median ledger value across the volumes the user has actually touched —
  /// 0 when the ledger has no data for any of them.
  double _medianOver(List<ReadingEntry> entries, Map<String, int> ledger) {
    final values = <int>[
      for (final e in entries)
        if ((ledger[_volumeKey(e.volume)] ?? 0) > 0)
          ledger[_volumeKey(e.volume)]!,
    ]..sort();
    if (values.isEmpty) return 0;
    final mid = values.length ~/ 2;
    return values.length.isOdd
        ? values[mid].toDouble()
        : (values[mid - 1] + values[mid]) / 2.0;
  }

  static String _volumeKey(Volume v) => '${v.seriesOpdsId}/${v.fileName}';
}
