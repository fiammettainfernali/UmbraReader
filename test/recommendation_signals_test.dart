// Phase A of the recommendation overhaul: behavioural signals (time/words,
// highlights, collections, outcomes), the stall taper, the decay floor for
// finished favourites, liked/snoozed feedback, and the similarTo polarity fix.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/rec_outcome_store.dart';
import 'package:umbra_reader/services/recommendation_engine.dart';
import 'package:umbra_reader/services/recommendation_feedback_store.dart';

Series _series({
  required int id,
  required String title,
  // Distinct per series by default so the author tag (×2 weight) doesn't
  // leak affinity between fixtures probing genre/length/behaviour signals.
  String? author,
  List<String> genres = const [],
  String readingStatus = 'ongoing',
  int totalChapters = 200,
}) => Series(
  opdsId: id,
  title: title,
  author: author ?? 'Author $id',
  description: '',
  genres: genres,
  readingStatus: readingStatus,
  totalChapters: totalChapters,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

ReadingEntry _entry({
  required int seriesId,
  required ReadingProgress progress,
  String fileName = 'v1.epub',
}) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: seriesId,
    title: 'Vol',
    fileName: fileName,
    downloadUrl: '',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: progress,
);

void main() {
  const engine = RecommendationEngine();
  final today = DateTime.utc(2026, 7, 1);

  // Two liked genres compete: whichever seed carries more weight decides
  // which candidate ranks first. The pairs use different length buckets so
  // the l: tag reinforces its own pair rather than leaking across.
  List<Series> library() => [
    _series(id: 1, title: 'Seed A', genres: ['Cultivation'], totalChapters: 50),
    _series(id: 2, title: 'Seed B', genres: ['Regression']),
    _series(id: 3, title: 'Pick A', genres: ['Cultivation'], totalChapters: 50),
    _series(id: 4, title: 'Pick B', genres: ['Regression']),
  ];

  ReadingProgress halfRead(DateTime at) => ReadingProgress(
    chapterIndex: 100,
    blockIndex: 0,
    chapterCount: 200,
    updatedAt: at,
  );

  test('time-in-book outweighs an equal chapter fraction', () {
    // Both seeds are half-read on the same day; the user spent 8× longer in
    // Seed B. Without signals they tie; with time data B's genre must win.
    final entries = [
      _entry(seriesId: 1, progress: halfRead(today)),
      _entry(seriesId: 2, progress: halfRead(today)),
    ];
    final recs = engine.recommend(
      allSeries: library(),
      readingEntries: entries,
      signals: const RecSignals(
        volumeSeconds: {'1/v1.epub': 3600, '2/v1.epub': 28800},
      ),
      now: today,
    );
    expect(recs.first.series.opdsId, 4,
        reason: 'the book they lived in should steer taste');
  });

  test('highlight density boosts a series', () {
    final entries = [
      _entry(seriesId: 1, progress: halfRead(today)),
      _entry(seriesId: 2, progress: halfRead(today)),
    ];
    final recs = engine.recommend(
      allSeries: library(),
      readingEntries: entries,
      signals: const RecSignals(highlightsPerSeries: {2: 3}),
      now: today,
    );
    expect(recs.first.series.opdsId, 4,
        reason: 'saved passages are a love signal');
  });

  test('a shallow start abandoned for months turns soft-negative', () {
    final stale = today.subtract(const Duration(days: 120));
    final entries = [
      // Bounced off Seed A at 10% four months ago.
      _entry(
        seriesId: 1,
        progress: ReadingProgress(
          chapterIndex: 20,
          blockIndex: 5,
          chapterCount: 200,
          updatedAt: stale,
        ),
      ),
      // Recently loving Seed B.
      _entry(seriesId: 2, progress: halfRead(today)),
    ];
    final recs = engine.recommend(
      allSeries: library(),
      readingEntries: entries,
      now: today,
    );
    final ids = [for (final r in recs) r.series.opdsId];
    expect(ids.first, 4);
    expect(ids, isNot(contains(3)),
        reason: 'the bounced-off genre must not score positive');
  });

  test('finished favourites keep a floor instead of decaying to zero', () {
    final yearAgo = today.subtract(const Duration(days: 365));
    final entries = [
      // Finished Seed A a year ago (all-time favourite).
      _entry(
        seriesId: 1,
        progress: ReadingProgress(
          chapterIndex: 199,
          blockIndex: 0,
          chapterCount: 200,
          endReached: true,
          updatedAt: yearAgo,
        ),
      ),
    ];
    final recs = engine.recommend(
      allSeries: library(),
      readingEntries: entries,
      now: today,
    );
    expect(recs.map((r) => r.series.opdsId), contains(3),
        reason: 'a year-old finished read must still steer recommendations');
    final pick = recs.firstWhere((r) => r.series.opdsId == 3);
    expect(pick.score, greaterThan(0.1),
        reason: 'the floor keeps meaningful weight (~0.15), not dust');
  });

  test('liked feedback adds a full extra like', () {
    final entries = [
      _entry(seriesId: 1, progress: halfRead(today)),
      _entry(seriesId: 2, progress: halfRead(today)),
    ];
    final recs = engine.recommend(
      allSeries: library(),
      readingEntries: entries,
      feedback: const {2: RecommendationFeedback.liked},
      now: today,
    );
    expect(recs.first.series.opdsId, 4);
  });

  test('snoozed series leave the shelf without becoming a taste signal', () {
    final entries = [
      _entry(seriesId: 1, progress: halfRead(today)),
    ];
    final recs = engine.recommend(
      allSeries: library(),
      readingEntries: entries,
      feedback: const {4: RecommendationFeedback.snoozed},
      now: today,
    );
    final ids = [for (final r in recs) r.series.opdsId];
    expect(ids, isNot(contains(4)), reason: 'snoozed is hidden');
    expect(ids, contains(3), reason: 'other picks are unaffected');
  });

  test('shown-and-ignored candidates fade', () {
    final entries = [
      _entry(seriesId: 1, progress: halfRead(today)),
      _entry(seriesId: 2, progress: halfRead(today)),
    ];
    // Equal seeds; Pick A ignored across 8 shelf days, Pick B never shown.
    final recs = engine.recommend(
      allSeries: library(),
      readingEntries: entries,
      signals: const RecSignals(
        outcomes: {3: RecOutcome(impressions: 8, taps: 0)},
      ),
      now: today,
    );
    expect(recs.first.series.opdsId, 4,
        reason: 'a rec ignored for days must yield to a fresh one');
    // A tapped candidate is NOT penalised.
    final tapped = engine.recommend(
      allSeries: library(),
      readingEntries: entries,
      signals: const RecSignals(
        outcomes: {3: RecOutcome(impressions: 8, taps: 1)},
      ),
      now: today,
    );
    final a = tapped.firstWhere((r) => r.series.opdsId == 3);
    final b = tapped.firstWhere((r) => r.series.opdsId == 4);
    expect(a.score, closeTo(b.score, 0.0001));
  });

  test('similarTo on a dropped/reset series still finds similar picks', () {
    final source = _series(
      id: 1,
      title: 'Dropped Seed',
      genres: ['Cultivation'],
      readingStatus: 'dropped',
      totalChapters: 50, // same length bucket as Pick A
    );
    final recs = engine.similarTo(
      source: source,
      allSeries: [source, ...library().skip(1)],
      feedback: const {1: RecommendationFeedback.reset},
      now: today,
    );
    expect(recs.map((r) => r.series.opdsId), contains(3),
        reason: "the source's own status/feedback must not flip the seed "
            'negative (the anti-recommendation bug)');
    expect(recs.first.series.opdsId, 3);
  });
}
