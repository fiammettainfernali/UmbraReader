import 'package:flutter/material.dart';

import '../models/download_record.dart';
import '../models/series.dart';
import '../models/volume.dart';
import '../services/download_service.dart';
import '../services/library_storage.dart';
import '../services/opds_client.dart';
import '../services/settings_service.dart';
import 'reader_screen.dart';

/// Download state of a single volume, derived per build.
enum _VolumeStatus { notDownloaded, downloading, downloaded, updateAvailable }

/// Detail view for one series: cover, metadata, description, and downloadable
/// volumes.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    super.key,
    required this.series,
    required this.settings,
  });

  final Series series;
  final OpdsSettings settings;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  List<Volume>? _volumes;
  bool _loadingVolumes = true;
  String? _volumesError;
  bool _descriptionExpanded = false;

  late final DownloadStore _store;
  late final DownloadService _downloadService;
  bool _ready = false;

  /// Fractional progress (0..1) of in-flight downloads, keyed by file name.
  final Map<String, double> _progress = {};
  bool _downloadingAll = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final storage = LibraryStorage();
    final store = DownloadStore(storage);
    await store.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _downloadService = DownloadService(
        settings: widget.settings,
        storage: storage,
        store: store,
      );
      _ready = true;
    });
    await _loadVolumes();
  }

  Future<void> _loadVolumes() async {
    setState(() {
      _loadingVolumes = true;
      _volumesError = null;
    });
    try {
      final volumes = await OpdsClient(
        widget.settings,
      ).fetchVolumes(widget.series.opdsId);
      if (!mounted) return;
      setState(() {
        _volumes = volumes;
        _loadingVolumes = false;
      });
    } on OpdsException catch (e) {
      if (!mounted) return;
      setState(() {
        _volumesError = e.message;
        _loadingVolumes = false;
      });
    }
  }

  _VolumeStatus _statusOf(Volume volume) {
    if (_progress.containsKey(volume.fileName)) {
      return _VolumeStatus.downloading;
    }
    final record = _store.recordFor(volume);
    if (record == null) return _VolumeStatus.notDownloaded;
    return _isStale(volume, record)
        ? _VolumeStatus.updateAvailable
        : _VolumeStatus.downloaded;
  }

  /// True when the server's copy of [volume] differs from what was downloaded
  /// — i.e. Novel Grabber re-compiled it with new chapters.
  bool _isStale(Volume volume, DownloadRecord record) {
    final serverTime = volume.updatedAt;
    final recordTime = record.volumeUpdatedAt;
    final timeChanged =
        serverTime != null &&
        recordTime != null &&
        serverTime.isAfter(recordTime);
    final sizeChanged =
        volume.fileSizeBytes > 0 &&
        record.sizeBytes > 0 &&
        volume.fileSizeBytes != record.sizeBytes;
    return timeChanged || sizeChanged;
  }

  Future<void> _download(Volume volume) async {
    setState(() => _progress[volume.fileName] = 0);
    try {
      await _downloadService.download(
        volume,
        onProgress: (p) {
          if (mounted) setState(() => _progress[volume.fileName] = p);
        },
      );
    } on DownloadException catch (e) {
      _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _progress.remove(volume.fileName));
    }
  }

  Future<void> _downloadAll() async {
    final volumes = _volumes ?? const <Volume>[];
    setState(() => _downloadingAll = true);
    for (final volume in volumes) {
      if (!mounted) break;
      final status = _statusOf(volume);
      if (status == _VolumeStatus.downloaded ||
          status == _VolumeStatus.downloading) {
        continue;
      }
      await _download(volume);
    }
    if (mounted) setState(() => _downloadingAll = false);
  }

  Future<void> _delete(Volume volume) async {
    await _downloadService.delete(volume);
    if (!mounted) return;
    setState(() {});
    _snack('Removed “${volume.title}”.');
  }

  void _openReader(Volume volume) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(volume: volume)),
    );
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: isError ? 6 : 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    return Scaffold(
      appBar: AppBar(title: Text(series.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(
            series: series,
            imageHeaders: OpdsClient(widget.settings).authHeaders,
          ),
          if (series.genres.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in series.genres) Chip(label: Text(genre)),
              ],
            ),
          ],
          if (series.description.isNotEmpty) ...[
            const SizedBox(height: 20),
            _Description(
              text: series.description,
              expanded: _descriptionExpanded,
              onToggle: () =>
                  setState(() => _descriptionExpanded = !_descriptionExpanded),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          _buildVolumesSection(),
        ],
      ),
    );
  }

  Widget _buildVolumesSection() {
    final theme = Theme.of(context);
    final volumes = _volumes;
    final count = volumes?.length;

    final Widget content;
    if (!_ready || _loadingVolumes) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_volumesError != null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _volumesError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _loadVolumes,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (volumes == null || volumes.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No volumes have been compiled for this series yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      content = Column(
        children: [
          for (final volume in volumes)
            _VolumeTile(
              volume: volume,
              status: _statusOf(volume),
              progress: _progress[volume.fileName] ?? 0,
              onDownload: () => _download(volume),
              onDelete: () => _delete(volume),
              onOpen:
                  (_statusOf(volume) == _VolumeStatus.downloaded ||
                      _statusOf(volume) == _VolumeStatus.updateAvailable)
                  ? () => _openReader(volume)
                  : null,
            ),
        ],
      );
    }

    final pending =
        volumes
            ?.where(
              (v) =>
                  _statusOf(v) == _VolumeStatus.notDownloaded ||
                  _statusOf(v) == _VolumeStatus.updateAvailable,
            )
            .length ??
        0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                count == null ? 'Volumes' : 'Volumes ($count)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_downloadingAll)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Downloading…', style: theme.textTheme.labelMedium),
                ],
              )
            else if (pending > 0)
              TextButton.icon(
                onPressed: _downloadAll,
                icon: const Icon(Icons.download, size: 18),
                label: Text('Download all ($pending)'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        content,
      ],
    );
  }
}

/// Cover + title + author + status + chapter progress.
class _Header extends StatelessWidget {
  const _Header({required this.series, required this.imageHeaders});

  final Series series;
  final Map<String, String> imageHeaders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          height: 174,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _Cover(series: series, headers: imageHeaders),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                series.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                series.author,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _StatusPill(status: series.readingStatus),
              const SizedBox(height: 10),
              Text(
                '${series.downloadedChapters} / ${series.totalChapters} '
                'chapters',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cover art — network image with a titled gradient fallback.
class _Cover extends StatelessWidget {
  const _Cover({required this.series, required this.headers});

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
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small coloured pill showing the reading status.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status.toLowerCase()) {
      'ongoing' => Colors.green,
      'completed' => Colors.blue,
      'hiatus' => Colors.orange,
      'dropped' => Colors.redAccent,
      _ => Colors.grey,
    };
    final label = status.isEmpty
        ? 'Unknown'
        : '${status[0].toUpperCase()}${status.substring(1)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Description text, collapsible when long.
class _Description extends StatelessWidget {
  const _Description({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLong = text.length > 280;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          maxLines: (isLong && !expanded) ? 6 : null,
          overflow: (isLong && !expanded)
              ? TextOverflow.ellipsis
              : TextOverflow.clip,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        if (isLong)
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
  }
}

/// Menu actions on a downloaded volume.
enum _VolumeAction { download, delete }

/// One row in the volume list, with a download / progress / downloaded control.
class _VolumeTile extends StatelessWidget {
  const _VolumeTile({
    required this.volume,
    required this.status,
    required this.progress,
    required this.onDownload,
    required this.onDelete,
    required this.onOpen,
  });

  final Volume volume;
  final _VolumeStatus status;
  final double progress;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  /// Opens the reader; null when the volume isn't downloaded yet.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(
        volume.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _subtitle(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      trailing: _trailing(context),
      onTap: onOpen,
    );
  }

  String _subtitle() {
    final size = _formatBytes(volume.fileSizeBytes);
    return switch (status) {
      _VolumeStatus.downloaded => '$size  ·  Tap to read',
      _VolumeStatus.updateAvailable => '$size  ·  Update available · tap to read',
      _ => '$size  ·  updated ${_formatDate(volume.updatedAt)}',
    };
  }

  Widget _trailing(BuildContext context) {
    switch (status) {
      case _VolumeStatus.notDownloaded:
        return IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Download',
          onPressed: onDownload,
        );
      case _VolumeStatus.downloading:
        return SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: progress > 0 ? progress : null,
                strokeWidth: 3,
              ),
            ),
          ),
        );
      case _VolumeStatus.downloaded:
        return PopupMenuButton<_VolumeAction>(
          icon: const Icon(Icons.download_done, color: Colors.green),
          tooltip: 'Downloaded',
          onSelected: (action) {
            if (action == _VolumeAction.delete) onDelete();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _VolumeAction.delete,
              child: Text('Delete download'),
            ),
          ],
        );
      case _VolumeStatus.updateAvailable:
        return PopupMenuButton<_VolumeAction>(
          icon: const Icon(Icons.update, color: Colors.orange),
          tooltip: 'Update available',
          onSelected: (action) {
            if (action == _VolumeAction.download) onDownload();
            if (action == _VolumeAction.delete) onDelete();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _VolumeAction.download,
              child: Text('Re-download (update)'),
            ),
            PopupMenuItem(
              value: _VolumeAction.delete,
              child: Text('Delete download'),
            ),
          ],
        );
    }
  }
}

/// Formats a byte count as a short human-readable size.
String _formatBytes(int bytes) {
  if (bytes <= 0) return 'Unknown size';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final decimals = (unit == 0 || size >= 100) ? 0 : 1;
  return '${size.toStringAsFixed(decimals)} ${units[unit]}';
}

/// Formats a date as e.g. `May 5, 2026`.
String _formatDate(DateTime? date) {
  if (date == null) return 'unknown date';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
