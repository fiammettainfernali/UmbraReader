// "New" on a Continue card means the library holds something this device
// does not.
//
// The complaint it answers: new chapters brought a story back to the shelf
// with no sign there was anything new about it -- the count still read
// "of 76", because that count comes from the EPUB on the device and the
// device still had the old one. It only changed after a download.
//
// Deliberately a flag and not a number. The progress line counts the spine
// of one volume; the library counts chapters across a whole series. Those
// are different scales, so any arithmetic between them is wrong by a
// different amount for every book.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/library_cards.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

Volume _volume() => Volume(
  seriesOpdsId: 7,
  title: 'A Book',
  fileName: 'book.epub',
  downloadUrl: 'https://hub.example/epub/7/book.epub',
  fileSizeBytes: 1000,
  updatedAt: DateTime.utc(2026, 5, 1),
);

Series _series() => Series(
  opdsId: 7,
  title: 'A Book',
  author: '',
  description: '',
  genres: const [],
  readingStatus: 'ongoing',
  totalChapters: 82,
  downloadedChapters: 82,
  updatedAt: DateTime.utc(2026, 6, 1),
  coverUrl: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

Widget _card({required bool hasUpdate}) => MaterialApp(
  home: Scaffold(
    body: ContinueCard(
      entry: ReadingEntry(
        volume: _volume(),
        progress: const ReadingProgress(
          chapterIndex: 14,
          blockIndex: 0,
          chapterCount: 76,
        ),
      ),
      series: _series(),
      imageHeaders: const {},
      hasUpdate: hasUpdate,
      onTap: () {},
      onLongPress: () {},
    ),
  ),
);

void main() {
  testWidgets('a book with newer chapters is marked', (tester) async {
    await tester.pumpWidget(_card(hasUpdate: true));
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('a book that is up to date is not', (tester) async {
    await tester.pumpWidget(_card(hasUpdate: false));
    expect(find.text('New'), findsNothing);
  });

  testWidgets('the progress line still says where you are', (tester) async {
    // The badge must not replace or alter the count -- "of 76" is still
    // the truth about the copy on this device.
    await tester.pumpWidget(_card(hasUpdate: true));
    expect(find.text('Chapter 15 of 76'), findsOneWidget);
  });

  testWidgets('a screen reader is told about it too', (tester) async {
    await tester.pumpWidget(_card(hasUpdate: true));
    final label = tester
        .getSemantics(find.byType(ContinueCard))
        .label;
    expect(label, contains('new chapters available'));
  });

  testWidgets('and is not told when there is nothing new', (tester) async {
    await tester.pumpWidget(_card(hasUpdate: false));
    final label = tester
        .getSemantics(find.byType(ContinueCard))
        .label;
    expect(label, isNot(contains('new chapters')));
  });
}
