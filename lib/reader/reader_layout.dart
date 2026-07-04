/// Reader layout engine: shared text styles, block measurement and the
/// page-packing algorithm. Extracted from reader_screen.dart so rendering
/// and pagination agree on one set of metrics.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/content_block.dart';
import '../models/reader_settings.dart';

// Layout constants — shared by rendering and pagination so the two agree.
const double kContentVPad = 8;
const double kTopBarHeight = 56;
const double kBottomBarHeight = 88;
const double kParagraphGap = 16;
const double kHeadingTopGap = 12;
const double kHeadingBottomGap = 16;
const double kDividerHeight = 60;

/// Sentinel for "jump to the last page" when paging backward into a chapter.
const int kLastPage = -1;

/// Body text style for the active settings.
TextStyle paragraphStyle(ReaderSettings s, Color color) {
  // inherit: false — the reader's text must NOT merge with the ambient
  // Material DefaultTextStyle (letterSpacing etc.). Pagination measures the
  // raw style with a TextPainter; if rendering inherited extra properties,
  // lines wrapped differently and pages packed more than fits (headings
  // rendered a whole line taller than measured).
  // letterSpacing/wordSpacing are set EXPLICITLY to 0: inherit:false only
  // stops the framework's DefaultTextStyle merge — at the engine level a
  // null letterSpacing still inherits the enclosing paragraph's root style,
  // and under a Scaffold that root is Material bodyMedium with
  // letterSpacing 0.3. Rendered lines then run ~0.3px/char wider than the
  // TextPainter measurement, re-wrapping onto extra lines and making paged
  // mode spill past the bottom of the page.
  final base = TextStyle(
    inherit: false,
    letterSpacing: 0,
    wordSpacing: 0,
    fontSize: s.fontSize,
    height: s.lineHeight,
    color: color,
    fontWeight: s.boldText ? FontWeight.bold : null,
    fontStyle: s.italicText ? FontStyle.italic : null,
  );
  return s.fontFamily.isEmpty
      ? base
      : GoogleFonts.getFont(s.fontFamily, textStyle: base);
}

/// Heading style — sized relative to the body text.
TextStyle headingStyle(ReaderSettings s, int level, Color color) {
  final scale = level <= 2
      ? 1.35
      : level <= 4
      ? 1.18
      : 1.06;
  final base = TextStyle(
    inherit: false,
    letterSpacing: 0,
    wordSpacing: 0,
    fontSize: s.fontSize * scale,
    height: 1.3,
    fontWeight: FontWeight.w700,
    fontStyle: s.italicText ? FontStyle.italic : null,
    color: color,
  );
  return s.fontFamily.isEmpty
      ? base
      : GoogleFonts.getFont(s.fontFamily, textStyle: base);
}

/// Builds a styled [TextSpan] for a run list, applying bold/italic per run.
TextSpan runSpan(List<TextRun> runs, TextStyle base) {
  return TextSpan(
    children: [
      for (final run in runs)
        TextSpan(
          text: run.text,
          style: base.copyWith(
            fontWeight: run.bold ? FontWeight.bold : null,
            fontStyle: run.italic ? FontStyle.italic : null,
          ),
        ),
    ],
  );
}

/// Measures the rendered height of a block at [width] — used for pagination.
double measureBlockHeight(ContentBlock block, double width, ReaderSettings s) {
  switch (block) {
    case ParagraphBlock paragraph:
      final painter = TextPainter(
        text: runSpan(
          paragraph.runs,
          paragraphStyle(s, const Color(0xFF000000)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: width);
      return painter.height + kParagraphGap;
    case HeadingBlock heading:
      final painter = TextPainter(
        text: runSpan(
          heading.runs,
          headingStyle(s, heading.level, const Color(0xFF000000)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: width);
      return painter.height + kHeadingTopGap + kHeadingBottomGap;
    case DividerBlock _:
      return kDividerHeight;
    case ImageBlock image:
      // Scale the image to the column width and preserve its aspect ratio,
      // capping height at 80% of a reasonable page so a tall illustration
      // doesn't push everything else off the page in scroll mode.
      final natural = image.width <= 0 ? 1 : image.width;
      final aspect = image.height / natural;
      final scaledHeight = (width * aspect).clamp(80.0, 900.0);
      return scaledHeight + kParagraphGap;
  }
}

/// One renderable slice on a page.
///
/// For a whole block, [block] is the original block and [charOffset] is 0.
/// For a paragraph split across pages, [block] is a [ParagraphBlock] holding
/// only that slice's runs, [originIndex] points back to the parent block in
/// the chapter's block list, and [charOffset] is where the slice's text
/// begins within the parent paragraph.
class PageBlock {
  const PageBlock({
    required this.block,
    required this.originIndex,
    this.charOffset = 0,
  });

  final ContentBlock block;
  final int originIndex;
  final int charOffset;
}

/// Total character length of a run list.
int runsLength(List<TextRun> runs) {
  var total = 0;
  for (final run in runs) {
    total += run.text.length;
  }
  return total;
}

/// Lays out a paragraph's runs at [width] for measurement.
TextPainter layoutParagraph(
  List<TextRun> runs,
  double width,
  ReaderSettings s,
) {
  return TextPainter(
    text: runSpan(runs, paragraphStyle(s, const Color(0xFF000000))),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: width);
}

/// Splits a run list into the runs before [offset] and the runs from [offset]
/// onward, cutting a straddling run in two. Character-exact: the two halves
/// concatenated equal the input.
(List<TextRun>, List<TextRun>) splitRuns(List<TextRun> runs, int offset) {
  final head = <TextRun>[];
  final tail = <TextRun>[];
  var pos = 0;
  for (final run in runs) {
    final start = pos;
    final end = pos + run.text.length;
    pos = end;
    if (end <= offset) {
      head.add(run);
    } else if (start >= offset) {
      tail.add(run);
    } else {
      final cut = offset - start;
      head.add(
        TextRun(run.text.substring(0, cut), bold: run.bold, italic: run.italic),
      );
      tail.add(
        TextRun(run.text.substring(cut), bold: run.bold, italic: run.italic),
      );
    }
  }
  return (head, tail);
}

/// Character offset at which the line centred on [centreY] begins.
int lineStartOffsetAt(TextPainter painter, double centreY) {
  final pos = painter.getPositionForOffset(Offset(1, centreY));
  return painter.getLineBoundary(pos).start;
}

/// Packs blocks into pages, splitting a paragraph across a page boundary when
/// it doesn't fully fit — so every page bar a chapter's last fills close to
/// the bottom. Headings and dividers are never split.
List<List<PageBlock>> paginateBlocks(
  List<ContentBlock> blocks,
  double width,
  double height,
  ReaderSettings settings,
) {
  final budget = height;
  final pages = <List<PageBlock>>[];
  var current = <PageBlock>[];
  var used = 0.0;

  void flush() {
    if (current.isNotEmpty) {
      pages.add(current);
      current = <PageBlock>[];
      used = 0;
    }
  }

  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];

    if (block is! ParagraphBlock) {
      final h = measureBlockHeight(block, width, settings);
      if (current.isNotEmpty && used + h > budget) flush();
      current.add(PageBlock(block: block, originIndex: i));
      used += h;
      continue;
    }

    // A paragraph: placed whole, or split across one or more page breaks.
    var runs = block.runs;
    var charBase = 0;
    while (true) {
      final painter = layoutParagraph(runs, width, settings);
      final lines = painter.computeLineMetrics();
      if (lines.isEmpty) break;
      final totalText = painter.height;
      final remaining = budget - used;

      if (totalText + kParagraphGap <= remaining) {
        current.add(
          PageBlock(
            block: ParagraphBlock(runs),
            originIndex: i,
            charOffset: charBase,
          ),
        );
        used += totalText + kParagraphGap;
        break;
      }

      // How many whole lines fit in the space left on this page?
      var fitHeight = 0.0;
      var fitLines = 0;
      for (final line in lines) {
        if (fitHeight + line.height > remaining) break;
        fitHeight += line.height;
        fitLines++;
      }

      if (fitLines == 0) {
        if (used == 0) {
          // A single line taller than the whole page — place it regardless.
          fitLines = 1;
          fitHeight = lines.first.height;
        } else {
          flush();
          continue;
        }
      }

      if (fitLines >= lines.length) {
        // All the lines fit; only the trailing gap didn't — place gapless.
        current.add(
          PageBlock(
            block: ParagraphBlock(runs),
            originIndex: i,
            charOffset: charBase,
          ),
        );
        used += totalText;
        break;
      }

      // Split after the last line that fits.
      final centreY = fitHeight + lines[fitLines].height / 2;
      final splitOffset = lineStartOffsetAt(painter, centreY);
      if (splitOffset <= 0 || splitOffset >= runsLength(runs)) {
        // No usable split point — move the whole fragment to a fresh page.
        if (used == 0) {
          current.add(
            PageBlock(
              block: ParagraphBlock(runs),
              originIndex: i,
              charOffset: charBase,
            ),
          );
          used += totalText + kParagraphGap;
          break;
        }
        flush();
        continue;
      }
      final parts = splitRuns(runs, splitOffset);
      current.add(
        PageBlock(
          block: ParagraphBlock(parts.$1),
          originIndex: i,
          charOffset: charBase,
        ),
      );
      used += fitHeight;
      flush();
      runs = parts.$2;
      charBase += splitOffset;
    }
  }

  flush();
  if (pages.isEmpty) pages.add(<PageBlock>[]);
  return pages;
}
