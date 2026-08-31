// A finished book comes back when its book gains chapters.
//
// A downloaded volume gets this for free: re-downloading re-reads the EPUB,
// and a changed chapter count clears the finished flag. A *streamed* volume
// is never downloaded, so nothing ever re-reads it — a book finished while
// streaming stayed finished for good, and the chapters that arrived
// afterwards could not bring it back to the Continue shelf. The only way to
// notice was to go and open it, which is the thing the shelf exists to save.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/test_db.dart';

Volume _volume() => Volume(
  seriesOpdsId: 7,
  title: 'A Book',
  fileName: 'book.epub',
  downloadUrl: 'http://host/book.epub',
  fileSizeBytes: 1000,
  updatedAt: DateTime.utc(2026, 5, 1),
);

Future<void> _finish(ReadingProgressStore store, Volume volume) =>
    store.save(
      volume,
      const ReadingProgress(
        chapterIndex: 29,
        blockIndex: 3,
        chapterCount: 30,
        endReached: true,
      ),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  test('a rebuild after finishing brings the book back', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    await _finish(store, volume);
    expect((await store.load(volume)).isFinished, isTrue);

    final changed = await store.unfinishIfRebuilt(
      volume, DateTime.now().add(const Duration(hours: 1)));

    expect(changed, isTrue);
    expect((await store.load(volume)).isFinished, isFalse);
  });

  test('a rebuild from before it was finished changes nothing', () async {
    // Finishing a book that was compiled last week is the ordinary case,
    // and must not put it straight back on the shelf.
    final store = ReadingProgressStore();
    final volume = _volume();
    await _finish(store, volume);

    final changed = await store.unfinishIfRebuilt(
      volume, DateTime.now().subtract(const Duration(days: 7)));

    expect(changed, isFalse);
    expect((await store.load(volume)).isFinished, isTrue);
  });

  test('it does not fight the reader for the shelf', () async {
    // Once revived, the row is stamped now — so the same rebuild timestamp
    // cannot revive it again on the next load. Without this it would
    // reappear every time the library refreshed, however often it was
    // dismissed.
    final store = ReadingProgressStore();
    final volume = _volume();
    await _finish(store, volume);
    final rebuiltAt = DateTime.now().add(const Duration(hours: 1));

    expect(await store.unfinishIfRebuilt(volume, rebuiltAt), isTrue);
    expect(await store.unfinishIfRebuilt(volume, rebuiltAt), isFalse);
  });

  test('an unfinished book is left alone', () async {
    final store = ReadingProgressStore();
    final volume = _volume();
    await store.save(
      volume,
      const ReadingProgress(chapterIndex: 4, blockIndex: 0, chapterCount: 30),
    );
    expect(
      await store.unfinishIfRebuilt(volume, DateTime.now()), isFalse);
  });

  test('a book with no saved position is left alone', () async {
    expect(
      await ReadingProgressStore().unfinishIfRebuilt(_volume(), DateTime.now()),
      isFalse,
    );
  });

  test('an unknown rebuild time changes nothing', () async {
    // A server that does not report one must not silently un-finish the
    // whole shelf.
    final store = ReadingProgressStore();
    final volume = _volume();
    await _finish(store, volume);
    expect(await store.unfinishIfRebuilt(volume, null), isFalse);
    expect((await store.load(volume)).isFinished, isTrue);
  });

  test('reviving keeps the reading position', () async {
    // It returns to the shelf where the reader left off, not at the start:
    // the new chapters are at the end, and the old ones are still read.
    final store = ReadingProgressStore();
    final volume = _volume();
    await _finish(store, volume);
    await store.unfinishIfRebuilt(
      volume, DateTime.now().add(const Duration(hours: 1)));
    final after = await store.load(volume);
    expect(after.chapterIndex, 29);
    expect(after.blockIndex, 3);
  });
}
