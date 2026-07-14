// Exact-numbers mode: the reader's position label swaps "~5 min" style
// approximations for precise counts — page N of M, one-decimal percent and
// minutes, no tildes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/reader_theme.dart';
import 'package:umbra_reader/reader/reader_chrome.dart';

Widget _bar({required bool exact, int? pageOfSpread, int? spreadCount}) =>
    MaterialApp(
      home: Scaffold(
        body: ReaderChapterBar(
          height: 88,
          preset: readerThemeById('dark'),
          index: 3,
          total: 120,
          progress: 5 / 12,
          minutesLeft: 12.54,
          bookMinutesLeft: 182.44,
          exactNumbers: exact,
          pageOfSpread: pageOfSpread,
          spreadCount: spreadCount,
          onPrevious: () {},
          onNext: () {},
          onSeek: (_) {},
          onJump: (_) {},
          isReading: false,
          isPlaying: false,
          canSeek: false,
          onPlayPause: () {},
          onBack15: () {},
          onForward15: () {},
        ),
      ),
    );

String _label(WidgetTester tester) {
  final texts = tester.widgetList<Text>(find.byType(Text));
  return texts
      .map((t) => t.data ?? '')
      .firstWhere((s) => s.contains('Chapter 4 of 120'));
}

void main() {
  testWidgets('default label approximates with a tilde', (tester) async {
    await tester.pumpWidget(_bar(exact: false));
    final label = _label(tester);
    expect(label, contains('~13 min in chapter'));
    expect(label, contains('~3h 2m in book'));
  });

  testWidgets('exact mode shows page, percent and minutes to one decimal', (
    tester,
  ) async {
    await tester.pumpWidget(_bar(exact: true, pageOfSpread: 5, spreadCount: 12));
    final label = _label(tester);
    expect(label, contains('page 5 of 12'));
    expect(label, contains('41.7%'));
    expect(label, contains('12.5 min'));
    expect(label, contains('182.4 min in book'));
    expect(label, isNot(contains('~')), reason: 'exact means no tildes');
  });

  testWidgets('exact mode without page data still shows percent + minutes', (
    tester,
  ) async {
    await tester.pumpWidget(_bar(exact: true));
    final label = _label(tester);
    expect(label, isNot(contains('page')));
    expect(label, contains('41.7%'));
    expect(label, contains('12.5 min'));
  });
}
