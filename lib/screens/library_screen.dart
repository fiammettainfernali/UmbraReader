import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/opds_client.dart';
import '../services/settings_service.dart';
import 'settings_screen.dart';

/// The home screen — shows every series synced from the OPDS library.
///
/// Phase 3 milestone: connect to the server and list the library. Downloading
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
      appBar: AppBar(
        title: Text(count == null ? 'Library' : 'Library ($count)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Server settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_settings!.isConfigured) {
      return _MessageView(
        icon: Icons.cloud_off_outlined,
        title: 'Not connected',
        message:
            'Connect Umbra Reader to your Novel Grabber library to see your '
            'books here.',
        actionLabel: 'Connect',
        onAction: _openSettings,
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageView(
        icon: Icons.error_outline,
        title: 'Sync failed',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _sync,
      );
    }
    final library = _library ?? const <Series>[];
    if (library.isEmpty) {
      return _MessageView(
        icon: Icons.library_books_outlined,
        title: 'No books found',
        message: 'The library is empty, or no series have a compiled EPUB yet.',
        actionLabel: 'Refresh',
        onAction: _sync,
      );
    }
    return RefreshIndicator(
      onRefresh: _sync,
      child: ListView.builder(
        itemCount: library.length,
        itemBuilder: (context, index) => _SeriesTile(
          series: library[index],
          imageHeaders: OpdsClient(_settings!).authHeaders,
        ),
      ),
    );
  }
}

/// A single row in the library list: cover, title, author, progress.
class _SeriesTile extends StatelessWidget {
  const _SeriesTile({required this.series, required this.imageHeaders});

  final Series series;
  final Map<String, String> imageHeaders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: SizedBox(
        width: 48,
        height: 64,
        child: _Cover(url: series.coverUrl, headers: imageHeaders),
      ),
      title: Text(
        series.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            series.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            '${series.downloadedChapters} / ${series.totalChapters} chapters'
            '  ·  ${series.readingStatus}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      trailing: series.hasMultipleVolumes
          ? Tooltip(
              message: 'Multiple volumes',
              child: Icon(
                Icons.collections_bookmark_outlined,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            )
          : null,
    );
  }
}

/// Cover thumbnail with graceful fallbacks for missing / failed images.
class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.headers});

  final String? url;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.menu_book_outlined,
        size: 22,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
    final coverUrl = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: coverUrl == null
          ? placeholder
          : Image.network(
              coverUrl,
              headers: headers,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return placeholder;
              },
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
