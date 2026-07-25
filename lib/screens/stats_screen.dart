import 'package:flutter/material.dart';

import '../services/reading_activity_store.dart';
import '../services/reading_progress_store.dart';
import '../services/settings_service.dart';
import '../widgets/section_header.dart';

/// Shows reading statistics derived from saved reading positions and
/// reading-time activity.
///
/// Reports on a chosen window (week / month / year / all) rather than only
/// lifetime totals: an all-time figure only ever grows, so it can't say
/// whether *this* week went well. The period's reading time leads, with the
/// change against the previous equivalent window beneath it; lifetime totals
/// are kept but demoted to a strip at the bottom.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _settingsService = SettingsService();

  /// Null while loading.
  List<ReadingEntry>? _entries;
  ReadingActivity _activity = ReadingActivity.empty;
  int _dailyGoalMinutes = 0;

  /// The window every headline figure reports on. Defaults to a week — the
  /// question the screen should answer on open is "how am I doing lately",
  /// not "what have I ever done".
  StatsPeriod _period = StatsPeriod.week;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ReadingProgressStore().allEntries();
    final activity = await ReadingActivityStore().load();
    final goal = await _settingsService.readDailyMinuteGoal();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _activity = activity;
      _dailyGoalMinutes = goal;
    });
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(
      text: _dailyGoalMinutes > 0 ? '$_dailyGoalMinutes' : '',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Daily reading goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes per day',
            hintText: 'e.g. 20',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) =>
              Navigator.of(dialogCtx).pop(int.tryParse(value) ?? 0),
        ),
        actions: [
          if (_dailyGoalMinutes > 0)
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(0),
              child: const Text('Clear goal'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx)
                .pop(int.tryParse(controller.text) ?? 0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    await _settingsService.saveDailyMinuteGoal(result);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Reading stats')),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty && _activity.totalSeconds == 0
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

  /// "this week" / "this month" / "this year" — the window in words.
  String _periodPhrase(StatsPeriod period) => switch (period) {
    StatsPeriod.week => 'this week',
    StatsPeriod.month => 'in the last 30 days',
    StatsPeriod.year => 'in the last year',
    StatsPeriod.all => 'all time',
  };

  /// The period-on-period change, phrased neutrally. A quiet week is
  /// information, not a failure — same rule as streak grace and the reminder
  /// copy, so there is no red, no warning icon and no "only".
  String _trendPhrase(double trend, StatsPeriod period) {
    final pct = (trend.abs() * 100).round();
    final against = switch (period) {
      StatsPeriod.week => 'the week before',
      StatsPeriod.month => 'the 30 days before',
      StatsPeriod.year => 'the year before',
      StatsPeriod.all => 'before',
    };
    if (pct == 0) return 'About the same as $against';
    return trend > 0 ? 'Up $pct% on $against' : 'Down $pct% on $against';
  }

  Widget _buildContent(BuildContext context, List<ReadingEntry> entries) {
    final theme = Theme.of(context);
    final period = _period;

    // Period figures — what the screen is actually reporting on.
    final seconds = _activity.secondsIn(period);
    final words = _activity.wordsIn(period);
    final daysRead = _activity.daysReadIn(period);
    final trend = _activity.trendAgainstPrevious(period);
    final perDay = daysRead > 0 ? seconds ~/ daysRead : 0;

    // Lifetime figures — kept, but demoted to the strip at the bottom.
    final inProgress = entries
        .where((e) => e.progress.isStarted && !e.progress.isFinished)
        .length;
    final finished = entries.where((e) => e.progress.isFinished).length;
    final streak = _activity.currentStreak();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<StatsPeriod>(
          segments: [
            for (final p in StatsPeriod.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {period},
          showSelectedIcon: false,
          onSelectionChanged: (sel) => setState(() => _period = sel.first),
        ),
        const SizedBox(height: 20),

        // ── the headline: time read in this window, and which way it is going
        Text(
          _formatDuration(seconds),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          period.isAllTime ? 'read all time' : 'read ${_periodPhrase(period)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (trend != null) ...[
          const SizedBox(height: 6),
          Text(
            _trendPhrase(trend, period),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 18),

        // Today against the goal — the most actionable line, so it sits high.
        _GoalRow(
          dailyGoalMinutes: _dailyGoalMinutes,
          todaySeconds: _activity.dailySeconds[_todayKey()] ?? 0,
          onEdit: _editGoal,
        ),
        const SizedBox(height: 18),

        // Supporting figures for the same window.
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.event_available_outlined,
                value: '$daysRead',
                label: daysRead == 1 ? 'day read' : 'days read',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.schedule,
                value: perDay == 0 ? '—' : _formatDuration(perDay),
                label: 'per reading day',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.text_fields,
                value: words == 0 ? '—' : _formatCount(words),
                label: 'words read',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.local_fire_department_outlined,
                value: streak == 0 ? '—' : '$streak',
                label: streak == 1 ? 'day streak' : 'days streak',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionHeader(
          'Reading activity',
          padding: EdgeInsets.only(bottom: 8),
        ),
        _CalendarHeatmap(dailySeconds: _activity.dailySeconds),
        const SizedBox(height: 20),

        // ── lifetime totals, deliberately quiet
        const SectionHeader('All time', padding: EdgeInsets.only(bottom: 8)),
        _AllTimeStrip(
          entries: entries.length,
          inProgress: inProgress,
          finished: finished,
          time: _formatDuration(_activity.totalSeconds),
          words: _activity.totalWords == 0
              ? '—'
              : _formatCount(_activity.totalWords),
          wpm: _activity.wordsPerMinute,
          longestStreak: _activity.longestStreak(),
        ),
        const SizedBox(height: 20),
        const SectionHeader('By book', padding: EdgeInsets.only(bottom: 8)),
        const SizedBox(height: 4),
        for (final entry in entries)
          _BookRow(
            entry: entry,
            seconds: _activity.perVolumeSeconds[
                '${entry.volume.seriesOpdsId}/${entry.volume.fileName}'] ?? 0,
          ),
      ],
    );
  }
}

/// One headline statistic in a rounded panel.
/// Lifetime totals, rendered as a quiet list rather than cards.
///
/// These are the figures that only ever grow — a trophy case. They are worth
/// keeping, but they answer "what have I ever done", not "how am I doing", so
/// they get the least visual weight on the screen rather than the most.
class _AllTimeStrip extends StatelessWidget {
  const _AllTimeStrip({
    required this.entries,
    required this.inProgress,
    required this.finished,
    required this.time,
    required this.words,
    required this.wpm,
    required this.longestStreak,
  });

  final int entries;
  final int inProgress;
  final int finished;
  final String time;
  final String words;
  final int wpm;
  final int longestStreak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      ('Time read', time),
      ('Words read', words),
      if (wpm > 0) ('Reading pace', '$wpm words / min'),
      ('Books started', '$entries'),
      ('In progress', '$inProgress'),
      ('Finished', '$finished'),
      if (longestStreak > 0)
        ('Longest streak', '$longestStreak ${longestStreak == 1 ? "day" : "days"}'),
    ];
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

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

/// Today's progress against the user's daily reading goal — a thin progress
/// bar plus the minute count and an "Edit" / "Set goal" action.
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.dailyGoalMinutes,
    required this.todaySeconds,
    required this.onEdit,
  });

  final int dailyGoalMinutes;
  final int todaySeconds;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayMinutes = todaySeconds ~/ 60;
    final hasGoal = dailyGoalMinutes > 0;
    final ratio = hasGoal
        ? (todayMinutes / dailyGoalMinutes).clamp(0.0, 1.0)
        : 0.0;
    final label = hasGoal
        ? '$todayMinutes / $dailyGoalMinutes min today'
        : '$todayMinutes min today  ·  no daily goal set';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onEdit,
              child: Text(hasGoal ? 'Edit goal' : 'Set goal'),
            ),
          ],
        ),
        if (hasGoal) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          if (ratio >= 1.0) ...[
            const SizedBox(height: 6),
            Text(
              'Goal hit for today — nice.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// A GitHub-style contribution calendar: one column per week, seven rows
/// (Mon–Sun), each cell shaded by how much was read that day. Shows the most
/// recent [_weeks] weeks, with today in the last column.
class _CalendarHeatmap extends StatelessWidget {
  const _CalendarHeatmap({required this.dailySeconds});

  final Map<String, int> dailySeconds;

  static const int _weeks = 13;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Start of the current week (Monday = weekday 1).
    final startOfThisWeek = today.subtract(Duration(days: today.weekday - 1));
    final firstColumn = startOfThisWeek.subtract(
      Duration(days: (_weeks - 1) * 7),
    );

    var maxSec = 0;
    for (final s in dailySeconds.values) {
      if (s > maxSec) maxSec = s;
    }
    final empty = theme.colorScheme.surfaceContainerHighest;
    final accent = theme.colorScheme.primary;

    Color cellColor(DateTime day) {
      if (day.isAfter(today)) return Colors.transparent;
      final seconds = dailySeconds[_dateKey(day)] ?? 0;
      if (seconds == 0) return empty;
      final intensity = maxSec == 0 ? 0.4 : (seconds / maxSec).clamp(0.25, 1.0);
      return accent.withValues(alpha: intensity);
    }

    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Weekday labels down the left.
        Column(
          children: [
            for (final l in labels)
              SizedBox(
                height: 18,
                child: Center(
                  child: Text(
                    l,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Row(
            children: [
              for (var w = 0; w < _weeks; w++)
                Expanded(
                  child: Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Padding(
                          padding: const EdgeInsets.all(1.5),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                color: cellColor(
                                  firstColumn.add(Duration(days: w * 7 + d)),
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A per-book row: progress ring, title, chapter position, time spent, and
/// last-read date.
class _BookRow extends StatelessWidget {
  const _BookRow({required this.entry, required this.seconds});

  final ReadingEntry entry;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = entry.progress;
    final finished = progress.isFinished;
    final chapterLabel = progress.chapterCount > 0
        ? 'Chapter ${progress.chapterIndex + 1} of ${progress.chapterCount}'
        : 'Chapter ${progress.chapterIndex + 1}';
    final timeText = seconds > 0 ? '  ·  ${_formatDuration(seconds)} read' : '';
    // Reading pace, only shown after at least 5 minutes — shorter sessions
    // skew the number wildly.
    final hours = seconds / 3600;
    final speedText = (seconds >= 300 && hours > 0)
        ? '  ·  ${((progress.chapterIndex + 1) / hours).toStringAsFixed(1)}'
              ' ch/hr'
        : '';
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
        '$chapterLabel$timeText$speedText  ·  '
        '${finished ? 'Finished' : 'Last read'} '
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

/// Formats a large count compactly: 1_240_000 → "1.2M", 34_500 → "34.5k".
String _formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    return k >= 100 ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
  }
  final m = n / 1000000;
  return '${m.toStringAsFixed(m >= 100 ? 0 : 1)}M';
}

/// Formats a duration in seconds as a short human string.
String _formatDuration(int seconds) {
  if (seconds <= 0) return '0m';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  if (hours < 24) return rem == 0 ? '${hours}h' : '${hours}h ${rem}m';
  final days = hours ~/ 24;
  final remH = hours % 24;
  return remH == 0 ? '${days}d' : '${days}d ${remH}h';
}

String _dateKey(DateTime date) {
  final local = date.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$d';
}

String _todayKey() => _dateKey(DateTime.now());
