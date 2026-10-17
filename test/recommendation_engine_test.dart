// Tests for RecommendationEngine — the genre/author affinity ranker.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/recommendation_engine.dart';
import 'package:umbra_reader/services/recommendation_feedback_store.dart';

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
          id: 1,
          title: 'Older',
          genres: ['Action'],
          updatedAt: today.subtract(const Duration(days: 10)),
        ),
        _series(id: 2, title: 'Newest', updatedAt: today),
        _series(
          id: 3,
          title: 'Oldest',
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
          id: i,
          title: 'S$i',
          genres: ['Action'],
          author: 'Author $i', // unique authors so diversity guard doesn't trim
        ),
      _series(
        id: 99,
        title: 'Liked',
        genres: ['Action'],
        author: 'Read Author',
      ),
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
      _series(id: 2, title: 'Hated', genres: ['Mecha'], author: 'B'),
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
      // The drop comes from the in-app picker here. It used to be set on
      // Series.readingStatus, but that field is the server's and is now only
      // conditionally trusted, so the test says which channel it means; the
      // server-side 'dropped' channel has its own test below.
      signals: const RecSignals(statusOverrides: {2: 'dropped'}),
      now: today,
    );
    expect(recs.any((r) => r.series.opdsId == 2), isFalse);
    expect(
      recs.any((r) => r.series.opdsId == 4),
      isFalse,
      reason: 'Mecha is poisoned by the dropped series',
    );
    expect(recs.first.series.opdsId, 3);
  });

  test("a server-side 'dropped' is still a real user verdict", () {
    // Novel Grabber writes 'dropped' into the feed straight from its own
    // status picker, so unlike its 'completed' this IS the user speaking.
    // Neutralising the unread 'completed' must not take this channel too.
    final library = [
      _series(id: 1, title: 'Loved', genres: ['Action'], author: 'A'),
      _series(
        id: 2,
        title: 'Hated',
        genres: ['Mecha'],
        author: 'B',
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
    expect(
      recs.any((r) => r.series.opdsId == 4),
      isFalse,
      reason: 'Mecha is poisoned even with no in-app reading to back it',
    );
    expect(recs.first.series.opdsId, 3);
  });

  test('user-marked "completed" still counts as a like', () {
    final library = [
      _series(id: 1, title: 'Done', genres: ['Wuxia'], author: 'X'),
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
      // The mark has to come from the user's own picker: the server's
      // Series.readingStatus 'completed' means "this novel finished
      // publishing", which is nobody's verdict on the book.
      signals: const RecSignals(statusOverrides: {1: 'completed'}),
      now: today,
    );
    expect(recs.first.series.opdsId, 2);
  });

  test(
    "an unread server 'completed' seeds nothing and stays recommendable",
    () {
      // 57 of this library's novels carry the server's 'completed'; 55 were
      // never opened. Read as "the user finished this" they each contributed
      // a permanent, never-decaying +1.0 — louder than a real finished read,
      // which decays to a 0.15 floor — and were banned as already-engaged.
      final library = [
        _series(id: 1, title: 'Real Read', genres: ['Mecha'], author: 'A'),
        _series(
          id: 2,
          title: 'Never Opened Mecha',
          genres: ['Mecha'],
          author: 'B',
          readingStatus: 'completed',
        ),
        _series(id: 3, title: 'Other Mecha', genres: ['Mecha'], author: 'C'),
        _series(
          id: 4,
          title: 'Never Opened Xianxia',
          genres: ['Xianxia'],
          author: 'D',
          readingStatus: 'completed',
        ),
        _series(
          id: 5,
          title: 'Other Xianxia',
          genres: ['Xianxia'],
          author: 'E',
        ),
      ];
      final entries = [
        _entry(
          seriesId: 1,
          progress: ReadingProgress(
            chapterIndex: 99,
            blockIndex: 0,
            chapterCount: 100,
            updatedAt: today,
          ),
        ),
      ];
      final profile = engine.buildProfile(
        allSeries: library,
        readingEntries: entries,
        now: today,
      );
      expect(profile.engagedIds, isNot(contains(2)));
      expect(profile.engagedIds, isNot(contains(4)));
      expect(profile.engagedIds, contains(1));

      final ids = [
        for (final r in engine.recommend(
          allSeries: library,
          readingEntries: entries,
          now: today,
        ))
          r.series.opdsId,
      ];
      expect(
        ids,
        contains(2),
        reason: 'an unread book must stay in the candidate pool',
      );
      expect(ids, contains(3));
      expect(
        ids,
        isNot(contains(5)),
        reason: 'the never-opened Xianxia contributed no Xianxia affinity',
      );
    },
  );

  test("a user override rescues a server 'completed' the engine ignores", () {
    // Same shape, but this time the user marked the never-opened series
    // caught-up themselves — the external-reader binge. Their own verdict is
    // unconditional, so its genre seeds taste and the series leaves the pool.
    final library = [
      _series(id: 1, title: 'Real Read', genres: ['Mecha'], author: 'A'),
      _series(
        id: 4,
        title: 'Binged Elsewhere',
        genres: ['Xianxia'],
        author: 'D',
        readingStatus: 'completed',
      ),
      _series(id: 5, title: 'Other Xianxia', genres: ['Xianxia'], author: 'E'),
    ];
    final ids = [
      for (final r in engine.recommend(
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
        signals: const RecSignals(statusOverrides: {4: 'completed'}),
        now: today,
      ))
        r.series.opdsId,
    ];
    expect(ids, contains(5), reason: 'the user-marked series seeds Xianxia');
    expect(ids, isNot(contains(4)), reason: 'and is itself engaged');
  });

  test('opening a book and bouncing off it does not ban it forever', () {
    // The reader saves a progress row the moment a book is opened, so
    // building engagedIds from the existence of a row meant one peek —
    // chapter 0, block 0, nothing read — removed the series from
    // recommendations permanently while contributing no taste at all.
    final library = [
      _series(id: 1, title: 'Real Read', genres: ['Action'], author: 'A'),
      _series(id: 2, title: 'Peeked', genres: ['Action'], author: 'B'),
      _series(id: 3, title: 'Other Action', genres: ['Action'], author: 'C'),
    ];
    final entries = [
      _entry(
        seriesId: 1,
        progress: ReadingProgress(
          chapterIndex: 99,
          blockIndex: 0,
          chapterCount: 100,
          updatedAt: today,
        ),
      ),
      // Opened and closed again: the row exists, at the very first block.
      _entry(
        seriesId: 2,
        progress: ReadingProgress(
          chapterIndex: 0,
          blockIndex: 0,
          chapterCount: 400,
          updatedAt: today,
        ),
      ),
    ];
    final profile = engine.buildProfile(
      allSeries: library,
      readingEntries: entries,
      now: today,
    );
    expect(profile.engagedIds, contains(1));
    expect(profile.engagedIds, isNot(contains(2)));

    final ids = [
      for (final r in engine.recommend(
        allSeries: library,
        readingEntries: entries,
        now: today,
      ))
        r.series.opdsId,
    ];
    expect(ids, contains(2));
    expect(ids, contains(3));
  });

  test('diversity guard caps picks per author', () {
    final library = [
      for (var i = 1; i <= 6; i++)
        _series(id: i, title: 'S$i', genres: ['Action'], author: 'Solo'),
      _series(
        id: 99,
        title: 'Loved',
        genres: ['Action'],
        author: 'Other Author',
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
        id: 1,
        title: 'Liked Long',
        genres: ['Action'],
        author: 'A',
        totalChapters: 1500,
      ),
      _series(
        id: 2,
        title: 'Short Candidate',
        genres: ['Action'],
        author: 'B',
        totalChapters: 50,
      ),
      _series(
        id: 3,
        title: 'Long Candidate',
        genres: ['Action'],
        author: 'C',
        totalChapters: 1800,
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

  test('a dismissed recommendation is suppressed and softens its tags', () {
    final library = [
      _series(id: 1, title: 'Loved', genres: ['Action'], author: 'A'),
      _series(id: 2, title: 'Dismissed', genres: ['Action'], author: 'B'),
      _series(id: 3, title: 'Other Action', genres: ['Action'], author: 'C'),
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
      feedback: const {2: RecommendationFeedback.dismissed},
      now: today,
    );
    // Dismissed series never appears in the result.
    expect(recs.any((r) => r.series.opdsId == 2), isFalse);
    // The other Action series still shows up — dismiss is a soft signal.
    expect(recs.any((r) => r.series.opdsId == 3), isTrue);
  });

  test('a reset series overrides a positive reading-history signal', () {
    final library = [
      _series(
        id: 1,
        title: 'Finished Then Reset',
        genres: ['Mecha'],
        author: 'A',
      ),
      _series(id: 2, title: 'Other Mecha', genres: ['Mecha'], author: 'B'),
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
      feedback: const {1: RecommendationFeedback.reset},
      now: today,
    );
    // Reset turns the Mecha tag negative, so the other Mecha series is
    // suppressed too.
    expect(recs.any((r) => r.series.opdsId == 2), isFalse);
  });

  group('what "similar" is allowed to mean', () {
    // Reported from a real library: the "More like this" shelf on an action
    // cultivation novel was offering age regression, and had not changed in
    // months. The screen was handing similarTo the reader's LEARNED weights
    // — fitted on what makes them tap a shelf pick, and free to turn genre
    // down to nothing — so the ranking fell through to description-keyword
    // overlap.
    const blurb = 'sect elder spirit stone tribulation breakthrough';

    final source = _series(
      id: 1,
      title: 'Azure Peak',
      author: 'A',
      genres: ['Cultivation', 'Action'],
      totalChapters: 1500,
      description: blurb,
    );
    final sameGenre = _series(
      id: 2,
      title: 'Jade Summit',
      author: 'B',
      genres: ['Cultivation', 'Action'],
      totalChapters: 1400,
      description: 'rivals duel across the northern mountain passes',
    );
    // Shares the source's vocabulary and none of its genres: the shape of
    // book that was winning.
    final keywordTwin = _series(
      id: 3,
      title: 'Second Childhood',
      author: 'C',
      genres: ['Slice of Life', 'Age Regression'],
      totalChapters: 120,
      description: blurb,
    );
    final library = [
      source,
      sameGenre,
      keywordTwin,
      for (var i = 10; i < 20; i++)
        _series(id: i, title: 'Filler $i', genres: ['Romance']),
    ];

    int rankOf(List<Recommendation> picks, String title) =>
        picks.indexWhere((r) => r.series.title == title);

    test('genre beats a shared blurb', () {
      final picks = engine.similarTo(
        source: source,
        allSeries: library,
        now: today,
      );

      expect(rankOf(picks, 'Jade Summit'), isNonNegative);
      expect(
        rankOf(picks, 'Jade Summit'),
        lessThan(
          rankOf(picks, 'Second Childhood') == -1
              ? 1 << 30
              : rankOf(picks, 'Second Childhood'),
        ),
        reason: 'the book in the same genre is the more alike one',
      );
    });

    test('the collapsed learned vector is why the default exists', () {
      // What the screen used to pass on an install carrying the weights the
      // old learner could produce. Kept as a test so the reason the default
      // is not negotiable stays visible.
      const collapsed = RecWeights(
        author: 2.0,
        genre: 0.0,
        keyword: 1.0,
        length: 0.0,
      );
      final picks = engine.similarTo(
        source: source,
        allSeries: library,
        weights: collapsed,
        now: today,
      );

      expect(
        rankOf(picks, 'Second Childhood'),
        lessThan(
          rankOf(picks, 'Jade Summit') == -1
              ? 1 << 30
              : rankOf(picks, 'Jade Summit'),
        ),
        reason: 'with genre switched off, a shared blurb is all that is left',
      );
    });
  });

  test('similarTo finds picks resembling the given series', () {
    final source = _series(
      id: 1,
      title: 'Source',
      author: 'A',
      genres: ['Cultivation', 'Action'],
      totalChapters: 1500,
    );
    final library = [
      source,
      _series(
        id: 2,
        title: 'Cultivation Match',
        author: 'B',
        genres: ['Cultivation', 'Action'],
        totalChapters: 1400,
      ),
      _series(
        id: 3,
        title: 'Unrelated',
        author: 'C',
        genres: ['Romance'],
        totalChapters: 200,
      ),
    ];
    final picks = engine.similarTo(
      source: source,
      allSeries: library,
      now: today,
    );
    expect(picks, isNotEmpty);
    expect(picks.first.series.opdsId, 2);
    // The source itself is never suggested.
    expect(picks.any((p) => p.series.opdsId == 1), isFalse);
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

  test('untouched volumes do not dilute the one volume actually read', () {
    // A 20-volume series with one volume read was divided by all twenty:
    // √20/20 turned a full like into ~0.22, so the series the user is
    // genuinely reading steered taste less than a one-volume skim. Only
    // volumes that earned something may count towards the damping.
    final library = [
      _series(id: 1, title: 'Twenty Volumes', genres: ['Wuxia'], author: 'A'),
      _series(id: 2, title: 'Other Wuxia', genres: ['Wuxia'], author: 'B'),
      _series(id: 3, title: 'One Volume', genres: ['Xianxia'], author: 'C'),
      _series(id: 4, title: 'Other Xianxia', genres: ['Xianxia'], author: 'D'),
    ];
    final read = ReadingProgress(
      chapterIndex: 99,
      blockIndex: 0,
      chapterCount: 100,
      updatedAt: today,
    );
    final recs = engine.recommend(
      allSeries: library,
      readingEntries: [
        // Series 1: twenty volumes downloaded, only the first one opened.
        for (var v = 1; v <= 20; v++)
          ReadingEntry(
            volume: Volume(
              seriesOpdsId: 1,
              title: 'Vol $v',
              fileName: 'v$v.epub',
              downloadUrl: '',
              fileSizeBytes: 0,
              updatedAt: null,
            ),
            progress: v == 1
                ? read
                : ReadingProgress(
                    chapterIndex: 0,
                    blockIndex: 0,
                    chapterCount: 100,
                    updatedAt: today,
                  ),
          ),
        // Series 3: the same single read, in a one-volume series.
        _entry(seriesId: 3, progress: read),
      ],
      now: today,
    );
    final byId = {for (final r in recs) r.series.opdsId: r};
    expect(byId[2], isNotNull);
    expect(byId[4], isNotNull);
    expect(
      byId[2]!.score,
      closeTo(byId[4]!.score, 0.0001),
      reason:
          'one volume read is one volume read, whether the series has '
          'one volume or twenty',
    );
  });

  test(
    'barely-started book contributes little, finished book contributes a lot',
    () {
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
    },
  );
}
