// Tests for ReadingActivityStore — daily / per-volume reading-time tallies.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';

import 'helpers/test_db.dart';

Volume _volume({int seriesId = 1, String fileName = 'book.epub'}) => Volume(
  seriesOpdsId: seriesId,
  title: 'A Book',
  fileName: fileName,
  downloadUrl: '',
  fileSizeBytes: 0,
  updatedAt: null,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  test('remote device ledgers merge into totals and streaks', () async {
    final store = ReadingActivityStore();
    // This device read today.
    final today = DateTime(2026, 7, 3, 9);
    await store.record(_volume(), const Duration(minutes: 5), now: today);
    // Another device read yesterday (and adds to the same volume).
    final merged = await store.mergeSyncBlob(
      '{"otherdevice1234":{"daily":{"2026-07-02":600},'
      '"perVolume":{"1/book.epub":600}}}',
    );
    expect(merged, isTrue);

    final activity = await store.load();
    expect(activity.dailySeconds['2026-07-02'], 600);
    expect(activity.dailySeconds['2026-07-03'], 300);
    expect(activity.perVolumeSeconds['1/book.epub'], 900);
    expect(
      activity.currentStreak(now: today),
      2,
      reason: 'yesterday on the other device + today here = 2-day streak',
    );

    // The export carries every ledger; this device's own is included.
    final blob = await store.exportSyncBlob();
    expect(blob, contains('otherdevice1234'));
    expect(blob, contains('2026-07-03'));

    // Merging our own exported blob back must not double-count: our id is
    // skipped, so totals stay identical.
    await store.mergeSyncBlob(blob);
    final again = await store.load();
    expect(again.dailySeconds['2026-07-03'], 300);
    expect(again.perVolumeSeconds['1/book.epub'], 900);
    CloudSyncService().cancelPendingTimers();
  });

  test('todaySeconds reads the local-day bucket', () async {
    final store = ReadingActivityStore();
    final now = DateTime(2026, 7, 2, 21, 30);
    await store.record(_volume(), const Duration(minutes: 10), now: now);
    final activity = await store.load();
    expect(activity.todaySeconds(now: now), 600);
    // A different day sees nothing.
    expect(activity.todaySeconds(now: DateTime(2026, 7, 3, 1)), 0);
  });

  test('load returns empty activity with no data', () async {
    final activity = await ReadingActivityStore().load();
    expect(activity.totalSeconds, 0);
    expect(activity.weekSeconds(), 0);
    expect(activity.currentStreak(), 0);
  });

  test('record adds to today and per-volume tallies', () async {
    final store = ReadingActivityStore();
    final v = _volume();
    final t = DateTime.utc(2026, 5, 20, 12);
    await store.record(v, const Duration(seconds: 90), now: t);
    await store.record(v, const Duration(seconds: 30), now: t);

    final activity = await store.load();
    expect(activity.totalSeconds, 120);
    expect(
      activity.perVolumeSeconds['${v.seriesOpdsId}/${v.fileName}'],
      120,
    );
  });

  test('record ignores zero or negative durations', () async {
    final store = ReadingActivityStore();
    await store.record(_volume(), const Duration(seconds: 0));
    await store.record(_volume(), Duration.zero);
    expect((await store.load()).totalSeconds, 0);
  });

  test('record tallies words per day and per volume', () async {
    final store = ReadingActivityStore();
    final v = _volume();
    final t = DateTime(2026, 7, 3, 12);
    await store.record(v, const Duration(minutes: 5), words: 400, now: t);
    await store.record(v, const Duration(minutes: 5), words: 250, now: t);

    final a = await store.load();
    expect(a.totalWords, 650);
    expect(a.todayWords(now: t), 650);
    expect(a.perVolumeWords['${v.seriesOpdsId}/${v.fileName}'], 650);
    // 10 minutes of reading, 650 words → 65 wpm.
    expect(a.wordsPerMinute, 65);
    // wordsForVolume reports this device's high-water mark for seeding.
    expect(await store.wordsForVolume(v), 650);
  });

  test('record clamps negative word counts to zero', () async {
    final store = ReadingActivityStore();
    await store.record(_volume(), const Duration(minutes: 1), words: -50);
    expect((await store.load()).totalWords, 0);
  });

  test('weekWords sums the last seven days of words', () async {
    final store = ReadingActivityStore();
    final t0 = DateTime(2026, 5, 20, 12);
    for (var i = 0; i < 10; i++) {
      await store.record(
        _volume(),
        const Duration(minutes: 1),
        words: 100,
        now: t0.subtract(Duration(days: i)),
      );
    }
    expect((await store.load()).weekWords(now: t0), 700);
  });

  test('word ledgers merge across devices and survive a JSON round-trip',
      () async {
    final store = ReadingActivityStore();
    final today = DateTime(2026, 7, 3, 9);
    await store.record(_volume(), const Duration(minutes: 5),
        words: 300, now: today);
    // Another device read yesterday, on the same volume.
    await store.mergeSyncBlob(
      '{"otherdevice1234":{"daily":{"2026-07-02":600},'
      '"perVolume":{"1/book.epub":600},'
      '"dailyWords":{"2026-07-02":500},'
      '"perVolumeWords":{"1/book.epub":500}}}',
    );
    final a = await store.load();
    expect(a.totalWords, 800, reason: '300 here + 500 remote');
    expect(a.perVolumeWords['1/book.epub'], 800);
    // Re-merging our own exported blob must not double-count words.
    final blob = await store.exportSyncBlob();
    expect(blob, contains('dailyWords'));
    await store.mergeSyncBlob(blob);
    expect((await store.load()).totalWords, 800);
    CloudSyncService().cancelPendingTimers();
  });

  test('streak grace: today unread keeps the streak alive', () async {
    final store = ReadingActivityStore();
    final v = _volume();
    // Read the last three days, nothing yet today (it's 9am).
    for (var d = 1; d <= 3; d++) {
      await store.record(
        v,
        const Duration(minutes: 10),
        now: DateTime(2026, 7, 3 - d, 12),
      );
    }
    final a = await store.load();
    expect(a.currentStreak(now: DateTime(2026, 7, 3, 9)), 3);
    expect(a.streakUsedGrace(now: DateTime(2026, 7, 3, 9)), isFalse);
  });

  test('streak grace: one rest day per week is forgiven', () async {
    final store = ReadingActivityStore();
    final v = _volume();
    // Read July 1 and July 3 — July 2 was a rest day.
    await store.record(v, const Duration(minutes: 10),
        now: DateTime(2026, 7, 1, 12));
    await store.record(v, const Duration(minutes: 10),
        now: DateTime(2026, 7, 3, 12));
    final a = await store.load();
    expect(
      a.currentStreak(now: DateTime(2026, 7, 3, 20)),
      2,
      reason: 'a single missed day must not zero the streak',
    );
    expect(a.streakUsedGrace(now: DateTime(2026, 7, 3, 20)), isTrue);
  });

  test('streak grace: two gaps in a week end the streak', () async {
    final store = ReadingActivityStore();
    final v = _volume();
    // Read July 1, skipped 2, read 3, skipped 4, reading 5.
    for (final day in [1, 3, 5]) {
      await store.record(v, const Duration(minutes: 10),
          now: DateTime(2026, 7, day, 12));
    }
    final a = await store.load();
    // Walking back from the 5th: the gap on the 4th is forgiven, but the
    // second gap (the 2nd) within the same week is not.
    expect(a.currentStreak(now: DateTime(2026, 7, 5, 20)), 2);
  });

  test('currentStreak counts back from today', () async {
    final store = ReadingActivityStore();
    final t0 = DateTime(2026, 5, 20, 12);
    // Read every day for the last 3 days, then a gap, then one a week back.
    await store.record(_volume(), const Duration(seconds: 60), now: t0);
    await store.record(
      _volume(),
      const Duration(seconds: 60),
      now: t0.subtract(const Duration(days: 1)),
    );
    await store.record(
      _volume(),
      const Duration(seconds: 60),
      now: t0.subtract(const Duration(days: 2)),
    );
    // Gap at day 3.
    await store.record(
      _volume(),
      const Duration(seconds: 60),
      now: t0.subtract(const Duration(days: 6)),
    );

    final activity = await store.load();
    expect(activity.currentStreak(now: t0), 3);
  });

  test('weekSeconds sums the last seven days', () async {
    final store = ReadingActivityStore();
    final t0 = DateTime(2026, 5, 20, 12);
    for (var i = 0; i < 10; i++) {
      await store.record(
        _volume(),
        const Duration(seconds: 100),
        now: t0.subtract(Duration(days: i)),
      );
    }
    final activity = await store.load();
    expect(activity.weekSeconds(now: t0), 700);
  });

  test('per-volume totals are independent', () async {
    final store = ReadingActivityStore();
    final a = _volume(fileName: 'a.epub');
    final b = _volume(fileName: 'b.epub');
    final t = DateTime(2026, 5, 20, 12);
    await store.record(a, const Duration(seconds: 100), now: t);
    await store.record(b, const Duration(seconds: 250), now: t);
    final activity = await store.load();
    expect(activity.perVolumeSeconds['${a.seriesOpdsId}/a.epub'], 100);
    expect(activity.perVolumeSeconds['${b.seriesOpdsId}/b.epub'], 250);
    expect(activity.totalSeconds, 350);
  });
}
