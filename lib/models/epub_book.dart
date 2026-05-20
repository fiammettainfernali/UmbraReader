/// A parsed EPUB: its metadata and the ordered list of chapters.
class EpubBook {
  EpubBook({
    required this.title,
    required this.author,
    required this.chapters,
  });

  final String title;
  final String author;

  /// Chapters in spine (reading) order.
  final List<EpubChapter> chapters;
}

/// One chapter within an EPUB — a single XHTML document in the archive.
class EpubChapter {
  EpubChapter({
    required this.index,
    required this.title,
    required this.zipPath,
  });

  /// Zero-based position in the spine.
  final int index;

  /// Display title, from the table of contents (or `Chapter N` as a fallback).
  final String title;

  /// Path of the chapter's XHTML file inside the EPUB archive.
  final String zipPath;
}
