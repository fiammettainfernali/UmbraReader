import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../reader/block_view.dart';
import '../reader/line_focus_overlay.dart';
import '../reader/book_search_screen.dart';
import '../reader/bookmarks_sheet.dart';
import '../reader/reader_chrome.dart';
import '../reader/reader_layout.dart';
import '../reader/reader_tts_session.dart';
import '../models/bookmark.dart';
import '../models/content_block.dart';
import '../models/epub_book.dart';
import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../models/volume.dart';
import '../services/bookmark_store.dart';
import '../services/dictionary_service.dart';
import '../services/epub_parser.dart';
import '../services/library_cache.dart';
import '../services/cover_cache.dart';
import '../services/library_storage.dart';
import '../services/network_tts_service.dart';
import '../services/reader_preferences.dart';
import '../services/reading_activity_store.dart';
import '../services/reading_progress_store.dart';
import '../services/tts_engine.dart';
import '../services/tts_service.dart';
import '../services/tts_skip.dart';
import '../utils/volume_ordering.dart';
import '../widgets/reader_settings_sheet.dart';
import 'glossary_screen.dart';

/// Reads a downloaded volume: parses the EPUB and renders its chapters, with
/// scroll or paged layout, an immersive (fade-away) chrome, a colour-theme /
/// typography engine, chapter navigation and keyboard/remote support.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.volume,
    this.initialChapterIndex,
    this.initialBlockIndex,
  });

  final Volume volume;

  /// When set, the reader opens at this exact spot (e.g. a library-search
  /// hit) instead of the saved reading position.
  final int? initialChapterIndex;
  final int? initialBlockIndex;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver, ReaderTtsSession {
  final _progressStore = ReadingProgressStore();
  final _scrollController = ScrollController();
  final _pageController = PageController();

  EpubParser? _parser;
  EpubBook? _book;
  int _chapterIndex = 0;
  List<ContentBlock>? _blocks;
  bool _loading = true;
  String? _error;

  ReaderSettings _settings = ReaderSettings.defaults;
  bool _chromeVisible = true;


  // Paged-mode pagination cache.
  List<List<PageBlock>>? _pages;
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

  /// Reading-ruler band index on the current page (paged mode): the band
  /// steps down the page tap by tap, rolling into a page turn at the
  /// bottom. Reset to the top on any page/chapter change.
  int _rulerBand = 0;

  /// The spread the ruler band was last positioned on — a manual swipe
  /// bypasses _advance, so the position tick resets the band on change.
  int _rulerSpread = 0;

  /// Character offset within [_pendingRestoreBlock]'s text to restore to —
  /// the line-level precision part of the saved position.
  int _pendingRestoreChar = 0;

  /// Block index to restore to on open; consumed once the content lays out.
  int? _pendingRestoreBlock;

  /// Content width (screen minus margins), cached each build so progress can
  /// be measured without a MediaQuery lookup (e.g. during dispose).
  double _lastContentWidth = 0;


  /// Last block that auto-follow moved to — so it only moves on a change.
  int _followedBlock = -1;

  /// Last page that read-aloud auto-follow turned to (paged mode).
  int _followedPage = -1;


  /// Periodic timer driving the hands-free auto-scroll, when enabled.
  Timer? _autoScrollTimer;

  /// Periodic timer driving timed auto page-turns in paged mode, when enabled.
  Timer? _autoPageTimer;

  /// Total width of the centred reading column (text + its own margins) when
  /// "centred column" is on — keeps lines in the comfortable centre of wide
  /// displays and XR-glasses optics.
  static const double _centeredColumnWidth = 620;

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
    initTtsSession();
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
      // Save the current page/scroll position the moment the app loses
      // foreground (screen lock, app switcher, etc.) — without this iOS can
      // kill the process before dispose() fires and the user reopens to an
      // older saved position from the last page turn.
      _saveProgress();
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
    // Release any reader-imposed orientation lock so the rest of the app
    // (library, settings) follows the device's normal auto-rotate setting.
    _applyOrientation(ReaderOrientation.auto);
    // Don't leave the screen pinned awake after leaving the reader.
    _applyKeepAwake(false);
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollTimer?.cancel();
    _autoPageTimer?.cancel();
    disposeTtsSession();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }


  // ── ReaderTtsSession plumbing ────────────────────────────────────────────
  // Thin proxies exposing the State's private fields to the read-aloud mixin.

  @override
  Volume get readerVolume => widget.volume;

  @override
  ReaderSettings get readerSettings => _settings;

  @override
  List<ContentBlock>? get currentBlocks => _blocks;

  @override
  EpubBook? get currentBook => _book;

  @override
  EpubParser? get currentParser => _parser;

  @override
  int get currentChapterIndex => _chapterIndex;

  @override
  int get currentChapterWordCount => _chapterWordCount;

  @override
  double get chapterFraction => _chapterFraction;

  @override
  set chapterFraction(double value) => _chapterFraction = value;

  @override
  int currentTopBlockIndex() => _settings.mode == ReadingMode.paged
      ? _pagedTopBlockIndex()
      : _scrollTopBlockIndex();

  @override
  void goToChapter(
    int index, {
    bool landOnLastPage = false,
    bool fromTts = false,
  }) => _goToChapter(index, landOnLastPage: landOnLastPage, fromTts: fromTts);

  @override
  void saveReadingProgress() => _saveProgress();

  @override
  void followSpeaking(int blockIndex) => _followSpeaking(blockIndex);

  @override
  void resetFollow() {
    _followedBlock = -1;
    _followedPage = -1;
  }

  @override
  Future<void> applyReaderSettings(ReaderSettings next) => _applySettings(next);

  @override
  Future<void> openReaderSettings() => _openSettings();

  Future<void> _open() async {
    var settings = await ReaderPreferences().load(volume: widget.volume);
    // Apply this series' remembered narrator, if one was chosen for it.
    final seriesVoice =
        await ReaderPreferences().seriesVoice(widget.volume.seriesOpdsId);
    if (seriesVoice != null) {
      settings = settings.copyWith(
        voiceName: seriesVoice.$1,
        voiceLocale: seriesVoice.$2,
      );
    }
    final resume = await _progressStore.resumeOffset(widget.volume);
    if (resume != null) {
      ttsResumeBlock = resume.$1;
      ttsResumeChar = resume.$2;
    }
    final cover = await CoverCache(
      LibraryStorage(),
    ).cached(widget.volume.seriesOpdsId);
    ttsCoverPath = cover?.path;
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
      var chapterIndex = (widget.initialChapterIndex ?? progress.chapterIndex)
          .clamp(0, book.chapters.length - 1);
      // Recompiled-volume resilience: if the saved chapter still exists but
      // at a different index (chapters inserted/reordered), follow its
      // spine path instead of the stale number.
      final savedPath = progress.chapterPath;
      if (widget.initialChapterIndex == null && savedPath != null) {
        final byPath = book.chapters.indexWhere((c) => c.zipPath == savedPath);
        if (byPath >= 0) chapterIndex = byPath;
      }
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
            : (widget.initialBlockIndex ?? progress.blockIndex).clamp(
                0,
                blocks.length - 1,
              );
        // Search hits target a block; the saved position carries the char.
        _pendingRestoreChar = widget.initialBlockIndex != null
            ? 0
            : progress.blockChar;
        _loading = false;
      });
      _applyOrientation(settings.orientation);
      _applyKeepAwake(settings.keepAwake);
      syncEngineToSettings();
      loadPronunciations().then((_) => prepareAudio());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollPosition();
        if (_settings.autoScroll) _startAutoScroll();
        _startAutoPage();
        // Record the restored position immediately (jumpTo applies the
        // offset synchronously). Without this, a book opened and closed
        // without any scroll/page event never saves at all: restoring to
        // an unchanged offset fires no scroll notification, and the
        // dispose-time save is skipped once the controllers detach. It
        // also heals stale finished-state — a book sitting at the end of
        // its last chapter registers endReached here (the "caught-up book
        // stuck on the Continue shelf" bug). Paged mode may still be
        // mid-jump this frame; its controller listener saves right after.
        if (mounted) _saveProgress();
      });
      _refreshHighlights();
    } on EpubException catch (e) {
      _fail(e.message);
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
      // Advancing past the final chapter is the clearest "I finished this
      // book" signal there is — record it explicitly, so the volume leaves
      // the Continue shelf even if no position save happened to catch the
      // scroll sitting at the very bottom.
      final blocks = _blocks ?? const <ContentBlock>[];
      final block = _settings.mode == ReadingMode.paged
          ? (_pageController.hasClients ? _pagedTopBlockIndex() : 0)
          : (_scrollController.hasClients ? _scrollTopBlockIndex() : 0);
      _progressStore.save(
        widget.volume,
        ReadingProgress(
          chapterIndex: _chapterIndex,
          blockIndex: blocks.isEmpty ? 0 : block.clamp(0, blocks.length - 1),
          chapterPath: _currentChapterPath,
          chapterCount: book.chapters.length,
          endReached: true,
        ),
      );
      if (!_endOfVolumePrompted) {
        _endOfVolumePrompted = true;
        _maybeShowEndOfVolumePrompt();
      }
      return;
    }
    final clamped = index.clamp(0, book.chapters.length - 1);
    if (clamped == _chapterIndex && _blocks != null) return;
    // A manual chapter change stops read-aloud; a TTS-driven advance keeps it.
    if (!fromTts) ttsEngine.stop();
    _lastChapterChange = DateTime.now();
    _edgeOverscroll = 0;
    final blocks = parser.parseChapter(book.chapters[clamped]);
    setState(() {
      _chapterIndex = clamped;
      _lastSavedBlock = -1;
      _blocks = blocks;
      _chapterWordCount = _countWords(blocks);
      _chapterFraction = 0;
      _pageKey = null;
      _pageJumpTarget = landOnLastPage ? kLastPage : 0;
    });
    _progressStore.save(
      widget.volume,
      ReadingProgress(
        chapterIndex: clamped,
        blockIndex: 0,
        chapterPath: book.chapters[clamped].zipPath,
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
    final cached = cache.volumesFor(widget.volume.seriesOpdsId);
    if (cached == null || cached.isEmpty) return;
    final volumes = volumesInReadingOrder(cached);
    final currentIdx = volumes.indexWhere(
      (v) => v.fileName == widget.volume.fileName,
    );
    // No match, or this is the latest volume in reading order → nothing to
    // advance to, so stay put silently.
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
    var offset = kContentVPad;
    for (var i = 0; i < blockIndex && i < blocks.length; i++) {
      offset += measureBlockHeight(blocks[i], _lastContentWidth, _settings);
    }
    return offset;
  }

  /// Index of the block at the top of the viewport in scroll mode.
  int _scrollTopBlockIndex() {
    final blocks = _blocks ?? const <ContentBlock>[];
    if (blocks.isEmpty || !_scrollController.hasClients) return 0;
    final target = _scrollController.offset;
    var acc = kContentVPad;
    for (var i = 0; i < blocks.length; i++) {
      acc += measureBlockHeight(blocks[i], _lastContentWidth, _settings);
      if (acc > target) return i;
    }
    return blocks.length - 1;
  }

  /// Index of the first block on the current page in paged mode.
  /// Underlying pages per swipe — 1 normally, 2 in TV mode (left/right
  /// columns of a spread). PageController.page tracks *spreads*, so all
  /// conversions between block-index and page-index go through this.
  int get _pageStride => _settings.tvMode ? 2 : 1;

  int _pagedTopBlockIndex() {
    final pages = _pages;
    if (pages == null || pages.isEmpty || !_pageController.hasClients) return 0;
    final spread = (_pageController.page?.round() ?? 0);
    final underlying = (spread * _pageStride).clamp(0, pages.length - 1);
    final pageBlocks = pages[underlying];
    return pageBlocks.isEmpty ? 0 : pageBlocks.first.originIndex;
  }

  /// The spread (PageController page) showing block [blockIndex] at
  /// character [charOffset] — so read-aloud follow stays correct for a
  /// paragraph that spans pages.
  int _pageForBlockAt(int blockIndex, int charOffset) {
    final pages = _pages ?? const <List<PageBlock>>[];
    final stride = _pageStride;
    var firstPage = -1;
    for (var i = 0; i < pages.length; i++) {
      for (final pb in pages[i]) {
        if (pb.originIndex != blockIndex) continue;
        if (firstPage < 0) firstPage = i;
        final length = pb.block is ParagraphBlock
            ? runsLength((pb.block as ParagraphBlock).runs)
            : 0;
        if (charOffset >= pb.charOffset &&
            charOffset < pb.charOffset + length) {
          return i ~/ stride;
        }
      }
    }
    if (firstPage >= 0) return firstPage ~/ stride;
    if (pages.isEmpty) return 0;
    return (pages.length - 1) ~/ stride;
  }

  void _saveProgress() {
    final blocks = _blocks ?? const <ContentBlock>[];
    // While reading aloud, the authoritative position is the paragraph being
    // spoken — not the scroll top (which trails it because the follow-scroll
    // keeps the spoken line partway down the screen).
    final ttsActive =
        ttsEngine.state != TtsPlaybackState.stopped && speakingBlock != null;
    final int block;
    final int blockChar;
    final bool atEnd;
    if (ttsActive) {
      block = speakingBlock!.clamp(0, blocks.isEmpty ? 0 : blocks.length - 1);
      blockChar = speakingStart;
      atEnd = blocks.isNotEmpty && block >= blocks.length - 1;
      // Record the word-level resume point (Kokoro can seek back to it).
      _progressStore.saveResumeOffset(widget.volume, block, speakingStart);
    } else if (_settings.mode == ReadingMode.paged) {
      // Skip if the position can't be read (e.g. controllers already detached
      // during dispose) — saving a fallback 0 would clobber the real position.
      if (!_pageController.hasClients) return;
      block = _pagedTopBlockIndex();
      blockChar = _pagedTopChar(block);
      atEnd = _isAtChapterEnd();
    } else {
      if (!_scrollController.hasClients) return;
      block = _scrollTopBlockIndex();
      blockChar = _scrollTopChar(block);
      atEnd = _isAtChapterEnd();
    }
    final chapterCount = _book?.chapters.length ?? 0;
    // "Finished" means the end of the *last* chapter was actually reached —
    // not merely being on it (you can stop mid-final-chapter).
    final onLastChapter =
        chapterCount > 0 && _chapterIndex >= chapterCount - 1;
    _progressStore.save(
      widget.volume,
      ReadingProgress(
        chapterIndex: _chapterIndex,
        blockIndex: block,
        blockChar: blockChar,
        chapterPath: _currentChapterPath,
        chapterCount: chapterCount,
        endReached: onLastChapter && atEnd,
      ),
    );
  }

  /// Spine href of the open chapter — the recompile-proof anchor stored
  /// alongside the numeric index.
  String? get _currentChapterPath {
    final book = _book;
    if (book == null ||
        _chapterIndex < 0 ||
        _chapterIndex >= book.chapters.length) {
      return null;
    }
    return book.chapters[_chapterIndex].zipPath;
  }

  /// Character offset (line start) of the first visible line within [block]
  /// in scroll mode — 0 when the block top is visible or it isn't text.
  int _scrollTopChar(int block) {
    final blocks = _blocks ?? const <ContentBlock>[];
    if (block < 0 || block >= blocks.length) return 0;
    final b = blocks[block];
    if (b is! ParagraphBlock || !_scrollController.hasClients) return 0;
    final yIn = _scrollController.offset - _blockOffset(block);
    if (yIn <= 4) return 0;
    final painter = layoutParagraph(b.runs, _lastContentWidth, _settings);
    final pos = painter.getPositionForOffset(
      Offset(0, (yIn + 1).clamp(0.0, painter.height)),
    );
    return painter.getLineBoundary(pos).start;
  }

  /// Character offset of the current page's first slice when it belongs to
  /// [block] — the paged-mode precision component.
  int _pagedTopChar(int block) {
    final pages = _pages;
    if (pages == null || pages.isEmpty || !_pageController.hasClients) {
      return 0;
    }
    final spread = _pageController.page?.round() ?? 0;
    final underlying = (spread * _pageStride).clamp(0, pages.length - 1);
    final pageBlocks = pages[underlying];
    if (pageBlocks.isEmpty) return 0;
    final first = pageBlocks.first;
    return first.originIndex == block ? first.charOffset : 0;
  }

  /// True when the view is at the very end of the current chapter — the last
  /// page (paged) or scrolled to the bottom (scroll).
  bool _isAtChapterEnd() {
    if (_settings.mode == ReadingMode.paged) {
      if (!_pageController.hasClients) return false;
      final pages = _pages;
      if (pages == null || pages.isEmpty) return false;
      final spreads = (pages.length / _pageStride).ceil();
      final current = (_pageController.page ?? 0).round();
      return current >= spreads - 1;
    }
    if (!_scrollController.hasClients) return false;
    final pos = _scrollController.position;
    // A chapter short enough to fit the viewport has maxScrollExtent 0 —
    // the whole chapter is visible, so the reader IS at its end. (Requiring
    // extent > 0 here left books with a short final chapter permanently
    // "in progress": endReached could never become true.)
    return pos.maxScrollExtent <= 0 || pos.pixels >= pos.maxScrollExtent - 4;
  }

  // ── in-chapter progress ──────────────────────────────────────────────────

  /// Recomputes how far through the current chapter the reader is, refreshing
  /// the progress bar / time estimate when it moves by at least half a percent.
  /// The page index (paged mode) or top-block index (scroll mode) that was
  /// last persisted — used to skip duplicate saves on the same position.
  int _lastSavedBlock = -1;

  void _onPositionTick() {
    // A page change from any source (swipe, scrubber, follow) resets the
    // ruler band to the top of the new page.
    if (_settings.lineFocus &&
        _settings.mode == ReadingMode.paged &&
        _pageController.hasClients) {
      final spread = _pageController.page?.round() ?? 0;
      if (spread != _rulerSpread) {
        _rulerSpread = spread;
        if (_rulerBand != 0) setState(() => _rulerBand = 0);
      }
    }
    final fraction = _computeChapterFraction();
    if ((fraction * 200).round() != (_chapterFraction * 200).round()) {
      setState(() => _chapterFraction = fraction);
    }
    // Persist the page / scroll position whenever the user settles on a new
    // page so the saved spot tracks the real one — not just on screen close.
    // Lock-screen / app-kill used to lose the last few pages because the
    // only saves were on chapter change + dispose.
    final block = _settings.mode == ReadingMode.paged
        ? (_pageController.hasClients ? _pagedTopBlockIndex() : -1)
        : (_scrollController.hasClients ? _scrollTopBlockIndex() : -1);
    if (block >= 0 && block != _lastSavedBlock) {
      _lastSavedBlock = block;
      _saveProgress();
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
      for (final word in plainBlockText(block).split(RegExp(r'\s+'))) {
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
    var offset = _blockOffset(block);
    final char = _pendingRestoreChar;
    _pendingRestoreChar = 0;
    final blocks = _blocks ?? const <ContentBlock>[];
    if (char > 0 && block < blocks.length) {
      final b = blocks[block];
      if (b is ParagraphBlock) {
        // Land on the exact line the reader stopped at, not the paragraph
        // top — webnovel paragraphs can be a whole screen tall.
        final painter = layoutParagraph(b.runs, _lastContentWidth, _settings);
        offset += painter
            .getOffsetForCaret(
              TextPosition(offset: char.clamp(0, runsLength(b.runs))),
              Rect.zero,
            )
            .dy;
      }
    }
    _scrollController.jumpTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  /// Kindle-style word lookup: long-press a word to open the system
  /// dictionary. The word under the finger is resolved with the same
  /// TextPainter layout math the pagination uses, so it's exact.
  void _onContentLongPress(LongPressStartDetails details) {
    final word = _wordAt(details.globalPosition);
    if (word == null) return;
    HapticFeedback.selectionClick();
    DictionaryService().define(word);
  }

  /// The word at [globalPosition], or null when the press isn't on text.
  String? _wordAt(Offset globalPosition) {
    final blocks = _blocks;
    if (blocks == null || blocks.isEmpty) return null;
    final mq = MediaQuery.of(context);
    final areaWidth = _settings.centeredColumn && !_settings.tvMode
        ? math.min(mq.size.width, _centeredColumnWidth)
        : mq.size.width;
    final contentLeft = (mq.size.width - areaWidth) / 2;
    final contentTop = _chromeVisible
        ? mq.padding.top + kTopBarHeight
        : mq.padding.top + 8;

    final (block, slice, localX, localY) = _settings.mode == ReadingMode.paged
        ? _pagedHit(globalPosition, areaWidth, contentLeft, contentTop)
        : _scrollHit(globalPosition, contentLeft, contentTop);
    if (block == null) return null;

    final ParagraphBlock? paragraph = switch (slice ?? block) {
      ParagraphBlock p => p,
      HeadingBlock h => ParagraphBlock(h.runs),
      _ => null,
    };
    if (paragraph == null) return null;

    final width = _settings.mode == ReadingMode.paged
        ? _pagedColumnTextWidth(areaWidth)
        : areaWidth - 2 * _settings.margin;
    final style = (slice ?? block) is HeadingBlock
        ? headingStyle(
            _settings,
            ((slice ?? block) as HeadingBlock).level,
            _settings.theme.text,
          )
        : paragraphStyle(_settings, _settings.theme.text);
    final painter = TextPainter(
      text: runSpan(paragraph.runs, style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);
    if (localY < 0 || localY > painter.height) return null;
    final pos = painter.getPositionForOffset(Offset(localX, localY));
    final text = paragraph.runs.map((r) => r.text).join();
    final range = painter.getWordBoundary(pos);
    if (range.start >= range.end || range.end > text.length) return null;
    final word = text
        .substring(range.start, range.end)
        .replaceAll(RegExp(r'''^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$''', unicode: true), '');
    if (word.isEmpty || word.length > 40) return null;
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(word)) return null;
    return word;
  }

  /// Text width of one paged column (matches _buildPaged's colWidth).
  double _pagedColumnTextWidth(double areaWidth) {
    final stride = _pageStride;
    final tvSafeH = _settings.tvMode ? areaWidth * 0.055 : 0.0;
    final usableWidth = areaWidth - 2 * tvSafeH;
    const columnGutter = 36.0;
    final gutterTotal = columnGutter * (stride - 1);
    return ((usableWidth - gutterTotal) / stride) - 2 * _settings.margin;
  }

  /// Resolves a scroll-mode press to (block, sliceless, x, y within the
  /// block's own text layout).
  (ContentBlock?, ContentBlock?, double, double) _scrollHit(
    Offset global,
    double contentLeft,
    double contentTop,
  ) {
    final blocks = _blocks!;
    if (!_scrollController.hasClients) return (null, null, 0, 0);
    final x = global.dx - contentLeft - _settings.margin;
    var y = global.dy - contentTop + _scrollController.offset - kContentVPad;
    for (final block in blocks) {
      final h = measureBlockHeight(block, _lastContentWidth, _settings);
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
    final pages = _pages;
    if (pages == null || pages.isEmpty || !_pageController.hasClients) {
      return (null, null, 0, 0);
    }
    final stride = _pageStride;
    final tvSafeH = _settings.tvMode ? areaWidth * 0.055 : 0.0;
    final tvSafeV = _settings.tvMode
        ? (MediaQuery.of(context).size.height) * 0.04
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
    final spread = (_pageController.page ?? 0).round();
    final pageIndex = spread * stride + col;
    if (pageIndex < 0 || pageIndex >= pages.length) return (null, null, 0, 0);

    final textX = x - _settings.margin;
    var y = global.dy - contentTop - tvSafeV - kContentVPad;
    final width = _pagedColumnTextWidth(areaWidth);
    for (final pb in pages[pageIndex]) {
      final block = pb.block;
      final double h;
      final double inset;
      switch (block) {
        case ParagraphBlock p:
          h = layoutParagraph(p.runs, width, _settings).height + kParagraphGap;
          inset = 0;
        case HeadingBlock _:
          h = measureBlockHeight(block, width, _settings);
          inset = kHeadingTopGap;
        case DividerBlock _:
          h = kDividerHeight;
          inset = 0;
        case ImageBlock _:
          h = measureBlockHeight(block, width, _settings);
          inset = 0;
      }
      if (y < h) {
        final origin = (_blocks != null && pb.originIndex < _blocks!.length)
            ? _blocks![pb.originIndex]
            : block;
        return (origin, block, textX, y - inset);
      }
      y -= h;
    }
    return (null, null, 0, 0);
  }

  void _toggleChrome() {
    // Showing/hiding the chrome changes the content padding, which re-paginates
    // paged mode. Restore by the top *block* — page indices shift when the
    // page height changes, so remembering the page number landed on the wrong
    // content.
    if (_settings.mode == ReadingMode.paged && _pageController.hasClients) {
      final block = _pagedTopBlockIndex();
      _pendingRestoreBlock = block;
      _pendingRestoreChar = _pagedTopChar(block);
    }
    setState(() => _chromeVisible = !_chromeVisible);
  }

  /// Routes a tap on the page: the left and right edges turn the page, while
  /// the centre toggles the reading chrome.
  void _onContentTap(TapUpDetails details) {
    // While the chrome is up, any tap on the page just dismisses it — the
    // edge zones stay dormant. Otherwise a tap meant to close the menu
    // that landed near an edge flipped a page as a side effect.
    if (_chromeVisible) {
      _toggleChrome();
      return;
    }
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
    final orientationChanged = next.orientation != _settings.orientation;
    final engineChanged = next.ttsEngine != _settings.ttsEngine ||
        next.ttsServerUrl != _settings.ttsServerUrl ||
        next.ttsServerToken != _settings.ttsServerToken;
    final tvModeChanged = next.tvMode != _settings.tvMode;
    final keepAwakeChanged = next.keepAwake != _settings.keepAwake;
    // Centred-column toggle changes the content width, so paged mode must
    // re-paginate.
    final centeredChanged = next.centeredColumn != _settings.centeredColumn;
    // TV mode is paged-only — auto-promote a scroll-mode user when they
    // flip it on so the 2-column layout has something to slice into pages.
    if (next.tvMode && next.mode != ReadingMode.paged) {
      next = next.copyWith(mode: ReadingMode.paged);
    }
    final currentPage = _pageController.hasClients
        ? (_pageController.page?.round() ?? 0)
        : 0;
    setState(() {
      _settings = next;
      _pageJumpTarget = currentPage;
    });
    ReaderPreferences().save(next, volume: widget.volume);
    if (engineChanged) syncEngineToSettings();
    if (rateChanged) ttsEngine.setRate(next.speechRate);
    if (voiceChanged) {
      ttsEngine.setVoice(next.voiceName, next.voiceLocale);
      // Remember the chosen narrator for this whole series.
      ReaderPreferences().saveSeriesVoice(
        widget.volume.seriesOpdsId,
        next.voiceName,
        next.voiceLocale,
      );
    }
    // The cache is keyed by voice/engine, so re-warm it when either changes.
    if (voiceChanged || engineChanged) prepareAudio();
    if (fontChanged && mounted) {
      // Bundled fonts need no preload; bump the token so paged mode
      // re-paginates with the new family's metrics.
      setState(() => _fontToken++);
    }
    if (autoScrollChanged) {
      if (next.autoScroll && next.mode == ReadingMode.scroll) {
        _startAutoScroll();
      } else {
        _stopAutoScroll();
      }
    }
    if (orientationChanged || tvModeChanged) {
      _applyOrientation(next.orientation);
    }
    if (keepAwakeChanged) _applyKeepAwake(next.keepAwake);
    // Restart timed page-turns against the (possibly changed) interval/mode.
    _startAutoPage();
    // Toggling TV mode or the centred column changes the content width, so the
    // cached pagination must be rebuilt.
    if (tvModeChanged || centeredChanged) {
      _pageKey = null;
      _lastSavedBlock = -1;
    }
  }

  /// Asks the OS to lock to (or release) a specific orientation. Auto
  /// re-enables all four orientations so the device follows its rotate lock.
  /// TV mode always forces landscape regardless of the requested setting.
  void _applyOrientation(ReaderOrientation orientation) {
    final effective = _settings.tvMode
        ? ReaderOrientation.landscape
        : orientation;
    switch (effective) {
      case ReaderOrientation.auto:
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      case ReaderOrientation.portrait:
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      case ReaderOrientation.landscape:
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
    }
  }

  // ── read-aloud ───────────────────────────────────────────────────────────

  /// Plain text of a block — exactly the runs as rendered, so TTS word
  /// offsets line up with the on-screen text for highlighting.
  @override
  String plainBlockText(ContentBlock block) => switch (block) {
    ParagraphBlock p => p.runs.map((r) => r.text).join(),
    HeadingBlock h => h.runs.map((r) => r.text).join(),
    DividerBlock _ => '',
    ImageBlock _ => '',
  };


  /// True when the system asks for reduced motion (iOS Reduce Motion) —
  /// page turns and follow-scrolls jump instead of animating.
  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  /// Scrolls/pages so the block being read stays visible — only when the
  /// block changes, so it doesn't fight the reader within a paragraph.
  void _followSpeaking(int blockIndex) {
    if (_settings.mode == ReadingMode.paged) {
      if (!_pageController.hasClients) return;
      // Follow by page (not block) so a paragraph split across pages is
      // tracked as read-aloud moves through it.
      final page = _pageForBlockAt(blockIndex, speakingStart);
      final currentPage = _pageController.page?.round() ?? 0;
      if (page != currentPage && page != _followedPage) {
        _followedPage = page;
        if (_reduceMotion) {
          _pageController.jumpToPage(page);
        } else {
          _pageController.animateToPage(
            page,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
      return;
    }
    // Scroll mode: only move when the block changes, so it doesn't fight the
    // reader within a paragraph.
    if (blockIndex == _followedBlock) return;
    _followedBlock = blockIndex;
    if (!_scrollController.hasClients) return;
    // Keep the spoken line a little above the middle of the screen (~42% down)
    // rather than pinned near the top, so it reads more like a teleprompter.
    final topInset = MediaQuery.of(context).size.height * 0.42;
    final target = (_blockOffset(blockIndex) - topInset).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if (_reduceMotion) {
      _scrollController.jumpTo(target);
    } else {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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

  /// Timed auto page-turn for paged mode (the paged analogue of auto-scroll) —
  /// advances a page every `autoPageSeconds`. Hands-free reading for XR glasses.
  void _startAutoPage() {
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
    if (_settings.autoPageSeconds <= 0) return;
    if (_settings.mode != ReadingMode.paged) return;
    _autoPageTimer = Timer.periodic(
      Duration(seconds: _settings.autoPageSeconds),
      (_) {
        if (!mounted ||
            _settings.mode != ReadingMode.paged ||
            _settings.autoPageSeconds <= 0) {
          _stopAutoPage();
          return;
        }
        _advance(forward: true);
      },
    );
  }

  void _stopAutoPage() {
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
  }

  /// Holds (or releases) the screen-awake lock per the keep-awake setting.
  /// Best-effort — silently ignored where the plugin is unavailable.
  Future<void> _applyKeepAwake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } on Exception {
      // ignore — non-critical
    }
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


  /// Speechify-style "skip while reading" menu: pick content the voice skips
  /// over (parentheses, URLs, citations, headings, …). Applies on the next
  /// read-aloud start.
  void _openSkipMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          final theme = Theme.of(context);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Skip while reading',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The voice silently skips the selected content. Takes '
                    'effect the next time read-aloud starts.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final kind in TtsSkip.values)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(kind.label),
                      subtitle: Text(kind.description),
                      value: _settings.ttsSkips.contains(kind),
                      onChanged: (on) {
                        final next = Set<TtsSkip>.of(_settings.ttsSkips);
                        if (on) {
                          next.add(kind);
                        } else {
                          next.remove(kind);
                        }
                        _applySettings(_settings.copyWith(ttsSkips: next));
                        setSheet(() {});
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openGlossary() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GlossaryScreen(
          seriesId: widget.volume.seriesOpdsId,
          title: widget.volume.title,
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final voices = await ttsEngine.availableVoices();
    final prefs = ReaderPreferences();
    final hasOverride = await prefs.hasOverride(widget.volume);
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
        sleepOption: sleepOption,
        onChanged: _applySettings,
        onSleepTimerChanged: setSleepTimer,
        hasOverride: hasOverride,
        onOverrideToggled: (enabled) async {
          if (enabled) {
            await prefs.enableOverride(widget.volume, _settings);
          } else {
            await prefs.clearOverride(widget.volume);
          }
        },
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
        : _shortSnippet(plainBlockText(blocks[clampedTop]));
    final picked = await showModalBottomSheet<Bookmark>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (_) => BookmarksSheet(
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
    final hit = await Navigator.of(context).push<SearchHit>(
      MaterialPageRoute(
        builder: (_) => BookSearchScreen(
          parser: parser,
          book: book,
          plainText: plainBlockText,
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
    ttsEngine.stop();
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
      _lastSavedBlock = -1;
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
        chapterPath: book.chapters[clamped].zipPath,
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

  /// Height of the ruler's content area (mirrors contentPadding).
  double _rulerAreaHeight() {
    final mq = MediaQuery.of(context);
    return _chromeVisible
        ? mq.size.height -
              (mq.padding.top + kTopBarHeight) -
              (mq.padding.bottom + kBottomBarHeight)
        : mq.size.height - (mq.padding.top + 8) - (mq.padding.bottom + 8);
  }

  double get _rulerBandHeight =>
      _settings.fontSize * _settings.lineHeight * 3.2;

  /// Highest band index that still shows content on the page.
  int get _rulerMaxBand {
    final h = _rulerAreaHeight();
    if (h <= 0) return 0;
    return ((h / _rulerBandHeight).ceil() - 1).clamp(0, 999);
  }

  void _advance({required bool forward}) {
    // Stepping band: with the ruler on in paged mode, the page is static,
    // so the focus band moves instead of the text — each advance steps the
    // band one height down, rolling into a real page turn at the bottom
    // (and back up / page-back in reverse).
    if (_settings.lineFocus && _settings.mode == ReadingMode.paged) {
      if (forward) {
        if (_rulerBand < _rulerMaxBand) {
          HapticFeedback.selectionClick();
          setState(() => _rulerBand++);
          return;
        }
        _rulerBand = 0; // page turns below; new page starts at the top
      } else {
        if (_rulerBand > 0) {
          HapticFeedback.selectionClick();
          setState(() => _rulerBand--);
          return;
        }
        // Paging back lands the band on the bottom of the previous page.
        _rulerBand = _rulerMaxBand;
      }
    }
    _advancePage(forward: forward);
  }

  void _advancePage({required bool forward}) {
    if (_settings.mode == ReadingMode.paged) {
      final pages = _pages ?? const [];
      final current =
          (_pageController.hasClients ? _pageController.page : 0)?.round() ?? 0;
      if (forward) {
        if (current < pages.length - 1) {
          HapticFeedback.lightImpact();
          if (_reduceMotion) {
            _pageController.jumpToPage(current + 1);
          } else {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          }
        } else {
          HapticFeedback.mediumImpact();
          _goToChapter(_chapterIndex + 1);
        }
      } else {
        if (current > 0) {
          HapticFeedback.lightImpact();
          if (_reduceMotion) {
            _pageController.jumpToPage(current - 1);
          } else {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          }
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
        final next = (pos.pixels + step).clamp(0.0, pos.maxScrollExtent);
        if (_reduceMotion) {
          _scrollController.jumpTo(next);
        } else {
          _scrollController.animateTo(
            next,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      }
    } else {
      if (pos.pixels <= 4) {
        HapticFeedback.mediumImpact();
        _goToChapter(_chapterIndex - 1);
      } else {
        HapticFeedback.lightImpact();
        final prev = (pos.pixels - step).clamp(0.0, pos.maxScrollExtent);
        if (_reduceMotion) {
          _scrollController.jumpTo(prev);
        } else {
          _scrollController.animateTo(
            prev,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
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
                        // Chapters before the current position count as read.
                        final read = index < _chapterIndex;
                        final scheme = Theme.of(context).colorScheme;
                        final Widget leading;
                        if (current) {
                          leading = Icon(Icons.play_arrow, color: scheme.primary);
                        } else if (read) {
                          leading = Icon(
                            Icons.check_circle,
                            size: 20,
                            color: scheme.primary.withValues(alpha: 0.55),
                          );
                        } else {
                          leading = Icon(
                            Icons.circle_outlined,
                            size: 20,
                            color: scheme.outlineVariant,
                          );
                        }
                        return ListTile(
                          selected: current,
                          leading: leading,
                          title: Text(
                            chapter.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: read && !current
                                ? TextStyle(color: scheme.outline)
                                : null,
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
    if (listenMode) return buildListenView(book, preset);
    final mq = MediaQuery.of(context);
    // Centred-column mode caps the reading area to a comfortable measure and
    // centres it (wide side gutters); otherwise it spans the screen. TV mode
    // ignores the cap: its two-column spread needs the whole display (it
    // applies its own overscan-safe insets), and squeezing a spread into the
    // 620px column made two unreadably narrow strips on big screens.
    final areaWidth = _settings.centeredColumn && !_settings.tvMode
        ? math.min(mq.size.width, _centeredColumnWidth)
        : mq.size.width;
    _lastContentWidth = areaWidth - 2 * _settings.margin;
    final topSpace = mq.padding.top + kTopBarHeight;
    final bottomSpace = mq.padding.bottom + kBottomBarHeight;
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
            onLongPressStart: _onContentLongPress,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: contentPadding,
                    child: Center(
                      child: SizedBox(
                        width: areaWidth,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onScrollNotification,
                          child: _settings.mode == ReadingMode.paged
                              ? _buildPaged(preset)
                              : _buildScroll(preset),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_settings.lineFocus)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: contentPadding,
                        child: LineFocusOverlay(
                          background: preset.background,
                          bandHeight: _rulerBandHeight,
                          // Paged: the band steps down the static page.
                          // Scroll: fixed teleprompter position.
                          bandTop: _settings.mode == ReadingMode.paged
                              ? _rulerBand * _rulerBandHeight
                              : null,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _fadeChrome(
                    ReaderTopBar(
                      height: topSpace,
                      title: book.chapters[_chapterIndex].title,
                      preset: preset,
                      onBack: () => Navigator.of(context).pop(),
                      onToggleListen: toggleListen,
                      onOpenSettings: _openSettings,
                      onShowContents: _showTableOfContents,
                      onSearch: _openSearch,
                      onBookmarks: _openBookmarks,
                      onGlossary: _openGlossary,
                      onOpenSkip: _openSkipMenu,
                      onOpenPronunciations: openPronunciations,
                      onPrepareOffline: prepareVolumeForOffline,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _fadeChrome(
                    ReaderChapterBar(
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
                      onJump: (delta) => _goToChapter(_chapterIndex + delta),
                      isReading:
                          ttsEngine.state != TtsPlaybackState.stopped,
                      isPlaying:
                          ttsEngine.state == TtsPlaybackState.playing,
                      canSeek: ttsEngine is NetworkTtsService,
                      onPlayPause: toggleTts,
                      onBack15: () => nudgeTts(-15),
                      onForward15: () => nudgeTts(15),
                    ),
                  ),
                ),
                if (ttsPrepTotal > 0 && ttsPrepDone < ttsPrepTotal)
                  Positioned(
                    top: topSpace + 8,
                    left: 0,
                    right: 0,
                    child: _fadeChrome(Center(child: ttsPrepChip(preset))),
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
        vertical: kContentVPad,
      ),
      itemCount: blocks.length,
      itemBuilder: (context, index) => BlockView(
        block: blocks[index],
        settings: _settings,
        preset: preset,
        highlightStart: index == speakingBlock ? speakingStart : null,
        highlightEnd: index == speakingBlock ? speakingEnd : null,
        highlightColor: _highlightedBlocks[index],
      ),
    );
  }

  Widget _buildPaged(ReaderThemePreset preset) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stride = _pageStride;
        // TV title-safe area: most TVs (and AirPlay receivers) clip ~5% off
        // each edge via overscan, so insetting the reader keeps text from
        // spilling off the visible screen.
        final tvSafeH = _settings.tvMode ? constraints.maxWidth * 0.055 : 0.0;
        final tvSafeV = _settings.tvMode ? constraints.maxHeight * 0.04 : 0.0;
        final usableWidth = constraints.maxWidth - 2 * tvSafeH;
        final usableHeight = constraints.maxHeight - 2 * tvSafeV;
        // TV mode splits the viewport into two side-by-side columns with a
        // fixed gutter between them, so each column is sized like a normal
        // page and the two texts don't visually run together.
        const columnGutter = 36.0;
        final gutterTotal = columnGutter * (stride - 1);
        final colWidth =
            ((usableWidth - gutterTotal) / stride) - 2 * _settings.margin;
        final height = usableHeight - 2 * kContentVPad;
        final key =
            '$_chapterIndex:${colWidth.round()}x${height.round()}'
            ':${_settings.fontSize}:${_settings.lineHeight}'
            ':${_settings.fontFamily}:$_fontToken'
            ':${_settings.boldText}:${_settings.italicText}'
            ':$stride';
        if (key != _pageKey) {
          _pageKey = key;
          _pages = paginateBlocks(_blocks ?? const [], colWidth, height, _settings);
          final pageCount = _pages?.length ?? 1;
          final spreadCount = (pageCount / stride).ceil().clamp(1, 1 << 30);
          final int wanted;
          if (_pendingRestoreBlock != null) {
            wanted = _pageForBlockAt(
              _pendingRestoreBlock!,
              _pendingRestoreChar,
            );
            _pendingRestoreBlock = null;
            _pendingRestoreChar = 0;
          } else if (_pageJumpTarget == kLastPage) {
            wanted = spreadCount - 1;
          } else {
            wanted = _pageJumpTarget;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_pageController.hasClients) return;
            _pageController.jumpToPage(wanted.clamp(0, spreadCount - 1));
            _saveProgress();
          });
        }
        final pages = _pages ?? const <List<PageBlock>>[];
        final spreadCount = (pages.length / stride).ceil().clamp(1, 1 << 30);
        final pager = PageView.builder(
          controller: _pageController,
          itemCount: spreadCount,
          itemBuilder: (context, spreadIndex) {
            if (stride == 1) {
              return _buildPagedColumn(pages, spreadIndex, preset);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < stride; c++) ...[
                  if (c > 0) const SizedBox(width: columnGutter),
                  Expanded(
                    child: _buildPagedColumn(
                      pages,
                      spreadIndex * stride + c,
                      preset,
                    ),
                  ),
                ],
              ],
            );
          },
        );
        if (!_settings.tvMode) return pager;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tvSafeH,
            vertical: tvSafeV,
          ),
          child: pager,
        );
      },
    );
  }

  /// Renders one paginated page slice (a single column). Used directly in
  /// single-column paged mode, and twice side-by-side per spread in TV mode.
  /// Out-of-range page indices (the right-hand column of an odd-last spread)
  /// render an empty placeholder so the spread keeps its width.
  Widget _buildPagedColumn(
    List<List<PageBlock>> pages,
    int pageIndex,
    ReaderThemePreset preset,
  ) {
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return const SizedBox.shrink();
    }
    final pageBlocks = pages[pageIndex];
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _settings.margin,
        vertical: kContentVPad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var j = 0; j < pageBlocks.length; j++)
            BlockView(
              block: pageBlocks[j].block,
              settings: _settings,
              preset: preset,
              isLast: j == pageBlocks.length - 1,
              // The highlight range is in parent-block coordinates;
              // shift it into this slice's own coordinates.
              highlightStart: pageBlocks[j].originIndex == speakingBlock
                  ? speakingStart - pageBlocks[j].charOffset
                  : null,
              highlightEnd: pageBlocks[j].originIndex == speakingBlock
                  ? speakingEnd - pageBlocks[j].charOffset
                  : null,
              highlightColor: _highlightedBlocks[pageBlocks[j].originIndex],
            ),
        ],
      ),
    );
  }
}
