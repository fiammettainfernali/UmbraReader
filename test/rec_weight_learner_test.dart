// Phase B of the recommendation overhaul: the per-user weight learner.
// It must hold the hand-tuned prior with no data, bend toward the feature
// group that actually predicts follow-through, and never go negative.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/rec_outcome_store.dart';
import 'package:umbra_reader/services/rec_weight_learner.dart';
import 'package:umbra_reader/services/recommendation_engine.dart';
import 'package:umbra_reader/services/recommendation_feedback_store.dart';

import 'helpers/test_db.dart';

RecGroupScores _g({
  double author = 0,
  double genre = 0,
  double keyword = 0,
  double length = 0,
}) => RecGroupScores(
  author: author,
  genre: genre,
  keyword: keyword,
  length: length,
);

Series _series({
  required int id,
  required String title,
  String? author,
  List<String> genres = const [],
  int totalChapters = 200,
}) => Series(
  opdsId: id,
  title: title,
  author: author ?? 'Author $id',
  description: '',
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: totalChapters,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

ReadingEntry _entry({
  required int seriesId,
  required double fraction,
  required DateTime at,
}) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: seriesId,
    title: 'Vol',
    fileName: 'v1.epub',
    downloadUrl: '',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: ReadingProgress(
    chapterIndex: (fraction * 199).round(),
    blockIndex: 0,
    chapterCount: 200,
    updatedAt: at,
  ),
);

void main() {
  const learner = RecWeightLearner();

  test('no examples returns the prior exactly', () {
    final w = learner.fit(const []);
    expect(w.author, RecWeights.prior.author);
    expect(w.genre, RecWeights.prior.genre);
    expect(w.keyword, RecWeights.prior.keyword);
    expect(w.length, RecWeights.prior.length);
  });

  test('learns that this user follows authors, not genres', () {
    // Recs with an author match got read; recs with only genre matches got
    // dismissed — the author weight must rise relative to prior and the
    // genre weight must fall.
    final examples = [
      for (var i = 0; i < 12; i++) ...[
        RecTrainingExample(groups: _g(author: 0.6), positive: true),
        RecTrainingExample(groups: _g(genre: 0.6), positive: false),
      ],
    ];
    final w = learner.fit(examples);
    expect(w.author, greaterThan(RecWeights.prior.author));
    expect(w.genre, lessThan(RecWeights.prior.genre));
  });

  test('learns the reverse for a trope-chaser', () {
    final examples = [
      for (var i = 0; i < 12; i++) ...[
        RecTrainingExample(groups: _g(keyword: 0.6), positive: true),
        RecTrainingExample(groups: _g(author: 0.6), positive: false),
      ],
    ];
    final w = learner.fit(examples);
    expect(w.keyword, greaterThan(RecWeights.prior.keyword));
    expect(w.author, lessThan(RecWeights.prior.author));
  });

  test('weights never go negative', () {
    final examples = [
      for (var i = 0; i < 60; i++)
        RecTrainingExample(groups: _g(length: 0.9), positive: false),
    ];
    final w = learner.fit(examples);
    expect(w.length, greaterThanOrEqualTo(0));
  });

  group('buildRecTrainingExamples', () {
    final today = DateTime.utc(2026, 7, 10);
    const engine = RecommendationEngine();

    List<Series> library() => [
      // History seed so the profile has taste for Cultivation.
      _series(id: 1, title: 'Seed', genres: ['Cultivation']),
      // Labeled series sharing that genre.
      _series(id: 2, title: 'TappedRead', genres: ['Cultivation']),
      _series(id: 3, title: 'Dismissed', genres: ['Cultivation']),
      _series(id: 4, title: 'Ignored', genres: ['Cultivation']),
      _series(id: 5, title: 'Unlabeled', genres: ['Cultivation']),
      // Labeled but sharing nothing with the profile → zero features.
      _series(id: 6, title: 'NoOverlap', genres: ['Romance']),
    ];

    test('labels tap+read positive, dismissed/ignored negative, skips rest',
        () {
      final examples = buildRecTrainingExamples(
        engine: engine,
        allSeries: library(),
        readingEntries: [
          _entry(seriesId: 1, fraction: 0.6, at: today),
          _entry(seriesId: 2, fraction: 0.5, at: today), // read after tap
        ],
        feedback: const {3: RecommendationFeedback.dismissed},
        signals: const RecSignals(
          outcomes: {
            2: RecOutcome(impressions: 3, taps: 1),
            4: RecOutcome(impressions: 6, taps: 0), // shown 6 days, ignored
          },
        ),
        now: today,
      );
      // id 2 → positive, id 3 → negative, id 4 → negative; id 5 unlabeled,
      // id 6 zero-feature (Romance shares nothing with the taste profile).
      expect(examples.length, 3);
      expect(examples.where((e) => e.positive).length, 1);
      expect(examples.where((e) => !e.positive).length, 2);
    });

    test('a labeled series does not leak its own affinity into its features',
        () {
      // The only taste history IS the labeled series itself: with leakage
      // its genre feature would be strongly positive; excluded, there is no
      // profile left at all and no usable example.
      final examples = buildRecTrainingExamples(
        engine: engine,
        allSeries: [
          _series(id: 2, title: 'TappedRead', genres: ['Cultivation']),
          _series(id: 7, title: 'Other', genres: ['Romance']),
        ],
        readingEntries: [_entry(seriesId: 2, fraction: 0.5, at: today)],
        signals: const RecSignals(
          outcomes: {2: RecOutcome(impressions: 2, taps: 1)},
        ),
        now: today,
      );
      expect(examples, isEmpty,
          reason: 'self-affinity must not become a training feature');
    });
  });

  group('RecWeightsStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await useInMemoryDatabase();
    });

    tearDown(AppDatabase.reset);

    test('round-trips weights and defaults to the prior', () async {
      final store = RecWeightsStore();
      expect((await store.load()).author, RecWeights.prior.author);
      await store.save(
        const RecWeights(author: 3.1, genre: 0.4, keyword: 1.7, length: 0.0),
      );
      final back = await store.load();
      expect(back.author, 3.1);
      expect(back.genre, 0.4);
      expect(back.keyword, 1.7);
      expect(back.length, 0.0);
    });
  });
}
