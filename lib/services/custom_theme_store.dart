import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_theme.dart';

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
