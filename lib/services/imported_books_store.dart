import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/volume.dart';
import 'library_storage.dart';

/// Persists sideloaded EPUBs the user imported from Files, kept separate from
/// the OPDS library (which is server-derived and would overwrite them on
/// sync). Each import is modelled as a single-volume [Volume] under a
/// synthetic negative series id so it never collides with real OPDS ids.
class ImportedBooksStore {
  static const _key = 'imported_books';

  /// Synthetic series id bucket for imported volumes. Negative so it can't
  /// clash with OPDS series ids (always >= 0).
  static const int importedSeriesId = -1;

  final _storage = LibraryStorage();

  Future<List<Volume>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic>) Volume.fromJson(e),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Copies [source] (a picked .epub) into library storage and records it as
  /// an imported volume. [originalName] is the picked file's name, used for
  /// the title and (de-duplicated) storage filename. Returns the new volume.
  Future<Volume> import(File source, String originalName) async {
    final existing = await list();
    final fileName = _uniqueName(originalName, existing);
    final volume = Volume(
      seriesOpdsId: importedSeriesId,
      title: _titleFromName(originalName),
      fileName: fileName,
      downloadUrl: '',
      fileSizeBytes: await source.length(),
      updatedAt: DateTime.now(),
    );
    final dest = await _storage.epubFile(volume);
    await dest.parent.create(recursive: true);
    await source.copy(dest.path);
    await _write([...existing, volume]);
    return volume;
  }

  Future<void> delete(Volume volume) async {
    await _storage.deleteEpub(volume);
    final next = [
      for (final v in await list())
        if (v.fileName != volume.fileName) v,
    ];
    await _write(next);
  }

  Future<void> _write(List<Volume> volumes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final v in volumes) v.toJson()]),
    );
  }

  String _titleFromName(String name) {
    var t = name;
    final dot = t.toLowerCase().lastIndexOf('.epub');
    if (dot > 0) t = t.substring(0, dot);
    return t.trim().isEmpty ? 'Imported book' : t.trim();
  }

  String _uniqueName(String name, List<Volume> existing) {
    var base = name.trim();
    if (!base.toLowerCase().endsWith('.epub')) base = '$base.epub';
    final taken = {for (final v in existing) v.fileName};
    if (!taken.contains(base)) return base;
    final stem = base.substring(0, base.length - 5);
    var n = 2;
    while (taken.contains('$stem ($n).epub')) {
      n++;
    }
    return '$stem ($n).epub';
  }
}
