// Auto-delete decides which downloaded books get removed from the device.
// It had no tests at all, which for the only code in the app that destroys
// user data is the wrong place to be relying on inspection. Each test below
// pins one of its safety rules — a bug in any of them silently eats a book
// the reader still wanted.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/screens/library_downloads.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

Volume _vol(int series, int? number, {String? title}) => Volume(
  seriesOpdsId: series,
  title: title ?? (number == null ? 'Side Story' : 'Saga Vol $number'),
  fileName: number == null ? 'side-story.epub' : 'saga-v$number.epub',
  downloadUrl: 'http://unused/x.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
);

/// Reading position: [started] moves off the first block, [finished] sets the
/// end-reached flag that `isFinished` keys on.
ReadingEntry _entry(
  Volume v, {
  bool started = false,
  bool finished = false,
}) => ReadingEntry(
  volume: v,
  progress: ReadingProgress(
    chapterIndex: started || finished ? 3 : 0,
    blockIndex: 0,
    chapterCount: 10,
    endReached: finished,
  ),
);

/// Every volume is on disk unless named here.
bool Function(Volume) _downloadedExcept([Set<String> missing = const {}]) =>
    (v) => !missing.contains(v.fileName);

void main() {
  test('prunes a finished volume the reader has moved past', () {
    final v1 = _vol(1, 1);
    final v2 = _vol(1, 2);
    final doomed = volumesToPrune([
      _entry(v1, finished: true),
      _entry(v2, started: true),
    ], _downloadedExcept());
    expect(doomed.map((v) => v.fileName), ['saga-v1.epub']);
  });

  test('never prunes the volume being read', () {
    final doomed = volumesToPrune([
      _entry(_vol(1, 1), finished: true),
      _entry(_vol(1, 2), started: true, finished: true),
    ], _downloadedExcept());
    expect(
      doomed.map((v) => v.fileName),
      ['saga-v1.epub'],
      reason: 'v2 is the furthest started, so it stays even when finished',
    );
  });

  test('never prunes volumes ahead of the current one', () {
    final doomed = volumesToPrune([
      _entry(_vol(1, 2), started: true),
      _entry(_vol(1, 3), finished: true),
    ], _downloadedExcept());
    expect(
      doomed,
      isEmpty,
      reason: 'v3 is ahead of the furthest started — reading on, not done',
    );
  });

  test('never prunes a part-read volume', () {
    final doomed = volumesToPrune([
      _entry(_vol(1, 1), started: true), // started, not finished
      _entry(_vol(1, 2), started: true),
    ], _downloadedExcept());
    expect(doomed, isEmpty, reason: 'v1 was abandoned mid-way, not finished');
  });

  test('ignores volumes that are not on disk', () {
    final doomed = volumesToPrune([
      _entry(_vol(1, 1), finished: true),
      _entry(_vol(1, 2), started: true),
    ], _downloadedExcept({'saga-v1.epub'}));
    expect(doomed, isEmpty, reason: 'nothing to delete');
  });

  test('never prunes a volume with no parseable number', () {
    // Without an order there's no way to know it's behind anything.
    final side = _vol(1, null);
    final doomed = volumesToPrune([
      _entry(side, finished: true),
      _entry(_vol(1, 5), started: true),
    ], _downloadedExcept());
    expect(doomed, isEmpty);
  });

  test('an unnumbered current volume prunes nothing in that series', () {
    // maxStarted stays null, so the whole series is left alone.
    final doomed = volumesToPrune([
      _entry(_vol(1, 1), finished: true),
      _entry(_vol(1, null), started: true),
    ], _downloadedExcept());
    expect(doomed, isEmpty);
  });

  test('prunes nothing in a series the reader has not started', () {
    // The fresh-library case: finished-looking entries with nothing started
    // must not trigger a sweep.
    final doomed = volumesToPrune([
      _entry(_vol(1, 1)),
      _entry(_vol(1, 2)),
    ], _downloadedExcept());
    expect(doomed, isEmpty);
  });

  test('prunes every finished volume behind the current one', () {
    final doomed = volumesToPrune([
      _entry(_vol(1, 1), finished: true),
      _entry(_vol(1, 2), finished: true),
      _entry(_vol(1, 3), finished: true),
      _entry(_vol(1, 4), started: true),
    ], _downloadedExcept());
    expect(
      doomed.map((v) => v.fileName).toSet(),
      {'saga-v1.epub', 'saga-v2.epub', 'saga-v3.epub'},
    );
  });

  test('series are judged independently', () {
    // Being deep into series 1 must not prune series 2.
    final doomed = volumesToPrune([
      _entry(_vol(1, 1), finished: true),
      _entry(_vol(1, 2), started: true),
      _entry(_vol(2, 1), finished: true), // nothing started in series 2
    ], _downloadedExcept());
    expect(doomed.map((v) => v.fileName), ['saga-v1.epub']);
  });

  test('an empty library prunes nothing', () {
    expect(volumesToPrune(const [], _downloadedExcept()), isEmpty);
  });
}
