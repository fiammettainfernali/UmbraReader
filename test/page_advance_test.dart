// Where a chapter ends, when the reader is showing two columns.
//
// The pager counts *spreads*; the paginator counts *pages*. On a two-page
// spread there are half as many of the former, and the reader compared a
// spread index against a page count to decide whether it had run out of
// chapter. It never had: the last spread of every chapter looked like the
// middle of one, so tapping the forward zone called nextPage, which had
// nowhere to go and did nothing at all. The edge of the screen went dead
// and the only way on was to swipe past the edge.

import 'package:flutter_test/flutter_test.dart';

/// The last index the pager can be on, given a page count and a stride.
///
/// Mirrors the reader's own arithmetic. It is one line, and one line is
/// exactly the size of thing that is wrong for a year.
int lastPagerIndex(int pageCount, int stride) =>
    (pageCount / stride).ceil().clamp(1, 1 << 30) - 1;

void main() {
  group('single column', () {
    test('the last page is the last index', () {
      expect(lastPagerIndex(7, 1), 6);
    });

    test('a one-page chapter has nowhere to go', () {
      expect(lastPagerIndex(1, 1), 0);
    });
  });

  group('two-column spread', () {
    test('two pages are one spread', () {
      expect(lastPagerIndex(2, 2), 0);
    });

    test('an odd page count still gets its final half-spread', () {
      // Seven pages is four spreads, the last holding one page and a blank.
      // Rounding down here would strand the final page of every chapter.
      expect(lastPagerIndex(7, 2), 3);
    });

    test('the end of a chapter is reachable', () {
      // The bug, stated directly: with 10 pages across 5 spreads, a reader
      // on the last spread is at index 4. The old test asked whether 4 was
      // less than 9 — it is, so the reader was told to turn another page
      // rather than cross into the next chapter.
      const pages = 10;
      const stride = 2;
      final onLastSpread = lastPagerIndex(pages, stride);
      expect(onLastSpread, 4);
      expect(onLastSpread < pages - 1, isTrue,
          reason: 'the old comparison, which is why this was broken');
      expect(onLastSpread < lastPagerIndex(pages, stride), isFalse,
          reason: 'the fixed comparison: there is no further spread');
    });
  });

  group('degenerate input', () {
    test('an empty chapter has one index, not minus one', () {
      // Clamped rather than allowed to go negative: a -1 here would be fed
      // to jumpToPage.
      expect(lastPagerIndex(0, 1), 0);
      expect(lastPagerIndex(0, 2), 0);
    });
  });
}
