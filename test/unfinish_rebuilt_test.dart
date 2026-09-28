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

Future<void> _finish(ReadingProgressStore store, Volume volume) => store.save(
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
      volume,
      DateTime.now().add(const Duration(hours: 1)),
    );

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
      volume,
      DateTime.now().subtract(const Duration(days: 7)),
    );

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
    expect(await store.unfinishIfRebuilt(volume, DateTime.now()), isFalse);
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

  group('which volume was rebuilt', () {
    // The evidence question, kept apart from the act. The caller used to
    // answer it with the SERIES timestamp, so a new chapter in volume twelve
    // marked every finished volume of that series as rebuilt and dumped the
    // lot back onto the Continue shelf. For a long series that is most of
    // the shelf, arriving unasked, one dismissal each to clear.
    Volume vol(int n, {required int size, required DateTime at}) => Volume(
      seriesOpdsId: 7,
      title: 'Volume $n',
      fileName: 'v$n.epub',
      downloadUrl: 'http://host/v$n.epub',
      fileSizeBytes: size,
      updatedAt: at,
    );

    ReadingEntry finishedEntry(Volume volume) => ReadingEntry(
      volume: volume,
      progress: const ReadingProgress(
        chapterIndex: 29,
        blockIndex: 3,
        chapterCount: 30,
        endReached: true,
      ),
    );

    final oldVolume = vol(1, size: 1000, at: DateTime.utc(2026, 1, 1));
    final grownVolume = vol(12, size: 2000, at: DateTime.utc(2026, 9, 20));

    test('a new chapter in volume twelve leaves volume one finished', () {
      // The reported bug, in one assertion.
      final current = [
        oldVolume, // untouched: same size, same mtime
        vol(12, size: 2400, at: DateTime.utc(2026, 9, 27)), // grew today
      ];

      expect(
        ReadingProgressStore.volumeRebuiltAt(finishedEntry(oldVolume), current),
        isNull,
      );
    });

    test('the volume that actually grew does come back', () {
      final current = [
        oldVolume,
        vol(12, size: 2400, at: DateTime.utc(2026, 9, 27)),
      ];

      expect(
        ReadingProgressStore.volumeRebuiltAt(
          finishedEntry(grownVolume),
          current,
        ),
        DateTime.utc(2026, 9, 27),
      );
    });

    test('a rebuild that added nothing is not a reason to come back', () {
      // Re-rendered with a new cover: newer, and not one word longer.
      final current = [vol(1, size: 1000, at: DateTime.utc(2026, 9, 27))];

      expect(
        ReadingProgressStore.volumeRebuiltAt(finishedEntry(oldVolume), current),
        isNull,
      );
    });

    test('a volume the cache has never seen is left alone', () {
      expect(
        ReadingProgressStore.volumeRebuiltAt(finishedEntry(oldVolume), null),
        isNull,
      );
      expect(
        ReadingProgressStore.volumeRebuiltAt(finishedEntry(oldVolume), [
          grownVolume,
        ]),
        isNull,
        reason: 'a different volume of the same series says nothing',
      );
    });

    test('a legacy entry with no recorded size falls back to the date', () {
      final legacy = ReadingEntry(
        volume: vol(1, size: 0, at: DateTime.utc(2026, 1, 1)),
        progress: const ReadingProgress(
          chapterIndex: 29,
          blockIndex: 3,
          chapterCount: 30,
          endReached: true,
        ),
      );

      expect(
        ReadingProgressStore.volumeRebuiltAt(legacy, [
          vol(1, size: 1000, at: DateTime.utc(2026, 9, 27)),
        ]),
        DateTime.utc(2026, 9, 27),
      );
    });
  });

  group('tidying up what the old revival left behind', () {
    // Fixing the cause does not put back the flags it already took off, so
    // the shelf stays cluttered with books finished months ago. Nothing
    // recorded that they were finished, so the repair matches the shape the
    // bug left: read to the last chapter, no growth, several volumes of one
    // series at once.
    Volume vol(int n, {int size = 1000}) => Volume(
      seriesOpdsId: 7,
      title: 'Volume $n',
      fileName: 'v$n.epub',
      downloadUrl: 'http://host/v$n.epub',
      fileSizeBytes: size,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    /// A volume read to its last chapter but not marked finished — exactly
    /// what a revived row looks like.
    Future<void> atLastChapter(ReadingProgressStore store, Volume volume) =>
        store.save(
          volume,
          const ReadingProgress(
            chapterIndex: 29,
            blockIndex: 3,
            chapterCount: 30,
          ),
        );

    test('a series worth of revived volumes comes back finished', () async {
      final store = ReadingProgressStore();
      for (final n in [1, 2, 3]) {
        await atLastChapter(store, vol(n));
      }

      final restored = await store.tidyRevivedVolumes(
        await store.allEntries(),
        (_) => null,
      );

      expect(restored, 3);
      for (final n in [1, 2, 3]) {
        expect((await store.load(vol(n))).isFinished, isTrue);
      }
    });

    test('one book stopped in its final chapter is left alone', () async {
      // The case this could get wrong. Someone genuinely mid-way through a
      // last chapter looks identical to a revived volume, so a lone match
      // is not treated as evidence of anything.
      final store = ReadingProgressStore();
      await atLastChapter(store, vol(1));

      expect(
        await store.tidyRevivedVolumes(await store.allEntries(), (_) => null),
        0,
      );
      expect((await store.load(vol(1))).isFinished, isFalse);
    });

    test('a volume that really grew stays on the shelf', () async {
      final store = ReadingProgressStore();
      for (final n in [1, 2, 3]) {
        await atLastChapter(store, vol(n));
      }

      // Volume 3 is bigger and newer than when it was read: it has genuinely
      // gained chapters and belongs on the Continue shelf.
      final restored = await store.tidyRevivedVolumes(
        await store.allEntries(),
        (_) => [
          vol(1),
          vol(2),
          Volume(
            seriesOpdsId: 7,
            title: 'Volume 3',
            fileName: 'v3.epub',
            downloadUrl: 'http://host/v3.epub',
            fileSizeBytes: 5000,
            updatedAt: DateTime.utc(2026, 9, 27),
          ),
        ],
      );

      expect(restored, 2);
      expect((await store.load(vol(3))).isFinished, isFalse);
      expect((await store.load(vol(1))).isFinished, isTrue);
    });

    test('a book being read in the middle is never touched', () async {
      final store = ReadingProgressStore();
      for (final n in [1, 2]) {
        await store.save(
          vol(n),
          const ReadingProgress(
            chapterIndex: 8,
            blockIndex: 1,
            chapterCount: 30,
          ),
        );
      }

      expect(
        await store.tidyRevivedVolumes(await store.allEntries(), (_) => null),
        0,
      );
      expect((await store.load(vol(1))).isFinished, isFalse);
    });

    test('it happens once and never again', () async {
      final store = ReadingProgressStore();
      for (final n in [1, 2]) {
        await atLastChapter(store, vol(n));
      }
      expect(
        await store.tidyRevivedVolumes(await store.allEntries(), (_) => null),
        2,
      );

      // A later re-read left at the last chapter is the reader's business,
      // not the repair's.
      for (final n in [1, 2]) {
        await atLastChapter(store, vol(n));
      }
      expect(
        await store.tidyRevivedVolumes(await store.allEntries(), (_) => null),
        0,
      );
    });
  });

  test('reviving keeps the reading position', () async {
    // It returns to the shelf where the reader left off, not at the start:
    // the new chapters are at the end, and the old ones are still read.
    final store = ReadingProgressStore();
    final volume = _volume();
    await _finish(store, volume);
    await store.unfinishIfRebuilt(
      volume,
      DateTime.now().add(const Duration(hours: 1)),
    );
    final after = await store.load(volume);
    expect(after.chapterIndex, 29);
    expect(after.blockIndex, 3);
  });
}
