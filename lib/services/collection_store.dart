import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection.dart';
import 'cloud_sync_service.dart';

/// Persists user-defined library shelves ("Favourites", "Save for later",
/// etc.). Stored as a single JSON list in SharedPreferences.
class CollectionStore {
  static const _key = 'collections';

  /// Timestamp of the last local edit — drives whole-set last-write-wins when
  /// merging the iCloud copy.
  static const _modifiedKey = 'collections_modified_at';
  static final _rng = Random();

  /// All collections, ordered by creation time (oldest first).
  Future<List<Collection>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <Collection>[];
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          out.add(Collection.fromJson(entry));
        }
      }
      out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return out;
    } on FormatException {
      return const [];
    }
  }

  /// Creates a new collection with [name] and returns it.
  Future<Collection> create(String name) async {
    final clean = name.trim();
    // Microseconds + a random suffix so two creates fired within the same
    // clock tick still get distinct ids.
    final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
        '-${_rng.nextInt(1 << 32).toRadixString(16)}';
    final mark = Collection(
      id: id,
      name: clean.isEmpty ? 'Untitled' : clean,
      seriesIds: const [],
      createdAt: DateTime.now(),
    );
    final all = [...(await list()), mark];
    await _write(all);
    return mark;
  }

  Future<void> rename(String id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final all = await list();
    final next = [
      for (final c in all)
        if (c.id == id) c.copyWith(name: clean) else c,
    ];
    await _write(next);
  }

  Future<void> delete(String id) async {
    final all = await list();
    final next = [for (final c in all) if (c.id != id) c];
    await _write(next);
  }

  /// Toggles [seriesId] in/out of [collectionId].
  Future<void> setMembership(
    String collectionId,
    int seriesId, {
    required bool member,
  }) async {
    final all = await list();
    final next = <Collection>[];
    for (final c in all) {
      if (c.id != collectionId) {
        next.add(c);
        continue;
      }
      final ids = [...c.seriesIds];
      final has = ids.contains(seriesId);
      if (member && !has) ids.add(seriesId);
      if (!member && has) ids.removeWhere((id) => id == seriesId);
      next.add(c.copyWith(seriesIds: ids));
    }
    await _write(next);
  }

  /// Set of collection ids that already contain [seriesId].
  Future<Set<String>> collectionsContaining(int seriesId) async {
    final all = await list();
    return {
      for (final c in all)
        if (c.seriesIds.contains(seriesId)) c.id,
    };
  }

  Future<void> _write(List<Collection> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final c in all) c.toJson()]),
    );
    await prefs.setString(_modifiedKey, DateTime.now().toIso8601String());
    CloudSyncService().pushCollections();
  }

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  /// Serialises the whole collection set plus its last-modified time for the
  /// cloud. Merging is whole-set last-write-wins, so the timestamp travels
  /// with the data.
  Future<String> exportSyncBlob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final Object? collections;
    try {
      collections = raw == null || raw.isEmpty ? <dynamic>[] : jsonDecode(raw);
    } on FormatException {
      return jsonEncode({'modifiedAt': '', 'collections': <dynamic>[]});
    }
    return jsonEncode({
      'modifiedAt': prefs.getString(_modifiedKey) ?? '',
      'collections': collections,
    });
  }

  /// Replaces the local collection set with the cloud copy when the cloud's
  /// modified time is newer. Returns true if local data changed.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    final cloudModified = DateTime.tryParse(decoded['modifiedAt'] as String? ?? '');
    if (cloudModified == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final localModified = DateTime.tryParse(
      prefs.getString(_modifiedKey) ?? '',
    );
    if (localModified != null && !cloudModified.isAfter(localModified)) {
      return false;
    }
    final collections = decoded['collections'];
    if (collections is! List) return false;
    await prefs.setString(_key, jsonEncode(collections));
    await prefs.setString(_modifiedKey, cloudModified.toIso8601String());
    return true;
  }
}
