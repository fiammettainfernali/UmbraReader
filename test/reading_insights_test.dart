// Insights, and the two ways they could go wrong: saying something before
// the data can support it, and saying the same thing forever.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/awards.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';
import 'package:umbra_reader/services/reading_insights.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

final _today = DateTime(2026, 9, 25);

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Series _series({
  required int id,
  String title = 'A Series',
  List<String> genres = const ['Fantasy'],
}) => Series(
  opdsId: id,
  title: title,
  author: 'Author',
  description: '',
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: 100,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  addedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

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
    chapterIndex: 19,
    blockIndex: 1,
    chapterCount: 20,
    endReached: true,
    updatedAt: at,
  ),
);

/// [days] consecutive days ending today, [minutes] on each.
AwardContext _steadyReader({
  int days = 120,
  int minutes = 40,
  List<ReadingEntry> entries = const [],
  List<Series> library = const [],
  Map<String, int> perVolumeSeconds = const {},
  Map<String, int> dailyWords = const {},
}) {
  final daily = <String, int>{};
  for (var i = 0; i < days; i++) {
    daily[_key(_today.subtract(Duration(days: i)))] = minutes * 60;
  }
  return AwardContext(
    activity: ReadingActivity(
      dailySeconds: daily,
      perVolumeSeconds: perVolumeSeconds,
      dailyWords: dailyWords,
    ),
    entries: entries,
    library: library,
    now: _today,
  );
}

void main() {
  group('nothing is claimed before the data can support it', () {
    test('a reader with no history gets no insights at all', () {
      final ctx = AwardContext(
        activity: ReadingActivity.empty,
        entries: const [],
        library: const [],
        now: _today,
      );
      expect(allInsights(ctx), isEmpty);
    });

    test('a favourite weekday needs three weeks before it is a pattern', () {
      final thin = _steadyReader(days: 10);
      expect(_ids(thin), isNot(contains('weekday')));
    });

    test('an even week is not reported as a preference', () {
      // Identical minutes every day for months: there is no favourite, and
      // inventing one would be noise dressed up as insight.
      final even = _steadyReader(days: 120, minutes: 40);
      expect(_ids(even), isNot(contains('weekday')));
    });

    test('a real weekday habit is reported', () {
      final daily = <String, int>{};
      for (var i = 0; i < 120; i++) {
        final day = _today.subtract(Duration(days: i));
        // Sundays get three hours, everything else twenty minutes.
        daily[_key(day)] = day.weekday == DateTime.sunday ? 10800 : 1200;
      }
      final ctx = AwardContext(
        activity: ReadingActivity(
          dailySeconds: daily,
          perVolumeSeconds: const {},
        ),
        entries: const [],
        library: const [],
        now: _today,
      );
      final weekday = allInsights(ctx).firstWhere((i) => i.id == 'weekday');
      expect(weekday.headline, contains('Sundays'));
    });

    test('year-on-year waits until there is a last year to compare', () {
      final oneYear = _steadyReader(days: 120);
      expect(_ids(oneYear), isNot(contains('year-on-year')));

      final daily = <String, int>{};
      for (var i = 0; i < 400; i++) {
        daily[_key(_today.subtract(Duration(days: i)))] = 2400;
      }
      final twoYears = AwardContext(
        activity: ReadingActivity(
          dailySeconds: daily,
          perVolumeSeconds: const {},
        ),
        entries: const [],
        library: const [],
        now: _today,
      );
      expect(_ids(twoYears), contains('year-on-year'));
    });

    test('pace is only claimed once there is an hour to measure it over', () {
      final barely = _steadyReader(
        days: 1,
        minutes: 5,
        dailyWords: {_key(_today): 1000},
      );
      expect(_ids(barely), isNot(contains('pace')));
    });
  });

  group('rotation keeps the page fresh without making it unreliable', () {
    late AwardContext ctx;

    setUp(() {
      ctx = _steadyReader(
        days: 400,
        entries: [
          for (var i = 0; i < 6; i++)
            _finished(i, DateTime(2026, 3 + i % 6, 10)),
        ],
        library: [
          for (var i = 0; i < 6; i++)
            _series(id: i, genres: ['Genre$i', 'Fantasy']),
        ],
        perVolumeSeconds: const {'1/v1.epub': 40000},
        dailyWords: {
          for (var i = 0; i < 400; i++)
            _key(_today.subtract(Duration(days: i))): 9000,
        },
      );
    });

    test('the same week always shows the same insights', () {
      // A reader who saw something interesting in the morning has to be able
      // to find it again that evening.
      final morning = rotatingInsights(ctx, now: DateTime(2026, 9, 21, 9));
      final evening = rotatingInsights(ctx, now: DateTime(2026, 9, 25, 22));
      expect([for (final i in morning) i.id], [for (final i in evening) i.id]);
    });

    test('a later week shows something different', () {
      final thisWeek = rotatingInsights(ctx, now: DateTime(2026, 9, 21));
      final nextWeek = rotatingInsights(ctx, now: DateTime(2026, 9, 28));
      expect([
        for (final i in thisWeek) i.id,
      ], isNot([for (final i in nextWeek) i.id]));
    });

    test('every insight comes around rather than starving', () {
      // The whole point of rotating is that the less flashy findings still
      // get their turn; a selection that always favoured the first few would
      // be a fixed list wearing a costume.
      final seen = <String>{};
      for (var week = 0; week < 20; week++) {
        seen.addAll([
          for (final i in rotatingInsights(
            ctx,
            now: DateTime(2026, 1, 5).add(Duration(days: 7 * week)),
          ))
            i.id,
        ]);
      }
      expect(seen.length, allInsights(ctx).length);
    });

    test('a reader with few insights sees all of them, not a padded list', () {
      final thin = _steadyReader(days: 8, minutes: 30);
      final shown = rotatingInsights(thin);
      expect(shown.length, allInsights(thin).length);
      expect(shown.length, lessThanOrEqualTo(3));
    });
  });

  group('the yearly retrospective', () {
    test('summarises a year from the ledger and what was finished in it', () {
      final daily = <String, int>{
        '2025-02-10': 7200,
        '2025-02-11': 3600,
        '2025-07-04': 1800,
        '2026-01-09': 3600, // a different year, must not leak in
      };
      final ctx = AwardContext(
        activity: ReadingActivity(
          dailySeconds: daily,
          perVolumeSeconds: const {'1/v1.epub': 9000},
        ),
        entries: [
          _finished(1, DateTime(2025, 2, 12)),
          _finished(2, DateTime(2026, 1, 9)),
        ],
        library: [
          _series(id: 1, title: 'The Long One', genres: ['Fantasy', 'Action']),
          _series(id: 2, title: 'Next Year', genres: ['Romance']),
        ],
        now: _today,
      );

      final year = yearInReview(ctx, 2025);

      expect(year.hours, 3); // 12,600 seconds
      expect(year.daysRead, 3);
      expect(year.booksFinished, 1, reason: 'the 2026 finish belongs to 2026');
      expect(year.busiestMonth, 2);
      expect(monthName(year.busiestMonth), 'February');
      expect(year.topSeries, 'The Long One');
      expect(year.genres, 2);
      expect(year.isEmpty, isFalse);
    });

    test('a year with nothing in it says so instead of lying', () {
      final ctx = _steadyReader(days: 30);
      expect(yearInReview(ctx, 2019).isEmpty, isTrue);
    });

    test('years are offered newest first', () {
      final ctx = AwardContext(
        activity: ReadingActivity(
          dailySeconds: const {'2024-05-05': 600, '2026-01-01': 600},
          perVolumeSeconds: const {},
        ),
        entries: [_finished(1, DateTime(2025, 6, 1))],
        library: [_series(id: 1)],
        now: _today,
      );
      expect(yearsWithReading(ctx), [2026, 2025, 2024]);
    });
  });
}

List<String> _ids(AwardContext ctx) => [for (final i in allInsights(ctx)) i.id];
