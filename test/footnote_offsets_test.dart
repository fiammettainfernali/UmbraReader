// Footnote markers give a paragraph two coordinate systems, and pagination
// lives on the seam between them.
//
// [layoutRuns] measures a marker as a placeholder, which is ONE character in
// the painter's text where the marker's own text ("[1]") is three. Every
// offset the painter hands out — line starts for page splits, hit-test
// positions, word boundaries — is therefore in placeholder space, while
// everything that indexes runs (splitRuns, PageBlock.charOffset, saved
// reading positions, the selection wash) is in run space.
//
// A missed conversion doesn't crash. It splits a paragraph a few characters
// off, and drifts further with every marker earlier in the paragraph.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/content_block.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/reader/reader_layout.dart';

import 'helpers/reader_fonts.dart';

/// "before[1]middle[2]after" — 6 + 3 + 6 + 3 + 5 characters of run space,
/// 6 + 1 + 6 + 1 + 5 of placeholder space.
const _runs = <TextRun>[
  TextRun('before'),
  TextRun('[1]', footnoteBody: 'first note'),
  TextRun('middle'),
  TextRun('[2]', footnoteBody: 'second note'),
  TextRun('after'),
];

String _textOf(List<TextRun> runs) => runs.map((r) => r.text).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReaderFonts);

  group('offset conversion', () {
    test('plain text before any marker maps one-to-one', () {
      for (var i = 0; i <= 6; i++) {
        expect(runOffsetFor(_runs, i), i, reason: 'placeholder $i');
        expect(placeholderOffsetFor(_runs, i), i, reason: 'run $i');
      }
    });

    test('each marker costs run space its placeholder does not', () {
      // Placeholder 7 is the first character of "middle"; in run space that
      // is 6 ("before") + 3 ("[1]") = 9.
      expect(runOffsetFor(_runs, 7), 9);
      expect(placeholderOffsetFor(_runs, 9), 7);
      // Past both markers: placeholder 14 is the first of "after", run 18.
      expect(runOffsetFor(_runs, 14), 18);
      expect(placeholderOffsetFor(_runs, 18), 14);
    });

    test('an offset landing on a marker resolves to the marker, not past it', () {
      // The placeholder standing in for "[1]" sits at offset 6.
      expect(runOffsetFor(_runs, 6), 6);
      // Anywhere inside "[1]" is the placeholder itself, never a character
      // halfway through it — a caret cannot land inside a placeholder.
      expect(placeholderOffsetFor(_runs, 6), 6);
      expect(placeholderOffsetFor(_runs, 7), 6);
      expect(placeholderOffsetFor(_runs, 8), 6);
    });

    test('the end of the text maps to the end of the text', () {
      final runLength = runsLength(_runs); // 23
      const placeholderLength = 19;
      expect(runOffsetFor(_runs, placeholderLength), runLength);
      expect(placeholderOffsetFor(_runs, runLength), placeholderLength);
      // And past the end, rather than running off it.
      expect(runOffsetFor(_runs, placeholderLength + 5), runLength);
      expect(placeholderOffsetFor(_runs, runLength + 5), placeholderLength);
    });

    test('run space is the same whether or not fixation has split the runs', () {
      final split = fixationRuns(_runs);
      expect(_textOf(split), _textOf(_runs));
      for (var i = 0; i <= 19; i++) {
        expect(runOffsetFor(split, i), runOffsetFor(_runs, i), reason: 'at $i');
      }
    });

    test('runs with no markers in them convert to themselves', () {
      const plain = [TextRun('one '), TextRun('two', bold: true)];
      for (var i = 0; i <= 7; i++) {
        expect(runOffsetFor(plain, i), i);
        expect(placeholderOffsetFor(plain, i), i);
      }
    });

    test('the painter really does count a marker as one character', () {
      // The premise the conversions rest on. If the engine ever stopped
      // flattening a placeholder to a single U+FFFC, the arithmetic above
      // would be quietly wrong everywhere.
      final s = ReaderSettings.defaults.copyWith(fontFamily: kTestReaderFont);
      final painter = layoutRuns(
        _runs,
        1000, // one line, so the last caret is at the end of the text
        paragraphStyle(s, const Color(0xFF000000)),
      );
      final end = painter.getPositionForOffset(Offset(painter.width + 50, 1));
      expect(end.offset, 19);
    });
  });

  group('splitting a paragraph that carries markers', () {
    // Narrow and short, so the paragraphs below split several times each.
    const width = 300.0;
    const height = 220.0;

    final settings = ReaderSettings.defaults.copyWith(
      fontFamily: kTestReaderFont,
      fontSize: 18,
      lineHeight: 1.6,
    );

    List<ContentBlock> chapter() => <ContentBlock>[
      for (var i = 0; i < 6; i++)
        ParagraphBlock([
          TextRun('Paragraph $i opens on the terrace and runs on a while '),
          TextRun('[${i + 1}]', footnoteBody: 'The translator explains.'),
          const TextRun(
            ' before it carries on for long enough to need several lines, '
            'across a page break or two, with a second marker waiting',
          ),
          const TextRun('[b]', footnoteBody: 'And again.'),
          const TextRun(
            ' near the end of it so the conversion is exercised twice in '
            'the one paragraph rather than only once.',
          ),
        ]),
    ];

    test('every slice concatenates back to the paragraph it came from', () {
      final blocks = chapter();
      final pages = paginateBlocks(blocks, width, height, settings);

      final slices = <int, List<PageBlock>>{};
      for (final page in pages) {
        for (final pb in page) {
          slices.putIfAbsent(pb.originIndex, () => []).add(pb);
        }
      }
      expect(slices.length, blocks.length, reason: 'a paragraph went missing');

      for (final entry in slices.entries) {
        final origin = blocks[entry.key] as ParagraphBlock;
        final buffer = StringBuffer();
        for (final pb in entry.value) {
          expect(
            pb.charOffset,
            buffer.length,
            reason:
                'block ${entry.key}: a slice claims to start at '
                '${pb.charOffset} but ${buffer.length} characters precede it',
          );
          buffer.write(_textOf((pb.block as ParagraphBlock).runs));
        }
        expect(
          buffer.toString(),
          _textOf(origin.runs),
          reason: 'block ${entry.key} did not survive being split',
        );
      }
    });

    test('a page break lands on a line boundary', () {
      // The invariant a missed conversion actually breaks. Slices still
      // concatenate back whatever offset they were cut at — splitRuns is
      // exact either way — so the damage is silent: the break lands a few
      // characters short of the line it was meant to fall on, one character
      // per marker before it, and the next page opens mid-word.
      final blocks = chapter();
      final pages = paginateBlocks(blocks, width, height, settings);

      for (final page in pages) {
        for (final pb in page) {
          if (pb.charOffset == 0) continue;
          final origin = blocks[pb.originIndex] as ParagraphBlock;
          // Where the whole paragraph's lines begin, in run space.
          final painter = layoutParagraph(origin.runs, width, settings);
          final starts = <int>{};
          var y = 0.0;
          for (final line in painter.computeLineMetrics()) {
            starts.add(
              runOffsetFor(
                origin.runs,
                lineStartOffsetAt(painter, y + line.height / 2),
              ),
            );
            y += line.height;
          }
          expect(
            starts,
            contains(pb.charOffset),
            reason:
                'block ${pb.originIndex} was cut at ${pb.charOffset}, which '
                'is not the start of any of its lines — nearest are '
                '${(starts.toList()..sort()).where((o) => (o - pb.charOffset).abs() < 12)}',
          );
        }
      }
    });

    test('a split never cuts a marker in half', () {
      final blocks = chapter();
      final pages = paginateBlocks(blocks, width, height, settings);
      expect(
        pages.length,
        greaterThan(blocks.length),
        reason: 'nothing split, so this proves nothing',
      );

      final markers = <String>[];
      for (final page in pages) {
        for (final pb in page) {
          for (final run in (pb.block as ParagraphBlock).runs) {
            if (run.footnoteBody != null) markers.add(run.text);
          }
        }
      }
      // Two per paragraph, each whole and still carrying its note.
      expect(markers.length, blocks.length * 2);
      for (final marker in markers) {
        expect(marker.length, 3, reason: '"$marker" was cut by a split');
      }
    });
  });
}
