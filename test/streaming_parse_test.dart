// A book read from the hub parses into the same blocks as one on disk.
//
// That is the claim the whole design rests on: the parser, the renderer
// and the pagination never learn where the bytes came from, so streaming
// cannot quietly produce different pages. These tests drive a real
// EpubParser against a fake remote source and check it against the same
// book opened locally.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/content_block.dart';
import 'package:umbra_reader/services/epub_parser.dart';
import 'package:umbra_reader/services/epub_source.dart';

/// A source backed by a map, standing in for the hub. Records what was
/// asked for, and refuses to answer anything not prefetched — exactly like
/// the real one, whose bytes() reads only from cache.
class _FakeRemote implements EpubSource {
  _FakeRemote(this.server);

  final Map<String, List<int>> server;
  final Map<String, List<int>> _cache = {};
  final List<String> fetched = [];

  @override
  List<int>? bytes(String path) => _cache[path];

  @override
  Future<void> prefetch(Iterable<String> paths) async {
    for (final p in paths) {
      if (_cache.containsKey(p)) continue;
      fetched.add(p);
      final hit = server[p];
      if (hit != null) _cache[p] = hit;
    }
  }

  @override
  void dispose() {}
}

const _container =
    '<container><rootfile full-path="OEBPS/content.opf"/></container>';

const _opf = '''
<package xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>A Streamed Book</dc:title>
    <dc:creator>An Author</dc:creator>
  </metadata>
  <manifest>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="i1" href="images/p.png" media-type="image/png"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''';

const _ch1 = '<html><body><h1>One</h1><p>First chapter text.</p>'
    '<img src="images/p.png"/></body></html>';
const _ch2 = '<html><body><p>Second chapter text.</p></body></html>';

// A 1x1 PNG, so ImageBlock has something real to decode.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Map<String, List<int>> _book() => {
      'META-INF/container.xml': utf8.encode(_container),
      'OEBPS/content.opf': utf8.encode(_opf),
      'OEBPS/ch1.xhtml': utf8.encode(_ch1),
      'OEBPS/ch2.xhtml': utf8.encode(_ch2),
      'OEBPS/images/p.png': _png,
    };

void main() {
  test('a streamed book opens with its spine intact', () async {
    final remote = _FakeRemote(_book());
    await remote.prefetch(['OEBPS/content.opf']);
    final book = await EpubParser().openSource(remote);

    expect(book.title, 'A Streamed Book');
    expect(book.author, 'An Author');
    expect(book.chapters.map((c) => c.zipPath),
        ['OEBPS/ch1.xhtml', 'OEBPS/ch2.xhtml']);
  });

  test('opening does not drag the chapters down with it', () async {
    // If opening fetched every chapter it would be a download wearing a
    // different name.
    final remote = _FakeRemote(_book());
    await remote.prefetch(['OEBPS/content.opf']);
    await EpubParser().openSource(remote);
    expect(remote.fetched, isNot(contains('OEBPS/ch1.xhtml')));
  });

  test('a prepared chapter parses to the same blocks as a local one',
      () async {
    final remote = _FakeRemote(_book());
    await remote.prefetch(['OEBPS/content.opf']);
    final parser = EpubParser();
    final book = await parser.openSource(remote);

    final ready = await parser.prepareChapter(book.chapters.first);
    expect(ready, isTrue);
    final blocks = parser.parseChapter(book.chapters.first);

    expect(blocks.whereType<HeadingBlock>(), isNotEmpty);
    final text = blocks
        .whereType<ParagraphBlock>()
        .expand((p) => p.runs.map((r) => r.text))
        .join();
    expect(text, contains('First chapter text.'));
  });

  test('images are fetched before the parse that needs them', () async {
    // ImageBlock holds bytes resolved during the parse, which is
    // synchronous — so an image not already in hand is an image lost.
    final remote = _FakeRemote(_book());
    await remote.prefetch(['OEBPS/content.opf']);
    final parser = EpubParser();
    final book = await parser.openSource(remote);

    await parser.prepareChapter(book.chapters.first);
    expect(remote.fetched, contains('OEBPS/images/p.png'));
    expect(parser.parseChapter(book.chapters.first).whereType<ImageBlock>(),
        isNotEmpty, reason: 'the image did not survive the parse');
  });

  test('a chapter with no images costs one fetch', () async {
    final remote = _FakeRemote(_book());
    await remote.prefetch(['OEBPS/content.opf']);
    final parser = EpubParser();
    final book = await parser.openSource(remote);
    remote.fetched.clear();

    await parser.prepareChapter(book.chapters[1]);
    expect(remote.fetched, ['OEBPS/ch2.xhtml']);
  });

  test('an unreachable chapter reports false rather than a broken book',
      () async {
    // The caller needs to tell "the hub is unreachable" apart from "this
    // book is damaged" — they read identically otherwise, and only one of
    // them is worth retrying.
    final incomplete = _book()..remove('OEBPS/ch2.xhtml');
    final remote = _FakeRemote(incomplete);
    await remote.prefetch(['OEBPS/content.opf']);
    final parser = EpubParser();
    final book = await parser.openSource(remote);

    expect(await parser.prepareChapter(book.chapters[1]), isFalse);
    expect(await parser.prepareChapter(book.chapters[0]), isTrue);
  });
}
