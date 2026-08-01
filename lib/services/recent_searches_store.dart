import 'package:shared_preferences/shared_preferences.dart';

/// The last few library searches, offered back under an empty search box.
///
/// This is where search persistence belongs. The query itself deliberately
/// isn't part of the saved library view — reopening the app to a silently
/// narrowed grid would be worse than retyping — but the searches you make
/// repeatedly are worth one tap, and offering them visibly, only when the
/// box is empty, keeps the choice with the reader.
///
/// Local only: unlike the library arrangement, a half-finished search on the
/// phone has no business appearing on the iPad.
class RecentSearchesStore {
  static const _key = 'recent_library_searches';

  /// Kept short on purpose — a long history is just another list to read.
  static const maxEntries = 6;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  /// Records [query], most recent first. Case-insensitively de-duplicated so
  /// repeating a search promotes it rather than stacking near-copies.
  Future<List<String>> record(String query) async {
    final trimmed = query.trim();
    // One or two characters match most of the library; they are keystrokes
    // on the way somewhere, not searches worth remembering.
    if (trimmed.length < 3) return load();
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? const <String>[];
    final lower = trimmed.toLowerCase();
    final next = <String>[
      trimmed,
      for (final e in existing)
        if (e.toLowerCase() != lower) e,
    ];
    final capped = next.take(maxEntries).toList();
    await prefs.setStringList(_key, capped);
    return capped;
  }

  Future<List<String>> remove(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? const <String>[];
    final next = [
      for (final e in existing)
        if (e != query) e,
    ];
    await prefs.setStringList(_key, next);
    return next;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
