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

  /// True when the recommendation worked (genuinely read — from a rec card
  /// or from anywhere else in the app — or explicitly liked); false when it
  /// was dismissed or repeatedly ignored.
  final bool positive;
}

/// Learns how much each feature group (author / genre / keyword / length)
/// predicts THIS user acting on a recommendation.
///
/// Deliberately tiny: batch logistic regression over four features,
/// L2-regularized toward [RecWeights.prior] so the hand-tuned defaults hold
/// exactly at zero examples and are only bent as evidence accumulates. Full
/// refit on every call — deterministic and idempotent, no consumed-example
/// bookkeeping, microseconds at this scale.
///
/// Three guards stop a lopsided batch from wiping a group out, because the
/// plain example-average did exactly that: a SINGLE negative example drove
/// genre from 1.0 to 0.0 and pinned it there, and a reader who opens books
/// from the library grid rather than from rec cards could only ever produce
/// negatives — so ranking quietly degraded to author-only, which in a
/// library of 883 books across 795 authors is barely a ranking at all.
/// Measured on 0.6-valued features, 200 epochs at lr 0.15:
///
///  - class balancing, so each class carries half the gradient mass however
///    many examples it has and 40 ignores cannot outvote 4 reads (genre
///    0.27 → 0.93 on a 4-positive/40-negative batch, within 0.01 of the
///    same batch balanced 4/4);
///  - an evidence factor n/(n + [evidenceScale]) on the data term, so a
///    couple of examples barely leave the prior (single negative: genre
///    0.0 → 0.69) while a sustained pattern still moves hard (24 consistent
///    examples: author 2.0 → 2.93);
///  - floor and ceiling as fractions of each group's prior. The old clamp
///    sat at zero, which is not a floor — zero weight means the group stops
///    being a ranking signal at all, permanently, on evidence this thin.
///
/// Weights still never go negative: "an author match makes it WORSE" is far
/// more likely label noise than real taste, and a negative weight would
/// invert ranking semantics.
class RecWeightLearner {
  const RecWeightLearner({
    this.epochs = 200,
    this.learningRate = 0.15,
    this.regularization = 0.05,
    this.evidenceScale = 12.0,
    this.floorFraction = 0.25,
    this.ceilingFactor = 4.0,
  });

  final int epochs;
  final double learningRate;

  /// Pull-toward-prior strength per step. At the old 0.02 it was ~15× weaker
  /// than a typical gradient (0.3 for a 0.6 feature at σ = 0.5), so the data
  /// term always ran the weight into the clamp; at 0.05 a consistent pattern
  /// still bends a weight by ~45% while noise stays near the prior.
  final double regularization;

  /// How many examples it takes for the data to count at roughly half
  /// strength — the "don't rewrite a reader's taste off three impressions"
  /// knob.
  final double evidenceScale;

  /// Bounds on every weight, as a multiple of that group's own prior: a
  /// group can be turned right down or way up, never off and never wild.
  /// Expressed against the prior so a group that starts out mattering less
  /// (length, at 0.5) gets a proportionally smaller band. A prior of zero
  /// therefore pins its group at zero, which is what a zero prior means.
  final double floorFraction;
  final double ceilingFactor;

  /// Fits weights on [examples], starting from — and regularized toward —
  /// [prior]. With no examples, returns [prior] unchanged; that is the only
  /// path here that declines to learn. There is deliberately no "needs N
  /// positives AND N negatives before fitting" gate: for a reader who never
  /// taps a rec card and never touches the thumbs, a gate like that returns
  /// the prior forever and the feature is dead without ever saying so. The
  /// guards below shape how far evidence moves the weights, never whether
  /// it is allowed to.
  RecWeights fit(
    List<RecTrainingExample> examples, {
    RecWeights prior = RecWeights.prior,
  }) {
    if (examples.isEmpty) return prior;
    final priorVec = [prior.author, prior.genre, prior.keyword, prior.length];
    final w = [...priorVec];
    var bias = 0.0;

    // Gradient mass per example. With both classes present each side gets
    // half the total, so batch composition — for this reader an accident of
    // how many cards happened to be on screen versus how many books they
    // happened to finish — cannot decide the outcome on its own. With one
    // class present there is nothing to balance and this is the plain
    // average; the evidence factor below is what keeps that case honest.
    final positives = examples.where((e) => e.positive).length;
    final negatives = examples.length - positives;
    final oneSided = positives == 0 || negatives == 0;
    final posMass = oneSided ? 1 / examples.length : 0.5 / positives;
    final negMass = oneSided ? 1 / examples.length : 0.5 / negatives;

    // Discount the data until there is enough of it to be worth believing.
    final evidence = examples.length / (examples.length + evidenceScale);

    for (var epoch = 0; epoch < epochs; epoch++) {
      final grad = List<double>.filled(4, 0);
      var gradBias = 0.0;
      for (final ex in examples) {
        final x = ex.groups.features;
        var z = bias;
        for (var i = 0; i < 4; i++) {
          z += w[i] * x[i];
        }
        final err =
            ((ex.positive ? 1.0 : 0.0) - _sigmoid(z)) *
            (ex.positive ? posMass : negMass);
        for (var i = 0; i < 4; i++) {
          grad[i] += err * x[i];
        }
        gradBias += err;
      }
      for (var i = 0; i < 4; i++) {
        w[i] +=
            learningRate *
            (evidence * grad[i] - regularization * (w[i] - priorVec[i]));
        final floor = floorFraction * priorVec[i];
        final ceiling = ceilingFactor * priorVec[i];
        if (w[i] < floor) w[i] = floor;
        if (w[i] > ceiling) w[i] = ceiling;
      }
      bias += learningRate * evidence * gradBias;
    }
    return RecWeights(author: w[0], genre: w[1], keyword: w[2], length: w[3]);
  }

  double _sigmoid(double z) => 1 / (1 + exp(-z));
}

/// How much of a book counts as having genuinely read it. Deep enough that
/// opening a book and bouncing off it isn't a verdict either way.
const _readPositiveFraction = 0.2;

/// Builds training examples from recommendation outcomes and what the user
/// went on to do:
///
///  - positive: explicitly 👍-liked; opened from a rec card AND genuinely
///    read; or simply READ past [_readPositiveFraction], however the book
///    was found;
///  - negative: dismissed / reset, or shown on 5+ distinct days and never
///    opened;
///  - everything else is unlabeled and skipped.
///
/// That bare read is what makes the learner trainable at all for a reader
/// who opens books from the library grid and has never touched a thumbs
/// button. A tap on a rec card or a 👍 used to be the only routes to a
/// positive, so every batch such a reader produced was all-negative and the
/// learner could only ever turn groups down — to zero, and permanently.
/// Nothing here asks the user to mark anything; finishing a fifth of a book
/// is the whole affordance.
///
/// Features are the labeled series' group scores against a profile built
/// WITHOUT any labeled series' own contribution (else a read series would
/// see its own affinity reflected back — label leakage). Zero-feature
/// examples are dropped: they carry no signal about which group matters.
///
/// Which is exactly why bare-read positives are capped at
/// [maxReadPositives], newest first, and never more than half the reads:
/// label every read series and the excluded set becomes the entire reading
/// history, leaving no profile to measure against, so every example comes
/// out featureless, all of them are dropped, and fit() silently returns the
/// prior. Holding out at most half guarantees the extractor is always built
/// from more history than it is asked to explain. (Per-example
/// self-subtraction would hold out one series at a time instead, but costs
/// a full profile build — keyword TF-IDF across all 883 books — per label,
/// on every Discover load; this costs one.)
List<RecTrainingExample> buildRecTrainingExamples({
  required RecommendationEngine engine,
  required List<Series> allSeries,
  required List<ReadingEntry> readingEntries,
  Map<int, RecommendationFeedback> feedback = const {},
  RecSignals signals = RecSignals.none,
  int maxReadPositives = 12,
  DateTime? now,
}) {
  // Deepest read, and when it was last read, per series. "Deepest" is
  // measured the same way the engine measures it — the better of the
  // fraction and the chapter-depth term — because a volume Novel Grabber
  // packed with 250 chapters reads 40 chapters deep at a fraction of 0.16,
  // and a learner that scored that as untouched would disagree with the
  // ranking it is supposed to be explaining.
  final maxRead = <int, double>{};
  final lastReadAt = <int, DateTime>{};
  for (final entry in readingEntries) {
    final id = entry.volume.seriesOpdsId;
    final p = entry.progress;
    final chaptersRead = p.chapterIndex;
    final depth =
        chaptersRead / (chaptersRead + RecommendationEngine.depthHalfChapters);
    final f = p.isFinished ? 1.0 : max(p.fraction, depth);
    if (f > (maxRead[id] ?? 0)) maxRead[id] = f;
    final at = p.updatedAt;
    final best = lastReadAt[id];
    if (at != null && (best == null || at.isAfter(best))) lastReadAt[id] = at;
  }
  bool genuinelyRead(int id) => (maxRead[id] ?? 0) >= _readPositiveFraction;

  final labels = <int, bool>{};
  for (final series in allSeries) {
    final id = series.opdsId;
    final fb = feedback[id];
    final outcome = signals.outcomes[id];
    if (fb == RecommendationFeedback.liked) {
      labels[id] = true;
    } else if ((outcome?.taps ?? 0) > 0 && genuinelyRead(id)) {
      labels[id] = true;
    } else if (fb == RecommendationFeedback.dismissed ||
        fb == RecommendationFeedback.reset) {
      // An explicit "no thanks" outranks a read: it is the later and more
      // deliberate of the two statements about the same book.
      labels[id] = false;
    } else if ((outcome?.ignored ?? 0) >= 5) {
      // Five distinct days of looking past the card. This only means
      // anything because impressions are now counted for cards that were
      // actually on screen and expire after ~60 days — stamped at launch
      // for a shelf nobody looked at, and never aged out, it was a verdict
      // the reader never gave.
      labels[id] = false;
    }
  }

  // Bare reads fill whatever the hold-out budget leaves, newest first: the
  // recent reads are the ones that describe current taste, and the older
  // history they get measured against is the part that has settled. Reads
  // labeled above — a tapped read, a read the user then dismissed — spend
  // budget too, since they leave the profile just the same.
  final readCount = maxRead.keys.where(genuinelyRead).length;
  final alreadyHeldOut = labels.keys.where(genuinelyRead).length;
  final budget = min(maxReadPositives, readCount ~/ 2) - alreadyHeldOut;
  if (budget > 0) {
    final bareReads = [
      for (final series in allSeries)
        if (!labels.containsKey(series.opdsId) && genuinelyRead(series.opdsId))
          series.opdsId,
    ];
    bareReads.sort((a, b) {
      final at = lastReadAt[a];
      final bt = lastReadAt[b];
      // Undated legacy progress rows sort last: no date is no claim to
      // being recent.
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    for (final id in bareReads.take(budget)) {
      labels[id] = true;
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
