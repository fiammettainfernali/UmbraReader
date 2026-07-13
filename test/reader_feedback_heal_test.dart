// Re-engagement healing: a real reading session (>=5 min) in a series clears
// stale recommendation feedback (dismiss/reset) so the series can rejoin
// taste; a quick skim does not.

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
import 'package:umbra_reader/services/recommendation_feedback_store.dart';

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
    <dc:title>Heal</dc:title><dc:creator>Test</dc:creator>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>''');
  add('OEBPS/ch1.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>One</h1><p>Some chapter text to read.</p></body>
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
  seriesOpdsId: 21,
  title: 'Heal',
  fileName: 'heal.epub',
  downloadUrl: 'http://unused/heal.epub',
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

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    tempDir = Directory.systemTemp.createTempSync('umbra_heal');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    final file = await LibraryStorage().epubFile(_volume());
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_buildEpub());
  });

  tearDown(() {
    ReaderScreen.debugSessionDelta = null;
    CloudSyncService().cancelPendingTimers();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // harmless on Windows
    }
  });

  Future<void> readThenBackground(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  }

  testWidgets('a real session clears a stale reset', (tester) async {
    await RecommendationFeedbackStore().recordReset(21);
    ReaderScreen.debugSessionDelta = const Duration(minutes: 6);

    await readThenBackground(tester);

    final feedback = await RecommendationFeedbackStore().load();
    expect(feedback.containsKey(21), isFalse,
        reason: 'six minutes of reading is re-engagement — the old '
            '"no thanks" must stop suppressing the series');
  });

  testWidgets('a quick skim does not clear feedback', (tester) async {
    await RecommendationFeedbackStore().recordDismiss(21);
    ReaderScreen.debugSessionDelta = const Duration(minutes: 1);

    await readThenBackground(tester);

    final feedback = await RecommendationFeedbackStore().load();
    expect(feedback[21], RecommendationFeedback.dismissed,
        reason: 'peeking at a book is not re-engagement');
  });
}
