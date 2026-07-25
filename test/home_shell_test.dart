// The app's root gained a bottom bar, and annotations gained a home of their
// own — they were previously reachable only from the bookmarks sheet inside a
// book, so there was no way to see them across the library at all.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/bookmark.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/home_shell.dart';
import 'package:umbra_reader/screens/notes_screen.dart';
import 'package:umbra_reader/services/bookmark_store.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/test_db.dart';

/// The library reads a download manifest from disk on mount.
class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.createTempSync('umbra_shell').path;
}

Volume _volume() => Volume(
  seriesOpdsId: 1,
  title: 'Saga Vol 1',
  fileName: 'saga-v1.epub',
  downloadUrl: 'http://unused/x.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
);

Bookmark _mark({
  String id = 'a',
  bool highlight = false,
  String note = '',
  String selected = '',
}) => Bookmark(
  id: id,
  chapterIndex: 2,
  blockIndex: 5,
  chapterTitle: 'Chapter 3',
  snippet: 'a saved spot',
  createdAt: DateTime.utc(2026, 7, 1),
  isHighlight: highlight,
  note: note,
  selectedText: selected,
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
    PathProviderPlatform.instance = _FakePathProvider();
  });

  tearDown(() {
    CloudSyncService().cancelPendingTimers();
    return AppDatabase.reset();
  });

  testWidgets('the shell offers four destinations and opens on Library', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await _settle(tester);

    for (final label in ['Library', 'Discover', 'Notes', 'You']) {
      expect(find.text(label), findsWidgets, reason: '$label destination');
    }
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('Notes is reachable from the bar without opening a book', (
    tester,
  ) async {
    // The whole point: annotations used to require going into a book first.
    await BookmarkStore().add(
      _volume(),
      _mark(highlight: true, selected: 'the sect elder is the traitor'),
    );
    await ReadingProgressStore().save(
      _volume(),
      const ReadingProgress(chapterIndex: 2, blockIndex: 0, chapterCount: 10),
    );

    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.bookmark_border).last);
    await _settle(tester);

    expect(find.byType(NotesScreen), findsOneWidget);
    expect(find.text('the sect elder is the traitor'), findsOneWidget);
    expect(
      find.textContaining('Saga Vol 1'),
      findsWidgets,
      reason: 'each note says which book it came from',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('Notes explains itself when there is nothing saved', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
    await _settle(tester);
    expect(find.text('No notes yet'), findsOneWidget);
  });

  testWidgets('Notes can filter down to highlights and notes', (tester) async {
    await ReadingProgressStore().save(
      _volume(),
      const ReadingProgress(chapterIndex: 2, blockIndex: 0, chapterCount: 10),
    );
    await BookmarkStore().add(_volume(), _mark(id: 'plain'));
    await BookmarkStore().add(
      _volume(),
      _mark(id: 'lit', highlight: true, selected: 'a highlighted passage'),
    );

    await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
    await _settle(tester);
    expect(find.text('a saved spot'), findsOneWidget);
    expect(find.text('a highlighted passage'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();
    expect(
      find.text('a saved spot'),
      findsNothing,
      reason: 'plain bookmarks are navigation, not thoughts',
    );
    expect(find.text('a highlighted passage'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
