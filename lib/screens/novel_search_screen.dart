import 'package:flutter/material.dart';

import '../services/control_client.dart';
import '../services/settings_service.dart';

/// Searches a source site (via Novel Grabber's control API) and lets the user
/// add a result to the library, which kicks off a scrape on the server.
class NovelSearchScreen extends StatefulWidget {
  const NovelSearchScreen({
    super.key,
    required this.settings,
    required this.sites,
  });

  final OpdsSettings settings;

  /// Searchable source SITE_NAMEs (from /api/status → searchSites).
  final List<String> sites;

  @override
  State<NovelSearchScreen> createState() => _NovelSearchScreenState();
}

class _NovelSearchScreenState extends State<NovelSearchScreen> {
  late final ControlClient _client = ControlClient(widget.settings);
  final _controller = TextEditingController();

  late String _site = widget.sites.isNotEmpty ? widget.sites.first : '';
  List<SearchHit>? _results;
  bool _loading = false;
  String? _error;
  final Set<String> _added = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _site.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _client.search(q, site: _site);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _add(SearchHit hit) async {
    try {
      await _client.addNovel(hit.url);
      if (!mounted) return;
      setState(() => _added.add(hit.url));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added “${hit.title}” — scraping started.')),
      );
    } on ControlException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Find novels')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'Search by title',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(_controller.clear),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  'Source:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _site.isEmpty ? null : _site,
                  hint: const Text('Pick a site'),
                  items: [
                    for (final s in widget.sites)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setState(() => _site = v ?? _site),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  child: const Text('Search'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final results = _results;
    if (results == null) {
      return Center(
        child: Text(
          'Search a source for novels to add.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No results.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final hit = results[i];
        final added = _added.contains(hit.url);
        return ListTile(
          leading: SizedBox(
            width: 44,
            height: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: hit.coverUrl.isEmpty
                  ? _coverFallback(theme)
                  : Image.network(
                      hit.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _coverFallback(theme),
                    ),
            ),
          ),
          title: Text(hit.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (hit.author.isNotEmpty) hit.author,
              if (hit.latestChapter.isNotEmpty) hit.latestChapter,
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          trailing: added
              ? Icon(Icons.check, color: theme.colorScheme.primary)
              : IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add to library',
                  onPressed: () => _add(hit),
                ),
        );
      },
    );
  }

  Widget _coverFallback(ThemeData theme) => ColoredBox(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.menu_book_outlined,
      size: 18,
      color: theme.colorScheme.outline,
    ),
  );
}
