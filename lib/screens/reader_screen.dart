import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/content_block.dart';
import '../models/epub_book.dart';
import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../models/volume.dart';
import '../services/epub_parser.dart';
import '../services/library_storage.dart';
import '../services/now_playing_service.dart';
import '../services/reader_preferences.dart';
import '../services/reading_progress_store.dart';
import '../services/tts_service.dart';
import '../widgets/reader_settings_sheet.dart';

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
  }
}

/// Greedily packs whole blocks into pages. Blocks are never split, so a line
/// is never cut across a page boundary.
///
/// Block-height estimation isn't pixel-exact, so pages are packed to only a
/// fraction of the real height — the headroom guarantees content fits rather
/// than overflowing into a scroll, at the cost of a little bottom margin.
List<List<ContentBlock>> _paginate(
  List<ContentBlock> blocks,
  double width,
  double height,
  ReaderSettings settings,
) {
  const fillFactor = 0.93;
  final budget = height * fillFactor;
  final pages = <List<ContentBlock>>[];
  var current = <ContentBlock>[];
  var used = 0.0;
  for (final block in blocks) {
    final blockHeight = _measureBlockHeight(block, width, settings);
    if (current.isNotEmpty && used + blockHeight > budget) {
      pages.add(current);
      current = <ContentBlock>[];
      used = 0;
    }
    current.add(block);
    used += blockHeight;
  }
  if (current.isNotEmpty) pages.add(current);
  if (pages.isEmpty) pages.add(const <ContentBlock>[]);
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

class _ReaderScreenState extends State<ReaderScreen> {
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
  List<List<ContentBlock>>? _pages;
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

  /// Active sleep-timer choice and its countdown.
  SleepTimerOption _sleepOption = SleepTimerOption.off;
  Timer? _sleepTimer;

  /// Progress through the current chapter (0..1) and its total word count —
  /// drive the reading-progress bar and the "time left" estimate.
  double _chapterFraction = 0;
  int _chapterWordCount = 0;

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
    _open();
  }

  @override
  void dispose() {
    _saveProgress();
    _sleepTimer?.cancel();
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
        _settings = settings;
        _pendingRestoreBlock = blocks.isEmpty
            ? 0
            : progress.blockIndex.clamp(0, blocks.length - 1);
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restoreScrollPosition(),
      );
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
    var index = 0;
    for (var i = 0; i < page; i++) {
      index += pages[i].length;
    }
    return index;
  }

  /// The page that contains [blockIndex] in paged mode.
  int _pageForBlock(int blockIndex) {
    final pages = _pages ?? const <List<ContentBlock>>[];
    var acc = 0;
    for (var i = 0; i < pages.length; i++) {
      acc += pages[i].length;
      if (blockIndex < acc) return i;
    }
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

  Future<void> _applySettings(ReaderSettings next) async {
    final fontChanged = next.fontFamily != _settings.fontFamily;
    final rateChanged = next.speechRate != _settings.speechRate;
    final voiceChanged =
        next.voiceName != _settings.voiceName ||
        next.voiceLocale != _settings.voiceLocale;
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
  }

  // ── read-aloud ───────────────────────────────────────────────────────────

  /// Plain text of a block — exactly the runs as rendered, so TTS word
  /// offsets line up with the on-screen text for highlighting.
  String _blockText(ContentBlock block) => switch (block) {
    ParagraphBlock p => p.runs.map((r) => r.text).join(),
    HeadingBlock h => h.runs.map((r) => r.text).join(),
    DividerBlock _ => '',
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
    if (blockIndex == _followedBlock) return;
    _followedBlock = blockIndex;
    if (_settings.mode == ReadingMode.paged) {
      if (!_pageController.hasClients) return;
      final page = _pageForBlock(blockIndex);
      if ((_pageController.page?.round() ?? 0) != page) {
        _pageController.animateToPage(
          page,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else {
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
      builder: (_) => ReaderSettingsSheet(
        initial: _settings,
        voices: voices,
        sleepOption: _sleepOption,
        onChanged: _applySettings,
        onSleepTimerChanged: _setSleepTimer,
      ),
    );
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

  void _advance({required bool forward}) {
    if (_settings.mode == ReadingMode.paged) {
      final pages = _pages ?? const [];
      final current =
          (_pageController.hasClients ? _pageController.page : 0)?.round() ?? 0;
      if (forward) {
        if (current < pages.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } else {
          _goToChapter(_chapterIndex + 1);
        }
      } else {
        if (current > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } else {
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
        _goToChapter(_chapterIndex + 1);
      } else {
        _scrollController.animateTo(
          (pos.pixels + step).clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } else {
      if (pos.pixels <= 4) {
        _goToChapter(_chapterIndex - 1);
      } else {
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
                child: ListView.builder(
                  itemCount: book.chapters.length,
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
            onTap: _toggleChrome,
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
                      onPrevious: () => _goToChapter(_chapterIndex - 1),
                      onNext: () => _goToChapter(_chapterIndex + 1),
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
        final pages = _pages ?? const <List<ContentBlock>>[];
        return PageView.builder(
          controller: _pageController,
          itemCount: pages.length,
          itemBuilder: (context, pageIndex) {
            // Global block index of the first block on this page, so the
            // read-aloud highlight can be matched.
            var globalIndex = 0;
            for (var p = 0; p < pageIndex; p++) {
              globalIndex += pages[p].length;
            }
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
                      block: pageBlocks[j],
                      settings: _settings,
                      preset: preset,
                      highlightStart: (globalIndex + j) == _speakingBlock
                          ? _speakingStart
                          : null,
                      highlightEnd: (globalIndex + j) == _speakingBlock
                          ? _speakingEnd
                          : null,
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
    this.highlightStart,
    this.highlightEnd,
  });

  final ContentBlock block;
  final ReaderSettings settings;
  final ReaderThemePreset preset;

  /// Character range to highlight (the sentence being read aloud), or null.
  final int? highlightStart;
  final int? highlightEnd;

  @override
  Widget build(BuildContext context) {
    switch (block) {
      case ParagraphBlock paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: _paragraphGap),
          child: Text.rich(
            TextSpan(
              children: _spansFor(
                paragraph.runs,
                _paragraphStyle(settings, preset.text),
              ),
            ),
            textScaler: TextScaler.noScaling,
          ),
        );
      case HeadingBlock heading:
        return Padding(
          padding: const EdgeInsets.only(
            top: _headingTopGap,
            bottom: _headingBottomGap,
          ),
          child: Text.rich(
            TextSpan(
              children: _spansFor(
                heading.runs,
                _headingStyle(settings, heading.level, preset.text),
              ),
            ),
            textScaler: TextScaler.noScaling,
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
    }
  }

  /// Builds the run spans, giving the highlighted character range a
  /// background colour (splitting runs at the highlight boundaries).
  List<InlineSpan> _spansFor(List<TextRun> runs, TextStyle base) {
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
  });

  final double height;
  final String title;
  final ReaderThemePreset preset;
  final TtsPlaybackState ttsState;
  final VoidCallback onBack;
  final VoidCallback onToggleTts;
  final VoidCallback onOpenSettings;
  final VoidCallback onShowContents;

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
    required this.onPrevious,
    required this.onNext,
  });

  final double height;
  final ReaderThemePreset preset;
  final int index;
  final int total;

  /// Fraction (0..1) of the current chapter that has been read.
  final double progress;

  /// Estimated reading time remaining in the chapter, in minutes.
  final double minutesLeft;

  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// A short human label for the time left in the chapter.
  String get _timeLabel {
    if (minutesLeft < 0.5) return 'Almost done';
    if (minutesLeft < 1.5) return '~1 min left in chapter';
    return '~${minutesLeft.round()} min left in chapter';
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
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: preset.secondary.withValues(alpha: 0.25),
              color: preset.text.withValues(alpha: 0.55),
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
