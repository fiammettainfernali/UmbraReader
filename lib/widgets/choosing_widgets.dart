import 'package:flutter/material.dart';

import '../models/series.dart';
import '../screens/library_cards.dart';
import '../screens/library_home.dart';
import '../services/choosing.dart';
import '../services/reading_progress_store.dart';
import 'living_surfaces.dart';

/// Tonight's three, at the top of the library: three covers, each with why
/// it's here, Not now under each, and Decide for me.
class TonightsThree extends StatelessWidget {
  const TonightsThree({
    super.key,
    required this.picks,
    required this.headers,
    required this.onOpen,
    required this.onNotNow,
    required this.onDecide,
  });

  final List<TonightPick> picks;
  final Map<String, String> headers;
  final void Function(TonightPick pick) onOpen;
  final void Function(TonightPick pick) onNotNow;
  final VoidCallback onDecide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RowHeading(title: "Tonight's three", tag: 'Pick one'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // As tall as the tallest card, so the Not now buttons line up.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: i < picks.length
                        ? _PickCard(
                            pick: picks[i],
                            headers: headers,
                            onOpen: () => onOpen(picks[i]),
                            onNotNow: () => onNotNow(picks[i]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Under the cards, not beside the heading: on the Fold's outer
        // screen there is no room beside it.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: picks.any((p) => p.kind != TonightKind.carryOn)
                  ? onDecide
                  : null,
              icon: const Icon(Icons.casino_outlined, size: 18),
              label: const Text('Decide for me'),
            ),
          ),
        ),
      ],
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.pick,
    required this.headers,
    required this.onOpen,
    required this.onNotNow,
  });

  final TonightPick pick;
  final Map<String, String> headers;
  final VoidCallback onOpen;
  final VoidCallback onNotNow;

  static String _label(TonightKind kind) => switch (kind) {
    TonightKind.carryOn => 'Carry on',
    TonightKind.likeLast => 'Like your last',
    TonightKind.wildcard => 'Wildcard',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '${_label(pick.kind)}: ${pick.series.title}. ${pick.reason}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _label(pick.kind).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: PressScale(
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CoverImage(
                    series: pick.series,
                    headers: headers,
                    decodeWidth: 300,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            pick.series.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            pick.reason,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onNotNow,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 36),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

/// What to do with a book being tried, three chapters in.
enum TryItAnswer { keep, notForMe, later }

Future<TryItAnswer?> showTryItPrompt(BuildContext context, String title) {
  return showModalBottomSheet<TryItAnswer>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keep reading $title?',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              "Three chapters in. Keep it and it joins Continue reading. "
              "If it isn't for you, it goes quietly and stops being suggested.",
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, TryItAnswer.keep),
              child: const Text('Keep it'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, TryItAnswer.notForMe),
              child: const Text('Not for me'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, TryItAnswer.later),
              child: const Text('Ask me in a few chapters'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Over the limit of books at once: which to pause. Returns the series to
/// pause, or null to keep them all going.
Future<Set<int>?> showPauseSheet(
  BuildContext context, {
  required List<({Series? series, ReadingEntry entry})> books,
  required int limit,
  required int justStarted,
}) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final chosen = <int>{};
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final over = books.length - limit;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "That's ${books.length} books at once",
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your limit is $limit. Pause ${over == 1 ? 'one' : '$over'} '
                    "to keep Continue reading short. Paused books wait under "
                    'Paused in the library, where you left them.',
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final b in books)
                          if (b.entry.volume.seriesOpdsId != justStarted)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: chosen.contains(
                                b.entry.volume.seriesOpdsId,
                              ),
                              title: Text(
                                b.series?.title ?? b.entry.volume.title,
                              ),
                              subtitle: Text(_lastRead(b.entry)),
                              onChanged: (on) => setSheet(() {
                                final id = b.entry.volume.seriesOpdsId;
                                on == true ? chosen.add(id) : chosen.remove(id);
                              }),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: chosen.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, Set<int>.of(chosen)),
                    child: Text(
                      chosen.isEmpty
                          ? 'Pick books to pause'
                          : 'Pause ${chosen.length}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Keep them all going'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String _lastRead(ReadingEntry entry) {
  final at = entry.progress.updatedAt;
  final p = entry.progress;
  final where = p.chapterCount > 0
      ? 'Chapter ${p.chapterIndex + 1} of ${p.chapterCount}'
      : 'Chapter ${p.chapterIndex + 1}';
  if (at == null) return where;
  final days = DateTime.now().difference(at).inDays;
  final when = days <= 0
      ? 'today'
      : days == 1
      ? 'yesterday'
      : '$days days ago';
  return '$where · read $when';
}

/// A stalled book's fate at the check-in.
enum StalledAnswer { keepGoing, pause, drop }

/// The week's check-in, as a card above the rows.
class StalledCheckInCard extends StatelessWidget {
  const StalledCheckInCard({
    super.key,
    required this.count,
    required this.onStart,
    required this.onDismiss,
  });

  final int count;
  final VoidCallback onStart;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count == 1
                    ? "1 book you haven't opened in a month"
                    : "$count books you haven't opened in a month",
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Keep going, pause or drop each one, so the books on the go '
                'are the ones you mean to read.',
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text('Not this week'),
                  ),
                  FilledButton(
                    onPressed: onStart,
                    child: const Text('Sort them out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One stalled book at a time. Returns what was decided for each; books
/// left when the sheet is closed are simply not decided.
Future<Map<int, StalledAnswer>> showStalledCheckIn(
  BuildContext context, {
  required List<({Series? series, ReadingEntry entry})> books,
  required Map<String, String> headers,
}) async {
  final answers = <int, StalledAnswer>{};
  for (final book in books) {
    if (!context.mounted) break;
    final answer = await showModalBottomSheet<StalledAnswer>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final series = book.series;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (series != null)
                      SizedBox(
                        width: 72,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CoverImage(
                              series: series,
                              headers: headers,
                              decodeWidth: 200,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            series?.title ?? book.entry.volume.title,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(_lastRead(book.entry)),
                          const SizedBox(height: 4),
                          Text(
                            '${books.indexOf(book) + 1} of ${books.length}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, StalledAnswer.drop),
                        child: const Text('Drop'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(ctx, StalledAnswer.pause),
                        child: const Text('Pause'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(ctx, StalledAnswer.keepGoing),
                        child: const Text('Keep going'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (answer == null) break;
    answers[book.entry.volume.seriesOpdsId] = answer;
  }
  return answers;
}
