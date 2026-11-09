// Bringing a book up to date as it opens, and the book always opening anyway.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/download_record.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/library_home.dart';
import 'package:umbra_reader/services/book_freshener.dart';
import 'package:umbra_reader/services/download_service.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

final _then = DateTime(2026, 11, 1);
final _later = DateTime(2026, 11, 3);

Volume _volume({String file = 'book.epub', DateTime? at, int size = 100}) =>
    Volume(
      seriesOpdsId: 1,
      title: file,
      fileName: file,
      downloadUrl: 'http://server/$file',
      fileSizeBytes: size,
      updatedAt: at ?? _then,
    );

DownloadRecord _record({DateTime? at, int size = 100}) => DownloadRecord(
  fileName: 'book.epub',
  sizeBytes: size,
  downloadedAt: _then,
  volumeUpdatedAt: at ?? _then,
  etag: null,
);

void main() {
  group('bringing a book up to date', () {
    late List<Volume> downloaded;

    BookFreshener freshener({
      DownloadRecord? record,
      Future<List<Volume>> Function(int)? feed,
      Future<void> Function(Volume, void Function(double))? download,
      Duration checkTimeout = const Duration(seconds: 8),
    }) => BookFreshener(
      fetchVolumes: feed ?? (_) async => [_volume(at: _later, size: 200)],
      recordFor: (_) => record,
      checkTimeout: checkTimeout,
      download:
          download ??
          (volume, onProgress) async {
            downloaded.add(volume);
            onProgress(1);
          },
    );

    setUp(() => downloaded = []);

    test('downloads a changed book and opens the new copy', () async {
      final progress = <double>[];
      final outcome = await freshener(
        record: _record(),
      ).run(_volume(), onProgress: progress.add);
      expect(downloaded.single.updatedAt, _later);
      expect(outcome.updated, isTrue);
      expect(outcome.volume.fileSizeBytes, 200);
      expect(outcome.note, isNull);
      expect(progress, [1]);
    });

    test('leaves an unchanged book alone', () async {
      final outcome = await freshener(
        record: _record(),
        feed: (_) async => [_volume()],
      ).run(_volume(), onProgress: (_) {});
      expect(downloaded, isEmpty);
      expect(outcome.updated, isFalse);
      expect(outcome.note, isNull);
    });

    test('a book read from the server has nothing to update', () async {
      var asked = false;
      final outcome = await freshener(
        feed: (_) async {
          asked = true;
          return const [];
        },
      ).run(_volume(), onProgress: (_) {});
      expect(asked, isFalse);
      expect(outcome.note, isNull);
    });

    test('new chapters in a later volume leave this one as it is', () async {
      final outcome = await freshener(
        record: _record(),
        feed: (_) async => [_volume(), _volume(file: 'next.epub', at: _later)],
      ).run(_volume(), onProgress: (_) {});
      expect(downloaded, isEmpty);
      expect(outcome.volume.fileName, 'book.epub');
    });

    test('a computer that is off still opens the book, and says so', () async {
      final original = _volume();
      final outcome = await freshener(
        record: _record(),
        feed: (_) async => throw Exception('no route'),
      ).run(original, onProgress: (_) {});
      expect(identical(outcome.volume, original), isTrue);
      expect(outcome.note, BookFreshener.couldNotCheck);
    });

    test('a check that hangs gives up rather than holding the book', () async {
      final outcome = await freshener(
        record: _record(),
        feed: (_) => Completer<List<Volume>>().future,
        checkTimeout: const Duration(milliseconds: 10),
      ).run(_volume(), onProgress: (_) {});
      expect(outcome.note, BookFreshener.couldNotCheck);
    });

    test('a failed download opens the old copy and says why', () async {
      final original = _volume();
      final outcome = await freshener(
        record: _record(),
        download: (_, _) async => throw DownloadException('Not enough space.'),
      ).run(original, onProgress: (_) {});
      expect(identical(outcome.volume, original), isTrue);
      expect(outcome.updated, isFalse);
      expect(outcome.note, contains('Not enough space.'));
    });
  });

  group('whether the server has changed a volume', () {
    test('a newer build or a different size counts', () {
      expect(volumeChangedOnServer(_volume(at: _later), _record()), isTrue);
      expect(volumeChangedOnServer(_volume(size: 200), _record()), isTrue);
    });

    test('the same build does not', () {
      expect(volumeChangedOnServer(_volume(), _record()), isFalse);
    });
  });

  group('a caught-up book with new chapters', () {
    final now = DateTime(2026, 11, 4);
    final entry = ReadingEntry(
      volume: _volume(),
      progress: ReadingProgress(
        chapterIndex: 9,
        blockIndex: 0,
        chapterCount: 10,
        updatedAt: now.subtract(const Duration(days: 30)),
      ),
    );

    int shelved({bool isNew = false, Set<String> hidden = const {}}) =>
        continueShelf(
          [entry],
          hidden: hidden,
          statuses: const {},
          hasNewChapters: (_) => isNew,
          now: now,
        ).length;

    test('stays away with nothing new', () => expect(shelved(), 0));

    test('comes back when there is', () => expect(shelved(isNew: true), 1));

    test('stays off if it was removed by hand', () {
      expect(shelved(isNew: true, hidden: const {'1/book.epub'}), 0);
    });
  });

  testWidgets('the dialog shows the bar and lets you skip the wait', (
    tester,
  ) async {
    var skipped = 0;
    final progress = ValueNotifier<double?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GettingChaptersDialog(
            title: 'A novel',
            progress: progress,
            onSkip: () => skipped++,
          ),
        ),
      ),
    );
    expect(find.text('Getting new chapters'), findsOneWidget);
    expect(find.text('A novel'), findsOneWidget);
    progress.value = 0.5;
    await tester.pump();
    await tester.tap(find.text('Read what I have'));
    expect(skipped, 1);
  });
}
