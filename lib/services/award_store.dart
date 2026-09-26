// When each badge was first earned, and which ones the reader has not been
// told about yet.
//
// This is the only part of the awards system that keeps state, and it keeps
// as little as it can get away with. Everything about WHAT is earned is
// derived from the ledger on demand (see awards.dart); the one fact that
// cannot be recovered afterwards is WHEN something first became true, so
// that is what is written down.

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'awards.dart';

class AwardStore {
  AppDatabase get _db => AppDatabase.instance;

  /// Set once the reader's existing history has been folded in, so the
  /// backfill can never run twice and re-announce a decade of reading.
  static const _backfilledKey = 'awards_backfilled';

  Future<Map<String, DateTime>> earned() async {
    final rows = await _db.select(_db.awardRows).get();
    return {
      for (final row in rows)
        row.id: DateTime.tryParse(row.earnedAt) ?? DateTime(1970),
    };
  }

  /// Badges earned but not yet shown to the reader, oldest first.
  Future<List<String>> unseen() async {
    final rows =
        await (_db.select(_db.awardRows)
              ..where((t) => t.seen.equals(false))
              ..orderBy([(t) => OrderingTerm(expression: t.earnedAt)]))
            .get();
    return [for (final row in rows) row.id];
  }

  Future<void> markSeen(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    await _db.batch((b) {
      for (final id in ids) {
        b.update(
          _db.awardRows,
          const AwardRowsCompanion(seen: Value(true)),
          where: (t) => t.id.equals(id),
        );
      }
    });
  }

  /// Files everything in [snapshot], and returns what is genuinely new.
  ///
  /// The first pass is deliberately silent. A reader who has been in this
  /// app for two years before the feature existed has already earned most of
  /// a shelf, and announcing forty badges at once would spend the whole
  /// novelty of the thing in a single toast and teach them that the
  /// notification means nothing. So the first pass records the true earned
  /// dates — the history is real and the screen shows all of it — but marks
  /// them seen, and only what is earned from then on arrives as news.
  Future<List<String>> record(
    AwardSnapshot snapshot, {
    DateTime? now,
    Map<String, DateTime> earnedDates = const {},
  }) async {
    final stamp = now ?? DateTime.now();
    final known = await earned();
    final firstPass = (await _db.kvGet(_backfilledKey)) == null;

    final fresh = [
      for (final id in snapshot.badgeIds)
        if (!known.containsKey(id)) id,
    ];
    if (fresh.isEmpty) {
      if (firstPass) await _db.kvSet(_backfilledKey, stamp.toIso8601String());
      return const [];
    }

    await _db.batch((b) {
      for (final id in fresh) {
        b.insert(
          _db.awardRows,
          AwardRowsCompanion.insert(
            id: id,
            // A real date where the ledger knows one — the day the hundredth
            // hour actually landed reads better than the day the feature
            // shipped — and today only as a fallback.
            earnedAt: (earnedDates[id] ?? stamp).toIso8601String(),
            seen: Value(firstPass),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });

    if (firstPass) {
      await _db.kvSet(_backfilledKey, stamp.toIso8601String());
      return const [];
    }
    return fresh;
  }

  /// Drops every award. Used by backup restore, which is about to replay a
  /// ledger that the awards will be re-derived from anyway.
  Future<void> clear() => _db.delete(_db.awardRows).go();
}
