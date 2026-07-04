// The pagination measurer (measureBlockHeight) must predict the exact
// height BlockView renders — any drift and paged mode packs more content
// than fits, spilling text past the bottom of the page.
//
// This pumps the real BlockView at a fixed width and compares the rendered
// height against the measurement for every block type, including the
// footnote-marker case (rendered as an inline WidgetSpan).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/content_block.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/models/reader_theme.dart';
import 'package:umbra_reader/reader/block_view.dart';
import 'package:umbra_reader/reader/reader_layout.dart';

Future<double> _renderedHeight(
  WidgetTester tester,
  ContentBlock block,
  double width,
  ReaderSettings settings,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Unbounded height so a block taller than the test screen still
        // reports its intrinsic rendered height.
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: BlockView(
                block: block,
                settings: settings,
                preset: kReaderThemes.first,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byType(BlockView)).height;
}

void main() {
  const width = 465.0;
  final settings = ReaderSettings.defaults.copyWith(
    fontSize: 18,
    lineHeight: 1.6,
  );

  final long = List.generate(
    80,
    (w) => w % 9 == 0 ? 'extraordinary' : 'word$w',
  ).join(' ');

  final cases = <String, ContentBlock>{
    'plain paragraph': ParagraphBlock([TextRun(long)]),
    'mixed bold/italic': ParagraphBlock([
      TextRun('Normal start, '),
      TextRun('then bold middle parts, ', bold: true),
      TextRun('then italics to finish the line and wrap around. ',
          italic: true),
      TextRun(long),
    ]),
    'heading': HeadingBlock(2, [TextRun('A Chapter Heading That Wraps: $long')]),
    'divider': const DividerBlock(),
    'paragraph with footnote markers': ParagraphBlock([
      TextRun('Some text before the marker'),
      const TextRun('[1]', footnoteBody: 'The translator explains.'),
      TextRun(' and after it, $long'),
      const TextRun('[2]', footnoteBody: 'Another note.'),
      TextRun(' and yet more text that wraps a few lines. $long'),
    ]),
  };

  for (final entry in cases.entries) {
    testWidgets('measure matches render: ${entry.key}', (tester) async {
      final block = entry.value;
      final rendered = await _renderedHeight(tester, block, width, settings);
      // measureBlockHeight includes the trailing gap; BlockView with
      // isLast=false renders the same gap, so compare like for like.
      final measured = measureBlockHeight(block, width, settings);
      expect(
        (rendered - measured).abs(),
        lessThanOrEqualTo(1.0),
        reason:
            '${entry.key}: rendered $rendered vs measured $measured '
            '(drift ${(rendered - measured).toStringAsFixed(1)}px)',
      );
    });
  }
}
