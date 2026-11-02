// A page that pagination says fits must fit when it is actually drawn.
//
// block_measure_test pins the per-block invariant. This pins the whole
// assembled page, and pins it against the real BlockView rather than
// against the measurer -- pagination_overflow_test re-measures pages with
// layoutParagraph, so it compares the measurer with itself and cannot see
// the two paths diverge.
//
// Three things make that divergence possible, and all three are here:
//
//   * a page is rendered inside a SingleChildScrollView, so an overflowing
//     page quietly becomes a scrollable one instead of throwing. Nothing
//     here wraps the page in one.
//   * Text.rich merges the system "Bold text" accessibility setting into
//     the root span it wraps the reader's runs in, and a run whose own
//     fontWeight is null inherits that at the engine level. The TextPainter
//     pagination measures with has no such root, so the screen rendered
//     Literata 7.3% wider than it was measured and pages spilled.
//   * a footnote marker renders as an inline WidgetSpan, which is sized by
//     its child and takes no part in text measurement. Measured as ordinary
//     text it is the wrong width, and left unstyled its middle alignment
//     grew the line it sat on by ~2px. Both are the measurer's job now, and
//     these pages hold markers so that stays true.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/content_block.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/models/reader_theme.dart';
import 'package:umbra_reader/reader/block_view.dart';
import 'package:umbra_reader/reader/reader_layout.dart';

import 'helpers/reader_fonts.dart';

const _pageKey = ValueKey('page');

/// The rendered height of one packed page, laid out the way
/// _buildPagedColumn lays it out, minus the scroll view that would hide an
/// overflow.
Future<double> _pageHeight(
  WidgetTester tester,
  List<PageBlock> page,
  double width,
  ReaderSettings settings, {
  bool boldText = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(boldText: boldText),
          child: Scaffold(
            body: SingleChildScrollView(
              // Unbounded height, so a page taller than the screen reports
              // the height it really wants rather than the height it got.
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: Column(
                    key: _pageKey,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var j = 0; j < page.length; j++)
                        BlockView(
                          block: page[j].block,
                          settings: settings,
                          preset: kReaderThemes.first,
                          isLast: j == page.length - 1,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byKey(_pageKey)).height;
}

/// How far one paragraph's rendered height runs ahead of its measurement.
Future<double> _drift(
  WidgetTester tester,
  ParagraphBlock block,
  double width,
  ReaderSettings settings,
) async {
  final rendered = await _pageHeight(
    tester,
    [PageBlock(block: block, originIndex: 0)],
    width,
    settings,
  );
  // isLast drops the trailing gap that measureBlockHeight includes.
  final measured =
      measureBlockHeight(block, width, settings) - paragraphGap(settings);
  return rendered - measured;
}

/// Prose-shaped filler: deterministic, mixed word lengths, so lines break
/// in the awkward places real text breaks in.
const _vocab = <String>[
  'the',
  'cultivator',
  'a',
  'sword',
  'of',
  'inheritance',
  'and',
  'qi',
  'to',
  'formation',
  'in',
  'disciple',
  'that',
  'immortal',
  'was',
  'sect',
  'his',
  'tribulation',
  'her',
  'realm',
  'it',
  'spiritual',
  'as',
  'elder',
  'but',
  'foundation',
  'for',
  'pill',
  'with',
  'transformation',
  'he',
  'core',
];

String _prose(int seed, int words) {
  final out = StringBuffer();
  var x = seed * 7919 + 13;
  for (var i = 0; i < words; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    if (i > 0) out.write(' ');
    out.write(_vocab[x % _vocab.length]);
    if (i % 17 == 16) out.write('.');
  }
  out.write('.');
  return out.toString();
}

List<ContentBlock> _chapter() => <ContentBlock>[
  HeadingBlock(2, [TextRun('Chapter 412: A Title Long Enough To Wrap Once')]),
  for (var i = 0; i < 40; i++) ...[
    // Every seventh paragraph carries a translator note. Markers render as
    // inline WidgetSpans — the one part of a paragraph the measurer has to
    // reproduce by standing something else in for it.
    if (i % 7 == 6)
      ParagraphBlock([
        TextRun(_prose(i, 40)),
        const TextRun('[1]', footnoteBody: 'The translator explains.'),
        TextRun(' ${_prose(i + 100, 60)}'),
      ])
    else
      ParagraphBlock([TextRun(_prose(i, 20 + (i * 37) % 260))]),
    if (i % 11 == 10) const DividerBlock(),
  ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReaderFonts);

  final blocks = _chapter();
  const widths = <double>[363, 411];
  const heights = <double>[560, 720, 823];
  final base = ReaderSettings.defaults.copyWith(fontFamily: kTestReaderFont);

  test('the test font can tell bold from regular', () {
    // Without this every render-vs-measure test below is decoration: the
    // fallback font lays bold and regular out to the same width, so the
    // comparison holds however far the two paths drift.
    double width(FontWeight weight) => (TextPainter(
      text: TextSpan(
        text: 'the cultivator raised his sword and the formation answered',
        style: TextStyle(
          inherit: false,
          fontSize: 18,
          fontFamily: kTestReaderFont,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout()).width;

    expect(
      width(FontWeight.bold),
      greaterThan(width(FontWeight.normal) + 1),
      reason:
          'the reading font is not being loaded; these tests prove '
          'nothing about weight',
    );
  });

  final settingsCases = <String, ReaderSettings>{
    'defaults': base,
    'justified': base.copyWith(textAlign: ReaderTextAlign.justify),
    'large text': base.copyWith(fontSize: 22, lineHeight: 1.8),
    'reader bold': base.copyWith(boldText: true),
    'paragraph spacing': base.copyWith(paragraphSpacing: 12),
    'fixation anchors': base.copyWith(fixationAnchors: true),
  };

  for (final entry in settingsCases.entries) {
    for (final width in widths) {
      // A footnote marker used to cost a couple of pixels a page: it renders
      // as a WidgetSpan, which takes no part in text measurement and whose
      // middle alignment grows its line. The measurer now stands a
      // placeholder of the marker's own size in for it, so a paragraph
      // carrying one must drift no more than a paragraph without — which is
      // to say, not at all. Pinned separately from the page tests below
      // because it names the cause; a page overflowing by 2px does not.
      testWidgets('a footnote marker costs the measurer nothing: '
          '${entry.key} at ${width.round()}', (tester) async {
        final settings = entry.value;
        final plain = await _drift(
          tester,
          ParagraphBlock([TextRun(_prose(1, 60))]),
          width,
          settings,
        );
        final marked = await _drift(
          tester,
          ParagraphBlock([
            TextRun(_prose(1, 30)),
            const TextRun('[1]', footnoteBody: 'note'),
            TextRun(' ${_prose(2, 30)}'),
          ]),
          width,
          settings,
        );
        expect(
          plain.abs(),
          lessThanOrEqualTo(0.5),
          reason: 'a paragraph with no marker in it drifts ${plain}px',
        );
        expect(
          marked.abs(),
          lessThanOrEqualTo(0.5),
          reason: 'a paragraph with one marker in it drifts ${marked}px',
        );
      });

      for (final height in heights) {
        // Every case runs twice: once as the reader is normally used, and
        // once with the platform's "Bold text" accessibility setting on.
        for (final systemBold in [false, true]) {
          final label = systemBold ? ' + system bold' : '';
          testWidgets('pages fit: ${entry.key}$label at '
              '${width.round()}x${height.round()}', (tester) async {
            final settings = entry.value;
            final pages = paginateBlocks(blocks, width, height, settings);
            final overflows = <String>[];
            for (var p = 0; p < pages.length; p++) {
              final rendered = await _pageHeight(
                tester,
                pages[p],
                width,
                settings,
                boldText: systemBold,
              );
              // A strict fit: a page carrying footnote markers gets no
              // allowance for them, because the measurer stands a
              // correctly-sized placeholder in for each one.
              final budget = height + 0.5;
              if (rendered > budget) {
                overflows.add(
                  'page $p by ${(rendered - budget).toStringAsFixed(1)}px',
                );
              }
            }
            expect(
              overflows,
              isEmpty,
              reason:
                  '${overflows.length} of ${pages.length} pages render '
                  'taller than the $height budget: '
                  '${overflows.take(6).join(', ')}',
            );
          });
        }
      }
    }
  }
}
