import 'dart:math';

import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/recommendation_engine.dart';
import '../services/recommendation_feedback_store.dart';
import '../services/rec_outcome_store.dart';
import '../services/opds_client.dart';
import '../services/settings_service.dart';
import '../widgets/section_header.dart';
import 'library_cards.dart';

/// The "Recommended for you" shelf, extracted from the library screen: the
/// window of picks currently on show, the shuffle through the wider pool, the
/// like / snooze / dismiss feedback, and impression tracking.
///
/// Only the *shelf* lives here. Running the recommendation engine stays in the
/// screen's load path, where the signals it needs are already being gathered;
/// the result arrives through [setRecommendations]. That split is the point —
/// this owns what is on screen, not how it was chosen.
mixin LibraryRecommendations<T extends StatefulWidget> on State<T> {
  // ── what the library State must provide ─────────────────────────────────

  OpdsSettings? get opdsSettings;

  /// Re-reads the library and re-runs the ranking after feedback.
  ///
  /// Unconditional by contract. The host skips the refit when the library
  /// looks unchanged, and feedback never changes the library — so a dismiss,
  /// a like or a snooze left the shelf byte-identical, which read as the
  /// buttons doing nothing at all.
  Future<void> reloadRecommendations();

  /// True while the shelf is the tab being looked at.
  ///
  /// The shell keeps Discover alive inside an IndexedStack, so "built" and
  /// "on screen" are different questions — and an impression is only worth
  /// recording when the answer to the second one is yes.
  bool get shelfIsOnScreen;

  Future<void> openSeries(Series series);

  List<Recommendation> _recommendations = const [];

  /// Window offset into [_recommendations] for the displayed shelf.
  int _recommendOffset = 0;

  /// The current pool of picks; the shelf shows one window of it.
  List<Recommendation> get recommendations => _recommendations;

  /// Receives a fresh pool from the screen's load path and resets the
  /// window, so a reload always starts at the top of the new picks.
  void setRecommendations(List<Recommendation> next) {
    if (!mounted) return;
    setState(() {
      _recommendations = next;
      _recommendOffset = 0;
    });
    // Only if they are being looked at. Fresh picks arrive on launch, while
    // the app is sitting on Library with this tab alive but off screen.
    if (shelfIsOnScreen) recordShelfImpressions();
  }

  /// Number of recommendations on screen at one time.
  static const int _recommendWindow = 10;

  /// One card's horizontal footprint — [RecommendCard] is 124 wide and the
  /// shelf separates them by 14 (see library_cards.dart) — and the shelf's
  /// leading gutter. Used to work out how much of the window a given screen
  /// actually shows.
  static const double _cardStride = 124.0 + 14;
  static const double _shelfGutter = 16;

  /// What to assume when there is no size to measure (a shelf recorded from
  /// outside a laid-out frame). A folded Fold fits about this many.
  static const int _assumedOnScreenCards = 3;

  Future<void> _dismissRecommendation(Series series) async {
    await RecommendationFeedbackStore().recordDismiss(series.opdsId);
    await reloadRecommendations();
  }

  /// Records a 👍 "more like this" and refreshes so the shelf leans into it.
  Future<void> _likeRecommendation(Series series) async {
    final messenger = ScaffoldMessenger.of(context);
    await RecommendationFeedbackStore().recordLike(series.opdsId);
    // The old wording promised picks that were "coming up", and none ever
    // were: the reload was skipped, so the shelf stayed exactly as it was.
    // It refits now — and a liked series joins the engaged set, so the card
    // that was just praised is also the one that leaves. Say what happens.
    messenger.showSnackBar(
      SnackBar(content: Text('More like “${series.title}” — shelf updated.')),
    );
    await reloadRecommendations();
  }

  /// Records a "not now" (30-day snooze) and refreshes the shelf.
  Future<void> _snoozeRecommendation(Series series) async {
    final messenger = ScaffoldMessenger.of(context);
    await RecommendationFeedbackStore().recordSnooze(series.opdsId);
    messenger.showSnackBar(
      SnackBar(content: Text('“${series.title}” hidden for 30 days.')),
    );
    await reloadRecommendations();
  }

  /// Long-press options for a recommendation card: the full feedback set.
  Future<void> _showRecommendationOptions(Series series) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.thumb_up_outlined),
              title: const Text('More like this'),
              onTap: () => Navigator.of(sheetCtx).pop('like'),
            ),
            ListTile(
              leading: const Icon(Icons.snooze),
              title: const Text('Not now'),
              subtitle: const Text('Hide for 30 days'),
              onTap: () => Navigator.of(sheetCtx).pop('snooze'),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Not interested'),
              onTap: () => Navigator.of(sheetCtx).pop('dismiss'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'like':
        await _likeRecommendation(series);
      case 'snooze':
        await _snoozeRecommendation(series);
      case 'dismiss':
        await _dismissRecommendation(series);
    }
  }

  /// Everything the window rotates through: the wildcard is pinned rather
  /// than rotated, so it is not part of the pool being sliced.
  List<Recommendation> _rotatingPool() => [
    for (final r in _recommendations)
      if (!r.isWildcard) r,
  ];

  /// The recommendations currently visible in the shelf window. The
  /// exploration wildcard (if any) is pinned as the last visible card in
  /// every window so it always gets its one slot.
  List<Recommendation> _visibleRecommendations() {
    final wildcard = _recommendations.where((r) => r.isWildcard).toList();
    final pool = _rotatingPool();
    final List<Recommendation> window;
    if (pool.length <= _recommendWindow) {
      window = pool;
    } else {
      final start = _recommendOffset % pool.length;
      final take = pool.skip(start).take(_recommendWindow).toList();
      if (take.length < _recommendWindow) {
        take.addAll(pool.take(_recommendWindow - take.length));
      }
      window = take;
    }
    return [...window, ...wildcard];
  }

  /// How many cards of the window this screen actually puts in front of the
  /// reader. The shelf holds ten; a folded Fold shows about three of them,
  /// and the rest are off the right edge until someone scrolls.
  int _onScreenCardCount() {
    final width = MediaQuery.maybeOf(context)?.size.width ?? 0;
    if (width <= 0) return _assumedOnScreenCards;
    // Ceil, not floor: a card half over the edge has still been seen.
    return max(1, ((width - _shelfGutter) / _cardStride).ceil());
  }

  /// Counts an impression (once per series per day) for the cards that were
  /// really on screen — the outcome data that lets repeatedly-ignored picks
  /// fade and, later, trains the per-user weights.
  ///
  /// Callers must only reach here while the shelf is being looked at. This
  /// used to run from [setRecommendations], which fires from Discover's
  /// initState inside the shell's IndexedStack while the app opens on
  /// Library: every launch stamped a screenful of series "shown and ignored"
  /// that had never been rendered, and the only thing that ever takes a
  /// tally back is [RecOutcomeStore.pruneStale], sixty days later.
  void recordShelfImpressions() {
    final visible = _visibleRecommendations();
    if (visible.isEmpty) return;
    // The wildcard is pinned *last*, so on a full window it sits off the
    // right edge and has not been seen either. Slicing the visible list
    // gives it its impression only when the pool is short enough to bring
    // it into view, which is exactly when it is on screen.
    final onScreen = visible.take(_onScreenCardCount());
    RecOutcomeStore().recordImpressions([
      for (final rec in onScreen) rec.series.opdsId,
    ]);
  }

  /// Opens a series from a recommendation card, recording the tap outcome.
  void _openRecommended(Series series) {
    RecOutcomeStore().recordTap(series.opdsId);
    openSeries(series);
  }

  /// Advances the visible recommendation window so "Show me different" gives
  /// you the next batch; wraps to the start when the pool runs out.
  ///
  /// Both the guard and the wrap count the pool, not the whole list: the
  /// offset indexes the pool, while the list also holds the pinned wildcard.
  /// Counting it meant eleven picks offered a shuffle that redrew the same
  /// ten, and past that the wrap landed a card short and repeated one.
  void _rotateRecommendations() {
    final pool = _rotatingPool();
    if (pool.length <= _recommendWindow) return;
    setState(() {
      _recommendOffset = (_recommendOffset + _recommendWindow) % pool.length;
    });
    recordShelfImpressions();
  }

  Widget buildRecommendedShelf() {
    final headers = (opdsSettings?.isConfigured ?? false)
        ? OpdsClient(opdsSettings!).authHeaders
        : const <String, String>{};
    // Slice the pool into a visible window; wrap past the end so the shuffle
    // button can cycle.
    final visible = _visibleRecommendations();
    final canRotate = _rotatingPool().length > _recommendWindow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Recommended for you',
          trailing: canRotate
              ? IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Show me different',
                  visualDensity: VisualDensity.compact,
                  onPressed: _rotateRecommendations,
                )
              : null,
        ),
        SizedBox(
          height: 244,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final rec = visible[index];
              final series = rec.series;
              return RecommendCard(
                series: series,
                imageHeaders: headers,
                reason: rec.reason,
                isWildcard: rec.isWildcard,
                onTap: () => _openRecommended(series),
                onDismiss: () => _dismissRecommendation(series),
                onLike: () => _likeRecommendation(series),
                onLongPress: () => _showRecommendationOptions(series),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
