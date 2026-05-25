import 'dart:math';

import '../models/series.dart';
import 'reading_progress_store.dart';

/// One recommended series with the score that produced it.
class Recommendation {
  const Recommendation(this.series, this.score);

  final Series series;
  final double score;
}

/// Builds a ranked list of "you might also like" suggestions from the user's
/// reading history.
///
/// Strategy: every started or finished book contributes weighted "like" mass
/// to its genre tags (and its author). Each unread series in the library is
/// then scored by how much of that mass its own genres and author capture.
/// Recent reads dominate via time decay, so the recs naturally drift with
/// current taste — no persistence or training step needed.
class RecommendationEngine {
  const RecommendationEngine({
    this.halfLifeDays = 30,
    this.maxResults = 12,
  });

  /// Days for a like's weight to halve — controls how fast tastes "drift".
  /// 30 days means a book finished a month ago counts half as much as one
  /// finished today; two months ago, a quarter; and so on.
  final int halfLifeDays;

  /// Cap on the number of recommendations returned.
  final int maxResults;

  /// Returns the top-scored series the user hasn't engaged with yet, ordered
  /// best-first. [now] is overridable for tests.
  List<Recommendation> recommend({
    required List<Series> allSeries,
    required List<ReadingEntry> readingEntries,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    if (allSeries.isEmpty || readingEntries.isEmpty) return const [];

    // Cluster reading entries by series so multiple volumes of the same
    // series don't double-count.
    final perSeries = <int, double>{};
    final engagedSeriesIds = <int>{};
    for (final entry in readingEntries) {
      engagedSeriesIds.add(entry.volume.seriesOpdsId);
      final like = _likeWeight(entry, clock);
      if (like <= 0) continue;
      perSeries.update(
        entry.volume.seriesOpdsId,
        (s) => s + like,
        ifAbsent: () => like,
      );
    }
    if (perSeries.isEmpty) return const [];

    final byId = {for (final s in allSeries) s.opdsId: s};

    // Build genre + author affinity maps from liked series.
    final genreScore = <String, double>{};
    final authorScore = <String, double>{};
    perSeries.forEach((id, score) {
      final series = byId[id];
      if (series == null) return;
      for (final raw in series.genres) {
        final key = raw.trim().toLowerCase();
        if (key.isEmpty) continue;
        genreScore.update(key, (s) => s + score, ifAbsent: () => score);
      }
      final author = series.author.trim().toLowerCase();
      if (author.isNotEmpty && author != 'unknown') {
        authorScore.update(
          author,
          (s) => s + score,
          ifAbsent: () => score,
        );
      }
    });
    if (genreScore.isEmpty && authorScore.isEmpty) return const [];

    // Score every series the user hasn't engaged with at all.
    final scored = <Recommendation>[];
    for (final series in allSeries) {
      if (engagedSeriesIds.contains(series.opdsId)) continue;
      var score = 0.0;
      for (final raw in series.genres) {
        final key = raw.trim().toLowerCase();
        if (key.isEmpty) continue;
        score += genreScore[key] ?? 0;
      }
      final author = series.author.trim().toLowerCase();
      if (author.isNotEmpty) {
        // Author is a stronger signal than a single genre tag — double it.
        score += (authorScore[author] ?? 0) * 2;
      }
      if (score > 0) scored.add(Recommendation(series, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    if (scored.length <= maxResults) return scored;
    return scored.sublist(0, maxResults);
  }

  /// How strongly a reading entry counts as a "like", time-decayed.
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
