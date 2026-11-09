// The You tab's picture of the library.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/stats_screen.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/series_status_store.dart';

Series _series(int id) => Series(
  opdsId: id,
  title: 'Novel $id',
  author: 'A',
  description: '',
  genres: const [],
  readingStatus: 'ongoing',
  totalChapters: 10,
  downloadedChapters: 10,
  coverUrl: null,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

ReadingEntry _read(int id, String file, {bool finished = false}) =>
    ReadingEntry(
      volume: Volume(
        seriesOpdsId: id,
        title: file,
        fileName: file,
        downloadUrl: '',
        fileSizeBytes: 0,
        updatedAt: null,
      ),
      progress: ReadingProgress(
        chapterIndex: 3,
        blockIndex: 0,
        endReached: finished,
      ),
    );

void main() {
  test('counts keep every digit', () {
    expect(exactCount(7), '7');
    expect(exactCount(1035), '1,035');
    expect(exactCount(1008429), '1,008,429');
  });

  group('the reading breakdown', () {
    final library = [for (var i = 1; i <= 5; i++) _series(i)];

    test('every series lands in exactly one place', () {
      final counts = readingBreakdown(library, const [], const {});
      expect(counts, {'Reading': 0, 'Unread': 5, 'Finished': 0, 'Dropped': 0});
    });

    test('follows what has been read', () {
      final counts = readingBreakdown(library, [
        _read(1, 'a'),
        _read(2, 'b', finished: true),
      ], const {});
      expect(counts, {'Reading': 1, 'Unread': 3, 'Finished': 1, 'Dropped': 0});
    });

    test('a series part-way through another volume is still being read', () {
      final counts = readingBreakdown(library, [
        _read(1, 'v1', finished: true),
        _read(1, 'v2'),
      ], const {});
      expect(counts['Reading'], 1);
      expect(counts['Finished'], 0);
    });

    test('a status set by hand wins', () {
      final counts = readingBreakdown(
        library,
        [_read(1, 'a'), _read(2, 'b')],
        const {1: SeriesStatus.dropped, 2: SeriesStatus.caughtUp},
      );
      expect(counts, {'Reading': 0, 'Unread': 3, 'Finished': 1, 'Dropped': 1});
    });

    test('books no longer in the library are not counted', () {
      final counts = readingBreakdown(library, [_read(99, 'gone')], const {});
      expect(counts.values.reduce((a, b) => a + b), 5);
    });
  });
}
