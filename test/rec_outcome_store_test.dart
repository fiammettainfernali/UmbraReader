// Tests for RecOutcomeStore — impression/tap outcome tallies per series.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/services/rec_outcome_store.dart';

import 'helpers/test_db.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  test('impressions count at most once per series per day', () async {
    final store = RecOutcomeStore();
    final monday = DateTime(2026, 7, 6, 9);
    await store.recordImpressions([1, 2], now: monday);
    // The same shelf redrawn later the same day must not double-count.
    await store.recordImpressions([
      1,
      2,
    ], now: monday.add(const Duration(hours: 8)));
    var outcomes = await store.load();
    expect(outcomes[1]!.impressions, 1);
    expect(outcomes[2]!.impressions, 1);

    // A new day counts again.
    await store.recordImpressions([
      1,
    ], now: monday.add(const Duration(days: 1)));
    outcomes = await store.load();
    expect(outcomes[1]!.impressions, 2);
    expect(outcomes[2]!.impressions, 1);
  });

  test('taps accumulate and zero the ignored count', () async {
    final store = RecOutcomeStore();
    final day = DateTime(2026, 7, 6, 9);
    await store.recordImpressions([5], now: day);
    await store.recordImpressions([5], now: day.add(const Duration(days: 1)));
    var outcomes = await store.load();
    expect(outcomes[5]!.ignored, 2, reason: 'shown twice, never opened');

    await store.recordTap(5, now: day.add(const Duration(days: 1)));
    outcomes = await store.load();
    expect(outcomes[5]!.taps, 1);
    expect(
      outcomes[5]!.ignored,
      0,
      reason: 'a tapped series is not "ignored" no matter the impressions',
    );
  });

  test('outcomes nothing has touched in two months are forgotten', () async {
    // The tally used to be one-way: every impression was permanent, so a
    // series shown a dozen times last spring kept the engine's ignored
    // penalty for good — and the launch-time phantom impressions that
    // predate the visibility fix had no way off the device at all.
    final store = RecOutcomeStore();
    final spring = DateTime(2026, 3, 1, 9);
    await store.recordImpressions([1], now: spring);
    // Tap-only: its lastShownDay is empty, which must not read as "shown
    // before the dawn of time and therefore immortal".
    await store.recordTap(2, now: spring);
    await store.recordImpressions([
      4,
    ], now: spring.add(const Duration(days: 80)));

    final removed = await store.pruneStale(
      now: spring.add(const Duration(days: 90)),
    );
    expect(removed, 2);
    expect((await store.load()).keys, [4]);
  });

  test('a recent tap keeps a row that has not been shown in months', () async {
    // Opening a series is the strongest thing this table records. Expiry is
    // about forgetting stale guesses, not throwing away an answer.
    final store = RecOutcomeStore();
    final spring = DateTime(2026, 3, 1, 9);
    await store.recordImpressions([7], now: spring);
    await store.recordTap(7, now: spring.add(const Duration(days: 85)));

    await store.pruneStale(now: spring.add(const Duration(days: 90)));
    expect((await store.load())[7]?.taps, 1);
  });

  test('a tap on a never-shown series creates its row', () async {
    final store = RecOutcomeStore();
    await store.recordTap(9);
    final outcomes = await store.load();
    expect(outcomes[9]!.taps, 1);
    expect(outcomes[9]!.impressions, 0);
  });
}
