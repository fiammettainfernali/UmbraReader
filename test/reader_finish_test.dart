// Regression: finishing a book must set endReached so it leaves the
// Continue Reading shelf — including the two paths that historically
// dropped the signal:
//  1. scroll mode with a final chapter short enough to fit the viewport
//     (maxScrollExtent == 0 meant "never at the end"), and
//  2. swiping past the end of the last chapter (the end-of-volume prompt
//     path returned early without saving).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/screens/reader_screen.dart';
import 'package:umbra_reader/services/library_storage.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/test_db.dart';

const _containerXml = '''<?xml version="1.0"?>
<container version="1.0"
    xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf"
        media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

const _opf = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0"
    unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Short Ending</dc:title>
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
</package>''';

const _ch1 = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>Chapter One</h1><p>A chapter of ordinary length.</p></body>
</html>''';

// The regression case: the final chapter fits on one screen.
const _ch2 = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>The End</h1><p>Fin.</p></body>
</html>''';

List<int> _buildEpub() {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('META-INF/container.xml', _containerXml);
  add('OEBPS/content.opf', _opf);
  add('OEBPS/ch1.xhtml', _ch1);
  add('OEBPS/ch2.xhtml', _ch2);
  return ZipEncoder().encode(archive);
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Volume _volume() => Volume(
  seriesOpdsId: 3,
  title: 'Short Ending',
  fileName: 'short.epub',
  downloadUrl: 'http://unused/short.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
);

/// Pumps with real event-loop time until the reader finishes loading.
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
    // The reader talks to flutter_tts on chapter changes; there's no
    // platform in `flutter test`, so stub the channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    tempDir = Directory.systemTemp.createTempSync('umbra_finish');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    // Place the EPUB where LibraryStorage expects the downloaded volume.
    final file = await LibraryStorage().epubFile(_volume());
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_buildEpub());
  });

  tearDown(() {
    // A progress save arms a 3-second debounced iCloud push; cancel it so
    // no timer outlives the test body.
    CloudSyncService().cancelPendingTimers();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold handles briefly; a leaked temp dir is harmless.
    }
  });

  testWidgets('short final chapter marks the book finished (scroll mode)', (
    tester,
  ) async {
    final volume = _volume();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);

    // Chapter 1 is open; a short chapter has nothing to scroll, but that's
    // NOT the last chapter, so the book must not read as finished.
    await tester.tap(
      find.byTooltip('Next chapter (long-press to skip ahead)'),
    );
    await _settle(tester);
    expect(find.textContaining('Fin', findRichText: true), findsOneWidget);

    // Backgrounding saves the position — the whole (short) last chapter is
    // visible, so this must record endReached.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    final progress = await tester.runAsync(
      () => ReadingProgressStore().load(volume),
    );
    expect(progress!.chapterIndex, 1);
    expect(
      progress.isFinished,
      isTrue,
      reason: 'a fully-visible final chapter must count as read to the end',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('a stuck caught-up book heals on open + close alone', (
    tester,
  ) async {
    final volume = _volume();
    // The stuck state this regression is about: sitting at the end of the
    // last chapter, but endReached was never recorded.
    await ReadingProgressStore().save(
      volume,
      const ReadingProgress(chapterIndex: 1, blockIndex: 1, chapterCount: 2),
    );
    expect(
      (await ReadingProgressStore().load(volume)).isFinished,
      isFalse,
      reason: 'precondition: the book is stuck in progress',
    );

    // Open the book… and just close it. No scrolling, no page turns, no
    // app lifecycle event — the restore-time save must do the healing.
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);
    expect(find.textContaining('Fin', findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final progress = await tester.runAsync(
      () => ReadingProgressStore().load(volume),
    );
    expect(
      progress!.isFinished,
      isTrue,
      reason: 'opening a book resting at its end must record the finish',
    );
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('advancing past the last chapter marks the book finished', (
    tester,
  ) async {
    final volume = _volume();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    await _settle(tester);

    await tester.tap(
      find.byTooltip('Next chapter (long-press to skip ahead)'),
    ); // → chapter 2 (last)
    await _settle(tester);

    // The chevron is disabled on the last chapter; going "past the end" is
    // the right-edge page-turn tap — which only works with the chrome
    // hidden (a tap with chrome up just dismisses it), so tap twice.
    final size = tester.getSize(find.byType(ReaderScreen));
    await tester.tapAt(Offset(size.width * 0.9, size.height * 0.5));
    await _settle(tester); // first tap: hides the chrome
    await tester.tapAt(Offset(size.width * 0.9, size.height * 0.5));
    await _settle(tester); // second tap: pages past the end

    final progress = await tester.runAsync(
      () => ReadingProgressStore().load(volume),
    );
    expect(
      progress!.isFinished,
      isTrue,
      reason: 'swiping past the final chapter is the finish signal',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
