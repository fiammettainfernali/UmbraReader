// Tests for CollectionStore — user-defined library shelves.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/services/collection_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('list is empty on a fresh install', () async {
    expect(await CollectionStore().list(), isEmpty);
  });

  test('create then list round-trips, oldest first', () async {
    final store = CollectionStore();
    await store.create('Favourites');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.create('Later');
    final list = await store.list();
    expect(list, hasLength(2));
    expect(list.first.name, 'Favourites');
    expect(list.last.name, 'Later');
  });

  test('rename updates the name and keeps the id', () async {
    final store = CollectionStore();
    final c = await store.create('Old');
    await store.rename(c.id, 'New');
    final list = await store.list();
    expect(list.single.name, 'New');
    expect(list.single.id, c.id);
  });

  test('delete removes the collection', () async {
    final store = CollectionStore();
    final a = await store.create('A');
    await store.create('B');
    await store.delete(a.id);
    final list = await store.list();
    expect(list, hasLength(1));
    expect(list.single.name, 'B');
  });

  test('setMembership adds and removes a series', () async {
    final store = CollectionStore();
    final c = await store.create('Pile');
    await store.setMembership(c.id, 42, member: true);
    var list = await store.list();
    expect(list.single.seriesIds, [42]);

    await store.setMembership(c.id, 42, member: false);
    list = await store.list();
    expect(list.single.seriesIds, isEmpty);
  });

  test('setMembership is idempotent', () async {
    final store = CollectionStore();
    final c = await store.create('Pile');
    await store.setMembership(c.id, 1, member: true);
    await store.setMembership(c.id, 1, member: true);
    final list = await store.list();
    expect(list.single.seriesIds, [1]);
  });

  test('collectionsContaining returns every collection holding a series',
      () async {
    final store = CollectionStore();
    final a = await store.create('A');
    final b = await store.create('B');
    await store.create('C'); // does not contain the series
    await store.setMembership(a.id, 7, member: true);
    await store.setMembership(b.id, 7, member: true);
    final ids = await store.collectionsContaining(7);
    expect(ids, {a.id, b.id});
  });
}
