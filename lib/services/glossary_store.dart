import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Where in a series a term was last observed.
///
/// [volume] and [chapter] exist to order sightings and are meaningless to
/// show; [label] is the human-facing part. A chapter index alone would be
/// ambiguous because Umbra reads one EPUB per volume and the index restarts
/// in each, hence the pair.
class GlossarySighting {
  const GlossarySighting({
    required this.volume,
    required this.chapter,
    required this.label,
  });

  /// Volume number from the volume's title, or 0 when it carries none.
  final int volume;

  /// Zero-based chapter index within [volume].
  final int chapter;

  /// What the reader shows the chapter as — usually its table-of-contents
  /// title, e.g. `Chapter 412: The Duel`.
  final String label;

  /// True when this sighting is further along the series than [other].
  bool isAfter(GlossarySighting? other) {
    if (other == null) return true;
    if (volume != other.volume) return volume > other.volume;
    return chapter > other.chapter;
  }

  Map<String, dynamic> toJson() => {
    'volume': volume,
    'chapter': chapter,
    'label': label,
  };

  factory GlossarySighting.fromJson(Map<String, dynamic> json) =>
      GlossarySighting(
        volume: (json['volume'] as num?)?.toInt() ?? 0,
        chapter: (json['chapter'] as num?)?.toInt() ?? 0,
        label: json['label'] as String? ?? '',
      );
}

/// One glossary entry: a term (character / place / term) and the user's note
/// about it. Built up while reading a series to keep its large cast straight.
class GlossaryEntry {
  const GlossaryEntry({
    required this.id,
    required this.term,
    required this.note,
    this.lastSeen,
  });

  final String id;
  final String term;
  final String note;

  /// The furthest-along place this term has been read, or null if it has not
  /// been seen since the entry was made. Maintained by [GlossaryStore.
  /// noteSightings] as chapters are opened.
  final GlossarySighting? lastSeen;

  GlossaryEntry copyWith({
    String? term,
    String? note,
    GlossarySighting? lastSeen,
  }) => GlossaryEntry(
    id: id,
    term: term ?? this.term,
    note: note ?? this.note,
    lastSeen: lastSeen ?? this.lastSeen,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'term': term,
    'note': note,
    if (lastSeen != null) 'lastSeen': lastSeen!.toJson(),
  };

  factory GlossaryEntry.fromJson(Map<String, dynamic> json) {
    final seen = json['lastSeen'];
    return GlossaryEntry(
      id: json['id'] as String? ?? '',
      term: json['term'] as String? ?? '',
      note: json['note'] as String? ?? '',
      lastSeen: seen is Map<String, dynamic>
          ? GlossarySighting.fromJson(seen)
          : null,
    );
  }
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

  /// Records that every glossary term mentioned in [text] was seen at [at],
  /// keeping only the furthest-along sighting for each.
  ///
  /// Deliberately monotonic: re-reading chapter 5 must not rewrite "last seen
  /// in chapter 489" back to 5. The question the glossary answers is "how long
  /// has it been since this character turned up?", and the answer lives at the
  /// furthest point reached, not the most recent one visited.
  ///
  /// Returns true when anything changed, so callers can skip a reload.
  Future<bool> noteSightings(
    int seriesId,
    String text,
    GlossarySighting at,
  ) async {
    final all = await list(seriesId);
    if (all.isEmpty) return false;
    var changed = false;
    final next = <GlossaryEntry>[];
    for (final entry in all) {
      // Order matters: the cheap position check short-circuits the scan for
      // terms we already have a later sighting for.
      final update =
          entry.term.isNotEmpty &&
          at.isAfter(entry.lastSeen) &&
          _mentions(text, entry.term);
      next.add(update ? entry.copyWith(lastSeen: at) : entry);
      changed |= update;
    }
    if (changed) await _write(seriesId, next);
    return changed;
  }

  /// True when [term] appears in [text] as a word in its own right.
  ///
  /// The lookarounds stop a short name like `Al` matching inside `Also`. For
  /// scripts where `\w` doesn't apply — CJK names, say — they pass trivially
  /// and this degrades to a plain substring test, which is the right
  /// behaviour there since those scripts don't delimit words with spaces.
  static bool _mentions(String text, String term) => RegExp(
    '(?<!\\w)${RegExp.escape(term.trim())}(?!\\w)',
    caseSensitive: false,
  ).hasMatch(text);

  Future<void> _write(int seriesId, List<GlossaryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(seriesId),
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }
}
