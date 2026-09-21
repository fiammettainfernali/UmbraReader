// Phase C of the recommendation overhaul: the two timescales, and letting
// depth and time in a book count before it is a finished one.
//
// The reader's own words for the problem were "the learning needs to be
// dynamic because what i like can change randomly". Nothing in the engine
// used to move faster than a 30-day half-life, and the finished-favourite
// floor meant a canon book stopped fading at all after roughly 82 days — so
// a genuinely new interest could never get loud enough to reach the shelf
// while the old one was still standing there at full height.
//
// Every test here injects a fixed `now`, as the other recommendation tests
// do: decay IS the subject, so the clock cannot be the wall clock.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/recommendation_engine.dart';

Series _series({
  required int id,
  required String title,
  // Distinct per series by default so the author tag (×2 weight) doesn't
  // leak affinity between fixtures probing genre, depth and time.
  String? author,
  List<String> genres = const [],
  int totalChapters = 500,
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
  required ReadingProgress progress,
}) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: seriesId,
    title: 'Vol',
    fileName: 'v1.epub',
    downloadUrl: '',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: progress,
);

void main() {
  const engine = RecommendationEngine();
  final today = DateTime.utc(2026, 9, 21);

  // ── the two lanes ────────────────────────────────────────────────────
  //
  // Twelve fantasy series finished ~200 days ago — far enough back that
  // only the core lane's 0.15 floor keeps them alive at all — then four
  // series opened THIS week, a dozen chapters into each, which is what
  // starting a run of new books actually looks like. Ids 31/32 are the
  // two things being ranked and have never been touched.
  List<Series> laneLibrary(String recentGenre) => [
    for (var id = 1; id <= 12; id++)
      _series(id: id, title: 'Old Fantasy $id', genres: const ['Fantasy']),
    for (var id = 21; id <= 24; id++)
      _series(id: id, title: 'This Week $id', genres: [recentGenre]),
    _series(id: 31, title: 'Candidate Fantasy', genres: const ['Fantasy']),
    _series(id: 32, title: 'Candidate Sci-Fi', genres: const ['Sci-Fi']),
  ];

  List<ReadingEntry> oldFantasy() => [
    for (var id = 1; id <= 12; id++)
      _entry(
        seriesId: id,
        progress: ReadingProgress(
          chapterIndex: 499,
          blockIndex: 0,
          chapterCount: 500,
          endReached: true,
          updatedAt: today.subtract(const Duration(days: 200)),
        ),
      ),
  ];

  List<ReadingEntry> thisWeek() => [
    for (var id = 21; id <= 24; id++)
      _entry(
        seriesId: id,
        progress: ReadingProgress(
          chapterIndex: 12,
          blockIndex: 0,
          chapterCount: 250,
          updatedAt: today.subtract(const Duration(days: 3)),
        ),
      ),
  ];

  test('a week of sci-fi beats a year of fantasy on the shelf', () {
    // Twelve floored fantasy seeds put 12 × 0.15 = 1.80 on g:fantasy; four
    // shallow sci-fi starts put ~0.64 there on the core lane. On the raw
    // core lane alone fantasy wins by nearly 3:1, and that is exactly what
    // the single-lane engine did — the fantasy candidate came first and
    // the sci-fi one trailed it. The fast lane has forgotten the fantasy
    // entirely, the measured genre drift is ≈0.66, and the blend hands the
    // recent lane ≈51% of the taste vector, which flips it.
    final recs = engine.recommend(
      allSeries: laneLibrary('Sci-Fi'),
      readingEntries: [...oldFantasy(), ...thisWeek()],
      now: today,
    );
    final ids = [for (final r in recs) r.series.opdsId];
    expect(ids, contains(32));
    expect(
      ids.indexOf(32),
      lessThan(ids.indexOf(31)),
      reason: 'what they are reading this week has to be able to win',
    );
    expect(recs.first.series.opdsId, 32);
  });

  test('a week of MORE fantasy does not swing the shelf', () {
    // Byte for byte the test above, except that this week was more of the
    // same. The lanes then point the same way, the measured drift is 0 and
    // the blend sits on its floor, so the shelf has to stay where it was.
    // This is the half a constant blend gets wrong: it would churn the
    // shelf for a week that said nothing new. Unlike the test above this
    // one also passed before the change — it is the guard that the drift
    // machinery cannot fire on its own.
    final recs = engine.recommend(
      allSeries: laneLibrary('Fantasy'),
      readingEntries: [...oldFantasy(), ...thisWeek()],
      now: today,
    );
    expect(
      recs.first.series.opdsId,
      31,
      reason: 'more of the same taste is not a change of taste',
    );
    double scoreOf(int id) =>
        recs.firstWhere((r) => r.series.opdsId == id).score;
    expect(
      scoreOf(32),
      lessThan(scoreOf(31) / 2),
      reason: 'and the unread genre stays where it was, well behind',
    );
  });

  // ── depth and time ───────────────────────────────────────────────────
  //
  // Each genre pair gets its own length bucket, so the l: tag reinforces
  // its own pair instead of leaking a positive score across the shelf and
  // making the assertions below vacuous.
  List<Series> depthLibrary() => [
    _series(
      id: 1,
      title: 'Seed Slow',
      genres: ['Cultivation'],
      totalChapters: 50,
    ),
    _series(
      id: 3,
      title: 'Pick Cultivation',
      genres: ['Cultivation'],
      totalChapters: 50,
    ),
    _series(
      id: 2,
      title: 'Seed Recent',
      genres: ['Regression'],
      totalChapters: 200,
    ),
    _series(
      id: 4,
      title: 'Pick Regression',
      genres: ['Regression'],
      totalChapters: 200,
    ),
    _series(id: 5, title: 'Seed Skim', genres: ['Horror'], totalChapters: 1000),
    _series(
      id: 6,
      title: 'Pick Horror',
      genres: ['Horror'],
      totalChapters: 1000,
    ),
  ];

  // Seed 1 is fifteen chapters into a 250-chapter volume and hasn't been
  // reopened in three months — a 6% fraction, well inside the stall
  // taper's old reach. Seeds 2 and 5 are today's reading and exist to give
  // the ledger a median to measure seed 1 against.
  List<ReadingEntry> depthEntries() => [
    _entry(
      seriesId: 1,
      progress: ReadingProgress(
        chapterIndex: 15,
        blockIndex: 0,
        chapterCount: 250,
        updatedAt: today.subtract(const Duration(days: 90)),
      ),
    ),
    _entry(
      seriesId: 2,
      progress: ReadingProgress(
        chapterIndex: 100,
        blockIndex: 0,
        chapterCount: 200,
        updatedAt: today,
      ),
    ),
    _entry(
      seriesId: 5,
      progress: ReadingProgress(
        chapterIndex: 100,
        blockIndex: 0,
        chapterCount: 200,
        updatedAt: today,
      ),
    ),
  ];

  test('real time in a book counts even at a low chapter fraction', () {
    // Ledger seconds 10800 / 3600 / 1200 → a median of 3600, so seed 1 got
    // three times the reader's usual sitting. Three months later the old
    // engine tapered it to -0.15 anyway, because it only ever looked at
    // the fraction, and Cultivation went negative on the strength of a
    // book they had loved.
    final recs = engine.recommend(
      allSeries: depthLibrary(),
      readingEntries: depthEntries(),
      signals: const RecSignals(
        volumeSeconds: {
          '1/v1.epub': 10800,
          '2/v1.epub': 3600,
          '5/v1.epub': 1200,
        },
      ),
      now: today,
    );
    expect(
      [for (final r in recs) r.series.opdsId],
      contains(3),
      reason: 'three hours is a verdict; 6% of a packed volume is not',
    );
  });

  test('a book with a low fraction AND low time still goes negative', () {
    // The other side of the same gate, and the reason it is a gate on
    // POSITIVE evidence rather than on the engagement multiplier: that
    // multiplier falls back to 1.0 whenever the ledger has no row, so
    // "engagement < 1" would have spared every volume the ledger never
    // saw. Here the ledger HAS a row and it says half the usual sitting,
    // so the taper is right to fire. Passes before and after the
    // two-lane change by design — it is the guard that the fix did not
    // quietly disable the taper.
    final recs = engine.recommend(
      allSeries: depthLibrary(),
      readingEntries: depthEntries(),
      signals: const RecSignals(
        volumeSeconds: {'1/v1.epub': 600, '2/v1.epub': 3600, '5/v1.epub': 1200},
      ),
      now: today,
    );
    final ids = [for (final r in recs) r.series.opdsId];
    expect(
      ids,
      isNot(contains(3)),
      reason: 'fifteen chapters and ten minutes is a bounce',
    );
    expect(ids, contains(4), reason: 'the genuine reads still steer');
  });

  test('a long favourite waiting on new chapters does not go negative', () {
    // Three hundred chapters into a fifteen-hundred-chapter novel, caught
    // up and waiting two months for the next drop. That is a 0.2 fraction,
    // which the old taper read as "bounced off it" and turned into a
    // negative against the reader's own favourite genre — the single most
    // common shape in this library, since waiting on a running webnovel is
    // the normal state of one.
    final lib = [
      _series(
        id: 1,
        title: 'Long Favourite',
        genres: ['Cultivation'],
        totalChapters: 1500,
      ),
      _series(
        id: 3,
        title: 'Pick Cultivation',
        genres: ['Cultivation'],
        totalChapters: 1500,
      ),
      _series(
        id: 2,
        title: 'Other',
        genres: ['Regression'],
        totalChapters: 200,
      ),
      _series(
        id: 4,
        title: 'Pick Regression',
        genres: ['Regression'],
        totalChapters: 200,
      ),
    ];
    final recs = engine.recommend(
      allSeries: lib,
      readingEntries: [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 300,
            blockIndex: 0,
            chapterCount: 1500,
            updatedAt: today.subtract(const Duration(days: 60)),
          ),
        ),
      ],
      now: today,
    );
    expect(
      [for (final r in recs) r.series.opdsId],
      contains(3),
      reason: 'waiting for chapters is not abandoning a book',
    );
  });
}
