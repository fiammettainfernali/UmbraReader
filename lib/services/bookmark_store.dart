import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark.dart';
import '../models/volume.dart';

/// Persists user bookmarks per volume.
///
/// Each volume's bookmarks live under a single JSON-encoded list in
/// SharedPreferences keyed `bookmarks:<seriesOpdsId>/<fileName>`. Listing,
/// adding and removing all rewrite the volume's whole list — fine here since
/// a single book rarely has more than a handful of bookmarks.
class BookmarkStore {
  static const _prefix = 'bookmarks:';

  String _key(Volume volume) =>
      '$_prefix${volume.seriesOpdsId}/${volume.fileName}';

  /// Bookmarks for [volume], newest-first.
  Future<List<Bookmark>> list(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(volume));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final marks = <Bookmark>[];
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          marks.add(Bookmark.fromJson(entry));
        }
      }
      marks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return marks;
    } on FormatException {
      return const [];
    }
  }

  /// Appends [bookmark] to [volume]'s list (idempotent on id).
  Future<void> add(Volume volume, Bookmark bookmark) async {
    final current = await list(volume);
    final next = [
      bookmark,
      for (final b in current)
        if (b.id != bookmark.id) b,
    ];
    await _write(volume, next);
  }

  /// Removes the bookmark with [id] from [volume]'s list.
  Future<void> remove(Volume volume, String id) async {
    final current = await list(volume);
    final next = [for (final b in current) if (b.id != id) b];
    await _write(volume, next);
  }

  /// Drops every bookmark for [volume] — useful when reading progress is
  /// reset on the same volume.
  Future<void> clear(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(volume));
  }

  Future<void> _write(Volume volume, List<Bookmark> marks) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode([for (final b in marks) b.toJson()]);
    await prefs.setString(_key(volume), encoded);
  }
}
