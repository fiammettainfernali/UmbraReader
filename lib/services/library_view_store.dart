import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/library_view.dart';
import 'cloud_sync_service.dart';

/// Persists how the reader has arranged their library — sort, direction and
/// filter set — and syncs it across devices. The reading-state chip is
/// stored with them but deliberately not restored; see [load].
///
/// Every other piece of user state in the app persists: progress, bookmarks,
/// collections, reader settings, themes. The library view was the exception,
/// so a library of several hundred series had to be re-narrowed from scratch
/// on every launch.
///
/// The whole view is one value under one key, resolved by last-writer-wins on
/// the time it was changed. Per-field merging would be wrong here: the sort
/// and the filters are chosen together as one arrangement, and interleaving
/// halves of two devices' arrangements would produce a view neither device
/// asked for.
class LibraryViewStore {
  static const _key = 'library_view';
  static const _keyUpdatedAt = 'library_view_updated_at';

  Future<LibraryView> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = _decode(prefs.getString(_key)) ?? LibraryView.initial;
    // Everything survives a launch except which reading-state chip was
    // tapped, and that exception is deliberate.
    //
    // The library screen only shows its home extras — the Continue card, the
    // in-progress shelf, the streak — on an unfiltered list. So tapping
    // "Reading", which is the most natural gesture there is for "where was
    // I", silently removed the resume card from every future launch, on
    // every device, with nothing on screen to connect the two. The chip had
    // become a one-way door into a library with no way back to the book.
    //
    // This is the same reasoning the class already applies to a search
    // query — a question you ask once, and reopening the app to a silently
    // narrowed library is worse than asking it again — which simply had not
    // been applied to the chip beside it. Saved views keep their own
    // reading state: choosing to save a filtered view is a different act
    // from tapping a chip to look something up.
    return stored.copyWith(readingState: ReadingStateFilter.any);
  }

  Future<void> save(LibraryView view) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(view.toJson()));
    await prefs.setString(
      _keyUpdatedAt,
      DateTime.now().toUtc().toIso8601String(),
    );
    CloudSyncService().pushLibraryViewSoon();
  }

  static LibraryView? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return LibraryView.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<DateTime> _updatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_keyUpdatedAt) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  Future<String> exportSyncBlob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return '';
    return jsonEncode({
      'view': jsonDecode(raw),
      'at': (await _updatedAt()).toIso8601String(),
    });
  }

  /// Takes the cloud's view when it was set more recently than this device's.
  /// Returns true when the local value changed.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    final at = DateTime.tryParse(decoded['at'] as String? ?? '');
    final view = decoded['view'];
    if (at == null || view is! Map<String, dynamic>) return false;
    // Not `isAfter` on equal timestamps: two devices that genuinely agree
    // would otherwise ping-pong a no-op change back and forth.
    if (!at.isAfter(await _updatedAt())) return false;
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(view);
    if (prefs.getString(_key) == encoded) return false;
    await prefs.setString(_key, encoded);
    await prefs.setString(_keyUpdatedAt, at.toIso8601String());
    return true;
  }
}
