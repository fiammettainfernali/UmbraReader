import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/library_view.dart';
import '../models/saved_view.dart';
import 'cloud_sync_service.dart';

/// Stores the user's named library arrangements and syncs them.
///
/// Whole-set last-writer-wins on a modified timestamp, the same shape
/// [CollectionStore] uses. Per-view merging would need tombstones to stop a
/// deleted view resurrecting from the other device, and for a handful of
/// deliberately-curated entries that machinery costs more than it buys —
/// the losing side of a conflict is a rename or an ordering, not data the
/// user can't see is missing.
class SavedViewStore {
  static const _key = 'saved_views';
  static const _modifiedKey = 'saved_views_modified_at';

  static final _rng = Random();

  Future<List<SavedView>> list() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key));
  }

  /// Saves [view] under [name]. Returns the stored list, newest last.
  Future<List<SavedView>> create(
    String name,
    LibraryView view, {
    String query = '',
  }) async {
    final all = await list();
    final saved = SavedView(
      id:
          '${DateTime.now().microsecondsSinceEpoch}'
          '${_rng.nextInt(0xFFFF).toRadixString(16)}',
      name: name.trim(),
      query: query.trim(),
      view: view,
      createdAt: DateTime.now(),
    );
    return _write([...all, saved]);
  }

  Future<List<SavedView>> rename(String id, String name) async {
    final all = await list();
    return _write([
      for (final v in all)
        if (v.id == id) v.copyWith(name: name.trim()) else v,
    ]);
  }

  /// Replaces [id]'s stored arrangement with the one currently in use.
  Future<List<SavedView>> update(
    String id,
    LibraryView view, {
    String query = '',
  }) async {
    final all = await list();
    return _write([
      for (final v in all)
        if (v.id == id) v.copyWith(view: view, query: query.trim()) else v,
    ]);
  }

  Future<List<SavedView>> delete(String id) async {
    final all = await list();
    return _write([
      for (final v in all)
        if (v.id != id) v,
    ]);
  }

  /// Reorders the list, so the views used most can be moved to the top.
  Future<List<SavedView>> reorder(List<SavedView> ordered) => _write(ordered);

  Future<List<SavedView>> _write(List<SavedView> views) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final v in views) v.toJson()]),
    );
    await prefs.setString(
      _modifiedKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    CloudSyncService().pushSavedViews();
    return views;
  }

  static List<SavedView> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic>) ?SavedView.fromJson(e),
      ];
    } on FormatException {
      return const [];
    }
  }

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  Future<String> exportSyncBlob() async {
    final prefs = await SharedPreferences.getInstance();
    final modified = prefs.getString(_modifiedKey);
    // Never touched: export nothing rather than an empty set, so a fresh
    // install can't wipe the views already in the cloud.
    if (modified == null) return '';
    return jsonEncode({
      'modifiedAt': modified,
      'views': [for (final v in await list()) v.toJson()],
    });
  }

  /// Takes the cloud's set when it was changed more recently. Returns true
  /// when the local set changed.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    final cloudModified = DateTime.tryParse(
      decoded['modifiedAt'] as String? ?? '',
    );
    final views = decoded['views'];
    if (cloudModified == null || views is! List) return false;
    final prefs = await SharedPreferences.getInstance();
    final localModified = DateTime.tryParse(
      prefs.getString(_modifiedKey) ?? '',
    );
    if (localModified != null && !cloudModified.isAfter(localModified)) {
      return false;
    }
    final encoded = jsonEncode(views);
    if (prefs.getString(_key) == encoded) return false;
    await prefs.setString(_key, encoded);
    await prefs.setString(_modifiedKey, cloudModified.toIso8601String());
    return true;
  }
}
