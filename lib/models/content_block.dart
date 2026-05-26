import 'dart:typed_data';

/// A run of chapter text with optional emphasis.
///
/// Emphasis is stored as flags, not concrete styles, so the reader can apply
/// the active theme (font, size, colour) at render time — and so a later
/// read-aloud feature can highlight individual runs.
class TextRun {
  const TextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.footnoteBody,
  });

  final String text;
  final bool bold;
  final bool italic;

  /// Body of the translator/footnote attached to this run, or null. When
  /// set, [text] is the inline marker (e.g. "[1]") and the renderer shows
  /// the body in a popup on tap.
  final String? footnoteBody;
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

/// An inline image pulled from the EPUB archive — chapter art, character
/// illustrations, volume splash pages. [width] / [height] are the image's
/// natural pixel size (parsed from the PNG/JPEG header at parse time, with
/// a 4:3 fallback for unrecognised formats); the renderer uses the ratio to
/// keep aspect right at any column width.
class ImageBlock extends ContentBlock {
  const ImageBlock({
    required this.bytes,
    required this.width,
    required this.height,
    this.alt = '',
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String alt;
}
