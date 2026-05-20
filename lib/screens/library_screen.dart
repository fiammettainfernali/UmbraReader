import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/opds_client.dart';
import '../services/settings_service.dart';
import 'settings_screen.dart';

/// The home screen — a cover grid of every series synced from the OPDS library.
///
/// Phase 3 milestone: connect to the server and browse the library. Downloading
/// EPUBs for offline reading comes in the next step.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _settingsService = SettingsService();

  /// Null until the initial settings load finishes.
  OpdsSettings? _settings;
  List<Series>? _library;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() => _settings = settings);
    if (settings.isConfigured) {
      await _sync();
    }
  }

  Future<void> _sync() async {
    final settings = _settings;
    if (settings == null || !settings.isConfigured) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final library = await OpdsClient(settings).fetchLibrary();
      library.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _library = library;
        _loading = false;
      });
    } on OpdsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsScreen(initial: _settings ?? OpdsSettings.empty),
      ),
    );
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() => _settings = settings);
    if (settings.isConfigured) await _sync();
  }

  @override
  Widget build(BuildContext context) {
    final count = _library?.length;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _sync,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('Library'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Server settings',
                  onPressed: _openSettings,
                ),
              ],
            ),
            if (count != null && count > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    '$count series',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
            _buildContentSliver(),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSliver() {
    if (_settings == null || _loading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_settings!.isConfigured) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _MessageView(
          icon: Icons.cloud_off_outlined,
          title: 'Not connected',
          message:
              'Connect Umbra Reader to your Novel Grabber library to see your '
              'books here.',
          actionLabel: 'Connect',
          onAction: _openSettings,
        ),
      );
    }
    if (_error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _MessageView(
          icon: Icons.error_outline,
          title: 'Sync failed',
          message: _error!,
          actionLabel: 'Retry',
          onAction: _sync,
        ),
      );
    }
    final library = _library ?? const <Series>[];
    if (library.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _MessageView(
          icon: Icons.library_books_outlined,
          title: 'No books found',
          message:
              'The library is empty, or no series have a compiled EPUB yet.',
          actionLabel: 'Refresh',
          onAction: _sync,
        ),
      );
    }
    final imageHeaders = OpdsClient(_settings!).authHeaders;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          childAspectRatio: 0.52,
          crossAxisSpacing: 16,
          mainAxisSpacing: 20,
        ),
        itemCount: library.length,
        itemBuilder: (context, index) =>
            _SeriesCard(series: library[index], imageHeaders: imageHeaders),
      ),
    );
  }
}

/// A single cover in the library grid: cover art, title, author.
class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.series, required this.imageHeaders});

  final Series series;
  final Map<String, String> imageHeaders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CoverImage(series: series, headers: imageHeaders),
                  if (series.hasMultipleVolumes)
                    const Positioned(top: 6, right: 6, child: _VolumeBadge()),
                ],
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
    );
  }
}

/// Cover art for a series — the network image, or a titled gradient fallback
/// when there is no cover or it fails to load.
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.series, required this.headers});

  final Series series;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final coverUrl = series.coverUrl;
    if (coverUrl == null) return _fallback(context);
    return Image.network(
      coverUrl,
      headers: headers,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _fallback(context),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        );
      },
    );
  }

  /// A gradient panel showing the title — looks intentional, not broken.
  Widget _fallback(BuildContext context) {
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
            series.title,
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

/// Small corner badge marking a series that has more than one volume.
class _VolumeBadge extends StatelessWidget {
  const _VolumeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.collections_bookmark,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}

/// A centered icon + message + action button, used for the empty / error /
/// not-connected states.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
