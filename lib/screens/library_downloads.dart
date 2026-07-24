import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/download_record.dart';
import '../models/series.dart';
import '../models/volume.dart';
import '../services/download_service.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/opds_client.dart';
import '../services/reading_progress_store.dart';
import '../services/settings_service.dart';
import '../utils/volume_ordering.dart';

/// Everything the library screen does with *files on disk*, extracted from
/// its State: the user-initiated whole-library download, and the background
/// upkeep that keeps the next volume ready and prunes finished ones.
///
/// These belong together because they are one concern — getting volumes onto
/// the device and taking them off again — separate from the screen's real job
/// of displaying the library. Both borrow the library and settings to read
/// them, and call back only to refresh; neither drives the screen.
mixin LibraryDownloads<T extends StatefulWidget> on State<T> {
  // ── what the library State must provide ─────────────────────────────────

  OpdsSettings? get opdsSettings;
  SettingsService get settingsService;
  List<Series>? get librarySeries;
  LibraryCache? get libraryCache;
  DownloadStore? get downloadStore;

  /// Every known reading position — drives which volume comes next and which
  /// finished ones are safe to prune.
  List<ReadingEntry> get readingEntries;

  /// Re-reads the download records after files change on disk.
  Future<void> reloadDownloads();

  /// Re-reads reading state (the Continue shelf, recommendations).
  Future<void> reloadReading();

  void showSnack(String message);

  // ── state (owned by the mixin) ──────────────────────────────────────────

  bool _bulkDownloading = false;
  bool _bulkCancel = false;
  int _bulkDone = 0;
  int _bulkTotal = 0;
  String? _bulkCurrent;

  /// When library upkeep last ran, and whether it's running now — it is
  /// throttled because it used to fire on every sync / pull-to-refresh,
  /// stacking per-series network fetches that competed with the user's own
  /// checking and downloading.
  DateTime? _lastMaintenance;
  bool _maintenanceRunning = false;
  static const _maintenanceInterval = Duration(minutes: 30);

  bool get bulkDownloading => _bulkDownloading;

  // ── background upkeep ───────────────────────────────────────────────────

  /// Runs the auto-download / auto-delete pass, at most once per
  /// [_maintenanceInterval].
  Future<void> runLibraryMaintenance() async {
    if (_maintenanceRunning) return;
    final last = _lastMaintenance;
    if (last != null &&
        DateTime.now().difference(last) < _maintenanceInterval) {
      return;
    }
    _maintenanceRunning = true;
    _lastMaintenance = DateTime.now();
    try {
      await _autoDownloadNextVolumes();
      await _autoDeleteFinishedVolumes();
    } finally {
      _maintenanceRunning = false;
    }
  }

  /// When enabled, removes the downloaded EPUB of any volume the reader has
  /// finished *and* moved past (a later volume in the same series has been
  /// started). Reading progress/history is left intact, so the volume still
  /// shows as finished and can be re-downloaded. Uses only local data — no
  /// network — keying volume order off the volume number.
  Future<void> _autoDeleteFinishedVolumes() async {
    if (!await settingsService.autoDeleteFinished()) return;
    final settings = opdsSettings;
    final downloads = downloadStore;
    if (settings == null || downloads == null) return;

    final bySeries = <int, List<ReadingEntry>>{};
    for (final e in readingEntries) {
      bySeries.putIfAbsent(e.volume.seriesOpdsId, () => []).add(e);
    }
    final service = DownloadService(
      settings: settings,
      storage: LibraryStorage(),
      store: downloads,
    );
    var changed = false;
    for (final entries in bySeries.values) {
      // Highest volume number the reader has actually started in this series.
      int? maxStarted;
      for (final e in entries) {
        if (!e.progress.isStarted) continue;
        final n = volumeNumber(e.volume);
        if (n != null && (maxStarted == null || n > maxStarted)) {
          maxStarted = n;
        }
      }
      if (maxStarted == null) continue;
      for (final e in entries) {
        final n = volumeNumber(e.volume);
        if (n == null || n >= maxStarted) continue;
        if (!e.progress.isFinished) continue;
        if (!downloads.isDownloaded(e.volume)) continue;
        try {
          await service.delete(e.volume);
          changed = true;
        } on Exception {
          // Best-effort.
        }
      }
    }
    if (changed && mounted) await reloadDownloads();
  }

  /// Best-effort background fetch of the next volume for each in-progress
  /// series, so finishing one rolls straight into the next without a manual
  /// download. Bounded to one volume per series per sync, gated by the
  /// auto-download setting and (optionally) Wi-Fi.
  Future<void> _autoDownloadNextVolumes() async {
    final settings = opdsSettings;
    final downloads = downloadStore;
    if (settings == null || !settings.isConfigured || downloads == null) return;
    if (!await settingsService.autoDownloadNext()) return;
    if (await settingsService.autoDownloadWifiOnly() && !await _onWifi()) {
      return;
    }

    // Most-recently-read entry per started series (so the just-finished
    // volume's successor is the one we pull).
    final perSeries = <int, ReadingEntry>{};
    for (final e in readingEntries) {
      if (!e.progress.isStarted) continue;
      final existing = perSeries[e.volume.seriesOpdsId];
      final et = e.progress.updatedAt;
      final xt = existing?.progress.updatedAt;
      if (existing == null || (et != null && (xt == null || et.isAfter(xt)))) {
        perSeries[e.volume.seriesOpdsId] = e;
      }
    }
    if (perSeries.isEmpty) return;

    final client = OpdsClient(settings);
    final service = DownloadService(
      settings: settings,
      storage: LibraryStorage(),
      store: downloads,
    );
    var pulled = false;
    for (final entry in perSeries.values) {
      try {
        final fetched = await client.fetchVolumes(entry.volume.seriesOpdsId);
        // Cache the list so the series opens (and reads) offline later.
        await libraryCache?.saveVolumes(entry.volume.seriesOpdsId, fetched);
        final volumes = volumesInReadingOrder(fetched);
        final idx = volumes.indexWhere(
          (v) => v.fileName == entry.volume.fileName,
        );
        if (idx < 0 || idx >= volumes.length - 1) continue;
        final next = volumes[idx + 1];
        if (downloads.isDownloaded(next)) continue;
        await service.download(next, onProgress: (_) {});
        pulled = true;
      } on Exception {
        // Best-effort per series — a failure here never blocks the library.
      }
    }
    if (pulled && mounted) await reloadDownloads();
  }

  /// True on Wi-Fi or ethernet. On any error we report false so auto-download
  /// errs toward *not* spending cellular data.
  Future<bool> _onWifi() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet);
    } on Exception {
      return false;
    }
  }

  // ── whole-library download ──────────────────────────────────────────────

  /// True when a volume isn't downloaded, or the server has a newer build of
  /// it than what's on the device (a re-compiled volume).
  bool needsDownload(Volume volume, DownloadRecord? record) {
    if (record == null) return true;
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

  /// Confirms, then downloads every volume of every series for offline use.
  Future<void> confirmDownloadEverything() async {
    final count = librarySeries?.length ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download whole library?'),
        content: Text(
          'Umbra Reader will download every volume of all $count series for '
          'offline reading. This can take a while and use a lot of storage '
          'and data. Books already downloaded are skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _downloadEverything();
  }

  Future<void> _downloadEverything() async {
    final settings = opdsSettings;
    final library = librarySeries;
    if (settings == null || !settings.isConfigured || library == null) return;

    setState(() {
      _bulkDownloading = true;
      _bulkCancel = false;
      _bulkDone = 0;
      _bulkTotal = 0;
      _bulkCurrent = null;
    });

    final storage = LibraryStorage();
    final store = DownloadStore(storage);
    await store.load();
    final service = DownloadService(
      settings: settings,
      storage: storage,
      store: store,
    );
    final opds = OpdsClient(settings);
    var failures = 0;

    // Phase 1 — scan every series for volumes that need downloading.
    final pending = <Volume>[];
    for (final series in library) {
      if (_bulkCancel || !mounted) break;
      setState(() => _bulkCurrent = series.title);
      try {
        final volumes = await opds.fetchVolumes(series.opdsId);
        // Cache the list so each series opens (and reads) offline later.
        await libraryCache?.saveVolumes(series.opdsId, volumes);
        for (final volume in volumes) {
          if (needsDownload(volume, store.recordFor(volume))) {
            pending.add(volume);
          }
        }
      } on OpdsException {
        failures++;
      }
    }

    if (!mounted) return;
    setState(() {
      _bulkTotal = pending.length;
      _bulkCurrent = null;
    });

    // Phase 2 — download them one at a time.
    for (final volume in pending) {
      if (_bulkCancel || !mounted) break;
      setState(() => _bulkCurrent = volume.title);
      try {
        await service.download(volume, onProgress: (_) {});
      } on DownloadException {
        failures++;
      }
      if (!mounted) return;
      setState(() => _bulkDone++);
    }

    if (!mounted) return;
    final cancelled = _bulkCancel;
    final done = _bulkDone;
    final total = _bulkTotal;
    setState(() {
      _bulkDownloading = false;
      _bulkCurrent = null;
    });
    await reloadDownloads();
    await reloadReading();

    final String message;
    if (cancelled) {
      message = 'Download stopped — $done of $total volumes saved.';
    } else if (total == 0) {
      message = failures > 0
          ? 'Nothing new to download ($failures series unreachable).'
          : 'Your whole library is already downloaded.';
    } else if (failures > 0) {
      message = 'Library download finished — $done saved, $failures failed.';
    } else {
      message = 'Library downloaded — $done volumes saved for offline reading.';
    }
    showSnack(message);
  }

  /// Progress banner shown while the whole-library download runs.
  Widget buildBulkBanner() {
    final theme = Theme.of(context);
    final total = _bulkTotal;
    final done = _bulkDone;
    final scanning = total == 0 && !_bulkCancel;
    final label = _bulkCancel
        ? 'Stopping…'
        : scanning
        ? 'Scanning library for new volumes…'
        : 'Downloading $done of $total volumes…';
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              value: (total > 0 && !scanning) ? done / total : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_bulkCurrent != null)
                  Text(
                    _bulkCurrent!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: _bulkCancel
                ? null
                : () => setState(() => _bulkCancel = true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
