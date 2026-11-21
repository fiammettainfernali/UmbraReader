import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';

/// Your own verdict on a novel: 1 to 5 stars and a line of thoughts.
class Rating {
  const Rating({required this.stars, this.note = '', required this.at});

  /// 1 to 5; 0 means cleared (kept, so the clear syncs rather than being
  /// undone by the other device's older rating).
  final int stars;
  final String note;

  /// When it was last set, for newest-wins between devices.
  final DateTime at;

  bool get isSet => stars > 0;

  Map<String, dynamic> toJson() => {
    'stars': stars,
    'note': note,
    'at': at.toIso8601String(),
  };

  static Rating? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final stars = raw['stars'];
    final at = DateTime.tryParse('${raw['at']}');
    if (stars is! num || at == null) return null;
    return Rating(
      stars: stars.toInt().clamp(0, 5),
      note: raw['note'] is String ? raw['note'] as String : '',
      at: at,
    );
  }
}

/// Ratings by series, kept on the phone and synced with the computer (the
/// `cloud_ratings` blob), newest first per novel, like reading states.
class RatingStore {
  static const _key = 'ratings';

  /// Every rating that is set, by series.
  Future<Map<int, Rating>> load() async => {
    for (final e in (await _loadRaw()).entries)
      if (e.value.isSet) e.key: e.value,
  };

  Future<Rating?> ratingFor(int seriesId) async => (await load())[seriesId];

  /// Sets the stars (1–5) and note for [seriesId]. 0 stars clears it.
  Future<void> rate(int seriesId, int stars, {String note = ''}) async {
    final all = Map<int, Rating>.of(await _loadRaw());
    all[seriesId] = Rating(
      stars: stars.clamp(0, 5),
      note: stars > 0 ? note.trim() : '',
      at: DateTime.now(),
    );
    await _save(all);
    CloudSyncService().pushRatings();
  }

  Future<Map<int, Rating>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return _parse(prefs.getString(_key));
  }

  Future<void> _save(Map<int, Rating> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(all));
  }

  static Map<int, Rating> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (int.tryParse('${e.key}') != null &&
              Rating.fromJson(e.value) != null)
            int.parse('${e.key}'): Rating.fromJson(e.value)!,
      };
    } on FormatException {
      return {};
    }
  }

  static String _encode(Map<int, Rating> all) =>
      jsonEncode({for (final e in all.entries) '${e.key}': e.value.toJson()});

  // ── sync (see CloudSyncService) ─────────────────────────────────────────

  Future<String> exportSyncBlob() async {
    final raw = await _loadRaw();
    return raw.isEmpty ? '' : _encode(raw);
  }

  /// Takes each novel's rating from [blob] when it was set later than this
  /// phone's. True when anything changed.
  Future<bool> mergeSyncBlob(String blob) async {
    final cloud = _parse(blob);
    if (cloud.isEmpty) return false;
    final merged = Map<int, Rating>.of(await _loadRaw());
    var changed = false;
    cloud.forEach((id, remote) {
      final local = merged[id];
      if (local != null && !remote.at.isAfter(local.at)) return;
      merged[id] = remote;
      changed = true;
    });
    if (changed) await _save(merged);
    return changed;
  }
}
