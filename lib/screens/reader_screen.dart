import 'package:flutter/material.dart';

import '../models/content_block.dart';
import '../models/epub_book.dart';
import '../models/volume.dart';
import '../services/epub_parser.dart';
import '../services/library_storage.dart';
import '../services/reading_progress_store.dart';

/// Reads a downloaded volume: parses the EPUB and renders its chapters with
/// chapter navigation and a table of contents.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.volume});

  final Volume volume;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _progressStore = ReadingProgressStore();
  final _scrollController = ScrollController();

  EpubParser? _parser;
  EpubBook? _book;
  int _chapterIndex = 0;
  List<ContentBlock>? _blocks;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final file = await LibraryStorage().epubFile(widget.volume);
      if (!file.existsSync()) {
        setState(() {
          _error = 'This volume is not downloaded.';
          _loading = false;
        });
        return;
      }
      final parser = EpubParser();
      final book = await parser.open(file);
      if (book.chapters.isEmpty) {
        setState(() {
          _error = 'No readable chapters were found in this book.';
          _loading = false;
        });
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
        _loading = false;
      });
    } on EpubException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _goToChapter(int index) {
    final book = _book;
    final parser = _parser;
    if (book == null || parser == null) return;
    final clamped = index.clamp(0, book.chapters.length - 1);
    if (clamped == _chapterIndex && _blocks != null) return;
    final blocks = parser.parseChapter(book.chapters[clamped]);
    setState(() {
      _chapterIndex = clamped;
      _blocks = blocks;
    });
    _progressStore.saveChapterIndex(widget.volume, clamped);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
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

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final chapterTitle = (book != null && _blocks != null)
        ? book.chapters[_chapterIndex].title
        : widget.volume.title;
    return Scaffold(
      appBar: AppBar(
        title: Text(chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (book != null)
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: 'Contents',
              onPressed: _showTableOfContents,
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: (book != null && _blocks != null)
          ? _ChapterBar(
              index: _chapterIndex,
              total: book.chapters.length,
              onPrevious: () => _goToChapter(_chapterIndex - 1),
              onNext: () => _goToChapter(_chapterIndex + 1),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    final blocks = _blocks ?? const <ContentBlock>[];
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: blocks.length,
      itemBuilder: (context, index) => _BlockView(block: blocks[index]),
    );
  }
}

/// Renders one [ContentBlock] with comfortable reading typography.
///
/// Typography is fixed for now; Phase 4's theme engine will make font, size,
/// spacing and colour configurable.
class _BlockView extends StatelessWidget {
  const _BlockView({required this.block});

  final ContentBlock block;

  static const _baseStyle = TextStyle(fontSize: 18, height: 1.62);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    switch (block) {
      case ParagraphBlock paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text.rich(
            TextSpan(
              children: _spans(
                paragraph.runs,
                _baseStyle.copyWith(color: textColor),
              ),
            ),
          ),
        );
      case HeadingBlock heading:
        final size = heading.level <= 2
            ? 24.0
            : heading.level <= 4
            ? 21.0
            : 19.0;
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          child: Text.rich(
            TextSpan(
              children: _spans(
                heading.runs,
                _baseStyle.copyWith(
                  color: textColor,
                  fontSize: size,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
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

  List<InlineSpan> _spans(List<TextRun> runs, TextStyle base) {
    return [
      for (final run in runs)
        TextSpan(
          text: run.text,
          style: base.copyWith(
            fontWeight: run.bold ? FontWeight.bold : null,
            fontStyle: run.italic ? FontStyle.italic : null,
          ),
        ),
    ];
  }
}

/// Bottom bar: previous / position / next chapter.
class _ChapterBar extends StatelessWidget {
  const _ChapterBar({
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int index;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: 56,
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
    );
  }
}
