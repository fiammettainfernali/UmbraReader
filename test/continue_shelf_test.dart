// What belongs on Continue reading, and the reading theme that matches the app.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/reader_theme.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/library_home.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/series_status_store.dart';

ReadingEntry _entry(
  int series,
  String file, {
  int chapter = 3,
  bool finished = false,
}) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: series,
    title: file,
    fileName: file,
    downloadUrl: '',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: ReadingProgress(
    chapterIndex: chapter,
    blockIndex: 0,
    chapterCount: 10,
    endReached: finished,
  ),
);

List<int> _shelf(
  List<ReadingEntry> entries, {
  Set<String> hidden = const {},
  Map<int, SeriesStatus> statuses = const {},
}) => [
  for (final entry in continueShelf(
    entries,
    hidden: hidden,
    statuses: statuses,
  ))
    entry.volume.seriesOpdsId,
];

void main() {
  group('Continue reading', () {
    test('holds what has been started and not finished', () {
      expect(
        _shelf([
          _entry(1, 'a'),
          _entry(2, 'b', chapter: 0),
          _entry(3, 'c', finished: true),
        ]),
        [1],
      );
    });

    test('a series appears once, on its newest volume', () {
      final shelf = continueShelf(
        [_entry(1, 'vol2'), _entry(1, 'vol1'), _entry(2, 'x')],
        hidden: const {},
        statuses: const {},
      );
      expect(shelf.map((e) => e.volume.fileName), ['vol2', 'x']);
    });

    test('dropped and caught up series are off it', () {
      expect(
        _shelf(
          [_entry(1, 'a'), _entry(2, 'b'), _entry(3, 'c')],
          statuses: const {
            1: SeriesStatus.dropped,
            2: SeriesStatus.caughtUp,
            3: SeriesStatus.reading,
          },
        ),
        [3],
      );
    });

    test('removing the newest volume does not let an older one step in', () {
      expect(
        _shelf(
          [_entry(1, 'vol2'), _entry(1, 'vol1'), _entry(2, 'x')],
          hidden: const {'1/vol2'},
        ),
        [2],
      );
    });

    test('reading another volume after removal brings the series back', () {
      expect(
        _shelf(
          [_entry(1, 'vol3'), _entry(1, 'vol2')],
          hidden: const {'1/vol2'},
        ),
        [1],
      );
    });

    test('a finished newest volume leaves an unfinished older one on', () {
      expect(_shelf([_entry(1, 'vol2', finished: true), _entry(1, 'vol1')]), [
        1,
      ]);
    });

    group('left on the last chapter', () {
      final now = DateTime(2026, 11, 4, 12);
      ReadingEntry onChapter(int chapter, {int count = 10, DateTime? at}) =>
          ReadingEntry(
            volume: _entry(1, 'a').volume,
            progress: ReadingProgress(
              chapterIndex: chapter,
              blockIndex: 0,
              chapterCount: count,
              updatedAt: at,
            ),
          );
      int shelved(ReadingEntry entry) => continueShelf(
        [entry],
        hidden: const {},
        statuses: const {},
        now: now,
      ).length;

      test('stays while it was read in the last few days', () {
        final at = now.subtract(const Duration(days: 2));
        expect(shelved(onChapter(9, at: at)), 1);
      });

      test('counts as caught up after that', () {
        final at = now.subtract(const Duration(days: 4));
        expect(shelved(onChapter(9, at: at)), 0);
      });

      test('comes back when new chapters raise the count', () {
        final at = now.subtract(const Duration(days: 40));
        expect(shelved(onChapter(9, count: 12, at: at)), 1);
      });

      test('a book left mid-way stays however old', () {
        final at = now.subtract(const Duration(days: 400));
        expect(shelved(onChapter(4, at: at)), 1);
      });

      test('a book with no recorded length is left alone', () {
        expect(shelved(onChapter(9, count: 0)), 1);
      });
    });

    test('stops at twelve', () {
      expect(_shelf([for (var i = 0; i < 20; i++) _entry(i, 'v')]).length, 12);
    });
  });

  group('the Hawthorne reading theme', () {
    final theme = readerThemeById('hawthorne');

    test('is on offer, and is dark', () {
      expect(theme.id, 'hawthorne');
      expect(theme.isLight, isFalse);
    });

    test('headings use its red, and other themes stay as they were', () {
      expect(theme.headingColor, theme.accent);
      final dark = readerThemeById('dark');
      expect(dark.headingColor, dark.text);
      expect(dark.edgeGlow, isNull);
    });

    test('keeps its colours through an overlay tint', () {
      final washed = theme.withOverlay(kOverlayTints[1], 0.5);
      expect(washed.accent, isNotNull);
      expect(washed.edgeGlow, isNotNull);
    });
  });
}
