// "Where was I?" re-entry aid: reopening a book after a real gap surfaces a
// recap chip; reopening straight away does not.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/reader_screen.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/library_storage.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

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
    <dc:title>Reentry</dc:title><dc:creator>Test</dc:creator>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>''');
  add('OEBPS/ch1.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>Chapter</h1>
  <p>First paragraph of context.</p>
  <p>Second paragraph of context.</p>
  <p>Third paragraph, where we left off.</p></body>
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
  seriesOpdsId: 11,
  title: 'Reentry',
  fileName: 'reentry.epub',
  downloadUrl: 'http://unused/reentry.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
);

Future<void> _seedPosition(Volume volume, {required bool stale}) async {
  await ReadingProgressStore().save(
    volume,
    const ReadingProgress(
      chapterIndex: 0,
      blockIndex: 3, // the "where we left off" paragraph
      chapterPath: 'OEBPS/ch1.xhtml',
      chapterCount: 1,
    ),
  );
  if (stale) {
    // save() stamps updatedAt = now; backdate it so the reopen is a "gap".
    final key = '${volume.seriesOpdsId}/${volume.fileName}';
    final old = DateTime.now()
        .subtract(const Duration(hours: 2))
        .toIso8601String();
    final db = AppDatabase.instance;
    await (db.update(db.readingProgressRows)
          ..where((t) => t.volumeKey.equals(key)))
        .write(ReadingProgressRowsCompanion(updatedAt: Value(old)));
  }
}

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

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    tempDir = Directory.systemTemp.createTempSync('umbra_reentry');
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

  testWidgets('resuming after a gap offers a recap', (tester) async {
    final volume = _volume();
    await _seedPosition(volume, stale: true);

    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);

    expect(find.text('Where was I?'), findsOneWidget);

    await tester.tap(find.text('Where was I?'));
    await tester.pumpAndSettle();
    expect(find.text('WHERE YOU LEFT OFF'), findsOneWidget);
    // The recap includes the paragraph we stopped on.
    expect(
      find.textContaining('where we left off', findRichText: true),
      findsWidgets,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('resuming immediately shows no recap chip', (tester) async {
    final volume = _volume();
    await _seedPosition(volume, stale: false); // fresh timestamp

    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);

    expect(find.text('Where was I?'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
