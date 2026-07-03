// Parser robustness against real-world EPUBs.
//
// Runs EpubParser over every file in test/corpus/ (populated by
// tool/fetch_epub_corpus.sh — a mix of Standard Ebooks EPUB3 and Project
// Gutenberg epub3/epub2 builds, including poetry, tables, images and
// non-Latin scripts). The corpus is .gitignored; when it's absent this
// whole file is a no-op so CI and fresh clones stay green.
//
// The bar is graceful degradation, not pixel fidelity:
//  - open() must succeed and find at least one chapter,
//  - parseChapter() must never throw on any chapter,
//  - the book as a whole must yield a sane amount of text (a book that
//    parses to near-nothing means the parser silently dropped the content).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/content_block.dart';
import 'package:umbra_reader/services/epub_parser.dart';

String _blockText(ContentBlock block) => switch (block) {
  ParagraphBlock p => p.runs.map((r) => r.text).join(),
  HeadingBlock h => h.runs.map((r) => r.text).join(),
  DividerBlock _ => '',
  ImageBlock _ => '',
};

void main() {
  final corpusDir = Directory('test/corpus');
  final files =
      corpusDir.existsSync()
          ? (corpusDir
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.epub'))
                .toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
          : const <File>[];

  if (files.isEmpty) {
    test('corpus absent — run tool/fetch_epub_corpus.sh to enable', () {});
    return;
  }

  // Vector-only books (SVG drawings in the spine, no bitmaps, no prose).
  // The reader can't rasterise vector art; the graceful-degradation bar for
  // these is "opens, every page parses without throwing, placeholder shown"
  // — which the shared assertions below already cover, so they're exempt
  // from the content-volume checks only.
  const vectorOnly = {'idpf_svg-in-spine.epub'};

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    test('parses $name', () async {
      final parser = EpubParser();
      final book = await parser.open(file);
      expect(book.chapters, isNotEmpty, reason: '$name: no chapters');

      var totalChars = 0;
      var totalImages = 0;
      var emptyChapters = 0;
      for (final chapter in book.chapters) {
        // The reader calls parseChapter lazily per chapter — it must never
        // throw, whatever the markup does.
        final blocks = parser.parseChapter(chapter);
        final chars = blocks.fold<int>(
          0,
          (sum, b) => sum + _blockText(b).length,
        );
        totalChars += chars;
        final images = blocks.whereType<ImageBlock>().length;
        totalImages += images;
        if (chars == 0 && images == 0) emptyChapters++;
      }

      if (!vectorOnly.contains(name)) {
        // A real book must not parse to (near) nothing: either a body of
        // text, or (picture books) a body of images.
        expect(
          totalChars > 5000 || totalImages >= 2,
          isTrue,
          reason:
              '$name: only $totalChars chars and $totalImages images '
              'across the whole book',
        );
        // Some structural chapters (covers, title pages) are legitimately
        // content-free, but most chapters must carry content.
        expect(
          emptyChapters,
          lessThan((book.chapters.length / 2).ceil()),
          reason:
              '$name: $emptyChapters of ${book.chapters.length} chapters '
              'parsed to empty',
        );
      }
    });
  }
}
