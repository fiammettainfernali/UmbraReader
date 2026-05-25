import 'dart:math';

import '../models/series.dart';
import '../models/volume.dart';
import 'reading_progress_store.dart';

/// One recommended series with the score that produced it.
class Recommendation {
  const Recommendation(this.series, this.score);

  final Series series;
  final double score;
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
    this.keywordsPerSeries = 8,
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
  /// [now] is overridable for tests.
  List<Recommendation> recommend({
    required List<Series> allSeries,
    required List<ReadingEntry> readingEntries,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    if (allSeries.isEmpty) return const [];

    final byId = {for (final s in allSeries) s.opdsId: s};
    final keywords = _computeKeywords(allSeries);

    // Group reading entries by series so multiple volumes of one series fold
    // into a single signal.
    final entriesBySeries = <int, List<ReadingEntry>>{};
    for (final entry in readingEntries) {
      entriesBySeries
          .putIfAbsent(entry.volume.seriesOpdsId, () => <ReadingEntry>[])
          .add(entry);
    }

    final engagedIds = <int>{...entriesBySeries.keys};
    final signedSeries = <int, double>{};

    for (final series in allSeries) {
      final status = series.readingStatus.trim().toLowerCase();
      final entries = entriesBySeries[series.opdsId];
      double signed;
      if (entries == null) {
        // No reading entry — only the explicit "dropped" status carries any
        // signal here, and it's a negative one.
        if (status == 'dropped') {
          signed = -0.5;
          engagedIds.add(series.opdsId);
        } else {
          continue;
        }
      } else {
        // Sum per-volume like weights, then dampen with √n so a 10-volume
        // binge doesn't drown out single-volume favourites.
        var aggregated = 0.0;
        for (final entry in entries) {
          aggregated += _likeWeight(entry, clock);
        }
        if (entries.length > 1) {
          aggregated = aggregated * sqrt(entries.length) / entries.length;
        }
        if (status == 'completed') {
          // User-marked complete → at least a full "like" even if the
          // chapter-count guess says otherwise.
          if (aggregated < 1.0) aggregated = 1.0;
        }
        if (status == 'dropped') {
          // User-marked dropped → flip to negative signal.
          aggregated = -(aggregated.abs().clamp(0.5, double.infinity));
        }
        signed = aggregated;
      }
      if (signed != 0) signedSeries[series.opdsId] = signed;
    }

    // Cold start: nothing engaged → recommend recently-updated series so the
    // shelf isn't blank on a fresh install.
    if (signedSeries.isEmpty) {
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

    // Accumulate signed affinity per content tag.
    final tagScore = <String, double>{};
    signedSeries.forEach((id, score) {
      final series = byId[id];
      if (series == null) return;
      for (final tag in _tagsFor(series, keywords[id] ?? const [])) {
        tagScore.update(tag, (s) => s + score, ifAbsent: () => score);
      }
    });

    // Score every series the user hasn't engaged with.
    final scored = <Recommendation>[];
    for (final series in allSeries) {
      if (engagedIds.contains(series.opdsId)) continue;
      var score = 0.0;
      for (final tag in _tagsFor(series, keywords[series.opdsId] ?? const [])) {
        score += tagScore[tag] ?? 0;
      }
      if (score > 0) scored.add(Recommendation(series, score));
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
    return result;
  }

  /// Iterates every affinity tag for a series. Author is yielded twice so
  /// matching the author counts roughly double a single genre tag.
  Iterable<String> _tagsFor(Series series, List<String> keywords) sync* {
    for (final raw in series.genres) {
      final key = raw.trim().toLowerCase();
      if (key.isNotEmpty) yield 'g:$key';
    }
    final author = series.author.trim().toLowerCase();
    if (author.isNotEmpty && author != 'unknown') {
      yield 'a:$author';
      yield 'a:$author';
    }
    yield 'l:${_lengthBucket(series.totalChapters)}';
    for (final kw in keywords) {
      yield 'k:$kw';
    }
  }

  String _lengthBucket(int chapters) {
    if (chapters <= 0) return 'unknown';
    if (chapters < 100) return 'short';
    if (chapters < 500) return 'medium';
    if (chapters < 2000) return 'long';
    return 'huge';
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
  };

  List<String> _tokenize(String text) {
    final tokens = <String>[];
    for (final raw in text.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      if (raw.length < 4) continue;
      if (_stopwords.contains(raw)) continue;
      tokens.add(raw);
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
    final picks = recommend(
      allSeries: allSeries,
      readingEntries: [fakeEntry],
      now: clock,
    );
    if (picks.length <= maxResults) return picks;
    return picks.sublist(0, maxResults);
  }

  /// How strongly a single reading entry counts as a "like", time-decayed.
  double _likeWeight(ReadingEntry entry, DateTime now) {
    final p = entry.progress;
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
    final updated = p.updatedAt;
    if (updated == null) return base;
    final ageDays = now.difference(updated).inDays;
    if (ageDays <= 0) return base;
    return base * pow(0.5, ageDays / halfLifeDays).toDouble();
  }
}
