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
  String readingStatus = 'ongoing',
  int totalChapters = 0,
  String description = '',
  DateTime? updatedAt,
}) => Series(
  opdsId: id,
  title: title,
  author: author,
  description: description,
  genres: genres,
  readingStatus: readingStatus,
  totalChapters: totalChapters,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: updatedAt,
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

  test('cold start falls back to recently-updated series', () {
    final recs = engine.recommend(
      allSeries: [
        _series(
          id: 1, title: 'Older', genres: ['Action'],
          updatedAt: today.subtract(const Duration(days: 10)),
        ),
        _series(id: 2, title: 'Newest', updatedAt: today),
        _series(
          id: 3, title: 'Oldest',
          updatedAt: today.subtract(const Duration(days: 100)),
        ),
      ],
      readingEntries: const [],
      now: today,
    );
    expect(recs, isNotEmpty);
    expect(recs.first.series.opdsId, 2);
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
        _series(
          id: i, title: 'S$i', genres: ['Action'],
          author: 'Author $i', // unique authors so diversity guard doesn't trim
        ),
      _series(id: 99, title: 'Liked', genres: ['Action'], author: 'Read Author'),
    ];
    final recs = const RecommendationEngine(maxResults: 5).recommend(
      allSeries: library,
      readingEntries: [
        _entry(
          seriesId: 99,
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
    expect(recs.length, lessThanOrEqualTo(5));
    expect(recs, isNotEmpty);
  });

  test('a dropped series pulls candidates with its genres downward', () {
    final library = [
      _series(id: 1, title: 'Loved', genres: ['Action'], author: 'A'),
      _series(
        id: 2, title: 'Hated', genres: ['Mecha'], author: 'B',
        readingStatus: 'dropped',
      ),
      _series(id: 3, title: 'Pure Action', genres: ['Action'], author: 'C'),
      _series(id: 4, title: 'Pure Mecha', genres: ['Mecha'], author: 'D'),
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
    expect(recs.any((r) => r.series.opdsId == 2), isFalse);
    expect(recs.any((r) => r.series.opdsId == 4), isFalse,
        reason: 'Mecha is poisoned by the dropped series');
    expect(recs.first.series.opdsId, 3);
  });

  test('user-marked "completed" still counts as a like', () {
    final library = [
      _series(
        id: 1, title: 'Done', genres: ['Wuxia'], author: 'X',
        readingStatus: 'completed',
      ),
      _series(id: 2, title: 'Other Wuxia', genres: ['Wuxia'], author: 'Y'),
      _series(id: 3, title: 'Sci-Fi', genres: ['Sci-Fi'], author: 'Z'),
    ];
    final recs = engine.recommend(
      allSeries: library,
      // Only the very first paragraph read — the chapter-progress signal
      // alone is weak; the "completed" status should override.
      readingEntries: [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 0,
            blockIndex: 1,
            chapterCount: 200,
            updatedAt: today,
          ),
        ),
      ],
      now: today,
    );
    expect(recs.first.series.opdsId, 2);
  });

  test('diversity guard caps picks per author', () {
    final library = [
      for (var i = 1; i <= 6; i++)
        _series(id: i, title: 'S$i', genres: ['Action'], author: 'Solo'),
      _series(
        id: 99, title: 'Loved', genres: ['Action'], author: 'Other Author',
      ),
    ];
    final recs = const RecommendationEngine(maxPerAuthor: 2).recommend(
      allSeries: library,
      readingEntries: [
        _entry(
          seriesId: 99,
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
    final soloCount = recs
        .where((r) => r.series.author.toLowerCase() == 'solo')
        .length;
    expect(soloCount, lessThanOrEqualTo(2));
  });

  test('length bucket affinity favours similarly-sized novels', () {
    final library = [
      _series(
        id: 1, title: 'Liked Long', genres: ['Action'],
        author: 'A', totalChapters: 1500,
      ),
      _series(
        id: 2, title: 'Short Candidate', genres: ['Action'],
        author: 'B', totalChapters: 50,
      ),
      _series(
        id: 3, title: 'Long Candidate', genres: ['Action'],
        author: 'C', totalChapters: 1800,
      ),
    ];
    final recs = engine.recommend(
      allSeries: library,
      readingEntries: [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 1499,
            blockIndex: 0,
            chapterCount: 1500,
            updatedAt: today,
          ),
        ),
      ],
      now: today,
    );
    expect(recs.first.series.opdsId, 3);
  });

  test('a 10-volume binge does not drown out a single-volume favourite', () {
    final library = [
      _series(id: 1, title: 'Binge', genres: ['Wuxia'], author: 'Binge Author'),
      _series(id: 2, title: 'Other Wuxia', genres: ['Wuxia'], author: 'Z'),
      _series(id: 3, title: 'Same Binge Author', author: 'Binge Author'),
    ];
    final recs = engine.recommend(
      allSeries: library,
      readingEntries: [
        // Ten volumes of series 1, all finished today.
        for (var v = 1; v <= 10; v++)
          ReadingEntry(
            volume: Volume(
              seriesOpdsId: 1,
              title: 'Vol $v',
              fileName: 'v$v.epub',
              downloadUrl: '',
              fileSizeBytes: 0,
              updatedAt: null,
            ),
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
    // The √10 cap keeps the per-tag weight around ~3.2, not 10. So an
    // "other Wuxia" series should still be recommended (positive score).
    expect(recs.any((r) => r.series.opdsId == 2), isTrue);
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
