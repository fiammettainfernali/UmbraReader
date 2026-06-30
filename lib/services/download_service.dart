import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/download_record.dart';
import '../models/volume.dart';
import 'epub_parser.dart';
import 'library_storage.dart';
import 'opds_client.dart';
import 'reading_progress_store.dart';
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

      await _refreshReadingProgress(volume, epubFile);
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

  /// After a (re)download, refreshes the saved reading position's chapter
  /// count from the new EPUB. If a re-compiled volume gained chapters, a book
  /// that was marked finished stops being finished — so it returns to the
  /// "Continue reading" shelf. Best-effort: any failure leaves progress as-is.
  Future<void> _refreshReadingProgress(Volume volume, File epubFile) async {
    try {
      final progressStore = ReadingProgressStore();
      final progress = await progressStore.load(volume);
      // Nothing has been read — there is no position to refresh.
      if (!progress.isStarted) return;
      final book = await EpubParser().open(epubFile);
      if (book.chapters.isEmpty ||
          book.chapters.length == progress.chapterCount) {
        return;
      }
      await progressStore.save(
        volume,
        ReadingProgress(
          chapterIndex: progress.chapterIndex.clamp(
            0,
            book.chapters.length - 1,
          ),
          blockIndex: progress.blockIndex,
          chapterCount: book.chapters.length,
        ),
        // A background count refresh must not un-hide a volume the user
        // removed from the Continue shelf.
        unhide: false,
      );
    } on Exception {
      // Best-effort — the download itself already succeeded.
    }
  }
}
