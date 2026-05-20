/// A run of chapter text with optional emphasis.
///
/// Emphasis is stored as flags, not concrete styles, so the reader can apply
/// the active theme (font, size, colour) at render time — and so a later
/// read-aloud feature can highlight individual runs.
class TextRun {
  const TextRun(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;
}

/// A renderable block of chapter content. Sealed so the reader can switch over
/// every kind exhaustively.
sealed class ContentBlock {
  const ContentBlock();
}

/// A normal paragraph.
class ParagraphBlock extends ContentBlock {
  const ParagraphBlock(this.runs);

  final List<TextRun> runs;
}

/// A heading; [level] is 1–6 (as in `<h1>`–`<h6>`).
class HeadingBlock extends ContentBlock {
  const HeadingBlock(this.level, this.runs);

  final int level;
  final List<TextRun> runs;
}

/// A scene break / horizontal rule.
class DividerBlock extends ContentBlock {
  const DividerBlock();
}
