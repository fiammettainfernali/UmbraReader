// Ranking by meaning, and the indexing that feeds it.
//
// No model here: the vectors are hand-placed so "these two books are about
// the same thing" is a fact of the fixture rather than something the test
// hopes the model got right. What is under test is everything around the
// model — which books get indexed, which get skipped, and what comes back
// when the index has nothing useful to say.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/services/semantic_recommender.dart';
import 'package:umbra_reader/services/series_indexer.dart';
import 'package:umbra_reader/services/series_vector_store.dart';
import 'package:umbra_reader/services/text_embedder.dart';

import 'helpers/test_db.dart';

Series _series({
  required int id,
  String title = 'A Book',
  String description = 'Something happens.',
  List<String> genres = const ['Fantasy'],
  DateTime? addedAt,
}) => Series(
  opdsId: id,
  title: title,
  author: 'Anon',
  description: description,
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: 100,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  addedAt: addedAt,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

/// A direction in a tiny space, so "alike" is arranged by hand.
Float32List _at(double x, double y) =>
    l2Normalize(Float32List.fromList([x, y]));

void main() {
  group('ranking', () {
    // Two cultivation novels pointing one way, a romance pointing another.
    final cultivationA = _series(id: 1, title: 'Azure Peak');
    final cultivationB = _series(id: 2, title: 'Jade Summit');
    final romance = _series(id: 3, title: 'Tea Shop Afternoons');
    final library = [cultivationA, cultivationB, romance];
    final vectors = {
      1: _at(1, 0.05),
      2: _at(1, 0.1),
      3: _at(0.05, 1),
    };

    test('the nearest book comes first, and the source is not in its own list', () {
      final picks = mostSimilarTo(
        source: cultivationA,
        library: library,
        vectors: vectors,
      );

      expect(picks.first.series.opdsId, 2);
      expect(
        picks.map((p) => p.series.opdsId),
        isNot(contains(1)),
        reason: 'a book is not similar to itself, it IS itself',
      );
    });

    test('nothing related is an empty shelf, not six unrelated books', () {
      // A library with one lonely horror novel: the six nearest things to
      // it are not horror. Saying nothing is more honest than filling the
      // space, and it is what sent age regression to a cultivation novel.
      final picks = mostSimilarTo(
        source: romance,
        library: [romance, cultivationA, cultivationB],
        vectors: vectors,
        floor: 0.5,
      );

      expect(picks, isEmpty);
    });

    test('an unindexed book falls back rather than guessing', () {
      final picks = mostSimilarTo(
        source: _series(id: 99, title: 'Never Indexed'),
        library: library,
        vectors: vectors,
      );

      expect(
        picks,
        isEmpty,
        reason: 'empty tells the caller to use the old engine',
      );
    });

    test('taste is built from what was read, weighted by how it was read', () {
      final picks = mostSimilarToTaste(
        readWeights: {1: 1.0},
        library: library,
        vectors: vectors,
      );

      expect(picks.first.series.opdsId, 2);
      expect(
        picks.map((p) => p.series.opdsId),
        isNot(contains(1)),
        reason: 'what has been read is not a recommendation',
      );
    });

    test('a book bounced off does not drag taste to its opposite', () {
      // Weight at or below zero drops the book. Subtracting it instead
      // would make "not for me" an argument FOR the furthest thing away.
      final picks = mostSimilarToTaste(
        readWeights: {1: 1.0, 3: -5.0},
        library: library,
        vectors: vectors,
        floor: -1,
      );

      expect(picks.first.series.opdsId, 2);
    });

    test('having read nothing yields nothing', () {
      expect(
        mostSimilarToTaste(
          readWeights: const {},
          library: library,
          vectors: vectors,
        ),
        isEmpty,
      );
    });

    test('a phrase finds the books it means', () {
      final hits = matching(
        query: _at(1, 0),
        library: library,
        vectors: vectors,
        limit: 2,
      );

      expect(hits.map((h) => h.series.opdsId), [1, 2]);
    });
  });

  group('indexing', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await useInMemoryDatabase();
    });

    tearDown(AppDatabase.reset);

    /// Counts calls, so "did this book get embedded again" is answerable.
    /// Log lines are captured rather than printed: they belong to the one
    /// test that is about them, and nowhere else.
    ({SeriesIndexer indexer, List<String> seen, List<String> logged}) build() {
      final seen = <String>[];
      final logged = <String>[];
      return (
        indexer: SeriesIndexer(
          embed: (text) async {
            seen.add(text);
            logged.add('<inference>');
            return _at(text.length.toDouble(), 1);
          },
          log: logged.add,
        ),
        seen: seen,
        logged: logged,
      );
    }

    test('a first pass indexes the library', () async {
      final b = build();
      final outcome = await b.indexer.indexLibrary([
        _series(id: 1),
        _series(id: 2),
      ]);

      expect(outcome.embedded, 2);
      expect(outcome.isComplete, isTrue);
      expect(await SeriesVectorStore().count(), 2);
    });

    test('a second pass does nothing at all', () async {
      // The whole reason the text hash exists. Without it every launch
      // re-embeds the entire library, which is a minute of phone each time
      // for no change whatsoever.
      final library = [_series(id: 1), _series(id: 2)];
      final b = build();
      await b.indexer.indexLibrary(library);
      b.seen.clear();

      final outcome = await b.indexer.indexLibrary(library);

      expect(outcome.embedded, 0);
      expect(b.seen, isEmpty);
    });

    test('a rewritten blurb costs exactly one book', () async {
      final b = build();
      await b.indexer.indexLibrary([_series(id: 1), _series(id: 2)]);
      b.seen.clear();

      final outcome = await b.indexer.indexLibrary([
        _series(id: 1, description: 'Rewritten entirely.'),
        _series(id: 2),
      ]);

      expect(outcome.embedded, 1);
      expect(b.seen.single, contains('Rewritten entirely'));
    });

    test('a budget leaves the rest for next time', () async {
      final b = build();
      final outcome = await b.indexer.indexLibrary(
        [for (var i = 0; i < 10; i++) _series(id: i)],
        budget: 4,
      );

      expect(outcome.embedded, 4);
      expect(outcome.remaining, 6);
      expect(outcome.isComplete, isFalse);
    });

    test('the newest books are indexed first', () async {
      // A budget means some books wait. The shelf someone is about to look
      // at matters more than the one they filled two years ago.
      final b = build();
      await b.indexer.indexLibrary([
        _series(id: 1, title: 'Old', addedAt: DateTime(2024, 1, 1)),
        _series(id: 2, title: 'New', addedAt: DateTime(2026, 9, 1)),
      ], budget: 1);

      expect(b.seen.single, contains('New'));
    });

    test('a book that leaves the library takes its vector with it', () async {
      final b = build();
      await b.indexer.indexLibrary([_series(id: 1), _series(id: 2)]);

      final outcome = await b.indexer.indexLibrary([_series(id: 1)]);

      expect(outcome.pruned, 1);
      expect((await SeriesVectorStore().loadAll()).keys, [1]);
    });

    test('a book the model cannot embed is counted, not crashed on', () async {
      final logged = <String>[];
      final indexer = SeriesIndexer(embed: (_) async => null, log: logged.add);

      final outcome = await indexer.indexLibrary([_series(id: 1)]);

      expect(outcome.failed, 1);
      expect(outcome.embedded, 0);
      expect(logged.any((l) => l.contains('no vector for 1')), isTrue);
    });

    test('each book is named in the log before it is embedded', () async {
      // The ordering is the whole point. Inference runs in a native
      // runtime, and when that aborts there is no exception, no stack and
      // no further output — the process is simply gone. A line written
      // after the call would never exist for the book that caused it, so
      // the last line in the log has to be the one that names it.
      final b = build();

      await b.indexer.indexLibrary([_series(id: 4, title: 'Nine Star Hegemon')]);

      final named = b.logged.indexWhere((l) => l.contains('Nine Star Hegemon'));
      final inference = b.logged.indexOf('<inference>');
      expect(named, isNonNegative);
      expect(named, lessThan(inference));
    });

    test('a pass reports the same counts it returns', () async {
      // A log that disagrees with the outcome is worse than no log: it is
      // what gets believed when the shelves look wrong.
      final b = build();
      await b.indexer.indexLibrary([_series(id: 1), _series(id: 2)]);
      b.logged.clear();

      final outcome = await b.indexer.indexLibrary(
        [_series(id: 2), _series(id: 3), _series(id: 4)],
        budget: 1,
      );

      final summary = b.logged.lastWhere((l) => l.startsWith('pass done'));
      expect(outcome, isA<IndexOutcome>().having((o) => o.embedded, 'embedded', 1));
      expect(summary, contains('embedded ${outcome.embedded}'));
      expect(summary, contains('failed ${outcome.failed}'));
      expect(summary, contains('pruned ${outcome.pruned}'));
      expect(summary, contains('${outcome.remaining} left'));
    });

    test('vectors survive a round trip through the database', () async {
      // Float32 packed into a blob and read back: a byte-order slip here
      // would not throw, it would just rank the wrong books forever.
      final original = _at(0.3, 0.7);
      await SeriesVectorStore().put(7, original, 'hash');

      final back = (await SeriesVectorStore().loadAll())[7]!;

      expect(back.length, original.length);
      expect(cosineSimilarity(back, original), closeTo(1.0, 1e-6));
    });
  });

  group('fingerprints', () {
    test('the same text always hashes the same', () {
      // Not String.hashCode: that is only stable within one run, so every
      // launch would see the whole library as changed and re-embed it.
      expect(textFingerprint('Azure Peak'), textFingerprint('Azure Peak'));
    });

    test('different text hashes differently', () {
      expect(
        textFingerprint('Azure Peak'),
        isNot(textFingerprint('Azure Peaks')),
      );
    });
  });
}
