// Tests for ReadingActivityStore — daily / per-volume reading-time tallies.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';

Volume _volume({int seriesId = 1, String fileName = 'book.epub'}) => Volume(
  seriesOpdsId: seriesId,
  title: 'A Book',
  fileName: fileName,
  downloadUrl: '',
  fileSizeBytes: 0,
  updatedAt: null,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

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
