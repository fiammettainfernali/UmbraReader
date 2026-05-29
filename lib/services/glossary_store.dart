import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// One glossary entry: a term (character / place / term) and the user's note
/// about it. Built up while reading a series to keep its large cast straight.
class GlossaryEntry {
  const GlossaryEntry({
    required this.id,
    required this.term,
    required this.note,
  });

  final String id;
  final String term;
  final String note;

  GlossaryEntry copyWith({String? term, String? note}) => GlossaryEntry(
    id: id,
    term: term ?? this.term,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {'id': id, 'term': term, 'note': note};

  factory GlossaryEntry.fromJson(Map<String, dynamic> json) => GlossaryEntry(
    id: json['id'] as String? ?? '',
    term: json['term'] as String? ?? '',
    note: json['note'] as String? ?? '',
  );
}

/// Persists per-series glossaries as a JSON list under `glossary:<seriesId>`.
class GlossaryStore {
  static const _prefix = 'glossary:';
  static final _rng = Random();

  String _key(int seriesId) => '$_prefix$seriesId';

  /// Entries for [seriesId], sorted alphabetically by term.
  Future<List<GlossaryEntry>> list(int seriesId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(seriesId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <GlossaryEntry>[
        for (final e in decoded)
          if (e is Map<String, dynamic>) GlossaryEntry.fromJson(e),
      ];
      out.sort(
        (a, b) => a.term.toLowerCase().compareTo(b.term.toLowerCase()),
      );
      return out;
    } on FormatException {
      return const [];
    }
  }

  Future<void> upsert(int seriesId, GlossaryEntry entry) async {
    final all = await list(seriesId);
    final next = [
      for (final e in all)
        if (e.id != entry.id) e,
      entry,
    ];
    await _write(seriesId, next);
  }

  /// Creates a new entry with a unique id and saves it.
  Future<GlossaryEntry> create(int seriesId, String term, String note) async {
    final entry = GlossaryEntry(
      id: '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
          '-${_rng.nextInt(1 << 32).toRadixString(16)}',
      term: term.trim(),
      note: note.trim(),
    );
    await upsert(seriesId, entry);
    return entry;
  }

  Future<void> remove(int seriesId, String id) async {
    final all = await list(seriesId);
    await _write(seriesId, [for (final e in all) if (e.id != id) e]);
  }

  Future<void> _write(int seriesId, List<GlossaryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(seriesId),
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }
}
