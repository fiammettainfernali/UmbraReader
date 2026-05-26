/// A single user-saved spot inside a book.
///
/// Like reading progress, the position is stored as a chapter index plus a
/// block index — not a pixel offset — so the bookmark stays valid across font
/// and margin changes.
class Bookmark {
  const Bookmark({
    required this.id,
    required this.chapterIndex,
    required this.blockIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.createdAt,
  });

  /// Stable identifier for delete + dedupe (a millisecond timestamp is fine).
  final String id;

  final int chapterIndex;

  /// Block index within the chapter (paragraph or heading).
  final int blockIndex;

  /// Chapter title at save time — denormalised so the bookmark list can
  /// render without re-parsing the EPUB.
  final String chapterTitle;

  /// Short excerpt of the block at the bookmark, for the list label.
  final String snippet;

  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'chapterIndex': chapterIndex,
    'blockIndex': blockIndex,
    'chapterTitle': chapterTitle,
    'snippet': snippet,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String? ?? '',
    chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
    blockIndex: (json['blockIndex'] as num?)?.toInt() ?? 0,
    chapterTitle: json['chapterTitle'] as String? ?? '',
    snippet: json['snippet'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}
