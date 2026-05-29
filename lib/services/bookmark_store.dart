import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark.dart';
import '../models/volume.dart';
import 'cloud_sync_service.dart';

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
    CloudSyncService().pushBookmarks();
  }

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  /// All bookmarks across every volume as one JSON blob, keyed by the same
  /// `bookmarks:<seriesId>/<fileName>` SharedPreferences keys.
  Future<String> exportSyncBlob() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        out[key] = jsonDecode(raw);
      } on FormatException {
        // Skip a corrupt entry rather than abort the whole export.
      }
    }
    return jsonEncode(out);
  }

  /// Union-by-id merge: every bookmark id present on either device is kept.
  /// Returns true if any local list gained entries. (Deletions are not
  /// propagated — this never loses a highlight, at the cost of a deleted one
  /// possibly reappearing from the other device.)
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    final prefs = await SharedPreferences.getInstance();
    var changed = false;
    for (final entry in decoded.entries) {
      final key = entry.key;
      final cloudList = entry.value;
      if (key is! String || !key.startsWith(_prefix) || cloudList is! List) {
        continue;
      }
      final byId = <String, Map<String, dynamic>>{};
      // Existing local entries first.
      final localRaw = prefs.getString(key);
      if (localRaw != null && localRaw.isNotEmpty) {
        try {
          final localList = jsonDecode(localRaw);
          if (localList is List) {
            for (final m in localList) {
              if (m is Map<String, dynamic> && m['id'] is String) {
                byId[m['id'] as String] = m;
              }
            }
          }
        } on FormatException {
          // fall through — cloud entries will populate the map
        }
      }
      final before = byId.length;
      for (final m in cloudList) {
        if (m is Map<String, dynamic> && m['id'] is String) {
          byId.putIfAbsent(m['id'] as String, () => m);
        }
      }
      if (byId.length != before) {
        await prefs.setString(key, jsonEncode(byId.values.toList()));
        changed = true;
      }
    }
    return changed;
  }
}
