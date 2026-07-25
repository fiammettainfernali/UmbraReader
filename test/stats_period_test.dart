// Period windows for the stats screen. The daily ledger always held enough to
// answer "how did last month go" — these are the accessors that let the screen
// ask, plus the period-on-period comparison that all-time totals can never
// give you.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';

/// Fixed "today" so the windows are deterministic.
final _now = DateTime(2026, 7, 24, 12);

String _key(int daysAgo) {
  final d = DateTime(2026, 7, 24).subtract(Duration(days: daysAgo));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Ledger from {daysAgo: seconds}.
ReadingActivity _activity(Map<int, int> seconds, {Map<int, int>? words}) =>
    ReadingActivity(
      dailySeconds: {for (final e in seconds.entries) _key(e.key): e.value},
      dailyWords: {for (final e in (words ?? {}).entries) _key(e.key): e.value},
      perVolumeSeconds: const {},
      perVolumeWords: const {},
    );

void main() {
  group('windows', () {
    test('a week covers today back through six days ago', () {
      final a = _activity({0: 100, 6: 50, 7: 999});
      expect(
        a.secondsInLast(7, now: _now),
        150,
        reason: 'day 7 is outside the window',
      );
    });

    test('the previous window is the one immediately before', () {
      final a = _activity({0: 10, 7: 200, 13: 5, 14: 999});
      expect(a.secondsInLast(7, now: _now), 10);
      expect(
        a.secondsInPrevious(7, now: _now),
        205,
        reason: 'days 7..13 inclusive, and not day 14',
      );
    });

    test('windows do not overlap', () {
      // Every day carries 1s, so the two windows must partition cleanly.
      final a = _activity({for (var i = 0; i < 14; i++) i: 1});
      expect(a.secondsInLast(7, now: _now), 7);
      expect(a.secondsInPrevious(7, now: _now), 7);
    });

    test('counts days read, not consecutive ones', () {
      final a = _activity({0: 60, 3: 60, 6: 60});
      expect(
        a.daysReadInLast(7, now: _now),
        3,
        reason: 'gaps do not break the count the way a streak would',
      );
    });

    test('the daily series runs oldest first and is the right length', () {
      final a = _activity({0: 3, 1: 2, 2: 1});
      expect(a.dailySeriesLast(4, now: _now), [0, 1, 2, 3]);
    });
  });

  group('period resolution', () {
    test('All reports lifetime, not a window', () {
      final a = _activity({0: 10, 400: 90});
      expect(a.secondsIn(StatsPeriod.all, now: _now), 100);
      expect(
        a.secondsIn(StatsPeriod.year, now: _now),
        10,
        reason: '400 days ago is outside a year',
      );
    });

    test('each period widens the window', () {
      final a = _activity({3: 1, 20: 1, 200: 1});
      expect(a.secondsIn(StatsPeriod.week, now: _now), 1);
      expect(a.secondsIn(StatsPeriod.month, now: _now), 2);
      expect(a.secondsIn(StatsPeriod.year, now: _now), 3);
    });

    test('pace is measured within the period', () {
      // 60s and 300 words in the last week; older data must not dilute it.
      final a = _activity({0: 60, 100: 6000}, words: {0: 300, 100: 100});
      expect(a.wordsPerMinuteIn(StatsPeriod.week, now: _now), 300);
      expect(
        a.wordsPerMinuteIn(StatsPeriod.week, now: _now),
        isNot(a.wordsPerMinute),
        reason: 'the lifetime figure is dragged down by the old session',
      );
    });

    test('days read across all time counts every recorded day', () {
      final a = _activity({0: 5, 40: 5, 900: 5});
      expect(a.daysReadIn(StatsPeriod.all, now: _now), 3);
    });
  });

  group('trend', () {
    test('reports the change against the previous window', () {
      // 200s this week against 100s last week.
      final a = _activity({0: 200, 7: 100});
      expect(a.trendAgainstPrevious(StatsPeriod.week, now: _now), 1.0);
    });

    test('a quieter week reads as a negative, not an error', () {
      final a = _activity({0: 50, 7: 100});
      expect(a.trendAgainstPrevious(StatsPeriod.week, now: _now), -0.5);
    });

    test('no prior window yields null rather than a fake improvement', () {
      // A first week has no "last week" to compare against; dividing by zero
      // would otherwise read as infinite growth.
      final a = _activity({0: 200});
      expect(a.trendAgainstPrevious(StatsPeriod.week, now: _now), isNull);
    });

    test('all-time has nothing to compare against', () {
      final a = _activity({0: 200, 7: 100});
      expect(a.trendAgainstPrevious(StatsPeriod.all, now: _now), isNull);
    });
  });

  group('trend buckets', () {
    test('a week is seven daily buckets, oldest first, weekday-labelled', () {
      final a = _activity({0: 30, 6: 10});
      final b = a.trendBuckets(StatsPeriod.week, now: _now);
      expect(b, hasLength(7));
      expect(b.first.seconds, 10, reason: 'six days ago comes first');
      expect(b.last.seconds, 30, reason: 'today comes last');
      expect(b.every((x) => x.label.isNotEmpty), isTrue);
    });

    test('a month is thirty daily buckets, unlabelled', () {
      final b = _activity({0: 5}).trendBuckets(StatsPeriod.month, now: _now);
      expect(b, hasLength(30));
      expect(
        b.every((x) => x.label.isEmpty),
        isTrue,
        reason: 'thirty labels are unreadable at this size',
      );
    });

    test('a year is twelve monthly buckets ending with this month', () {
      // 5s today (July) and 7s ~2 months back must land in different buckets.
      final a = _activity({0: 5, 62: 7});
      final b = a.trendBuckets(StatsPeriod.year, now: _now);
      expect(b, hasLength(12));
      expect(b.last.seconds, 5, reason: 'the current month is last');
      expect(b.map((x) => x.seconds).reduce((p, c) => p + c), 12);
    });

    test('all-time has no buckets — the heatmap covers it', () {
      expect(_activity({0: 5}).trendBuckets(StatsPeriod.all, now: _now), isEmpty);
    });

    test('an empty ledger still yields a full row of zero buckets', () {
      final b = _activity(const {}).trendBuckets(StatsPeriod.week, now: _now);
      expect(b, hasLength(7));
      expect(b.every((x) => x.seconds == 0), isTrue);
    });
  });

  group('best day / best week', () {
    test('finds the heaviest day in the window', () {
      final a = _activity({0: 30, 2: 900, 5: 60});
      final best = a.bestDayIn(StatsPeriod.week, now: _now);
      expect(best?.seconds, 900);
    });

    test('ignores heavier days outside the window', () {
      final a = _activity({1: 60, 40: 9999});
      expect(a.bestDayIn(StatsPeriod.week, now: _now)?.seconds, 60);
      expect(a.bestDayIn(StatsPeriod.all, now: _now)?.seconds, 9999);
    });

    test('is null when nothing was read', () {
      expect(_activity(const {}).bestDayIn(StatsPeriod.week, now: _now), isNull);
    });

    test('best week sums a rolling seven days, not a calendar week', () {
      // 100 on each of three consecutive days sits inside one rolling week.
      final a = _activity({1: 100, 2: 100, 3: 100});
      expect(a.bestWeekIn(StatsPeriod.month, now: _now), 300);
    });

    test('best week is zero on an empty ledger', () {
      expect(_activity(const {}).bestWeekIn(StatsPeriod.week, now: _now), 0);
    });
  });

  test('an empty ledger answers zero everywhere, not null', () {
    final a = _activity(const {});
    for (final p in StatsPeriod.values) {
      expect(a.secondsIn(p, now: _now), 0);
      expect(a.wordsIn(p, now: _now), 0);
      expect(a.daysReadIn(p, now: _now), 0);
      expect(a.wordsPerMinuteIn(p, now: _now), 0);
    }
  });
}
