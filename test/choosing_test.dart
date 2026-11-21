// Help choosing what to read: a few picks with reasons, starting a book
// without a promise, and books left on the go sorted out.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/book_length_store.dart';
import 'package:umbra_reader/services/choosing.dart';
import 'package:umbra_reader/services/recommendation_feedback_store.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/series_status_store.dart';

import 'helpers/test_db.dart';

final _today = DateTime(2026, 11, 21, 20);

Series _series(int id, {String genres = 'Fantasy', bool cover = true}) => Series(
  opdsId: id,
  title: 'Book $id',
  author: 'Author $id',
  description: 'A long enough description for the spotlight rule to let it in. ' * 2,
  genres: genres.split(', '),
  readingStatus: '',
  totalChapters: 100,
  downloadedChapters: 100,
  coverUrl: cover ? 'http://pc/cover/$id' : null,
  updatedAt: DateTime(2026, 11, 1),
  directEpubUrl: 'http://pc/book/$id.epub',
  volumesFeedUrl: null,
);

Volume _volume(int id, {String file = 'v1.epub'}) => Volume(
  seriesOpdsId: id,
  title: 'Book $id',
  fileName: file,
  downloadUrl: 'http://pc/$id/$file',
  fileSizeBytes: 0,
  updatedAt: DateTime(2026, 11, 1),
);

ReadingEntry _entry(int id, {int chapter = 11, bool finished = false, int daysAgo = 1}) => ReadingEntry(
  volume: _volume(id),
  progress: ReadingProgress(
    chapterIndex: chapter,
    blockIndex: 1,
    chapterCount: 76,
    endReached: finished,
    updatedAt: _today.subtract(Duration(days: daysAgo)),
  ),
);

void main() {
  final library = [for (var i = 1; i <= 12; i++) _series(i)];

  List<TonightPick> tonight({
    List<ReadingEntry> shelf = const [],
    List<ReadingEntry> entries = const [],
    Map<int, SeriesStatus> statuses = const {},
    Map<int, RecommendationFeedback> feedback = const {},
    Set<int> skipped = const {},
    List<Series>? lib,
    List<int> similarIds = const [3, 1, 4],
    DateTime? day,
  }) {
    final source = lib ?? library;
    return pickTonight(
      library: source,
      shelf: shelf,
      entries: entries,
      statuses: statuses,
      feedback: feedback,
      skipped: skipped,
      today: day ?? _today,
      similar: (_) => [
        for (final id in similarIds) source.firstWhere((s) => s.opdsId == id),
      ],
      lengths: const {7: BookLength(words: 150000, estimated: false, finished: true)},
      wordsPerMinute: 250,
    );
  }

  group('tonight', () {
    test('three picks: one to carry on with, one like the last finished, one wildcard', () {
      final picks = tonight(
        shelf: [_entry(1)],
        entries: [_entry(1), _entry(2, finished: true, daysAgo: 3)],
      );
      expect(picks.map((p) => p.kind), [
        TonightKind.carryOn,
        TonightKind.likeLast,
        TonightKind.wildcard,
      ]);
      expect(picks[0].series.opdsId, 1);
      expect(picks[0].reason, 'Chapter 12 of 76');
      expect(picks[1].series.opdsId, 3, reason: 'book 1 is already open, so not new');
      expect(picks[1].reason, startsWith('Like Book 2, which you finished'));
      expect({1, 2, 3}, isNot(contains(picks[2].series.opdsId)));
    });

    test('the same three all day', () {
      final a = tonight(shelf: [_entry(1)], entries: [_entry(1)], day: _today);
      final b = tonight(shelf: [_entry(1)], entries: [_entry(1)], day: _today.add(const Duration(hours: 2)));
      expect(b.map((p) => p.series.opdsId), a.map((p) => p.series.opdsId));
    });

    test('Not now swaps a pick for another', () {
      final first = tonight(shelf: [_entry(1)], entries: [_entry(1), _entry(5)]);
      final skippedId = first[0].series.opdsId;
      final again = tonight(shelf: [_entry(1)], entries: [_entry(1), _entry(5)], skipped: {skippedId});
      expect(again.map((p) => p.series.opdsId), isNot(contains(skippedId)));
      expect(again.length, 3);
    });

    test('books set aside, adult or without a cover are never offered as new', () {
      final lib = [
        _series(1),
        _series(2, genres: 'Romance, Adult'),
        _series(3, cover: false),
        _series(4),
        _series(5),
      ];
      final picks = tonight(lib: lib, feedback: {4: RecommendationFeedback.snoozed}, similarIds: [2, 3, 4, 5]);
      final ids = picks.map((p) => p.series.opdsId).toSet();
      expect(ids.intersection({2, 3, 4}), isEmpty);
      expect(ids, containsAll([1, 5]));
    });

    test('a book being tried, read since, is the one to carry on with', () {
      final picks = tonight(
        shelf: [_entry(1, daysAgo: 4)],
        entries: [_entry(1, daysAgo: 4), _entry(6, chapter: 1, daysAgo: 0)],
        statuses: {6: SeriesStatus.trying},
      );
      expect(picks.first.series.opdsId, 6);
      expect(picks.first.reason, 'Trying it · Chapter 2 of 76');
    });

    test('with nothing finished, the like-this pick follows the book on the go', () {
      final picks = tonight(shelf: [_entry(1)], entries: [_entry(1)]);
      expect(picks[1].reason, startsWith('Like Book 1, which you are reading'));
    });

    test('a pick says how big a commitment it is', () {
      final picks = tonight(entries: [_entry(2, finished: true)], similarIds: [7]);
      final like = picks.firstWhere((p) => p.kind == TonightKind.likeLast);
      expect(like.series.opdsId, 7);
      expect(like.reason, 'Like Book 2, which you finished · A finished story · about 10 h');
    });

    test('Decide for me never picks the book already on the go', () {
      final picks = tonight(shelf: [_entry(1)], entries: [_entry(1)]);
      for (var seed = 0; seed < 20; seed++) {
        expect(decideFor(picks, math.Random(seed))!.kind, isNot(TonightKind.carryOn));
      }
    });
  });

  group('stalled books', () {
    test('a month untouched comes up; recent, finished, paused or kept do not', () {
      final entries = [
        _entry(1, daysAgo: 40),
        _entry(2, daysAgo: 10),
        _entry(3, daysAgo: 50, finished: true),
        _entry(4, daysAgo: 60),
        _entry(5, daysAgo: 45),
        _entry(6, daysAgo: 70),
      ];
      final stalled = stalledBooks(
        entries,
        {4: SeriesStatus.paused, 6: SeriesStatus.trying},
        now: _today,
        keptAt: {5: _today.subtract(const Duration(days: 3))},
      );
      expect(stalled.map((e) => e.volume.seriesOpdsId), [6, 1]);
    });
  });

  group('hours', () {
    test('short, medium and long', () {
      const short = BookLength(words: 6000, estimated: false, finished: true);
      const mid = BookLength(words: 60000, estimated: false, finished: true);
      const long = BookLength(words: 4500000, estimated: true, finished: false);
      expect(hoursToRead(short, 250), 'about 25 min');
      expect(hoursToRead(mid, 250), 'about 4 h');
      expect(hoursToRead(long, 250), 'about 300 h');
      expect(hoursToRead(mid, 0), 'about 4 h', reason: 'no pace measured yet uses 250 wpm');
      expect(hoursToRead(mid, 26), 'about 4 h', reason: '26 wpm is a ledger missing words, not a pace');
      expect(hoursToRead(mid, 400), 'about 3 h');
      expect(lengthLine(long, 250), 'Still being written · about 300 h');
      expect(hoursToRead(null, 250), isNull);
    });
  });

  group('trying a book first', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await useInMemoryDatabase();
    });

    tearDown(AppDatabase.reset);

    test('a book never opened is only being tried', () async {
      expect(await const TryItFirst().markIfNew(_volume(9)), isTrue);
      expect(await SeriesStatusStore().statusFor(9), SeriesStatus.trying);
    });

    test('a series already read is not', () async {
      await ReadingProgressStore().save(
        _volume(8),
        const ReadingProgress(chapterIndex: 40, blockIndex: 0, chapterCount: 76),
      );
      expect(await const TryItFirst().markIfNew(_volume(8, file: 'v2.epub')), isFalse);
      expect(await SeriesStatusStore().statusFor(8), SeriesStatus.none);
    });

    test('it asks after the third chapter, and Ask me later waits three more', () async {
      const tryIt = TryItFirst();
      await tryIt.markIfNew(_volume(9));
      expect(await tryIt.shouldAsk(9, 2), isFalse);
      expect(await tryIt.shouldAsk(9, 3), isTrue);
      await tryIt.askLater(9, 3);
      expect(await tryIt.shouldAsk(9, 5), isFalse);
      expect(await tryIt.shouldAsk(9, 6), isTrue);
      await tryIt.keep(9);
      expect(await tryIt.shouldAsk(9, 9), isFalse);
      expect(await SeriesStatusStore().statusFor(9), SeriesStatus.reading);
    });

    test('Not now lasts the day, and the limit starts at three', () async {
      final store = ChoosingStore.instance;
      await store.skipToday(4, _today);
      expect(await store.skippedToday(_today), {4});
      expect(await store.skippedToday(_today.add(const Duration(days: 1))), isEmpty);
      expect(await store.booksAtOnce(), 3);
      await store.setBooksAtOnce(0);
      expect(await store.booksAtOnce(), 0);
    });

    test('the check-in comes round once a week', () async {
      final store = ChoosingStore.instance;
      expect(await store.checkInDue(_today), isTrue);
      await store.checkedIn(_today);
      expect(await store.checkInDue(_today.add(const Duration(days: 6))), isFalse);
      expect(await store.checkInDue(_today.add(const Duration(days: 7))), isTrue);
    });
  });

  group('mood', () {
    Series s(int id, String genres, {int chapters = 100}) => Series(
      opdsId: id,
      title: 'Book $id',
      author: 'A',
      description: 'About it.',
      genres: genres.split(', '),
      readingStatus: '',
      totalChapters: chapters,
      downloadedChapters: chapters,
      coverUrl: 'http://pc/cover/$id',
      updatedAt: null,
      directEpubUrl: null,
      volumesFeedUrl: null,
    );
    final lib = [
      s(1, 'Romance, Comedy', chapters: 120),
      s(2, 'Romance, Fantasy', chapters: 2000),
      s(3, 'Action, Martial Arts'),
      s(4, 'romance, Adult'),
      s(5, 'Slice of Life', chapters: 900),
    ];
    List<int> ids(Set<Mood> moods, {Map<int, BookLength> lengths = const {}}) => [
      for (final p in pickForMood(
        library: lib,
        moods: moods,
        entries: const [],
        statuses: const {},
        feedback: const {},
        today: _today,
        lengths: lengths,
        count: 10,
      ))
        p.series.opdsId,
    ]..sort();

    test('one mood: books whose genres fit it, adult left out', () {
      expect(ids({Mood.romance}), [1, 2]);
      expect(ids({Mood.light}), [1, 5]);
    });

    test('two moods: books that fit both', () {
      expect(ids({Mood.romance, Mood.short}), [1]);
    });

    test('short goes by hours when the length is known, else chapters', () {
      const long = BookLength(words: 600000, estimated: false, finished: true);
      expect(ids({Mood.short}, lengths: {1: long}), [3]);
    });

    test('finished stories only', () {
      const done = BookLength(words: 1000, estimated: false, finished: true);
      expect(ids({Mood.finished}, lengths: {2: done}), [2]);
    });

    test('no mood, no picks; each says what it fits', () {
      expect(ids({}), isEmpty);
      final p = pickForMood(
        library: lib, moods: {Mood.action}, entries: const [], statuses: const {},
        feedback: const {}, today: _today,
      ).single;
      expect(p.reason, 'Fits action');
    });
  });

  group('this or that', () {
    test('the one tapped stays on, neither skips both, and wins rank the pile', () {
      final books = [for (var i = 1; i <= 8; i++) _series(i)];
      final game = ThisOrThat(books, rounds: 5);
      expect(game.current, (books[0], books[1]));
      game.choose(books[1]); // 2 beats 1
      expect(game.current, (books[1], books[2]));
      game.choose(books[1]); // 2 beats 3
      game.choose(books[3]); // 4 beats 2
      game.neither(); // 4 and 5 both go
      expect(game.current, (books[5], books[6]));
      game.choose(books[6]); // 7 beats 6
      expect(game.current, isNull, reason: 'five rounds played');
      expect(game.rank(), [2, 4, 7]);
    });

    test('the pile comes before the wildcard, and says why', () {
      final picks = tonight(entries: [_entry(1)], similarIds: [3]);
      final withPile = pickTonight(
        library: library,
        shelf: const [],
        entries: const [],
        statuses: const {},
        feedback: const {},
        similar: (_) => const [],
        today: _today,
        pile: const [9, 8],
      );
      expect(picks, isNotEmpty);
      expect(withPile.map((p) => p.series.opdsId).take(2), [9, 8]);
      expect(withPile.first.reason, 'You picked it in This or that');
    });
  });

  group('just arrived', () {
    test('added this week and never opened', () {
      Series added(int id, int daysAgo) => Series(
        opdsId: id,
        title: 'Book $id',
        author: 'A',
        description: 'About it.',
        genres: const ['Fantasy'],
        readingStatus: '',
        totalChapters: 10,
        downloadedChapters: 10,
        coverUrl: 'http://pc/cover/$id',
        updatedAt: null,
        directEpubUrl: null,
        volumesFeedUrl: null,
        addedAt: _today.subtract(Duration(days: daysAgo)),
      );
      final lib = [added(1, 1), added(2, 3), added(3, 9), added(4, 0)];
      expect(justArrived(lib, [_entry(2)], _today), {1, 4});
    });
  });
}
