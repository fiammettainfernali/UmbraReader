// The Discover shelf as a thing you can act on: feedback that moves it, and
// impressions that only count cards a reader was actually shown.
//
// Both were broken in the same direction. Feedback ran an unforced reload
// whose signature check said "nothing changed" — so a dismiss redrew the
// identical shelf — while impressions were stamped from the tab's initState,
// inside the shell's IndexedStack, at a launch that opens on Library. The
// shelf recorded verdicts nobody gave and ignored the ones they did.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/discover_screen.dart';
import 'package:umbra_reader/screens/home_shell.dart';
import 'package:umbra_reader/screens/library_cards.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/library_cache.dart';
import 'package:umbra_reader/services/library_storage.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/rec_outcome_store.dart';
import 'package:umbra_reader/services/settings_service.dart';

import 'helpers/reader_fonts.dart';
import 'helpers/test_db.dart';

/// One documents directory for the whole test, so the library cache written
/// during setup is the one the screen reads back. (A provider that makes a
/// temp directory per call hands every reader a different empty library.)
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// The card FOR a series, found by the series it was built with.
///
/// Not `find.text(title)`: a card also renders the engine's "Because…"
/// line, which quotes the title of the seed a pick resembles — so a bare
/// text finder matches both the card for a series and the reason line of
/// every card recommended because of it.
Finder _cardFor(String title) => find.byWidgetPredicate(
  (w) => w is RecommendCard && w.series.title == title,
  description: 'RecommendCard for "$title"',
);

Series _series({
  required int id,
  required String title,
  required String author,
  required List<String> genres,
}) => Series(
  opdsId: id,
  title: title,
  author: author,
  description: '',
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: 100,
  downloadedChapters: 0,
  coverUrl: null,
  // Undated on purpose: with no updatedAt or addedAt, Discover draws neither
  // the "Recently updated" nor the "Recently added" shelf, which together
  // push the recommendations off the bottom of a test screen — and a card
  // below the fold cannot be tapped.
  updatedAt: null,
  addedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

Volume _volume(int seriesId) => Volume(
  seriesOpdsId: seriesId,
  title: 'Vol 1',
  fileName: 'v1.epub',
  downloadUrl: '',
  fileSizeBytes: 0,
  updatedAt: null,
);

const _settings = OpdsSettings(baseUrl: '', username: '', password: '');

/// A theme whose text is measured in a font that exists. Without naming a
/// registered family, every string here would lay out in the placeholder
/// font `flutter test` falls back to — see [loadUiFont].
final _testTheme = ThemeData(fontFamily: kTestUiFont);

/// Writes the cached library and one deep read of [readId].
///
/// Through [WidgetTester.runAsync] because it is real file and SQLite work,
/// which the fake clock inside a widget test will not drive. The read has to
/// be deep: taste has to come from somewhere, or the engine takes its
/// cold-start path, where feedback is not consulted at all.
Future<void> _seedLibrary(
  WidgetTester tester,
  List<Series> library, {
  required int readId,
}) async {
  await tester.runAsync(() async {
    await LibraryCache(LibraryStorage()).saveSeries(library);
    await ReadingProgressStore().save(
      _volume(readId),
      const ReadingProgress(chapterIndex: 8, blockIndex: 0, chapterCount: 10),
    );
  });
}

/// The stores are real SQLite and real files here, so the frames have to be
/// allowed to actually wait on them.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<Map<int, RecOutcome>> _outcomes(WidgetTester tester) async =>
    await tester.runAsync(() => RecOutcomeStore().load()) ??
    const <int, RecOutcome>{};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // These tests lay out real screens at phone width, so text has to
    // measure like text. See loadUiFont.
    await loadUiFont();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    PathProviderPlatform.instance = _FakePathProvider(
      Directory.systemTemp.createTempSync('umbra_discover').path,
    );
  });

  tearDown(() {
    CloudSyncService().cancelPendingTimers();
    return AppDatabase.reset();
  });

  testWidgets('a dismissed recommendation leaves the shelf', (tester) async {
    // Two candidates by the author of the one book that has been read, so
    // both are firmly recommended whatever the learner does with genres.
    await _seedLibrary(tester, [
      _series(id: 1, title: 'The Read One', author: 'Lu', genres: ['Xianxia']),
      _series(id: 2, title: 'Candidate Two', author: 'Lu', genres: ['Xianxia']),
      _series(
        id: 3,
        title: 'Candidate Three',
        author: 'Lu',
        genres: ['Xianxia'],
      ),
    ], readId: 1);

    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: const DiscoverScreen(settings: _settings, isSelected: true),
      ),
    );
    await _settle(tester);
    expect(_cardFor('Candidate Two'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: _cardFor('Candidate Two'),
        matching: find.byType(DismissChip),
      ),
    );
    await _settle(tester);

    // The point of the whole exercise: "not interested" used to record the
    // dismissal and then redraw the identical shelf, because the reload it
    // ran is the one the library-signature check throws away.
    expect(
      _cardFor('Candidate Two'),
      findsNothing,
      reason: 'the dismissed card is gone, not merely noted',
    );
    expect(
      _cardFor('Candidate Three'),
      findsOneWidget,
      reason: 'one dismissal is not a verdict on the whole shelf',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('impressions wait until Discover is the tab on screen', (
    tester,
  ) async {
    // A folded Fold: the shelf holds ten cards and this shows about three.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Five candidates that clear the engine's per-author (2) and per-genre
    // (3) caps: distinct primary genres, one genre in common with the book
    // that was read, authors in pairs.
    await _seedLibrary(tester, [
      _series(id: 1, title: 'The Read One', author: 'Lu', genres: ['Xianxia']),
      _series(
        id: 2,
        title: 'Pick Two',
        author: 'Bo',
        genres: ['Adventure', 'Xianxia'],
      ),
      _series(
        id: 3,
        title: 'Pick Three',
        author: 'Bo',
        genres: ['Mystery', 'Xianxia'],
      ),
      _series(
        id: 4,
        title: 'Pick Four',
        author: 'Cai',
        genres: ['Comedy', 'Xianxia'],
      ),
      _series(
        id: 5,
        title: 'Pick Five',
        author: 'Cai',
        genres: ['Drama', 'Xianxia'],
      ),
      _series(
        id: 6,
        title: 'Pick Six',
        author: 'Da',
        genres: ['Romance', 'Xianxia'],
      ),
    ], readId: 1);

    await tester.pumpWidget(
      MaterialApp(theme: _testTheme, home: const HomeShell()),
    );
    await _settle(tester);

    // Discover is alive in the shell's IndexedStack from launch: its
    // initState has run and it has ranked its picks — which is exactly how
    // every launch used to bank a screenful of verdicts for cards nobody
    // had seen. The cards themselves are deliberately NOT asserted here:
    // an unselected IndexedStack child is built but never laid out, so the
    // shelf's lazy list builds no cards at all while the app sits on
    // Library. That is the state being pinned — ranked, unseen, unrecorded.
    // `skipOffstage: false` because that is precisely the state being
    // pinned: an unselected IndexedStack child is offstage, and finders
    // skip offstage widgets by default. The cards ARE built and ranked —
    // the reader simply has not seen them, which is how every launch used
    // to bank a screenful of verdicts.
    expect(
      find.byType(RecommendCard, skipOffstage: false),
      findsWidgets,
      reason: 'the picks are built and ranked, they are just not on show',
    );
    expect(
      await _outcomes(tester),
      isEmpty,
      reason: 'nothing has been on screen yet',
    );

    await tester.tap(find.byIcon(Icons.travel_explore_outlined));
    await _settle(tester);

    // Two populations on purpose: every card the shelf built, and the ones
    // actually on screen. A horizontal list scrolls its overflow offstage
    // and finders skip offstage widgets by default, so the plain finder is
    // already "what the reader can see" — taking the first N of it would
    // have compared that set against itself and proved nothing.
    final built = tester
        .widgetList<RecommendCard>(
          find.byType(RecommendCard, skipOffstage: false),
        )
        .toList();
    final visible = tester
        .widgetList<RecommendCard>(find.byType(RecommendCard))
        .toList();
    expect(
      built.length,
      greaterThan(visible.length),
      reason: 'the shelf has more picks than this screen can show at once',
    );
    final onScreen = {for (final c in visible) c.series.opdsId};

    expect(
      (await _outcomes(tester)).keys.toSet(),
      onScreen,
      reason: 'only the cards this screen actually fits count as shown',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
