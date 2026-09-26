// The earned view, end to end: it renders a real ledger, and it does not
// greet a reader's backlog with a fanfare.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/stats_awards.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/reader_fonts.dart';
import 'helpers/test_db.dart';

Series _series(int id) => Series(
  opdsId: id,
  title: 'Series $id',
  author: 'Author',
  description: '',
  genres: const ['Fantasy'],
  readingStatus: 'ongoing',
  totalChapters: 100,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  addedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

ReadingEntry _finished(int id) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: id,
    title: 'Vol',
    fileName: 'v$id.epub',
    downloadUrl: '',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: ReadingProgress(
    chapterIndex: 19,
    blockIndex: 1,
    chapterCount: 20,
    endReached: true,
    updatedAt: DateTime(2026, 8, 1),
  ),
);

ReadingActivity _ledger(int hours) => ReadingActivity(
  dailySeconds: {
    for (var i = 0; i < 40; i++)
      '2026-08-${(i + 1).toString().padLeft(2, '0')}': (hours * 3600) ~/ 40,
  },
  perVolumeSeconds: const {'1/v1.epub': 3600},
  dailyWords: const {'2026-08-01': 40000},
);

/// Scrolls [target] into the viewport before asserting on it.
///
/// The view is a lazy list, so anything below the fold is not merely
/// off-screen — it has not been built, and no finder will see it however
/// the offstage flag is set.
Future<void> _scrollTo(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );

Future<void> _pump(WidgetTester tester, ReadingActivity activity) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: kTestUiFont),
      home: Scaffold(
        body: AwardsView(
          activity: activity,
          entries: [_finished(1), _finished(2)],
          library: [_series(1), _series(2)],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadUiFont();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  testWidgets('shows a level, the ladders and what was found', (tester) async {
    await _pump(tester, _ledger(30));

    expect(find.textContaining('Level '), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Hours in books'), findsOneWidget);

    await _scrollTo(tester, find.text('Found along the way'));
    expect(find.text('Found along the way'), findsOneWidget);

    await _scrollTo(tester, find.text('Year by year'));
    expect(find.text('Year by year'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
  });

  testWidgets('a backlog is filed quietly, not announced', (tester) async {
    // Thirty hours and two finished books already on the record. Shipping
    // the feature is not an achievement, and saying so would spend the
    // novelty of the whole thing in one toast.
    await _pump(tester, _ledger(30));

    expect(find.text('New since last time'), findsNothing);
  });

  testWidgets('what is earned afterwards is announced once', (tester) async {
    await _pump(tester, _ledger(30));
    // Reading on to 60 hours crosses the 50-hour rung.
    await _pump(tester, _ledger(60));

    expect(find.text('New since last time'), findsOneWidget);

    // And it is not still being announced on the next visit: a badge that
    // keeps repeating itself stops being news and starts being nagging.
    await _pump(tester, _ledger(60));
    expect(find.text('New since last time'), findsNothing);
  });

  testWidgets('a reader with nothing yet is not scolded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: kTestUiFont),
        home: const Scaffold(
          body: AwardsView(
            activity: ReadingActivity.empty,
            entries: [],
            library: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Level 1'), findsOneWidget);

    await _scrollTo(tester, find.textContaining('not a checklist'));
    expect(
      find.textContaining('not a checklist'),
      findsOneWidget,
      reason: 'the empty state explains rather than demands',
    );
  });
}
