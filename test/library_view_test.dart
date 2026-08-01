// Tests for the persisted library arrangement — sort, direction, chip and
// filter set. Before this, every launch reset the view, so a library of
// several hundred series had to be re-narrowed from scratch each time.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/library_view.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/library_view_store.dart';

Series _series({
  int id = 1,
  String title = 'A Series',
  List<String> genres = const [],
  String status = 'ongoing',
}) => Series(
  opdsId: id,
  title: title,
  author: 'Someone',
  description: '',
  genres: genres,
  readingStatus: status,
  totalChapters: 10,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => CloudSyncService().cancelPendingTimers());

  group('LibraryView round-trip', () {
    test('survives encode and decode intact', () {
      const view = LibraryView(
        sort: LibrarySort.recentlyRead,
        descending: true,
        readingState: ReadingStateFilter.unread,
        filters: LibraryFilters(
          genres: {'Cultivation', 'Xianxia'},
          statuses: {'completed'},
          downloaded: true,
          multiVolume: false,
        ),
      );

      final back = LibraryView.fromJson(view.toJson());

      expect(back.sort, LibrarySort.recentlyRead);
      expect(back.descending, isTrue);
      expect(back.readingState, ReadingStateFilter.unread);
      expect(back.filters.genres, {'Cultivation', 'Xianxia'});
      expect(back.filters.statuses, {'completed'});
      expect(back.filters.downloaded, isTrue);
      expect(back.filters.multiVolume, isFalse);
    });

    test('an unknown sort name falls back rather than throwing', () {
      // A view written by a newer build must not brick an older one.
      final back = LibraryView.fromJson({'sort': 'sortByVibes'});
      expect(back.sort, LibrarySort.titleAsc);
      expect(back.readingState, ReadingStateFilter.any);
    });

    test('tri-state filters keep null distinct from false', () {
      const filters = LibraryFilters(downloaded: false);
      final back = LibraryFilters.fromJson(filters.toJson());
      expect(back.downloaded, isFalse, reason: 'false means "not downloaded"');
      expect(back.multiVolume, isNull, reason: 'null means "either"');
    });
  });

  group('LibraryFilters.activeCount', () {
    test('counts each active clause once, however many values it holds', () {
      expect(const LibraryFilters().activeCount, 0);
      expect(
        const LibraryFilters(genres: {'a', 'b', 'c'}).activeCount,
        1,
        reason: 'three genres are still one filter',
      );
      expect(
        const LibraryFilters(genres: {'a'}, downloaded: true).activeCount,
        2,
      );
    });

    test('a false tri-state counts as active', () {
      expect(const LibraryFilters(multiVolume: false).activeCount, 1);
    });
  });

  group('LibraryFilters.matches', () {
    test('a genre filter passes a series sharing any selected genre', () {
      const f = LibraryFilters(genres: {'Cultivation', 'LitRPG'});
      expect(
        f.matches(_series(genres: ['LitRPG', 'Action']), isDownloaded: false),
        isTrue,
      );
      expect(
        f.matches(_series(genres: ['Romance']), isDownloaded: false),
        isFalse,
      );
    });

    test('the downloaded filter distinguishes false from unset', () {
      expect(
        const LibraryFilters(downloaded: false)
            .matches(_series(), isDownloaded: true),
        isFalse,
      );
      expect(
        const LibraryFilters().matches(_series(), isDownloaded: true),
        isTrue,
      );
    });
  });

  group('LibraryViewStore', () {
    test('a fresh install gets the default arrangement', () async {
      final view = await LibraryViewStore().load();
      expect(view.sort, LibrarySort.titleAsc);
      expect(view.descending, isFalse);
      expect(view.filters.isEmpty, isTrue);
    });

    test('what was saved is what loads back', () async {
      final store = LibraryViewStore();
      await store.save(
        const LibraryView(
          sort: LibrarySort.author,
          descending: true,
          readingState: ReadingStateFilter.finished,
        ),
      );

      final back = await LibraryViewStore().load();
      expect(back.sort, LibrarySort.author);
      expect(back.descending, isTrue);
      expect(back.readingState, ReadingStateFilter.finished);
    });

    test('corrupt stored data falls back instead of throwing', () async {
      SharedPreferences.setMockInitialValues({'library_view': 'not json'});
      expect((await LibraryViewStore().load()).sort, LibrarySort.titleAsc);
    });
  });

  group('LibraryViewStore sync', () {
    test('a newer arrangement from the other device wins', () async {
      final store = LibraryViewStore();
      await store.save(const LibraryView(sort: LibrarySort.author));

      final blob =
          '{"view":{"sort":"recentlyRead","descending":true,'
          '"readingState":"any","filters":{}},'
          '"at":"${DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String()}"}';

      expect(await store.mergeSyncBlob(blob), isTrue);
      expect((await store.load()).sort, LibrarySort.recentlyRead);
    });

    test('an older arrangement does not overwrite a newer local one', () async {
      final store = LibraryViewStore();
      await store.save(const LibraryView(sort: LibrarySort.author));

      final blob =
          '{"view":{"sort":"recentlyRead","descending":false,'
          '"readingState":"any","filters":{}},"at":"2020-01-01T00:00:00.000Z"}';

      expect(await store.mergeSyncBlob(blob), isFalse);
      expect((await store.load()).sort, LibrarySort.author);
    });

    test('an identical arrangement reports no change', () async {
      // Otherwise two agreeing devices ping-pong a no-op merge forever.
      final store = LibraryViewStore();
      await store.save(const LibraryView(sort: LibrarySort.author));
      final exported = await store.exportSyncBlob();
      expect(await store.mergeSyncBlob(exported), isFalse);
    });

    test('a malformed or empty blob is ignored', () async {
      final store = LibraryViewStore();
      await store.save(const LibraryView(sort: LibrarySort.author));
      expect(await store.mergeSyncBlob(''), isFalse);
      expect(await store.mergeSyncBlob('{{{'), isFalse);
      expect(await store.mergeSyncBlob('{"view":{}}'), isFalse);
      expect((await store.load()).sort, LibrarySort.author);
    });

    test('nothing saved yet exports an empty blob, not a default view',
        () async {
      // Pushing a default would let a fresh install overwrite the real
      // arrangement already in the cloud.
      expect(await LibraryViewStore().exportSyncBlob(), isEmpty);
    });
  });

  group('sort direction labels', () {
    test('each sort names directions that make sense for it', () {
      expect(LibrarySort.titleAsc.directionLabels, ('A–Z', 'Z–A'));
      expect(
        LibrarySort.recentlyUpdated.directionLabels,
        ('Newest first', 'Oldest first'),
      );
    });
  });
}
