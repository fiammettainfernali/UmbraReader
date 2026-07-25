// Deleting a glossary entry or a highlight used to be one tap with no
// confirm, no undo and no way back — while deleting a *collection*, which is
// rebuildable in seconds, asked for confirmation. Both are hand-authored and
// both now sync, so a mis-tap propagated everywhere.
//
// These check the restore path itself: that undoing puts back what was
// deleted, intact.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/bookmark.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/bookmark_store.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/glossary_store.dart';

import 'helpers/test_db.dart';

const _series = 42;

Volume _volume() => Volume(
  seriesOpdsId: _series,
  title: 'Saga Vol 1',
  fileName: 'saga-v1.epub',
  downloadUrl: 'http://unused/x.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(() {
    CloudSyncService().cancelPendingTimers();
    return AppDatabase.reset();
  });

  test('undoing a highlight delete restores it exactly', () async {
    final store = BookmarkStore();
    final mark = Bookmark(
      id: 'h1',
      chapterIndex: 4,
      blockIndex: 9,
      chapterTitle: 'Chapter 5',
      snippet: 'a passage',
      createdAt: DateTime.utc(2026, 7, 1),
      isHighlight: true,
      note: 'the elder is the traitor',
      color: HighlightColor.blue,
      startChar: 10,
      endChar: 30,
      selectedText: 'the sect elder smiled',
    );
    await store.add(_volume(), mark);

    await store.remove(_volume(), mark.id);
    expect(await store.list(_volume()), isEmpty);

    // What the undo action does.
    await store.add(_volume(), mark);

    final back = (await store.list(_volume())).single;
    expect(back.id, 'h1');
    expect(back.isHighlight, isTrue);
    expect(back.note, 'the elder is the traitor');
    expect(back.color, HighlightColor.blue);
    expect(back.selectedText, 'the sect elder smiled');
    expect(back.startChar, 10, reason: 'the range survives the round trip');
    expect(back.endChar, 30);
  });

  test('undoing a glossary delete restores the term, note and sighting',
      () async {
    final store = GlossaryStore();
    await store.create(_series, 'Zhang Wei', 'The protagonist');
    await store.noteSightings(
      _series,
      'Zhang Wei drew his blade.',
      const GlossarySighting(
        volume: 2,
        chapter: 488,
        label: 'Chapter 489',
      ),
    );
    final before = (await store.list(_series)).single;
    expect(before.lastSeen?.chapter, 488);

    await store.remove(_series, before.id);
    expect(await store.list(_series), isEmpty);

    // What the undo action does.
    await store.upsert(_series, before);

    final back = (await store.list(_series)).single;
    expect(back.id, before.id, reason: 'the same entry, not a new one');
    expect(back.term, 'Zhang Wei');
    expect(back.note, 'The protagonist');
    expect(
      back.lastSeen?.chapter,
      488,
      reason: 'sightings accumulate over a long read and must come back too',
    );
    expect(back.lastSeen?.volume, 2);
  });

  test('restoring does not duplicate the entry', () async {
    final store = GlossaryStore();
    final entry = await store.create(_series, 'Li Mei', '');
    await store.remove(_series, entry.id);
    await store.upsert(_series, entry);
    await store.upsert(_series, entry); // a double-tap on Undo
    expect(await store.list(_series), hasLength(1));
  });
}
