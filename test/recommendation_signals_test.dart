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

  test('IDF: a rare shared genre outranks a ubiquitous one', () {
    // 'Fantasy' is on every series (uninformative); 'Necromancy' is rare.
    // The user read one book carrying both; the candidate sharing the RARE
    // genre must outrank the one sharing only the ubiquitous genre.
    final lib = [
      _series(id: 1, title: 'Seed', genres: ['Fantasy', 'Necromancy']),
      _series(id: 2, title: 'RareMatch', genres: ['Fantasy', 'Necromancy']),
      _series(id: 3, title: 'CommonOnly', genres: ['Fantasy']),
      _series(id: 4, title: 'Filler A', genres: ['Fantasy']),
      _series(id: 5, title: 'Filler B', genres: ['Fantasy']),
    ];
    final recs = engine.recommend(
      allSeries: lib,
      readingEntries: [_entry(seriesId: 1, progress: halfRead(today))],
      now: today,
    );
    expect(recs.first.series.opdsId, 2);
  });

  test('unknown length is not a matchable tag', () {
    final lib = [
      _series(id: 1, title: 'Seed', genres: ['Cultivation'],
          totalChapters: 0),
      // Shares ONLY the unknown length bucket with the seed — must not match.
      _series(id: 2, title: 'AlsoUnknown', genres: ['Romance'],
          totalChapters: 0),
      _series(id: 3, title: 'GenreMatch', genres: ['Cultivation']),
    ];
    final recs = engine.recommend(
      allSeries: lib,
      readingEntries: [_entry(seriesId: 1, progress: halfRead(today))],
      now: today,
    );
    final ids = [for (final r in recs) r.series.opdsId];
    expect(ids, contains(3));
    expect(ids, isNot(contains(2)),
        reason: 'two series with missing metadata do not "match"');
  });

  test('bigram keywords carry two-word concepts', () {
    Series withDesc(int id, String title, String desc) => Series(
      opdsId: id, title: title, author: 'Author $id', description: desc,
      genres: const [], readingStatus: 'ongoing', totalChapters: 200,
      downloadedChapters: 0, coverUrl: null, updatedAt: null,
      directEpubUrl: null, volumesFeedUrl: null,
    );
    // Both candidates mention the words; only one preserves the CONCEPT
    // "martial arts" as an adjacent pair.
    final lib = [
      withDesc(1, 'Seed',
          'A cripple rises through martial arts tournaments and sect wars.'),
      withDesc(2, 'ConceptMatch',
          'Martial arts cultivation in a ruthless sect tournament.'),
      withDesc(3, 'WordSoup',
          'Martial law and fine arts in a peaceful academy of painters.'),
      withDesc(4, 'Unrelated',
          'Corporate romance about spreadsheets and quarterly meetings.'),
    ];
    final recs = engine.recommend(
      allSeries: lib,
      readingEntries: [_entry(seriesId: 1, progress: halfRead(today))],
      now: today,
    );
    expect(recs, isNotEmpty);
    expect(recs.first.series.opdsId, 2,
        reason: 'the adjacent-pair bigram must outrank scattered words');
  });

  test('learned weights change the ranking', () {
    // Candidate 3 matches the seed's AUTHOR; candidate 4 matches its genre.
    final lib = [
      _series(id: 1, title: 'Seed', author: 'Shared Author',
          genres: ['Cultivation']),
      _series(id: 3, title: 'AuthorMatch', author: 'Shared Author',
          genres: ['Romance']),
      _series(id: 4, title: 'GenreMatch', genres: ['Cultivation']),
    ];
    final entries = [_entry(seriesId: 1, progress: halfRead(today))];
    // Under the prior (author 2.0) the author match wins…
    final withPrior = engine.recommend(
      allSeries: lib, readingEntries: entries, now: today,
    );
    expect(withPrior.first.series.opdsId, 3);
    // …but a learner that discovered this user ignores author matches
    // flips the order.
    final genreLover = engine.recommend(
      allSeries: lib,
      readingEntries: entries,
      weights: const RecWeights(
        author: 0.1, genre: 2.5, keyword: 1.0, length: 0.5,
      ),
      now: today,
    );
    expect(genreLover.first.series.opdsId, 4);
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
