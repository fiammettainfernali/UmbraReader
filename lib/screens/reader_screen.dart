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
import '../services/reader_preferences.dart';
import '../services/reading_progress_store.dart';
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
  final base = TextStyle(fontSize: s.fontSize, height: s.lineHeight, color: color);
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

  /// Overscroll accumulated past a content edge during the current drag —
  /// used to cross into the previous/next chapter on a swipe past the end.
  double _edgeOverscroll = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
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
      final saved = await _progressStore.chapterIndexFor(widget.volume);
      final index = saved.clamp(0, book.chapters.length - 1);
      final blocks = parser.parseChapter(book.chapters[index]);
      if (!mounted) return;
      setState(() {
        _parser = parser;
        _book = book;
        _chapterIndex = index;
        _blocks = blocks;
        _settings = settings;
        _loading = false;
      });
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

  void _goToChapter(int index, {bool landOnLastPage = false}) {
    final book = _book;
    final parser = _parser;
    if (book == null || parser == null) return;
    final clamped = index.clamp(0, book.chapters.length - 1);
    if (clamped == _chapterIndex && _blocks != null) return;
    final blocks = parser.parseChapter(book.chapters[clamped]);
    setState(() {
      _chapterIndex = clamped;
      _blocks = blocks;
      _pageKey = null;
      _pageJumpTarget = landOnLastPage ? _lastPage : 0;
    });
    _progressStore.saveChapterIndex(widget.volume, clamped);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_settings.mode == ReadingMode.scroll && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
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
    final currentPage = _pageController.hasClients
        ? (_pageController.page?.round() ?? 0)
        : 0;
    setState(() {
      _settings = next;
      _pageJumpTarget = currentPage;
    });
    ReaderPreferences().save(next);
    if (fontChanged) {
      await _preloadFont(next.fontFamily);
      if (mounted) setState(() => _fontToken++);
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          ReaderSettingsSheet(initial: _settings, onChanged: _applySettings),
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

    if (notification is ScrollStartNotification) {
      _edgeOverscroll = 0;
    } else if (notification is OverscrollNotification) {
      _edgeOverscroll += notification.overscroll;
    } else if (notification is ScrollEndNotification) {
      final amount = _edgeOverscroll;
      _edgeOverscroll = 0;
      if (amount > 90) {
        _goToChapter(_chapterIndex + 1);
      } else if (amount < -90) {
        _goToChapter(_chapterIndex - 1, landOnLastPage: true);
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
                      onBack: () => Navigator.of(context).pop(),
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
      itemBuilder: (context, index) =>
          _BlockView(block: blocks[index], settings: _settings, preset: preset),
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
            ':${_settings.fontFamily}:$_fontToken';
        if (key != _pageKey) {
          _pageKey = key;
          _pages = _paginate(_blocks ?? const [], width, height, _settings);
          final target = _pageJumpTarget;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_pageController.hasClients) return;
            final pageCount = _pages?.length ?? 1;
            final wanted = target == _lastPage ? pageCount - 1 : target;
            _pageController.jumpToPage(wanted.clamp(0, pageCount - 1));
          });
        }
        final pages = _pages ?? const <List<ContentBlock>>[];
        return PageView.builder(
          controller: _pageController,
          itemCount: pages.length,
          itemBuilder: (context, index) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: _settings.margin,
              vertical: _contentVPad,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final block in pages[index])
                  _BlockView(
                    block: block,
                    settings: _settings,
                    preset: preset,
                  ),
              ],
            ),
          ),
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
  });

  final ContentBlock block;
  final ReaderSettings settings;
  final ReaderThemePreset preset;

  @override
  Widget build(BuildContext context) {
    switch (block) {
      case ParagraphBlock paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: _paragraphGap),
          child: Text.rich(
            _runSpan(paragraph.runs, _paragraphStyle(settings, preset.text)),
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
            _runSpan(
              heading.runs,
              _headingStyle(settings, heading.level, preset.text),
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
}

/// Overlay top bar: back, chapter title, reading settings, contents.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.height,
    required this.title,
    required this.preset,
    required this.onBack,
    required this.onOpenSettings,
    required this.onShowContents,
  });

  final double height;
  final String title;
  final ReaderThemePreset preset;
  final VoidCallback onBack;
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
    required this.onPrevious,
    required this.onNext,
  });

  final double height;
  final ReaderThemePreset preset;
  final int index;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: preset.background,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      child: SizedBox(
        height: height,
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
                child: Center(
                  child: Text(
                    'Chapter ${index + 1} of $total',
                    style: TextStyle(color: preset.secondary, fontSize: 12),
                  ),
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
    );
  }
}
