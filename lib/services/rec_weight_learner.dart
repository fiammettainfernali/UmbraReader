import 'dart:convert';
import 'dart:math';

import '../db/app_database.dart';
import '../models/series.dart';
import 'reading_progress_store.dart';
import 'recommendation_engine.dart';
import 'recommendation_feedback_store.dart';

/// One training example for the weight learner: the feature-group scores a
/// series had when it was recommended, and what the user did about it.
class RecTrainingExample {
  const RecTrainingExample({required this.groups, required this.positive});

  final RecGroupScores groups;

  /// True when the recommendation worked (opened and genuinely read, or
  /// explicitly liked); false when it was dismissed or repeatedly ignored.
  final bool positive;
}

/// Learns how much each feature group (author / genre / keyword / length)
/// predicts THIS user acting on a recommendation.
///
/// Deliberately tiny: batch logistic regression over four features,
/// L2-regularized toward [RecWeights.prior] so the hand-tuned defaults hold
/// exactly at zero examples and are only bent as evidence accumulates. Full
/// refit on every call — deterministic and idempotent, no consumed-example
/// bookkeeping, microseconds at this scale. Weights are floored at zero: a
/// group can stop mattering, but "author match makes it WORSE" is far more
/// likely label noise than real taste, and negative weights would invert
/// ranking semantics.
class RecWeightLearner {
  const RecWeightLearner({
    this.epochs = 200,
    this.learningRate = 0.15,
    this.regularization = 0.02,
  });

  final int epochs;
  final double learningRate;

  /// Pull-toward-prior strength per example-averaged step. Small: ~a dozen
  /// consistent examples visibly bend a weight, a couple of noisy ones don't.
  final double regularization;

  /// Fits weights on [examples], starting from — and regularized toward —
  /// [prior]. With no examples, returns [prior] unchanged.
  RecWeights fit(
    List<RecTrainingExample> examples, {
    RecWeights prior = RecWeights.prior,
  }) {
    if (examples.isEmpty) return prior;
    final priorVec = [prior.author, prior.genre, prior.keyword, prior.length];
    final w = [...priorVec];
    var bias = 0.0;

    for (var epoch = 0; epoch < epochs; epoch++) {
      final grad = List<double>.filled(4, 0);
      var gradBias = 0.0;
      for (final ex in examples) {
        final x = ex.groups.features;
        var z = bias;
        for (var i = 0; i < 4; i++) {
          z += w[i] * x[i];
        }
        final err = (ex.positive ? 1.0 : 0.0) - _sigmoid(z);
        for (var i = 0; i < 4; i++) {
          grad[i] += err * x[i];
        }
        gradBias += err;
      }
      final n = examples.length;
      for (var i = 0; i < 4; i++) {
        w[i] += learningRate *
            (grad[i] / n - regularization * (w[i] - priorVec[i]));
        if (w[i] < 0) w[i] = 0;
      }
      bias += learningRate * (gradBias / n);
    }
    return RecWeights(
      author: w[0],
      genre: w[1],
      keyword: w[2],
      length: w[3],
    );
  }

  double _sigmoid(double z) => 1 / (1 + exp(-z));
}

/// Builds training examples from recommendation outcomes and what the user
/// went on to do:
///
///  - positive: opened from a rec card AND genuinely read (past 20%), or
///    explicitly 👍-liked;
///  - negative: dismissed / reset, or shown on 5+ distinct days and never
///    opened;
///  - everything else is unlabeled and skipped.
///
/// Features are the labeled series' group scores against a profile built
/// WITHOUT any labeled series' own contribution (else a read series would
/// see its own affinity reflected back — label leakage). Zero-feature
/// examples are dropped: they carry no signal about which group matters.
List<RecTrainingExample> buildRecTrainingExamples({
  required RecommendationEngine engine,
  required List<Series> allSeries,
  required List<ReadingEntry> readingEntries,
  Map<int, RecommendationFeedback> feedback = const {},
  RecSignals signals = RecSignals.none,
  DateTime? now,
}) {
  // Deepest read fraction per series.
  final maxFraction = <int, double>{};
  for (final entry in readingEntries) {
    final id = entry.volume.seriesOpdsId;
    final f = entry.progress.isFinished ? 1.0 : entry.progress.fraction;
    if (f > (maxFraction[id] ?? 0)) maxFraction[id] = f;
  }

  final labels = <int, bool>{};
  for (final series in allSeries) {
    final id = series.opdsId;
    final fb = feedback[id];
    final outcome = signals.outcomes[id];
    if (fb == RecommendationFeedback.liked) {
      labels[id] = true;
    } else if ((outcome?.taps ?? 0) > 0 && (maxFraction[id] ?? 0) >= 0.2) {
      labels[id] = true;
    } else if (fb == RecommendationFeedback.dismissed ||
        fb == RecommendationFeedback.reset) {
      labels[id] = false;
    } else if ((outcome?.ignored ?? 0) >= 5) {
      labels[id] = false;
    }
  }
  if (labels.isEmpty) return const [];

  final profile = engine.buildProfile(
    allSeries: allSeries,
    readingEntries: readingEntries,
    feedback: feedback,
    signals: signals,
    excludeSeriesIds: labels.keys.toSet(),
    now: now,
  );
  final byId = {for (final s in allSeries) s.opdsId: s};
  final examples = <RecTrainingExample>[];
  labels.forEach((id, positive) {
    final series = byId[id];
    if (series == null) return;
    final groups = profile.groupsFor(series);
    if (groups.features.every((f) => f == 0)) return;
    examples.add(RecTrainingExample(groups: groups, positive: positive));
  });
  return examples;
}

/// Persists the learned per-user weights in the app database's kv table.
/// Device-local on purpose: the outcomes they're trained on are device-local,
/// and a whole-vector cloud merge would let a barely-used device clobber the
/// better-trained one.
class RecWeightsStore {
  static const _kvKey = 'rec_learned_weights';

  AppDatabase get _db => AppDatabase.instance;

  Future<RecWeights> load() async {
    final raw = await _db.kvGet(_kvKey);
    if (raw == null || raw.isEmpty) return RecWeights.prior;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return RecWeights.prior;
      return RecWeights.fromJson(decoded);
    } on FormatException {
      return RecWeights.prior;
    }
  }

  Future<void> save(RecWeights weights) =>
      _db.kvSet(_kvKey, jsonEncode(weights.toJson()));
}
