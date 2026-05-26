import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../models/series.dart';
import '../services/collection_store.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/opds_client.dart';
import '../services/settings_service.dart';
import '../widgets/cached_cover.dart';
import 'series_detail_screen.dart';

/// Cover grid for a single user collection. Series are resolved from the
/// library cache by id, so works offline as long as the library has been
/// synced once.
class CollectionDetailScreen extends StatefulWidget {
  const CollectionDetailScreen({
    super.key,
    required this.collection,
    required this.settings,
  });

  final Collection collection;
  final OpdsSettings settings;

  @override
  State<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  late Collection _current;
  List<Series>? _series;

  @override
  void initState() {
    super.initState();
    _current = widget.collection;
    _load();
  }

  Future<void> _load() async {
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    // Refresh the collection — its membership may have changed in the
    // "Add to collection" sheet while we're on screen.
    final all = await CollectionStore().list();
    final fresh = all.firstWhere(
      (c) => c.id == _current.id,
      orElse: () => _current,
    );
    final byId = {for (final s in cache.series) s.opdsId: s};
    final list = <Series>[
      for (final id in fresh.seriesIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
    if (!mounted) return;
    setState(() {
      _current = fresh;
      _series = list;
    });
  }

  Future<void> _open(Series series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeriesDetailScreen(
          series: series,
          settings: widget.settings,
        ),
      ),
    );
    // Membership might have changed.
    await _load();
  }

  Future<void> _remove(Series series) async {
    await CollectionStore().setMembership(
      _current.id,
      series.opdsId,
      member: false,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = _series;
    return Scaffold(
      appBar: AppBar(title: Text(_current.name)),
      body: series == null
          ? const Center(child: CircularProgressIndicator())
          : series.isEmpty
          ? _empty(theme)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 0.52,
                crossAxisSpacing: 16,
                mainAxisSpacing: 20,
              ),
              itemCount: series.length,
              itemBuilder: (context, index) {
                final s = series[index];
                return _CollectionCard(
                  series: s,
                  imageHeaders: OpdsClient(widget.settings).authHeaders,
                  onTap: () => _open(s),
                  onRemove: () => _remove(s),
                );
              },
            ),
    );
  }

  Widget _empty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No books in this collection',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Open a series in your library and tap "Add to collection".',
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

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.series,
    required this.imageHeaders,
    required this.onTap,
    required this.onRemove,
  });

  final Series series;
  final Map<String, String> imageHeaders;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _confirmRemove(context),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedCover(
                  seriesId: series.opdsId,
                  coverUrl: series.coverUrl,
                  headers: imageHeaders,
                  fallback: _GradientFallback(title: series.title),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            series.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            series.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Remove "${series.title}"?'),
        content: const Text(
          'This removes the book from this collection. It stays in your '
          'library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) onRemove();
  }
}

class _GradientFallback extends StatelessWidget {
  const _GradientFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}
