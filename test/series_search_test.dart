// Tests for library search matching, ranking and the genre facets.
//
// The old behaviour was `title.contains(query)` on raw strings, so word
// order, spacing, accents and typos each broke a search outright, and there
// was no notion of a better match. These pin the replacement.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/services/recent_searches_store.dart';
import 'package:umbra_reader/services/series_search.dart';

Series _s({
  int id = 1,
  String title = 'A Series',
  String author = 'Someone',
  String description = '',
  List<String> genres = const [],
}) => Series(
  opdsId: id,
  title: title,
  author: author,
  description: description,
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: 10,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

List<String> _titles(List<Series> l) => [for (final s in l) s.title];

void main() {
  group('foldForSearch', () {
    test('lower-cases and strips accents', () {
      expect(foldForSearch('Café Ámbar'), 'cafe ambar');
    });

    test('reduces punctuation to spaces so Re:Zero is reachable', () {
      expect(foldForSearch('Re:Zero'), 're zero');
    });

    test('keeps non-Latin text rather than erasing it', () {
      // Treating CJK as punctuation would delete the whole title.
      expect(foldForSearch('魔法'), '魔法');
    });
  });

  group('searchTerms', () {
    test('splits on whitespace and drops empties', () {
      expect(searchTerms('  primal   hunter '), ['primal', 'hunter']);
    });

    test('a blank query yields no terms', () {
      expect(searchTerms('   '), isEmpty);
      expect(searchTerms('!!!'), isEmpty);
    });
  });

  group('scoreSeries', () {
    final hunter = _s(title: 'The Primal Hunter');

    test('word order no longer matters', () {
      // The original bug: this found nothing.
      expect(scoreSeries(hunter, searchTerms('hunter primal')), isNotNull);
    });

    test('every term must land somewhere', () {
      expect(scoreSeries(hunter, searchTerms('primal wizard')), isNull);
    });

    test('punctuation and spacing differences still match', () {
      final rezero = _s(title: 'Re:Zero');
      expect(scoreSeries(rezero, searchTerms('rezero')), isNotNull);
      expect(scoreSeries(rezero, searchTerms('re zero')), isNotNull);
    });

    test('an empty query matches everything with a neutral score', () {
      expect(scoreSeries(hunter, const []), 0);
    });

    test('matches the author', () {
      expect(
        scoreSeries(_s(author: 'Zogarth'), searchTerms('zogarth')),
        isNotNull,
      );
    });

    test('matches a genre, which the old search never did', () {
      expect(
        scoreSeries(_s(genres: ['Cultivation']), searchTerms('cultivation')),
        isNotNull,
      );
    });

    test('a description supports a term but cannot qualify a series', () {
      // Searching "two" used to return 28 of 486 series, because a word
      // that common appears in most blurbs.
      expect(
        scoreSeries(
          _s(description: 'A tale of beast cores and levelling'),
          searchTerms('beast'),
        ),
        isNull,
        reason: 'description alone is not evidence of relevance',
      );
      // But once the title has established relevance, the description can
      // satisfy the rest of the query.
      expect(
        scoreSeries(
          _s(title: 'Beast Tamer', description: 'about cores and levelling'),
          searchTerms('beast cores'),
        ),
        isNotNull,
      );
    });

    test('a short term does not match mid-word', () {
      // The reported bug: "two" matched "neTWOrk" and "beTWOeen".
      expect(
        scoreSeries(_s(title: 'Network Chronicles'), searchTerms('two')),
        isNull,
      );
      expect(
        scoreSeries(
          _s(title: 'A Story', description: 'somewhere between two worlds'),
          searchTerms('two'),
        ),
        isNull,
      );
    });

    test('a short term still matches at the start of a word', () {
      expect(
        scoreSeries(_s(title: 'Two Small Hearts'), searchTerms('two')),
        isNotNull,
      );
    });

    test('a long term may still match mid-word, for CJK and run-ons', () {
      expect(
        scoreSeries(_s(title: 'Re:Zero'), searchTerms('rezero')),
        isNotNull,
      );
    });

    test('author and genre match at word starts, not inside words', () {
      expect(
        scoreSeries(_s(author: 'Networking Press'), searchTerms('two')),
        isNull,
      );
      expect(scoreSeries(_s(genres: ['Network']), searchTerms('two')), isNull);
    });
  });

  group('the reported "two" search', () {
    // Titles taken from the screenshot of the bad result set.
    final library = [
      _s(id: 1, title: 'Abyss Draconis', description: 'two dragons clash'),
      _s(id: 2, title: 'Connected Hearts', description: 'between two girls'),
      _s(id: 3, title: 'Getting A System In A Modern World'),
      _s(id: 4, title: 'MAGUS INFINITE', description: 'a network of magi'),
      _s(id: 5, title: 'Two Small Hearts'),
    ];

    test('returns the title the reader was looking for, and only it', () {
      final hits = rankedSearch(library, 'two');
      expect(_titles(hits), ['Two Small Hearts']);
    });
  });

  group('rankedSearch ordering', () {
    test('a title hit beats a description hit', () {
      final result = rankedSearch([
        _s(id: 1, title: 'Unrelated', description: 'mentions a shadow slave'),
        _s(id: 2, title: 'Shadow Slave'),
      ], 'shadow slave');
      expect(_titles(result).first, 'Shadow Slave');
    });

    test('a title beats an author, and an author beats a genre', () {
      final result = rankedSearch([
        _s(id: 1, title: 'C', genres: ['Nightfall']),
        _s(id: 2, title: 'B', author: 'Nightfall'),
        _s(id: 3, title: 'Nightfall'),
      ], 'nightfall');
      expect(_titles(result), ['Nightfall', 'B', 'C']);
    });

    test('a title starting with the term beats one merely containing it', () {
      final result = rankedSearch([
        _s(id: 1, title: 'The Hunter Chronicles'),
        _s(id: 2, title: 'Hunter'),
      ], 'hunter');
      expect(_titles(result).first, 'Hunter');
    });

    test('a shorter title wins when the terms match equally well', () {
      final result = rankedSearch([
        _s(id: 1, title: 'Shadow Slave And The Long Extended Subtitle'),
        _s(id: 2, title: 'Shadow Slave'),
      ], 'shadow slave');
      expect(_titles(result).first, 'Shadow Slave');
    });

    test('non-matches are dropped, not merely sorted last', () {
      final result = rankedSearch([
        _s(id: 1, title: 'Shadow Slave'),
        _s(id: 2, title: 'Something Else'),
      ], 'shadow');
      expect(_titles(result), ['Shadow Slave']);
    });

    test('an empty query returns everything, order untouched', () {
      final all = [_s(id: 1, title: 'B'), _s(id: 2, title: 'A')];
      expect(_titles(rankedSearch(all, '')), ['B', 'A']);
    });
  });

  group('genreFacets', () {
    final library = [
      _s(id: 1, genres: ['Fantasy', 'Action']),
      _s(id: 2, genres: ['Fantasy', 'Romance']),
      _s(id: 3, genres: ['Fantasy']),
      _s(id: 4, genres: ['Action']),
      _s(id: 5, genres: ['  ', 'Obscure']),
    ];

    test('orders by how many series carry each genre', () {
      final facets = genreFacets(library);
      expect(facets.first, (name: 'Fantasy', count: 3));
      expect(facets[1], (name: 'Action', count: 2));
    });

    test('ties break alphabetically so the order is stable', () {
      final facets = genreFacets(library).where((f) => f.count == 1).toList();
      expect([for (final f in facets) f.name], ['Obscure', 'Romance']);
    });

    test('blank genres are dropped', () {
      expect(genreFacets(library).map((f) => f.name), isNot(contains('  ')));
    });
  });

  group('filterFacets', () {
    final facets = genreFacets([
      _s(id: 1, genres: ['Fantasy', 'Dark Fantasy', 'Romance']),
      _s(id: 2, genres: ['Fantasy']),
    ]);

    test('narrows to matching genres', () {
      final out = filterFacets(facets, 'fantasy', const {});
      expect([for (final f in out) f.name], ['Fantasy', 'Dark Fantasy']);
    });

    test('a selected genre stays visible even when it does not match', () {
      // Otherwise an applied filter vanishes while you search for another,
      // and there is no way to see or remove it.
      final out = filterFacets(facets, 'fantasy', const {'Romance'});
      expect(out.first.name, 'Romance');
      expect([for (final f in out) f.name], contains('Fantasy'));
    });

    test('an empty query keeps everything, selected first', () {
      final out = filterFacets(facets, '', const {'Romance'});
      expect(out.first.name, 'Romance');
      expect(out.length, facets.length);
    });
  });

  group('RecentSearchesStore', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('records most recent first', () async {
      final store = RecentSearchesStore();
      await store.record('shadow');
      final out = await store.record('hunter');
      expect(out, ['hunter', 'shadow']);
    });

    test('repeating a search promotes it instead of duplicating', () async {
      final store = RecentSearchesStore();
      await store.record('shadow');
      await store.record('hunter');
      final out = await store.record('SHADOW');
      expect(out, ['SHADOW', 'hunter']);
    });

    test('very short queries are not remembered', () async {
      // These are keystrokes on the way somewhere, not searches.
      final store = RecentSearchesStore();
      expect(await store.record('sh'), isEmpty);
    });

    test('the list is capped', () async {
      final store = RecentSearchesStore();
      for (var i = 0; i < 12; i++) {
        await store.record('query$i');
      }
      expect((await store.load()).length, RecentSearchesStore.maxEntries);
    });

    test('an entry can be forgotten', () async {
      final store = RecentSearchesStore();
      await store.record('shadow');
      await store.record('hunter');
      expect(await store.remove('shadow'), ['hunter']);
    });
  });
}
