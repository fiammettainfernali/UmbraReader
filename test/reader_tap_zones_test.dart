// Tap routing in the reader: while the chrome (menus) is visible, ANY
// content tap only dismisses it — the page-turn edge zones must stay
// dormant. Regression for "tapping to close the menu sometimes turned a
// page".

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
    <dc:title>Tap Zones</dc:title>
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
  <body><h1>Chapter One</h1><p>Short first chapter.</p></body>
</html>''';

const _ch2 = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>Chapter Two</h1><p>Second chapter text.</p></body>
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
  seriesOpdsId: 4,
  title: 'Tap Zones',
  fileName: 'tap.epub',
  downloadUrl: 'http://unused/tap.epub',
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    tempDir = Directory.systemTemp.createTempSync('umbra_tap');
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

  testWidgets('edge tap with chrome visible only dismisses the chrome', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);
    expect(find.textContaining('Short first', findRichText: true),
        findsOneWidget);

    // Chrome starts visible. A tap in the right-edge page-turn zone must
    // NOT advance — it only hides the chrome.
    final size = tester.getSize(find.byType(ReaderScreen));
    await tester.tapAt(Offset(size.width * 0.9, size.height * 0.5));
    await _settle(tester);
    expect(
      find.textContaining('Short first', findRichText: true),
      findsOneWidget,
      reason: 'closing the chrome must not turn the page',
    );

    // Chrome is now hidden: the same tap advances (short chapter → ch2).
    await tester.tapAt(Offset(size.width * 0.9, size.height * 0.5));
    await _settle(tester);
    expect(
      find.textContaining('Second chapter', findRichText: true),
      findsOneWidget,
      reason: 'with chrome hidden the edge tap pages forward',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('paged ruler: taps step the band, then turn the page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_mode': 'paged',
      'reader_line_focus': true,
    });
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);
    expect(find.textContaining('Short first', findRichText: true),
        findsOneWidget);

    final size = tester.getSize(find.byType(ReaderScreen));
    final rightEdge = Offset(size.width * 0.9, size.height * 0.5);
    await tester.tapAt(rightEdge); // hide chrome
    await _settle(tester);

    // First advance must step the band, NOT turn the page (this chapter is
    // a single page — without the stepping band it would jump to ch2).
    await tester.tapAt(rightEdge);
    await _settle(tester);
    expect(
      find.textContaining('Short first', findRichText: true),
      findsOneWidget,
      reason: 'the first tap steps the focus band, not the page',
    );

    // Keep advancing: once the band reaches the page bottom, the next tap
    // turns the page for real.
    var turned = false;
    for (var i = 0; i < 15 && !turned; i++) {
      await tester.tapAt(rightEdge);
      await _settle(tester);
      turned = find
          .textContaining('Second chapter', findRichText: true)
          .evaluate()
          .isNotEmpty;
    }
    expect(turned, isTrue, reason: 'band rollover must still turn pages');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('left-handed mode swaps the turn sides', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_left_handed_taps': true,
    });
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);

    final size = tester.getSize(find.byType(ReaderScreen));
    final leftEdge = Offset(size.width * 0.08, size.height * 0.5);
    await tester.tapAt(leftEdge); // hide chrome
    await _settle(tester);

    // Left-handed: the LEFT edge goes forward.
    await tester.tapAt(leftEdge);
    await _settle(tester);
    expect(
      find.textContaining('Second chapter', findRichText: true),
      findsOneWidget,
      reason: 'left-handed: a left-edge tap must page forward',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('swipe-only guard: an edge tap never turns the page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_tap_turn_zones': false,
    });
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);

    final size = tester.getSize(find.byType(ReaderScreen));
    final rightEdge = Offset(size.width * 0.9, size.height * 0.5);
    await tester.tapAt(rightEdge); // hide chrome
    await _settle(tester);
    // With edge turns disabled, tapping the edge just toggles chrome back —
    // it must not advance.
    await tester.tapAt(rightEdge);
    await _settle(tester);
    expect(
      find.textContaining('Short first', findRichText: true),
      findsOneWidget,
      reason: 'the accidental-turn guard must block edge-tap page turns',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('sliding the left edge dims the brightness', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);

    final size = tester.getSize(find.byType(ReaderScreen));
    // Drag down along the left-edge gutter (x within the 24px strip).
    await tester.dragFrom(
      Offset(10, size.height * 0.4),
      Offset(0, size.height * 0.4),
    );
    await _settle(tester);

    final prefs = await SharedPreferences.getInstance();
    final brightness = prefs.getDouble('reader_brightness');
    expect(brightness, isNotNull, reason: 'the drag end must persist brightness');
    expect(
      brightness,
      lessThan(1.0),
      reason: 'dragging down the left edge must dim the page',
    );
    expect(brightness, greaterThanOrEqualTo(0.15));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('long-press on a word opens the dictionary for it', (
    tester,
  ) async {
    final defined = <String>[];
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

    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);

    final paragraph = find.textContaining('Short first', findRichText: true);
    expect(paragraph, findsOneWidget);
    // Press ON the first word — the widget's centre is past the end of this
    // short line, which correctly resolves to nothing.
    await tester.longPressAt(
      tester.getTopLeft(paragraph) + const Offset(24, 12),
    );
    await tester.pump();

    expect(defined, hasLength(1), reason: 'long-press must hit the bridge');
    expect(
      RegExp('Short|first|chapter').hasMatch(defined.single),
      isTrue,
      reason: 'looked-up word was "${defined.single}"',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
