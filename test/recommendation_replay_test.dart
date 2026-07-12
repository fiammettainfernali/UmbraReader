// Phase D of the recommendation overhaul: offline replay evaluation.
//
// Rebuilds a reading history on a synthetic-but-realistic webnovel library,
// asks the engine to recommend at time T, and measures hits against what the
// simulated reader actually went on to read after T — so engine changes are
// validated against reading patterns, not vibes. The final test replays the
// full loop: recommend → outcomes → learn weights → measurably better recs.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/rec_outcome_store.dart';
import 'package:umbra_reader/services/rec_weight_learner.dart';
import 'package:umbra_reader/services/recommendation_engine.dart';
import 'package:umbra_reader/services/recommendation_feedback_store.dart';

// ── the library ────────────────────────────────────────────────────────────
// One favourite author (Er Gen) whose books span genres, a cultivation
// cluster, and romance/sci-fi clusters as distractors. Cluster members share
// distinctive description vocabulary so keyword affinity has something real
// to bite on.

Series _series(
  int id,
  String title,
  String author,
  List<String> genres,
  String description, {
  int chapters = 1200,
  DateTime? updatedAt,
}) => Series(
  opdsId: id,
  title: title,
  author: author,
  description: description,
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: chapters,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: updatedAt,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

const _cultivationDesc =
    'A mortal joins a sect and walks the dao. Immortal cultivation, '
    'tribulation lightning, spirit stones and sect elders bar the long '
    'road to ascension.';
const _erGenDesc =
    'A slow burn of karma and reincarnation where scheming protagonists '
    'ponder mortality beneath the heavens.';
const _romanceDesc =
    'A contract marriage between a cold ceo and a plucky assistant blooms '
    'into jealous rivals, secret heirs and wedding drama.';
const _scifiDesc =
    'Starships and warp gates. A ragtag crew smuggles alien relics across '
    'the galactic frontier dodging the empire fleet.';

// Recency trap: the distractor clusters are the most recently updated, so a
// naive recently-updated shelf ranks them first.
final _tNow = DateTime.utc(2026, 6, 1);

List<Series> _library() => [
  // Er Gen's books — the reader's favourite author. EG4/EG5 are deliberately
  // NOT cultivation: only the author (and his style keywords) connect them.
  _series(1, 'EG1 Renegade Immortal', 'Er Gen', ['Cultivation', 'Xianxia'],
      '$_cultivationDesc $_erGenDesc'),
  _series(2, 'EG2 Pursuit of the Truth', 'Er Gen', ['Cultivation', 'Xianxia'],
      '$_cultivationDesc $_erGenDesc'),
  _series(3, 'EG3 A World Worth Protecting', 'Er Gen',
      ['Cultivation', 'Xianxia'], '$_cultivationDesc $_erGenDesc'),
  _series(4, 'EG4 Beseech the Devil', 'Er Gen', ['Tragedy'], _erGenDesc),
  _series(5, 'EG5 I Shall Seal the Heavens', 'Er Gen', ['Tragedy'],
      _erGenDesc),
  // Cultivation cluster by distinct authors.
  for (var i = 0; i < 8; i++)
    _series(10 + i, 'Cult ${10 + i}', 'Author C$i',
        ['Cultivation', 'Xianxia'], _cultivationDesc),
  // Romance distractors — freshest updates in the library.
  for (var i = 0; i < 6; i++)
    _series(30 + i, 'Rom ${30 + i}', 'Author R$i', ['Romance'], _romanceDesc,
        chapters: 300, updatedAt: _tNow.subtract(Duration(days: i))),
  // Sci-fi distractors — also fresher than every cultivation book.
  for (var i = 0; i < 6; i++)
    _series(40 + i, 'Sci ${40 + i}', 'Author S$i', ['Sci-fi'], _scifiDesc,
        chapters: 300,
        updatedAt: _tNow.subtract(Duration(days: 10 + i))),
];

ReadingEntry _finished(int seriesId, DateTime at) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: seriesId,
    title: 'Vol',
    fileName: 'v1.epub',
    downloadUrl: '',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: ReadingProgress(
    chapterIndex: 199,
    blockIndex: 0,
    chapterCount: 200,
    endReached: true,
    updatedAt: at,
  ),
);

/// History BEFORE the split point T: five finished reads, Jan → May —
/// three Er Gen books and two cultivation-cluster books.
List<ReadingEntry> _historyBeforeT() => [
  _finished(1, DateTime.utc(2026, 1, 10)),
  _finished(2, DateTime.utc(2026, 2, 12)),
  _finished(10, DateTime.utc(2026, 3, 15)),
  _finished(11, DateTime.utc(2026, 4, 16)),
  _finished(3, DateTime.utc(2026, 5, 20)),
];

/// What the reader ACTUALLY read after T: the next Er Gen book (crossing
/// genre — author loyalty) and another cultivation-cluster book.
const _readAfterT = {4, 12};

int _hits(List<Recommendation> recs, Set<int> future, int k) {
  var hits = 0;
  for (final rec in recs.take(k)) {
    if (future.contains(rec.series.opdsId)) hits++;
  }
  return hits;
}

void main() {
  const engine = RecommendationEngine();

  test('replay: recs at T contain what was actually read after T', () {
    final recs = engine.recommend(
      allSeries: _library(),
      readingEntries: _historyBeforeT(),
      now: _tNow,
    );
    expect(_hits(recs, _readAfterT, 10), _readAfterT.length,
        reason: 'both future reads must appear in the top 10');
  });

  test('replay: the engine beats a recently-updated baseline', () {
    final engaged = {for (final e in _historyBeforeT()) e.volume.seriesOpdsId};
    // The naive shelf: newest updatedAt first, engaged excluded.
    final recency = _library().where((s) => !engaged.contains(s.opdsId)).toList()
      ..sort((a, b) {
        final at = a.updatedAt;
        final bt = b.updatedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
    final recencyHits = _hits(
      [for (final s in recency) Recommendation(s, 0)],
      _readAfterT,
      10,
    );
    final engineHits = _hits(
      engine.recommend(
        allSeries: _library(),
        readingEntries: _historyBeforeT(),
        now: _tNow,
      ),
      _readAfterT,
      10,
    );
    expect(recencyHits, 0,
        reason: 'the distractors are fresher — recency finds nothing');
    expect(engineHits, greaterThan(recencyHits));
  });

  test('replay: the full loop — outcomes teach author-loyalty and sharpen '
      'the next shelf', () {
    final library = _library();
    final history = _historyBeforeT();

    // At T the shelf was shown; over the following weeks the reader tapped
    // and READ the author-match (EG4) but dismissed two genre-only picks
    // and ignored another across many shelf days.
    final feedback = {
      13: RecommendationFeedback.dismissed,
      14: RecommendationFeedback.dismissed,
    };
    const signals = RecSignals(
      outcomes: {
        4: RecOutcome(impressions: 3, taps: 1), // tapped, then read
        15: RecOutcome(impressions: 8, taps: 0), // shown 8 days, ignored
      },
    );
    final historyAfter = [...history, _finished(4, DateTime.utc(2026, 6, 20))];

    final examples = buildRecTrainingExamples(
      engine: engine,
      allSeries: library,
      readingEntries: historyAfter,
      feedback: feedback,
      signals: signals,
      now: DateTime.utc(2026, 7, 1),
    );
    expect(examples, isNotEmpty);
    final learned = const RecWeightLearner().fit(examples);
    expect(learned.author, greaterThan(RecWeights.prior.author),
        reason: 'following the author across genres must raise its weight');
    expect(learned.genre, lessThan(RecWeights.prior.genre),
        reason: 'dismissed/ignored genre-only picks must lower genre weight');

    // The sharpened shelf: EG5 (author-only connection) must now rank ABOVE
    // every remaining cultivation-cluster candidate.
    final after = engine.recommend(
      allSeries: library,
      readingEntries: historyAfter,
      feedback: feedback,
      signals: signals,
      weights: learned,
      now: DateTime.utc(2026, 7, 1),
    );
    expect(after, isNotEmpty);
    final ids = [for (final r in after) r.series.opdsId];
    final eg5Rank = ids.indexOf(5);
    expect(eg5Rank, isNot(-1), reason: 'EG5 must be recommended at all');
    final firstCultRank = ids.indexWhere((id) => id >= 10 && id < 20);
    expect(
      firstCultRank == -1 || eg5Rank < firstCultRank,
      isTrue,
      reason: 'after learning author-loyalty, the author match outranks '
          'every genre match (EG5 at $eg5Rank vs first cult at '
          '$firstCultRank in $ids)',
    );
  });
}
