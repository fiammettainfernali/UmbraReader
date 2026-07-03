// LibrarySearch: full-text search across the downloaded library.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:umbra_reader/models/download_record.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/library_search.dart';
import 'package:umbra_reader/services/library_storage.dart';

List<int> _epub(String title, List<String> paragraphs) {
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
    <dc:title>$title</dc:title>
    <dc:creator>A</dc:creator>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>''');
  add('OEBPS/ch1.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<h1>Chapter</h1>
${paragraphs.map((p) => '<p>$p</p>').join('\n')}
</body></html>''');
  return ZipEncoder().encode(archive);
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Volume _volume(int seriesId, String fileName) => Volume(
  seriesOpdsId: seriesId,
  title: fileName,
  fileName: fileName,
  downloadUrl: '',
  fileSizeBytes: 0,
  updatedAt: null,
);

void main() {
  late Directory tempDir;
  late LibraryStorage storage;
  late DownloadStore store;

  Future<void> install(int seriesId, String fileName, List<int> bytes) async {
    final volume = _volume(seriesId, fileName);
    final file = await storage.epubFile(volume);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    await store.put(
      volume,
      DownloadRecord(
        fileName: fileName,
        sizeBytes: bytes.length,
        downloadedAt: DateTime(2026, 7, 1),
        volumeUpdatedAt: null,
        etag: null,
      ),
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('umbra_libsearch');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    storage = LibraryStorage();
    store = DownloadStore(storage);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // harmless on Windows
    }
  });

  test('finds matches across every downloaded book', () async {
    await install(
      1,
      'alpha.epub',
      _epub('Alpha', [
        'The dragon slept on a hoard of gold.',
        'Nothing else of note happened.',
      ]),
    );
    await install(
      2,
      'beta.epub',
      _epub('Beta', [
        'A different tale entirely.',
        'But here too a dragon appears, briefly.',
      ]),
    );

    final hits = await LibrarySearch(
      storage: storage,
    ).search('dragon').toList();
    expect(hits, hasLength(2));
    expect(hits.map((h) => h.bookTitle).toSet(), {'Alpha', 'Beta'});
    final alpha = hits.singleWhere((h) => h.bookTitle == 'Alpha');
    expect(alpha.snippet, contains('dragon'));
    expect(
      alpha.snippet.substring(alpha.matchStart, alpha.matchEnd).toLowerCase(),
      'dragon',
    );
    expect(alpha.chapterIndex, 0);
    expect(alpha.blockIndex, greaterThan(0)); // heading is block 0
  });

  test('is case-insensitive and needs at least two characters', () async {
    await install(1, 'alpha.epub', _epub('Alpha', ['The DRAGON roared.']));
    expect(
      await LibrarySearch(storage: storage).search('dRaGoN').toList(),
      hasLength(1),
    );
    expect(await LibrarySearch(storage: storage).search('d').toList(), isEmpty);
  });

  test('caps hits per book', () async {
    await install(
      1,
      'alpha.epub',
      _epub('Alpha', [
        for (var i = 0; i < 30; i++) 'dragon sighting number $i',
      ]),
    );
    final hits = await LibrarySearch(
      storage: storage,
    ).search('dragon', maxPerBook: 5).toList();
    expect(hits, hasLength(5));
  });

  test('an unreadable book is skipped, not fatal', () async {
    await install(1, 'broken.epub', utf8.encode('this is not a zip'));
    await install(2, 'beta.epub', _epub('Beta', ['A dragon appears.']));
    final hits = await LibrarySearch(
      storage: storage,
    ).search('dragon').toList();
    expect(hits, hasLength(1));
    expect(hits.single.bookTitle, 'Beta');
  });
}
