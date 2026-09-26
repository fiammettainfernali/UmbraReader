// The awards engine, and in particular the claim that it lasts.
//
// A rewards system dies in one of two ways: it runs out of things to give,
// or it hands everything over at once. Both are arithmetic, so both can be
// pinned here rather than discovered in a year's time when the screen has
// gone quiet.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/awards.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

const _minutesPerYearLight = 30 * 365; // half an hour a night
const _minutesPerYearHeavy = 120 * 365; // two hours a night

Series _series({
  required int id,
  String title = 'S',
  String author = 'A',
  List<String> genres = const ['Fantasy'],
  DateTime? addedAt,
}) => Series(
  opdsId: id,
  title: title,
  author: author,
  description: '',
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: 100,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  addedAt: addedAt,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

ReadingEntry _entry({
  required int seriesId,
  String file = 'v1.epub',
  bool finished = false,
  int chapterCount = 20,
  DateTime? at,
}) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: seriesId,
    title: 'Vol',
    fileName: file,
    downloadUrl: '',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: ReadingProgress(
    chapterIndex: finished ? chapterCount - 1 : 1,
    blockIndex: 1,
    chapterCount: chapterCount,
    endReached: finished,
    updatedAt: at,
  ),
);

/// A ledger with [minutes] spread over [days] consecutive days ending today.
ReadingActivity _ledger({
  required int minutes,
  required int days,
  int words = 0,
  DateTime? endingAt,
}) {
  final end = endingAt ?? DateTime(2026, 9, 25);
  final daily = <String, int>{};
  final dailyWords = <String, int>{};
  for (var i = 0; i < days; i++) {
    final d = end.subtract(Duration(days: i));
    final key =
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    daily[key] = (minutes * 60) ~/ days;
    if (words > 0) dailyWords[key] = words ~/ days;
  }
  return ReadingActivity(
    dailySeconds: daily,
    perVolumeSeconds: const {},
    dailyWords: dailyWords,
    perVolumeWords: const {},
  );
}

AwardContext _ctx({
  ReadingActivity? activity,
  List<ReadingEntry> entries = const [],
  List<Series> library = const [],
  Map<int, int> highlights = const {},
}) => AwardContext(
  activity: activity ?? ReadingActivity.empty,
  entries: entries,
  library: library,
  highlightsPerSeries: highlights,
  now: DateTime(2026, 9, 25),
);

void main() {
  group('the ladders never run out', () {
    test('every ladder defines a rung far past any real reader', () {
      for (final ladder in kAwardLadders) {
        // Rung 40 of 'hours' is ~137 million hours. The point is not that
        // anyone reaches it: it is that the code has an answer at every
        // index, so the screen can always show a next target instead of a
        // dead end.
        expect(
          ladder.rung(40),
          greaterThan(ladder.seeds.last),
          reason: '${ladder.id} must define rungs past its seeds',
        );
      }
    });

    test('rungs only ever ascend', () {
      for (final ladder in kAwardLadders) {
        var previous = 0;
        for (var n = 0; n < 30; n++) {
          final rung = ladder.rung(n);
          expect(
            rung,
            greaterThan(previous),
            reason: '${ladder.id} rung $n went backwards',
          );
          previous = rung;
        }
      }
    });

    test('a decade of heavy reading still has hours rungs left', () {
      // Ten years at two hours a night is 7,300 hours. If the ladder ended
      // near there, the most committed reader would hit a wall — which is
      // exactly the failure this system is meant to avoid.
      final hours = kAwardLadders.firstWhere((l) => l.id == 'hours');
      final reached = hours.reachedBy(7300);
      expect(hours.rung(reached), greaterThan(7300));
    });
  });

  group('the level curve paces across years', () {
    test('the first level comes inside the first few sessions', () {
      // Level 2 costs 170 XP — two hours and fifty minutes of reading. Close
      // enough that a new reader sees the thing work in their first week,
      // far enough that it is not handed over for opening the app. If this
      // ever needs more than three hours, the curve's base has grown too
      // steep at the bottom and a beginner watches a bar that never moves.
      expect(levelForXp(3 * 60), greaterThanOrEqualTo(2));
      expect(levelForXp(60), 1, reason: 'not given away in one hour either');
    });

    test('a light reader is still levelling after a decade', () {
      final tenYears = _minutesPerYearLight * 10;
      final level = levelForXp(tenYears);
      expect(level, greaterThan(50), reason: 'a decade should be substantial');
      expect(
        xpForLevel(level + 1),
        greaterThan(tenYears),
        reason: 'there is always a next level to reach',
      );
    });

    test(
      'a heavy reader is still levelling at a good cadence after four years',
      () {
        final fourYears = _minutesPerYearHeavy * 4;
        final level = levelForXp(fourYears);
        final toNext = xpForLevel(level + 1) - fourYears;

        // Four years at two hours a night lands around level 200, with the
        // next level roughly a week's reading away. Both halves matter: a
        // level that costs days is filler, and one that costs months reads as
        // a wall. The window below is "somewhere between an evening and a
        // couple of months", which is the band where a level still lands as
        // news.
        expect(level, greaterThan(150));
        expect(toNext, greaterThan(120), reason: 'more than one evening');
        expect(toNext, lessThan(20000), reason: 'not an unreachable wall');
      },
    );

    test('levels slow down but never stop', () {
      // Each level costs more than the last, which is what stretches the
      // curve; if any step were cheaper than its predecessor the ladder
      // would speed up over time and burn out.
      var previousCost = 0;
      for (var level = 2; level < 300; level++) {
        final cost = xpForLevel(level + 1) - xpForLevel(level);
        expect(
          cost,
          greaterThanOrEqualTo(previousCost),
          reason: 'level $level got cheaper than the one before',
        );
        previousCost = cost;
      }
    });

    test('levelForXp is the exact inverse of xpForLevel', () {
      // A level that flickers as the ledger ticks over would be worse than
      // one that is briefly conservative, so the boundaries are pinned.
      for (var level = 1; level < 200; level++) {
        final at = xpForLevel(level);
        expect(levelForXp(at), level, reason: 'at exactly level $level');
        expect(levelForXp(at - 1), lessThan(level + 1));
        expect(levelForXp(xpForLevel(level + 1) - 1), level);
      }
    });
  });

  group('it reads a history that already happened', () {
    test('two years of reading arrives already earned', () {
      // The whole reason the engine derives rather than counts: someone who
      // has been reading for two years must not open this to a blank slate.
      final ctx = _ctx(
        activity: _ledger(minutes: _minutesPerYearLight * 2, days: 500),
        entries: [
          for (var i = 0; i < 30; i++)
            _entry(seriesId: i, finished: true, at: DateTime(2026, 9, 1)),
        ],
        library: [for (var i = 0; i < 30; i++) _series(id: i)],
      );
      final snapshot = evaluateAwards(ctx);

      expect(snapshot.level.level, greaterThan(10));
      expect(snapshot.badgeIds, isNotEmpty);
      expect(
        snapshot.ladders.where((l) => l.rungsReached > 0).length,
        greaterThanOrEqualTo(3),
        reason: 'hours, days and books should all be well underway',
      );
    });

    test('evaluating twice changes nothing', () {
      final ctx = _ctx(
        activity: _ledger(minutes: 5000, days: 100),
        entries: [_entry(seriesId: 1, finished: true)],
        library: [_series(id: 1)],
      );
      expect(evaluateAwards(ctx).badgeIds, evaluateAwards(ctx).badgeIds);
    });

    test('a reader with nothing yet has nothing, and is still level 1', () {
      final snapshot = evaluateAwards(_ctx());
      expect(snapshot.badgeIds, isEmpty);
      expect(snapshot.level.level, 1);
      expect(
        snapshot.ladders.every((l) => l.nextRung > 0),
        isTrue,
        reason: 'every ladder still shows something to aim at',
      );
    });

    test('progress towards the next rung is a real fraction', () {
      // 30 hours sits between the 25 and 50 rungs: a fifth of the way.
      final ctx = _ctx(activity: _ledger(minutes: 30 * 60, days: 30));
      final hours = evaluateAwards(
        ctx,
      ).ladders.firstWhere((l) => l.ladder.id == 'hours');
      expect(hours.value, 30);
      expect(hours.previousRung, 25);
      expect(hours.nextRung, 50);
      expect(hours.fraction, closeTo(0.2, 0.01));
      expect(hours.remaining, 20);
    });
  });

  group('rare finds', () {
    test('a four-hour day is a marathon, three hours is not', () {
      final long = _ctx(activity: _ledger(minutes: 260, days: 1));
      final short = _ctx(activity: _ledger(minutes: 179, days: 1));
      expect(_ids(long), contains('find.marathon'));
      expect(_ids(short), isNot(contains('find.marathon')));
    });

    test('a month away and back again is a comeback', () {
      final activity = ReadingActivity(
        dailySeconds: const {
          '2026-01-05': 3600,
          '2026-03-20': 3600, // 74 days later
        },
        perVolumeSeconds: const {},
      );
      expect(_ids(_ctx(activity: activity)), contains('find.comeback'));
    });

    test('a gap of a week is not', () {
      final activity = ReadingActivity(
        dailySeconds: const {'2026-01-05': 3600, '2026-01-12': 3600},
        perVolumeSeconds: const {},
      );
      expect(_ids(_ctx(activity: activity)), isNot(contains('find.comeback')));
    });

    test('finishing a 250-chapter volume is a doorstop', () {
      final ctx = _ctx(
        entries: [_entry(seriesId: 1, finished: true, chapterCount: 250)],
        library: [_series(id: 1)],
      );
      expect(_ids(ctx), contains('find.doorstop'));
    });

    test('an unfinished doorstop does not count', () {
      final ctx = _ctx(
        entries: [_entry(seriesId: 1, finished: false, chapterCount: 250)],
        library: [_series(id: 1)],
      );
      expect(_ids(ctx), isNot(contains('find.doorstop')));
    });

    test('a book finished a year after it arrived is an old flame', () {
      final ctx = _ctx(
        entries: [
          _entry(seriesId: 1, finished: true, at: DateTime(2026, 9, 1)),
        ],
        library: [_series(id: 1, addedAt: DateTime(2024, 1, 1))],
      );
      expect(_ids(ctx), contains('find.old-flame'));
    });

    test('ten genres finished casts a wide net', () {
      final genres = [
        'Fantasy',
        'Action',
        'Romance',
        'Horror',
        'Mystery',
        'Sci-Fi',
        'Comedy',
        'Drama',
        'Xianxia',
        'Isekai',
      ];
      final ctx = _ctx(
        entries: [
          for (var i = 0; i < genres.length; i++)
            _entry(seriesId: i, finished: true),
        ],
        library: [
          for (var i = 0; i < genres.length; i++)
            _series(id: i, genres: [genres[i]]),
        ],
      );
      expect(_ids(ctx), contains('find.wide-net'));
    });

    test('rare finds describe what happened, in the past tense', () {
      final ctx = _ctx(activity: _ledger(minutes: 300, days: 1));
      final found = evaluateAwards(ctx).rareFinds;
      expect(found, isNotEmpty);
      expect(found.first.description, isNotEmpty);
      expect(found.first.description, contains('5.0 hours'));
    });
  });
}

Set<String> _ids(AwardContext ctx) => evaluateAwards(ctx).badgeIds;
