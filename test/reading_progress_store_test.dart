// Tests for ReadingProgressStore — the SharedPreferences-backed store behind
// reading positions, the "Continue reading" shelf and reading stats.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

Volume _volume({int seriesId = 1, String fileName = 'book.epub'}) => Volume(
  seriesOpdsId: seriesId,
  title: 'A Book',
  fileName: fileName,
  downloadUrl: 'http://host/$fileName',
  fileSizeBytes: 1000,
  updatedAt: DateTime.utc(2026, 5, 1),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

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
}
