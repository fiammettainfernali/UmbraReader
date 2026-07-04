// Library-wide annotations → Markdown export.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/bookmark.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/annotations_export.dart';
import 'package:umbra_reader/services/bookmark_store.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/test_db.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

Volume _volume(int seriesId, String title) => Volume(
  seriesOpdsId: seriesId,
  title: title,
  fileName: '$title.epub',
  downloadUrl: '',
  fileSizeBytes: 0,
  updatedAt: null,
);

Bookmark _mark({
  required String id,
  required int chapter,
  required String chapterTitle,
  required String snippet,
  bool highlight = false,
  String note = '',
}) => Bookmark(
  id: id,
  chapterIndex: chapter,
  blockIndex: int.parse(id),
  chapterTitle: chapterTitle,
  snippet: snippet,
  createdAt: DateTime(2026, 6, 1),
  isHighlight: highlight,
  note: note,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    tempDir = Directory.systemTemp.createTempSync('umbra_export');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.reset();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // harmless on Windows
    }
  });

  test('markdown groups by book and chapter, in reading order', () async {
    final zebra = _volume(1, 'Zebra Tales');
    final apple = _volume(2, 'Apple Chronicle');
    // Progress entries provide the volume snapshots (and titles).
    for (final v in [zebra, apple]) {
      await ReadingProgressStore().save(
        v,
        const ReadingProgress(chapterIndex: 1, blockIndex: 0, chapterCount: 5),
      );
    }
    await BookmarkStore().add(
      zebra,
      _mark(
        id: '2',
        chapter: 1,
        chapterTitle: 'Z Ch2',
        snippet: 'zebra second',
        highlight: true,
        note: 'love this line\nsecond line',
      ),
    );
    await BookmarkStore().add(
      zebra,
      _mark(id: '1', chapter: 0, chapterTitle: 'Z Ch1', snippet: 'zebra first'),
    );
    await BookmarkStore().add(
      apple,
      _mark(id: '3', chapter: 0, chapterTitle: 'A Ch1', snippet: 'apple one'),
    );

    final md = await AnnotationsExport().markdown();
    // Books alphabetical: Apple before Zebra.
    expect(
      md.indexOf('## Apple Chronicle'),
      lessThan(md.indexOf('## Zebra Tales')),
    );
    // Within a book, reading order: Ch1 before Ch2.
    expect(md.indexOf('### Z Ch1'), lessThan(md.indexOf('### Z Ch2')));
    expect(md, contains('**Highlight** — zebra second'));
    expect(md, contains('**Bookmark** — zebra first'));
    // Multi-line note becomes a blockquote.
    expect(md, contains('> love this line'));
    expect(md, contains('> second line'));
  });

  test('exportToFile writes a shareable .md; null when empty', () async {
    expect(await AnnotationsExport().exportToFile(), isNull);

    final volume = _volume(1, 'Solo');
    await ReadingProgressStore().save(
      volume,
      const ReadingProgress(chapterIndex: 1, blockIndex: 0, chapterCount: 3),
    );
    await BookmarkStore().add(
      volume,
      _mark(id: '9', chapter: 0, chapterTitle: 'One', snippet: 'a snippet'),
    );
    final file = await AnnotationsExport().exportToFile();
    expect(file, isNotNull);
    expect(file!.path, endsWith('.md'));
    expect(file.readAsStringSync(), contains('a snippet'));
  });
}
