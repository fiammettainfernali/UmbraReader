import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/reading_activity_store.dart';
import '../services/reading_progress_store.dart';
import '../services/settings_service.dart';
import '../widgets/section_header.dart';
import 'series_detail_screen.dart';

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

  /// Series by opdsId, so the by-series list can name a series properly and
  /// open it rather than being a dead end.
  Map<int, Series> _seriesById = const {};

  /// Needed to open a series; null until settings load.
  OpdsSettings? _opdsSettings;

  /// The window every headline figure reports on. Defaults to a week — the
  /// question the screen should answer on open is "how am I doing lately",
  /// not "what have I ever done".
  StatsPeriod _period = StatsPeriod.week;

  /// The by-book list is ranked, so a handful covers most reading; the
  /// rest are one tap away rather than an endless scroll.
  static const int _bookRowCap = 8;
  bool _showAllBooks = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ReadingProgressStore().allEntries();
    final activity = await ReadingActivityStore().load();
    final goal = await _settingsService.readDailyMinuteGoal();
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    final opds = await _settingsService.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _activity = activity;
      _dailyGoalMinutes = goal;
      _seriesById = {for (final s in cache.series) s.opdsId: s};
      _opdsSettings = opds;
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

  /// Books whose *last* reading position falls in the window and which were
  /// read to the end.
  ///
  /// Approximate by design: positions record when they were last saved, not
  /// when a book was finished, so re-opening a finished book to check
  /// something moves it back into the window. Tracking a real finish date
  /// would need a schema change for a number that is decoration.
  int _finishedIn(List<ReadingEntry> entries, StatsPeriod period) {
    final finished = entries.where((e) => e.progress.isFinished);
    if (period.isAllTime) return finished.length;
    final cutoff = DateTime.now().subtract(Duration(days: period.days));
    return finished
        .where((e) => e.progress.updatedAt?.isAfter(cutoff) ?? false)
        .length;
  }

  /// Opens a series from the breakdown. Null when the series is no longer in
  /// the library cache — the row still shows its time, it just has nowhere to
  /// go, so it is rendered as plain text rather than a tap that does nothing.
  Future<void> _openSeries(Series? series) async {
    final settings = _opdsSettings;
    if (series == null || settings == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeriesDetailScreen(series: series, settings: settings),
      ),
    );
    await _load();
  }

  int _secondsFor(ReadingEntry e) =>
      _activity.perVolumeSeconds[
          '${e.volume.seriesOpdsId}/${e.volume.fileName}'] ??
      0;

  /// Reading time grouped by series and ranked, most time first.
  ///
  /// Lifetime rather than per period: the per-volume ledger records totals,
  /// not dated entries, so windowing it would be a guess. Series titles come
  /// from the library cache; a series that isn't cached (deleted from the
  /// server, say) falls back to one of its volume titles so the row is still
  /// recognisable rather than blank.
  List<({String title, int seconds, int volumes, bool finished, Series? series})>
  _seriesByTime(
    List<ReadingEntry> entries,
  ) {
    final grouped = <int, List<ReadingEntry>>{};
    for (final e in entries) {
      grouped.putIfAbsent(e.volume.seriesOpdsId, () => []).add(e);
    }
    final out =
        <({String title, int seconds, int volumes, bool finished, Series? series})>[];
    grouped.forEach((id, group) {
      var seconds = 0;
      for (final e in group) {
        seconds += _secondsFor(e);
      }
      final series = _seriesById[id];
      out.add((
        title: series?.title ?? group.first.volume.title,
        seconds: seconds,
        volumes: group.length,
        finished: group.every((e) => e.progress.isFinished),
        series: series,
      ));
    });
    out.sort((a, b) => b.seconds.compareTo(a.seconds));
    return out;
  }

  /// "today" / "yesterday" / a short date — whichever reads most naturally.
  String _dayLabel(DateTime day) {
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    final diff = midnight.difference(DateTime(day.year, day.month, day.day)).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${day.day} ${months[day.month - 1]}';
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
    final pace = _activity.wordsPerMinuteIn(period);
    final finishedInPeriod = _finishedIn(entries, period);
    final bestDay = _activity.bestDayIn(period);
    final bestWeek = _activity.bestWeekIn(period);

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
                icon: Icons.speed,
                value: pace == 0 ? '—' : '$pace',
                label: 'words / min',
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
                value: '$finishedInPeriod',
                label: 'books finished',
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
        // Bars for a window (how much, and which way), the heatmap for
        // all-time (whether, across a long stretch) — each is the right tool
        // for its question.
        if (period.isAllTime)
          _CalendarHeatmap(dailySeconds: _activity.dailySeconds)
        else
          _TrendBars(buckets: _activity.trendBuckets(period)),
        if (bestDay != null) ...[
          const SizedBox(height: 10),
          Text(
            'Best day ${_dayLabel(bestDay.day)} · ${_formatDuration(bestDay.seconds)}'
            '${bestWeek > 0 ? '   ·   Best week ${_formatDuration(bestWeek)}' : ''}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
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
        const SectionHeader('By series', padding: EdgeInsets.only(bottom: 8)),
        const SizedBox(height: 4),
        // Grouped by series and ranked by time: a forty-volume webnovel is one
        // line about where the time went, not forty rows to scroll past.
        for (final row in _seriesByTime(entries).take(
          _showAllBooks ? 1 << 30 : _bookRowCap,
        ))
          _SeriesRow(row: row, onTap: () => _openSeries(row.series)),
        if (!_showAllBooks && _seriesByTime(entries).length > _bookRowCap)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAllBooks = true),
              child: Text(
                'Show all ${_seriesByTime(entries).length}',
              ),
            ),
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
/// A compact bar per bucket, scaled to the busiest one.
///
/// Deliberately not a charting dependency: this is a row of rounded boxes with
/// a fractional height, which is all the question "how much, and which way"
/// needs. Days with no reading keep a faint stub so the row still reads as a
/// timeline rather than a gap.
/// One series in the by-series list: title, how many volumes it covers, and
/// the reading time behind it.
class _SeriesRow extends StatelessWidget {
  const _SeriesRow({required this.row, required this.onTap});

  final ({
    String title,
    int seconds,
    int volumes,
    bool finished,
    Series? series,
  })
  row;

  /// Opens the series. Ignored when the series isn't in the library any more.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openable = row.series != null;
    final sub = [
      '${row.volumes} ${row.volumes == 1 ? "volume" : "volumes"}',
      if (row.finished) 'finished',
    ].join(' · ');
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            row.seconds == 0 ? '—' : _formatDuration(row.seconds),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (openable) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.outline,
            ),
          ],
        ],
      ),
    );
    if (!openable) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.buckets});

  final List<({String label, int seconds})> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (buckets.isEmpty) return const SizedBox.shrink();
    final peak = buckets.fold<int>(0, (m, b) => b.seconds > m ? b.seconds : m);
    final labelled = buckets.any((b) => b.label.isNotEmpty);
    return Semantics(
      label: 'Reading time per period, most recent last',
      child: SizedBox(
        height: labelled ? 92 : 76,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final b in buckets)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FractionallySizedBox(
                          alignment: Alignment.bottomCenter,
                          heightFactor: peak == 0
                              ? 0.02
                              : (b.seconds / peak).clamp(0.02, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: b.seconds == 0
                                  ? theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.4)
                                  : theme.colorScheme.primary
                                        .withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      if (labelled) ...[
                        const SizedBox(height: 6),
                        Text(
                          b.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
