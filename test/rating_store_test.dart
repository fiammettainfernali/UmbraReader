// Your ratings: stars and a line of thoughts, kept in step with the computer
// newest first, and used to pick what to read next.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/services/choosing.dart';
import 'package:umbra_reader/services/rating_store.dart';

Series _series(int id) => Series(
  opdsId: id,
  title: 'Book $id',
  author: 'Author',
  description: 'A long enough description for the spotlight rule to let it in. ' * 2,
  genres: const ['Fantasy'],
  readingStatus: '',
  totalChapters: 100,
  downloadedChapters: 100,
  coverUrl: 'http://pc/cover/$id',
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('stars and a note come back, and none clears them', () async {
    final store = RatingStore();
    await store.rate(7, 4, note: '  Loved the harbour arc ');
    final r = await store.ratingFor(7);
    expect((r!.stars, r.note), (4, 'Loved the harbour arc'));
    await store.rate(7, 0, note: 'ignored');
    expect(await store.ratingFor(7), isNull);
  });

  test('a clear survives the other device sending its older rating', () async {
    final store = RatingStore();
    await store.rate(7, 0);
    final older = jsonEncode({
      '7': {'stars': 5, 'note': '', 'at': '2020-01-01T00:00:00.000'},
    });
    expect(await store.mergeSyncBlob(older), isFalse);
    expect(await store.ratingFor(7), isNull);
  });

  test('a newer rating from the computer is taken, an older one is not', () async {
    final store = RatingStore();
    await store.rate(7, 3);
    final newer = jsonEncode({
      '7': {'stars': 5, 'note': 'Better on a reread', 'at': '2099-01-01T00:00:00.000'},
      '8': {'stars': 2, 'note': '', 'at': '2026-11-01T00:00:00.000'},
    });
    expect(await store.mergeSyncBlob(newer), isTrue);
    final all = await store.load();
    expect(all[7]!.stars, 5);
    expect(all[7]!.note, 'Better on a reread');
    expect(all[8]!.stars, 2);
  });

  test('never used, nothing is sent', () async {
    expect(await RatingStore().exportSyncBlob(), '');
  });

  test('a book you rated highly leads the like-this pick, and rated books are not new', () {
    final library = [for (var i = 1; i <= 6; i++) _series(i)];
    final picks = pickTonight(
      library: library,
      shelf: const [],
      entries: const [],
      statuses: const {},
      feedback: const {},
      today: DateTime(2026, 11, 21),
      similar: (_) => [library[3], library[2]],
      ratings: {
        2: Rating(stars: 5, at: DateTime(2026, 11, 20)),
        3: Rating(stars: 2, at: DateTime(2026, 11, 21)),
      },
    );
    final like = picks.firstWhere((p) => p.kind == TonightKind.likeLast);
    expect(like.series.opdsId, 4);
    expect(like.reason, 'Like Book 2, which you rated 5 stars');
    expect(picks.map((p) => p.series.opdsId), isNot(contains(3)));
  });
}
