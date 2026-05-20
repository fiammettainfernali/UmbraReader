/// A series in the library — one OPDS "novel" entry from Novel Grabber.
///
/// In Novel Grabber's model a "novel" maps to a *series*, and each compiled
/// EPUB batch maps to a *volume*. Volumes are listed in a separate per-novel
/// OPDS feed and fetched during sync, not here.
class Series {
  const Series({
    required this.opdsId,
    required this.title,
    required this.author,
    required this.description,
    required this.genres,
    required this.readingStatus,
    required this.totalChapters,
    required this.downloadedChapters,
    required this.coverUrl,
    required this.updatedAt,
    required this.directEpubUrl,
    required this.volumesFeedUrl,
  });

  /// Numeric id from the OPDS entry urn (`urn:novel-grabber:novel:<id>`).
  final int opdsId;
  final String title;
  final String author;
  final String description;
  final List<String> genres;

  /// Reader-set status: ongoing, completed, dropped, hiatus.
  final String readingStatus;
  final int totalChapters;
  final int downloadedChapters;

  /// Absolute URL of the cover image, or null if the series has no cover.
  final String? coverUrl;

  /// When the series' newest EPUB was last (re)compiled. Used for sync.
  final DateTime? updatedAt;

  /// Direct EPUB download URL — set only when the series has exactly one
  /// EPUB batch (Novel Grabber links straight to it in that case).
  final String? directEpubUrl;

  /// Per-novel OPDS feed listing every volume — set only when the series has
  /// more than one EPUB batch.
  final String? volumesFeedUrl;

  /// True when the series has multiple volumes (and so a [volumesFeedUrl]).
  bool get hasMultipleVolumes => volumesFeedUrl != null;
}
