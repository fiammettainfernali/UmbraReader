// Earned dates, and the rule that shipping this feature is not an event.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/services/award_store.dart';
import 'package:umbra_reader/services/awards.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';

import 'helpers/test_db.dart';

/// A ledger holding [hours] on a single day.
AwardContext _ctx(int hours) => AwardContext(
  activity: ReadingActivity(
    dailySeconds: {'2026-09-20': hours * 3600},
    perVolumeSeconds: const {},
  ),
  entries: const [],
  library: const [],
  now: DateTime(2026, 9, 25),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  test('the first pass files a whole history without announcing it', () async {
    final store = AwardStore();
    // Six hours read before the feature existed: several rungs' worth.
    final snapshot = evaluateAwards(_ctx(6));
    expect(snapshot.badgeIds, isNotEmpty);

    final announced = await store.record(snapshot);

    expect(announced, isEmpty, reason: 'a backlog is not news');
    expect(
      (await store.earned()).keys.toSet(),
      snapshot.badgeIds,
      reason: 'but every one of them is on the record',
    );
    expect(await store.unseen(), isEmpty);
  });

  test('what is earned afterwards is news', () async {
    final store = AwardStore();
    await store.record(evaluateAwards(_ctx(6)));

    // Reading on to eleven hours crosses the 10-hour rung.
    final later = evaluateAwards(_ctx(11));
    final announced = await store.record(later);

    expect(announced, isNotEmpty);
    expect(announced, contains('hours.3'));
    expect(await store.unseen(), contains('hours.3'));
  });

  test('being told once is enough', () async {
    final store = AwardStore();
    await store.record(evaluateAwards(_ctx(6)));
    await store.record(evaluateAwards(_ctx(11)));

    await store.markSeen(await store.unseen());
    expect(await store.unseen(), isEmpty);

    // Re-evaluating the same reading must not resurrect it.
    expect(await store.record(evaluateAwards(_ctx(11))), isEmpty);
    expect(await store.unseen(), isEmpty);
  });

  test('an earned date can be the day it really happened', () async {
    final store = AwardStore();
    await store.record(evaluateAwards(_ctx(1)));

    final when = DateTime(2026, 5, 4, 21, 30);
    await store.record(
      evaluateAwards(_ctx(11)),
      earnedDates: {'hours.3': when},
    );

    expect((await store.earned())['hours.3'], when);
  });

  test('re-recording an unchanged history changes nothing', () async {
    final store = AwardStore();
    final snapshot = evaluateAwards(_ctx(6));
    await store.record(snapshot);
    final before = await store.earned();

    await store.record(snapshot);

    expect(await store.earned(), before);
  });
}
