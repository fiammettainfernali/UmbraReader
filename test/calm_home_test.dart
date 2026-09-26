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

/// Scrolls [target] into view. The grid is a lazy sliver, so its cards are
/// not merely off-screen when they sit below the fold — they have not been
/// built, and no finder will see them.
Future<void> _scrollTo(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );

/// Taps "Browse all" and returns to the top of the resulting list.
///
/// Both halves matter. The button sits below the fold once a few books are
/// in progress, so it has to be scrolled to before it can be tapped at all;
/// and the scroll view keeps that offset when the content swaps, so the
/// browse view arrives already scrolled past its own controls.
Future<void> _tapBrowseAll(WidgetTester tester) async {
  await tester.ensureVisible(find.textContaining('Browse all'));
  // ensureVisible starts an ANIMATED scroll. Tapping before it has been
  // pumped to completion aims at where the button used to be, the hit test
  // lands on nothing, and the only sign is a "tap missed" warning buried in
  // the output while the assertion fails somewhere else entirely.
  await _settle(tester);
  await tester.tap(find.textContaining('Browse all'));
  await _settle(tester);
  await tester.scrollUntilVisible(
    find.byType(SearchBar),
    -400,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
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
    // Three books on the go at once, which is how this reader actually
    // reads — the calm home has to account for all of them, not just the
    // last one touched.
    for (final id in [1, 2, 3]) {
      await ReadingProgressStore().save(
        _volume(id),
        ReadingProgress(
          chapterIndex: 7 + id,
          blockIndex: 2,
          chapterCount: 40,
          updatedAt: DateTime(2026, 9, 20 + id),
        ),
      );
    }
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

  testWidgets('every book on the go is reachable, not just the newest', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpLibrary(tester);

    // Three books are open. The first calm home showed only the most recent
    // one and dropped the rest, which left a reader who keeps several going
    // at once with no way to any of them except the grid the calm view is
    // there to avoid.
    for (final id in [1, 2, 3]) {
      expect(
        find.textContaining('Book $id'),
        findsWidgets,
        reason: 'Book $id is in progress and must be reachable',
      );
    }
    // Still calm: the shelf is the reading, not the machinery.
    expect(find.byType(SearchBar), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(SeriesCard), findsNothing);
  });

  testWidgets('the whole library is one tap away', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpLibrary(tester);
    await _tapBrowseAll(tester);

    expect(find.byType(SearchBar), findsOneWidget);
    expect(
      find.textContaining('Browse all'),
      findsNothing,
      reason: 'already browsing',
    );
    await _scrollTo(tester, find.byType(SeriesCard).first);
    expect(find.byType(SeriesCard), findsWidgets);
  });

  testWidgets('every launch starts calm again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpLibrary(tester);
    await _tapBrowseAll(tester);
    expect(find.byType(SearchBar), findsOneWidget, reason: 'now browsing');

    // Tear the screen down first: pumping the same widget type again only
    // rebuilds the existing State, which is not what a launch does. A real
    // launch builds a new one, and that is what has to start calm.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // Nothing about browsing is remembered. This is the whole reason the
    // flag is session-only: a remembered view is how the reading-state chip
    // became a trap that quietly removed the resume card from every launch.
    await _pumpLibrary(tester);

    // Asserted on the search field rather than the absence of grid cards:
    // the grid is lazy, so "no cards built" is true of the browse view too
    // whenever they sit below the fold, and an assertion that passes either
    // way proves nothing. The search field is at the top of the browse view
    // and nowhere in the calm one.
    expect(find.byType(SearchBar), findsNothing);
    expect(find.textContaining('Browse all'), findsOneWidget);
  });
}
