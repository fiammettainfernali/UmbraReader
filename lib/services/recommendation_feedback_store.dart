import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';

/// What kind of "no thanks" the user has given a series — fed into the
/// recommendation engine as a negative signal.
enum RecommendationFeedback {
  /// User tapped the ✕ on a recommendation card. Mild negative.
  dismissed,

  /// User reset reading progress on this series. Strong negative — they're
  /// explicitly done with where it was going.
  reset,
}

/// Persists per-series recommendation feedback so the engine can keep
/// suppressing dismissed/reset series across app launches.
class RecommendationFeedbackStore {
  static const _key = 'recommendation_feedback';

  /// Reads the current feedback map (series-opdsId -> feedback kind). Never
  /// throws — a missing or corrupt store yields an empty map.
  Future<Map<int, RecommendationFeedback>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <int, RecommendationFeedback>{};
      decoded.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id == null) return;
        final name = v?.toString();
        final feedback = RecommendationFeedback.values
            .where((e) => e.name == name)
            .firstOrNull;
        if (feedback != null) result[id] = feedback;
      });
      return result;
    } on FormatException {
      return const {};
    }
  }

  /// Records that the user dismissed [seriesOpdsId] from a recommendation
  /// surface. If a reset is already stored for this series, the harder reset
  /// signal is kept.
  Future<void> recordDismiss(int seriesOpdsId) async {
    final current = await load();
    if (current[seriesOpdsId] == RecommendationFeedback.reset) return;
    await _write({...current, seriesOpdsId: RecommendationFeedback.dismissed});
  }

  /// Records that the user reset reading progress on [seriesOpdsId]. Reset
  /// always wins over a prior dismiss.
  Future<void> recordReset(int seriesOpdsId) async {
    final current = await load();
    await _write({...current, seriesOpdsId: RecommendationFeedback.reset});
  }

  /// Clears stored feedback for [seriesOpdsId] — useful if the user picks the
  /// series back up later (re-engages with it).
  Future<void> forget(int seriesOpdsId) async {
    final current = await load();
    if (!current.containsKey(seriesOpdsId)) return;
    final next = Map<int, RecommendationFeedback>.of(current)
      ..remove(seriesOpdsId);
    await _write(next);
  }

  Future<void> _write(Map<int, RecommendationFeedback> feedback) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, String>{
      for (final entry in feedback.entries) '${entry.key}': entry.value.name,
    };
    await prefs.setString(_key, jsonEncode(encoded));
    CloudSyncService().pushRecFeedback();
  }

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  /// The feedback map as a JSON blob for the cloud.
  Future<String> exportSyncBlob() async {
    final current = await load();
    return jsonEncode(<String, String>{
      for (final entry in current.entries) '${entry.key}': entry.value.name,
    });
  }

  /// Merges a cloud feedback blob into local, taking the stronger signal per
  /// series (`reset` beats `dismissed`) and the union of all series. Returns
  /// true if local data changed. Writes directly so the merge doesn't recurse
  /// through [_write]'s push hook.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    final local = await load();
    final merged = Map<int, RecommendationFeedback>.of(local);
    var changed = false;
    decoded.forEach((k, v) {
      final id = int.tryParse(k.toString());
      if (id == null) return;
      final cloud = RecommendationFeedback.values
          .where((e) => e.name == v?.toString())
          .firstOrNull;
      if (cloud == null) return;
      final existing = merged[id];
      // reset is the stronger signal; otherwise take whichever exists.
      final winner = (existing == RecommendationFeedback.reset ||
              cloud == RecommendationFeedback.reset)
          ? RecommendationFeedback.reset
          : cloud;
      if (winner != existing) {
        merged[id] = winner;
        changed = true;
      }
    });
    if (!changed) return false;
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, String>{
      for (final entry in merged.entries) '${entry.key}': entry.value.name,
    };
    await prefs.setString(_key, jsonEncode(encoded));
    return true;
  }
}
