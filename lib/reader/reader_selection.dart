import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/bookmark.dart';
import '../models/content_block.dart';
import '../models/epub_book.dart';
import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../models/volume.dart';
import '../services/bookmark_store.dart';
import '../services/dictionary_service.dart';
import 'block_view.dart';
import 'reader_layout.dart';

/// Text hit-testing and selection, extracted from the ReaderScreen State:
/// resolving which word or character the reader is touching, holding the
/// active selection, and the actions on it (copy, define, highlight, note).
///
/// Hit-testing lives here rather than in the State because selection is its
/// only substantial consumer — and because both word lookup and selection
/// resolve a press the same way. They previously did so through two
/// near-identical copies of the layout maths; [_resolveHit] is now the single
/// implementation and [wordAt] is a thin wrapper over it.
///
/// The mixin owns every selection-only field; everything it needs from the
/// rest of the reader goes through the abstract members below, which the
/// State implements as thin proxies onto its private fields.
mixin ReaderSelection<T extends StatefulWidget> on State<T> {
  // ── what the reader State must provide ──────────────────────────────────

  Volume get readerVolume;
  ReaderSettings get readerSettings;
  List<ContentBlock>? get currentBlocks;
  EpubBook? get currentBook;
  int get currentChapterIndex;

  /// True while the overlay chrome is up — it shifts the content down, so the
  /// hit-test origin moves with it.
  bool get chromeVisible;

  /// Width the content was last laid out at, for block height measurement.
  double get contentWidth;

  ScrollController get readerScrollController;
  PageController get readerPageController;
  List<List<PageBlock>>? get currentPages;

  /// Columns per page view (1, or 2 for TV mode / tablet spreads).
  int get pageStride;

  void hapticSelection();

  /// Trims block text to a short single-line preview for the bookmark list.
  String shortSnippet(String text);

  /// Re-reads saved highlights so a new one paints immediately.
  Future<void> refreshHighlights();

  /// Opens the one-field note editor for [mark] (shared with quick capture).
  Future<void> addNoteToBookmark(Bookmark mark);

  // ── selection state (owned by the mixin) ────────────────────────────────

  /// Max width of the centred reading column, matching the State's layout.
  static const double _centeredColumnWidth = 620;

  /// Active text selection (scroll mode) — a range from (startBlock,
  /// startChar) to (endBlock, endChar), normalised so start ≤ end, in the
  /// blocks' joined run text. Null when nothing is selected.
  ({int startBlock, int startChar, int endBlock, int endChar})? _selection;

  /// The seed word's block and char bounds, so a drag extends the selection
  /// out from the long-pressed word (either direction, across paragraphs).
  int _selAnchorBlock = 0;
  int _selAnchorStart = 0;
  int _selAnchorEnd = 0;

  bool get hasSelection => _selection != null;

  /// The wash painted behind the live selection — an iOS-ish blue, distinct
  /// from the coloured saved-highlight tints.
  Color get selectionTint => const Color(0xFF4C8DFF).withValues(alpha: 0.35);

  // ── hit testing ─────────────────────────────────────────────────────────

  /// The word at [globalPosition], or null when the press isn't on text.
  /// Uses the pagination's own TextPainter maths, so it's exact.
  String? wordAt(Offset globalPosition) {
    // Focus mode centres a single paragraph outside the geometry this
    // hit-test relies on — skip word lookup there for now.
    if (readerSettings.focusParagraph) return null;
    final hit = _resolveHit(globalPosition, allowPaged: true);
    if (hit == null) return null;
    if (hit.wordStart >= hit.wordEnd || hit.wordEnd > hit.text.length) {
      return null;
    }
    final word = hit.text
        .substring(hit.wordStart, hit.wordEnd)
        .replaceAll(
          RegExp(r'''^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$''', unicode: true),
          '',
        );
    if (word.isEmpty || word.length > 40) return null;
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(word)) return null;
    return word;
  }

  /// Resolves a press to the block index, character offset and word bounds
  /// under it. The single implementation behind both [wordAt] and selection.
  ///
  /// In paged mode a block can be sliced across pages: the returned index is
  /// the *origin* block, while the text is the rendered slice's — fine for
  /// word lookup, which is why selection stays scroll-only for now.
  ({int block, int offset, int wordStart, int wordEnd, String text})?
  _resolveHit(Offset global, {required bool allowPaged}) {
    final blocks = currentBlocks;
    if (blocks == null || blocks.isEmpty) return null;
    final paged = readerSettings.mode == ReadingMode.paged;
    if (paged && !allowPaged) return null;

    final mq = MediaQuery.of(context);
    final areaWidth = readerSettings.centeredColumn && !readerSettings.tvMode
        ? math.min(mq.size.width, _centeredColumnWidth)
        : mq.size.width;
    final contentLeft = (mq.size.width - areaWidth) / 2;
    final contentTop = chromeVisible
        ? mq.padding.top + kTopBarHeight
        : mq.padding.top + 8;

    final (block, slice, localX, localY) = paged
        ? _pagedHit(global, areaWidth, contentLeft, contentTop)
        : _scrollHit(global, contentLeft, contentTop);
    if (block == null) return null;
    final blockIndex = blocks.indexOf(block);
    if (blockIndex < 0) return null;

    final rendered = slice ?? block;
    final ParagraphBlock? paragraph = switch (rendered) {
      ParagraphBlock p => p,
      HeadingBlock h => ParagraphBlock(h.runs),
      _ => null,
    };
    if (paragraph == null) return null;

    final width = paged
        ? _pagedColumnTextWidth(areaWidth)
        : areaWidth - 2 * readerSettings.margin;
    final style = rendered is HeadingBlock
        ? headingStyle(
            readerSettings,
            rendered.level,
            readerSettings.theme.text,
          )
        : paragraphStyle(readerSettings, readerSettings.theme.text);
    final painter = TextPainter(
      // Fixation anchors widen line wrapping, so hit-test with the same runs
      // that were rendered or the tapped word won't line up.
      text: runSpan(effectiveRuns(paragraph.runs, readerSettings), style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);
    if (localY < 0 || localY > painter.height) return null;

    final pos = painter.getPositionForOffset(Offset(localX, localY));
    final text = paragraph.runs.map((r) => r.text).join();
    final range = painter.getWordBoundary(pos);
    return (
      block: blockIndex,
      offset: pos.offset.clamp(0, text.length),
      wordStart: range.start,
      wordEnd: range.end,
      text: text,
    );
  }

  /// Text width of one paged column (matches _buildPaged's colWidth).
  double _pagedColumnTextWidth(double areaWidth) {
    final stride = pageStride;
    final tvSafeH = readerSettings.tvMode ? areaWidth * 0.055 : 0.0;
    final usableWidth = areaWidth - 2 * tvSafeH;
    const columnGutter = 36.0;
    final gutterTotal = columnGutter * (stride - 1);
    return ((usableWidth - gutterTotal) / stride) - 2 * readerSettings.margin;
  }

  /// Resolves a scroll-mode press to (block, sliceless, x, y within the
  /// block's own text layout).
  (ContentBlock?, ContentBlock?, double, double) _scrollHit(
    Offset global,
    double contentLeft,
    double contentTop,
  ) {
    final blocks = currentBlocks!;
    if (!readerScrollController.hasClients) return (null, null, 0, 0);
    final x = global.dx - contentLeft - readerSettings.margin;
    var y =
        global.dy - contentTop + readerScrollController.offset - kContentVPad;
    for (final block in blocks) {
      final h = measureBlockHeight(block, contentWidth, readerSettings);
      if (y < h) {
        // Headings carry a top gap before their text.
        final inset = block is HeadingBlock ? kHeadingTopGap : 0.0;
        return (block, null, x, y - inset);
      }
      y -= h;
    }
    return (null, null, 0, 0);
  }

  /// Resolves a paged-mode press to (origin block, rendered slice, x, y
  /// within the slice's own text layout).
  (ContentBlock?, ContentBlock?, double, double) _pagedHit(
    Offset global,
    double areaWidth,
    double contentLeft,
    double contentTop,
  ) {
    final pages = currentPages;
    if (pages == null || pages.isEmpty || !readerPageController.hasClients) {
      return (null, null, 0, 0);
    }
    final blocks = currentBlocks;
    final stride = pageStride;
    final tvSafeH = readerSettings.tvMode ? areaWidth * 0.055 : 0.0;
    final tvSafeV = readerSettings.tvMode
        ? MediaQuery.of(context).size.height * 0.04
        : 0.0;
    const columnGutter = 36.0;
    final colOuter =
        ((areaWidth - 2 * tvSafeH) - columnGutter * (stride - 1)) / stride;
    var x = global.dx - contentLeft - tvSafeH;
    var col = 0;
    while (col < stride - 1 && x > colOuter + columnGutter / 2) {
      x -= colOuter + columnGutter;
      col++;
    }
    final spread = (readerPageController.page ?? 0).round();
    final pageIndex = spread * stride + col;
    if (pageIndex < 0 || pageIndex >= pages.length) return (null, null, 0, 0);

    final textX = x - readerSettings.margin;
    var y = global.dy - contentTop - tvSafeV - kContentVPad;
    final width = _pagedColumnTextWidth(areaWidth);
    for (final pb in pages[pageIndex]) {
      final block = pb.block;
      final double h;
      final double inset;
      switch (block) {
        case ParagraphBlock p:
          h =
              layoutParagraph(p.runs, width, readerSettings).height +
              paragraphGap(readerSettings);
          inset = 0;
        case HeadingBlock _:
          h = measureBlockHeight(block, width, readerSettings);
          inset = kHeadingTopGap;
        case DividerBlock _:
          h = kDividerHeight;
          inset = 0;
        case ImageBlock _:
          h = measureBlockHeight(block, width, readerSettings);
          inset = 0;
      }
      if (y < h) {
        final origin = (blocks != null && pb.originIndex < blocks.length)
            ? blocks[pb.originIndex]
            : block;
        return (origin, block, textX, y - inset);
      }
      y -= h;
    }
    return (null, null, 0, 0);
  }

  // ── selection lifecycle ─────────────────────────────────────────────────

  /// Starts a selection at the word under [global]. Returns false when the
  /// press isn't on a selectable word, so the caller can fall back (e.g. to
  /// quick capture). Scroll mode only — see [_resolveHit].
  bool beginSelectionAt(Offset global) {
    if (readerSettings.mode != ReadingMode.scroll ||
        readerSettings.focusParagraph) {
      return false;
    }
    final hit = _resolveHit(global, allowPaged: false);
    if (hit == null) return false;
    if (hit.wordStart >= hit.wordEnd || hit.wordEnd > hit.text.length) {
      return false;
    }
    final word = hit.text.substring(hit.wordStart, hit.wordEnd);
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(word)) return false;
    hapticSelection();
    setState(() {
      _selection = (
        startBlock: hit.block,
        startChar: hit.wordStart,
        endBlock: hit.block,
        endChar: hit.wordEnd,
      );
      _selAnchorBlock = hit.block;
      _selAnchorStart = hit.wordStart;
      _selAnchorEnd = hit.wordEnd;
    });
    return true;
  }

  /// Extends the active selection to the position under [global]. Dragging
  /// doesn't need to land on a word — sliding over whitespace or into another
  /// paragraph should still move the edge.
  void extendSelectionTo(Offset global) {
    if (_selection == null) return;
    final hit = _resolveHit(global, allowPaged: false);
    if (hit == null) return;
    _extendSelection(hit.block, hit.offset);
  }

  /// Extends out from the seed word to (block, offset), on either side of the
  /// anchor and across paragraphs, keeping the seed word covered.
  void _extendSelection(int block, int offset) {
    if (_selection == null) return;
    final o = offset.clamp(0, blockText(block).length);
    final int sb, sc, eb, ec;
    if (_cmpPos(block, o, _selAnchorBlock, _selAnchorEnd) > 0) {
      // Past the anchor word — grow the end.
      sb = _selAnchorBlock;
      sc = _selAnchorStart;
      eb = block;
      ec = o;
    } else if (_cmpPos(block, o, _selAnchorBlock, _selAnchorStart) < 0) {
      // Before the anchor word — grow the start.
      sb = block;
      sc = o;
      eb = _selAnchorBlock;
      ec = _selAnchorEnd;
    } else {
      // Inside the anchor word — hold the whole word.
      sb = _selAnchorBlock;
      sc = _selAnchorStart;
      eb = _selAnchorBlock;
      ec = _selAnchorEnd;
    }
    final sel = _selection!;
    if (sb == sel.startBlock &&
        sc == sel.startChar &&
        eb == sel.endBlock &&
        ec == sel.endChar) {
      return;
    }
    setState(
      () => _selection = (
        startBlock: sb,
        startChar: sc,
        endBlock: eb,
        endChar: ec,
      ),
    );
  }

  void clearSelection() {
    if (_selection == null) return;
    setState(() => _selection = null);
  }

  /// Lexicographic comparison of two (block, char) positions.
  int _cmpPos(int b1, int c1, int b2, int c2) => b1 != b2 ? b1 - b2 : c1 - c2;

  /// Joined run text of block [index] (paragraph or heading), or '' otherwise.
  String blockText(int index) {
    final blocks = currentBlocks;
    if (blocks == null || index < 0 || index >= blocks.length) return '';
    final b = blocks[index];
    return switch (b) {
      ParagraphBlock p => p.runs.map((r) => r.text).join(),
      HeadingBlock h => h.runs.map((r) => r.text).join(),
      _ => '',
    };
  }

  /// The live selection's character range within block [index], or null when
  /// the block isn't part of it. Drives the selection wash.
  ({int start, int end})? selectionRangeFor(int index) {
    final sel = _selection;
    if (sel == null || index < sel.startBlock || index > sel.endBlock) {
      return null;
    }
    return (
      start: index == sel.startBlock ? sel.startChar : 0,
      end: index == sel.endBlock ? sel.endChar : blockText(index).length,
    );
  }

  String get selectedText {
    final sel = _selection;
    if (sel == null) return '';
    if (sel.startBlock == sel.endBlock) {
      final t = blockText(sel.startBlock);
      return t.substring(
        sel.startChar.clamp(0, t.length),
        sel.endChar.clamp(0, t.length),
      );
    }
    final buf = StringBuffer();
    for (var b = sel.startBlock; b <= sel.endBlock; b++) {
      final t = blockText(b);
      final s = b == sel.startBlock ? sel.startChar.clamp(0, t.length) : 0;
      final e = b == sel.endBlock ? sel.endChar.clamp(0, t.length) : t.length;
      buf.write(t.substring(s, e));
      if (b != sel.endBlock) buf.write('\n\n');
    }
    return buf.toString();
  }

  // ── actions ─────────────────────────────────────────────────────────────

  void copySelection() {
    final text = selectedText;
    clearSelection();
    if (text.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied')));
    // Fire-and-forget: the clipboard write shouldn't block dismissal.
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  void defineSelection() {
    final text = selectedText.trim();
    clearSelection();
    if (text.isEmpty) return;
    // A phrase resolves to its first word for the dictionary.
    DictionaryService().define(text.split(RegExp(r'\s+')).first);
  }

  /// Builds a range-highlight bookmark from the current selection, or null if
  /// there's nothing selected.
  Bookmark? _selectionBookmark(HighlightColor color) {
    final sel = _selection;
    final book = currentBook;
    if (sel == null || book == null) return null;
    final text = selectedText;
    return Bookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      chapterIndex: currentChapterIndex,
      blockIndex: sel.startBlock,
      endBlockIndex: sel.endBlock == sel.startBlock ? null : sel.endBlock,
      chapterTitle: book.chapters[currentChapterIndex].title,
      snippet: shortSnippet(text),
      createdAt: DateTime.now(),
      isHighlight: true,
      color: color,
      startChar: sel.startChar,
      endChar: sel.endChar,
      selectedText: text,
    );
  }

  Future<void> highlightSelection(HighlightColor color) async {
    final mark = _selectionBookmark(color);
    if (mark == null) return;
    await BookmarkStore().add(readerVolume, mark);
    clearSelection();
    await refreshHighlights();
    hapticSelection();
  }

  /// Highlights the selection and immediately opens a note editor for it.
  Future<void> noteSelection() async {
    final mark = _selectionBookmark(HighlightColor.yellow);
    if (mark == null) return;
    await BookmarkStore().add(readerVolume, mark);
    clearSelection();
    await refreshHighlights();
    hapticSelection();
    // add() upserts by id, so the note attaches to the highlight just saved.
    if (mounted) await addNoteToBookmark(mark);
  }

  // ── action bar ──────────────────────────────────────────────────────────

  /// The action bar shown above an active selection: copy, define, note, and
  /// the four highlight colours.
  Widget selectionToolbar(ReaderThemePreset preset) {
    return Material(
      color: preset.background.withValues(alpha: 0.98),
      elevation: 4,
      shape: StadiumBorder(
        side: BorderSide(color: preset.text.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _selAction(preset, Icons.copy_outlined, 'Copy', copySelection),
            _selAction(
              preset,
              Icons.menu_book_outlined,
              'Define',
              defineSelection,
            ),
            _selAction(preset, Icons.note_alt_outlined, 'Note', noteSelection),
            const SizedBox(width: 2),
            for (final c in HighlightColor.values) _selHighlightDot(preset, c),
          ],
        ),
      ),
    );
  }

  Widget _selAction(
    ReaderThemePreset preset,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: preset.text.withValues(alpha: 0.8)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: preset.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selHighlightDot(ReaderThemePreset preset, HighlightColor c) {
    return InkWell(
      key: ValueKey(c),
      customBorder: const CircleBorder(),
      onTap: () => highlightSelection(c),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: highlightPaintFor(c),
            shape: BoxShape.circle,
            border: Border.all(color: preset.text.withValues(alpha: 0.3)),
          ),
        ),
      ),
    );
  }
}
