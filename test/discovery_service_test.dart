// Taste-driven source discovery ("option 1"): the profile's top queries,
// and the DiscoveryService that turns them into deduped, interleaved,
// failure-tolerant source-search picks.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/control_client.dart';
import 'package:umbra_reader/services/discovery_service.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/recommendation_engine.dart';

Series _series({
  required int id,
  required String title,
  String? author,
  List<String> genres = const [],
  String description = '',
}) => Series(
  opdsId: id,
  title: title,
  author: author ?? 'Author $id',
  description: description,
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: 200,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

ReadingEntry _finished(int seriesId, DateTime at) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: seriesId,
    title: 'Vol',
    fileName: 'v1.epub',
    downloadUrl: '',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: ReadingProgress(
    chapterIndex: 199,
    blockIndex: 0,
    chapterCount: 200,
    endReached: true,
    updatedAt: at,
  ),
);

SearchHit _hit(String title, {String site = 'siteA', String? url}) => SearchHit(
  title: title,
  author: 'someone',
  url: url ?? 'https://x/$title',
  coverUrl: '',
  latestChapter: '',
  site: site,
);

void main() {
  final today = DateTime.utc(2026, 7, 12);

  group('RecTasteProfile.topQueries', () {
    test('exports author, bigram keyword and genre with seed reasons', () {
      const engine = RecommendationEngine();
      final lib = [
        _series(
          id: 1,
          title: 'Reverend Insanity',
          author: 'Gu Zhen Ren',
          genres: ['Cultivation'],
          description:
              'A venomous transmigrator refines gu worms through martial '
              'arts and heavenly secrets. Martial arts and gu worms '
              'everywhere.',
        ),
        _series(id: 2, title: 'Other', genres: ['Romance'],
            description: 'A sweet office romance with contracts.'),
      ];
      final profile = engine.buildProfile(
        allSeries: lib,
        readingEntries: [_finished(1, today)],
        now: today,
      );
      final queries = profile.topQueries(max: 4);
      expect(queries, isNotEmpty);
      final kinds = {for (final q in queries) q.kind};
      expect(kinds, contains('author'));
      final author = queries.firstWhere((q) => q.kind == 'author');
      expect(author.query, 'gu zhen ren');
      expect(author.reason, contains('Reverend Insanity'));
      // No short generic single-word keywords as queries.
      for (final q in queries.where((q) => q.kind == 'keyword')) {
        expect(q.query.contains(' ') || q.query.length >= 5, isTrue,
            reason: '"${q.query}" is too generic to search');
      }
    });

    test('unknown authors never become queries', () {
      const engine = RecommendationEngine();
      final lib = [
        _series(id: 1, title: 'Anon Work', author: 'Unknown',
            genres: ['Cultivation']),
        _series(id: 2, title: 'Other', genres: ['Romance']),
      ];
      final profile = engine.buildProfile(
        allSeries: lib,
        readingEntries: [_finished(1, today)],
        now: today,
      );
      expect(
        profile.topQueries().where((q) => q.kind == 'author'),
        isEmpty,
      );
    });
  });

  group('DiscoveryService.discover', () {
    const q1 = TasteQuery(query: 'gu zhen ren', kind: 'author', reason: 'R1');
    const q2 = TasteQuery(query: 'martial arts', kind: 'keyword',
        reason: 'R2');

    test('dedupes against the library and across queries, interleaved', () async {
      final picks = await const DiscoveryService().discover(
        queries: const [q1, q2],
        sites: const ['siteA'],
        search: (query, site) async => switch (query) {
          'gu zhen ren' => [
              _hit('Already Have!'), // in library (punctuation differs)
              _hit('Fresh One'),
              _hit('Fresh Two'),
            ],
          _ => [
              _hit('Fresh One', url: 'https://y/dupe'), // cross-query dupe
              _hit('Fresh Three'),
            ],
        },
        libraryTitles: const ['already have'],
      );
      final titles = [for (final p in picks) p.hit.title];
      expect(titles, ['Fresh One', 'Fresh Three', 'Fresh Two'],
          reason: 'library dupe dropped, cross-query dupe dropped, '
              'round-robin across queries');
      expect(picks[0].reason, 'R1');
      expect(picks[1].reason, 'R2');
    });

    test('one failing source does not sink the rest', () async {
      final picks = await const DiscoveryService().discover(
        queries: const [q1],
        sites: const ['dead', 'alive'],
        search: (query, site) async {
          if (site == 'dead') throw ControlException('blocked');
          return [_hit('Survivor', site: site)];
        },
        libraryTitles: const [],
      );
      expect(picks, hasLength(1));
      expect(picks.single.hit.title, 'Survivor');
    });

    test('stops early at maxResults and caps hits per search', () async {
      var calls = 0;
      final picks = await const DiscoveryService(
        maxResults: 4,
        maxHitsPerSearch: 3,
      ).discover(
        queries: const [q1, q2],
        sites: const ['a', 'b'],
        search: (query, site) async {
          calls++;
          return [for (var i = 0; i < 10; i++) _hit('$query-$site-$i')];
        },
        libraryTitles: const [],
      );
      expect(picks, hasLength(4));
      expect(calls, lessThanOrEqualTo(2),
          reason: 'the budget stops as soon as enough picks exist');
    });

    test('empty queries or sites means no network at all', () async {
      var called = false;
      final picks = await const DiscoveryService().discover(
        queries: const [],
        sites: const ['a'],
        search: (q, s) async {
          called = true;
          return [];
        },
        libraryTitles: const [],
      );
      expect(picks, isEmpty);
      expect(called, isFalse);
    });
  });
}
