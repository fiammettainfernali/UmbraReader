// Pages must never render taller than the viewport they were packed for —
// overflow shows up as "the last lines spill past the bottom and you have
// to scroll". This re-measures every page exactly the way the renderer
// draws it and reports any overrun.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/content_block.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/reader/reader_layout.dart';

List<ContentBlock> _chapter() {
  final blocks = <ContentBlock>[
    const HeadingBlock(1, [TextRun('Chapter 12: A Long One')]),
  ];
  // Varied paragraph lengths like real webnovel prose.
  for (var i = 0; i < 60; i++) {
    final words = 12 + (i * 7) % 90;
    blocks.add(
      ParagraphBlock([
        TextRun(
          List.generate(
            words,
            (w) => w % 9 == 0 ? 'extraordinary' : 'word$w',
          ).join(' '),
        ),
      ]),
    );
    if (i % 17 == 16) blocks.add(const DividerBlock());
  }
  return blocks;
}

/// Height of one page as the renderer will actually draw it: every block
/// re-measured, trailing gap dropped on the last block (BlockView isLast).
double _renderedHeight(List<PageBlock> page, double width, ReaderSettings s) {
  var total = 0.0;
  for (var i = 0; i < page.length; i++) {
    final block = page[i].block;
    final isLast = i == page.length - 1;
    double h;
    switch (block) {
      case ParagraphBlock p:
        h = layoutParagraph(p.runs, width, s).height +
            (isLast ? 0 : kParagraphGap);
      case HeadingBlock _:
      case DividerBlock _:
      case ImageBlock _:
        h = measureBlockHeight(block, width, s);
        if (isLast && block is HeadingBlock) h -= kHeadingBottomGap;
        if (isLast && block is ParagraphBlock) h -= kParagraphGap;
    }
    total += h;
  }
  return total;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (width, height, fontSize, lineHeight, bold) in [
    (480.0, 700.0, 17.0, 1.5, false),
    (250.0, 620.0, 18.0, 1.6, false),
    (390.0, 750.0, 16.0, 1.4, false),
    (465.0, 700.0, 19.0, 1.65, true), // ~iPad TV-mode column, bold
    (465.0, 700.0, 21.0, 1.35, true),
    (512.0, 660.0, 17.5, 1.55, false),
  ]) {
    test(
        'no page overflows at ${width}x$height f$fontSize lh$lineHeight '
        'bold=$bold', () {
      final settings = ReaderSettings.defaults.copyWith(
        fontSize: fontSize,
        lineHeight: lineHeight,
        boldText: bold,
        textAlign: ReaderTextAlign.justify,
      );
      final pages = paginateBlocks(_chapter(), width, height, settings);
      var worst = 0.0;
      var worstPage = -1;
      for (var i = 0; i < pages.length; i++) {
        final rendered = _renderedHeight(pages[i], width, settings);
        final overrun = rendered - height;
        if (overrun > worst) {
          worst = overrun;
          worstPage = i;
        }
      }
      // ignore: avoid_print
      print('pages=${pages.length} worst overrun='
          '${worst.toStringAsFixed(1)}px on page $worstPage');
      expect(
        worst,
        lessThanOrEqualTo(0.5),
        reason: 'page $worstPage renders ${worst.toStringAsFixed(1)}px '
            'taller than the viewport',
      );
    });
  }
}
