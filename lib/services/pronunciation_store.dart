import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One pronunciation override: speak [term] as [soundsLike].
class PronunciationEntry {
  const PronunciationEntry(this.term, this.soundsLike);

  final String term;
  final String soundsLike;

  Map<String, dynamic> toJson() => {'term': term, 'sounds': soundsLike};

  factory PronunciationEntry.fromJson(Map<String, dynamic> j) =>
      PronunciationEntry(
        (j['term'] as String?)?.trim() ?? '',
        (j['sounds'] as String?)?.trim() ?? '',
      );
}

/// Stores read-aloud pronunciation overrides — a global list plus per-series
/// lists — so the Kokoro voice says names/terms the way you want (e.g. "Klein"
/// → "Kline"). Applied server-side before synthesis; series entries win over
/// global ones for the same term.
class PronunciationStore {
  static const _globalKey = 'pron_global';
  String _seriesKey(int seriesId) => 'pron_series:$seriesId';

  Future<List<PronunciationEntry>> global() => _load(_globalKey);
  Future<List<PronunciationEntry>> series(int seriesId) =>
      _load(_seriesKey(seriesId));

  Future<void> saveGlobal(List<PronunciationEntry> entries) =>
      _save(_globalKey, entries);
  Future<void> saveSeries(int seriesId, List<PronunciationEntry> entries) =>
      _save(_seriesKey(seriesId), entries);

  /// The effective term → sounds-like map for a series: global entries with
  /// this series' entries layered on top.
  Future<Map<String, String>> merged(int seriesId) async {
    final map = <String, String>{};
    for (final e in await global()) {
      if (e.term.isNotEmpty) map[e.term] = e.soundsLike;
    }
    for (final e in await series(seriesId)) {
      if (e.term.isNotEmpty) map[e.term] = e.soundsLike;
    }
    return map;
  }

  Future<List<PronunciationEntry>> _load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) PronunciationEntry.fromJson(e),
      ].where((e) => e.term.isNotEmpty).toList();
    } on Object {
      return const [];
    }
  }

  Future<void> _save(String key, List<PronunciationEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = entries.where((e) => e.term.trim().isNotEmpty).toList();
    await prefs.setString(
      key,
      jsonEncode(clean.map((e) => e.toJson()).toList()),
    );
  }
}
