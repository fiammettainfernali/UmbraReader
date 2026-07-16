// Tests for GlossaryStore — per-series character/term notes, and the
// automatic "last seen in chapter N" tracking layered on top.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/services/glossary_store.dart';

const _series = 42;

GlossarySighting _at(int volume, int chapter, [String? label]) =>
    GlossarySighting(
      volume: volume,
      chapter: chapter,
      label: label ?? 'Chapter ${chapter + 1}',
    );

void main() {
  late GlossaryStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = GlossaryStore();
  });

  Future<GlossaryEntry> only() async => (await store.list(_series)).single;

  group('entries', () {
    test('list is empty on a fresh install', () async {
      expect(await store.list(_series), isEmpty);
    });

    test('create then list round-trips', () async {
      await store.create(_series, 'Zhang Wei', 'The protagonist');
      final e = await only();
      expect(e.term, 'Zhang Wei');
      expect(e.note, 'The protagonist');
      expect(e.lastSeen, isNull, reason: 'a new entry has not been seen yet');
    });

    test('glossaries are per-series', () async {
      await store.create(_series, 'Zhang Wei', '');
      expect(await store.list(_series + 1), isEmpty);
    });

    test('entries saved before sightings existed still load', () async {
      // Back-compat: pre-existing glossary JSON has no lastSeen key.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'glossary:$_series': jsonEncode([
          {'id': 'a', 'term': 'Zhang Wei', 'note': 'The protagonist'},
        ]),
      });
      final e = await only();
      expect(e.term, 'Zhang Wei');
      expect(e.lastSeen, isNull);
    });
  });

  group('noteSightings', () {
    test('records the chapter a term appears in', () async {
      await store.create(_series, 'Zhang Wei', '');
      final changed = await store.noteSightings(
        _series,
        'Then Zhang Wei drew his blade.',
        _at(1, 411, 'Chapter 412: The Duel'),
      );
      expect(changed, isTrue);
      expect((await only()).lastSeen?.label, 'Chapter 412: The Duel');
    });

    test('leaves terms that do not appear alone', () async {
      await store.create(_series, 'Zhang Wei', '');
      final changed = await store.noteSightings(
        _series,
        'The tavern was empty.',
        _at(1, 0),
      );
      expect(changed, isFalse);
      expect((await only()).lastSeen, isNull);
    });

    test('is a no-op when the glossary is empty', () async {
      expect(await store.noteSightings(_series, 'anything', _at(1, 0)), isFalse);
    });

    test('matches regardless of case', () async {
      await store.create(_series, 'zhang wei', '');
      await store.noteSightings(_series, 'ZHANG WEI arrived.', _at(1, 3));
      expect((await only()).lastSeen, isNotNull);
    });

    test('matches whole words only', () async {
      // The bug this guards: a short name matching inside a longer word,
      // reporting a sighting in every chapter containing "Also".
      await store.create(_series, 'Al', '');
      await store.noteSightings(_series, 'Also, the door was shut.', _at(1, 5));
      expect(
        (await only()).lastSeen,
        isNull,
        reason: '"Al" must not match inside "Also"',
      );

      await store.noteSightings(_series, 'Then Al spoke.', _at(1, 6));
      expect((await only()).lastSeen?.chapter, 6);
    });

    test('matches a term butting against punctuation', () async {
      await store.create(_series, 'Zhang Wei', '');
      await store.noteSightings(_series, '"Zhang Wei!" she cried.', _at(1, 8));
      expect((await only()).lastSeen?.chapter, 8);
    });

    test('updates only the terms actually mentioned', () async {
      await store.create(_series, 'Zhang Wei', '');
      await store.create(_series, 'Li Mei', '');
      await store.noteSightings(_series, 'Li Mei waited alone.', _at(1, 9));
      final byTerm = {for (final e in await store.list(_series)) e.term: e};
      expect(byTerm['Li Mei']!.lastSeen?.chapter, 9);
      expect(byTerm['Zhang Wei']!.lastSeen, isNull);
    });
  });

  group('sightings track the furthest point reached', () {
    test('a later chapter advances the sighting', () async {
      await store.create(_series, 'Zhang Wei', '');
      await store.noteSightings(_series, 'Zhang Wei.', _at(1, 10));
      await store.noteSightings(_series, 'Zhang Wei.', _at(1, 20));
      expect((await only()).lastSeen?.chapter, 20);
    });

    test('re-reading an earlier chapter does not rewind it', () async {
      // The point of the feature is "how long has it been since they turned
      // up?", so a re-read of chapter 5 must not overwrite chapter 489.
      await store.create(_series, 'Zhang Wei', '');
      await store.noteSightings(_series, 'Zhang Wei.', _at(1, 489));
      final changed = await store.noteSightings(
        _series,
        'Zhang Wei.',
        _at(1, 5),
      );
      expect(changed, isFalse, reason: 'nothing to write, so no write');
      expect((await only()).lastSeen?.chapter, 489);
    });

    test('a later volume outranks a higher chapter index', () async {
      // Chapter indices restart per volume, so volume 2 chapter 1 is further
      // along than volume 1 chapter 99.
      await store.create(_series, 'Zhang Wei', '');
      await store.noteSightings(_series, 'Zhang Wei.', _at(1, 99));
      await store.noteSightings(_series, 'Zhang Wei.', _at(2, 1, 'Chapter 2'));
      expect((await only()).lastSeen?.volume, 2);
      expect((await only()).lastSeen?.label, 'Chapter 2');
    });

    test('an earlier volume does not rewind it', () async {
      await store.create(_series, 'Zhang Wei', '');
      await store.noteSightings(_series, 'Zhang Wei.', _at(3, 1));
      await store.noteSightings(_series, 'Zhang Wei.', _at(2, 99));
      expect((await only()).lastSeen?.volume, 3);
    });

    test('sightings survive an edit to the note', () async {
      final e = await store.create(_series, 'Zhang Wei', 'old');
      await store.noteSightings(_series, 'Zhang Wei.', _at(1, 30));
      final seen = (await only()).lastSeen;
      await store.upsert(_series, e.copyWith(note: 'new', lastSeen: seen));
      final after = await only();
      expect(after.note, 'new');
      expect(after.lastSeen?.chapter, 30);
    });

    test('sightings persist across store instances', () async {
      await store.create(_series, 'Zhang Wei', '');
      await store.noteSightings(_series, 'Zhang Wei.', _at(1, 77, 'Ch. 78'));
      final reloaded = await GlossaryStore().list(_series);
      expect(reloaded.single.lastSeen?.label, 'Ch. 78');
      expect(reloaded.single.lastSeen?.chapter, 77);
    });
  });

  group('GlossarySighting.isAfter', () {
    test('anything beats never having been seen', () {
      expect(_at(0, 0).isAfter(null), isTrue);
    });

    test('the same spot is not after itself', () {
      expect(_at(1, 5).isAfter(_at(1, 5)), isFalse);
    });

    test('compares volume before chapter', () {
      expect(_at(2, 0).isAfter(_at(1, 500)), isTrue);
      expect(_at(1, 500).isAfter(_at(2, 0)), isFalse);
    });
  });
}
