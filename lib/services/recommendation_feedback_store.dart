import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
  }
}
