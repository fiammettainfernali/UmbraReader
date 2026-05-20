import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/download_record.dart';
import '../models/volume.dart';
import 'library_storage.dart';
import 'opds_client.dart';
import 'settings_service.dart';

/// Raised when a volume download fails. [message] is safe to show to the user.
class DownloadException implements Exception {
  DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads volume EPUBs to local storage and records them in the store.
class DownloadService {
  DownloadService({
    required this.settings,
    required this.storage,
    required this.store,
  });

  final OpdsSettings settings;
  final LibraryStorage storage;
  final DownloadStore store;

  /// Downloads [volume]'s EPUB, reporting fractional progress (0..1) through
  /// [onProgress]. The bytes land in a `.part` file first and are renamed into
  /// place only on success, so an interrupted download never looks complete.
  Future<void> download(
    Volume volume, {
    required void Function(double progress) onProgress,
  }) async {
    final client = http.Client();
    IOSink? sink;
    File? partFile;
    try {
      final request = http.Request('GET', Uri.parse(volume.downloadUrl));
      request.headers.addAll(OpdsClient(settings).authHeaders);

      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw DownloadException(
          'Server returned HTTP ${response.statusCode} while downloading '
          '"${volume.title}".',
        );
      }

      final epubFile = await storage.epubFile(volume);
      await epubFile.parent.create(recursive: true);
      partFile = File('${epubFile.path}.part');
      sink = partFile.openWrite();

      final total = response.contentLength ?? volume.fileSizeBytes;
      var received = 0;
      onProgress(0);
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (epubFile.existsSync()) await epubFile.delete();
      await partFile.rename(epubFile.path);
      partFile = null;
      onProgress(1);

      await store.put(
        volume,
        DownloadRecord(
          fileName: volume.fileName,
          sizeBytes: received,
          downloadedAt: DateTime.now(),
          volumeUpdatedAt: volume.updatedAt,
          etag: response.headers['etag'],
        ),
      );
    } on DownloadException {
      rethrow;
    } on Exception catch (e) {
      throw DownloadException('Could not download "${volume.title}".\n($e)');
    } finally {
      try {
        await sink?.close();
      } on Exception {
        // Already closing/closed — nothing to recover.
      }
      if (partFile != null && partFile.existsSync()) {
        try {
          await partFile.delete();
        } on Exception {
          // Leftover .part cleanup is best-effort.
        }
      }
      client.close();
    }
  }

  /// Removes a downloaded volume from disk and the manifest.
  Future<void> delete(Volume volume) async {
    await storage.deleteEpub(volume);
    await store.remove(volume);
  }
}
