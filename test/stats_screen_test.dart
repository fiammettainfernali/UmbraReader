// The stats screen was restructured around a period selector; it previously
// had no test coverage at all. This drives the real screen to check the
// selector is present, the headline responds to it, and lifetime totals are
// still reachable rather than dropped.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/stats_screen.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/test_db.dart';

Volume _volume() => Volume(
  seriesOpdsId: 1,
  title: 'Saga Vol 1',
  fileName: 'saga-v1.epub',
  downloadUrl: 'http://unused/x.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(() {
    // record() arms a debounced iCloud push that would outlive the test.
    CloudSyncService().cancelPendingTimers();
    return AppDatabase.reset();
  });

  testWidgets('offers a period selector and defaults to the week', (
    tester,
  ) async {
    await ReadingProgressStore().save(
      _volume(),
      const ReadingProgress(chapterIndex: 2, blockIndex: 0, chapterCount: 10),
    );
    await ReadingActivityStore().record(
      _volume(),
      const Duration(minutes: 30),
      words: 6000,
    );

    await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
    await _settle(tester);

    for (final p in StatsPeriod.values) {
      expect(find.text(p.label), findsOneWidget, reason: '${p.label} segment');
    }
    expect(
      find.text('read this week'),
      findsOneWidget,
      reason: 'opens on the week, not all time',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('switching the period changes what the headline reports', (
    tester,
  ) async {
    await ReadingActivityStore().record(
      _volume(),
      const Duration(minutes: 30),
      words: 6000,
    );
    await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
    await _settle(tester);
    expect(find.text('read this week'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('read all time'), findsOneWidget);
    expect(find.text('read this week'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('lifetime totals are kept, below the period figures', (
    tester,
  ) async {
    await ReadingProgressStore().save(
      _volume(),
      const ReadingProgress(chapterIndex: 2, blockIndex: 0, chapterCount: 10),
    );
    await ReadingActivityStore().record(
      _volume(),
      const Duration(minutes: 30),
      words: 6000,
    );
    await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
    await _settle(tester);

    // Below the period figures by design, so scroll to it — which also
    // proves it is still reachable rather than dropped.
    await tester.scrollUntilVisible(find.text('All time'), 300);
    await tester.pumpAndSettle();
    expect(find.text('All time'), findsOneWidget);
    expect(find.text('Books started'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('groups the breakdown by series, not by volume', (tester) async {
    // Three volumes of one series must collapse to a single row.
    for (var v = 1; v <= 3; v++) {
      final vol = Volume(
        seriesOpdsId: 1,
        title: 'Saga Vol $v',
        fileName: 'saga-v$v.epub',
        downloadUrl: 'http://unused/x.epub',
        fileSizeBytes: 0,
        updatedAt: DateTime.utc(2026, 6, 1),
      );
      await ReadingProgressStore().save(
        vol,
        const ReadingProgress(chapterIndex: 2, blockIndex: 0, chapterCount: 10),
      );
      await ReadingActivityStore().record(vol, const Duration(minutes: 10));
    }

    await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('By series'), 300);
    await tester.pumpAndSettle();

    expect(find.text('By series'), findsOneWidget);
    expect(
      find.text('3 volumes'),
      findsOneWidget,
      reason: 'one row covering all three, not three rows',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
