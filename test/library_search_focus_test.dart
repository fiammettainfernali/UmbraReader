// Typing in the Library's search box used to close the keyboard after one
// letter. The first letter turns the home view (spotlight, rows) into plain
// results, which took the spotlight out from above the search box; with no
// key, the box's place in the list was taken for the spotlight's old one,
// so a new search box was built in its stead, without the focus.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/screens/home_shell.dart';
import 'package:umbra_reader/screens/library_home.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/library_cache.dart';
import 'package:umbra_reader/services/library_storage.dart';

import 'helpers/reader_fonts.dart';
import 'helpers/test_db.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Series _series(int id, String title) => Series(
  opdsId: id,
  title: title,
  author: 'Someone',
  // Over 80 characters, which the spotlight asks of a book before showing it.
  description: 'A long enough story about a road, a harbour and the people '
      'who walk it, told over a hundred chapters.',
  genres: const ['Fantasy'],
  readingStatus: 'ongoing',
  totalChapters: 100,
  downloadedChapters: 100,
  // A cover, so the spotlight shows above the search box: its going away is
  // what moved the box.
  coverUrl: 'http://127.0.0.1:9/opds/cover/$id',
  updatedAt: null,
  addedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadUiFont();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'opds_base_url': 'http://127.0.0.1:9',
      'onboarding_done': true,
    });
    await useInMemoryDatabase();
    PathProviderPlatform.instance = _FakePathProvider(
      Directory.systemTemp.createTempSync('umbra_search_focus').path,
    );
  });

  tearDown(() {
    CloudSyncService().cancelPendingTimers();
    return AppDatabase.reset();
  });

  testWidgets('typing in the library search keeps the keyboard up', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() => LibraryCache(LibraryStorage()).saveSeries([
      for (var i = 1; i <= 8; i++) _series(i, 'Novel Number $i'),
    ]));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: kTestUiFont),
      home: const HomeShell(),
    ));
    await _settle(tester);

    final box = find.descendant(of: find.byType(SearchBar), matching: find.byType(EditableText));
    expect(box, findsOneWidget);
    expect(find.byType(SpotlightCarousel), findsOneWidget,
        reason: 'the home view, with the spotlight above the search box');
    await tester.showKeyboard(box);
    await tester.pump();
    expect(tester.widget<EditableText>(box).focusNode.hasFocus, isTrue,
        reason: 'the box has the focus before anything is typed');

    await tester.enterText(box, 'N');
    await _settle(tester);

    expect(box, findsOneWidget);
    expect(tester.widget<EditableText>(box).focusNode.hasFocus, isTrue,
        reason: 'the box that was typed in still has the focus');
    expect(tester.testTextInput.isVisible, isTrue, reason: 'so the keyboard stays up');

    await tester.enterText(box, 'No');
    await _settle(tester);
    expect(tester.widget<EditableText>(box).focusNode.hasFocus, isTrue,
        reason: 'and a second letter can follow');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
