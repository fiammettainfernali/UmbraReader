// Tests for the streaming home: what goes in the spotlight and rows, and that
// the pieces do what the desktop's do without getting in the way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/screens/library_home.dart';

Series _series(
  int id, {
  String title = 'A novel',
  String? cover = 'http://x/cover.jpg',
  String description =
      'A long enough description that this could stand in a spotlight, by '
      'running to more than eighty characters.',
  List<String> genres = const ['Fantasy'],
  int chapters = 100,
  DateTime? added,
}) => Series(
  opdsId: id,
  title: title,
  author: 'Author',
  description: description,
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: chapters,
  downloadedChapters: chapters,
  coverUrl: cover,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
  addedAt: added,
);

void main() {
  group('the spotlight', () {
    final today = DateTime(2026, 11, 3);

    test('leads with what is being read, then fills up to five', () {
      final library = [for (var i = 1; i <= 9; i++) _series(i)];
      final picks = pickSpotlight(library, [7, 3, 5], today);
      expect(picks.length, 5);
      expect(picks.take(2).map((s) => s.opdsId), [7, 3]);
      expect(picks.map((s) => s.opdsId).toSet().length, 5);
    });

    test('leaves out adult titles, no cover and a thin description', () {
      final picks = pickSpotlight(
        [
          _series(1, genres: const ['Fantasy', 'Mature']),
          _series(2, cover: null),
          _series(3, description: 'Too short.'),
          _series(4),
        ],
        const [],
        today,
      );
      expect(picks.map((s) => s.opdsId), [4]);
    });

    test('stays the same all day and changes the next', () {
      final library = [for (var i = 1; i <= 40; i++) _series(i)];
      List<int> ids(DateTime day) => [
        for (final s in pickSpotlight(library, const [], day)) s.opdsId,
      ];
      expect(ids(today), ids(today));
      expect(ids(today), isNot(ids(today.add(const Duration(days: 1)))));
    });

    test('a book being read that would not qualify is skipped', () {
      final picks = pickSpotlight(
        [_series(1, cover: null), _series(2)],
        const [1],
        today,
      );
      expect(picks.map((s) => s.opdsId), [2]);
    });
  });

  group('the rows', () {
    test('newest and longest come first, then the biggest genres', () {
      final library = [
        for (var i = 1; i <= 6; i++)
          _series(
            i,
            chapters: i * 10,
            added: DateTime(2026, 1, i),
            genres: i.isEven ? const ['Action'] : const ['Fantasy', 'Action'],
          ),
      ];
      final rows = buildHomeRows(library);
      expect(rows.map((r) => r.title), [
        'Recently added',
        'Longest series',
        'Action',
      ]);
      expect(rows[0].series.first.opdsId, 6);
      expect(rows[1].series.first.totalChapters, 60);
      expect(rows[2].tag, '6 novels');
    });

    test('a row with under four covers is dropped', () {
      final rows = buildHomeRows([for (var i = 1; i <= 3; i++) _series(i)]);
      expect(rows, isEmpty);
    });

    test('adult titles and missing covers stay out of the rows', () {
      final rows = buildHomeRows([
        for (var i = 1; i <= 4; i++) _series(i),
        _series(5, genres: const ['Harem']),
        _series(6, cover: null),
      ]);
      for (final row in rows) {
        expect(row.series.map((s) => s.opdsId), isNot(contains(5)));
        expect(row.series.map((s) => s.opdsId), isNot(contains(6)));
      }
    });

    test('a genre row counts the whole library, as See all will show', () {
      final rows = buildHomeRows([
        for (var i = 1; i <= 4; i++) _series(i, genres: const ['Mystery']),
        _series(5, cover: null, genres: const ['Mystery']),
      ]);
      expect(rows.firstWhere((r) => r.title == 'Mystery').tag, '5 novels');
    });
  });

  testWidgets('the sliding bar reports the choice tapped', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlidingPillBar<String>(
            values: const ['a', 'b', 'c'],
            labels: const ['First', 'Second', 'Third'],
            selected: 'a',
            onSelected: (v) => picked = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Third'));
    expect(picked, 'c');
  });

  testWidgets('a short row sits still and shows each cover once', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriftingRow(
            itemCount: 2,
            itemExtent: 100,
            height: 100,
            itemBuilder: (context, i, clock) => Text('Cover $i'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Cover 0'), findsOneWidget);
    expect(find.text('Cover 1'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Cover 0')).dx, 16);
  });

  testWidgets('a long row drifts by itself and stops for a finger', (
    tester,
  ) async {
    const key = Key('row');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriftingRow(
            key: key,
            itemCount: 8,
            itemExtent: 100,
            height: 100,
            itemBuilder: (context, i, clock) => Text('Cover $i'),
          ),
        ),
      ),
    );
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final start = scrollable.position.pixels;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final moved = scrollable.position.pixels;
    expect(moved, greaterThanOrEqualTo(start));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(key)),
    );
    await tester.pump();
    final held = scrollable.position.pixels;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scrollable.position.pixels, held);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
