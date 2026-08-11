import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
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
/// Moves the bytes of one file to [target], reporting 0..1 progress.
///
/// A seam under [DownloadService] rather than an abstraction for its own
/// sake: the platform downloader lives behind a method channel that does
/// not exist in a test process, and the pipeline worth testing — the part
/// file, the rename, the manifest write, the reparse — is everything
/// *around* the transfer. [httpFetch] lets that be exercised without a
/// device.
typedef FileFetch =
    Future<void> Function(
      Uri url,
      Map<String, String> headers,
      File target,
      void Function(double progress) onProgress,
    );

/// The real one: hands the transfer to the platform — URLSession on iOS —
/// so it survives the app being backgrounded.
Future<void> platformFetch(
  Uri url,
  Map<String, String> headers,
  File target,
  void Function(double progress) onProgress,
) async {
  final task = DownloadTask(
    url: url.toString(),
    headers: headers,
    directory: target.parent.path,
    filename: target.uri.pathSegments.last,
    baseDirectory: BaseDirectory.root,
    updates: Updates.statusAndProgress,
    allowPause: true,
    retries: 2,
  );
  final result = await FileDownloader().download(
    task,
    onProgress: (p) {
      // The platform reports -1 for "unknown"; passing that through would
      // drive a progress bar backwards.
      if (p >= 0) onProgress(p.clamp(0.0, 1.0));
    },
  );
  switch (result.status) {
    case TaskStatus.complete:
      return;
    case TaskStatus.canceled:
      throw const _FetchFailure('the download was cancelled');
    case TaskStatus.notFound:
      throw const _FetchFailure('the server no longer has it');
    default:
      throw _FetchFailure(result.exception?.description ?? 'transfer failed');
  }
}

/// A plain in-process download, for tests and for platforms where the
/// background downloader isn't available.
Future<void> httpFetch(
  Uri url,
  Map<String, String> headers,
  File target,
  void Function(double progress) onProgress,
) async {
  final client = http.Client();
  IOSink? sink;
  try {
    final request = http.Request('GET', url)..headers.addAll(headers);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw _FetchFailure('server returned HTTP ${response.statusCode}');
    }
    sink = target.openWrite();
    final total = response.contentLength ?? 0;
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
    }
    await sink.flush();
  } finally {
    await sink?.close();
    client.close();
  }
}

class _FetchFailure implements Exception {
  const _FetchFailure(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class DownloadService {
  DownloadService({
    required this.settings,
    required this.storage,
    required this.store,
    FileFetch? fetch,
  }) : fetch = fetch ?? platformFetch;

  final OpdsSettings settings;
  final LibraryStorage storage;
  final DownloadStore store;

  /// How the bytes get here. Defaults to the platform downloader.
  final FileFetch fetch;

  /// Downloads [volume]'s EPUB, reporting fractional progress (0..1)
  /// through [onProgress].
  ///
  /// The transfer is handed to the platform's own downloader — URLSession
  /// on iOS — rather than streamed through Dart. That is what lets it keep
  /// going once the app is backgrounded: iOS freezes Dart the moment the
  /// process suspends, so a Dart-side download of a large EPUB simply
  /// stopped the instant the reader looked away, and a whole-library run
  /// only progressed while someone watched it.
  ///
  /// The bytes still land in a `.part` file and are renamed into place
  /// only on success, so an interrupted download never looks complete.
  Future<void> download(
    Volume volume, {
    required void Function(double progress) onProgress,
  }) async {
    File? partFile;
    try {
      final epubFile = await storage.epubFile(volume);
      await epubFile.parent.create(recursive: true);
      partFile = File('${epubFile.path}.part');
      if (partFile.existsSync()) await partFile.delete();

      onProgress(0);
      await fetch(
        Uri.parse(volume.downloadUrl),
        OpdsClient(settings).authHeaders,
        partFile,
        onProgress,
      );

      if (!partFile.existsSync()) {
        throw DownloadException(
          'Download of "${volume.title}" reported success but produced no '
          'file.',
        );
      }
      final received = await partFile.length();

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
          // The platform downloader does not surface response headers, so
          // the etag is no longer captured here. Freshness still works:
          // volumeUpdatedAt is what needsDownload actually compares.
          etag: null,
        ),
      );

      await _refreshReadingProgress(volume, epubFile);
    } on DownloadException {
      rethrow;
    } on _FetchFailure catch (e) {
      throw DownloadException('Could not download "${volume.title}" — $e.');
    } on FileSystemException catch (e) {
      // ENOSPC — the one storage failure worth a specific, actionable
      // message instead of a raw error dump.
      if (e.osError?.errorCode == 28) {
        throw DownloadException(
          'Not enough free space to download "${volume.title}". '
          'Free up storage (Settings → Storage) and try again.',
        );
      }
      throw DownloadException('Could not save "${volume.title}".\n($e)');
    } on Exception catch (e) {
      throw DownloadException('Could not download "${volume.title}".\n($e)');
    } finally {
      if (partFile != null && partFile.existsSync()) {
        try {
          await partFile.delete();
        } on Exception {
          // Leftover .part cleanup is best-effort.
        }
      }
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
          blockChar: progress.blockChar,
          chapterPath: progress.chapterPath,
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
