// Fixation anchors (Bionic-style): the transform must bold the first letters
// of each word WITHOUT changing the concatenated text — every reading-position
// character offset, highlight range and word lookup depends on that invariant.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/content_block.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/reader/reader_layout.dart';

String _concat(List<TextRun> runs) => runs.map((r) => r.text).join();
List<String> _boldSegments(List<TextRun> runs) =>
    [for (final r in runs) if (r.bold) r.text];

void main() {
  test('fixationRuns preserves the exact text', () {
    const input = [
      TextRun('The quick brown fox jumps over the lazy dog.'),
    ];
    final out = fixationRuns(input);
    expect(_concat(out), _concat(input),
        reason: 'character offsets must stay valid — text cannot change');
  });

  test('bold prefix length scales with word length', () {
    // len>=8 -> 3, len>=4 -> 2, else 1.
    const input = [TextRun('a the word flabbergasted')];
    final out = fixationRuns(input);
    expect(_concat(out), 'a the word flabbergasted');
    expect(
      _boldSegments(out),
      ['a', 't', 'wo', 'fla'],
      reason: 'a=1, the=1, word=2, flabbergasted=3',
    );
  });

  test('leading and internal spaces are kept as plain runs', () {
    const input = [TextRun('  hi   there')];
    final out = fixationRuns(input);
    expect(_concat(out), '  hi   there');
    expect(_boldSegments(out), ['h', 'th']);
  });

  test('already-bold and footnote runs pass through untouched', () {
    const input = [
      TextRun('shouted', bold: true),
      TextRun(' normally '),
      TextRun('1', footnoteBody: 'a note'),
    ];
    final out = fixationRuns(input);
    expect(_concat(out), 'shouted normally 1');
    // The bold word is emitted whole (not re-split); the footnote survives.
    expect(out.any((r) => r.text == 'shouted' && r.bold), isTrue);
    expect(out.any((r) => r.footnoteBody == 'a note'), isTrue);
    // 'normally' (8 letters) still gets a 3-letter anchor.
    expect(_boldSegments(out).contains('nor'), isTrue);
  });

  test('italic is carried onto both halves of a split word', () {
    const input = [TextRun('whispered', italic: true)];
    final out = fixationRuns(input);
    expect(_concat(out), 'whispered');
    expect(out.every((r) => r.italic), isTrue,
        reason: 'the emphasis of the source run must survive the split');
    expect(_boldSegments(out), ['whi']);
  });

  test('effectiveRuns is identity when the setting is off', () {
    const input = [TextRun('hello world')];
    const off = ReaderSettings.defaults; // fixationAnchors defaults to false
    expect(identical(effectiveRuns(input, off), input), isTrue);
    final on = ReaderSettings.defaults.copyWith(fixationAnchors: true);
    expect(_boldSegments(effectiveRuns(input, on)), ['he', 'wo']);
  });
}
