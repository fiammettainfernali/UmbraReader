import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';

/// The user's explicit verdict on a series, fed into the recommendation
/// engine. Ordered weakest → strongest so merge tie-breaks can compare.
enum RecommendationFeedback {
  /// User tapped 👍 "More like this" on a recommendation card. Positive.
  liked,

  /// "Not now" — hide from recommendation surfaces for a while without
  /// counting as a taste signal. Expires after [snoozeDays].
  snoozed,

  /// User tapped the ✕ on a recommendation card. Mild negative.
  dismissed,

  /// User reset reading progress on this series. Strong negative — they're
  /// explicitly done with where it was going.
  reset,
}

/// Persists per-series recommendation feedback (with timestamps) so the
/// engine keeps honouring it across launches and devices.
///
/// Stored as a JSON map `id -> "kind|iso8601"`; legacy entries that are a
/// bare kind name still parse (their time reads as the epoch, so any
/// timestamped action supersedes them).
class RecommendationFeedbackStore {
  static const _key = 'recommendation_feedback';

  /// How long a snooze keeps a series out of recommendation surfaces.
  static const snoozeDays = 30;

  /// How long a dismiss keeps suppressing a series. Tastes shift — "not
  /// interested" in March shouldn't still gag a series in July. Resets stay
  /// until re-engagement (they're a statement about the book, not the mood).
  static const dismissDays = 90;

  /// Reads the effective feedback map (series-opdsId -> feedback kind).
  /// Expired snoozes and aged-out dismisses are dropped. Never throws — a
  /// missing or corrupt store yields an empty map.
  Future<Map<int, RecommendationFeedback>> load({DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final full = await _upgradeLegacyTimestamps(await _loadRaw(), clock);
    final result = <int, RecommendationFeedback>{};
    full.forEach((id, entry) {
      final age = clock.difference(entry.at).inDays;
      if (entry.kind == RecommendationFeedback.snoozed && age >= snoozeDays) {
        return; // snooze has lapsed
      }
      if (entry.kind == RecommendationFeedback.dismissed &&
          age >= dismissDays) {
        return; // dismissal has aged out
      }
      result[id] = entry.kind;
    });
    return result;
  }

  /// Legacy entries carry no timestamp (they parse as the epoch); with
  /// expiry they'd all age out instantly, resurfacing everything the user
  /// ever dismissed at once. Start their clock now instead — a one-time,
  /// silent upgrade (no sync push; the merged winner still syncs later).
  Future<Map<int, _Entry>> _upgradeLegacyTimestamps(
    Map<int, _Entry> raw,
    DateTime clock,
  ) async {
    final epochThreshold = DateTime.fromMillisecondsSinceEpoch(1);
    if (raw.values.every((e) => e.at.isAfter(epochThreshold))) return raw;
    final upgraded = <int, _Entry>{
      for (final e in raw.entries)
        e.key: e.value.at.isAfter(epochThreshold)
            ? e.value
            : _Entry(e.value.kind, clock),
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(upgraded));
    return upgraded;
  }

  /// Records a 👍 on [seriesOpdsId]. An explicit like supersedes any earlier
  /// negative — the user changed their mind.
  Future<void> recordLike(int seriesOpdsId, {DateTime? now}) =>
      _record(seriesOpdsId, RecommendationFeedback.liked, now);

  /// Records a "not now" that hides the series for [snoozeDays].
  Future<void> recordSnooze(int seriesOpdsId, {DateTime? now}) =>
      _record(seriesOpdsId, RecommendationFeedback.snoozed, now);

  /// Records that the user dismissed [seriesOpdsId] from a recommendation
  /// surface. A stored reset is kept — both are negative and reset is the
  /// stronger statement.
  Future<void> recordDismiss(int seriesOpdsId, {DateTime? now}) async {
    final current = await _loadRaw();
    if (current[seriesOpdsId]?.kind == RecommendationFeedback.reset) return;
    await _record(seriesOpdsId, RecommendationFeedback.dismissed, now);
  }

  /// Records that the user reset reading progress on [seriesOpdsId].
  Future<void> recordReset(int seriesOpdsId, {DateTime? now}) =>
      _record(seriesOpdsId, RecommendationFeedback.reset, now);

  /// Clears stored feedback for [seriesOpdsId] — used when the user
  /// re-engages with the series.
  Future<void> forget(int seriesOpdsId) async {
    final current = await _loadRaw();
    if (!current.containsKey(seriesOpdsId)) return;
    final next = Map<int, _Entry>.of(current)..remove(seriesOpdsId);
    await _write(next);
  }

  Future<void> _record(int id, RecommendationFeedback kind, DateTime? now) async {
    final current = await _loadRaw();
    await _write({
      ...current,
      id: _Entry(kind, now ?? DateTime.now()),
    });
  }

  Future<Map<int, _Entry>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return _parse(prefs.getString(_key));
  }

  Map<int, _Entry> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <int, _Entry>{};
      decoded.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id == null) return;
        final entry = _Entry.parse(v?.toString());
        if (entry != null) result[id] = entry;
      });
      return result;
    } on FormatException {
      return {};
    }
  }

  Future<void> _write(Map<int, _Entry> feedback) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(feedback));
    CloudSyncService().pushRecFeedback();
  }

  String _encode(Map<int, _Entry> feedback) => jsonEncode(<String, String>{
        for (final e in feedback.entries) '${e.key}': e.value.encoded,
      });

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  /// The feedback map as a JSON blob for the cloud.
  Future<String> exportSyncBlob() async => _encode(await _loadRaw());

  /// Merges a cloud feedback blob into local: per series the NEWER action
  /// wins (last-writer-wins by timestamp); on a tie the stronger kind wins
  /// (reset > dismissed > snoozed > liked), which also preserves the legacy
  /// "reset beats dismissed" behaviour for un-timestamped entries. Returns
  /// true if local data changed. Writes directly so the merge doesn't
  /// recurse through [_write]'s push hook.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final cloud = _parse(blob);
    if (cloud.isEmpty) return false;
    final local = await _loadRaw();
    final merged = Map<int, _Entry>.of(local);
    var changed = false;
    cloud.forEach((id, remote) {
      final existing = merged[id];
      final winner = existing == null ? remote : _stronger(existing, remote);
      if (winner.kind != existing?.kind ||
          winner.at != existing?.at) {
        merged[id] = winner;
        changed = true;
      }
    });
    if (!changed) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(merged));
    return true;
  }

  _Entry _stronger(_Entry a, _Entry b) {
    if (a.at.isAfter(b.at)) return a;
    if (b.at.isAfter(a.at)) return b;
    return a.kind.index >= b.kind.index ? a : b;
  }
}

/// A feedback kind plus when it was given.
class _Entry {
  const _Entry(this.kind, this.at);

  final RecommendationFeedback kind;
  final DateTime at;

  String get encoded => '${kind.name}|${at.toIso8601String()}';

  /// Parses `"kind|iso"` and the legacy bare `"kind"` (epoch time, so any
  /// timestamped action supersedes it).
  static _Entry? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final sep = raw.indexOf('|');
    final name = sep < 0 ? raw : raw.substring(0, sep);
    final kind = RecommendationFeedback.values
        .where((e) => e.name == name)
        .firstOrNull;
    if (kind == null) return null;
    final at = sep < 0
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.tryParse(raw.substring(sep + 1)) ??
            DateTime.fromMillisecondsSinceEpoch(0);
    return _Entry(kind, at);
  }
}
