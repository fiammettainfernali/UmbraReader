// Tests for saved views — named library arrangements that can be returned
// to in one tap, and their cross-device sync.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/library_view.dart';
import 'package:umbra_reader/models/saved_view.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/saved_view_store.dart';

const _view = LibraryView(
  sort: LibrarySort.length,
  descending: true,
  readingState: ReadingStateFilter.unread,
  filters: LibraryFilters(genres: {'Cultivation'}, length: LengthBand.long),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => CloudSyncService().cancelPendingTimers());

  group('SavedView', () {
    test('round-trips through JSON with its arrangement intact', () {
      final saved = SavedView(
        id: 'v1',
        name: 'Unread cultivation',
        query: 'sect',
        view: _view,
        createdAt: DateTime(2026, 7, 31),
      );
      final back = SavedView.fromJson(saved.toJson())!;
      expect(back.id, 'v1');
      expect(back.name, 'Unread cultivation');
      expect(back.query, 'sect');
      expect(back.view.sort, LibrarySort.length);
      expect(back.view.descending, isTrue);
      expect(back.view.filters.length, LengthBand.long);
      expect(back.view.readingState, ReadingStateFilter.unread);
    });

    test('an entry with no id is rejected rather than half-built', () {
      expect(SavedView.fromJson({'name': 'No id'}), isNull);
      expect(SavedView.fromJson({'id': 'x'}), isNull);
    });

    test('summary describes what the view narrows by', () {
      final saved = SavedView(
        id: 'v1',
        name: 'x',
        query: 'sect',
        view: _view,
        createdAt: DateTime(2026, 7, 31),
      );
      expect(saved.summary, contains('sect'));
      expect(saved.summary, contains('Unread'));
      expect(saved.summary, contains('Cultivation'));
      expect(saved.summary, contains('Over 1000'));
      // `descending` selects the *second* of the sort's labelled
      // directions, which for Length is "Shortest first" — the base
      // comparator already runs longest-first. See LibraryView.descending.
      expect(saved.summary, contains('shortest first'));
    });

    test('a view that narrows nothing still says so', () {
      final saved = SavedView(
        id: 'v1',
        name: 'Everything',
        query: '',
        view: LibraryView.initial,
        createdAt: DateTime(2026, 7, 31),
      );
      expect(saved.summary, startsWith('Everything'));
    });
  });

  group('SavedViewStore', () {
    test('starts empty and stores what it is given', () async {
      final store = SavedViewStore();
      expect(await store.list(), isEmpty);

      await store.create('Unread cultivation', _view, query: 'sect');
      final all = await SavedViewStore().list();
      expect(all.length, 1);
      expect(all.single.name, 'Unread cultivation');
      expect(all.single.view.filters.genres, {'Cultivation'});
    });

    test('names and queries are trimmed', () async {
      final store = SavedViewStore();
      await store.create('  Spaced  ', _view, query: '  sect  ');
      final saved = (await store.list()).single;
      expect(saved.name, 'Spaced');
      expect(saved.query, 'sect');
    });

    test('each saved view gets a distinct id', () async {
      final store = SavedViewStore();
      await store.create('One', _view);
      await store.create('Two', _view);
      final all = await store.list();
      expect(all.map((v) => v.id).toSet().length, 2);
    });

    test('rename changes only the name', () async {
      final store = SavedViewStore();
      await store.create('Old', _view, query: 'sect');
      final id = (await store.list()).single.id;

      await store.rename(id, 'New');

      final saved = (await store.list()).single;
      expect(saved.name, 'New');
      expect(saved.query, 'sect', reason: 'the arrangement is untouched');
      expect(saved.id, id);
    });

    test('update replaces the arrangement but keeps id and name', () async {
      final store = SavedViewStore();
      await store.create('Mine', _view);
      final id = (await store.list()).single.id;

      await store.update(
        id,
        const LibraryView(sort: LibrarySort.author),
        query: 'other',
      );

      final saved = (await store.list()).single;
      expect(saved.id, id);
      expect(saved.name, 'Mine');
      expect(saved.view.sort, LibrarySort.author);
      expect(saved.query, 'other');
    });

    test('delete removes only the named view', () async {
      final store = SavedViewStore();
      await store.create('One', _view);
      await store.create('Two', _view);
      final first = (await store.list()).first;

      await store.delete(first.id);

      final left = await store.list();
      expect(left.length, 1);
      expect(left.single.name, 'Two');
    });

    test('corrupt storage reads as empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'saved_views': 'not json'});
      expect(await SavedViewStore().list(), isEmpty);
    });

    test('an entry that fails to parse is skipped, not fatal', () async {
      SharedPreferences.setMockInitialValues({
        'saved_views':
            '[{"name":"no id"},'
            '{"id":"ok","name":"Fine","view":{},"createdAt":""}]',
      });
      final all = await SavedViewStore().list();
      expect(all.length, 1);
      expect(all.single.name, 'Fine');
    });
  });

  group('SavedViewStore sync', () {
    test('an untouched install exports nothing', () async {
      // Exporting an empty set would let a fresh device wipe the views
      // already in the cloud.
      expect(await SavedViewStore().exportSyncBlob(), isEmpty);
    });

    test('a newer cloud set replaces the local one', () async {
      final store = SavedViewStore();
      await store.create('Local', _view);

      final blob =
          '{"modifiedAt":"${DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String()}",'
          '"views":[{"id":"r1","name":"Remote","query":"","view":{},'
          '"createdAt":"2026-07-31T00:00:00.000Z"}]}';

      expect(await store.mergeSyncBlob(blob), isTrue);
      final all = await store.list();
      expect(all.single.name, 'Remote');
    });

    test('an older cloud set is ignored', () async {
      final store = SavedViewStore();
      await store.create('Local', _view);

      const blob =
          '{"modifiedAt":"2020-01-01T00:00:00.000Z",'
          '"views":[{"id":"r1","name":"Remote","query":"","view":{},'
          '"createdAt":"2020-01-01T00:00:00.000Z"}]}';

      expect(await store.mergeSyncBlob(blob), isFalse);
      expect((await store.list()).single.name, 'Local');
    });

    test('a deletion propagates rather than resurrecting', () async {
      // Whole-set replacement is what makes this work: a per-view union
      // would bring the deleted entry back from the other device.
      final store = SavedViewStore();
      await store.create('Doomed', _view);

      final blob =
          '{"modifiedAt":"${DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String()}",'
          '"views":[]}';

      expect(await store.mergeSyncBlob(blob), isTrue);
      expect(await store.list(), isEmpty);
    });

    test('malformed blobs are ignored', () async {
      final store = SavedViewStore();
      await store.create('Local', _view);
      expect(await store.mergeSyncBlob(''), isFalse);
      expect(await store.mergeSyncBlob('{{{'), isFalse);
      expect(await store.mergeSyncBlob('{"views":[]}'), isFalse);
      expect((await store.list()).single.name, 'Local');
    });

    test('an exported set merges back as a no-op', () async {
      final store = SavedViewStore();
      await store.create('Local', _view);
      final exported = await store.exportSyncBlob();
      expect(await store.mergeSyncBlob(exported), isFalse);
    });
  });
}
