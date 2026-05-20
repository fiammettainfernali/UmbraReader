import 'package:flutter/material.dart';

import '../models/series.dart';
import '../models/volume.dart';
import '../services/opds_client.dart';
import '../services/settings_service.dart';

/// Detail view for one series: cover, metadata, description, and its volumes.
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

  @override
  void initState() {
    super.initState();
    _loadVolumes();
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
          _VolumesSection(
            loading: _loadingVolumes,
            error: _volumesError,
            volumes: _volumes,
            onRetry: _loadVolumes,
          ),
        ],
      ),
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
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
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

/// The "Volumes" section: loading, error, or the list of volumes.
class _VolumesSection extends StatelessWidget {
  const _VolumesSection({
    required this.loading,
    required this.error,
    required this.volumes,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final List<Volume>? volumes;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = volumes?.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count == null ? 'Volumes' : 'Volumes ($count)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          )
        else if (volumes != null && volumes!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No volumes have been compiled for this series yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final volume in volumes ?? const <Volume>[])
            _VolumeTile(volume: volume),
      ],
    );
  }
}

/// One row in the volume list — display-only for now; a download action is
/// added in the next step.
class _VolumeTile extends StatelessWidget {
  const _VolumeTile({required this.volume});

  final Volume volume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = _formatBytes(volume.fileSizeBytes);
    final date = _formatDate(volume.updatedAt);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(volume.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$size  ·  updated $date',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
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
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
