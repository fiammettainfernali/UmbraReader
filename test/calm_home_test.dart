// The calm home: what the library shows before it is asked for anything.
//
// The complaint this answers was that the app had become a chore to open —
// roughly nineteen controls stacked above the grid between launching it and
// carrying on with the book that was already open. So the thing worth
// pinning is not what the calm view contains but what it LEAVES OUT, and
// that the full library is still one tap away.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/library_cards.dart';
import 'package:umbra_reader/screens/library_screen.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/library_cache.dart';
import 'package:umbra_reader/services/library_storage.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/reader_fonts.dart';
import 'helpers/test_db.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Series _series(int id) => Series(
  opdsId: id,
  title: 'Book $id',
  author: 'Author $id',
  description: 'A description.',
  genres: const ['Fantasy'],
  readingStatus: 'ongoing',
  totalChapters: 40,
  downloadedChapters: 40,
  coverUrl: null,
  updatedAt: DateTime(2026, 9, 1),
  addedAt: DateTime(2026, 1, 1),
  directEpubUrl: null,
  volumesFeedUrl: null,
);

Volume _volume(int id) => Volume(
  seriesOpdsId: id,
  title: 'Book $id, Volume 1',
  fileName: 'b$id-v1.epub',
  downloadUrl: 'http://host/b$id.epub',
  fileSizeBytes: 1000,
  updatedAt: null,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _pumpLibrary(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: kTestUiFont),
      home: const LibraryScreen(),
    ),
  );
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadUiFont();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    PathProviderPlatform.instance = _FakePathProvider(
      Directory.systemTemp.createTempSync('umbra_calm').path,
    );
    await LibraryCache(
      LibraryStorage(),
    ).saveSeries([for (var i = 1; i <= 12; i++) _series(i)]);
    // One book in progress, so there is something to carry on with.
    await ReadingProgressStore().save(
      _volume(1),
      const ReadingProgress(chapterIndex: 7, blockIndex: 2, chapterCount: 40),
    );
  });

  tearDown(() {
    CloudSyncService().cancelPendingTimers();
    return AppDatabase.reset();
  });

  testWidgets('opens on the book, not the machinery', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpLibrary(tester);

    // What it leaves out is the point.
    expect(find.byType(SearchBar), findsNothing, reason: 'no search field');
    expect(
      find.byType(ChoiceChip),
      findsNothing,
      reason: 'no reading-state chips',
    );
    expect(find.byType(SeriesCard), findsNothing, reason: 'no wall of covers');

    // And what it keeps: the way back into the book, and one way out.
    expect(find.textContaining('Book 1'), findsWidgets);
    expect(find.textContaining('Browse all'), findsOneWidget);
  });

  testWidgets('the whole library is one tap away', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpLibrary(tester);
    await tester.tap(find.textContaining('Browse all'));
    await _settle(tester);

    expect(find.byType(SeriesCard), findsWidgets);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(
      find.textContaining('Browse all'),
      findsNothing,
      reason: 'already browsing',
    );
  });

  testWidgets('every launch starts calm again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpLibrary(tester);
    await tester.tap(find.textContaining('Browse all'));
    await _settle(tester);
    expect(find.byType(SeriesCard), findsWidgets);

    // Tear the screen down first: pumping the same widget type again only
    // rebuilds the existing State, which is not what a launch does. A real
    // launch builds a new one, and that is what has to start calm.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // Nothing about browsing is remembered. This is the whole reason the
    // flag is session-only: a remembered view is how the reading-state chip
    // became a trap that quietly removed the resume card from every launch.
    await _pumpLibrary(tester);

    expect(find.byType(SeriesCard), findsNothing);
    expect(find.textContaining('Browse all'), findsOneWidget);
  });
}
