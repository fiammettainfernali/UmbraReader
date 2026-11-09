// The earned half of the "You" screen: a level, the ladders, the things
// found along the way, and what the ledger has noticed lately.
//
// Deliberately a separate view behind a toggle rather than more rows under
// the existing figures. The stats page is already dense, and a reader who
// finds the app heavy going should be able to look at their reading
// WITHOUT being shown a wall of progress bars — and, on the days they want
// the progress bars, should get them without scrolling past everything else
// to reach them.

import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/award_store.dart';
import '../services/awards.dart';
import '../services/bookmark_store.dart';
import '../services/reading_activity_store.dart';
import '../services/reading_insights.dart';
import '../services/reading_progress_store.dart';
import '../widgets/hawthorne_parts.dart';

class AwardsView extends StatefulWidget {
  const AwardsView({
    super.key,
    required this.activity,
    required this.entries,
    required this.library,
  });

  final ReadingActivity activity;
  final List<ReadingEntry> entries;
  final List<Series> library;

  @override
  State<AwardsView> createState() => _AwardsViewState();
}

class _AwardsViewState extends State<AwardsView> {
  AwardSnapshot? _snapshot;
  List<ReadingInsight> _insights = const [];
  List<int> _years = const [];

  /// Badges earned since the reader last looked. Shown once, at the top,
  /// then marked seen — a badge that keeps announcing itself stops being
  /// news and starts being nagging.
  Set<String> _new = const {};

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  @override
  void didUpdateWidget(AwardsView old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity || old.entries != widget.entries) {
      _evaluate();
    }
  }

  Future<void> _evaluate() async {
    final highlights = await BookmarkStore().countBySeries();
    final ctx = AwardContext(
      activity: widget.activity,
      entries: widget.entries,
      library: widget.library,
      highlightsPerSeries: highlights,
    );
    final snapshot = evaluateAwards(ctx);

    final store = AwardStore();
    await store.record(snapshot);
    final unseen = (await store.unseen()).toSet();
    await store.markSeen(unseen);

    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _insights = rotatingInsights(ctx);
      _years = yearsWithReading(ctx);
      _new = unseen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        _LevelCard(level: snapshot.level),
        if (_new.isNotEmpty) ...[
          const SizedBox(height: 20),
          _NewlyEarned(ids: _new, snapshot: snapshot),
        ],

        const SizedBox(height: 24),
        _Heading('Progress', theme: theme),
        const SizedBox(height: 4),
        for (final ladder in snapshot.ladders) _LadderRow(progress: ladder),

        if (_insights.isNotEmpty) ...[
          const SizedBox(height: 24),
          _Heading('Noticed', theme: theme),
          const SizedBox(height: 4),
          for (final insight in _insights) _InsightCard(insight: insight),
        ],

        const SizedBox(height: 24),
        _Heading('Found along the way', theme: theme),
        const SizedBox(height: 4),
        if (snapshot.rareFinds.isEmpty)
          Text(
            'Nothing yet. These are not a checklist — they happen while you '
            'read, and you find out afterwards.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          for (final found in snapshot.rareFinds)
            _FindCard(name: found.find.name, description: found.description),
          const SizedBox(height: 4),
          Text(
            'There are others, and they are not listed anywhere.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],

        if (_years.isNotEmpty) ...[
          const SizedBox(height: 24),
          _Heading('Year by year', theme: theme),
          const SizedBox(height: 4),
          for (final year in _years)
            _YearTile(
              review: yearInReview(
                AwardContext(
                  activity: widget.activity,
                  entries: widget.entries,
                  library: widget.library,
                ),
                year,
              ),
            ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: theme.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
  );
}

/// The headline: what all the reading adds up to.
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level});

  final LevelProgress level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Level ${level.level}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  shadows: const [
                    Shadow(color: Color(0x8CE5121F), blurRadius: 20),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${_count(level.xp)} XP',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GrowingBar(fraction: level.fraction, height: 10),
          const SizedBox(height: 8),
          Text(
            '${_count(level.remaining)} XP to level ${level.level + 1}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'A minute read is a point, and finishing a book is a hundred.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// What has been earned since the last look.
class _NewlyEarned extends StatelessWidget {
  const _NewlyEarned({required this.ids, required this.snapshot});

  final Set<String> ids;
  final AwardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = <String>[
      for (final ladder in snapshot.ladders)
        if (ids.contains(ladder.badgeId))
          '${ladder.previousRung} ${ladder.ladder.unit}',
      for (final found in snapshot.rareFinds)
        if (ids.contains('find.${found.find.id}')) found.find.name,
    ];
    if (names.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x29F09628),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x6BF09628)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            names.length == 1 ? 'New since last time' : 'New since last time',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(names.join(' · '), style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// One ladder: where it stands and what the next rung costs.
class _LadderRow extends StatelessWidget {
  const _LadderRow({required this.progress});

  final LadderProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reached = progress.rungsReached;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.ladder.name,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (reached > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x29F09628),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0x6BF09628)),
                  ),
                  child: Text(
                    'Tier $reached',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFFFD9B0),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GrowingBar(fraction: progress.fraction, warm: true, height: 7),
          const SizedBox(height: 5),
          Text(
            '${_count(progress.value)} of ${_count(progress.nextRung)} '
            '${progress.ladder.unit}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final ReadingInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            insight.headline,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            insight.detail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FindCard extends StatelessWidget {
  const _FindCard({required this.name, required this.description});

  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _YearTile extends StatelessWidget {
  const _YearTile({required this.review});

  final YearInReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (review.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text('${review.year}', style: theme.textTheme.bodyLarge),
      subtitle: Text(
        '${review.hours} hours · ${review.booksFinished} finished',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        _YearLine('Days read', '${review.daysRead}'),
        if (review.busiestMonth > 0)
          _YearLine(
            'Busiest month',
            '${monthName(review.busiestMonth)} '
                '(${review.busiestMonthHours} hours)',
          ),
        if (review.topSeries != null)
          _YearLine('Most time in', review.topSeries!),
        if (review.genres > 0) _YearLine('Genres finished', '${review.genres}'),
      ],
    );
  }
}

class _YearLine extends StatelessWidget {
  const _YearLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Thousands separators, because six-figure word counts are the norm here
/// and "12345678" is not a number anyone reads.
String _count(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
