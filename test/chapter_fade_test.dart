// Covering the frame in which a chapter changes.
//
// Crossing a chapter replaces the blocks and repaginates, but the pager is
// still on the old chapter's last index until a post-frame callback jumps
// it. The frame in between renders the new chapter at the wrong page. That
// is the stutter at a chapter boundary — not a failed page turn, since a
// jump has no intermediate positions for a turn to be drawn from.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/reader/chapter_fade.dart';

Widget _wrap(int chapter, {Duration duration = const Duration(milliseconds: 160)}) {
  return MaterialApp(
    home: Scaffold(
      body: ChapterFade(
        chapterIndex: chapter,
        duration: duration,
        child: Text('chapter $chapter'),
      ),
    ),
  );
}

double _opacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

void main() {
  testWidgets('opening a book is not an arrival to cover', (tester) async {
    // There is no previous chapter underneath to be caught between, and
    // fading the first page in would just make the reader feel slow.
    await tester.pumpWidget(_wrap(3));
    expect(_opacity(tester), 1);
  });

  testWidgets('the frame a chapter changes on is hidden', (tester) async {
    await tester.pumpWidget(_wrap(3));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_wrap(4));
    // This is the frame that used to show the new chapter at the old
    // chapter's page index.
    expect(_opacity(tester), 0);
  });

  testWidgets('and it comes back on the next one', (tester) async {
    await tester.pumpWidget(_wrap(3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(4));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets('repagination within a chapter is not covered', (tester) async {
    // The menu appearing repaginates and re-anchors, but the reader stays on
    // the words they were reading. Blanking for that would make opening a
    // menu flicker the whole page.
    await tester.pumpWidget(_wrap(3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(3));
    expect(_opacity(tester), 1);
  });

  testWidgets('reduce-motion still hides the frame, without the fade', (
    tester,
  ) async {
    // The wrong-page frame is a glitch, not an animation: someone who asked
    // for less motion did not ask to see it.
    await tester.pumpWidget(_wrap(3, duration: Duration.zero));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(4, duration: Duration.zero));
    expect(_opacity(tester), 0);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets('the chapter that fades in is the new one', (tester) async {
    await tester.pumpWidget(_wrap(3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(4));
    await tester.pumpAndSettle();
    expect(find.text('chapter 4'), findsOneWidget);
    expect(find.text('chapter 3'), findsNothing);
  });

  testWidgets('going backwards is covered too', (tester) async {
    await tester.pumpWidget(_wrap(4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(3));
    expect(_opacity(tester), 0);
  });
}
