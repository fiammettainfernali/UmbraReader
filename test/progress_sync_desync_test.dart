// Two devices, one library: the reported desyncs and why they happened.
//
// Chapters finished on the phone came back unread on the iPad, and books
// removed from Continue reading on the phone stayed on the iPad forever.
// Different bugs, both in how a reading-progress row crosses devices.
//
// 1. `updatedAt` was stamped on every write, not only when the position
//    moved. Opening a book, or a background pass refreshing the chapter
//    count, produced a row that outranked genuine reading done earlier
//    elsewhere — and the merge is last-write-wins on that field.
// 2. The merge wrote `endReached` straight from the blob, bypassing the
//    stickiness a local save applies, so a merge could un-finish a book.
// 3. The hidden flag was never exported or merged at all, so a removal had
//    no way to leave the device it happened on.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/volume.dart';
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

ReadingProgress _at(int chapter, {int block = 0, bool end = false, int count = 10}) =>
    ReadingProgress(
      chapterIndex: chapter,
      blockIndex: block,
      chapterCount: count,
      endReached: end,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  group('updatedAt means "the position moved"', () {
    test('re-saving the same position does not restamp it', () async {
      // Opening a book re-saves where it already was. Treating that as a
      // fresh write let the device that merely opened the book win the
      // merge against the device that actually read it.
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(3, block: 7));
      final first = (await store.load(_volume())).updatedAt;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.save(_volume(), _at(3, block: 7));

      expect((await store.load(_volume())).updatedAt, first);
    });

    test('a real move does restamp it', () async {
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(3));
      final first = (await store.load(_volume())).updatedAt;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.save(_volume(), _at(4));

      expect((await store.load(_volume())).updatedAt, isNot(first));
    });

    test('a background chapter-count refresh does not restamp it', () async {
      // The count changes after a re-download; the reader has not moved.
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(3, count: 10));
      final first = (await store.load(_volume())).updatedAt;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.save(_volume(), _at(3, count: 12), unhide: false);

      expect((await store.load(_volume())).updatedAt, first);
      expect((await store.load(_volume())).chapterCount, 12);
    });

    test('finishing restamps it even from the same position', () async {
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(9));
      final first = (await store.load(_volume())).updatedAt;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.save(_volume(), _at(9, end: true));

      expect((await store.load(_volume())).updatedAt, isNot(first));
    });
  });

  group('finishing survives a merge', () {
    test('an older blob cannot un-finish a book', () async {
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(9, end: true));

      // The other device says the same edition is unfinished, and says it
      // later — the exact shape of "I opened it on the iPad afterwards".
      final blob = _blobFor(
        key: '1/book.epub',
        chapterIndex: 0,
        chapterCount: 10,
        endReached: false,
        updatedAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await store.mergeSyncBlob(blob);

      expect(
        (await store.load(_volume())).endReached,
        isTrue,
        reason: 'a merge un-finished a book that was read to the end',
      );
    });

    test('new chapters do reopen it', () async {
      // The one thing that legitimately un-finishes a book: there is more
      // of it now.
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(9, end: true, count: 10));

      await store.mergeSyncBlob(_blobFor(
        key: '1/book.epub',
        chapterIndex: 9,
        chapterCount: 14,
        endReached: false,
        updatedAt: DateTime.now().add(const Duration(minutes: 5)),
      ));

      expect((await store.load(_volume())).endReached, isFalse);
    });
  });

  group('shelf removals travel', () {
    test('hiding is exported', () async {
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(2));
      await store.hideFromContinue(_volume());

      final blob = await store.exportSyncBlob();
      expect(blob, contains('"hidden":true'));
      expect(blob, contains('hiddenAt'));
    });

    test('a removal on the other device arrives', () async {
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(2));
      expect(await store.hiddenFromContinue(), isEmpty);

      await store.mergeSyncBlob(_blobFor(
        key: '1/book.epub',
        chapterIndex: 2,
        chapterCount: 10,
        updatedAt: DateTime.now(),
        hidden: true,
        hiddenAt: DateTime.now(),
      ));

      expect(await store.hiddenFromContinue(), contains('1/book.epub'));
    });

    test('an older removal does not undo a newer un-hide', () async {
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(2));
      await store.hideFromContinue(_volume());
      // Reading it again puts it back on the shelf, here and everywhere.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.save(_volume(), _at(3));
      expect(await store.hiddenFromContinue(), isEmpty);

      await store.mergeSyncBlob(_blobFor(
        key: '1/book.epub',
        chapterIndex: 2,
        chapterCount: 10,
        updatedAt: DateTime.now(),
        hidden: true,
        hiddenAt: DateTime.now().subtract(const Duration(hours: 1)),
      ));

      expect(
        await store.hiddenFromContinue(),
        isEmpty,
        reason: 'a stale removal came back and hid the book again',
      );
    });

    test('a position merge alone never changes shelf state', () async {
      // The old merge deliberately skipped the hidden column to protect it.
      // Now that shelf state syncs, it must still only move on its own
      // clock — a blob with no hiddenAt says nothing about the shelf.
      final store = ReadingProgressStore();
      await store.save(_volume(), _at(2));
      await store.hideFromContinue(_volume());

      await store.mergeSyncBlob(_blobFor(
        key: '1/book.epub',
        chapterIndex: 5,
        chapterCount: 10,
        updatedAt: DateTime.now().add(const Duration(minutes: 5)),
      ));

      expect(await store.hiddenFromContinue(), contains('1/book.epub'));
      expect((await store.load(_volume())).chapterIndex, 5);
    });
  });
}

/// One-entry sync blob, shaped exactly like [exportSyncBlob] writes them.
String _blobFor({
  required String key,
  required int chapterIndex,
  required int chapterCount,
  required DateTime updatedAt,
  bool endReached = false,
  bool hidden = false,
  DateTime? hiddenAt,
}) {
  final volume = _volume().toJson();
  final entry = <String, dynamic>{
    'chapterIndex': chapterIndex,
    'blockIndex': 0,
    'chapterCount': chapterCount,
    'updatedAt': updatedAt.toIso8601String(),
    'endReached': endReached,
    'volume': volume,
    'hidden': hidden,
    if (hiddenAt != null) 'hiddenAt': hiddenAt.toIso8601String(),
  };
  return jsonEncode({key: entry});
}

