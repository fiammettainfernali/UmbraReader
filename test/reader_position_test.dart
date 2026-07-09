// Reading-position precision (Kindle-location / EPUB-CFI grade):
//  - stopping mid-way through a huge paragraph must restore to the same
//    LINE, not the paragraph top, and
//  - a saved chapter is re-found by its spine path if indexes shift.

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
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/library_storage.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/test_db.dart';

final _hugeParagraph = List.generate(
  900,
  (w) => w % 11 == 0 ? 'wonderful' : 'word$w',
).join(' ');

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
    <dc:title>Precision</dc:title>
    <dc:creator>Test Author</dc:creator>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''');
  add('OEBPS/ch1.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>Giant One</h1><p>$_hugeParagraph</p></body>
</html>''');
  add('OEBPS/ch2.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>Second</h1><p>Second chapter text here.</p></body>
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
  seriesOpdsId: 5,
  title: 'Precision',
  fileName: 'precision.epub',
  downloadUrl: 'http://unused/precision.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
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

double _scrollOffset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    tempDir = Directory.systemTemp.createTempSync('umbra_precision');
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

  testWidgets('mid-paragraph position restores to the same line', (
    tester,
  ) async {
    final volume = _volume();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);

    // Scroll deep into the giant paragraph.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1500));
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1500));
    await tester.pump();
    final before = _scrollOffset(tester);
    expect(before, greaterThan(1000));

    // Save via the lifecycle path, then close.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final saved = await tester.runAsync(
      () => ReadingProgressStore().load(volume),
    );
    expect(
      saved!.blockChar,
      greaterThan(0),
      reason: 'a mid-paragraph stop must record the character offset',
    );
    expect(saved.chapterPath, 'OEBPS/ch1.xhtml');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // Reopen: the restored offset must be within a couple of lines of where
    // reading stopped — NOT back at the paragraph top.
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);
    final after = _scrollOffset(tester);
    expect(
      (after - before).abs(),
      lessThan(80),
      reason:
          'stopped at $before, restored to $after — drift must stay within '
          'a couple of lines (block-only precision restored to 0)',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('a shifted chapter is re-found by its spine path', (
    tester,
  ) async {
    final volume = _volume();
    // Simulate a stale index from a recompiled volume: the number says
    // chapter 0, but the saved spine path is chapter 2's.
    await ReadingProgressStore().save(
      volume,
      const ReadingProgress(
        chapterIndex: 0,
        blockIndex: 1,
        chapterPath: 'OEBPS/ch2.xhtml',
        chapterCount: 2,
      ),
    );

    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);
    expect(
      find.textContaining('Second chapter', findRichText: true),
      findsOneWidget,
      reason: 'the spine path outranks the stale numeric index',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
