import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_block.dart';
import '../models/epub_book.dart';
import '../services/epub_parser.dart';

/// One full-text search match within the open book.
class SearchHit {
  const SearchHit({
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
/// [SearchHit] back to the reader.
class BookSearchScreen extends StatefulWidget {
  const BookSearchScreen({
    super.key,
    required this.parser,
    required this.book,
    required this.plainText,
  });

  final EpubParser parser;
  final EpubBook book;

  /// Extracts a block's plain text — shared with the reader so matches line up.
  final String Function(ContentBlock block) plainText;

  @override
  State<BookSearchScreen> createState() => _BookSearchScreenState();
}

class _BookSearchScreenState extends State<BookSearchScreen> {
  static const _maxHits = 200;

  final _controller = TextEditingController();
  Timer? _debounce;

  /// Bumped on every new search so a slower stale search can bail out.
  int _searchToken = 0;
  bool _searching = false;
  String _query = '';
  List<SearchHit> _hits = const [];

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
    final hits = <SearchHit>[];
    for (var ci = 0; ci < widget.book.chapters.length; ci++) {
      if (token != _searchToken) return;
      final chapter = widget.book.chapters[ci];
      final blocks = widget.parser.parseChapter(chapter);
      for (var bi = 0; bi < blocks.length; bi++) {
        final text = widget.plainText(blocks[bi]);
        final idx = text.toLowerCase().indexOf(needle);
        if (idx < 0) continue;
        hits.add(_buildHit(ci, bi, chapter.title, text, idx, needle.length));
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
  SearchHit _buildHit(
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
    return SearchHit(
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
