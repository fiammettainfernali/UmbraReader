import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_theme.dart';
import 'cloud_sync_service.dart';

/// Persists user-defined reader themes alongside the built-in [kReaderThemes].
///
/// Each custom theme is just a [ReaderThemePreset] with a `custom-…` id.
/// They're loaded once at app start into [_loaded] so the synchronous
/// [readerThemeById] lookup can find them; saving a new one updates the
/// store and the in-memory cache.
class CustomThemeStore {
  static const _key = 'custom_themes';
  static List<ReaderThemePreset> _loaded = const [];

  /// Every theme the reader knows about — built-ins followed by user
  /// customs, in display order.
  static List<ReaderThemePreset> get all => [...kReaderThemes, ..._loaded];

  /// Just the user customs.
  static List<ReaderThemePreset> get customs => _loaded;

  /// Loads the saved customs into the in-memory cache. Call once at app
  /// start before any code asks for a theme by id.
  Future<void> initialize() async {
    _loaded = await _readAll();
    setAdditionalThemes(_loaded);
  }

  /// Upserts a custom theme (by id) and refreshes the cache.
  Future<void> save(ReaderThemePreset theme) async {
    final current = await _readAll();
    final next = [
      for (final t in current) if (t.id != theme.id) t,
      theme,
    ];
    await _writeAll(next);
    _loaded = next;
    setAdditionalThemes(_loaded);
  }

  /// Removes the custom theme with [id] from the store and cache.
  Future<void> delete(String id) async {
    final current = await _readAll();
    final next = [for (final t in current) if (t.id != id) t];
    await _writeAll(next);
    _loaded = next;
    setAdditionalThemes(_loaded);
  }

  Future<List<ReaderThemePreset>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <ReaderThemePreset>[];
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          final theme = _fromJson(entry);
          if (theme != null) out.add(theme);
        }
      }
      return out;
    } on FormatException {
      return const [];
    }
  }

  Future<void> _writeAll(List<ReaderThemePreset> themes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final t in themes) _toJson(t)]),
    );
    CloudSyncService().pushCustomThemes();
  }

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  Future<String> exportSyncBlob() async =>
      jsonEncode([for (final t in await _readAll()) _toJson(t)]);

  /// Merges a cloud blob into local, union by theme id — a theme made on
  /// either device shows up on both. On a same-id conflict the local copy
  /// wins (editing one theme on two devices at once isn't a real workflow,
  /// and keeping local avoids churning the reader's active theme).
  ///
  /// Like the glossary, deletions aren't represented: a theme deleted on one
  /// device can return from the other. Preferring to keep a theme the user
  /// built is the safe direction.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! List) return false;
    final local = await _readAll();
    final byId = {for (final t in local) t.id: t};
    var changed = false;
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      final theme = _fromJson(entry);
      if (theme == null || byId.containsKey(theme.id)) continue;
      byId[theme.id] = theme;
      changed = true;
    }
    if (!changed) return false;
    final next = byId.values.toList();
    // Write directly: _writeAll would push straight back to the cloud.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final t in next) _toJson(t)]),
    );
    _loaded = next;
    setAdditionalThemes(_loaded);
    return true;
  }

  static Map<String, dynamic> _toJson(ReaderThemePreset t) => {
    'id': t.id,
    'name': t.name,
    'background': t.background.toARGB32(),
    'text': t.text.toARGB32(),
    'secondary': t.secondary.toARGB32(),
    'highlight': t.highlight.toARGB32(),
  };

  static ReaderThemePreset? _fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;
    int? c(String key) {
      final v = json[key];
      return v is num ? v.toInt() : null;
    }
    final bg = c('background');
    final text = c('text');
    final sec = c('secondary');
    final hi = c('highlight');
    if (bg == null || text == null || sec == null || hi == null) return null;
    return ReaderThemePreset(
      id: id,
      name: name,
      background: Color(bg),
      text: Color(text),
      secondary: Color(sec),
      highlight: Color(hi),
    );
  }
}
