// Sync coverage for the three stores that shipped after CloudSyncService was
// built and never got wired into it: manual series status (which feeds the
// recommendation engine), per-series glossaries, and custom themes.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/reader_theme.dart';
import 'package:umbra_reader/services/custom_theme_store.dart';
import 'package:umbra_reader/services/glossary_store.dart';
import 'package:umbra_reader/services/series_status_store.dart';

const _series = 42;

GlossarySighting _at(int volume, int chapter) => GlossarySighting(
  volume: volume,
  chapter: chapter,
  label: 'Chapter ${chapter + 1}',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('series status', () {
    test('a status set on one device arrives on the other', () async {
      final phone = SeriesStatusStore();
      await phone.setStatus(7, SeriesStatus.caughtUp);
      final blob = await phone.exportSyncBlob();

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ipad = SeriesStatusStore();
      expect(await ipad.statusFor(7), SeriesStatus.none);
      expect(await ipad.mergeSyncBlob(blob), isTrue);
      expect(
        await ipad.statusFor(7),
        SeriesStatus.caughtUp,
        reason: 'binge-marking on one device must teach the other',
      );
    });

    test('the newer status wins regardless of merge direction', () async {
      // Phone says dropped (older); iPad says caught up (newer).
      final store = SeriesStatusStore();
      await store.setStatus(7, SeriesStatus.dropped);
      final older = await store.exportSyncBlob();

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final newer = SeriesStatusStore();
      await newer.setStatus(7, SeriesStatus.caughtUp);

      // Merging the OLDER blob in must not clobber the newer local value.
      expect(await newer.mergeSyncBlob(older), isFalse);
      expect(await newer.statusFor(7), SeriesStatus.caughtUp);
    });

    test('a clear is not undone by the other device\'s stale status', () async {
      // The tombstone case: without it, dropping the key would let the other
      // device's older "caught up" win the next merge and the clear would
      // silently bounce back.
      final store = SeriesStatusStore();
      await store.setStatus(7, SeriesStatus.caughtUp);
      final stale = await store.exportSyncBlob();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.setStatus(7, SeriesStatus.none);

      expect(await store.mergeSyncBlob(stale), isFalse);
      expect(await store.statusFor(7), SeriesStatus.none);
    });

    test('a clear propagates to the other device', () async {
      // Device B marks it caught up first…
      final b = SeriesStatusStore();
      await b.setStatus(7, SeriesStatus.caughtUp);
      final bBlob = await b.exportSyncBlob();

      // …then device A clears it later, so the clear is the newer write.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final a = SeriesStatusStore();
      await a.setStatus(7, SeriesStatus.none);
      final clearBlob = await a.exportSyncBlob();

      // Back on B: it still shows caught up, then A's clear lands.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final bAgain = SeriesStatusStore();
      await bAgain.mergeSyncBlob(bBlob);
      expect(await bAgain.statusFor(7), SeriesStatus.caughtUp);

      expect(await bAgain.mergeSyncBlob(clearBlob), isTrue);
      expect(await bAgain.statusFor(7), SeriesStatus.none);
    });

    test('legacy un-timestamped entries still load and lose to edits', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'series_status': '{"7":"reading"}',
      });
      final store = SeriesStatusStore();
      expect(await store.statusFor(7), SeriesStatus.reading);

      // A timestamped remote beats the legacy bare value.
      final remote = SeriesStatusStore();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await remote.setStatus(7, SeriesStatus.caughtUp);
      final blob = await remote.exportSyncBlob();

      SharedPreferences.setMockInitialValues(<String, Object>{
        'series_status': '{"7":"reading"}',
      });
      final legacy = SeriesStatusStore();
      expect(await legacy.mergeSyncBlob(blob), isTrue);
      expect(await legacy.statusFor(7), SeriesStatus.caughtUp);
    });
  });

  group('glossary', () {
    test('terms union across devices', () async {
      final phone = GlossaryStore();
      await phone.create(_series, 'Zhang Wei', 'The protagonist');
      final blob = await phone.exportSyncBlob();

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ipad = GlossaryStore();
      await ipad.create(_series, 'Li Mei', 'The rival');
      expect(await ipad.mergeSyncBlob(blob), isTrue);

      final terms = (await ipad.list(_series)).map((e) => e.term).toList();
      expect(terms, containsAll(['Zhang Wei', 'Li Mei']));
    });

    test('a sighting never rewinds when merged', () async {
      // The monotonic rule has to survive sync: reading ahead on the iPad
      // must not be undone by the phone's older "last seen".
      final phone = GlossaryStore();
      final entry = await phone.create(_series, 'Zhang Wei', '');
      await phone.noteSightings(_series, 'Zhang Wei.', _at(1, 10));
      final older = await phone.exportSyncBlob();

      await phone.noteSightings(_series, 'Zhang Wei.', _at(1, 400));
      expect((await phone.list(_series)).single.lastSeen?.chapter, 400);

      await phone.mergeSyncBlob(older);
      expect(
        (await phone.list(_series)).single.lastSeen?.chapter,
        400,
        reason: 'an older sighting must not rewind the furthest point',
      );
      expect((await phone.list(_series)).single.id, entry.id);
    });

    test('a newer note edit wins on the same entry', () async {
      final phone = GlossaryStore();
      final entry = await phone.create(_series, 'Zhang Wei', 'old note');
      final stale = await phone.exportSyncBlob();

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await phone.upsert(_series, entry.copyWith(note: 'new note'));

      // Merging the stale copy must not resurrect the old note.
      await phone.mergeSyncBlob(stale);
      expect((await phone.list(_series)).single.note, 'new note');
    });

    test('entries saved before sync existed still merge', () async {
      // No updatedAt on the local entry; the remote edit should win.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'glossary:$_series':
            '[{"id":"a","term":"Zhang Wei","note":"legacy"}]',
      });
      final store = GlossaryStore();
      final remote = GlossaryStore();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await remote.upsert(
        _series,
        const GlossaryEntry(id: 'a', term: 'Zhang Wei', note: 'updated'),
      );
      final blob = await remote.exportSyncBlob();

      SharedPreferences.setMockInitialValues(<String, Object>{
        'glossary:$_series':
            '[{"id":"a","term":"Zhang Wei","note":"legacy"}]',
      });
      expect(await store.mergeSyncBlob(blob), isTrue);
      expect((await store.list(_series)).single.note, 'updated');
    });
  });

  group('custom themes', () {
    test('a theme made on one device arrives on the other', () async {
      const theme = ReaderThemePreset(
        id: 'custom-1',
        name: 'Midnight',
        background: Color(0xFF101018),
        text: Color(0xFFD8D8E0),
        secondary: Color(0xFF8A8A96),
        highlight: Color(0xFF303048),
      );
      final phone = CustomThemeStore();
      await phone.save(theme);
      final blob = await phone.exportSyncBlob();

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ipad = CustomThemeStore();
      await ipad.initialize();
      expect(CustomThemeStore.customs, isEmpty);

      expect(await ipad.mergeSyncBlob(blob), isTrue);
      expect(CustomThemeStore.customs.single.name, 'Midnight');
      // And the reader can resolve it by id, which is what actually matters.
      expect(readerThemeById('custom-1').name, 'Midnight');
    });

    test('merging the same themes twice changes nothing', () async {
      const theme = ReaderThemePreset(
        id: 'custom-1',
        name: 'Midnight',
        background: Color(0xFF101018),
        text: Color(0xFFD8D8E0),
        secondary: Color(0xFF8A8A96),
        highlight: Color(0xFF303048),
      );
      final store = CustomThemeStore();
      await store.save(theme);
      final blob = await store.exportSyncBlob();
      expect(
        await store.mergeSyncBlob(blob),
        isFalse,
        reason: 'an idempotent merge must not report a change (it would loop)',
      );
    });
  });
}
