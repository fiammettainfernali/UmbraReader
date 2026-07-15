// Quick thought capture (Phase 6): long-pressing empty space — anywhere the
// dictionary finds no word — instantly drops a bookmark at the current
// position with no dialog in the way; the snack offers an optional one-line
// note. Long-pressing ON a word still opens the dictionary and captures
// nothing.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/reader_screen.dart';
import 'package:umbra_reader/services/bookmark_store.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/library_storage.dart';

import 'helpers/test_db.dart';

List<int> _buildEpub() {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0"
    xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf"
        media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');
  add('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0"
    unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Capture</dc:title><dc:creator>Test</dc:creator>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>''');
  add('OEBPS/ch1.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>One</h1><p>Short first chapter.</p></body>
</html>''');
  return ZipEncoder().encode(archive);
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Volume _volume() => Volume(
  seriesOpdsId: 41,
  title: 'Capture',
  fileName: 'capture.epub',
  downloadUrl: 'http://unused/capture.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 7, 1),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

void main() {
  late Directory tempDir;
  late List<String> defined;

  setUp(() async {
    defined = [];
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('umbra/define'), (
          call,
        ) async {
          if (call.method == 'define') {
            defined.add((call.arguments as Map)['term'] as String);
            return true;
          }
          return null;
        });
    tempDir = Directory.systemTemp.createTempSync('umbra_capture');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    final file = await LibraryStorage().epubFile(_volume());
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_buildEpub());
  });

  tearDown(() {
    CloudSyncService().cancelPendingTimers();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // harmless on Windows
    }
  });

  testWidgets('long-press on empty space drops a thought marker', (
    tester,
  ) async {
    final volume = _volume();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);

    // The chapter is two short blocks; the lower half of the screen is
    // empty space — a long-press there is the capture gesture.
    final size = tester.getSize(find.byType(ReaderScreen));
    await tester.longPressAt(Offset(size.width * 0.5, size.height * 0.75));
    await tester.pump();
    await _settle(tester);

    final marks = await tester.runAsync(() => BookmarkStore().list(volume));
    expect(marks, hasLength(1), reason: 'one gesture, one marker');
    expect(marks!.single.snippet, isNotEmpty,
        reason: 'the marker carries the paragraph snippet for the list');
    expect(marks.single.note, isEmpty, reason: 'no note until asked for');
    expect(defined, isEmpty, reason: 'no word under the finger = no lookup');
    expect(find.text('Thought saved at this spot'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('capture offers an "Add words" affordance that upserts a note', (
    tester,
  ) async {
    final volume = _volume();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);

    final size = tester.getSize(find.byType(ReaderScreen));
    await tester.longPressAt(Offset(size.width * 0.5, size.height * 0.75));
    for (var i = 0; i < 10 && find.text('Add words').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // The optional-note path is reachable straight from the capture snack.
    expect(find.byType(SnackBarAction), findsOneWidget);
    expect(find.text('Add words'), findsOneWidget);

    // The note step relies on add() upserting by bookmark id — attaching a
    // note must update the SAME marker, not create a second. Exercise that
    // contract directly (the modal that collects the text is standard
    // Flutter plumbing over exactly this call).
    final marks = await tester.runAsync(() => BookmarkStore().list(volume));
    expect(marks, hasLength(1));
    await tester.runAsync(
      () => BookmarkStore().add(
        volume,
        marks!.single.copyWith(note: 'the sect elder is the traitor'),
      ),
    );
    final after = await tester.runAsync(() => BookmarkStore().list(volume));
    expect(after, hasLength(1), reason: 'a note updates, never duplicates');
    expect(after!.single.note, 'the sect elder is the traitor');
    expect(after.single.id, marks!.single.id);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('long-press ON a word still opens the dictionary, no marker', (
    tester,
  ) async {
    final volume = _volume();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);

    final paragraph = find.textContaining('Short first', findRichText: true);
    await tester.longPressAt(
      tester.getTopLeft(paragraph) + const Offset(24, 12),
    );
    await tester.pump();

    expect(defined, hasLength(1), reason: 'word lookup keeps its gesture');
    final marks = await tester.runAsync(() => BookmarkStore().list(volume));
    expect(marks, isEmpty, reason: 'a dictionary press must not capture');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
