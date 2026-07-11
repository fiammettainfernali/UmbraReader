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
    await store.recordImpressions([1, 2], now: monday.add(
      const Duration(hours: 8),
    ));
    var outcomes = await store.load();
    expect(outcomes[1]!.impressions, 1);
    expect(outcomes[2]!.impressions, 1);

    // A new day counts again.
    await store.recordImpressions([1], now: monday.add(
      const Duration(days: 1),
    ));
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
    expect(outcomes[5]!.ignored, 0,
        reason: 'a tapped series is not "ignored" no matter the impressions');
  });

  test('a tap on a never-shown series creates its row', () async {
    final store = RecOutcomeStore();
    await store.recordTap(9);
    final outcomes = await store.load();
    expect(outcomes[9]!.taps, 1);
    expect(outcomes[9]!.impressions, 0);
  });
}
