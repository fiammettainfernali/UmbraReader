// Phase B of the recommendation overhaul: the per-user weight learner.
// It must hold the hand-tuned prior with no data, bend toward the feature
// group that actually predicts follow-through, and keep every group above
// a floor — including for a reader who only ever reads, never taps a rec
// card and never touches a thumbs button, which is the case that used to
// collapse genre and length to zero on the very first refit.

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

  test('a one-sided batch presses a weight to its floor, never to zero', () {
    // This used to assert only `greaterThanOrEqualTo(0)`, which is how the
    // collapse shipped: 60 negatives drove length to exactly 0.0 and the
    // test was happy. Zero is not "this group matters less" — it is "this
    // group is no longer part of ranking", reached here on nothing but
    // ignored impressions. The floor is a quarter of the prior.
    final examples = [
      for (var i = 0; i < 60; i++)
        RecTrainingExample(groups: _g(length: 0.9), positive: false),
    ];
    final w = learner.fit(examples);
    final floor = RecWeights.prior.length * learner.floorFraction;
    expect(floor, greaterThan(0));
    expect(w.length, closeTo(floor, 1e-9));
    expect(
      w.length,
      lessThan(RecWeights.prior.length),
      reason: 'the negatives must still be heard, just not obeyed',
    );
  });

  test('thin evidence barely leaves the prior', () {
    // One ignored card used to be enough to zero a whole feature group:
    // the averaged gradient outran the pull to the prior ~15x, at any n.
    final w = learner.fit([
      RecTrainingExample(groups: _g(genre: 0.6), positive: false),
    ]);
    expect(w.genre, greaterThan(RecWeights.prior.genre * 0.6));
    expect(w.genre, lessThan(RecWeights.prior.genre));
  });

  test('a lopsided batch cannot decide a group on its own', () {
    // Same four positives either way; the negatives go from 4 to 40. For
    // this reader batch composition is an accident of how many cards were
    // on screen versus how many books got finished, so it must barely move
    // the answer. Unbalanced, the 40-negative batch landed at genre 0.27.
    final positives = [
      for (var i = 0; i < 4; i++)
        RecTrainingExample(groups: _g(genre: 0.5), positive: true),
    ];
    RecWeights fitWith(int negatives) => learner.fit([
      ...positives,
      for (var i = 0; i < negatives; i++)
        RecTrainingExample(groups: _g(genre: 0.5), positive: false),
    ]);
    final balanced = fitWith(4);
    final lopsided = fitWith(40);
    expect((lopsided.genre - balanced.genre).abs(), lessThan(0.05));
    expect(lopsided.genre, greaterThan(RecWeights.prior.genre * 0.7));
  });

  test('a consistent signal still bends the weights hard', () {
    // The guards against collapse must not quietly turn learning off: a
    // reader who really does follow one author across 40 observations has
    // to see the ranking change.
    final examples = [
      for (var i = 0; i < 20; i++) ...[
        RecTrainingExample(groups: _g(author: 0.6), positive: true),
        RecTrainingExample(groups: _g(genre: 0.6), positive: false),
      ],
    ];
    final w = learner.fit(examples);
    expect(w.author, greaterThan(RecWeights.prior.author * 1.25));
    expect(w.genre, lessThan(RecWeights.prior.genre * 0.5));
  });

  test('weights never go negative and never run away', () {
    final w = learner.fit([
      for (var i = 0; i < 60; i++)
        RecTrainingExample(groups: _g(author: 0.9), positive: true),
    ]);
    expect(w.author, greaterThan(0));
    expect(
      w.author,
      lessThanOrEqualTo(RecWeights.prior.author * learner.ceilingFactor),
    );
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
      // Never read, never judged — the unlabeled "everything else" case,
      // and sharing nothing with the profile either way.
      _series(id: 6, title: 'NoOverlap', genres: ['Romance']),
    ];

    test(
      'labels tap+read positive, dismissed/ignored negative, skips rest',
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
        // id 6 unread and unjudged. id 1 was read too, but with only two
        // reads in the whole history the hold-out budget is one and the
        // tapped read has already spent it — id 1 stays in the profile.
        expect(examples.length, 3);
        expect(examples.where((e) => e.positive).length, 1);
        expect(examples.where((e) => !e.positive).length, 2);
      },
    );

    test('a read the user never tapped is still a positive', () {
      // This reader opens books from the library grid and has never used a
      // thumbs button, so taps are permanently zero. Under the old rules
      // that left no positive label reachable at all: every batch came out
      // all-negative, and an all-negative batch drove genre and length to
      // zero on the first refit.
      final examples = buildRecTrainingExamples(
        engine: engine,
        allSeries: library(),
        readingEntries: [
          _entry(
            seriesId: 1,
            fraction: 0.6,
            at: today.subtract(const Duration(days: 30)),
          ),
          _entry(seriesId: 5, fraction: 0.4, at: today),
        ],
        now: today,
      );
      // Two reads → a budget of one → the newest (id 5) is held out and
      // labeled, and id 1 stays behind to be the taste it is measured
      // against.
      expect(examples.length, 1);
      expect(examples.single.positive, isTrue);
      expect(examples.single.groups.genre, greaterThan(0));
    });

    test('a dismissal outranks a read of the same series', () {
      final examples = buildRecTrainingExamples(
        engine: engine,
        allSeries: library(),
        readingEntries: [
          _entry(seriesId: 1, fraction: 0.6, at: today),
          _entry(seriesId: 3, fraction: 0.6, at: today),
        ],
        feedback: const {3: RecommendationFeedback.dismissed},
        now: today,
      );
      // Read it, then said no thanks: the later, deliberate statement wins
      // and the book must not be minted into a positive behind it.
      expect(examples.length, 1);
      expect(examples.single.positive, isFalse);
    });

    test('a 30-read history still produces examples with real features', () {
      // The trap in making reads positive: the features come from a
      // profile with every labeled series excluded, so labeling ALL of a
      // reader's history excludes all of it — the profile empties, every
      // example scores zero on every group, all of them are dropped, and
      // fit() quietly returns the prior. Capping the hold-out keeps more
      // history in the profile than is ever taken out of it.
      final read = [
        for (var i = 1; i <= 30; i++)
          _series(id: i, title: 'Read $i', genres: ['Cultivation']),
      ];
      final examples = buildRecTrainingExamples(
        engine: engine,
        allSeries: read,
        readingEntries: [
          for (var i = 1; i <= 30; i++)
            _entry(
              seriesId: i,
              fraction: 0.6,
              at: today.subtract(Duration(days: i)),
            ),
        ],
        now: today,
      );
      expect(examples.length, 12, reason: 'bare-read positives are capped');
      expect(examples.every((e) => e.positive), isTrue);
      expect(
        examples.every((e) => e.groups.features.any((f) => f != 0)),
        isTrue,
        reason: 'the 18 reads left in the profile must still be taste',
      );
      final w = const RecWeightLearner().fit(examples);
      expect(
        w.genre,
        greaterThan(RecWeights.prior.genre),
        reason:
            'a reader who never taps must still be able to teach it '
            'something — silently returning the prior is the bug',
      );
    });

    test(
      'a labeled series does not leak its own affinity into its features',
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
        expect(
          examples,
          isEmpty,
          reason: 'self-affinity must not become a training feature',
        );
      },
    );
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
