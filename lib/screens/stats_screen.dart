import 'package:flutter/material.dart';

import '../services/reading_progress_store.dart';

/// Shows reading statistics derived from saved reading positions: how many
/// books have been started, are in progress or finished, total chapters
/// reached, and a per-book breakdown.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  /// Null while loading.
  List<ReadingEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ReadingProgressStore().allEntries();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Reading stats')),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
          ? _buildEmpty(context)
          : _buildContent(context, entries),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No reading yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Open a book and your reading stats will start to appear here.',
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

  Widget _buildContent(BuildContext context, List<ReadingEntry> entries) {
    final theme = Theme.of(context);
    final inProgress = entries
        .where((e) => e.progress.isStarted && !e.progress.isFinished)
        .length;
    final finished = entries.where((e) => e.progress.isFinished).length;
    var chaptersRead = 0;
    for (final entry in entries) {
      chaptersRead += entry.progress.chapterIndex + 1;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.menu_book_outlined,
                value: '${entries.length}',
                label: 'Books started',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.auto_stories_outlined,
                value: '$inProgress',
                label: 'In progress',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.task_alt,
                value: '$finished',
                label: 'Finished',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.list_alt_outlined,
                value: '$chaptersRead',
                label: 'Chapters read',
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'By book',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        for (final entry in entries) _BookRow(entry: entry),
      ],
    );
  }
}

/// One headline statistic in a rounded panel.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A per-book row: progress ring, title, chapter position and last-read date.
class _BookRow extends StatelessWidget {
  const _BookRow({required this.entry});

  final ReadingEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = entry.progress;
    final finished = progress.isFinished;
    final chapterLabel = progress.chapterCount > 0
        ? 'Chapter ${progress.chapterIndex + 1} of ${progress.chapterCount}'
        : 'Chapter ${progress.chapterIndex + 1}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: finished ? 1.0 : progress.fraction,
              strokeWidth: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            if (finished)
              Icon(Icons.check, size: 18, color: theme.colorScheme.primary)
            else
              Text(
                '${(progress.fraction * 100).round()}%',
                style: theme.textTheme.labelSmall,
              ),
          ],
        ),
      ),
      title: Text(
        entry.volume.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$chapterLabel  ·  ${finished ? 'Finished' : 'Last read'} '
        '${_formatDate(progress.updatedAt)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

/// Formats a date relative to today, falling back to `Mon D`.
String _formatDate(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final days = today.difference(that).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}';
}
