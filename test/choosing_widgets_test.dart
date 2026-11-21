// The choosing help as it appears: three cards with reasons, Not now under
// each, Decide for me, and "Keep reading?" three chapters into a book.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/library_view.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/library_home.dart';
import 'package:umbra_reader/services/choosing.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/widgets/choosing_widgets.dart';

Series _series(int id) => Series(
  opdsId: id,
  title: 'Book $id',
  author: 'Author',
  description: 'About it.',
  genres: const ['Fantasy'],
  readingStatus: '',
  totalChapters: 10,
  downloadedChapters: 10,
  coverUrl: null,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

ReadingEntry _entry(int id) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: id,
    title: 'Book $id',
    fileName: 'v1.epub',
    downloadUrl: 'http://pc/v1.epub',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: ReadingProgress(
    chapterIndex: 4,
    blockIndex: 0,
    chapterCount: 10,
    updatedAt: DateTime.now().subtract(const Duration(days: 40)),
  ),
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  final picks = [
    TonightPick(series: _series(1), kind: TonightKind.carryOn, reason: 'Chapter 5 of 10', entry: _entry(1)),
    TonightPick(series: _series(2), kind: TonightKind.likeLast, reason: 'Like Book 9, which you finished'),
    TonightPick(series: _series(3), kind: TonightKind.wildcard, reason: 'Something different · A finished story · about 9 h'),
  ];

  testWidgets('three cards, each with its reason, and the buttons answer', (tester) async {
    final opened = <int>[];
    final skipped = <int>[];
    var decided = 0;
    await tester.pumpWidget(_host(TonightsThree(
      picks: picks,
      headers: const {},
      onOpen: (p) => opened.add(p.series.opdsId),
      onNotNow: (p) => skipped.add(p.series.opdsId),
      onDecide: () => decided++,
    )));
    await tester.pumpAndSettle();

    expect(find.text("Tonight's three"), findsOneWidget);
    expect(find.text('CARRY ON'), findsOneWidget);
    expect(find.text('LIKE YOUR LAST'), findsOneWidget);
    expect(find.text('WILDCARD'), findsOneWidget);
    expect(find.text('Something different · A finished story · about 9 h'), findsOneWidget);

    await tester.tap(find.text('Not now').at(1));
    await tester.ensureVisible(find.text('Decide for me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decide for me'));
    await tester.ensureVisible(find.byType(AspectRatio).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AspectRatio).first);
    expect(skipped, [2]);
    expect(decided, 1);
    expect(opened, [1]);
  });

  testWidgets('fits the Fold folded, with the largest text', (tester) async {
    tester.view.physicalSize = const Size(300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(300, 900), textScaler: TextScaler.linear(1.6)),
      child: _host(TonightsThree(
        picks: picks,
        headers: const {},
        onOpen: (_) {},
        onNotNow: (_) {},
        onDecide: () {},
        onMood: () {},
        onThisOrThat: () {},
      )),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final rows = {
      for (final label in ['This or that', 'Mood', 'Decide for me'])
        tester.getTopLeft(find.text(label)).dy.round() ~/ 40,
    };
    expect(rows, hasLength(1), reason: 'the three tools share one line');
  });

  testWidgets('seven reading states scroll on the outer screen instead of squeezing', (tester) async {
    tester.view.physicalSize = const Size(340, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SlidingPillBar<ReadingStateFilter>(
          values: ReadingStateFilter.values,
          labels: [for (final s in ReadingStateFilter.values) s.label],
          selected: ReadingStateFilter.any,
          onSelected: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final paused = tester.getSize(find.ancestor(of: find.text('Paused'), matching: find.byType(Expanded)));
    expect(paused.width, greaterThanOrEqualTo(SlidingPillBar.minSegmentWidth - 1));
  });

  testWidgets('Decide for me is off when the only pick is the book on the go', (tester) async {
    await tester.pumpWidget(_host(TonightsThree(
      picks: [picks.first],
      headers: const {},
      onOpen: (_) {},
      onNotNow: (_) {},
      onDecide: () => fail('nothing new to decide on'),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decide for me'));
    expect(find.text('CARRY ON'), findsOneWidget);
  });

  for (final (label, answer) in [
    ('Keep it', TryItAnswer.keep),
    ('Not for me', TryItAnswer.notForMe),
    ('Ask me in a few chapters', TryItAnswer.later),
  ]) {
    testWidgets('three chapters in, "$label" answers ${answer.name}', (tester) async {
      TryItAnswer? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await showTryItPrompt(context, 'The Road'),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Keep reading The Road?'), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(got, answer);
    });
  }

  testWidgets('over the limit, the books chosen are the ones paused', (tester) async {
    Set<int>? paused;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => paused = await showPauseSheet(
            context,
            books: [for (final id in [1, 2, 3, 4]) (series: _series(id), entry: _entry(id))],
            limit: 3,
            justStarted: 4,
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("That's 4 books at once"), findsOneWidget);
    expect(find.text('Book 4'), findsNothing, reason: 'the one just started is not offered');
    await tester.tap(find.text('Book 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause 1'));
    await tester.pumpAndSettle();
    expect(paused, {2});
  });
}
