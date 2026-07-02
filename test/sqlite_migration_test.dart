// End-to-end coverage for the SharedPreferences → SQLite move: the one-time
// legacy imports for bookmarks / collections / activity, and the backup
// round-trip that serialises SQLite stores back into the legacy prefs shape.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/bookmark.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/backup_service.dart';
import 'package:umbra_reader/services/bookmark_store.dart';
import 'package:umbra_reader/services/collection_store.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/test_db.dart';

Volume _volume({int seriesId = 1, String fileName = 'book.epub'}) => Volume(
  seriesOpdsId: seriesId,
  title: 'A Book',
  fileName: fileName,
  downloadUrl: 'http://host/$fileName',
  fileSizeBytes: 1000,
  updatedAt: DateTime.utc(2026, 5, 1),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  test('legacy prefs bookmarks import once into SQLite', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'bookmarks:1/book.epub': jsonEncode([
        {
          'id': '100',
          'chapterIndex': 3,
          'blockIndex': 7,
          'chapterTitle': 'Three',
          'snippet': 'A snippet',
          'createdAt': '2026-05-01T10:00:00.000',
          'isHighlight': true,
          'note': 'loved this',
          'color': 'pink',
        },
      ]),
    });
    final marks = await BookmarkStore().list(_volume());
    expect(marks, hasLength(1));
    expect(marks.single.id, '100');
    expect(marks.single.isHighlight, isTrue);
    expect(marks.single.note, 'loved this');
    expect(marks.single.color, HighlightColor.pink);
    // Non-destructive: the legacy key survives.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bookmarks:1/book.epub'), isNotNull);
  });

  test('legacy prefs collections import once into SQLite', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'collections': jsonEncode([
        {
          'id': 'abc',
          'name': 'Favourites',
          'seriesIds': [3, 9],
          'createdAt': '2026-04-01T09:00:00.000',
        },
      ]),
      'collections_modified_at': '2026-04-02T09:00:00.000',
    });
    final list = await CollectionStore().list();
    expect(list, hasLength(1));
    expect(list.single.name, 'Favourites');
    expect(list.single.seriesIds, [3, 9]);
    expect(await CollectionStore().collectionsContaining(9), {'abc'});
  });

  test('legacy prefs activity imports once into SQLite', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reading_activity': jsonEncode({
        'daily': {'2026-06-30': 1200, '2026-07-01': 600},
        'perVolume': {'1/book.epub': 1800},
      }),
    });
    final activity = await ReadingActivityStore().load();
    expect(activity.totalSeconds, 1800);
    expect(activity.perVolumeSeconds['1/book.epub'], 1800);
    // And new recording lands on top of the imported tallies.
    await ReadingActivityStore().record(
      _volume(),
      const Duration(minutes: 1),
      now: DateTime(2026, 7, 1),
    );
    final after = await ReadingActivityStore().load();
    expect(after.dailySeconds['2026-07-01'], 660);
    expect(after.perVolumeSeconds['1/book.epub'], 1860);
  });

  test('full backup round-trips every SQLite store', () async {
    final volume = _volume();

    // Populate all four stores through their public APIs.
    await ReadingProgressStore().save(
      volume,
      const ReadingProgress(chapterIndex: 5, blockIndex: 2, chapterCount: 20),
    );
    await BookmarkStore().add(
      volume,
      Bookmark(
        id: '42',
        chapterIndex: 5,
        blockIndex: 2,
        chapterTitle: 'Five',
        snippet: 'snip',
        createdAt: DateTime(2026, 6, 1, 12),
        isHighlight: true,
        color: HighlightColor.green,
      ),
    );
    final favs = await CollectionStore().create('Favourites');
    await CollectionStore().setMembership(favs.id, 7, member: true);
    await ReadingActivityStore().record(
      volume,
      const Duration(minutes: 10),
      now: DateTime(2026, 7, 1),
    );

    final backup = await BackupService().exportToJson();
    // Migration flags must never travel in a backup.
    expect(backup, isNot(contains('_in_sqlite_v1')));

    // Simulate a fresh install: empty prefs, empty database.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();

    await BackupService().importFromJson(backup);

    final progress = await ReadingProgressStore().load(volume);
    expect(progress.chapterIndex, 5);
    expect(progress.chapterCount, 20);
    final marks = await BookmarkStore().list(volume);
    expect(marks, hasLength(1));
    expect(marks.single.color, HighlightColor.green);
    final collections = await CollectionStore().list();
    expect(collections.single.name, 'Favourites');
    expect(collections.single.seriesIds, [7]);
    final activity = await ReadingActivityStore().load();
    expect(activity.perVolumeSeconds['1/book.epub'], 600);
  });

  test('annotations-only export imports on top without wiping', () async {
    final volume = _volume();
    await BookmarkStore().add(
      volume,
      Bookmark(
        id: '1',
        chapterIndex: 0,
        blockIndex: 0,
        chapterTitle: 'One',
        snippet: 'a',
        createdAt: DateTime(2026, 6, 1),
      ),
    );
    final annotations = await BackupService().exportAnnotationsToJson();

    // A different device with its own bookmark.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    await BookmarkStore().add(
      volume,
      Bookmark(
        id: '2',
        chapterIndex: 1,
        blockIndex: 0,
        chapterTitle: 'Two',
        snippet: 'b',
        createdAt: DateTime(2026, 6, 2),
      ),
    );

    await BackupService().importAnnotations(annotations);
    final marks = await BookmarkStore().list(volume);
    expect(marks.map((m) => m.id).toSet(), {'1', '2'});
  });
}
