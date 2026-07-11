import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// One series' recommendation outcome tally.
class RecOutcome {
  const RecOutcome({
    required this.impressions,
    required this.taps,
    this.lastTapAt,
  });

  /// How many distinct days a rec card for this series was on screen.
  final int impressions;

  /// How many times the user opened the series from a rec card.
  final int taps;

  final DateTime? lastTapAt;

  /// Impressions that never led anywhere — the "shown and ignored" count.
  int get ignored => taps > 0 ? 0 : impressions;
}

/// Persists what happened to recommendations: shown (impression) and opened
/// (tap). The engine softens candidates that keep being shown and ignored,
/// and Phase B's learner trains on these outcomes.
///
/// Device-local by design — an impression only means anything on the screen
/// that actually displayed it.
class RecOutcomeStore {
  AppDatabase get _db => AppDatabase.instance;

  /// Loads every outcome, keyed by series opdsId.
  Future<Map<int, RecOutcome>> load() async {
    final rows = await _db.select(_db.recOutcomeRows).get();
    return {
      for (final row in rows)
        row.seriesId: RecOutcome(
          impressions: row.impressions,
          taps: row.taps,
          lastTapAt: DateTime.tryParse(row.lastTapAt ?? ''),
        ),
    };
  }

  /// Counts an impression for each series in [seriesIds] — at most one per
  /// series per local calendar day, so redraws of the same shelf don't spam
  /// the tally. [now] is overridable for tests.
  Future<void> recordImpressions(Iterable<int> seriesIds, {
    DateTime? now,
  }) async {
    final day = _dayKey(now ?? DateTime.now());
    for (final id in seriesIds) {
      final existing = await (_db.select(_db.recOutcomeRows)
            ..where((t) => t.seriesId.equals(id)))
          .getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.recOutcomeRows).insert(
              RecOutcomeRowsCompanion(
                seriesId: Value(id),
                impressions: const Value(1),
                lastShownDay: Value(day),
              ),
            );
      } else if (existing.lastShownDay != day) {
        await (_db.update(_db.recOutcomeRows)
              ..where((t) => t.seriesId.equals(id)))
            .write(
          RecOutcomeRowsCompanion(
            impressions: Value(existing.impressions + 1),
            lastShownDay: Value(day),
          ),
        );
      }
    }
  }

  /// Records that the user opened [seriesId] from a recommendation card.
  Future<void> recordTap(int seriesId, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toIso8601String();
    final existing = await (_db.select(_db.recOutcomeRows)
          ..where((t) => t.seriesId.equals(seriesId)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.recOutcomeRows).insert(
            RecOutcomeRowsCompanion(
              seriesId: Value(seriesId),
              taps: const Value(1),
              lastTapAt: Value(at),
            ),
          );
    } else {
      await (_db.update(_db.recOutcomeRows)
            ..where((t) => t.seriesId.equals(seriesId)))
          .write(
        RecOutcomeRowsCompanion(
          taps: Value(existing.taps + 1),
          lastTapAt: Value(at),
        ),
      );
    }
  }

  String _dayKey(DateTime t) {
    final local = t.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$d';
  }
}
