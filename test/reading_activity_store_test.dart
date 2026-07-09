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
