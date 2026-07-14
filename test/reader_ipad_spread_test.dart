// iPad two-page spread: paged mode on a tablet-sized LANDSCAPE viewport
// renders facing pages (stride 2) like an open book; phones and portrait
// stay single-page. Rotating must keep the reading position instead of
// jumping to a stale spread index.

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

final _longChapter = List.generate(
  120,
  (p) => '<p>${List.generate(60, (w) => 'para${p}word$w').join(' ')}</p>',
).join();

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
    <dc:title>Spread</dc:title><dc:creator>Test</dc:creator>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>''');
  add('OEBPS/ch1.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>Long</h1>$_longChapter</body>
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
  seriesOpdsId: 31,
  title: 'Spread',
  fileName: 'spread.epub',
  downloadUrl: 'http://unused/spread.epub',
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

void _setViewport(WidgetTester tester, Size logical) {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = logical * 2.0;
}

int _stride(WidgetTester tester) =>
    (tester.state(find.byType(ReaderScreen)) as dynamic).debugPageStride
        as int;

int _topBlock(WidgetTester tester) =>
    (tester.state(find.byType(ReaderScreen)) as dynamic).currentTopBlockIndex()
        as int;

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_mode': 'paged',
    });
    await useInMemoryDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    tempDir = Directory.systemTemp.createTempSync('umbra_spread');
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

  testWidgets('tablet landscape gets a spread; portrait and phones do not', (
    tester,
  ) async {
    addTearDown(tester.view.reset);

    _setViewport(tester, const Size(1194, 834)); // iPad landscape
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);
    expect(_stride(tester), 2, reason: 'iPad landscape reads as an open book');

    _setViewport(tester, const Size(834, 1194)); // iPad portrait
    await _settle(tester);
    expect(_stride(tester), 1, reason: 'portrait is a single page');

    _setViewport(tester, const Size(812, 375)); // phone landscape
    await _settle(tester);
    expect(_stride(tester), 1,
        reason: 'phone landscape is too small for facing pages');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('rotation keeps the reading position', (tester) async {
    addTearDown(tester.view.reset);

    _setViewport(tester, const Size(834, 1194)); // iPad portrait
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);

    // Swipe forward well into the chapter (real page turns).
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
    }
    await _settle(tester);
    final before = _topBlock(tester);
    expect(before, greaterThan(0), reason: 'we must be deep into the book');

    // Rotate to landscape: repagination + spread. The position must follow.
    _setViewport(tester, const Size(1194, 834));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_stride(tester), 2);
    final after = _topBlock(tester);
    expect(after, greaterThan(0),
        reason: 'rotation must not reset to the chapter start');
    expect((after - before).abs(), lessThanOrEqualTo(4),
        reason: 'stopped at block $before, rotated to $after — the spread '
            'containing the reading position must be restored');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
