// Tests for the filter dimensions and sorts added alongside search:
// length bands, update recency, collection membership, and genre all-vs-any.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/library_view.dart';
import 'package:umbra_reader/models/series.dart';

Series _s({
  int id = 1,
  String title = 'A Series',
  List<String> genres = const [],
  int chapters = 100,
  DateTime? updatedAt,
}) => Series(
  opdsId: id,
  title: title,
  author: 'Someone',
  description: '',
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: chapters,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: updatedAt,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

final _now = DateTime(2026, 7, 31, 12);

void main() {
  group('LengthBand', () {
    test('bands are half-open so no chapter count falls in two of them', () {
      // 300 exactly must land in medium only, 1000 in long only.
      expect(LengthBand.short.contains(300), isFalse);
      expect(LengthBand.medium.contains(300), isTrue);
      expect(LengthBand.medium.contains(1000), isFalse);
      expect(LengthBand.long.contains(1000), isTrue);
    });

    test('the top band is open-ended', () {
      expect(LengthBand.long.contains(5000), isTrue);
    });

    test('any accepts everything, including zero', () {
      expect(LengthBand.any.contains(0), isTrue);
      expect(LengthBand.any.contains(99999), isTrue);
    });

    test('an unknown stored name falls back to any', () {
      expect(LengthBand.fromName('epic'), LengthBand.any);
    });
  });

  group('UpdatedWithin', () {
    test('accepts a series updated inside the window', () {
      expect(
        UpdatedWithin.week.contains(
          _now.subtract(const Duration(days: 3)),
          _now,
        ),
        isTrue,
      );
    });

    test('rejects one updated outside it', () {
      expect(
        UpdatedWithin.week.contains(
          _now.subtract(const Duration(days: 30)),
          _now,
        ),
        isFalse,
      );
    });

    test('an undated series fails the filter rather than slipping through', () {
      expect(UpdatedWithin.week.contains(null, _now), isFalse);
      expect(
        UpdatedWithin.any.contains(null, _now),
        isTrue,
        reason: 'but "any time" still means any',
      );
    });
  });

  group('genre any vs all', () {
    final both = _s(genres: ['Cultivation', 'Xianxia']);
    final one = _s(genres: ['Cultivation']);

    test('any-match is the default and widens', () {
      const f = LibraryFilters(genres: {'Cultivation', 'Xianxia'});
      expect(f.matchAllGenres, isFalse);
      expect(f.matches(one, isDownloaded: false, now: _now), isTrue);
      expect(f.matches(both, isDownloaded: false, now: _now), isTrue);
    });

    test('all-match narrows to series carrying every selected genre', () {
      const f = LibraryFilters(
        genres: {'Cultivation', 'Xianxia'},
        matchAllGenres: true,
      );
      expect(f.matches(one, isDownloaded: false, now: _now), isFalse);
      expect(f.matches(both, isDownloaded: false, now: _now), isTrue);
    });
  });

  group('collection filter', () {
    test('keeps only members of the chosen collection', () {
      const f = LibraryFilters(collectionId: 'c1');
      expect(
        f.matches(
          _s(id: 7),
          isDownloaded: false,
          now: _now,
          collectionSeriesIds: {7, 9},
        ),
        isTrue,
      );
      expect(
        f.matches(
          _s(id: 8),
          isDownloaded: false,
          now: _now,
          collectionSeriesIds: {7, 9},
        ),
        isFalse,
      );
    });

    test('a collection with unknown membership matches nothing', () {
      // A deleted collection must not silently behave as no filter at all.
      const f = LibraryFilters(collectionId: 'gone');
      expect(f.matches(_s(id: 7), isDownloaded: false, now: _now), isFalse);
    });
  });

  group('combined filters', () {
    test('every clause must pass, not just one', () {
      const f = LibraryFilters(
        genres: {'Cultivation'},
        length: LengthBand.long,
      );
      final rightGenreWrongLength = _s(genres: ['Cultivation'], chapters: 50);
      expect(
        f.matches(rightGenreWrongLength, isDownloaded: false, now: _now),
        isFalse,
      );
    });
  });

  group('isEmpty and activeCount', () {
    test('the new clauses count and un-empty the filter set', () {
      const length = LibraryFilters(length: LengthBand.long);
      expect(length.isEmpty, isFalse);
      expect(length.activeCount, 1);

      const three = LibraryFilters(
        length: LengthBand.long,
        updated: UpdatedWithin.month,
        collectionId: 'c1',
      );
      expect(three.activeCount, 3);
    });

    test('a default filter set is still empty', () {
      expect(const LibraryFilters().isEmpty, isTrue);
      expect(const LibraryFilters().activeCount, 0);
    });
  });

  group('persistence of the new clauses', () {
    test('they survive a round trip', () {
      const view = LibraryView(
        sort: LibrarySort.timeSpent,
        filters: LibraryFilters(
          genres: {'Cultivation'},
          matchAllGenres: true,
          length: LengthBand.medium,
          updated: UpdatedWithin.quarter,
          collectionId: 'c9',
        ),
      );
      final back = LibraryView.fromJson(view.toJson());
      expect(back.sort, LibrarySort.timeSpent);
      expect(back.filters.matchAllGenres, isTrue);
      expect(back.filters.length, LengthBand.medium);
      expect(back.filters.updated, UpdatedWithin.quarter);
      expect(back.filters.collectionId, 'c9');
    });

    test('a view saved before these existed still loads', () {
      // Older builds wrote no length/updated/collection keys at all.
      final back = LibraryFilters.fromJson({
        'genres': ['Cultivation'],
        'statuses': <String>[],
      });
      expect(back.genres, {'Cultivation'});
      expect(back.length, LengthBand.any);
      expect(back.updated, UpdatedWithin.any);
      expect(back.collectionId, isNull);
      expect(back.matchAllGenres, isFalse);
    });

    test('clearing the collection is distinct from leaving it alone', () {
      const f = LibraryFilters(collectionId: 'c1');
      expect(f.copyWith().collectionId, 'c1', reason: 'untouched');
      expect(f.copyWith(collectionId: null).collectionId, isNull);
    });
  });

  group('new sorts', () {
    test('each names directions that suit it', () {
      expect(LibrarySort.length.directionLabels, (
        'Longest first',
        'Shortest first',
      ));
      expect(LibrarySort.timeSpent.directionLabels, (
        'Most read',
        'Least read',
      ));
    });

    test('every sort option has direction labels', () {
      // A missing branch would be a compile error, but this also catches a
      // placeholder pair being left identical.
      for (final s in LibrarySort.values) {
        final (up, down) = s.directionLabels;
        expect(up, isNotEmpty);
        expect(down, isNotEmpty);
        expect(up, isNot(down));
      }
    });
  });
}
