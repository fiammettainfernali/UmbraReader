import 'dart:async';

import '../models/download_record.dart';
import '../models/volume.dart';
import 'download_service.dart';

/// True when the server's copy of [volume] differs from the one on the device,
/// which is what happens when new chapters get compiled into it.
bool volumeChangedOnServer(Volume volume, DownloadRecord record) {
  final serverTime = volume.updatedAt;
  final recordTime = record.volumeUpdatedAt;
  final timeChanged =
      serverTime != null &&
      recordTime != null &&
      serverTime.isAfter(recordTime);
  final sizeChanged =
      volume.fileSizeBytes > 0 &&
      record.sizeBytes > 0 &&
      volume.fileSizeBytes != record.sizeBytes;
  return timeChanged || sizeChanged;
}

/// What to open after trying to bring a book up to date.
class FreshenOutcome {
  const FreshenOutcome(this.volume, {this.updated = false, this.note});

  final Volume volume;

  /// True when a newer copy was actually downloaded.
  final bool updated;

  /// Something to tell the reader, when the update didn't happen.
  final String? note;
}

/// Brings a downloaded book up to date just before it opens, so a book showing
/// new chapters doesn't need a trip to its page and a tap on download first.
///
/// It never stands between someone and their book. Every failure ends in opening
/// the copy already on the device, and a failed download leaves that copy alone,
/// since [DownloadService] only replaces it once the new one has fully arrived.
class BookFreshener {
  const BookFreshener({
    required this.fetchVolumes,
    required this.recordFor,
    required this.download,
    this.checkTimeout = const Duration(seconds: 8),
  });

  final Future<List<Volume>> Function(int seriesId) fetchVolumes;
  final DownloadRecord? Function(Volume volume) recordFor;
  final Future<void> Function(
    Volume volume,
    void Function(double progress) onProgress,
  )
  download;

  /// Far shorter than the feed's own 20 seconds. Someone has just tapped a book
  /// and is waiting, usually with the computer simply switched off.
  final Duration checkTimeout;

  static const couldNotCheck =
      "Couldn't reach your computer, so this is the copy on your phone.";

  Future<FreshenOutcome> run(
    Volume volume, {
    required void Function(double progress) onProgress,
  }) async {
    final record = recordFor(volume);
    // Nothing on the device means it's read from the server, which already has
    // the new chapters.
    if (record == null) return FreshenOutcome(volume);

    final List<Volume> onServer;
    try {
      onServer = await fetchVolumes(volume.seriesOpdsId).timeout(checkTimeout);
    } on Exception {
      return FreshenOutcome(volume, note: couldNotCheck);
    }

    Volume? current;
    for (final candidate in onServer) {
      if (candidate.fileName == volume.fileName) current = candidate;
    }
    // Gone from the server, or the new chapters went into a later volume. Either
    // way this copy is still the place to carry on from.
    if (current == null || !volumeChangedOnServer(current, record)) {
      return FreshenOutcome(volume);
    }

    try {
      await download(current, onProgress);
    } on DownloadException catch (e) {
      return FreshenOutcome(
        volume,
        note: '${e.message} Opening the copy on your phone.',
      );
    }
    return FreshenOutcome(current, updated: true);
  }
}
