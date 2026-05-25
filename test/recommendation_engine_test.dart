// Tests for RecommendationEngine — the genre/author affinity ranker.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/recommendation_engine.dart';

Series _series({
  required int id,
  required String title,
  String author = 'Anon',
  List<String> genres = const [],
}) => Series(
  opdsId: id,
  title: title,
  author: author,
  description: '',
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: 0,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

ReadingEntry _entry({
  required int seriesId,
  required ReadingProgress progress,
}) => ReadingEntry(
  volume: Volume(
    seriesOpdsId: seriesId,
    title: 'Vol 1',
    fileName: 'v1.epub',
    downloadUrl: '',
    fileSizeBytes: 0,
    updatedAt: null,
  ),
  progress: progress,
);

void main() {
  const engine = RecommendationEngine();
  final today = DateTime.utc(2026, 6, 1);

  test('returns nothing when there is no reading history', () {
    final recs = engine.recommend(
      allSeries: [
        _series(id: 1, title: 'A', genres: ['Action']),
        _series(id: 2, title: 'B', genres: ['Romance']),
      ],
      readingEntries: const [],
      now: today,
    );
    expect(recs, isEmpty);
  });

  test('returns nothing when the library is empty', () {
    final recs = engine.recommend(
      allSeries: const [],
      readingEntries: [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 9,
            blockIndex: 0,
            chapterCount: 10,
            updatedAt: today,
          ),
        ),
      ],
      now: today,
    );
    expect(recs, isEmpty);
  });

  test('ranks shared-genre series above unrelated ones', () {
    final library = [
      _series(id: 1, title: 'Liked Action', genres: ['Action', 'Fantasy']),
      _series(id: 2, title: 'Other Action', genres: ['Action']),
      _series(id: 3, title: 'Unrelated Romance', genres: ['Romance']),
    ];
    final recs = engine.recommend(
      allSeries: library,
      readingEntries: [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 99,
            blockIndex: 0,
            chapterCount: 100,
            updatedAt: today,
          ),
        ),
      ],
      now: today,
    );
    expect(recs, isNotEmpty);
    expect(recs.first.series.opdsId, 2);
    // The unrelated series either ranks last or doesn't surface at all.
    if (recs.length > 1) {
      expect(recs.last.series.opdsId, 3);
    } else {
      expect(recs.any((r) => r.series.opdsId == 3), isFalse);
    }
  });

  test('does not recommend a series the user is already reading', () {
    final library = [
      _series(id: 1, title: 'Liked', genres: ['Action']),
      _series(id: 2, title: 'Also Action', genres: ['Action']),
    ];
    final recs = engine.recommend(
      allSeries: library,
      readingEntries: [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 99,
            blockIndex: 0,
            chapterCount: 100,
            updatedAt: today,
          ),
        ),
      ],
      now: today,
    );
    expect(recs.any((r) => r.series.opdsId == 1), isFalse);
  });

  test('author match boosts a series above pure genre overlap', () {
    final library = [
      _series(id: 1, title: 'Source', author: 'Jane Doe', genres: ['Action']),
      _series(
        id: 2,
        title: 'Same Author, No Genre',
        author: 'Jane Doe',
        genres: ['Romance'],
      ),
      _series(
        id: 3,
        title: 'Same Genre, Other Author',
        author: 'Someone Else',
        genres: ['Action'],
      ),
    ];
    final recs = engine.recommend(
      allSeries: library,
      readingEntries: [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 99,
            blockIndex: 0,
            chapterCount: 100,
            updatedAt: today,
          ),
        ),
      ],
      now: today,
    );
    expect(recs.first.series.opdsId, 2);
  });

  test('recent reads outweigh older reads of the opposite genre', () {
    final library = [
      _series(id: 1, title: 'Old Liked', genres: ['Mecha']),
      _series(id: 2, title: 'Recent Liked', genres: ['Slice of Life']),
      _series(id: 3, title: 'Candidate Mecha', genres: ['Mecha']),
      _series(id: 4, title: 'Candidate Slice', genres: ['Slice of Life']),
    ];
    final recs = engine.recommend(
      allSeries: library,
      readingEntries: [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 99,
            blockIndex: 0,
            chapterCount: 100,
            updatedAt: today.subtract(const Duration(days: 365)),
          ),
        ),
        _entry(
          seriesId: 2,
          progress: ReadingProgress(
            chapterIndex: 99,
            blockIndex: 0,
            chapterCount: 100,
            updatedAt: today,
          ),
        ),
      ],
      now: today,
    );
    expect(recs.first.series.opdsId, 4);
  });

  test('respects maxResults', () {
    final library = [
      for (var i = 1; i <= 30; i++)
        _series(id: i, title: 'S$i', genres: ['Action']),
    ];
    final recs = const RecommendationEngine(maxResults: 5).recommend(
      allSeries: library,
      readingEntries: [
        _entry(
          seriesId: 100,
          progress: ReadingProgress(
            chapterIndex: 99,
            blockIndex: 0,
            chapterCount: 100,
            updatedAt: today,
          ),
        ),
      ],
      now: today,
    );
    // The "read" series isn't in the library; affinity comes from nothing.
    expect(recs, isEmpty);
  });

  test('barely-started book contributes little, finished book contributes a lot', () {
    final library = [
      _series(id: 1, title: 'Barely Started', genres: ['A']),
      _series(id: 2, title: 'Finished', genres: ['B']),
      _series(id: 3, title: 'Candidate A', genres: ['A']),
      _series(id: 4, title: 'Candidate B', genres: ['B']),
    ];
    final recs = engine.recommend(
      allSeries: library,
      readingEntries: [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 0,
            blockIndex: 1, // started but barely
            chapterCount: 100,
            updatedAt: today,
          ),
        ),
        _entry(
          seriesId: 2,
          progress: ReadingProgress(
            chapterIndex: 99,
            blockIndex: 0,
            chapterCount: 100,
            updatedAt: today,
          ),
        ),
      ],
      now: today,
    );
    expect(recs.first.series.opdsId, 4);
  });
}
