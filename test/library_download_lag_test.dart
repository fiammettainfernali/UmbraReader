// The library's whole-library check used to rewrite the 2 MB cache after
// every series and reopen every downloaded book on the thread that draws the
// screen. These hold the replacements: staged cache writes, one at a time,
// and a chapter count taken in the background.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/download_service.dart';
import 'package:umbra_reader/services/library_cache.dart';
import 'package:umbra_reader/services/library_storage.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Volume _volume(int series, int n) => Volume(
  seriesOpdsId: series,
  title: 'Book $series — Volume $n',
  fileName: 'Book $series Volume 0$n.epub',
  downloadUrl: 'http://pc/opds/download/$series/$n',
  fileSizeBytes: 100,
  updatedAt: DateTime(2026, 11, 1),
);

List<int> _epub(int chapters) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''))
    ..addFile(ArchiveFile.string('EPUB/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>T</dc:title></metadata>
  <manifest>${[for (var i = 1; i <= chapters; i++) '<item id="c$i" href="chapter_000$i.xhtml" media-type="application/xhtml+xml"/>'].join()}</manifest>
  <spine>${[for (var i = 1; i <= chapters; i++) '<itemref idref="c$i"/>'].join()}</spine>
</package>'''));
  for (var i = 1; i <= chapters; i++) {
    archive.addFile(ArchiveFile.string('EPUB/chapter_000$i.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Chapter $i</h1><p>Text.</p></body></html>'));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('umbra_lag');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold handles briefly; leaking a temp dir is harmless.
    }
  });

  Future<File> cacheFile() async => File(await LibraryStorage().cachePath());

  test('staged volume lists are kept at once and written once, at flush', () async {
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    for (var s = 1; s <= 50; s++) {
      cache.stageVolumes(s, [_volume(s, 1), _volume(s, 2)]);
    }
    expect(cache.volumesFor(37)!.length, 2, reason: 'readable straight away');
    expect((await cacheFile()).existsSync(), isFalse, reason: 'not one write per series');
    await cache.flush();
    final again = LibraryCache(LibraryStorage());
    await again.load();
    expect(again.volumesFor(50)!.map((v) => v.fileName), ['Book 50 Volume 01.epub', 'Book 50 Volume 02.epub']);
  });

  test('staged lists are written by themselves after a moment', () async {
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    cache.stageVolumes(1, [_volume(1, 1)]);
    await Future<void>.delayed(LibraryCache.stageWindow + const Duration(seconds: 1));
    final again = LibraryCache(LibraryStorage());
    await again.load();
    expect(again.volumesFor(1), isNotNull);
  });

  test('saves at the same moment never leave the file half one and half another', () async {
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    await Future.wait([for (var s = 1; s <= 12; s++) cache.saveVolumes(s, [_volume(s, 1)])]);
    final text = await (await cacheFile()).readAsString();
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    expect((decoded['volumes'] as Map).length, 12);
  });

  test('a downloaded book\'s chapters are counted, in the background', () async {
    final file = File('${tempDir.path}/book.epub')..writeAsBytesSync(_epub(4));
    expect(await chapterCountOf(file), 4);
  });

  test('a book that is not an EPUB counts as nothing rather than failing', () async {
    final file = File('${tempDir.path}/junk.epub')..writeAsStringSync('not a zip');
    expect(await chapterCountOf(file), 0);
  });
}
