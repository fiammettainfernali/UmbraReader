// Tests for EpubParser, exercised against a synthetic in-memory EPUB.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/content_block.dart';
import 'package:umbra_reader/services/epub_parser.dart';

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
    <dc:title>Test Book</dc:title>
    <dc:creator>Test Author</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"
        properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''';

const _nav = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"
    xmlns:epub="http://www.idpf.org/2007/ops">
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="ch1.xhtml">First Chapter</a></li>
        <li><a href="ch2.xhtml">Second Chapter</a></li>
      </ol>
    </nav>
  </body>
</html>''';

const _ch1 = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <h1>First Chapter</h1>
    <p>Hello <b>bold</b> and <i>italic</i> world.</p>
    <hr/>
    <p>A second paragraph here.</p>
  </body>
</html>''';

const _ch2 = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <h1>Second Chapter</h1>
    <p>The story continues.</p>
    <p><img src="images/art.png" alt="Splash"/></p>
  </body>
</html>''';

/// A valid 1x1 RGBA PNG — enough to test src resolution + IHDR dimension
/// parsing without bundling a real image asset.
const List<int> _pixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, // IHDR length
  0x49, 0x48, 0x44, 0x52, // 'IHDR'
  0x00, 0x00, 0x00, 0x01, // width 1
  0x00, 0x00, 0x00, 0x01, // height 1
  0x08, 0x06, // bit depth 8, RGBA
  0x00, 0x00, 0x00, // compression/filter/interlace
  0x1F, 0x15, 0xC4, 0x89, // CRC
  0x00, 0x00, 0x00, 0x0A, // IDAT length
  0x49, 0x44, 0x41, 0x54, // 'IDAT'
  0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x01,
  0x0D, 0x0A, 0x2D, 0xB4, // CRC
  0x00, 0x00, 0x00, 0x00, // IEND length
  0x49, 0x45, 0x4E, 0x44, // 'IEND'
  0xAE, 0x42, 0x60, 0x82, // CRC
];

List<int> _buildEpub() {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('META-INF/container.xml', _containerXml);
  add('OEBPS/content.opf', _opf);
  add('OEBPS/nav.xhtml', _nav);
  add('OEBPS/ch1.xhtml', _ch1);
  add('OEBPS/ch2.xhtml', _ch2);
  archive.addFile(
    ArchiveFile('OEBPS/images/art.png', _pixelPng.length, _pixelPng),
  );
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) throw StateError('Failed to encode the test EPUB.');
  return encoded;
}

void main() {
  late Directory tempDir;
  late File epubFile;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('umbra_epub_test');
    epubFile = File('${tempDir.path}/test.epub');
    await epubFile.writeAsBytes(_buildEpub());
  });

  tearDownAll(() => tempDir.deleteSync(recursive: true));

  test('open reads metadata and the chapter list', () async {
    final book = await EpubParser().open(epubFile);
    expect(book.title, 'Test Book');
    expect(book.author, 'Test Author');
    expect(book.chapters.length, 2);
  });

  test('chapter titles come from the navigation document', () async {
    final book = await EpubParser().open(epubFile);
    expect(book.chapters[0].title, 'First Chapter');
    expect(book.chapters[1].title, 'Second Chapter');
  });

  test('parseChapter yields headings, paragraphs and dividers', () async {
    final parser = EpubParser();
    final book = await parser.open(epubFile);
    final blocks = parser.parseChapter(book.chapters[0]);

    expect(blocks.whereType<HeadingBlock>(), isNotEmpty);
    expect(blocks.whereType<DividerBlock>(), hasLength(1));
    expect(
      blocks.whereType<ParagraphBlock>().length,
      greaterThanOrEqualTo(2),
    );

    final heading = blocks.whereType<HeadingBlock>().first;
    expect(heading.level, 1);
    expect(
      heading.runs.map((r) => r.text).join(),
      contains('First Chapter'),
    );
  });

  test('parseChapter preserves bold and italic runs', () async {
    final parser = EpubParser();
    final book = await parser.open(epubFile);
    final blocks = parser.parseChapter(book.chapters[0]);
    final runs = blocks
        .whereType<ParagraphBlock>()
        .expand((p) => p.runs)
        .toList();

    expect(runs.any((r) => r.bold && r.text.contains('bold')), isTrue);
    expect(runs.any((r) => r.italic && r.text.contains('italic')), isTrue);
  });

  test('parseChapter pulls images and their natural dimensions', () async {
    final parser = EpubParser();
    final book = await parser.open(epubFile);
    final blocks = parser.parseChapter(book.chapters[1]);

    final images = blocks.whereType<ImageBlock>().toList();
    expect(images, hasLength(1));
    expect(images.first.width, 1);
    expect(images.first.height, 1);
    expect(images.first.alt, 'Splash');
    expect(images.first.bytes, isNotEmpty);
  });

  test('a malformed file throws a friendly EpubException', () async {
    final bad = File('${tempDir.path}/bad.epub');
    await bad.writeAsString('this is not a zip archive');
    await expectLater(
      EpubParser().open(bad),
      throwsA(isA<EpubException>()),
    );
  });
}
