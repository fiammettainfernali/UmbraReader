// Tests for BookmarkStore — per-volume saved spots.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/bookmark.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/bookmark_store.dart';

Volume _volume({String fileName = 'book.epub', int seriesId = 1}) => Volume(
  seriesOpdsId: seriesId,
  title: 'A Book',
  fileName: fileName,
  downloadUrl: 'http://host/$fileName',
  fileSizeBytes: 0,
  updatedAt: null,
);

Bookmark _mark({
  required String id,
  int chapter = 0,
  int block = 0,
}) => Bookmark(
  id: id,
  chapterIndex: chapter,
  blockIndex: block,
  chapterTitle: 'Chapter ${chapter + 1}',
  snippet: 'Snippet for $id',
  createdAt: DateTime.utc(2026, 5, 1).add(Duration(milliseconds: int.parse(id))),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('list returns nothing for a fresh volume', () async {
    expect(await BookmarkStore().list(_volume()), isEmpty);
  });

  test('add then list round-trips the bookmark', () async {
    final store = BookmarkStore();
    final volume = _volume();
    await store.add(volume, _mark(id: '1', chapter: 2, block: 5));
    final got = await store.list(volume);
    expect(got, hasLength(1));
    expect(got.first.id, '1');
    expect(got.first.chapterIndex, 2);
    expect(got.first.blockIndex, 5);
  });

  test('add multiple sorts newest-first', () async {
    final store = BookmarkStore();
    final volume = _volume();
    await store.add(volume, _mark(id: '1'));
    await store.add(volume, _mark(id: '2'));
    await store.add(volume, _mark(id: '3'));
    final got = await store.list(volume);
    expect(got.map((m) => m.id).toList(), ['3', '2', '1']);
  });

  test('add is idempotent on id', () async {
    final store = BookmarkStore();
    final volume = _volume();
    await store.add(volume, _mark(id: '1', chapter: 0));
    await store.add(volume, _mark(id: '1', chapter: 7));
    final got = await store.list(volume);
    expect(got, hasLength(1));
    expect(got.first.chapterIndex, 7);
  });

  test('remove deletes by id', () async {
    final store = BookmarkStore();
    final volume = _volume();
    await store.add(volume, _mark(id: '1'));
    await store.add(volume, _mark(id: '2'));
    await store.remove(volume, '1');
    final got = await store.list(volume);
    expect(got, hasLength(1));
    expect(got.first.id, '2');
  });

  test('bookmarks are scoped per volume', () async {
    final store = BookmarkStore();
    final a = _volume(fileName: 'a.epub');
    final b = _volume(fileName: 'b.epub');
    await store.add(a, _mark(id: '1'));
    expect(await store.list(a), hasLength(1));
    expect(await store.list(b), isEmpty);
  });

  test('clear empties the bookmark list', () async {
    final store = BookmarkStore();
    final volume = _volume();
    await store.add(volume, _mark(id: '1'));
    await store.clear(volume);
    expect(await store.list(volume), isEmpty);
  });
}
