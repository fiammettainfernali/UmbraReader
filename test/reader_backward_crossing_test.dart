// Going back one page must mean the same thing in every reading mode.
//
// Crossing a chapter boundary backwards should land on the previous
// chapter's *end* — the content immediately before this — and three of the
// five paths did. The two scroll-mode ones called _goToChapter without
// landOnLastPage and dropped the reader at the chapter's beginning, so one
// step back skipped the whole chapter being stepped into.
//
// Checked against the source rather than through the widget: the defect was
// a missing named argument at one call site, and no amount of exercising the
// other four would have found it. The same shape as source_encoding_test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A `_goToChapter(_chapterIndex - 1` call and the line it sits on.
typedef _BackwardCall = ({int line, String text});

List<_BackwardCall> _backwardCalls() {
  final source = File('lib/screens/reader_screen.dart').readAsLinesSync();
  final out = <_BackwardCall>[];
  for (var i = 0; i < source.length; i++) {
    if (source[i].contains('_goToChapter(_chapterIndex - 1')) {
      // The argument may wrap, so carry the next line too.
      final text = source[i] +
          (i + 1 < source.length ? ' ${source[i + 1].trim()}' : '');
      out.add((line: i + 1, text: text));
    }
  }
  return out;
}

void main() {
  test('the reader still has backward chapter moves to check', () {
    // Guards the guard: a rename would otherwise make this test vacuous
    // while continuing to pass.
    expect(_backwardCalls().length, greaterThanOrEqualTo(5));
  });

  test('every backward page crossing lands at the previous chapter end', () {
    final wrong = <String>[];
    for (final call in _backwardCalls()) {
      // The chapter list's Previous button is a deliberate exception: it
      // means "take me to that chapter", not "go back one page", so it
      // lands at the start.
      if (call.text.contains('onPrevious')) continue;
      if (!call.text.contains('landOnLastPage: true')) {
        wrong.add('reader_screen.dart:${call.line}');
      }
    }
    expect(
      wrong,
      isEmpty,
      reason: 'these go back across a chapter boundary but land at the '
          'start of the previous chapter instead of its end, so one page '
          'back skips a whole chapter: ${wrong.join(', ')}',
    );
  });

  test('the chapter list Previous button is still the only exception', () {
    // If this stops being true the rule above needs revisiting rather than
    // silently widening.
    final exceptions =
        _backwardCalls().where((c) => c.text.contains('onPrevious')).length;
    expect(exceptions, 1);
  });
}
