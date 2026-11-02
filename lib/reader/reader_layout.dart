/// Reader layout engine: shared text styles, block measurement and the
/// page-packing algorithm. Extracted from reader_screen.dart so rendering
/// and pagination agree on one set of metrics.
library;

import 'package:flutter/material.dart';

import '../models/content_block.dart';
import '../models/reader_settings.dart';

// Layout constants — shared by rendering and pagination so the two agree.
const double kContentVPad = 8;
const double kTopBarHeight = 56;
const double kBottomBarHeight = 88;
const double kParagraphGap = 16;

/// Shortest side at or above which a viewport is a tablet rather than a
/// large phone. A phone in landscape is wide but short; splitting it gives
/// two columns with three lines each.
///
/// 600 rather than the iPad mini's 744, because the gap this sits in is
/// wide and the top of it is the wrong end. Measured on the Fold: the inner
/// panel is 752dp at the default 480dpi — 52dp of headroom — and One UI's
/// display-size slider moves density in steps that eat that immediately.
/// At 540dpi the panel reports 668dp and the spread silently stops opening,
/// with nothing to explain why. The largest phones are around 440dp, so
/// 600 sits in the middle of the gap instead of at its edge and survives
/// every display-size setting the device offers.
const double kSpreadMinShortestSide = 600;

/// Width/height at or above which a tablet-sized viewport opens into a
/// two-page spread.
///
/// The rule this replaced asked "is this landscape?" — an orientation flag
/// standing in for a geometry question. An unfolded foldable is tablet-sized
/// and nearly square, so it reports as portrait and never opened the spread
/// it plainly has room for. Ratio asks what the layout actually cares about:
/// is there width here to split in two.
///
/// PROVISIONAL. 0.8 clears every landscape viewport and leaves an iPad in
/// portrait (0.66) single-page, so today's iOS behaviour is unchanged. It has
/// never been checked against a real unfolded panel — measure the device in
/// both postures and move this to sit below the unfolded ratio.
const double kSpreadMinAspectRatio = 0.8;

/// Whether paged mode should render a two-page spread at [size].
///
/// Independent of orientation on purpose: a square-ish tablet qualifies and a
/// wide phone does not, which is the distinction a foldable turns on.
bool shouldUseSpread(Size size) =>
    size.shortestSide >= kSpreadMinShortestSide &&
    size.height > 0 &&
    size.width / size.height >= kSpreadMinAspectRatio;

/// The vertical gap below a paragraph — the fixed base plus the reader's
/// extra paragraph-spacing setting. Used identically by measurement, page
/// packing and rendering so the three never disagree.
double paragraphGap(ReaderSettings s) => kParagraphGap + s.paragraphSpacing;
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
  //
  // fontWeight/fontStyle are pinned for the same reason, and the weight is
  // not hypothetical. [Text.rich] merges FontWeight.bold into the root span
  // it wraps these runs in whenever MediaQuery.boldText is set — the
  // platform "Bold text" accessibility setting, which Android reports as
  // font_weight_adjustment=300 — and a run whose own fontWeight is null
  // inherits it. Pagination measures with a bare TextPainter that has no
  // such root, so a phone with that setting on rendered Literata 7.3% wider
  // than it was measured: 44 of 46 pages on one chapter overflowed, by up
  // to 42px, and the reader had to scroll each page to reach its last
  // lines.
  //
  // Pinning means the platform setting no longer reaches the reader's body
  // text. That is the same bargain [TextScaler.noScaling] already strikes
  // with the platform font *scale*: the reader carries its own bold and
  // font-size controls, and typography it does not measure is typography it
  // cannot paginate.
  final base = TextStyle(
    inherit: false,
    letterSpacing: s.letterSpacing,
    wordSpacing: s.wordSpacing,
    fontSize: s.fontSize,
    height: s.lineHeight,
    color: color,
    fontWeight: s.boldText ? FontWeight.bold : FontWeight.normal,
    fontStyle: s.italicText ? FontStyle.italic : FontStyle.normal,
  );
  // Reading fonts are bundled app assets — a plain fontFamily reference,
  // no network fetch, identical metrics for measurement and render.
  return s.fontFamily.isEmpty ? base : base.copyWith(fontFamily: s.fontFamily);
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
    letterSpacing: s.letterSpacing,
    wordSpacing: s.wordSpacing,
    fontSize: s.fontSize * scale,
    height: 1.3,
    fontWeight: FontWeight.w700,
    // Explicit for the reason [paragraphStyle] gives: a null here inherits
    // the root span's style at the engine level.
    fontStyle: s.italicText ? FontStyle.italic : FontStyle.normal,
    color: color,
  );
  return s.fontFamily.isEmpty ? base : base.copyWith(fontFamily: s.fontFamily);
}

/// Fixation anchors (Bionic-style): bolds the first 1-3 letters of each
/// word so the eye has a saccade target. The concatenated TEXT is identical
/// to the input — only run boundaries and bold flags change — so every
/// character offset (positions, highlights, word lookup) stays valid.
/// Footnote-marker runs and already-bold runs pass through untouched.
List<TextRun> fixationRuns(List<TextRun> runs) {
  bool isSpace(String c) => c == ' ' || c == '\n' || c == '\t';
  final out = <TextRun>[];
  for (final run in runs) {
    if (run.footnoteBody != null || run.bold) {
      out.add(run);
      continue;
    }
    final text = run.text;
    var plainStart = 0;
    var i = 0;
    void flushPlain(int end) {
      if (end > plainStart) {
        out.add(TextRun(text.substring(plainStart, end), italic: run.italic));
      }
    }

    while (i < text.length) {
      if (isSpace(text[i])) {
        i++;
        continue;
      }
      var j = i;
      while (j < text.length && !isSpace(text[j])) {
        j++;
      }
      final len = j - i;
      final k = len >= 8
          ? 3
          : len >= 4
          ? 2
          : 1;
      flushPlain(i);
      out.add(
        TextRun(text.substring(i, i + k), bold: true, italic: run.italic),
      );
      plainStart = i + k;
      i = j;
    }
    flushPlain(text.length);
  }
  return out;
}

/// The runs as they will actually render under [s] — fixation anchors
/// applied when enabled. EVERY measurement and render path must go through
/// this so pagination and pixels always agree.
List<TextRun> effectiveRuns(List<TextRun> runs, ReaderSettings s) =>
    s.fixationAnchors ? fixationRuns(runs) : runs;

/// How much smaller than the text around it a footnote marker is drawn.
const double kFootnoteMarkerScale = 0.85;

/// The style a footnote marker is drawn in, given the style of the run it
/// belongs to: smaller, and underlined so it reads as tappable. Colour is
/// layered on by the renderer and moves no metric, so measurement and render
/// share this one definition — and they must, because the marker's size is
/// what pagination stands a placeholder in for.
TextStyle footnoteMarkerStyle(TextStyle base) => base.copyWith(
  fontSize: (base.fontSize ?? 16) * kFootnoteMarkerScale,
  decoration: TextDecoration.underline,
);

/// The size the marker widget lays out to inside a paragraph [width] wide —
/// the size the placeholder standing in for it must be given.
///
/// [BlockView] draws the marker as a [Text] inside a [WidgetSpan], and
/// RenderParagraph lays an inline child out under
/// `BoxConstraints(maxWidth: paragraphWidth)`. Same painter, same
/// constraint, same size.
Size _footnoteMarkerSize(String text, double width, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: footnoteMarkerStyle(style)),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: width);
  return painter.size;
}

/// Lays [runs] out at [width] the way [BlockView] draws them: bold/italic
/// per run, and every footnote marker as an inline placeholder sized from
/// the marker widget rather than as ordinary full-size text.
///
/// This is the ONLY place the reader turns runs into a laid-out paragraph.
/// Block measurement, page packing and hit-testing all come through here,
/// because the moment one of them builds its own span the paths diverge. A
/// marker renders as a [WidgetSpan], which is sized by its child and takes
/// no part in text measurement, and a span that spells the marker out as
/// ordinary text gets it wrong twice over:
///
///  * it is the wrong WIDTH. The marker draws at
///    [kFootnoteMarkerScale] of the body size, so full-size text wraps a
///    word the render keeps on the line before — a whole line of drift,
///    found at 5 of 221 column widths swept on one paragraph.
///  * it was the wrong HEIGHT, by 2px at fontSize 18 and more above it,
///    because the placeholder's middle alignment grows its line from the
///    ascent and descent of whatever style is in effect at it. That one is
///    settled by naming the style below rather than by the placeholder.
///
/// Paged mode packed the difference onto every page carrying a marker, and
/// an overfull page doesn't throw — it quietly becomes a scrolling page
/// with its last line cut off.
///
/// Offsets from the returned painter are in PLACEHOLDER SPACE: each marker
/// is a single U+FFFC character there, where its own text is several. Put
/// every offset that comes out through [runOffsetFor] before indexing into
/// the runs, and every offset that goes back in through
/// [placeholderOffsetFor].
TextPainter layoutRuns(List<TextRun> runs, double width, TextStyle base) {
  final children = <InlineSpan>[];
  final placeholders = <PlaceholderDimensions>[];
  for (final run in runs) {
    final style = base.copyWith(
      fontWeight: run.bold ? FontWeight.bold : null,
      fontStyle: run.italic ? FontStyle.italic : null,
    );
    if (run.footnoteBody == null) {
      children.add(TextSpan(text: run.text, style: style));
      continue;
    }
    children.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.alphabetic,
        // Pinned for the reason [paragraphStyle] pins its own fields. A
        // placeholder carrying no style of its own is measured against the
        // enclosing paragraph's root style, and under [Text.rich] that root
        // is the ambient Material DefaultTextStyle — with whatever weight
        // the platform "Bold text" setting merges into it. Middle alignment
        // sizes the line from that style's ascent and descent, so an
        // unstyled marker would grow the line by an amount neither path
        // controls. Naming the style here makes the growth a function of
        // the reader's own typography, which is the only typography
        // pagination knows about.
        style: style,
        // Never built. A [TextPainter] measures a placeholder from the
        // dimensions below; the widget exists only on the render side.
        child: const SizedBox.shrink(),
      ),
    );
    placeholders.add(
      PlaceholderDimensions(
        size: _footnoteMarkerSize(run.text, width, style),
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.alphabetic,
      ),
    );
  }
  final painter = TextPainter(
    text: TextSpan(children: children),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  );
  if (placeholders.isNotEmpty) painter.setPlaceholderDimensions(placeholders);
  return painter..layout(maxWidth: width);
}

/// Converts a placeholder-space offset from a [layoutRuns] painter into an
/// offset in the runs' own joined text.
///
/// A marker is atomic — a line cannot break inside a placeholder — so an
/// offset landing on one resolves to the start of its text.
///
/// Fixation anchors only subdivide runs, leaving markers and the joined text
/// untouched, so callers may pass the raw runs or [effectiveRuns] of them
/// interchangeably: both spaces come out identical either way.
int runOffsetFor(List<TextRun> runs, int offset) {
  var placeholderSpace = 0;
  var runSpace = 0;
  for (final run in runs) {
    final marker = run.footnoteBody != null;
    final span = marker ? 1 : run.text.length;
    if (offset < placeholderSpace + span) {
      return marker ? runSpace : runSpace + (offset - placeholderSpace);
    }
    placeholderSpace += span;
    runSpace += run.text.length;
  }
  return runSpace;
}

/// The inverse of [runOffsetFor]: a run-space offset expressed in the
/// placeholder space a [layoutRuns] painter speaks. An offset inside a
/// marker's text resolves to the placeholder standing in for it.
int placeholderOffsetFor(List<TextRun> runs, int offset) {
  var placeholderSpace = 0;
  var runSpace = 0;
  for (final run in runs) {
    if (offset < runSpace + run.text.length) {
      return run.footnoteBody != null
          ? placeholderSpace
          : placeholderSpace + (offset - runSpace);
    }
    placeholderSpace += run.footnoteBody != null ? 1 : run.text.length;
    runSpace += run.text.length;
  }
  return placeholderSpace;
}

/// Measures the rendered height of a block at [width] — used for pagination.
double measureBlockHeight(ContentBlock block, double width, ReaderSettings s) {
  switch (block) {
    case ParagraphBlock paragraph:
      final painter = layoutRuns(
        effectiveRuns(paragraph.runs, s),
        width,
        paragraphStyle(s, const Color(0xFF000000)),
      );
      return painter.height + paragraphGap(s);
    case HeadingBlock heading:
      final painter = layoutRuns(
        effectiveRuns(heading.runs, s),
        width,
        headingStyle(s, heading.level, const Color(0xFF000000)),
      );
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
      return scaledHeight + paragraphGap(s);
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

/// Lays out a paragraph's runs at [width] for measurement. Offsets from the
/// returned painter are in placeholder space — see [layoutRuns].
TextPainter layoutParagraph(
  List<TextRun> runs,
  double width,
  ReaderSettings s,
) {
  return layoutRuns(
    effectiveRuns(runs, s),
    width,
    paragraphStyle(s, const Color(0xFF000000)),
  );
}

/// Splits a run list into the runs before [offset] and the runs from [offset]
/// onward, cutting a straddling run in two. Character-exact: the two halves
/// concatenated equal the input.
///
/// [offset] is in run space. A footnote marker is one placeholder to the
/// painter that produces these offsets, so a line boundary never lands inside
/// one and a marker run always moves whole — which is why the cut halves here
/// need not carry `footnoteBody`.
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

/// Character offset at which the line centred on [centreY] begins, in the
/// painter's own placeholder space — put it through [runOffsetFor] before
/// indexing runs with it.
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

      if (totalText + paragraphGap(settings) <= remaining) {
        current.add(
          PageBlock(
            block: ParagraphBlock(runs),
            originIndex: i,
            charOffset: charBase,
          ),
        );
        used += totalText + paragraphGap(settings);
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
      // The painter counts each footnote marker as one placeholder
      // character; [splitRuns] counts the marker's own text. Convert before
      // the two meet, or a paragraph carrying a marker splits in the wrong
      // place — and further into the paragraph, in the wrong place by more.
      final splitOffset = runOffsetFor(
        runs,
        lineStartOffsetAt(painter, centreY),
      );
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
          used += totalText + paragraphGap(settings);
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
