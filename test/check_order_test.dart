// New-volume checks run as sequential network calls and can be cut short —
// by connectivity, by backgrounding, or (for the bulk scan) by the reader
// hitting Stop. The upkeep pass is also throttled to once per 30 minutes, so
// a poor ordering isn't retried for a while. These pin that the series read
// most recently get checked first.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/library_downloads.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

Volume _vol(int series, {String file = 'v1.epub'}) => Volume(
  seriesOpdsId: series,
  title: 'Series $series',
  fileName: file,
  downloadUrl: 'http://unused/x.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
);

ReadingEntry _entry(int series, {DateTime? readAt, String file = 'v1.epub'}) =>
    ReadingEntry(
      volume: _vol(series, file: file),
      progress: ReadingProgress(
        chapterIndex: 3, // started
        blockIndex: 0,
        chapterCount: 10,
        updatedAt: readAt,
      ),
    );

Series _series(int id) => Series(
  opdsId: id,
  title: 'Series $id',
  author: 'A',
  description: '',
  genres: const [],
  readingStatus: 'ongoing',
  totalChapters: 10,
  downloadedChapters: 0,
  coverUrl: '',
  updatedAt: DateTime.utc(2026, 6, 1),
  directEpubUrl: '',
  volumesFeedUrl: '',
);

DateTime _day(int d) => DateTime.utc(2026, 7, d);

void main() {
  group('seriesCheckOrder', () {
    test('checks the most recently read series first', () {
      final order = seriesCheckOrder([
        _entry(1, readAt: _day(1)),
        _entry(2, readAt: _day(20)),
        _entry(3, readAt: _day(10)),
      ]);
      expect(order.map((e) => e.volume.seriesOpdsId), [2, 3, 1]);
    });

    test('skips series that were never started', () {
      final unstarted = ReadingEntry(
        volume: _vol(9),
        progress: const ReadingProgress(chapterIndex: 0, blockIndex: 0),
      );
      final order = seriesCheckOrder([unstarted, _entry(1, readAt: _day(1))]);
      expect(order.map((e) => e.volume.seriesOpdsId), [1]);
    });

    test('one entry per series — the furthest read', () {
      final order = seriesCheckOrder([
        _entry(1, readAt: _day(1), file: 'v1.epub'),
        _entry(1, readAt: _day(9), file: 'v2.epub'),
      ]);
      expect(order, hasLength(1));
      expect(order.single.volume.fileName, 'v2.epub');
    });

    test('entries with no read time sort last', () {
      final order = seriesCheckOrder([
        _entry(1),
        _entry(2, readAt: _day(5)),
      ]);
      expect(order.map((e) => e.volume.seriesOpdsId), [2, 1]);
    });

    test('an empty library yields nothing to check', () {
      expect(seriesCheckOrder(const []), isEmpty);
    });
  });

  group('libraryScanOrder', () {
    test('scans recently-read series before the rest', () {
      final order = libraryScanOrder(
        [_series(1), _series(2), _series(3)],
        [_entry(3, readAt: _day(20)), _entry(1, readAt: _day(2))],
      );
      expect(order.map((s) => s.opdsId), [3, 1, 2]);
    });

    test('unread series keep their existing relative order', () {
      // Only series 2 has been read; 1, 3, 4 must not be shuffled.
      final order = libraryScanOrder(
        [_series(1), _series(2), _series(3), _series(4)],
        [_entry(2, readAt: _day(5))],
      );
      expect(order.map((s) => s.opdsId), [2, 1, 3, 4]);
    });

    test('ties keep their original order', () {
      final same = _day(7);
      final order = libraryScanOrder(
        [_series(1), _series(2)],
        [_entry(2, readAt: same), _entry(1, readAt: same)],
      );
      expect(order.map((s) => s.opdsId), [1, 2]);
    });

    test('with nothing read the library is untouched', () {
      final order = libraryScanOrder(
        [_series(1), _series(2), _series(3)],
        const [],
      );
      expect(order.map((s) => s.opdsId), [1, 2, 3]);
    });

    test('every series is still scanned, none dropped', () {
      final lib = [for (var i = 1; i <= 6; i++) _series(i)];
      final order = libraryScanOrder(lib, [_entry(4, readAt: _day(3))]);
      expect(order, hasLength(6));
      expect(order.map((s) => s.opdsId).toSet(), {1, 2, 3, 4, 5, 6});
    });
  });
}
