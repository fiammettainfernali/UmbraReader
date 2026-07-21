/// Categorical highlight color. The actual painted colour is derived from
/// the active reader theme inside the reader, so a "blue" highlight on a
/// sepia palette blends differently than on a dark one — but the categorical
/// meaning stays consistent across themes.
enum HighlightColor {
  yellow,
  blue,
  pink,
  green;

  static HighlightColor fromName(String? name) {
    for (final c in HighlightColor.values) {
      if (c.name == name) return c;
    }
    return HighlightColor.yellow;
  }
}

/// A single user-saved spot inside a book.
///
/// Like reading progress, the position is stored as a chapter index plus a
/// block index — not a pixel offset — so the bookmark stays valid across font
/// and margin changes. A bookmark can also act as a *highlight* (paints a
/// background on its block in the reader) and optionally carry a [note].
class Bookmark {
  const Bookmark({
    required this.id,
    required this.chapterIndex,
    required this.blockIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.createdAt,
    this.isHighlight = false,
    this.note = '',
    this.color = HighlightColor.yellow,
    this.endBlockIndex,
    this.startChar,
    this.endChar,
    this.selectedText = '',
  });

  /// Stable identifier for delete + dedupe (a microsecond timestamp).
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

  /// True when the bookmark should paint a background tint on its block,
  /// marking a highlighted passage.
  final bool isHighlight;

  /// Optional user note attached to the bookmark — typically used on
  /// highlights to capture a thought about the passage.
  final String note;

  /// Categorical colour of the highlight (ignored for plain bookmarks).
  final HighlightColor color;

  /// Last block of a multi-block range highlight (inclusive). Null on
  /// block-level highlights and single-block ranges default to [blockIndex]
  /// via [rangeEndBlock].
  final int? endBlockIndex;

  /// Character offsets of a range highlight into the joined run text of
  /// [blockIndex] / [rangeEndBlock]. Null on a legacy whole-block highlight,
  /// which is what [isRange] keys on.
  final int? startChar;
  final int? endChar;

  /// The exact selected string — for copy, notes, sharing, and the list label.
  final String selectedText;

  /// True when this highlight covers a character range rather than a whole
  /// block. Legacy highlights (no [startChar]) render as whole-block, as before.
  bool get isRange => startChar != null && endChar != null;

  /// The range's last block, defaulting to [blockIndex] for a single-block
  /// range.
  int get rangeEndBlock => endBlockIndex ?? blockIndex;

  Bookmark copyWith({
    bool? isHighlight,
    String? note,
    HighlightColor? color,
  }) => Bookmark(
    id: id,
    chapterIndex: chapterIndex,
    blockIndex: blockIndex,
    chapterTitle: chapterTitle,
    snippet: snippet,
    createdAt: createdAt,
    isHighlight: isHighlight ?? this.isHighlight,
    note: note ?? this.note,
    color: color ?? this.color,
    endBlockIndex: endBlockIndex,
    startChar: startChar,
    endChar: endChar,
    selectedText: selectedText,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'chapterIndex': chapterIndex,
    'blockIndex': blockIndex,
    'chapterTitle': chapterTitle,
    'snippet': snippet,
    'createdAt': createdAt.toIso8601String(),
    if (isHighlight) 'isHighlight': true,
    if (note.isNotEmpty) 'note': note,
    if (color != HighlightColor.yellow) 'color': color.name,
    if (startChar != null) 'startChar': startChar,
    if (endChar != null) 'endChar': endChar,
    if (endBlockIndex != null) 'endBlockIndex': endBlockIndex,
    if (selectedText.isNotEmpty) 'selectedText': selectedText,
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String? ?? '',
    chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
    blockIndex: (json['blockIndex'] as num?)?.toInt() ?? 0,
    chapterTitle: json['chapterTitle'] as String? ?? '',
    snippet: json['snippet'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    isHighlight: json['isHighlight'] == true,
    note: json['note'] as String? ?? '',
    color: HighlightColor.fromName(json['color'] as String?),
    startChar: (json['startChar'] as num?)?.toInt(),
    endChar: (json['endChar'] as num?)?.toInt(),
    endBlockIndex: (json['endBlockIndex'] as num?)?.toInt(),
    selectedText: json['selectedText'] as String? ?? '',
  );
}
