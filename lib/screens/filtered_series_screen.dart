import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/opds_client.dart';
import '../services/settings_service.dart';
import '../widgets/cached_cover.dart';
import 'series_detail_screen.dart';

/// A cover grid showing every series in the library that matches a predicate
/// — used as the destination when you tap an author name or a genre chip on
/// a series detail screen. Reads from the cached library so it works offline.
class FilteredSeriesScreen extends StatefulWidget {
  const FilteredSeriesScreen({
    super.key,
    required this.title,
    required this.predicate,
    required this.settings,
    this.emptyMessage,
  });

  final String title;
  final bool Function(Series) predicate;
  final OpdsSettings settings;

  /// Optional override for the empty-state body. Defaults to a generic
  /// message when null.
  final String? emptyMessage;

  @override
  State<FilteredSeriesScreen> createState() => _FilteredSeriesScreenState();
}

class _FilteredSeriesScreenState extends State<FilteredSeriesScreen> {
  List<Series>? _series;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    final matches = [
      for (final s in cache.series) if (widget.predicate(s)) s,
    ];
    matches.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    if (!mounted) return;
    setState(() => _series = matches);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = _series;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: series == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      series.length == 1
                          ? '1 series'
                          : '${series.length} series',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ),
      ),
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
                return _FilteredCard(
                  series: s,
                  imageHeaders: OpdsClient(widget.settings).authHeaders,
                  onTap: () => _open(s),
                );
              },
            ),
    );
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
    await _load();
  }

  Widget _empty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing matches',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              widget.emptyMessage ??
                  'Your library has no series matching this filter.',
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

class _FilteredCard extends StatelessWidget {
  const _FilteredCard({
    required this.series,
    required this.imageHeaders,
    required this.onTap,
  });

  final Series series;
  final Map<String, String> imageHeaders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
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
                  fallback: _Fallback(title: series.title),
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
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.title});

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
