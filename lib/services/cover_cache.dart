import 'dart:io';

import 'package:http/http.dart' as http;

import 'library_storage.dart';

/// Caches series cover images on disk so they still appear when the OPDS
/// server is unreachable.
class CoverCache {
  CoverCache(this._storage);

  final LibraryStorage _storage;

  /// The on-disk cover for [seriesId], or null if it hasn't been cached.
  Future<File?> cached(int seriesId) async {
    final file = File(await _storage.coverPath(seriesId));
    return file.existsSync() ? file : null;
  }

  /// Downloads [url] and stores it as [seriesId]'s cover, returning the saved
  /// file — or null if the download fails (e.g. offline).
  Future<File?> download(
    int seriesId,
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      final file = File(await _storage.coverPath(seriesId));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } on Exception {
      return null;
    }
  }
}
