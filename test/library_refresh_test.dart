// The app has to be able to learn something new after launch.
//
// This is the bug this file exists for. Fetching lived inside the library
// screen and ran once per launch (plus pull-to-refresh on that one screen).
// Every other screen read the cache it wrote, so Discover's pull-to-refresh
// re-read a file nobody had rewritten — the gesture a reader reaches for
// when a shelf looks stale was the one gesture guaranteed not to help. An
// app left open all day showed the library as it was at launch, while Novel
// Grabber compiled all day.
//
// A real local HTTP server plays Novel Grabber so the whole path runs:
// settings → client → feed → cache.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:umbra_reader/services/library_cache.dart';
import 'package:umbra_reader/services/library_refresh.dart';
import 'package:umbra_reader/services/library_storage.dart';
import 'package:umbra_reader/services/settings_service.dart';

/// A feed whose entry carries whatever title the server is told to serve,
/// so a test can move the server on and look for the change.
String _feed(String title) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:dc="http://purl.org/dc/elements/1.1/"
      xmlns:ng="http://novel-grabber.local/">
  <title>All Books</title>
  <entry>
    <title>$title</title>
    <id>urn:novel-grabber:novel:7</id>
    <author><name>Someone</name></author>
    <updated>2026-08-12T20:33:00Z</updated>
    <summary>A novel that exists only to be tested.</summary>
    <ng:readingStatus>ongoing</ng:readingStatus>
    <ng:chapters total="2" downloaded="0"/>
    <ng:addedAt>2026-08-12T20:00:00Z</ng:addedAt>
  </entry>
</feed>''';

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
  var served = 'Stale Title';

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // The test binding otherwise replaces every HttpClient with a stub that
    // returns 400, and this is a test about a real request being made.
    HttpOverrides.global = null;
    tempDir = Directory.systemTemp.createTempSync('umbra_refresh');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    served = 'Stale Title';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final response = req.response;
      if (req.uri.path == '/opds/all') {
        response.headers.contentType = ContentType(
          'application',
          'atom+xml',
          charset: 'utf-8',
        );
        response.write(_feed(served));
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
    settings = OpdsSettings(
      baseUrl: 'http://127.0.0.1:${server.port}',
      username: '',
      password: '',
    );
  });

  tearDown(() async {
    await server.close(force: true);
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold handles briefly; a leaked temp dir is harmless.
    }
  });

  Future<List<String>> cachedTitles() async {
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    return [for (final s in cache.series) s.title];
  }

  test('it fetches from the server and returns what it found', () async {
    final result = await const LibraryRefresh().run(settings);
    expect(result, isNotNull);
    expect([for (final s in result!) s.title], ['Stale Title']);
  });

  test('a second run picks up what changed', () async {
    // The whole point: the app must be able to learn something after
    // launch. Before this existed, only one screen could, once.
    await const LibraryRefresh().run(settings);
    served = 'Fresh Title';
    final result = await const LibraryRefresh().run(settings);
    expect([for (final s in result!) s.title], ['Fresh Title']);
  });

  test('what it fetches lands where every screen looks', () async {
    await const LibraryRefresh().run(settings);
    expect(await cachedTitles(), ['Stale Title']);

    served = 'Fresh Title';
    await const LibraryRefresh().run(settings);
    expect(
      await cachedTitles(),
      ['Fresh Title'],
      reason: 'screens read the cache, so a refresh must rewrite it',
    );
  });

  test('the write announces itself so watching screens redraw', () async {
    final before = libraryCacheRevision.value;
    await const LibraryRefresh().run(settings);
    expect(libraryCacheRevision.value, greaterThan(before));
  });

  test('it does not flush an empty volume map over the real one', () async {
    // The refresher builds its own cache instance, which starts with no
    // volumes. Saving without loading first would wipe every volume list
    // the app had cached — books would stop listing their parts offline.
    final seed = LibraryCache(LibraryStorage());
    await seed.load();
    await seed.saveVolumes(7, const []);

    await const LibraryRefresh().run(settings);

    final after = LibraryCache(LibraryStorage());
    await after.load();
    expect(after.volumesFor(7), isNotNull);
  });

  test('an unreachable server is null, not an exception', () async {
    await server.close(force: true);
    await expectLater(const LibraryRefresh().run(settings), completion(isNull));
  });

  test('an unreachable server leaves the cached library intact', () async {
    await const LibraryRefresh().run(settings);
    await server.close(force: true);
    await const LibraryRefresh().run(settings);
    expect(
      await cachedTitles(),
      ['Stale Title'],
      reason: 'offline must not empty the shelves',
    );
  });

  test('an unconfigured server is not contacted at all', () async {
    const blank = OpdsSettings(baseUrl: '', username: '', password: '');
    await expectLater(const LibraryRefresh().run(blank), completion(isNull));
  });
}
