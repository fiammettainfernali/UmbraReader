// Two backs that mean different things.
//
// The system back gesture walks the page history, because that is what the
// gesture means everywhere else on the phone. The arrow in the reader's own
// bar leaves for the library, because that is what an arrow in a reader's
// own bar means. Wiring the arrow to maybePop collapses the two: it
// consults the PopScope, which spends the history first, so after four
// chapters the arrow visibly did something and never arrived anywhere, and
// the way out was to press it once per page you had read.
//
// Checked against the source because the distinction IS the fix and nothing
// else expresses it — driving a WebView in a widget test would need a
// platform mock, and would still pass if the arrow were quietly changed
// back.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/web_series_screen.dart').readAsStringSync();

  test('the bar arrow leaves rather than consulting the page history', () {
    final arrow = source.indexOf("tooltip: 'Back to library'");
    expect(arrow, greaterThan(-1), reason: 'the back button moved');
    // The next onPressed after it is the arrow's own.
    final wiring = source.substring(arrow, arrow + 200);
    expect(
      wiring.contains('onPressed: _leave'),
      isTrue,
      reason: 'the back arrow must leave, not walk the page history',
    );
    expect(
      wiring.contains('maybePop'),
      isFalse,
      reason:
          'maybePop consults the PopScope, which spends the history '
          'first — that is the bug this guards',
    );
  });

  test('the system gesture still walks the page history', () {
    // The other half. If this ever goes, back inside a comic stops being
    // able to undo a navigation at all.
    expect(source.contains('canGoBack()'), isTrue);
    expect(source.contains('onPopInvokedWithResult'), isTrue);
  });

  test('leaving saves the place first', () {
    // Backing out is the most common way a reading session ends, so it is
    // the one moment the position most has to be written.
    final leave = source.indexOf('Future<void> _leave()');
    expect(leave, greaterThan(-1), reason: '_leave moved');
    final body = source.substring(leave, leave + 260);
    expect(body.indexOf('_save()'), greaterThan(-1));
    expect(
      body.indexOf('_save()'),
      lessThan(body.indexOf('navigator.pop()')),
      reason: 'the position must be saved before the screen goes',
    );
  });
}
