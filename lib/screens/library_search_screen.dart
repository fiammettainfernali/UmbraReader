import 'dart:async';

import 'package:flutter/material.dart';

import '../services/library_search.dart';
import 'reader_screen.dart';

/// Full-text search across every downloaded book in the library. Results
/// stream in book by book; tapping a hit opens the reader at that exact
/// spot.
class LibrarySearchScreen extends StatefulWidget {
  const LibrarySearchScreen({super.key});

  @override
  State<LibrarySearchScreen> createState() => _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends State<LibrarySearchScreen> {
  final _controller = TextEditingController();
  final _search = LibrarySearch();
  Timer? _debounce;
  StreamSubscription<LibraryHit>? _subscription;

  bool _searching = false;
  String _query = '';
  List<LibraryHit> _hits = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {}); // refresh the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(value.trim());
    });
  }

  void _runSearch(String query) {
    _subscription?.cancel();
    setState(() {
      _query = query;
      _hits = const [];
      _searching = query.length >= 2;
    });
    if (query.length < 2) return;
    final collected = <LibraryHit>[];
    _subscription = _search
        .search(query)
        .listen(
          (hit) {
            collected.add(hit);
            if (!mounted) return;
            setState(() => _hits = List.of(collected));
          },
          onDone: () {
            if (mounted) setState(() => _searching = false);
          },
          onError: (Object _) {
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  Future<void> _openHit(LibraryHit hit) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          volume: hit.volume,
          initialChapterIndex: hit.chapterIndex,
          initialBlockIndex: hit.blockIndex,
        ),
      ),
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
            hintText: 'Search inside downloaded books',
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
        Icons.manage_search,
        'Search the full text of every downloaded book.',
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
                  : '${_hits.length} result${_hits.length == 1 ? '' : 's'}',
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
              // A book header row whenever the book changes.
              final showBook =
                  index == 0 ||
                  _hits[index - 1].volume.fileName != hit.volume.fileName ||
                  _hits[index - 1].volume.seriesOpdsId !=
                      hit.volume.seriesOpdsId;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showBook)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        hit.bookTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ListTile(
                    title: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: hit.snippet.substring(0, hit.matchStart),
                          ),
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
                    onTap: () => _openHit(hit),
                  ),
                ],
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
