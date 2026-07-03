import 'dart:async';

import '../models/content_block.dart';
import '../models/volume.dart';
import 'epub_parser.dart';
import 'library_cache.dart';
import 'library_storage.dart';

/// One full-text match somewhere in the downloaded library.
class LibraryHit {
  const LibraryHit({
    required this.volume,
    required this.bookTitle,
    required this.chapterIndex,
    required this.blockIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
  });

  final Volume volume;
  final String bookTitle;
  final int chapterIndex;
  final int blockIndex;
  final String chapterTitle;

  /// A short excerpt of text around the match.
  final String snippet;

  /// Character range of the match within [snippet].
  final int matchStart;
  final int matchEnd;
}

/// Full-text search across every *downloaded* volume in the library.
///
/// Deliberately index-free: each book is unzipped and scanned on demand,
/// results streaming out as they're found so the UI can render matches from
/// the first book while later ones are still being read. Fast enough for a
/// few hundred volumes; if a giant library ever makes this crawl, the
/// upgrade path is an FTS5 table in [AppDatabase] filled at download time.
class LibrarySearch {
  LibrarySearch({LibraryStorage? storage})
    : _storage = storage ?? LibraryStorage();

  final LibraryStorage _storage;

  /// Streams matches for [query] (case-insensitive, min 2 chars) across all
  /// downloaded volumes. Caps at [maxPerBook] hits per volume and [maxHits]
  /// overall. Cancel the subscription to stop early — the scan yields
  /// between chapters, so cancellation is prompt.
  Stream<LibraryHit> search(
    String query, {
    int maxHits = 120,
    int maxPerBook = 12,
  }) async* {
    final needle = query.trim().toLowerCase();
    if (needle.length < 2) return;

    final store = DownloadStore(_storage);
    await store.load();
    final cache = LibraryCache(_storage);
    await cache.load();

    var total = 0;
    for (final key in store.allRecords.keys.toList()..sort()) {
      final slash = key.indexOf('/');
      if (slash <= 0) continue;
      final seriesId = int.tryParse(key.substring(0, slash));
      final fileName = key.substring(slash + 1);
      if (seriesId == null) continue;

      // Prefer the cached volume metadata (real title); fall back to a
      // minimal volume so an uncached book is still searchable.
      final cached = cache.volumesFor(seriesId);
      final volume =
          cached?.where((v) => v.fileName == fileName).firstOrNull ??
          Volume(
            seriesOpdsId: seriesId,
            title: fileName,
            fileName: fileName,
            downloadUrl: '',
            fileSizeBytes: 0,
            updatedAt: null,
          );

      final file = await _storage.epubFile(volume);
      if (!file.existsSync()) continue;

      final parser = EpubParser();
      final EpubBookHits? bookHits = await _scanBook(
        parser,
        file,
        volume,
        needle,
        maxPerBook,
      );
      if (bookHits == null) continue;
      for (final hit in bookHits.hits) {
        yield hit;
        total++;
        if (total >= maxHits) return;
      }
      // Yield to the event loop between books so a cancelled subscription
      // stops promptly and the UI stays responsive.
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<EpubBookHits?> _scanBook(
    EpubParser parser,
    dynamic file,
    Volume volume,
    String needle,
    int maxPerBook,
  ) async {
    try {
      final book = await parser.open(file);
      final hits = <LibraryHit>[];
      for (var ci = 0; ci < book.chapters.length; ci++) {
        final chapter = book.chapters[ci];
        final blocks = parser.parseChapter(chapter);
        for (var bi = 0; bi < blocks.length; bi++) {
          final text = _blockText(blocks[bi]);
          final idx = text.toLowerCase().indexOf(needle);
          if (idx < 0) continue;
          hits.add(
            _buildHit(
              volume,
              book.title,
              ci,
              bi,
              chapter.title,
              text,
              idx,
              needle.length,
            ),
          );
          if (hits.length >= maxPerBook) return EpubBookHits(hits);
        }
      }
      return EpubBookHits(hits);
    } on Exception {
      return null; // an unreadable book must not abort the whole search
    }
  }

  String _blockText(ContentBlock block) => switch (block) {
    ParagraphBlock p => p.runs.map((r) => r.text).join(),
    HeadingBlock h => h.runs.map((r) => r.text).join(),
    DividerBlock _ => '',
    ImageBlock _ => '',
  };

  LibraryHit _buildHit(
    Volume volume,
    String bookTitle,
    int chapterIndex,
    int blockIndex,
    String chapterTitle,
    String text,
    int matchIndex,
    int matchLength,
  ) {
    const lead = 36;
    const trail = 96;
    final start = (matchIndex - lead).clamp(0, text.length);
    final end = (matchIndex + matchLength + trail).clamp(0, text.length);
    var snippet = text.substring(start, end).replaceAll('\n', ' ');
    var matchStart = matchIndex - start;
    if (start > 0) {
      snippet = '…$snippet';
      matchStart += 1;
    }
    if (end < text.length) snippet = '$snippet…';
    return LibraryHit(
      volume: volume,
      bookTitle: bookTitle,
      chapterIndex: chapterIndex,
      blockIndex: blockIndex,
      chapterTitle: chapterTitle,
      snippet: snippet,
      matchStart: matchStart,
      matchEnd: matchStart + matchLength,
    );
  }
}

/// Hits found within one book — a tiny carrier so [_scanBook] can be a
/// single awaited unit per volume.
class EpubBookHits {
  const EpubBookHits(this.hits);
  final List<LibraryHit> hits;
}
