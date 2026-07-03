// The "money path", end to end, with no device: a real local HTTP server
// plays the OPDS server, and the app's real client / download / parser /
// progress stack runs against it —
//   browse library → list volumes → download EPUB → parse → read → resume.
//
// The final test opens the downloaded volume in the real ReaderScreen and
// checks the chapter text actually renders.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/reader_screen.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/download_service.dart';
import 'package:umbra_reader/services/epub_parser.dart';
import 'package:umbra_reader/services/library_storage.dart';
import 'package:umbra_reader/services/opds_client.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/settings_service.dart';

import 'helpers/test_db.dart';

// ── a tiny but real EPUB ─────────────────────────────────────────────────────

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
    <dc:title>Integration Novel</dc:title>
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
  <body>
    <h1>Chapter One</h1>
    <p>The integration story begins here.</p>
  </body>
</html>''';

const _ch2 = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <h1>Chapter Two</h1>
    <p>And it continues to a satisfying end.</p>
  </body>
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

// ── a tiny but real OPDS server ──────────────────────────────────────────────

String _libraryFeed(int port) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:ng="urn:novel-grabber">
  <title>All Books</title>
  <entry>
    <id>urn:novel-grabber:novel:7</id>
    <title>Integration Novel</title>
    <author><name>Test Author</name></author>
    <summary>A novel that exists only to be tested.</summary>
    <updated>2026-06-01T00:00:00Z</updated>
    <dc:subject>Fantasy</dc:subject>
    <ng:readingStatus>ongoing</ng:readingStatus>
    <ng:chapters total="2" downloaded="2"/>
    <link rel="subsection" href="http://127.0.0.1:$port/opds/novel/7"
        type="application/atom+xml"/>
  </entry>
</feed>''';

String _volumesFeed(int port, int epubLength) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Integration Novel</title>
  <entry>
    <id>urn:novel-grabber:volume:7:1</id>
    <title>Integration Novel - Volume 01</title>
    <updated>2026-06-01T00:00:00Z</updated>
    <link rel="http://opds-spec.org/acquisition"
        href="http://127.0.0.1:$port/files/vol1.epub"
        type="application/epub+zip" length="$epubLength"/>
  </entry>
</feed>''';

Future<HttpServer> _startOpdsServer(List<int> epub) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final response = req.response;
    switch (req.uri.path) {
      case '/opds/all':
        response.headers.contentType = ContentType(
          'application',
          'atom+xml',
          charset: 'utf-8',
        );
        response.write(_libraryFeed(server.port));
      case '/opds/novel/7':
        response.headers.contentType = ContentType(
          'application',
          'atom+xml',
          charset: 'utf-8',
        );
        response.write(_volumesFeed(server.port, epub.length));
      case '/files/vol1.epub':
        response.headers.contentType = ContentType(
          'application',
          'epub+zip',
        );
        response.add(epub);
      default:
        response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  });
  return server;
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  late Directory tempDir;
  late HttpServer server;
  late OpdsSettings settings;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // The test binding replaces every HttpClient with a stub that returns
    // 400 — the whole point here is REAL requests against the local server.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    tempDir = Directory.systemTemp.createTempSync('umbra_integration');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    server = await _startOpdsServer(_buildEpub());
    settings = OpdsSettings(
      baseUrl: 'http://127.0.0.1:${server.port}',
      username: '',
      password: '',
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await AppDatabase.reset();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold handles briefly; leaking a temp dir is harmless.
    }
  });

  test('money path: browse → volumes → download → parse → resume', () async {
    // Browse the library.
    final client = OpdsClient(settings);
    final library = await client.fetchLibrary();
    expect(library, hasLength(1));
    final series = library.single;
    expect(series.opdsId, 7);
    expect(series.title, 'Integration Novel');
    expect(series.author, 'Test Author');
    expect(series.genres, contains('Fantasy'));

    // List its volumes.
    final volumes = await client.fetchVolumes(series.opdsId);
    expect(volumes, hasLength(1));
    final volume = volumes.single;
    expect(volume.fileName, 'vol1.epub');
    expect(volume.fileSizeBytes, greaterThan(0));

    // Download the EPUB (streamed, .part-then-rename).
    final storage = LibraryStorage();
    final store = DownloadStore(storage);
    final progressTicks = <double>[];
    await DownloadService(
      settings: settings,
      storage: storage,
      store: store,
    ).download(volume, onProgress: progressTicks.add);
    final epubFile = await storage.epubFile(volume);
    expect(epubFile.existsSync(), isTrue);
    expect(progressTicks, isNotEmpty);
    expect(progressTicks.last, 1.0);

    // Parse what was downloaded.
    final book = await EpubParser().open(epubFile);
    expect(book.title, 'Integration Novel');
    expect(book.chapters, hasLength(2));

    // Read to chapter 2 and resume there.
    final progressStore = ReadingProgressStore();
    await progressStore.save(
      volume,
      const ReadingProgress(chapterIndex: 1, blockIndex: 1, chapterCount: 2),
    );
    final resumed = await progressStore.load(volume);
    expect(resumed.chapterIndex, 1);
    expect(resumed.blockIndex, 1);
    // And it surfaces on the Continue Reading shelf.
    final entries = await progressStore.allEntries();
    expect(entries.single.volume.fileName, 'vol1.epub');
  });

  testWidgets('downloaded volume renders in the real ReaderScreen', (
    tester,
  ) async {
    // Download through the real pipeline first (real async I/O).
    final storage = LibraryStorage();
    late final Volume volume;
    await tester.runAsync(() async {
      final client = OpdsClient(settings);
      final series = (await client.fetchLibrary()).single;
      volume = (await client.fetchVolumes(series.opdsId)).single;
      await DownloadService(
        settings: settings,
        storage: storage,
        store: DownloadStore(storage),
      ).download(volume, onProgress: (_) {});
    });

    await tester.pumpWidget(MaterialApp(home: ReaderScreen(volume: volume)));
    // The reader's open() does real file + prefs + database I/O — give it
    // real event-loop time, then pump until the loading spinner is gone.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }

    expect(
      find.textContaining('integration story begins', findRichText: true),
      findsOneWidget,
    );

    // Tear the reader down cleanly (dispose saves progress, stops timers).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // The open-time position save arms a debounced iCloud push; cancel it
    // so no timer outlives the test body.
    CloudSyncService().cancelPendingTimers();
  });
}
