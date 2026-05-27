import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/bookmark.dart';
import '../models/content_block.dart';
import '../models/epub_book.dart';
import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../models/volume.dart';
import '../services/bookmark_store.dart';
import '../services/epub_parser.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/now_playing_service.dart';
import '../services/reader_preferences.dart';
import '../services/reading_activity_store.dart';
import '../services/reading_progress_store.dart';
import '../services/tts_service.dart';
import '../widgets/reader_settings_sheet.dart';
import 'highlights_screen.dart';

// Layout constants — shared by rendering and pagination so the two agree.
const double _contentVPad = 8;
const double _topBarHeight = 56;
const double _bottomBarHeight = 56;
const double _paragraphGap = 16;
const double _headingTopGap = 12;
const double _headingBottomGap = 16;
const double _dividerHeight = 60;

/// Sentinel for "jump to the last page" when paging backward into a chapter.
const int _lastPage = -1;

/// Body text style for the active settings.
TextStyle _paragraphStyle(ReaderSettings s, Color color) {
  final base = TextStyle(
    fontSize: s.fontSize,
    height: s.lineHeight,
    color: color,
    fontWeight: s.boldText ? FontWeight.bold : null,
    fontStyle: s.italicText ? FontStyle.italic : null,
  );
  return s.fontFamily.isEmpty
      ? base
      : GoogleFonts.getFont(s.fontFamily, textStyle: base);
}

/// Heading style — sized relative to the body text.
TextStyle _headingStyle(ReaderSettings s, int level, Color color) {
  final scale = level <= 2
      ? 1.35
      : level <= 4
      ? 1.18
      : 1.06;
  final base = TextStyle(
    fontSize: s.fontSize * scale,
    height: 1.3,
    fontWeight: FontWeight.w700,
    fontStyle: s.italicText ? FontStyle.italic : null,
    color: color,
  );
  return s.fontFamily.isEmpty
      ? base
      : GoogleFonts.getFont(s.fontFamily, textStyle: base);
}

/// Builds a styled [TextSpan] for a run list, applying bold/italic per run.
TextSpan _runSpan(List<TextRun> runs, TextStyle base) {
  return TextSpan(
    children: [
      for (final run in runs)
        TextSpan(
          text: run.text,
          style: base.copyWith(
            fontWeight: run.bold ? FontWeight.bold : null,
            fontStyle: run.italic ? FontStyle.italic : null,
          ),
        ),
    ],
  );
}

/// Measures the rendered height of a block at [width] — used for pagination.
double _measureBlockHeight(ContentBlock block, double width, ReaderSettings s) {
  switch (block) {
    case ParagraphBlock paragraph:
      final painter = TextPainter(
        text: _runSpan(
          paragraph.runs,
          _paragraphStyle(s, const Color(0xFF000000)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: width);
      return painter.height + _paragraphGap;
    case HeadingBlock heading:
      final painter = TextPainter(
        text: _runSpan(
          heading.runs,
          _headingStyle(s, heading.level, const Color(0xFF000000)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: width);
      return painter.height + _headingTopGap + _headingBottomGap;
    case DividerBlock _:
      return _dividerHeight;
    case ImageBlock image:
      // Scale the image to the column width and preserve its aspect ratio,
      // capping height at 80% of a reasonable page so a tall illustration
      // doesn't push everything else off the page in scroll mode.
      final natural = image.width <= 0 ? 1 : image.width;
      final aspect = image.height / natural;
      final scaledHeight = (width * aspect).clamp(80.0, 900.0);
      return scaledHeight + _paragraphGap;
  }
}

/// One renderable slice on a page.
///
/// For a whole block, [block] is the original block and [charOffset] is 0.
/// For a paragraph split across pages, [block] is a [ParagraphBlock] holding
/// only that slice's runs, [originIndex] points back to the parent block in
/// the chapter's block list, and [charOffset] is where the slice's text
/// begins within the parent paragraph.
class _PageBlock {
  const _PageBlock({
    required this.block,
    required this.originIndex,
    this.charOffset = 0,
  });

  final ContentBlock block;
  final int originIndex;
  final int charOffset;
}

/// Total character length of a run list.
int _runsLength(List<TextRun> runs) {
  var total = 0;
  for (final run in runs) {
    total += run.text.length;
  }
  return total;
}

/// Lays out a paragraph's runs at [width] for measurement.
TextPainter _layoutParagraph(
  List<TextRun> runs,
  double width,
  ReaderSettings s,
) {
  return TextPainter(
    text: _runSpan(runs, _paragraphStyle(s, const Color(0xFF000000))),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: width);
}

/// Splits a run list into the runs before [offset] and the runs from [offset]
/// onward, cutting a straddling run in two. Character-exact: the two halves
/// concatenated equal the input.
(List<TextRun>, List<TextRun>) _splitRuns(List<TextRun> runs, int offset) {
  final head = <TextRun>[];
  final tail = <TextRun>[];
  var pos = 0;
  for (final run in runs) {
    final start = pos;
    final end = pos + run.text.length;
    pos = end;
    if (end <= offset) {
      head.add(run);
    } else if (start >= offset) {
      tail.add(run);
    } else {
      final cut = offset - start;
      head.add(
        TextRun(run.text.substring(0, cut), bold: run.bold, italic: run.italic),
      );
      tail.add(
        TextRun(run.text.substring(cut), bold: run.bold, italic: run.italic),
      );
    }
  }
  return (head, tail);
}

/// Character offset at which the line centred on [centreY] begins.
int _lineStartOffsetAt(TextPainter painter, double centreY) {
  final pos = painter.getPositionForOffset(Offset(1, centreY));
  return painter.getLineBoundary(pos).start;
}

/// Packs blocks into pages, splitting a paragraph across a page boundary when
/// it doesn't fully fit — so every page bar a chapter's last fills close to
/// the bottom. Headings and dividers are never split.
List<List<_PageBlock>> _paginate(
  List<ContentBlock> blocks,
  double width,
  double height,
  ReaderSettings settings,
) {
  final budget = height;
  final pages = <List<_PageBlock>>[];
  var current = <_PageBlock>[];
  var used = 0.0;

  void flush() {
    if (current.isNotEmpty) {
      pages.add(current);
      current = <_PageBlock>[];
      used = 0;
    }
  }

  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];

    if (block is! ParagraphBlock) {
      final h = _measureBlockHeight(block, width, settings);
      if (current.isNotEmpty && used + h > budget) flush();
      current.add(_PageBlock(block: block, originIndex: i));
      used += h;
      continue;
    }

    // A paragraph: placed whole, or split across one or more page breaks.
    var runs = block.runs;
    var charBase = 0;
    while (true) {
      final painter = _layoutParagraph(runs, width, settings);
      final lines = painter.computeLineMetrics();
      if (lines.isEmpty) break;
      final totalText = painter.height;
      final remaining = budget - used;

      if (totalText + _paragraphGap <= remaining) {
        current.add(
          _PageBlock(
            block: ParagraphBlock(runs),
            originIndex: i,
            charOffset: charBase,
          ),
        );
        used += totalText + _paragraphGap;
        break;
      }

      // How many whole lines fit in the space left on this page?
      var fitHeight = 0.0;
      var fitLines = 0;
      for (final line in lines) {
        if (fitHeight + line.height > remaining) break;
        fitHeight += line.height;
        fitLines++;
      }

      if (fitLines == 0) {
        if (used == 0) {
          // A single line taller than the whole page — place it regardless.
          fitLines = 1;
          fitHeight = lines.first.height;
        } else {
          flush();
          continue;
        }
      }

      if (fitLines >= lines.length) {
        // All the lines fit; only the trailing gap didn't — place gapless.
        current.add(
          _PageBlock(
            block: ParagraphBlock(runs),
            originIndex: i,
            charOffset: charBase,
          ),
        );
        used += totalText;
        break;
      }

      // Split after the last line that fits.
      final centreY = fitHeight + lines[fitLines].height / 2;
      final splitOffset = _lineStartOffsetAt(painter, centreY);
      if (splitOffset <= 0 || splitOffset >= _runsLength(runs)) {
        // No usable split point — move the whole fragment to a fresh page.
        if (used == 0) {
          current.add(
            _PageBlock(
              block: ParagraphBlock(runs),
              originIndex: i,
              charOffset: charBase,
            ),
          );
          used += totalText + _paragraphGap;
          break;
        }
        flush();
        continue;
      }
      final parts = _splitRuns(runs, splitOffset);
      current.add(
        _PageBlock(
          block: ParagraphBlock(parts.$1),
          originIndex: i,
          charOffset: charBase,
        ),
      );
      used += fitHeight;
      flush();
      runs = parts.$2;
      charBase += splitOffset;
    }
  }

  flush();
  if (pages.isEmpty) pages.add(<_PageBlock>[]);
  return pages;
}

/// Reads a downloaded volume: parses the EPUB and renders its chapters, with
/// scroll or paged layout, an immersive (fade-away) chrome, a colour-theme /
/// typography engine, chapter navigation and keyboard/remote support.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.volume});

  final Volume volume;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final _progressStore = ReadingProgressStore();
  final _scrollController = ScrollController();
  final _pageController = PageController();
  final _ttsService = TtsService();
  final _nowPlaying = NowPlayingService();

  EpubParser? _parser;
  EpubBook? _book;
  int _chapterIndex = 0;
  List<ContentBlock>? _blocks;
  bool _loading = true;
  String? _error;

  ReaderSettings _settings = ReaderSettings.defaults;
  bool _chromeVisible = true;

  // Paged-mode pagination cache.
  List<List<_PageBlock>>? _pages;
  String? _pageKey;
  int _pageJumpTarget = 0;

  /// Bumped when a web font finishes loading, to force re-pagination with the
  /// now-correct metrics.
  int _fontToken = 0;

  /// Peak distance the drag travelled past a content edge (signed: positive
  /// past the end, negative past the start) — used to cross chapters.
  double _edgeOverscroll = 0;

  /// When the last chapter change happened. Edge-crossing is suppressed for a
  /// short window afterward so the scrollable settling into the new chapter
  /// can't trigger a second (skipped-chapter) cross.
  DateTime _lastChapterChange = DateTime.fromMillisecondsSinceEpoch(0);

  /// Block index to restore to on open; consumed once the content lays out.
  int? _pendingRestoreBlock;

  /// Content width (screen minus margins), cached each build so progress can
  /// be measured without a MediaQuery lookup (e.g. during dispose).
  double _lastContentWidth = 0;

  /// The block currently being read aloud, and the character range of the
  /// active sentence within it. Null when read-aloud is stopped.
  int? _speakingBlock;
  int _speakingStart = 0;
  int _speakingEnd = 0;

  /// Maps a TTS chunk index back to its block index in `_blocks`.
  List<int> _ttsBlockForChunk = const [];

  /// Last block that auto-follow moved to — so it only moves on a change.
  int _followedBlock = -1;

  /// Last page that read-aloud auto-follow turned to (paged mode).
  int _followedPage = -1;

  /// Active sleep-timer choice and its countdown.
  SleepTimerOption _sleepOption = SleepTimerOption.off;
  Timer? _sleepTimer;

  /// Periodic timer driving the hands-free auto-scroll, when enabled.
  Timer? _autoScrollTimer;

  /// Block indices in the current chapter that have been highlighted,
  /// mapped to the color the user chose so the renderer can paint each
  /// passage with its own tint.
  Map<int, HighlightColor> _highlightedBlocks = const {};

  /// True once the end-of-volume prompt has fired this session, so the
  /// dialog doesn't reappear every time the user re-taps "next" from the
  /// last page.
  bool _endOfVolumePrompted = false;

  /// Persists per-day and per-volume reading-time totals.
  final _activityStore = ReadingActivityStore();

  /// When the current foreground reading session started; null when paused.
  DateTime? _sessionStart;

  /// Progress through the current chapter (0..1) and its total word count —
  /// drive the reading-progress bar and the "time left" estimate.
  double _chapterFraction = 0;
  int _chapterWordCount = 0;

  /// Word count per chapter, populated lazily as chapters are visited.
  /// Used to estimate how long is left in the *book* — the unmeasured
  /// chapters get the running average from what's been seen.
  final Map<int, int> _chapterWordCounts = {};

  @override
  void initState() {
    super.initState();
    _ttsService.onStateChanged = (state) {
      _updateNowPlaying();
      if (!mounted) return;
      setState(() {
        if (state == TtsPlaybackState.stopped) {
          _speakingBlock = null;
          _followedBlock = -1;
          _followedPage = -1;
        }
      });
    };
    _ttsService.onWord = _onTtsWord;
    _ttsService.onChapterFinished = _onTtsChapterFinished;
    _nowPlaying.onPlay = _remotePlay;
    _nowPlaying.onPause = _remotePause;
    _nowPlaying.onToggle = _toggleTts;
    _nowPlaying.onNext = () => _remoteSkipChapter(1);
    _nowPlaying.onPrevious = () => _remoteSkipChapter(-1);
    _scrollController.addListener(_onPositionTick);
    _pageController.addListener(_onPositionTick);
    WidgetsBinding.instance.addObserver(this);
    _sessionStart = DateTime.now();
    _open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sessionStart ??= DateTime.now();
    } else {
      _flushReadingSession();
    }
  }

  /// Records the time spent in the foreground reader since the last flush.
  void _flushReadingSession() {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;
    final delta = DateTime.now().difference(start);
    if (delta.inSeconds <= 0) return;
    // Fire-and-forget — losing the last fractional second on an app kill is
    // acceptable.
    _activityStore.record(widget.volume, delta);
  }

  @override
  void dispose() {
    _saveProgress();
    _flushReadingSession();
    WidgetsBinding.instance.removeObserver(this);
    _sleepTimer?.cancel();
    _autoScrollTimer?.cancel();
    _nowPlaying.clear();
    _nowPlaying.dispose();
    _ttsService.dispose();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final settings = await ReaderPreferences().load();
    await _preloadFont(settings.fontFamily);
    try {
      final file = await LibraryStorage().epubFile(widget.volume);
      if (!file.existsSync()) {
        _fail('This volume is not downloaded.');
        return;
      }
      final parser = EpubParser();
      final book = await parser.open(file);
      if (book.chapters.isEmpty) {
        _fail('No readable chapters were found in this book.');
        return;
      }
      final progress = await _progressStore.load(widget.volume);
      final chapterIndex = progress.chapterIndex.clamp(
        0,
        book.chapters.length - 1,
      );
      final blocks = parser.parseChapter(book.chapters[chapterIndex]);
      if (!mounted) return;
      setState(() {
        _parser = parser;
        _book = book;
        _chapterIndex = chapterIndex;
        _blocks = blocks;
        _chapterWordCount = _countWords(blocks);
        _chapterWordCounts[_chapterIndex] = _chapterWordCount;
        _settings = settings;
        _pendingRestoreBlock = blocks.isEmpty
            ? 0
            : progress.blockIndex.clamp(0, blocks.length - 1);
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollPosition();
        if (_settings.autoScroll) _startAutoScroll();
      });
      _refreshHighlights();
    } on EpubException catch (e) {
      _fail(e.message);
    }
  }

  Future<void> _preloadFont(String family) async {
    if (family.isEmpty) return;
    try {
      GoogleFonts.getFont(family);
      await GoogleFonts.pendingFonts();
    } on Exception {
      // Offline or fetch failed — the font falls back gracefully.
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  void _goToChapter(
    int index, {
    bool landOnLastPage = false,
    bool fromTts = false,
  }) {
    final book = _book;
    final parser = _parser;
    if (book == null || parser == null) return;
    // Advancing past the final chapter is the natural "I finished this volume"
    // moment — surface the next volume in the series rather than silently
    // pinning the user on the last page.
    if (index > book.chapters.length - 1 &&
        _chapterIndex == book.chapters.length - 1) {
      if (!_endOfVolumePrompted) {
        _endOfVolumePrompted = true;
        _maybeShowEndOfVolumePrompt();
      }
      return;
    }
    final clamped = index.clamp(0, book.chapters.length - 1);
    if (clamped == _chapterIndex && _blocks != null) return;
    // A manual chapter change stops read-aloud; a TTS-driven advance keeps it.
    if (!fromTts) _ttsService.stop();
    _lastChapterChange = DateTime.now();
    _edgeOverscroll = 0;
    final blocks = parser.parseChapter(book.chapters[clamped]);
    setState(() {
      _chapterIndex = clamped;
      _blocks = blocks;
      _chapterWordCount = _countWords(blocks);
      _chapterFraction = 0;
      _pageKey = null;
      _pageJumpTarget = landOnLastPage ? _lastPage : 0;
    });
    _progressStore.save(
      widget.volume,
      ReadingProgress(
        chapterIndex: clamped,
        blockIndex: 0,
        chapterCount: book.chapters.length,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_settings.mode == ReadingMode.scroll && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
    _refreshHighlights();
  }

  /// Pops a dialog at the end of the volume offering the next one in the
  /// series, if it's available in the cached volume list (downloaded or
  /// not — undownloaded ones bounce to the series screen so the user can
  /// download from there).
  Future<void> _maybeShowEndOfVolumePrompt() async {
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    final volumes = cache.volumesFor(widget.volume.seriesOpdsId);
    if (volumes == null || volumes.isEmpty) return;
    final currentIdx = volumes.indexWhere(
      (v) => v.fileName == widget.volume.fileName,
    );
    if (currentIdx < 0 || currentIdx >= volumes.length - 1) return;
    final next = volumes[currentIdx + 1];
    final downloaded = await LibraryStorage().epubFile(next).then(
          (f) => f.existsSync(),
        );
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('You finished this volume'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Next up:',
              style: Theme.of(dialogCtx).textTheme.labelSmall?.copyWith(
                color: Theme.of(dialogCtx).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              next.title,
              style: Theme.of(dialogCtx).textTheme.titleMedium,
            ),
            if (!downloaded) ...[
              const SizedBox(height: 8),
              Text(
                'Not downloaded yet — opening the series page lets you grab it.',
                style: Theme.of(dialogCtx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(dialogCtx).colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop('stay'),
            child: const Text('Stay here'),
          ),
          if (downloaded)
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop('open'),
              child: const Text('Open next'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop('series'),
              child: const Text('Open series'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'open':
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ReaderScreen(volume: next)),
        );
      case 'series':
      // Drop the reader and let the user re-enter the series from the
      // library — series detail requires the Series object we don't have.
        Navigator.of(context).pop();
      case 'stay':
      case null:
        break;
    }
  }

  // ── reading-position memory ──────────────────────────────────────────────

  /// Cumulative pixel offset of [blockIndex] in scroll mode.
  double _blockOffset(int blockIndex) {
    final blocks = _blocks ?? const <ContentBlock>[];
    var offset = _contentVPad;
    for (var i = 0; i < blockIndex && i < blocks.length; i++) {
      offset += _measureBlockHeight(blocks[i], _lastContentWidth, _settings);
    }
    return offset;
  }

  /// Index of the block at the top of the viewport in scroll mode.
  int _scrollTopBlockIndex() {
    final blocks = _blocks ?? const <ContentBlock>[];
    if (blocks.isEmpty || !_scrollController.hasClients) return 0;
    final target = _scrollController.offset;
    var acc = _contentVPad;
    for (var i = 0; i < blocks.length; i++) {
      acc += _measureBlockHeight(blocks[i], _lastContentWidth, _settings);
      if (acc > target) return i;
    }
    return blocks.length - 1;
  }

  /// Index of the first block on the current page in paged mode.
  int _pagedTopBlockIndex() {
    final pages = _pages;
    if (pages == null || pages.isEmpty || !_pageController.hasClients) return 0;
    final page = (_pageController.page?.round() ?? 0).clamp(
      0,
      pages.length - 1,
    );
    final pageBlocks = pages[page];
    return pageBlocks.isEmpty ? 0 : pageBlocks.first.originIndex;
  }

  /// The first page that shows any part of [blockIndex] in paged mode.
  int _pageForBlock(int blockIndex) {
    final pages = _pages ?? const <List<_PageBlock>>[];
    for (var i = 0; i < pages.length; i++) {
      for (final pb in pages[i]) {
        if (pb.originIndex == blockIndex) return i;
      }
    }
    return pages.isEmpty ? 0 : pages.length - 1;
  }

  /// The page showing block [blockIndex] at character [charOffset] — so
  /// read-aloud follow stays correct for a paragraph that spans pages.
  int _pageForBlockAt(int blockIndex, int charOffset) {
    final pages = _pages ?? const <List<_PageBlock>>[];
    var firstPage = -1;
    for (var i = 0; i < pages.length; i++) {
      for (final pb in pages[i]) {
        if (pb.originIndex != blockIndex) continue;
        if (firstPage < 0) firstPage = i;
        final length = pb.block is ParagraphBlock
            ? _runsLength((pb.block as ParagraphBlock).runs)
            : 0;
        if (charOffset >= pb.charOffset &&
            charOffset < pb.charOffset + length) {
          return i;
        }
      }
    }
    if (firstPage >= 0) return firstPage;
    return pages.isEmpty ? 0 : pages.length - 1;
  }

  void _saveProgress() {
    // Skip if the position can't be read (e.g. controllers already detached
    // during dispose) — saving a fallback 0 would clobber the real position.
    final int block;
    if (_settings.mode == ReadingMode.paged) {
      if (!_pageController.hasClients) return;
      block = _pagedTopBlockIndex();
    } else {
      if (!_scrollController.hasClients) return;
      block = _scrollTopBlockIndex();
    }
    _progressStore.save(
      widget.volume,
      ReadingProgress(
        chapterIndex: _chapterIndex,
        blockIndex: block,
        chapterCount: _book?.chapters.length ?? 0,
      ),
    );
  }

  // ── in-chapter progress ──────────────────────────────────────────────────

  /// Recomputes how far through the current chapter the reader is, refreshing
  /// the progress bar / time estimate when it moves by at least half a percent.
  void _onPositionTick() {
    final fraction = _computeChapterFraction();
    if ((fraction * 200).round() != (_chapterFraction * 200).round()) {
      setState(() => _chapterFraction = fraction);
    }
  }

  /// Fraction (0..1) of the current chapter that has been read.
  double _computeChapterFraction() {
    if (_settings.mode == ReadingMode.paged) {
      final pages = _pages;
      if (pages == null || pages.length <= 1 || !_pageController.hasClients) {
        return 0;
      }
      return ((_pageController.page ?? 0) / (pages.length - 1)).clamp(0.0, 1.0);
    }
    if (!_scrollController.hasClients) return 0;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return 0;
    return (_scrollController.offset / max).clamp(0.0, 1.0);
  }

  /// Total word count of a chapter's blocks, for the time-left estimate.
  int _countWords(List<ContentBlock> blocks) {
    var words = 0;
    for (final block in blocks) {
      for (final word in _blockText(block).split(RegExp(r'\s+'))) {
        if (word.isNotEmpty) words++;
      }
    }
    return words;
  }

  /// Estimated reading time left in the whole book, in minutes. Combines the
  /// remaining part of the current chapter with the running average word
  /// count of measured chapters multiplied by the unread chapter count.
  /// Returns null until at least one chapter has been measured (i.e. always
  /// available once the reader has rendered anything).
  double? _estimateBookMinutesLeft(EpubBook book) {
    if (_chapterWordCounts.isEmpty) return null;
    final measured = _chapterWordCounts.values;
    final avg = measured.reduce((a, b) => a + b) / measured.length;
    final remainingChapters = book.chapters.length - _chapterIndex - 1;
    final currentLeft = _chapterWordCount * (1 - _chapterFraction);
    final unreadWords = currentLeft + (remainingChapters * avg);
    return unreadWords / 220.0;
  }

  /// Restores the saved scroll-mode position once the list has laid out.
  /// (Paged-mode restore is handled when pages are computed in `_buildPaged`.)
  void _restoreScrollPosition() {
    final block = _pendingRestoreBlock;
    if (block == null || _settings.mode != ReadingMode.scroll) return;
    if (!_scrollController.hasClients) return;
    _pendingRestoreBlock = null;
    _scrollController.jumpTo(
      _blockOffset(block).clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  void _toggleChrome() {
    // Remember the page so paged mode lands back on it after the content
    // area resizes (and re-paginates) for the new chrome visibility.
    final currentPage = _pageController.hasClients
        ? (_pageController.page?.round() ?? 0)
        : 0;
    setState(() {
      _chromeVisible = !_chromeVisible;
      _pageJumpTarget = currentPage;
    });
  }

  /// Routes a tap on the page: the left and right edges turn the page, while
  /// the centre toggles the reading chrome.
  void _onContentTap(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    if (x < width * 0.28) {
      _advance(forward: false);
    } else if (x > width * 0.72) {
      _advance(forward: true);
    } else {
      _toggleChrome();
    }
  }

  Future<void> _applySettings(ReaderSettings next) async {
    final fontChanged = next.fontFamily != _settings.fontFamily;
    final rateChanged = next.speechRate != _settings.speechRate;
    final voiceChanged =
        next.voiceName != _settings.voiceName ||
        next.voiceLocale != _settings.voiceLocale;
    final autoScrollChanged =
        next.autoScroll != _settings.autoScroll ||
        next.mode != _settings.mode;
    final currentPage = _pageController.hasClients
        ? (_pageController.page?.round() ?? 0)
        : 0;
    setState(() {
      _settings = next;
      _pageJumpTarget = currentPage;
    });
    ReaderPreferences().save(next);
    if (rateChanged) _ttsService.setRate(next.speechRate);
    if (voiceChanged) _ttsService.setVoice(next.voiceName, next.voiceLocale);
    if (fontChanged) {
      await _preloadFont(next.fontFamily);
      if (mounted) setState(() => _fontToken++);
    }
    if (autoScrollChanged) {
      if (next.autoScroll && next.mode == ReadingMode.scroll) {
        _startAutoScroll();
      } else {
        _stopAutoScroll();
      }
    }
  }

  // ── read-aloud ───────────────────────────────────────────────────────────

  /// Plain text of a block — exactly the runs as rendered, so TTS word
  /// offsets line up with the on-screen text for highlighting.
  String _blockText(ContentBlock block) => switch (block) {
    ParagraphBlock p => p.runs.map((r) => r.text).join(),
    HeadingBlock h => h.runs.map((r) => r.text).join(),
    DividerBlock _ => '',
    ImageBlock _ => '',
  };

  void _startTts({bool fromCurrentPosition = true}) {
    final blocks = _blocks ?? const <ContentBlock>[];
    final texts = <String>[];
    final blockForChunk = <int>[];
    for (var i = 0; i < blocks.length; i++) {
      final text = _blockText(blocks[i]);
      if (text.trim().isEmpty) continue;
      texts.add(text);
      blockForChunk.add(i);
    }
    if (texts.isEmpty) return;
    // Begin from the paragraph currently in view, not the chapter top.
    var fromChunk = 0;
    if (fromCurrentPosition) {
      final topBlock = _settings.mode == ReadingMode.paged
          ? _pagedTopBlockIndex()
          : _scrollTopBlockIndex();
      fromChunk = blockForChunk.length - 1;
      for (var c = 0; c < blockForChunk.length; c++) {
        if (blockForChunk[c] >= topBlock) {
          fromChunk = c;
          break;
        }
      }
    }
    _ttsBlockForChunk = blockForChunk;
    _followedBlock = -1;
    _followedPage = -1;
    _ttsService.start(
      texts,
      from: fromChunk,
      rate: _settings.speechRate,
      voiceName: _settings.voiceName,
      voiceLocale: _settings.voiceLocale,
    );
  }

  /// Highlights the sentence being read and keeps it on screen.
  void _onTtsWord(int chunkIndex, int start, int end) {
    if (!mounted) return;
    if (chunkIndex < 0 || chunkIndex >= _ttsBlockForChunk.length) return;
    final blockIndex = _ttsBlockForChunk[chunkIndex];
    final blocks = _blocks ?? const <ContentBlock>[];
    if (blockIndex < 0 || blockIndex >= blocks.length) return;
    final range = _sentenceRangeAt(_blockText(blocks[blockIndex]), start);
    setState(() {
      _speakingBlock = blockIndex;
      _speakingStart = range.$1;
      _speakingEnd = range.$2;
    });
    _followSpeaking(blockIndex);
  }

  /// Scrolls/pages so the block being read stays visible — only when the
  /// block changes, so it doesn't fight the reader within a paragraph.
  void _followSpeaking(int blockIndex) {
    if (_settings.mode == ReadingMode.paged) {
      if (!_pageController.hasClients) return;
      // Follow by page (not block) so a paragraph split across pages is
      // tracked as read-aloud moves through it.
      final page = _pageForBlockAt(blockIndex, _speakingStart);
      final currentPage = _pageController.page?.round() ?? 0;
      if (page != currentPage && page != _followedPage) {
        _followedPage = page;
        _pageController.animateToPage(
          page,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      return;
    }
    // Scroll mode: only move when the block changes, so it doesn't fight the
    // reader within a paragraph.
    if (blockIndex == _followedBlock) return;
    _followedBlock = blockIndex;
    if (!_scrollController.hasClients) return;
    final target = (_blockOffset(blockIndex) - 80).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// The character range of the sentence containing [offset] in [text].
  (int, int) _sentenceRangeAt(String text, int offset) {
    if (text.isEmpty) return (0, 0);
    final o = offset.clamp(0, text.length - 1);
    var start = 0;
    for (var i = o - 1; i >= 0; i--) {
      final c = text[i];
      if (c == '.' || c == '!' || c == '?' || c == '\n') {
        start = i + 1;
        break;
      }
    }
    while (start < text.length && text[start] == ' ') {
      start++;
    }
    var end = text.length;
    for (var i = o; i < text.length; i++) {
      final c = text[i];
      if (c == '.' || c == '!' || c == '?' || c == '\n') {
        end = i + 1;
        break;
      }
    }
    return (start, end);
  }

  void _toggleTts() {
    final state = _ttsService.state;
    if (state == TtsPlaybackState.playing) {
      _ttsService.pause();
    } else if (state == TtsPlaybackState.paused) {
      _ttsService.resume(rate: _settings.speechRate);
    } else {
      _startTts();
    }
  }

  /// When read-aloud reaches the end of a chapter, roll into the next one and
  /// keep reading — unless the sleep timer is set to stop at the chapter end.
  void _onTtsChapterFinished() {
    if (_sleepOption == SleepTimerOption.endOfChapter) {
      if (mounted) setState(() => _sleepOption = SleepTimerOption.off);
      return;
    }
    final book = _book;
    if (book == null) return;
    if (_chapterIndex < book.chapters.length - 1) {
      _goToChapter(_chapterIndex + 1, fromTts: true);
      // A TTS-driven advance reads the new chapter from its start.
      _startTts(fromCurrentPosition: false);
    }
  }

  /// Arms (or clears) the read-aloud sleep timer.
  void _setSleepTimer(SleepTimerOption option) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    setState(() => _sleepOption = option);
    final duration = option.duration;
    if (duration != null) {
      _sleepTimer = Timer(duration, () {
        _ttsService.pause();
        if (mounted) setState(() => _sleepOption = SleepTimerOption.off);
      });
    }
  }

  // ── auto-scroll ──────────────────────────────────────────────────────────

  /// Pixels added to the scroll offset on each tick. ~32px/sec at the 50ms
  /// tick rate — a comfortable reading pace; tune later as a slider if
  /// users want it.
  static const double _autoScrollPxPerTick = 1.6;

  /// Starts the auto-scroll timer if the setting is on and the reader is in
  /// scroll mode. No-op otherwise. Safe to call repeatedly — it tears down
  /// any existing timer first.
  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (!_settings.autoScroll) return;
    if (_settings.mode != ReadingMode.scroll) return;
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _autoScrollTick(),
    );
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _autoScrollTick() {
    if (!mounted ||
        !_scrollController.hasClients ||
        !_settings.autoScroll ||
        _settings.mode != ReadingMode.scroll) {
      _stopAutoScroll();
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 1) {
      // End of chapter — pause briefly, then roll into the next one.
      _stopAutoScroll();
      final book = _book;
      if (book != null && _chapterIndex < book.chapters.length - 1) {
        Timer(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          _goToChapter(_chapterIndex + 1);
          _startAutoScroll();
        });
      }
      return;
    }
    _scrollController.jumpTo(
      (pos.pixels + _autoScrollPxPerTick).clamp(0.0, pos.maxScrollExtent),
    );
  }

  // ── lock-screen / Control Center controls ───────────────────────────────

  /// Publishes the current chapter and play state to the iOS lock screen, or
  /// clears it when read-aloud is stopped.
  void _updateNowPlaying() {
    final book = _book;
    if (book == null || _ttsService.state == TtsPlaybackState.stopped) {
      _nowPlaying.clear();
      return;
    }
    final title = (_chapterIndex >= 0 && _chapterIndex < book.chapters.length)
        ? book.chapters[_chapterIndex].title
        : widget.volume.title;
    _nowPlaying.update(
      title: title,
      book: widget.volume.title,
      isPlaying: _ttsService.state == TtsPlaybackState.playing,
    );
  }

  /// Lock-screen "play": resume if paused, otherwise start from the top of
  /// what's on screen.
  void _remotePlay() {
    switch (_ttsService.state) {
      case TtsPlaybackState.paused:
        _ttsService.resume(rate: _settings.speechRate);
      case TtsPlaybackState.stopped:
        _startTts();
      case TtsPlaybackState.playing:
        break;
    }
  }

  /// Lock-screen "pause".
  void _remotePause() {
    if (_ttsService.state == TtsPlaybackState.playing) {
      _ttsService.pause();
    }
  }

  /// Lock-screen next/previous-track: jump a chapter and, if read-aloud was
  /// active, keep reading from the new chapter's start.
  void _remoteSkipChapter(int delta) {
    final book = _book;
    if (book == null) return;
    final target = _chapterIndex + delta;
    if (target < 0 || target >= book.chapters.length) return;
    final wasActive = _ttsService.state != TtsPlaybackState.stopped;
    _goToChapter(target, fromTts: wasActive);
    if (wasActive) _startTts(fromCurrentPosition: false);
  }

  Future<void> _openSettings() async {
    final voices = await _ttsService.availableVoices();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Cap the height so the sheet never fully covers the screen — a scrim
      // strip stays visible (and tappable) above it to get back to the book.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (_) => ReaderSettingsSheet(
        initial: _settings,
        voices: voices,
        sleepOption: _sleepOption,
        onChanged: _applySettings,
        onSleepTimerChanged: _setSleepTimer,
      ),
    );
  }

  // ── bookmarks ────────────────────────────────────────────────────────────

  /// Opens the bookmarks sheet for this volume, and jumps to a chosen
  /// bookmark when one is tapped.
  Future<void> _openBookmarks() async {
    final book = _book;
    final blocks = _blocks;
    if (book == null || blocks == null) return;
    final topBlock = _settings.mode == ReadingMode.paged
        ? _pagedTopBlockIndex()
        : _scrollTopBlockIndex();
    final clampedTop = blocks.isEmpty
        ? 0
        : topBlock.clamp(0, blocks.length - 1);
    final chapterTitle = book.chapters[_chapterIndex].title;
    final snippet = blocks.isEmpty
        ? ''
        : _shortSnippet(_blockText(blocks[clampedTop]));
    final picked = await showModalBottomSheet<Bookmark>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (_) => _BookmarksSheet(
        volume: widget.volume,
        currentChapterIndex: _chapterIndex,
        currentBlockIndex: clampedTop,
        currentChapterTitle: chapterTitle,
        currentSnippet: snippet,
      ),
    );
    // Pick up any highlights the user added in the sheet so they paint
    // immediately on the rendered page.
    await _refreshHighlights();
    if (picked == null || !mounted) return;
    _jumpToSearchHit(picked.chapterIndex, picked.blockIndex);
  }

  /// Re-reads the bookmarks store and rebuilds the per-chapter set of
  /// highlighted block indices.
  Future<void> _refreshHighlights() async {
    final all = await BookmarkStore().list(widget.volume);
    if (!mounted) return;
    setState(() {
      _highlightedBlocks = {
        for (final mark in all)
          if (mark.isHighlight && mark.chapterIndex == _chapterIndex)
            mark.blockIndex: mark.color,
      };
    });
  }

  /// Trims a block's text to a short, single-line preview for bookmarks /
  /// search snippets.
  String _shortSnippet(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 80) return flat;
    return '${flat.substring(0, 77)}…';
  }

  // ── in-book search ───────────────────────────────────────────────────────

  /// Opens the full-text search screen and jumps to the chosen result.
  Future<void> _openSearch() async {
    final parser = _parser;
    final book = _book;
    if (parser == null || book == null) return;
    final hit = await Navigator.of(context).push<_SearchHit>(
      MaterialPageRoute(
        builder: (_) => _BookSearchScreen(
          parser: parser,
          book: book,
          plainText: _blockText,
        ),
      ),
    );
    if (hit == null || !mounted) return;
    _jumpToSearchHit(hit.chapterIndex, hit.blockIndex);
  }

  /// Navigates to a search hit: loads its chapter, then lands on its block.
  void _jumpToSearchHit(int chapterIndex, int blockIndex) {
    final book = _book;
    final parser = _parser;
    if (book == null || parser == null) return;
    final clamped = chapterIndex.clamp(0, book.chapters.length - 1);
    _ttsService.stop();
    _lastChapterChange = DateTime.now();
    _edgeOverscroll = 0;
    final blocks = (clamped == _chapterIndex && _blocks != null)
        ? _blocks!
        : parser.parseChapter(book.chapters[clamped]);
    final targetBlock = blocks.isEmpty
        ? 0
        : blockIndex.clamp(0, blocks.length - 1);
    setState(() {
      _chapterIndex = clamped;
      _blocks = blocks;
      _chapterWordCount = _countWords(blocks);
      _chapterFraction = 0;
      _pageKey = null;
      _pendingRestoreBlock = targetBlock;
      _pageJumpTarget = 0;
    });
    _progressStore.save(
      widget.volume,
      ReadingProgress(
        chapterIndex: clamped,
        blockIndex: targetBlock,
        chapterCount: book.chapters.length,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_settings.mode == ReadingMode.scroll) _restoreScrollPosition();
    });
    _refreshHighlights();
  }

  // ── navigation ───────────────────────────────────────────────────────────

  /// Crosses into the adjacent chapter when the reader is swiped/scrolled
  /// firmly past its first or last page.
  bool _onScrollNotification(ScrollNotification notification) {
    // Paged mode scrolls horizontally; scroll mode vertically. Ignore the
    // other axis (e.g. an over-tall page's own vertical scroll view).
    final wantAxis = _settings.mode == ReadingMode.paged
        ? Axis.horizontal
        : Axis.vertical;
    if (notification.metrics.axis != wantAxis) return false;

    // Suppress crossing while a just-changed chapter settles in — the
    // scrollable is transiently out of bounds and would otherwise re-trigger.
    if (DateTime.now().difference(_lastChapterChange) <
        const Duration(milliseconds: 600)) {
      _edgeOverscroll = 0;
      return false;
    }

    if (notification is ScrollStartNotification) {
      _edgeOverscroll = 0;
      return false;
    }

    // iOS bouncing physics moves the position *past* the extent rather than
    // emitting OverscrollNotifications, so watch the metrics directly and
    // record how far past either edge the drag travelled.
    final m = notification.metrics;
    final pastEnd = m.pixels - m.maxScrollExtent;
    final pastStart = m.pixels - m.minScrollExtent;
    if (pastEnd > 0 && pastEnd > _edgeOverscroll) {
      _edgeOverscroll = pastEnd;
    }
    if (pastStart < 0 && pastStart < _edgeOverscroll) {
      _edgeOverscroll = pastStart;
    }

    if (notification is ScrollEndNotification) {
      final amount = _edgeOverscroll;
      _edgeOverscroll = 0;
      if (amount > 90) {
        _goToChapter(_chapterIndex + 1);
      } else if (amount < -90) {
        _goToChapter(_chapterIndex - 1, landOnLastPage: true);
      } else {
        // Settled within the chapter — record the reading position.
        _saveProgress();
      }
    }
    return false;
  }

  /// Jumps to [fraction] (0..1) within the current chapter — driven by the
  /// scrubber overlay on the chapter bar.
  void _seekChapter(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    if (_settings.mode == ReadingMode.paged) {
      final pages = _pages;
      if (pages == null || pages.isEmpty || !_pageController.hasClients) {
        return;
      }
      final target =
          (clamped * (pages.length - 1)).round().clamp(0, pages.length - 1);
      _pageController.jumpToPage(target);
    } else {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      _scrollController.jumpTo(clamped * pos.maxScrollExtent);
    }
    // Update the displayed fraction immediately so the bar tracks the
    // drag, even before the scroll listener catches up.
    setState(() => _chapterFraction = clamped);
  }

  void _advance({required bool forward}) {
    if (_settings.mode == ReadingMode.paged) {
      final pages = _pages ?? const [];
      final current =
          (_pageController.hasClients ? _pageController.page : 0)?.round() ?? 0;
      if (forward) {
        if (current < pages.length - 1) {
          HapticFeedback.lightImpact();
          _pageController.nextPage(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } else {
          HapticFeedback.mediumImpact();
          _goToChapter(_chapterIndex + 1);
        }
      } else {
        if (current > 0) {
          HapticFeedback.lightImpact();
          _pageController.previousPage(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } else {
          HapticFeedback.mediumImpact();
          _goToChapter(_chapterIndex - 1, landOnLastPage: true);
        }
      }
      return;
    }
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final step = pos.viewportDimension * 0.85;
    if (forward) {
      if (pos.pixels >= pos.maxScrollExtent - 4) {
        HapticFeedback.mediumImpact();
        _goToChapter(_chapterIndex + 1);
      } else {
        HapticFeedback.lightImpact();
        _scrollController.animateTo(
          (pos.pixels + step).clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } else {
      if (pos.pixels <= 4) {
        HapticFeedback.mediumImpact();
        _goToChapter(_chapterIndex - 1);
      } else {
        HapticFeedback.lightImpact();
        _scrollController.animateTo(
          (pos.pixels - step).clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final forwardKeys = {
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
    };
    final backwardKeys = {
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.pageUp,
    };
    if (forwardKeys.contains(key)) {
      _advance(forward: true);
      return KeyEventResult.handled;
    }
    if (backwardKeys.contains(key)) {
      _advance(forward: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showTableOfContents() {
    final book = _book;
    if (book == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Contents',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Fixed-height rows so we can scroll the current chapter
                    // into view on open without measuring each tile. The
                    // initial offset positions the current chapter roughly a
                    // third of the way down the viewport.
                    const rowHeight = 64.0;
                    final maxOffset =
                        (book.chapters.length * rowHeight - constraints.maxHeight)
                            .clamp(0.0, double.infinity);
                    final target =
                        (_chapterIndex * rowHeight - constraints.maxHeight / 3)
                            .clamp(0.0, maxOffset);
                    return ListView.builder(
                      controller: ScrollController(initialScrollOffset: target),
                      itemCount: book.chapters.length,
                      itemExtent: rowHeight,
                      itemBuilder: (context, index) {
                        final chapter = book.chapters[index];
                        final current = index == _chapterIndex;
                        return ListTile(
                          selected: current,
                          leading: current
                              ? const Icon(Icons.play_arrow)
                              : const SizedBox(width: 24),
                          title: Text(
                            chapter.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            _goToChapter(index);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 56,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    final book = _book!;
    final preset = _settings.theme;
    final mq = MediaQuery.of(context);
    _lastContentWidth = mq.size.width - 2 * _settings.margin;
    final topSpace = mq.padding.top + _topBarHeight;
    final bottomSpace = mq.padding.bottom + _bottomBarHeight;
    // When the chrome is visible, the content sits between the bars. When it's
    // hidden (immersive reading), the content expands to the full screen,
    // clearing only the notch / home-indicator safe area.
    final contentPadding = _chromeVisible
        ? EdgeInsets.only(top: topSpace, bottom: bottomSpace)
        : EdgeInsets.only(
            top: mq.padding.top + 8,
            bottom: mq.padding.bottom + 8,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: preset.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: preset.background,
        body: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: GestureDetector(
            onTapUp: _onContentTap,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: contentPadding,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: _settings.mode == ReadingMode.paged
                          ? _buildPaged(preset)
                          : _buildScroll(preset),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _fadeChrome(
                    _TopBar(
                      height: topSpace,
                      title: book.chapters[_chapterIndex].title,
                      preset: preset,
                      ttsState: _ttsService.state,
                      onBack: () => Navigator.of(context).pop(),
                      onToggleTts: _toggleTts,
                      onOpenSettings: _openSettings,
                      onShowContents: _showTableOfContents,
                      onSearch: _openSearch,
                      onBookmarks: _openBookmarks,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _fadeChrome(
                    _ChapterBar(
                      height: bottomSpace,
                      preset: preset,
                      index: _chapterIndex,
                      total: book.chapters.length,
                      progress: _chapterFraction,
                      minutesLeft:
                          _chapterWordCount * (1 - _chapterFraction) / 220.0,
                      bookMinutesLeft: _estimateBookMinutesLeft(book),
                      onPrevious: () => _goToChapter(_chapterIndex - 1),
                      onNext: () => _goToChapter(_chapterIndex + 1),
                      onSeek: _seekChapter,
                    ),
                  ),
                ),
                if (_settings.brightness < 1.0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(
                          alpha: (1 - _settings.brightness).clamp(0.0, 0.85),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fadeChrome(Widget child) {
    return AnimatedOpacity(
      opacity: _chromeVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(ignoring: !_chromeVisible, child: child),
    );
  }

  Widget _buildScroll(ReaderThemePreset preset) {
    final blocks = _blocks ?? const <ContentBlock>[];
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: _settings.margin,
        vertical: _contentVPad,
      ),
      itemCount: blocks.length,
      itemBuilder: (context, index) => _BlockView(
        block: blocks[index],
        settings: _settings,
        preset: preset,
        highlightStart: index == _speakingBlock ? _speakingStart : null,
        highlightEnd: index == _speakingBlock ? _speakingEnd : null,
        highlightColor: _highlightedBlocks[index],
      ),
    );
  }

  Widget _buildPaged(ReaderThemePreset preset) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 2 * _settings.margin;
        final height = constraints.maxHeight - 2 * _contentVPad;
        final key =
            '$_chapterIndex:${width.round()}x${height.round()}'
            ':${_settings.fontSize}:${_settings.lineHeight}'
            ':${_settings.fontFamily}:$_fontToken'
            ':${_settings.boldText}:${_settings.italicText}';
        if (key != _pageKey) {
          _pageKey = key;
          _pages = _paginate(_blocks ?? const [], width, height, _settings);
          final pageCount = _pages?.length ?? 1;
          final int wanted;
          if (_pendingRestoreBlock != null) {
            wanted = _pageForBlock(_pendingRestoreBlock!);
            _pendingRestoreBlock = null;
          } else if (_pageJumpTarget == _lastPage) {
            wanted = pageCount - 1;
          } else {
            wanted = _pageJumpTarget;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_pageController.hasClients) return;
            _pageController.jumpToPage(wanted.clamp(0, pageCount - 1));
            _saveProgress();
          });
        }
        final pages = _pages ?? const <List<_PageBlock>>[];
        return PageView.builder(
          controller: _pageController,
          itemCount: pages.length,
          itemBuilder: (context, pageIndex) {
            final pageBlocks = pages[pageIndex];
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: _settings.margin,
                vertical: _contentVPad,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < pageBlocks.length; j++)
                    _BlockView(
                      block: pageBlocks[j].block,
                      settings: _settings,
                      preset: preset,
                      isLast: j == pageBlocks.length - 1,
                      // The highlight range is in parent-block coordinates;
                      // shift it into this slice's own coordinates.
                      highlightStart:
                          pageBlocks[j].originIndex == _speakingBlock
                          ? _speakingStart - pageBlocks[j].charOffset
                          : null,
                      highlightEnd: pageBlocks[j].originIndex == _speakingBlock
                          ? _speakingEnd - pageBlocks[j].charOffset
                          : null,
                      highlightColor:
                          _highlightedBlocks[pageBlocks[j].originIndex],
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Renders one [ContentBlock] with the active theme and typography.
class _BlockView extends StatelessWidget {
  const _BlockView({
    required this.block,
    required this.settings,
    required this.preset,
    this.isLast = false,
    this.highlightStart,
    this.highlightEnd,
    this.highlightColor,
  });

  final ContentBlock block;
  final ReaderSettings settings;
  final ReaderThemePreset preset;

  /// True for the last block on a page — its trailing gap is dropped so the
  /// content can sit flush against the page bottom.
  final bool isLast;

  /// Character range to highlight (the sentence being read aloud), or null.
  final int? highlightStart;
  final int? highlightEnd;

  /// Non-null when the user has saved a passage highlight on this block —
  /// the paragraph/heading body is painted with the matching tint.
  final HighlightColor? highlightColor;

  @override
  Widget build(BuildContext context) {
    switch (block) {
      case ParagraphBlock paragraph:
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : _paragraphGap),
          child: _maybeTint(
            child: Text.rich(
              TextSpan(
                children: _spansFor(
                  context,
                  paragraph.runs,
                  _paragraphStyle(settings, preset.text),
                ),
              ),
              textAlign: settings.textAlign == ReaderTextAlign.justify
                  ? TextAlign.justify
                  : TextAlign.left,
              textScaler: TextScaler.noScaling,
            ),
          ),
        );
      case HeadingBlock heading:
        return Padding(
          padding: EdgeInsets.only(
            top: _headingTopGap,
            bottom: isLast ? 0 : _headingBottomGap,
          ),
          child: _maybeTint(
            child: Text.rich(
              TextSpan(
                children: _spansFor(
                  context,
                  heading.runs,
                  _headingStyle(settings, heading.level, preset.text),
                ),
              ),
              textScaler: TextScaler.noScaling,
            ),
          ),
        );
      case DividerBlock _:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              '✶  ✶  ✶',
              style: TextStyle(color: preset.secondary, fontSize: 16),
            ),
          ),
        );
      case ImageBlock image:
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : _paragraphGap),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 900),
            child: Image.memory(
              image.bytes,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              semanticLabel: image.alt.isEmpty ? null : image.alt,
              errorBuilder: (_, _, _) => Container(
                height: 80,
                color: preset.secondary.withValues(alpha: 0.15),
                alignment: Alignment.center,
                child: Text(
                  image.alt.isEmpty ? '[image]' : '[${image.alt}]',
                  style: TextStyle(color: preset.secondary, fontSize: 12),
                ),
              ),
            ),
          ),
        );
    }
  }

  /// Wraps [child] in a soft tint matching the saved [highlightColor] when
  /// present; returns it unchanged otherwise. The tints are semi-transparent
  /// so they blend acceptably on both light (sepia/paper) and dark themes.
  Widget _maybeTint({required Widget child}) {
    final hc = highlightColor;
    if (hc == null) return child;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: _highlightPaint(hc),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }

  static Color _highlightPaint(HighlightColor color) {
    switch (color) {
      case HighlightColor.yellow:
        return const Color(0xFFFFE066).withValues(alpha: 0.32);
      case HighlightColor.blue:
        return const Color(0xFF66B5FF).withValues(alpha: 0.30);
      case HighlightColor.pink:
        return const Color(0xFFFF8FB5).withValues(alpha: 0.30);
      case HighlightColor.green:
        return const Color(0xFF8FE08F).withValues(alpha: 0.30);
    }
  }

  /// Builds the run spans, giving the highlighted character range a
  /// background colour (splitting runs at the highlight boundaries).
  List<InlineSpan> _spansFor(
    BuildContext context,
    List<TextRun> runs,
    TextStyle base,
  ) {
    final hs = highlightStart;
    final he = highlightEnd;
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final run in runs) {
      final runStart = offset;
      final runEnd = offset + run.text.length;
      offset = runEnd;
      final style = base.copyWith(
        fontWeight: run.bold ? FontWeight.bold : null,
        fontStyle: run.italic ? FontStyle.italic : null,
      );
      // Footnote: emit a tappable inline widget that pops the note body in
      // a bottom sheet. Highlight handling is skipped — the marker is short.
      final footnote = run.footnoteBody;
      if (footnote != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => _showFootnote(context, run.text, footnote),
              behavior: HitTestBehavior.opaque,
              child: Text(
                run.text,
                style: style.copyWith(
                  color: preset.text.withValues(alpha: 0.85),
                  fontSize: (style.fontSize ?? 16) * 0.85,
                  decoration: TextDecoration.underline,
                  decorationColor: preset.text.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      if (hs == null || he == null || he <= runStart || hs >= runEnd) {
        spans.add(TextSpan(text: run.text, style: style));
        continue;
      }
      final a = (hs - runStart).clamp(0, run.text.length);
      final b = (he - runStart).clamp(0, run.text.length);
      if (a > 0) {
        spans.add(TextSpan(text: run.text.substring(0, a), style: style));
      }
      spans.add(
        TextSpan(
          text: run.text.substring(a, b),
          style: style.copyWith(backgroundColor: preset.highlight),
        ),
      );
      if (b < run.text.length) {
        spans.add(TextSpan(text: run.text.substring(b), style: style));
      }
    }
    return spans;
  }

  /// Pops a small bottom sheet with the translator-note body when the
  /// inline marker is tapped.
  void _showFootnote(BuildContext context, String marker, String body) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Translator note  $marker',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlay top bar: back, chapter title, reading settings, contents.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.height,
    required this.title,
    required this.preset,
    required this.ttsState,
    required this.onBack,
    required this.onToggleTts,
    required this.onOpenSettings,
    required this.onShowContents,
    required this.onSearch,
    required this.onBookmarks,
  });

  final double height;
  final String title;
  final ReaderThemePreset preset;
  final TtsPlaybackState ttsState;
  final VoidCallback onBack;
  final VoidCallback onToggleTts;
  final VoidCallback onOpenSettings;
  final VoidCallback onShowContents;
  final VoidCallback onSearch;
  final VoidCallback onBookmarks;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: preset.background,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      child: SizedBox(
        height: height,
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: preset.text,
                tooltip: 'Back',
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: preset.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  ttsState == TtsPlaybackState.playing
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
                color: preset.text,
                tooltip: 'Read aloud',
                onPressed: onToggleTts,
              ),
              IconButton(
                icon: const Icon(Icons.search),
                color: preset.text,
                tooltip: 'Search in book',
                onPressed: onSearch,
              ),
              IconButton(
                icon: const Icon(Icons.bookmark_outline),
                color: preset.text,
                tooltip: 'Bookmarks',
                onPressed: onBookmarks,
              ),
              IconButton(
                icon: const Icon(Icons.text_fields),
                color: preset.text,
                tooltip: 'Reading settings',
                onPressed: onOpenSettings,
              ),
              IconButton(
                icon: const Icon(Icons.list),
                color: preset.text,
                tooltip: 'Contents',
                onPressed: onShowContents,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlay bottom bar: previous / position / next chapter.
class _ChapterBar extends StatelessWidget {
  const _ChapterBar({
    required this.height,
    required this.preset,
    required this.index,
    required this.total,
    required this.progress,
    required this.minutesLeft,
    required this.bookMinutesLeft,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
  });

  final double height;
  final ReaderThemePreset preset;
  final int index;
  final int total;

  /// Fraction (0..1) of the current chapter that has been read.
  final double progress;

  /// Estimated reading time remaining in the chapter, in minutes.
  final double minutesLeft;

  /// Estimated reading time remaining in the whole book, in minutes — null
  /// when no chapter word counts have been measured yet.
  final double? bookMinutesLeft;

  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Tap or drag along the progress bar to scrub to that fraction of the
  /// current chapter.
  final ValueChanged<double> onSeek;

  /// A short human label for the time left in the chapter and (when known)
  /// the rest of the book — e.g. "~5 min in chapter · ~2h left in book".
  String get _timeLabel {
    final chapter = minutesLeft < 0.5
        ? 'Almost done'
        : minutesLeft < 1.5
            ? '~1 min in chapter'
            : '~${minutesLeft.round()} min in chapter';
    final bk = bookMinutesLeft;
    if (bk == null || bk < 1) return chapter;
    return '$chapter · ${_formatBookLeft(bk)} in book';
  }

  /// Human-formatted book-remaining: "~12 min", "~2h", "~3h 25m".
  String _formatBookLeft(double minutes) {
    if (minutes < 60) return '~${minutes.round()} min';
    final h = minutes ~/ 60;
    final m = (minutes - h * 60).round();
    if (m == 0) return '~${h}h';
    return '~${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: preset.background,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      child: SizedBox(
        height: height,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tap / drag along the bar to scrub through the current chapter.
            // Expanded vertically to make the touch target comfortable while
            // the actual visible bar stays a thin 3px line.
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                void seek(double localX) {
                  if (width <= 0) return;
                  onSeek((localX / width).clamp(0.0, 1.0));
                }
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => seek(d.localPosition.dx),
                  onHorizontalDragStart: (d) => seek(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
                  child: SizedBox(
                    height: 16,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor:
                            preset.secondary.withValues(alpha: 0.25),
                        color: preset.text.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      color: preset.text,
                      disabledColor: preset.secondary,
                      tooltip: 'Previous chapter',
                      onPressed: index > 0 ? onPrevious : null,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Chapter ${index + 1} of $total',
                            style: TextStyle(
                              color: preset.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _timeLabel,
                            style: TextStyle(
                              color: preset.secondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      color: preset.text,
                      disabledColor: preset.secondary,
                      tooltip: 'Next chapter',
                      onPressed: index < total - 1 ? onNext : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One full-text search match within the open book.
class _SearchHit {
  const _SearchHit({
    required this.chapterIndex,
    required this.blockIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
  });

  final int chapterIndex;
  final int blockIndex;
  final String chapterTitle;

  /// A short excerpt of text around the match.
  final String snippet;

  /// Character range of the match within [snippet].
  final int matchStart;
  final int matchEnd;
}

/// Full-text search across every chapter of the open book. Pops the chosen
/// [_SearchHit] back to the reader.
class _BookSearchScreen extends StatefulWidget {
  const _BookSearchScreen({
    required this.parser,
    required this.book,
    required this.plainText,
  });

  final EpubParser parser;
  final EpubBook book;

  /// Extracts a block's plain text — shared with the reader so matches line up.
  final String Function(ContentBlock block) plainText;

  @override
  State<_BookSearchScreen> createState() => _BookSearchScreenState();
}

class _BookSearchScreenState extends State<_BookSearchScreen> {
  static const _maxHits = 200;

  final _controller = TextEditingController();
  Timer? _debounce;

  /// Bumped on every new search so a slower stale search can bail out.
  int _searchToken = 0;
  bool _searching = false;
  String _query = '';
  List<_SearchHit> _hits = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {}); // refresh the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _runSearch(value.trim());
    });
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    if (query.length < 2) {
      setState(() {
        _query = query;
        _hits = const [];
        _searching = false;
      });
      return;
    }
    setState(() {
      _query = query;
      _hits = const [];
      _searching = true;
    });

    final needle = query.toLowerCase();
    final hits = <_SearchHit>[];
    for (var ci = 0; ci < widget.book.chapters.length; ci++) {
      if (token != _searchToken) return;
      final chapter = widget.book.chapters[ci];
      final blocks = widget.parser.parseChapter(chapter);
      for (var bi = 0; bi < blocks.length; bi++) {
        final text = widget.plainText(blocks[bi]);
        final idx = text.toLowerCase().indexOf(needle);
        if (idx < 0) continue;
        hits.add(
          _buildHit(ci, bi, chapter.title, text, idx, needle.length),
        );
        if (hits.length >= _maxHits) break;
      }
      // Yield to the UI every few chapters so typing stays responsive and
      // results stream in for long books.
      if (ci % 4 == 3) {
        await Future<void>.delayed(Duration.zero);
        if (token != _searchToken) return;
        setState(() => _hits = List.of(hits));
      }
      if (hits.length >= _maxHits) break;
    }
    if (token != _searchToken) return;
    setState(() {
      _hits = List.of(hits);
      _searching = false;
    });
  }

  /// Builds a hit with a snippet of context around the match.
  _SearchHit _buildHit(
    int chapterIndex,
    int blockIndex,
    String chapterTitle,
    String text,
    int matchIndex,
    int matchLength,
  ) {
    const lead = 36;
    const trail = 96;
    var start = (matchIndex - lead).clamp(0, text.length);
    var end = (matchIndex + matchLength + trail).clamp(0, text.length);
    var snippet = text.substring(start, end).replaceAll('\n', ' ');
    var matchStart = matchIndex - start;
    if (start > 0) {
      snippet = '…$snippet';
      matchStart += 1;
    }
    if (end < text.length) snippet = '$snippet…';
    return _SearchHit(
      chapterIndex: chapterIndex,
      blockIndex: blockIndex,
      chapterTitle: chapterTitle,
      snippet: snippet,
      matchStart: matchStart,
      matchEnd: matchStart + matchLength,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Search this book',
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear',
              onPressed: () {
                _controller.clear();
                _onQueryChanged('');
              },
            ),
        ],
        bottom: _searching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_query.length < 2) {
      return _message(
        theme,
        Icons.search,
        'Search the text of every chapter in this book.',
      );
    }
    if (_hits.isEmpty) {
      return _searching
          ? const Center(child: CircularProgressIndicator())
          : _message(theme, Icons.search_off, 'No matches for “$_query”.');
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _searching
                  ? 'Searching… ${_hits.length} so far'
                  : '${_hits.length}${_hits.length >= _maxHits ? '+' : ''} '
                        'result${_hits.length == 1 ? '' : 's'}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _hits.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final hit = _hits[index];
              return ListTile(
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: hit.snippet.substring(0, hit.matchStart)),
                      TextSpan(
                        text: hit.snippet.substring(
                          hit.matchStart,
                          hit.matchEnd,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      TextSpan(text: hit.snippet.substring(hit.matchEnd)),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    hit.chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                onTap: () => Navigator.of(context).pop(hit),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _message(ThemeData theme, IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing this volume's bookmarks, with an "Add bookmark here"
/// button at the top. Pops with the [Bookmark] the user tapped, or null if
/// they only added/removed entries.
/// Carry-result of the highlight prompt: the note text plus the picked
/// color. Used so the prompt can return both pieces with a single dialog.
class _HighlightFields {
  const _HighlightFields(this.note, this.color);
  final String note;
  final HighlightColor color;
}

class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet({
    required this.volume,
    required this.currentChapterIndex,
    required this.currentBlockIndex,
    required this.currentChapterTitle,
    required this.currentSnippet,
  });

  final Volume volume;
  final int currentChapterIndex;
  final int currentBlockIndex;
  final String currentChapterTitle;
  final String currentSnippet;

  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  final _store = BookmarkStore();
  List<Bookmark>? _bookmarks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.list(widget.volume);
    if (!mounted) return;
    setState(() => _bookmarks = list);
  }

  Future<void> _addHere({bool asHighlight = false}) async {
    String note = '';
    var color = HighlightColor.yellow;
    if (asHighlight) {
      final result = await _promptForHighlight(
        initialNote: '',
        initialColor: color,
      );
      if (result == null) return;
      note = result.note;
      color = result.color;
    }
    final mark = Bookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      chapterIndex: widget.currentChapterIndex,
      blockIndex: widget.currentBlockIndex,
      chapterTitle: widget.currentChapterTitle,
      snippet: widget.currentSnippet,
      createdAt: DateTime.now(),
      isHighlight: asHighlight,
      note: note,
      color: color,
    );
    await _store.add(widget.volume, mark);
    await _load();
  }

  Future<void> _remove(String id) async {
    await _store.remove(widget.volume, id);
    await _load();
  }

  Future<void> _editNote(Bookmark mark) async {
    final result = await _promptForHighlight(
      initialNote: mark.note,
      initialColor: mark.color,
    );
    if (result == null) return;
    await _store.remove(widget.volume, mark.id);
    await _store.add(
      widget.volume,
      mark.copyWith(note: result.note, color: result.color),
    );
    await _load();
  }

  /// Dialog that captures the highlight's note + color. Returns null when
  /// the user cancels.
  Future<_HighlightFields?> _promptForHighlight({
    required String initialNote,
    required HighlightColor initialColor,
  }) async {
    final controller = TextEditingController(text: initialNote);
    var color = initialColor;
    final result = await showDialog<_HighlightFields>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Highlight'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Optional note for this passage',
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: [
                  for (final c in HighlightColor.values)
                    GestureDetector(
                      onTap: () => setLocal(() => color = c),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _BlockView._highlightPaint(c),
                          border: Border.all(
                            color: color == c
                                ? Theme.of(ctx).colorScheme.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(
              _HighlightFields(controller.text.trim(), color),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marks = _bookmarks;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Bookmarks',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.list_alt_outlined),
                  tooltip: 'View all annotations',
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HighlightsScreen(
                          volume: widget.volume,
                          bookTitle: widget.volume.title,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Done',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _addHere(),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Bookmark'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _addHere(asHighlight: true),
                    icon: const Icon(Icons.brush_outlined),
                    label: const Text('Highlight'),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'In: ${widget.currentChapterTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            Flexible(
              child: marks == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : marks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'No bookmarks yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: marks.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final mark = marks[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  mark.chapterTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (mark.isHighlight) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _BlockView._highlightPaint(
                                      mark.color,
                                    ),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Highlight',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mark.snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              if (mark.note.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    mark.note,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'More',
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  _editNote(mark);
                                case 'delete':
                                  _remove(mark.id);
                              }
                            },
                            itemBuilder: (_) => [
                              if (mark.isHighlight)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit note'),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                          onTap: () => Navigator.of(context).pop(mark),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
