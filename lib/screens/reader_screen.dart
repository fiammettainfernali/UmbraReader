import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/content_block.dart';
import '../models/epub_book.dart';
import '../models/volume.dart';
import '../services/epub_parser.dart';
import '../services/library_storage.dart';
import '../services/reader_preferences.dart';
import '../services/reading_progress_store.dart';

// Reading layout constants — shared by rendering and pagination so the two
// always agree.
const double _readingHPad = 20;
const double _contentVPad = 8;
const double _topBarHeight = 56;
const double _bottomBarHeight = 56;
const double _paragraphGap = 16;
const double _headingTopGap = 12;
const double _headingBottomGap = 16;
const double _dividerHeight = 60;

/// Sentinel for "jump to the last page" when paging backward into a chapter.
const int _lastPage = -1;

TextStyle _paragraphStyle(Color color) =>
    TextStyle(fontSize: 18, height: 1.62, color: color);

TextStyle _headingStyle(int level, Color color) => TextStyle(
  fontSize: level <= 2
      ? 24
      : level <= 4
      ? 21
      : 19,
  height: 1.3,
  fontWeight: FontWeight.w700,
  color: color,
);

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
double _measureBlockHeight(ContentBlock block, double width) {
  switch (block) {
    case ParagraphBlock paragraph:
      final painter = TextPainter(
        text: _runSpan(paragraph.runs, _paragraphStyle(const Color(0xFF000000))),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: width);
      return painter.height + _paragraphGap;
    case HeadingBlock heading:
      final painter = TextPainter(
        text: _runSpan(
          heading.runs,
          _headingStyle(heading.level, const Color(0xFF000000)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: width);
      return painter.height + _headingTopGap + _headingBottomGap;
    case DividerBlock _:
      return _dividerHeight;
  }
}

/// Greedily packs whole blocks into pages no taller than [height]. Blocks are
/// never split, so lines are never cut across a page boundary.
List<List<ContentBlock>> _paginate(
  List<ContentBlock> blocks,
  double width,
  double height,
) {
  final pages = <List<ContentBlock>>[];
  var current = <ContentBlock>[];
  var used = 0.0;
  for (final block in blocks) {
    final blockHeight = _measureBlockHeight(block, width);
    if (current.isNotEmpty && used + blockHeight > height) {
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
/// scroll or paged layout, an immersive (fade-away) chrome, chapter navigation
/// and keyboard/remote support.
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

  ReadingMode _mode = ReadingMode.scroll;
  bool _chromeVisible = true;

  // Paged-mode pagination cache.
  List<List<ContentBlock>>? _pages;
  String? _pageKey;
  int _pageJumpTarget = 0;

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
    final mode = await ReaderPreferences().loadMode();
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
        _mode = mode;
        _loading = false;
      });
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
      _pageKey = null; // force re-pagination
      _pageJumpTarget = landOnLastPage ? _lastPage : 0;
    });
    _progressStore.saveChapterIndex(widget.volume, clamped);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mode == ReadingMode.scroll && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  void _setMode(ReadingMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _pageKey = null;
      _pageJumpTarget = 0;
    });
    ReaderPreferences().saveMode(mode);
  }

  // ── navigation ───────────────────────────────────────────────────────────

  void _advance({required bool forward}) {
    if (_mode == ReadingMode.paged) {
      final pages = _pages ?? const [];
      final page = (_pageController.hasClients ? _pageController.page : 0)
          ?.round();
      final current = page ?? 0;
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
    // Scroll mode: move by ~one screen, spilling into the next/prev chapter.
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
    final mq = MediaQuery.of(context);
    final topSpace = mq.padding.top + _topBarHeight;
    final bottomSpace = mq.padding.bottom + _bottomBarHeight;

    return Scaffold(
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
                  padding: EdgeInsets.only(top: topSpace, bottom: bottomSpace),
                  child: _mode == ReadingMode.paged
                      ? _buildPaged()
                      : _buildScroll(),
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
                    mode: _mode,
                    onBack: () => Navigator.of(context).pop(),
                    onShowContents: _showTableOfContents,
                    onSelectMode: _setMode,
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
    );
  }

  Widget _fadeChrome(Widget child) {
    return AnimatedOpacity(
      opacity: _chromeVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(ignoring: !_chromeVisible, child: child),
    );
  }

  Widget _buildScroll() {
    final blocks = _blocks ?? const <ContentBlock>[];
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: _readingHPad,
        vertical: _contentVPad,
      ),
      itemCount: blocks.length,
      itemBuilder: (context, index) => _BlockView(block: blocks[index]),
    );
  }

  Widget _buildPaged() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 2 * _readingHPad;
        final height = constraints.maxHeight - 2 * _contentVPad;
        final key = '$_chapterIndex:${width.round()}x${height.round()}';
        if (key != _pageKey) {
          _pageKey = key;
          _pages = _paginate(_blocks ?? const [], width, height);
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
            padding: const EdgeInsets.symmetric(
              horizontal: _readingHPad,
              vertical: _contentVPad,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final block in pages[index]) _BlockView(block: block),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Renders one [ContentBlock] with comfortable reading typography.
///
/// Typography is fixed for now; the theme engine will make font, size,
/// spacing and colour configurable.
class _BlockView extends StatelessWidget {
  const _BlockView({required this.block});

  final ContentBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface;

    switch (block) {
      case ParagraphBlock paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: _paragraphGap),
          child: Text.rich(
            _runSpan(paragraph.runs, _paragraphStyle(color)),
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
            _runSpan(heading.runs, _headingStyle(heading.level, color)),
            textScaler: TextScaler.noScaling,
          ),
        );
      case DividerBlock _:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              '✶  ✶  ✶',
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 16),
            ),
          ),
        );
    }
  }
}

/// Overlay top bar: back, chapter title, reading-mode menu, contents.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.height,
    required this.title,
    required this.mode,
    required this.onBack,
    required this.onShowContents,
    required this.onSelectMode,
  });

  final double height;
  final String title;
  final ReadingMode mode;
  final VoidCallback onBack;
  final VoidCallback onShowContents;
  final ValueChanged<ReadingMode> onSelectMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      child: SizedBox(
        height: height,
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              PopupMenuButton<ReadingMode>(
                icon: const Icon(Icons.view_agenda_outlined),
                tooltip: 'Reading mode',
                initialValue: mode,
                onSelected: onSelectMode,
                itemBuilder: (context) => [
                  _modeItem(ReadingMode.scroll, 'Scroll', Icons.swap_vert),
                  _modeItem(ReadingMode.paged, 'Paged', Icons.auto_stories),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.list),
                tooltip: 'Contents',
                onPressed: onShowContents,
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<ReadingMode> _modeItem(
    ReadingMode value,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem<ReadingMode>(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: value == mode ? const Icon(Icons.check, size: 18) : null,
          ),
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

/// Overlay bottom bar: previous / position / next chapter.
class _ChapterBar extends StatelessWidget {
  const _ChapterBar({
    required this.height,
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final double height;
  final int index;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      child: SizedBox(
        height: height,
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous chapter',
                onPressed: index > 0 ? onPrevious : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Chapter ${index + 1} of $total',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
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
