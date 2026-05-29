import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A reading status the user sets on a series themselves — overriding the
/// status the library otherwise infers from reading progress.
enum SeriesStatus {
  /// No manual status; the library infers from progress.
  none('None'),

  /// Actively reading.
  reading('Reading'),

  /// Read everything available; waiting on new chapters.
  caughtUp('Caught up'),

  /// Given up on it.
  dropped('Dropped');

  const SeriesStatus(this.label);

  final String label;

  static SeriesStatus fromName(String? name) {
    for (final s in SeriesStatus.values) {
      if (s.name == name) return s;
    }
    return SeriesStatus.none;
  }
}

/// Persists the user's manual per-series reading status as a single JSON map
/// (`seriesOpdsId` → status name) in SharedPreferences.
class SeriesStatusStore {
  static const _key = 'series_status';

  Future<Map<int, SeriesStatus>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <int, SeriesStatus>{};
      decoded.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id == null) return;
        final status = SeriesStatus.fromName(v?.toString());
        if (status != SeriesStatus.none) result[id] = status;
      });
      return result;
    } on FormatException {
      return const {};
    }
  }

  Future<SeriesStatus> statusFor(int seriesId) async {
    final all = await load();
    return all[seriesId] ?? SeriesStatus.none;
  }

  /// Sets [seriesId]'s status. [SeriesStatus.none] clears it.
  Future<void> setStatus(int seriesId, SeriesStatus status) async {
    final all = Map<int, SeriesStatus>.of(await load());
    if (status == SeriesStatus.none) {
      all.remove(seriesId);
    } else {
      all[seriesId] = status;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        for (final e in all.entries) '${e.key}': e.value.name,
      }),
    );
  }
}
