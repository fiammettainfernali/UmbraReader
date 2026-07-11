// Gentle session timer: a quiet fill appears when a target is set, and once
// the target is passed a dismissible break check-in surfaces at the next
// chapter boundary (never mid-page).

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
    <dc:title>Session</dc:title><dc:creator>Test</dc:creator>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/><itemref idref="ch2"/></spine>
</package>''');
  add('OEBPS/ch1.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>One</h1><p>Short first chapter.</p></body>
</html>''');
  add('OEBPS/ch2.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>Two</h1><p>Second chapter text.</p></body>
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
  seriesOpdsId: 12,
  title: 'Session',
  fileName: 'session.epub',
  downloadUrl: 'http://unused/session.epub',
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

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_mode': 'paged',
      'reader_session_minutes': 15,
    });
    await useInMemoryDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    tempDir = Directory.systemTemp.createTempSync('umbra_session');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    final file = await LibraryStorage().epubFile(_volume());
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_buildEpub());
  });

  tearDown(() {
    ReaderScreen.debugSessionElapsed = null;
    CloudSyncService().cancelPendingTimers();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // harmless on Windows
    }
  });

  Future<void> hideThenAdvance(WidgetTester tester) async {
    final size = tester.getSize(find.byType(ReaderScreen));
    final edge = Offset(size.width * 0.9, size.height * 0.5);
    await tester.tapAt(edge); // chrome visible → first tap hides it
    await _settle(tester);
    await tester.tapAt(edge); // advances (single-page chapter → chapter cross)
    await _settle(tester);
  }

  testWidgets('the quiet fill shows only when a target is set', (tester) async {
    ReaderScreen.debugSessionElapsed = const Duration(minutes: 3);
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);
    expect(find.byKey(const ValueKey('session_fill')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('passing the target offers a break at the next chapter', (
    tester,
  ) async {
    ReaderScreen.debugSessionElapsed = const Duration(minutes: 20); // > 15
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);
    // Nothing mid-page yet.
    expect(find.textContaining('good time for a break'), findsNothing);

    await hideThenAdvance(tester); // cross into chapter two
    expect(find.textContaining('Second chapter', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('good time for a break'), findsOneWidget);

    // Tapping it dismisses.
    await tester.tap(find.textContaining('good time for a break'));
    await tester.pump();
    expect(find.textContaining('good time for a break'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('under the target, no break check-in appears', (tester) async {
    ReaderScreen.debugSessionElapsed = const Duration(minutes: 5); // < 15
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);
    await hideThenAdvance(tester);
    expect(find.textContaining('Second chapter', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('good time for a break'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
