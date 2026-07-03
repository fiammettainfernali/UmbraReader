// Tests for ReadingProgressStore — the SQLite-backed store behind reading
// positions, the "Continue reading" shelf and reading stats. Tests that seed
// raw `reading_*:` SharedPreferences keys double as coverage for the
// one-time prefs → SQLite import.

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

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  test('save then load round-trips the reading position', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    await store.save(
      volume,
      const ReadingProgress(
        chapterIndex: 4,
        blockIndex: 12,
        chapterCount: 30,
      ),
    );

    final loaded = await store.load(volume);
    expect(loaded.chapterIndex, 4);
    expect(loaded.blockIndex, 12);
    expect(loaded.chapterCount, 30);
    expect(loaded.updatedAt, isNotNull);
  });

  test('load returns a zeroed position for an unknown volume', () async {
    final loaded = await ReadingProgressStore().load(_volume());
    expect(loaded.chapterIndex, 0);
    expect(loaded.blockIndex, 0);
    expect(loaded.chapterCount, 0);
  });

  test('endReached round-trips and drives isFinished', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    // On the last chapter but not at its end → not finished.
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 9, blockIndex: 3, chapterCount: 10),
    );
    expect((await store.load(volume)).isFinished, isFalse);
    // Reaching the end → finished.
    await store.save(
      volume,
      const ReadingProgress(
        chapterIndex: 9,
        blockIndex: 40,
        chapterCount: 10,
        endReached: true,
      ),
    );
    expect((await store.load(volume)).isFinished, isTrue);
  });

  test('reading a volume un-hides it from the Continue shelf', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 2, blockIndex: 0, chapterCount: 20),
    );
    await store.hideFromContinue(volume);
    expect(await store.hiddenFromContinue(), contains('1/book.epub'));
    // An actual read un-hides it again.
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 3, blockIndex: 0, chapterCount: 20),
    );
    expect(await store.hiddenFromContinue(), isEmpty);
  });

  test('a count refresh (unhide:false) keeps a hidden volume hidden', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 2, blockIndex: 0, chapterCount: 20),
    );
    await store.hideFromContinue(volume);
    // New chapters arrive → the background count refresh must not bring it
    // back to the Continue shelf.
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 2, blockIndex: 0, chapterCount: 25),
      unhide: false,
    );
    expect(await store.hiddenFromContinue(), contains('1/book.epub'));
  });

  test('legacy entries on the last chapter still count as finished', () async {
    // Simulate pre-endReached data: raw keys with no reading_end: flag.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reading_chapter:1/book.epub': 9,
      'reading_block:1/book.epub': 0,
      'reading_count:1/book.epub': 10,
      'reading_volume:1/book.epub':
          '{"seriesOpdsId":1,"title":"A Book","fileName":"book.epub",'
          '"downloadUrl":"http://host/book.epub","fileSizeBytes":1000}',
    });
    final loaded = await ReadingProgressStore().load(_volume());
    expect(loaded.isFinished, isTrue);
  });

  test('clear forgets the saved position', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 2, blockIndex: 1, chapterCount: 9),
    );
    await store.clear(volume);

    final loaded = await store.load(volume);
    expect(loaded.chapterIndex, 0);
    expect(loaded.blockIndex, 0);
    expect(await store.allEntries(), isEmpty);
  });

  test('allEntries returns every saved volume, newest first', () async {
    final store = ReadingProgressStore();
    final older = _volume(seriesId: 1, fileName: 'older.epub');
    final newer = _volume(seriesId: 2, fileName: 'newer.epub');

    await store.save(
      older,
      const ReadingProgress(chapterIndex: 1, blockIndex: 0, chapterCount: 5),
    );
    // A tiny gap so the second save has a strictly later timestamp.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.save(
      newer,
      const ReadingProgress(chapterIndex: 3, blockIndex: 0, chapterCount: 5),
    );

    final entries = await store.allEntries();
    expect(entries.length, 2);
    expect(entries.first.volume.fileName, 'newer.epub');
    expect(entries.last.volume.fileName, 'older.epub');
    expect(entries.first.progress.chapterIndex, 3);
  });

  test('allEntries skips legacy entries that have no volume snapshot', () async {
    // Simulate a position saved before volume snapshots were recorded.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reading_chapter:99/legacy.epub': 7,
      'reading_block:99/legacy.epub': 3,
    });
    expect(await ReadingProgressStore().allEntries(), isEmpty);
    // The bare position still loads for the reader itself.
    final loaded = await ReadingProgressStore().load(
      _volume(seriesId: 99, fileName: 'legacy.epub'),
    );
    expect(loaded.chapterIndex, 7);
  });

  test('finishing is sticky until the chapter count changes', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    // Read to the end.
    await store.save(
      volume,
      const ReadingProgress(
        chapterIndex: 9,
        blockIndex: 40,
        chapterCount: 10,
        endReached: true,
      ),
    );
    // Re-open and scroll around: position saves with endReached false must
    // NOT flip the book back to in-progress.
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 9, blockIndex: 2, chapterCount: 10),
    );
    expect((await store.load(volume)).isFinished, isTrue);
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 3, blockIndex: 0, chapterCount: 10),
    );
    expect(
      (await store.load(volume)).isFinished,
      isTrue,
      reason: 're-reading an earlier chapter does not unfinish the book',
    );
    // New chapters arrive (count grows): now there IS more to read.
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 9, blockIndex: 0, chapterCount: 12),
      unhide: false,
    );
    expect((await store.load(volume)).isFinished, isFalse);
  });

  test('markFinished sets endReached without moving the position', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 8, blockIndex: 5, chapterCount: 10),
    );
    await store.markFinished(volume);
    final progress = await store.load(volume);
    expect(progress.isFinished, isTrue);
    expect(progress.chapterIndex, 8);
    expect(progress.blockIndex, 5);
    expect(progress.chapterCount, 10);
  });

  test('prefs import carries over the hidden list and resume point', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reading_chapter:1/book.epub': 4,
      'continue_hidden': <String>['1/book.epub'],
      'tts_resume:1/book.epub': '12:87',
    });
    final store = ReadingProgressStore();
    expect(await store.hiddenFromContinue(), contains('1/book.epub'));
    expect(await store.resumeOffset(_volume()), (12, 87));
    // Import is non-destructive: the legacy keys stay behind.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('reading_chapter:1/book.epub'), 4);
  });

  test('resume offset round-trips and survives a position save', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    await store.saveResumeOffset(volume, 5, 120);
    expect(await store.resumeOffset(volume), (5, 120));
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 2, blockIndex: 5, chapterCount: 9),
    );
    expect(await store.resumeOffset(volume), (5, 120));
  });

  test('cloud merge is last-write-wins and keeps local shelf state', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 2, blockIndex: 0, chapterCount: 20),
    );
    await store.hideFromContinue(volume);

    // A newer cloud position must apply — without un-hiding the volume.
    final future = DateTime.now().add(const Duration(minutes: 5));
    final blob =
        '{"1/book.epub":{"chapterIndex":8,"blockIndex":1,"chapterCount":20,'
        '"updatedAt":"${future.toIso8601String()}","endReached":false,'
        '"volume":${'{"seriesOpdsId":1,"title":"A Book","fileName":"book.epub",'
            '"downloadUrl":"http://host/book.epub","fileSizeBytes":1000}'}}}';
    expect(await store.mergeSyncBlob(blob), isTrue);
    expect((await store.load(volume)).chapterIndex, 8);
    expect(await store.hiddenFromContinue(), contains('1/book.epub'));

    // An older cloud position must not clobber the local one.
    final past = DateTime.now().subtract(const Duration(days: 1));
    final stale = blob.replaceFirst(future.toIso8601String(), past.toIso8601String());
    expect(await store.mergeSyncBlob(stale), isFalse);
    expect((await store.load(volume)).chapterIndex, 8);
  });
}
