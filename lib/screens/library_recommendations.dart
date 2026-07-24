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

  /// Re-reads reading state after feedback changes what should be suggested.
  Future<void> reloadReading();

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
    recordShelfImpressions();
  }

  /// Number of recommendations on screen at one time.
  static const int _recommendWindow = 10;

  Future<void> _dismissRecommendation(Series series) async {
    await RecommendationFeedbackStore().recordDismiss(series.opdsId);
    await reloadReading();
  }

  /// Records a 👍 "more like this" and refreshes so the shelf leans into it.
  Future<void> _likeRecommendation(Series series) async {
    final messenger = ScaffoldMessenger.of(context);
    await RecommendationFeedbackStore().recordLike(series.opdsId);
    messenger.showSnackBar(
      SnackBar(content: Text('More picks like “${series.title}” coming up.')),
    );
    await reloadReading();
  }

  /// Records a "not now" (30-day snooze) and refreshes the shelf.
  Future<void> _snoozeRecommendation(Series series) async {
    final messenger = ScaffoldMessenger.of(context);
    await RecommendationFeedbackStore().recordSnooze(series.opdsId);
    messenger.showSnackBar(
      SnackBar(content: Text('“${series.title}” hidden for 30 days.')),
    );
    await reloadReading();
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

  /// The recommendations currently visible in the shelf window. The
  /// exploration wildcard (if any) is pinned as the last visible card in
  /// every window so it always gets its one slot.
  List<Recommendation> _visibleRecommendations() {
    final wildcard = _recommendations
        .where((r) => r.isWildcard)
        .toList();
    final pool = [
      for (final r in _recommendations)
        if (!r.isWildcard) r,
    ];
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

  /// Counts an impression (once per series per day) for the recs on screen —
  /// the outcome data that lets repeatedly-ignored picks fade and, later,
  /// trains the per-user weights.
  void recordShelfImpressions() {
    final visible = _visibleRecommendations();
    if (visible.isEmpty) return;
    RecOutcomeStore().recordImpressions([
      for (final rec in visible) rec.series.opdsId,
    ]);
  }

  /// Opens a series from a recommendation card, recording the tap outcome.
  void _openRecommended(Series series) {
    RecOutcomeStore().recordTap(series.opdsId);
    openSeries(series);
  }

  /// Advances the visible recommendation window so "Show me different" gives
  /// you the next batch; wraps to the start when the pool runs out.
  void _rotateRecommendations() {
    if (_recommendations.length <= _recommendWindow) return;
    setState(() {
      _recommendOffset =
          (_recommendOffset + _recommendWindow) % _recommendations.length;
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
    final canRotate = _recommendations.length > _recommendWindow;
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
