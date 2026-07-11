// The haptic-feedback kill-switch must actually silence the reader's taps:
// with it off, a page turn fires no HapticFeedback platform call.

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
    <dc:title>Haptics</dc:title><dc:creator>Test</dc:creator>
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
  seriesOpdsId: 9,
  title: 'Haptics',
  fileName: 'haptics.epub',
  downloadUrl: 'http://unused/haptics.epub',
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
  var hapticCalls = 0;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: _volume())));
    await _settle(tester);
  }

  setUp(() async {
    hapticCalls = 0;
    await useInMemoryDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    // Count the reader's haptic taps; pass everything else (orientation,
    // wakelock, etc.) through as no-ops.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') hapticCalls++;
          return null;
        });
    tempDir = Directory.systemTemp.createTempSync('umbra_haptics');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    final file = await LibraryStorage().epubFile(_volume());
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_buildEpub());
  });

  tearDown(() {
    CloudSyncService().cancelPendingTimers();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // harmless on Windows
    }
  });

  Future<void> hideThenAdvance(WidgetTester tester) async {
    final size = tester.getSize(find.byType(ReaderScreen));
    final edge = Offset(size.width * 0.9, size.height * 0.5);
    await tester.tapAt(edge); // chrome visible → first tap only hides it
    await _settle(tester);
    await tester.tapAt(edge); // now this advances (fires a haptic if enabled)
    await _settle(tester);
  }

  testWidgets('a page turn taps by default', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_mode': 'paged',
    });
    await pump(tester);
    final before = hapticCalls;
    await hideThenAdvance(tester);
    expect(hapticCalls, greaterThan(before),
        reason: 'the default is haptics on');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });

  testWidgets('haptics off silences the page turn', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_mode': 'paged',
      'reader_haptic_feedback': false,
    });
    await pump(tester);
    final before = hapticCalls;
    await hideThenAdvance(tester);
    expect(hapticCalls, before,
        reason: 'with the kill-switch on, no haptic call should fire');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CloudSyncService().cancelPendingTimers();
  });
}
