import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models/content_block.dart';
import '../models/epub_book.dart';

/// Raised when an EPUB can't be parsed. [message] is safe to show to the user.
class EpubException implements Exception {
  EpubException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A manifest entry from the OPF package document.
class _ManifestItem {
  _ManifestItem(this.href, this.mediaType, this.properties);

  final String href;
  final String mediaType;
  final String properties;
}

/// Parses EPUB files: opens the archive, reads the package document and table
/// of contents, and extracts chapter content into renderable blocks.
///
/// Keep one instance alive while a book is open — it retains the decoded
/// archive so chapters can be extracted lazily as the reader needs them.
class EpubParser {
  Archive? _archive;
  String _opfDir = '';

  /// Opens [file] and returns its metadata + chapter list. The archive is
  /// retained for subsequent [parseChapter] calls.
  Future<EpubBook> open(File file) async {
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on Exception catch (e) {
      throw EpubException('Could not read the book file.\n($e)');
    }

    try {
      _archive = ZipDecoder().decodeBytes(bytes);
    } on Exception catch (e) {
      throw EpubException('This file is not a valid EPUB.\n($e)');
    }

    final containerBytes = _findBytes('META-INF/container.xml');
    if (containerBytes == null) {
      throw EpubException('Not a valid EPUB — container.xml is missing.');
    }
    final opfPath = _opfPath(_decode(containerBytes));
    _opfDir = _dirOf(opfPath);

    final opfBytes = _findBytes(opfPath);
    if (opfBytes == null) {
      throw EpubException('Not a valid EPUB — the package file is missing.');
    }

    final XmlDocument opf;
    try {
      opf = XmlDocument.parse(_decode(opfBytes));
    } on XmlException catch (e) {
      throw EpubException('The EPUB package file is malformed.\n($e)');
    }

    final title = _firstText(opf, 'title') ?? 'Untitled';
    final author = _firstText(opf, 'creator') ?? 'Unknown';

    // Manifest: id -> item.
    final manifest = <String, _ManifestItem>{};
    for (final item in opf.findAllElements('item', namespaceUri: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = _ManifestItem(
        href,
        item.getAttribute('media-type') ?? '',
        item.getAttribute('properties') ?? '',
      );
    }

    // Spine: ordered idrefs = reading order.
    final spineIds = <String>[];
    for (final ref in opf.findAllElements('itemref', namespaceUri: '*')) {
      final idref = ref.getAttribute('idref');
      if (idref != null) spineIds.add(idref);
    }

    final titles = _parseTableOfContents(opf, manifest);

    final chapters = <EpubChapter>[];
    for (final id in spineIds) {
      final item = manifest[id];
      if (item == null) continue;
      final zipPath = _resolve(_opfDir, item.href);
      // Only spine items that are actually documents.
      if (!zipPath.toLowerCase().endsWith('.xhtml') &&
          !zipPath.toLowerCase().endsWith('.html') &&
          !zipPath.toLowerCase().endsWith('.htm')) {
        continue;
      }
      final index = chapters.length;
      chapters.add(
        EpubChapter(
          index: index,
          title: titles[zipPath] ?? 'Chapter ${index + 1}',
          zipPath: zipPath,
        ),
      );
    }

    return EpubBook(title: title, author: author, chapters: chapters);
  }

  /// Footnote bodies for the chapter currently being parsed, keyed by the
  /// trailing index of the `fn-…-N` anchor id. Set by [parseChapter] and
  /// read inside [_collectInline] to attach bodies to inline note refs.
  final Map<int, String> _currentNotes = {};

  /// Extracts and parses one chapter into renderable content blocks.
  List<ContentBlock> parseChapter(EpubChapter chapter) {
    final bytes = _findBytes(chapter.zipPath);
    if (bytes == null) {
      return const [
        ParagraphBlock([TextRun('(This chapter could not be loaded.)')]),
      ];
    }
    final document = html_parser.parse(_decode(bytes));
    final body = document.body;
    if (body == null) return const [];
    _extractFootnotes(body);
    final blocks = <ContentBlock>[];
    _walkBlocks(body, blocks, _dirOf(chapter.zipPath));
    if (blocks.isEmpty) {
      return const [
        ParagraphBlock([TextRun('(This chapter appears to be empty.)')]),
      ];
    }
    return blocks;
  }

  /// Pulls every `<aside epub:type="footnote">` out of [body] into
  /// [_currentNotes] and removes them from the DOM so they don't render as
  /// regular paragraphs (the inline note refs will pop them up on tap
  /// instead).
  void _extractFootnotes(dom.Element body) {
    _currentNotes.clear();
    final asides = body.querySelectorAll('aside');
    for (final aside in asides) {
      final cls = aside.className;
      final epubType = aside.attributes['epub:type'] ?? '';
      if (epubType != 'footnote' && !cls.contains('footnote')) continue;
      final id = aside.id;
      final match = RegExp(r'-(\d+)$').firstMatch(id);
      if (match == null) continue;
      final index = int.parse(match.group(1)!);
      // Body text minus the leading "[N]" marker and the back-link arrow.
      var text = aside.text.trim();
      text = text.replaceFirst(RegExp(r'^\s*\[\d+\]\s*'), '');
      text = text.replaceAll('↩', '').trim();
      if (text.isNotEmpty) _currentNotes[index] = text;
      aside.remove();
    }
    // Also strip an empty endnotes section so it doesn't render as blank.
    for (final section in body.querySelectorAll('section.footnotes')) {
      section.remove();
    }
  }

  // ── archive helpers ──────────────────────────────────────────────────────

  List<int>? _findBytes(String path) {
    final archive = _archive;
    if (archive == null) return null;
    final normalized = path.replaceAll('\\', '/');
    var found = archive.findFile(normalized);
    if (found == null) {
      final lower = normalized.toLowerCase();
      for (final file in archive.files) {
        if (file.name.toLowerCase() == lower) {
          found = file;
          break;
        }
      }
    }
    if (found == null || !found.isFile) return null;
    return found.content;
  }

  String _decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

  // ── path helpers ─────────────────────────────────────────────────────────

  String _dirOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  /// Resolves [href] (relative, possibly URL-encoded, possibly with a #frag)
  /// against [baseDir] into an absolute archive path.
  String _resolve(String baseDir, String href) {
    final clean = Uri.decodeFull(href.split('#').first);
    if (baseDir.isEmpty) return clean;
    return Uri.parse('$baseDir/').resolveUri(Uri.parse(clean)).path;
  }

  // ── OPF / TOC parsing ────────────────────────────────────────────────────

  String _opfPath(String containerXml) {
    try {
      final doc = XmlDocument.parse(containerXml);
      for (final rootfile in doc.findAllElements('rootfile', namespaceUri: '*')) {
        final fullPath = rootfile.getAttribute('full-path');
        if (fullPath != null && fullPath.isNotEmpty) return fullPath;
      }
    } on XmlException {
      // fall through
    }
    throw EpubException('Not a valid EPUB — no package file declared.');
  }

  String? _firstText(XmlDocument opf, String localName) {
    for (final el in opf.findAllElements(localName, namespaceUri: '*')) {
      final text = el.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// Returns a map of chapter archive-path -> title, from the EPUB3 nav
  /// document or the EPUB2 NCX, whichever is present.
  Map<String, String> _parseTableOfContents(
    XmlDocument opf,
    Map<String, _ManifestItem> manifest,
  ) {
    // EPUB3 navigation document.
    for (final item in manifest.values) {
      if (item.properties.contains('nav')) {
        final navPath = _resolve(_opfDir, item.href);
        final bytes = _findBytes(navPath);
        if (bytes != null) {
          final titles = _parseNav(_decode(bytes), _dirOf(navPath));
          if (titles.isNotEmpty) return titles;
        }
      }
    }
    // EPUB2 NCX.
    for (final item in manifest.values) {
      if (item.mediaType == 'application/x-dtbncx+xml') {
        final ncxPath = _resolve(_opfDir, item.href);
        final bytes = _findBytes(ncxPath);
        if (bytes != null) {
          return _parseNcx(_decode(bytes), _dirOf(ncxPath));
        }
      }
    }
    return const {};
  }

  Map<String, String> _parseNav(String xhtml, String navDir) {
    final titles = <String, String>{};
    try {
      final doc = html_parser.parse(xhtml);
      for (final anchor in doc.querySelectorAll('a')) {
        final href = anchor.attributes['href'];
        final text = anchor.text.trim();
        if (href == null || href.isEmpty || text.isEmpty) continue;
        titles.putIfAbsent(_resolve(navDir, href), () => text);
      }
    } on Exception {
      // Malformed nav — caller falls back to generated titles.
    }
    return titles;
  }

  Map<String, String> _parseNcx(String xml, String ncxDir) {
    final titles = <String, String>{};
    try {
      final doc = XmlDocument.parse(xml);
      for (final point in doc.findAllElements('navPoint', namespaceUri: '*')) {
        final label = point
            .getElement('navLabel', namespaceUri: '*')
            ?.getElement('text', namespaceUri: '*')
            ?.innerText
            .trim();
        final src = point
            .getElement('content', namespaceUri: '*')
            ?.getAttribute('src');
        if (label == null || label.isEmpty || src == null) continue;
        titles.putIfAbsent(_resolve(ncxDir, src), () => label);
      }
    } on XmlException {
      // Malformed NCX — caller falls back to generated titles.
    }
    return titles;
  }

  // ── chapter content parsing ──────────────────────────────────────────────

  void _walkBlocks(
    dom.Element parent,
    List<ContentBlock> out,
    String baseDir,
  ) {
    for (final node in parent.nodes) {
      if (node is! dom.Element) continue;
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'p') {
        final runs = _inlineRuns(node);
        if (_hasText(runs)) out.add(ParagraphBlock(runs));
        // EPUBs commonly wrap chapter art in <p><img/></p>; pull every
        // image out as its own block so the renderer can show it standalone.
        for (final img in node.querySelectorAll('img')) {
          final block = _readImage(img, baseDir);
          if (block != null) out.add(block);
        }
      } else if (tag.length == 2 && tag[0] == 'h' && '123456'.contains(tag[1])) {
        final runs = _inlineRuns(node);
        if (_hasText(runs)) out.add(HeadingBlock(int.parse(tag[1]), runs));
      } else if (tag == 'hr') {
        out.add(const DividerBlock());
      } else if (tag == 'img' || tag == 'image') {
        final image = _readImage(node, baseDir);
        if (image != null) out.add(image);
      } else if (tag == 'br') {
        // Line break between inline content — handled by _collectInline.
      } else if (tag == 'div' ||
          tag == 'section' ||
          tag == 'article' ||
          tag == 'main' ||
          tag == 'blockquote' ||
          tag == 'body' ||
          tag == 'figure') {
        _walkBlocks(node, out, baseDir);
      } else if (node.children.isNotEmpty) {
        _walkBlocks(node, out, baseDir);
      } else {
        final runs = _inlineRuns(node);
        if (_hasText(runs)) out.add(ParagraphBlock(runs));
      }
    }
  }

  /// Loads the EPUB image referenced by [node] (an `<img>` or SVG `<image>`)
  /// and parses its natural pixel dimensions from the PNG/JPEG header so
  /// the reader can lay it out without an async decode.
  ImageBlock? _readImage(dom.Element node, String baseDir) {
    final src = node.attributes['src'] ??
        node.attributes['xlink:href'] ??
        node.attributes['href'] ??
        '';
    if (src.isEmpty) return null;
    final path = _resolve(baseDir, src);
    final raw = _findBytes(path);
    if (raw == null) return null;
    final bytes = Uint8List.fromList(raw);
    final dims = _readImageDimensions(bytes);
    return ImageBlock(
      bytes: bytes,
      width: dims?.$1 ?? 800,
      height: dims?.$2 ?? 600,
      alt: node.attributes['alt'] ?? '',
    );
  }

  /// Reads natural (width, height) from a PNG or JPEG file header.
  /// Returns null for unrecognised formats — the caller should fall back to
  /// a reasonable aspect ratio.
  (int, int)? _readImageDimensions(Uint8List bytes) {
    // PNG: 8-byte signature, then IHDR chunk; width/height are big-endian
    // 32-bit ints at offsets 16-23.
    if (bytes.length > 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final w = (bytes[16] << 24) |
          (bytes[17] << 16) |
          (bytes[18] << 8) |
          bytes[19];
      final h = (bytes[20] << 24) |
          (bytes[21] << 16) |
          (bytes[22] << 8) |
          bytes[23];
      if (w > 0 && h > 0) return (w, h);
    }
    // JPEG: SOI \xFF\xD8 then a chain of segments; the SOFn marker carries
    // height (offset +5..6) and width (offset +7..8) as big-endian 16-bit.
    if (bytes.length > 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var i = 2;
      while (i < bytes.length - 9) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        // Skip fill bytes (0xFF chains).
        while (i < bytes.length && bytes[i] == 0xFF) {
          i++;
        }
        if (i >= bytes.length) break;
        final marker = bytes[i];
        i++;
        // SOFn markers — but not DHT (C4), DAC (CC) or DNL (DC).
        if (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          if (i + 6 >= bytes.length) break;
          final h = (bytes[i + 3] << 8) | bytes[i + 4];
          final w = (bytes[i + 5] << 8) | bytes[i + 6];
          if (w > 0 && h > 0) return (w, h);
          break;
        }
        if (i + 1 >= bytes.length) break;
        final segLen = (bytes[i] << 8) | bytes[i + 1];
        if (segLen < 2) break;
        i += segLen;
      }
    }
    return null;
  }

  List<TextRun> _inlineRuns(dom.Element element) {
    final runs = <TextRun>[];
    _collectInline(element, bold: false, italic: false, out: runs);
    return _trim(runs);
  }

  void _collectInline(
    dom.Node node, {
    required bool bold,
    required bool italic,
    required List<TextRun> out,
  }) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        final text = child.text.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isNotEmpty) {
          out.add(TextRun(text, bold: bold, italic: italic));
        }
      } else if (child is dom.Element) {
        final tag = child.localName?.toLowerCase() ?? '';
        if (tag == 'br') {
          out.add(const TextRun('\n'));
        } else if (tag == 'b' || tag == 'strong') {
          _collectInline(child, bold: true, italic: italic, out: out);
        } else if (tag == 'i' || tag == 'em') {
          _collectInline(child, bold: bold, italic: true, out: out);
        } else if (tag == 'sup' && child.className.contains('noteref')) {
          // Footnote / translator-note reference: keep the [N] marker as the
          // visible run text and attach the body so the reader can pop it up.
          final markerText = child.text.trim();
          final match = RegExp(r'\[(\d+)\]').firstMatch(markerText);
          final body = match != null
              ? _currentNotes[int.parse(match.group(1)!)]
              : null;
          if (body != null && body.isNotEmpty) {
            out.add(
              TextRun(
                markerText,
                bold: bold,
                italic: italic,
                footnoteBody: body,
              ),
            );
          } else if (markerText.isNotEmpty) {
            out.add(TextRun(markerText, bold: bold, italic: italic));
          }
        } else {
          _collectInline(child, bold: bold, italic: italic, out: out);
        }
      }
    }
  }

  /// Trims leading/trailing whitespace at the edges of a run list.
  List<TextRun> _trim(List<TextRun> runs) {
    if (runs.isEmpty) return runs;
    final first = runs.first;
    runs[0] = TextRun(
      first.text.trimLeft(),
      bold: first.bold,
      italic: first.italic,
    );
    final last = runs.last;
    runs[runs.length - 1] = TextRun(
      last.text.trimRight(),
      bold: last.bold,
      italic: last.italic,
    );
    runs.removeWhere((run) => run.text.isEmpty);
    return runs;
  }

  bool _hasText(List<TextRun> runs) =>
      runs.any((run) => run.text.trim().isNotEmpty);
}
