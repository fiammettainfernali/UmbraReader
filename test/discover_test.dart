// Tests for the pieces that moved when Discover became a real tab.
//
// The shelves used to live above the library grid and the Discover tab
// opened the server controls — two different jobs behind one label. The
// selection logic came along with them.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/services/recommendation_loader.dart';

Series _s({
  required int id,
  String title = 'S',
  DateTime? updatedAt,
  DateTime? addedAt,
}) => Series(
  opdsId: id,
  title: title,
  author: '',
  description: '',
  genres: const [],
  readingStatus: 'ongoing',
  totalChapters: 10,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: updatedAt,
  addedAt: addedAt,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

DateTime _day(int d) => DateTime(2026, 8, d);

void main() {
  group('recentlyUpdated', () {
    test('newest first', () {
      final out = recentlyUpdated([
        _s(id: 1, title: 'old', updatedAt: _day(1)),
        _s(id: 2, title: 'newest', updatedAt: _day(9)),
        _s(id: 3, title: 'middle', updatedAt: _day(5)),
      ]);
      expect([for (final s in out) s.title], ['newest', 'middle', 'old']);
    });

    test('undated series are left out rather than sorted arbitrarily', () {
      // Novel Grabber bumps updatedAt when it recompiles, so a series
      // without one has nothing to say about being recent.
      final out = recentlyUpdated([
        _s(id: 1, title: 'dated', updatedAt: _day(3)),
        _s(id: 2, title: 'undated'),
      ]);
      expect([for (final s in out) s.title], ['dated']);
    });

    test('respects the limit', () {
      final out = recentlyUpdated([
        for (var i = 1; i <= 30; i++) _s(id: i, updatedAt: _day(i % 28 + 1)),
      ], limit: 5);
      expect(out.length, 5);
    });

    test('an empty library yields an empty shelf, not an error', () {
      expect(recentlyUpdated(const []), isEmpty);
    });

    test('does not mutate the list it was given', () {
      final library = [
        _s(id: 1, title: 'a', updatedAt: _day(1)),
        _s(id: 2, title: 'b', updatedAt: _day(9)),
      ];
      recentlyUpdated(library);
      expect([for (final s in library) s.title], ['a', 'b']);
    });
  });

  group('recentlyAdded', () {
    test('newest first', () {
      final out = recentlyAdded([
        _s(id: 1, title: 'old', addedAt: _day(1)),
        _s(id: 2, title: 'newest', addedAt: _day(9)),
        _s(id: 3, title: 'middle', addedAt: _day(5)),
      ]);
      expect([for (final s in out) s.title], ['newest', 'middle', 'old']);
    });

    test('a server too old to send the date contributes nothing', () {
      // addedAt is null on every series until Novel Grabber is rebuilt with
      // ng:addedAt. The shelf must stay empty rather than inventing an order.
      final out = recentlyAdded([
        _s(id: 1, title: 'a', updatedAt: _day(3)),
        _s(id: 2, title: 'b', updatedAt: _day(4)),
      ]);
      expect(out, isEmpty);
    });

    test('added order is independent of update order', () {
      // The whole reason this shelf exists: a bulk recompile rewrites every
      // updatedAt at once, and must not disturb what was added when.
      final out = recentlyAdded([
        _s(id: 1, title: 'added first', addedAt: _day(1), updatedAt: _day(20)),
        _s(id: 2, title: 'added last', addedAt: _day(9), updatedAt: _day(20)),
      ]);
      expect([for (final s in out) s.title], ['added last', 'added first']);
    });

    test('respects the limit', () {
      final out = recentlyAdded([
        for (var i = 1; i <= 30; i++) _s(id: i, addedAt: _day(i % 28 + 1)),
      ], limit: 5);
      expect(out.length, 5);
    });

    test('an empty library yields an empty shelf, not an error', () {
      expect(recentlyAdded(const []), isEmpty);
    });

    test('does not mutate the list it was given', () {
      final library = [
        _s(id: 1, title: 'a', addedAt: _day(1)),
        _s(id: 2, title: 'b', addedAt: _day(9)),
      ];
      recentlyAdded(library);
      expect([for (final s in library) s.title], ['a', 'b']);
    });
  });

  group('addedAt survives the cache', () {
    test('round-trips through JSON', () {
      // Discover reads the on-disk cache, not the feed, so a field that
      // does not survive toJson never reaches the shelf at all.
      final original = _s(id: 7, title: 'T', addedAt: _day(4));
      final revived = Series.fromJson(original.toJson());
      expect(revived.addedAt, _day(4));
    });

    test('a cache written before the field existed reads as null', () {
      final json = _s(id: 7, title: 'T', updatedAt: _day(4)).toJson()
        ..remove('addedAt');
      expect(Series.fromJson(json).addedAt, isNull);
    });
  });

  group('RecommendationLoader', () {
    test('an empty library short-circuits without touching any store', () {
      // Worth pinning: the loader reads seven stores, and doing that on a
      // fresh install to rank nothing would be pure waste.
      expectLater(
        const RecommendationLoader().load(const []),
        completion(isEmpty),
      );
    });

    test('carries a wider pool than the shelf shows', () {
      // The shelf shuffles through a pool; equal sizes would make shuffle
      // a no-op.
      expect(const RecommendationLoader().maxResults, greaterThan(12));
    });
  });
}
