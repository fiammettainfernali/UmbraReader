import 'dart:async';
import 'dart:math';

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
import '../services/recommendation_engine.dart';
import '../services/cloud_sync_service.dart';
import '../services/recommendation_feedback_store.dart';
import '../services/series_status_store.dart';
import '../services/settings_service.dart';
import '../utils/volume_ordering.dart';
import '../widgets/cached_cover.dart';
import 'backup_screen.dart';
import 'collections_screen.dart';
import 'imported_books_screen.dart';
import 'reader_screen.dart';
import 'series_detail_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'storage_screen.dart';

/// How the library grid is ordered.
enum LibrarySort {
  titleAsc('Title (A–Z)'),
  recentlyUpdated('Recently updated'),
  recentlyRead('Recently read'),
  author('Author'),
  readingStatus('Reading status');

  const LibrarySort(this.label);

  /// Human-readable label shown in the sort menu.
  final String label;
}

/// Quick reading-state chip selection above the library grid.
enum ReadingStateFilter {
  any('All'),
  inProgress('Reading'),
  unread('Unread'),
  finished('Finished'),
  dropped('Dropped');

  const ReadingStateFilter(this.label);

  final String label;
}

/// Sort rank for reading statuses — active series first, finished/abandoned last.
int _statusRank(String status) => switch (status.toLowerCase()) {
  'ongoing' => 0,
  'hiatus' => 1,
  'completed' => 2,
  'dropped' => 3,
  _ => 4,
};

/// The home screen — a searchable, sortable cover grid of the OPDS library.
///
/// Phase 3 milestone: connect, browse, search and sort. Downloading EPUBs for
/// offline reading comes in the next step.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _settingsService = SettingsService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// True when the grid is scrolled far enough to offer a "back to top" jump.
  bool _showBackToTop = false;

  /// Null until the initial settings load finishes.
  OpdsSettings? _settings;
  List<Series>? _library;
  LibraryCache? _cache;
  bool _loading = false;
  String? _error;

  /// True when the displayed library came from the offline cache because the
  /// last sync couldn't reach the server.
  bool _offline = false;

  String _searchQuery = '';
  LibrarySort _sort = LibrarySort.titleAsc;
  ReadingStateFilter _readingState = ReadingStateFilter.any;
  LibraryFilters _filters = const LibraryFilters();

  /// Every saved reading entry — drives the per-series reading-state map
  /// used by the filter chips. Distinct from [_reading], which is the
  /// in-progress-only subset that powers the Continue Reading hero and
  /// shelf.
  List<ReadingEntry> _allReadingEntries = const [];

  /// Manual per-series reading status set by the user; overrides the status
  /// inferred from progress in the filter chips.
  Map<int, SeriesStatus> _seriesStatus = const {};

  /// Books that have been started but not finished, newest first.
  List<ReadingEntry> _reading = const [];

  /// "Recommended for you" — rebuilt whenever reading history or the library
  /// changes so it tracks current taste with no manual training step. We
  /// hold a wider pool (~40) and show one window of it; the shuffle button
  /// rotates through the rest.
  List<Recommendation> _recommendations = const [];

  /// Window offset into [_recommendations] for the displayed shelf.
  int _recommendOffset = 0;

  /// Number of recommendations on screen at one time.
  static const int _recommendWindow = 10;

  /// Download records, used to flag series with content newer than what's
  /// been downloaded. Null until first loaded.
  DownloadStore? _downloads;

  // ── library-wide "download everything" state ─────────────────────────────
  bool _bulkDownloading = false;
  bool _bulkCancel = false;
  int _bulkDone = 0;
  int _bulkTotal = 0;
  String? _bulkCurrent;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Repaint the Continue Reading shelf / recommendations when an iCloud
    // sync from another device merges new progress or feedback in.
    CloudSyncService().onRemoteMerge = () {
      if (mounted) _loadReading();
    };
    _initialize();
  }

  @override
  void dispose() {
    if (CloudSyncService().onRemoteMerge != null) {
      CloudSyncService().onRemoteMerge = null;
    }
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Shows the "back to top" button once the grid is scrolled a few screens
  /// down, and hides it again near the top.
  void _onScroll() {
    final show = _scrollController.hasClients &&
        _scrollController.offset > 1200;
    if (show != _showBackToTop) {
      setState(() => _showBackToTop = show);
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _initialize() async {
    final settings = await _settingsService.load();
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _cache = cache;
      // Show the cached library straight away — instant, and works offline.
      if (cache.series.isNotEmpty) _library = cache.series;
    });
    await _loadReading();
    await _loadDownloads();
    if (settings.isConfigured) {
      await _sync();
    }
  }

  /// Refreshes the "Continue reading" shelf and the recommendation engine
  /// from the saved reading positions and the current library.
  Future<void> _loadReading() async {
    final entries = await ReadingProgressStore().allEntries();
    final feedback = await RecommendationFeedbackStore().load();
    final status = await SeriesStatusStore().load();
    final inProgress = entries
        .where((e) => e.progress.isStarted && !e.progress.isFinished)
        .take(12)
        .toList();
    final recs = const RecommendationEngine(maxResults: 40).recommend(
      allSeries: _library ?? const <Series>[],
      readingEntries: entries,
      feedback: feedback,
    );
    if (!mounted) return;
    setState(() {
      _allReadingEntries = entries;
      _seriesStatus = status;
      _reading = inProgress;
      _recommendations = recs;
      _recommendOffset = 0;
    });
  }

  /// Records a "not interested" on a recommendation and refreshes the shelf
  /// without the dismissed pick.
  Future<void> _dismissRecommendation(Series series) async {
    await RecommendationFeedbackStore().recordDismiss(series.opdsId);
    await _loadReading();
  }

  /// Advances the visible recommendation window so "Show me different" gives
  /// you the next batch; wraps to the start when the pool runs out.
  void _rotateRecommendations() {
    if (_recommendations.length <= _recommendWindow) return;
    setState(() {
      _recommendOffset =
          (_recommendOffset + _recommendWindow) % _recommendations.length;
    });
  }

  /// Reloads the download manifest so the "update available" badges reflect
  /// the latest downloads.
  Future<void> _loadDownloads() async {
    final store = DownloadStore(LibraryStorage());
    await store.load();
    if (!mounted) return;
    setState(() => _downloads = store);
  }

  /// True when a series has content newer than what's been downloaded — its
  /// latest volume was re-compiled, or a newer volume exists.
  bool _seriesHasUpdate(Series series) {
    final downloads = _downloads;
    final seriesUpdated = series.updatedAt;
    if (downloads == null || seriesUpdated == null) return false;
    DateTime? newestDownloaded;
    for (final record in downloads.recordsForSeries(series.opdsId)) {
      final t = record.volumeUpdatedAt;
      if (t != null &&
          (newestDownloaded == null || t.isAfter(newestDownloaded))) {
        newestDownloaded = t;
      }
    }
    // Nothing downloaded — there's no "update", just an undownloaded series.
    if (newestDownloaded == null) return false;
    return seriesUpdated.isAfter(newestDownloaded);
  }

  Future<void> _sync() async {
    final settings = _settings;
    if (settings == null || !settings.isConfigured) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final library = await OpdsClient(settings).fetchLibrary();
      await _cache?.saveSeries(library);
      if (!mounted) return;
      setState(() {
        _library = library;
        _offline = false;
        _loading = false;
      });
      // Recompute "Continue reading" + recommendations against the fresh
      // series list (its updatedAt advances after a recompile, etc.).
      await _loadReading();
      // Background library upkeep: pull the next volume of in-progress
      // series, then (if enabled) delete finished volumes we've moved past.
      unawaited(_runLibraryMaintenance());
    } on OpdsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_library != null && _library!.isNotEmpty) {
          // We have a cached library — stay browsable offline rather than
          // showing a fatal error.
          _offline = true;
        } else {
          _error = e.message;
        }
      });
    }
  }

  /// Runs the background download + cleanup passes in order (download first
  /// so a freshly-pulled next volume is never a delete candidate).
  Future<void> _runLibraryMaintenance() async {
    await _autoDownloadNextVolumes();
    await _autoDeleteFinishedVolumes();
  }

  /// When enabled, removes the downloaded EPUB of any volume the reader has
  /// finished *and* moved past (a later volume in the same series has been
  /// started). Reading progress/history is left intact, so the volume still
  /// shows as finished and can be re-downloaded. Uses only local data — no
  /// network — keying volume order off the volume number.
  Future<void> _autoDeleteFinishedVolumes() async {
    if (!await _settingsService.autoDeleteFinished()) return;
    final settings = _settings;
    final downloads = _downloads;
    if (settings == null || downloads == null) return;

    final bySeries = <int, List<ReadingEntry>>{};
    for (final e in _allReadingEntries) {
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
    if (changed && mounted) await _loadDownloads();
  }

  /// Best-effort background fetch of the next volume for each in-progress
  /// series, so finishing one rolls straight into the next without a manual
  /// download. Bounded to one volume per series per sync, gated by the
  /// auto-download setting and (optionally) Wi-Fi.
  Future<void> _autoDownloadNextVolumes() async {
    final settings = _settings;
    final downloads = _downloads;
    if (settings == null || !settings.isConfigured || downloads == null) return;
    if (!await _settingsService.autoDownloadNext()) return;
    if (await _settingsService.autoDownloadWifiOnly() && !await _onWifi()) {
      return;
    }

    // Most-recently-read entry per started series (so the just-finished
    // volume's successor is the one we pull).
    final perSeries = <int, ReadingEntry>{};
    for (final e in _allReadingEntries) {
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
        await _cache?.saveVolumes(entry.volume.seriesOpdsId, fetched);
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
    if (pulled && mounted) await _loadDownloads();
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsScreen(initial: _settings ?? OpdsSettings.empty),
      ),
    );
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() => _settings = settings);
    if (settings.isConfigured) await _sync();
  }

  /// Per-series reading state, derived from saved progress entries. A series
  /// counts as "in progress" if any of its volumes has been started and not
  /// finished, and "finished" if every started volume is finished.
  ({Set<int> inProgress, Set<int> finished, Map<int, DateTime> lastReadAt})
      get _seriesReadingState {
    final inProgress = <int>{};
    final finished = <int>{};
    final lastReadAt = <int, DateTime>{};
    for (final e in _allReadingEntries) {
      final id = e.volume.seriesOpdsId;
      if (e.progress.isFinished) {
        finished.add(id);
      } else if (e.progress.isStarted) {
        inProgress.add(id);
      } else {
        inProgress.add(id); // saved entry but at the start = still "reading"
      }
      final updated = e.progress.updatedAt;
      if (updated != null) {
        final prev = lastReadAt[id];
        if (prev == null || updated.isAfter(prev)) {
          lastReadAt[id] = updated;
        }
      }
    }
    // A series with both an in-progress entry and a finished one is still
    // "in progress" — the user hasn't put it down.
    finished.removeAll(inProgress);
    return (
      inProgress: inProgress,
      finished: finished,
      lastReadAt: lastReadAt,
    );
  }

  /// The library after applying the active search, filter set, and sort.
  List<Series> get _visibleLibrary {
    final all = _library ?? const <Series>[];
    final query = _searchQuery.trim().toLowerCase();
    final downloads = _downloads;
    final readState = _seriesReadingState;
    final filtered = <Series>[];
    for (final series in all) {
      if (query.isNotEmpty) {
        if (!series.title.toLowerCase().contains(query) &&
            !series.author.toLowerCase().contains(query)) {
          continue;
        }
      }
      if (!_filters.matches(
        series,
        isDownloaded: downloads?.recordsForSeries(series.opdsId).isNotEmpty
            ?? false,
      )) {
        continue;
      }
      if (_readingState != ReadingStateFilter.any &&
          _resolvedState(series, readState) != _readingState) {
        continue;
      }
      filtered.add(series);
    }
    filtered.sort(_comparatorFor(_sort, readState.lastReadAt));
    return filtered;
  }

  /// Resolves a series to a single reading state for the filter chips. A
  /// manual [SeriesStatus] (set on the detail screen) wins; otherwise the
  /// state is inferred from reading progress.
  ReadingStateFilter _resolvedState(
    Series series,
    ({Set<int> inProgress, Set<int> finished, Map<int, DateTime> lastReadAt})
        readState,
  ) {
    switch (_seriesStatus[series.opdsId]) {
      case SeriesStatus.dropped:
        return ReadingStateFilter.dropped;
      case SeriesStatus.caughtUp:
        return ReadingStateFilter.finished;
      case SeriesStatus.reading:
        return ReadingStateFilter.inProgress;
      case SeriesStatus.none:
      case null:
        break;
    }
    if (readState.finished.contains(series.opdsId)) {
      return ReadingStateFilter.finished;
    }
    if (readState.inProgress.contains(series.opdsId)) {
      return ReadingStateFilter.inProgress;
    }
    return ReadingStateFilter.unread;
  }

  /// Every distinct genre tag present across the library — used to build the
  /// filter sheet's genre chip set.
  List<String> get _allGenres {
    final set = <String>{};
    for (final s in _library ?? const <Series>[]) {
      for (final g in s.genres) {
        final clean = g.trim();
        if (clean.isNotEmpty) set.add(clean);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Every distinct reading status the library uses.
  List<String> get _allStatuses {
    final set = <String>{};
    for (final s in _library ?? const <Series>[]) {
      final clean = s.readingStatus.trim().toLowerCase();
      if (clean.isNotEmpty) set.add(clean);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _openFilters() async {
    final next = await showModalBottomSheet<LibraryFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (_) => _LibraryFilterSheet(
        initial: _filters,
        allGenres: _allGenres,
        allStatuses: _allStatuses,
      ),
    );
    if (next == null) return;
    setState(() => _filters = next);
  }

  Comparator<Series> _comparatorFor(
    LibrarySort sort,
    Map<int, DateTime> lastReadAt,
  ) {
    int byTitle(Series a, Series b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return switch (sort) {
      LibrarySort.titleAsc => byTitle,
      LibrarySort.recentlyUpdated => (a, b) {
        final at = a.updatedAt;
        final bt = b.updatedAt;
        if (at == null && bt == null) return byTitle(a, b);
        if (at == null) return 1; // undated series sink to the bottom
        if (bt == null) return -1;
        return bt.compareTo(at); // newest first
      },
      LibrarySort.recentlyRead => (a, b) {
        final at = lastReadAt[a.opdsId];
        final bt = lastReadAt[b.opdsId];
        if (at == null && bt == null) return byTitle(a, b);
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      },
      LibrarySort.author => (a, b) {
        final c = a.author.toLowerCase().compareTo(b.author.toLowerCase());
        return c != 0 ? c : byTitle(a, b);
      },
      LibrarySort.readingStatus => (a, b) {
        final c = _statusRank(
          a.readingStatus,
        ).compareTo(_statusRank(b.readingStatus));
        return c != 0 ? c : byTitle(a, b);
      },
    };
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  Future<void> _openSeries(Series series) async {
    final settings = _settings;
    if (settings == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeriesDetailScreen(series: series, settings: settings),
      ),
    );
    await _loadReading();
    await _loadDownloads();
  }

  void _openStats() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StatsScreen()),
    );
  }

  void _openCollections() {
    final settings = _settings;
    if (settings == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollectionsScreen(settings: settings),
      ),
    );
  }

  void _openBackup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
    );
  }

  Future<void> _openImported() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ImportedBooksScreen()),
    );
    // An imported book may have gained reading progress.
    await _loadReading();
  }

  Future<void> _openStorage() async {
    final settings = _settings;
    if (settings == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StorageScreen(settings: settings),
      ),
    );
    // Downloads may have been deleted — refresh the update badges.
    await _loadDownloads();
  }

  /// Opens a randomly chosen series — quick discovery for big libraries.
  void _openRandom() {
    final library = _library;
    if (library == null || library.isEmpty) return;
    final pick = library[Random().nextInt(library.length)];
    _openSeries(pick);
  }

  /// Opens a volume straight into the reader (from a "Continue reading" card).
  Future<void> _openVolume(Volume volume) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(volume: volume)),
    );
    await _loadReading();
  }

  // ── library-wide download ────────────────────────────────────────────────

  /// True when a volume isn't downloaded, or the server has a newer build of
  /// it than what's on the device (a re-compiled volume).
  bool _needsDownload(Volume volume, DownloadRecord? record) {
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
  Future<void> _confirmDownloadEverything() async {
    final count = _library?.length ?? 0;
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
    final settings = _settings;
    final library = _library;
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
        await _cache?.saveVolumes(series.opdsId, volumes);
        for (final volume in volumes) {
          if (_needsDownload(volume, store.recordFor(volume))) {
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
    await _loadDownloads();
    await _loadReading();

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
    _snack(message);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canDownloadAll =
        (_library?.isNotEmpty ?? false) && !_offline && !_bulkDownloading;
    return Scaffold(
      floatingActionButton: _showBackToTop
          ? FloatingActionButton.small(
              tooltip: 'Back to top',
              onPressed: _scrollToTop,
              child: const Icon(Icons.arrow_upward),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _sync,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('Library'),
              actions: [
                if ((_library?.isNotEmpty ?? false))
                  IconButton(
                    icon: const Icon(Icons.shuffle),
                    tooltip: 'Open a random book',
                    onPressed: _openRandom,
                  ),
                if (canDownloadAll)
                  IconButton(
                    icon: const Icon(Icons.download_for_offline_outlined),
                    tooltip: 'Download whole library',
                    onPressed: _confirmDownloadEverything,
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More',
                  onSelected: (action) {
                    switch (action) {
                      case 'collections':
                        _openCollections();
                      case 'stats':
                        _openStats();
                      case 'storage':
                        _openStorage();
                      case 'imported':
                        _openImported();
                      case 'backup':
                        _openBackup();
                      case 'settings':
                        _openSettings();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'collections',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.collections_bookmark_outlined),
                        title: Text('Collections'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'stats',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.insights_outlined),
                        title: Text('Reading stats'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'storage',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.sd_storage_outlined),
                        title: Text('Manage storage'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'imported',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.upload_file_outlined),
                        title: Text('Imported books'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'backup',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.cloud_upload_outlined),
                        title: Text('Backup & restore'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.settings_outlined),
                        title: Text('Server settings'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            ..._buildContentSlivers(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContentSlivers() {
    // Initial load — full-screen spinner (nothing cached to show yet).
    if (_settings == null || (_loading && _library == null)) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    // We have a library to show (live or from the offline cache).
    final all = _library ?? const <Series>[];
    if (all.isNotEmpty) {
      final visible = _visibleLibrary;
      return [
        if (_offline) SliverToBoxAdapter(child: _buildOfflineBanner()),
        if (_bulkDownloading)
          SliverToBoxAdapter(child: _buildBulkBanner()),
        SliverToBoxAdapter(child: _buildControls(all.length, visible.length)),
        if (_reading.isNotEmpty && _searchQuery.trim().isEmpty)
          SliverToBoxAdapter(child: _buildContinueHero()),
        if (_reading.length > 1 && _searchQuery.trim().isEmpty)
          SliverToBoxAdapter(child: _buildContinueShelf()),
        if (_searchQuery.trim().isEmpty && _recentlyUpdated.isNotEmpty)
          SliverToBoxAdapter(child: _buildRecentShelf()),
        if (_recommendations.isNotEmpty && _searchQuery.trim().isEmpty)
          SliverToBoxAdapter(child: _buildRecommendedShelf()),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _MessageView(
              icon: Icons.search_off_outlined,
              title: 'No matches',
              message: 'No series match “$_searchQuery”.',
              actionLabel: 'Clear search',
              onAction: _clearSearch,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 0.52,
                crossAxisSpacing: 16,
                mainAxisSpacing: 20,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) => _SeriesCard(
                series: visible[index],
                imageHeaders: _settings!.isConfigured
                    ? OpdsClient(_settings!).authHeaders
                    : const {},
                updateAvailable: _seriesHasUpdate(visible[index]),
                onTap: () => _openSeries(visible[index]),
              ),
            ),
          ),
      ];
    }

    // Nothing to show.
    if (!_settings!.isConfigured) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _MessageView(
            icon: Icons.cloud_off_outlined,
            title: 'Not connected',
            message:
                'Connect Umbra Reader to your Novel Grabber library to see '
                'your books here.',
            actionLabel: 'Connect',
            onAction: _openSettings,
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _MessageView(
            icon: Icons.error_outline,
            title: 'Sync failed',
            message: _error!,
            actionLabel: 'Retry',
            onAction: _sync,
          ),
        ),
      ];
    }
    return [
      SliverFillRemaining(
        hasScrollBody: false,
        child: _MessageView(
          icon: Icons.library_books_outlined,
          title: 'No books found',
          message:
              'The library is empty, or no series have a compiled EPUB yet.',
          actionLabel: 'Refresh',
          onAction: _sync,
        ),
      ),
    ];
  }

  /// A slim banner shown above the grid when browsing the offline cache.
  Widget _buildOfflineBanner() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — showing your saved library. Downloaded books can '
              'still be read.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A big tappable "Resume reading" banner for the single most-recently-read
  /// volume — saves a scroll into the horizontal shelf when there's only one
  /// thing you're likely to pick back up.
  ///
  /// Layout note: the outer SizedBox pins the hero to a fixed height so the
  /// inner Row never has to compute intrinsic heights. An earlier version
  /// used Row(crossAxisAlignment.stretch) + Expanded(Column with Spacer),
  /// which threw during the CustomScrollView's intrinsic-sizing pass and
  /// silently nuked everything below it in the sliver list — so be careful
  /// before reintroducing Spacer/Expanded inside this widget.
  Widget _buildContinueHero() {
    final theme = Theme.of(context);
    final entry = _reading.first;
    final seriesById = {
      for (final s in _library ?? const <Series>[]) s.opdsId: s,
    };
    final series = seriesById[entry.volume.seriesOpdsId];
    final headers = (_settings?.isConfigured ?? false)
        ? OpdsClient(_settings!).authHeaders
        : const <String, String>{};
    final title = series?.title ?? entry.volume.title;
    final volumeLabel = entry.volume.title != title ? entry.volume.title : null;
    final progress = entry.progress;
    final chapterLabel = progress.chapterCount > 0
        ? 'Chapter ${progress.chapterIndex + 1} of ${progress.chapterCount}'
        : 'Chapter ${progress.chapterIndex + 1}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openVolume(entry.volume),
          child: SizedBox(
            height: 148,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    height: 124,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: series != null
                          ? _CoverImage(series: series, headers: headers)
                          : _TitleCover(title: entry.volume.title),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Continue reading',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                            if (volumeLabel != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                volumeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress.fraction,
                                minHeight: 4,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    chapterLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.play_arrow_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueShelf() {
    final theme = Theme.of(context);
    final seriesById = {
      for (final s in _library ?? const <Series>[]) s.opdsId: s,
    };
    final headers = (_settings?.isConfigured ?? false)
        ? OpdsClient(_settings!).authHeaders
        : const <String, String>{};
    // The hero already covers entry [0]; the shelf shows the rest.
    final rest = _reading.skip(1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Also in progress',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: rest.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final entry = rest[index];
              return _ContinueCard(
                entry: entry,
                series: seriesById[entry.volume.seriesOpdsId],
                imageHeaders: headers,
                onTap: () => _openVolume(entry.volume),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// The 10 most-recently-updated series in the library (most-recent first).
  /// Used as the "Recently updated" shelf — Novel Grabber bumps a series'
  /// updatedAt every time it recompiles a volume, so this surfaces what's
  /// genuinely new.
  List<Series> get _recentlyUpdated {
    final all = _library ?? const <Series>[];
    if (all.length < 3) return const [];
    final dated = all.where((s) => s.updatedAt != null).toList()
      ..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
    if (dated.length < 3) return const [];
    return dated.take(10).toList();
  }

  /// Horizontal shelf of the freshest series in the library.
  Widget _buildRecentShelf() {
    final theme = Theme.of(context);
    final headers = (_settings?.isConfigured ?? false)
        ? OpdsClient(_settings!).authHeaders
        : const <String, String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Recently updated',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 226,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentlyUpdated.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final series = _recentlyUpdated[index];
              return _RecommendCard(
                series: series,
                imageHeaders: headers,
                onTap: () => _openSeries(series),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Horizontal shelf of "you might like" suggestions from the engine.
  Widget _buildRecommendedShelf() {
    final theme = Theme.of(context);
    final headers = (_settings?.isConfigured ?? false)
        ? OpdsClient(_settings!).authHeaders
        : const <String, String>{};
    // Slice the pool into a visible window; wrap past the end so the shuffle
    // button can cycle.
    final pool = _recommendations;
    final List<Recommendation> visible;
    if (pool.length <= _recommendWindow) {
      visible = pool;
    } else {
      final start = _recommendOffset % pool.length;
      final take = pool.skip(start).take(_recommendWindow).toList();
      if (take.length < _recommendWindow) {
        take.addAll(pool.take(_recommendWindow - take.length));
      }
      visible = take;
    }
    final canRotate = pool.length > _recommendWindow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recommended for you',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canRotate)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Show me different',
                  visualDensity: VisualDensity.compact,
                  onPressed: _rotateRecommendations,
                ),
            ],
          ),
        ),
        SizedBox(
          height: 226,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final series = visible[index].series;
              return _RecommendCard(
                series: series,
                imageHeaders: headers,
                onTap: () => _openSeries(series),
                onDismiss: () => _dismissRecommendation(series),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Progress banner shown while the whole library is downloading.
  Widget _buildBulkBanner() {
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

  /// The search field, sort menu, and result-count line.
  Widget _buildControls(int total, int visible) {
    final theme = Theme.of(context);
    final searching = _searchQuery.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'Search by title or author',
                  leading: const Icon(Icons.search),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12),
                  ),
                  trailing: [
                    if (searching)
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear',
                        onPressed: _clearSearch,
                      ),
                  ],
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Badge(
                  isLabelVisible: !_filters.isEmpty,
                  smallSize: 8,
                  child: const Icon(Icons.filter_list),
                ),
                tooltip: 'Filter library',
                onPressed: _openFilters,
              ),
              PopupMenuButton<LibrarySort>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort',
                initialValue: _sort,
                onSelected: (value) => setState(() => _sort = value),
                itemBuilder: (context) => [
                  for (final option in LibrarySort.values)
                    PopupMenuItem<LibrarySort>(
                      value: option,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: option == _sort
                                ? const Icon(Icons.check, size: 18)
                                : null,
                          ),
                          Text(option.label),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Quick reading-state chips: a tap-friendly way to narrow the grid
          // down to what's actually being read (or the unread backlog) without
          // diving into the full filter sheet.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final state in ReadingStateFilter.values) ...[
                  ChoiceChip(
                    label: Text(state.label),
                    selected: _readingState == state,
                    onSelected: (_) =>
                        setState(() => _readingState = state),
                  ),
                  if (state != ReadingStateFilter.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            visible == total
                ? '$total series  ·  ${_sort.label}'
                : '$visible of $total series  ·  ${_sort.label}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single cover in the library grid: cover art, title, author.
class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.series,
    required this.imageHeaders,
    required this.updateAvailable,
    required this.onTap,
  });

  final Series series;
  final Map<String, String> imageHeaders;

  /// True when the series has content newer than what's been downloaded.
  final bool updateAvailable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CoverImage(series: series, headers: imageHeaders),
                    if (series.hasMultipleVolumes)
                      const Positioned(top: 6, right: 6, child: _VolumeBadge()),
                    if (updateAvailable)
                      const Positioned(
                        top: 6,
                        left: 6,
                        child: _UpdateBadge(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            series.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            series.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// A card on the "Continue reading" shelf: cover, title, and progress.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.entry,
    required this.series,
    required this.imageHeaders,
    required this.onTap,
  });

  final ReadingEntry entry;

  /// The owning series, if it's in the loaded library — for the cover art.
  final Series? series;
  final Map<String, String> imageHeaders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = entry.progress;
    final title = series?.title ?? entry.volume.title;
    final chapterLabel = progress.chapterCount > 0
        ? 'Chapter ${progress.chapterIndex + 1} of ${progress.chapterCount}'
        : 'Chapter ${progress.chapterIndex + 1}';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 124,
              height: 165,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: series != null
                      ? _CoverImage(series: series!, headers: imageHeaders)
                      : _TitleCover(title: entry.volume.title),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              chapterLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card showing a series cover, title and author. Used by both the
/// "Recommended for you" and "Recently updated" shelves; the ✕ dismiss
/// button only appears when [onDismiss] is supplied.
class _RecommendCard extends StatelessWidget {
  const _RecommendCard({
    required this.series,
    required this.imageHeaders,
    required this.onTap,
    this.onDismiss,
  });

  final Series series;
  final Map<String, String> imageHeaders;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 124,
              height: 165,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedCover(
                        seriesId: series.opdsId,
                        coverUrl: series.coverUrl,
                        headers: imageHeaders,
                        fallback: _TitleCover(title: series.title),
                      ),
                      if (onDismiss != null)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: _DismissChip(onPressed: onDismiss!),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: Text(
                series.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              series.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled gradient panel used when no cover art is available.
class _TitleCover extends StatelessWidget {
  const _TitleCover({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cover art for a series — the network image, or a titled gradient fallback
/// when there is no cover or it fails to load.
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.series, required this.headers});

  final Series series;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return CachedCover(
      seriesId: series.opdsId,
      coverUrl: series.coverUrl,
      headers: headers,
      fallback: _fallback(context),
    );
  }

  /// A gradient panel showing the title — looks intentional, not broken.
  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Center(
          child: Text(
            series.title,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small corner badge marking a series that has more than one volume.
class _VolumeBadge extends StatelessWidget {
  const _VolumeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.collections_bookmark,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}

/// A small "not interested" ✕ button overlaid on a recommendation card. Taps
/// dismiss the recommendation and feed a soft-negative back to the engine.
class _DismissChip extends StatelessWidget {
  const _DismissChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

/// Corner badge marking a series with content newer than what's downloaded.
class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.update, size: 15, color: Colors.white),
    );
  }
}

/// A centered icon + message + action button, used for the empty / error /
/// not-connected / no-matches states.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// The active set of library filters, applied alongside search + sort.
class LibraryFilters {
  const LibraryFilters({
    this.genres = const {},
    this.statuses = const {},
    this.downloaded,
    this.multiVolume,
  });

  /// Genres the user wants to see; empty = no genre filter.
  final Set<String> genres;

  /// Reading statuses the user wants to see; empty = no status filter.
  final Set<String> statuses;

  /// null = either, true = only downloaded series, false = only not-downloaded.
  final bool? downloaded;

  /// null = either, true = only multi-volume, false = only single-volume.
  final bool? multiVolume;

  bool get isEmpty =>
      genres.isEmpty &&
      statuses.isEmpty &&
      downloaded == null &&
      multiVolume == null;

  /// True when [series] satisfies every active filter clause.
  bool matches(Series series, {required bool isDownloaded}) {
    if (genres.isNotEmpty) {
      final seriesGenres = {
        for (final g in series.genres) g.trim(),
      };
      if (!seriesGenres.any(genres.contains)) return false;
    }
    if (statuses.isNotEmpty &&
        !statuses.contains(series.readingStatus.trim().toLowerCase())) {
      return false;
    }
    if (downloaded != null && isDownloaded != downloaded) return false;
    if (multiVolume != null && series.hasMultipleVolumes != multiVolume) {
      return false;
    }
    return true;
  }

  LibraryFilters copyWith({
    Set<String>? genres,
    Set<String>? statuses,
    Object? downloaded = _unset,
    Object? multiVolume = _unset,
  }) {
    return LibraryFilters(
      genres: genres ?? this.genres,
      statuses: statuses ?? this.statuses,
      downloaded: identical(downloaded, _unset)
          ? this.downloaded
          : downloaded as bool?,
      multiVolume: identical(multiVolume, _unset)
          ? this.multiVolume
          : multiVolume as bool?,
    );
  }

  static const Object _unset = Object();
}

/// Bottom-sheet UI for picking [LibraryFilters]. Returns the new filter set
/// when the user taps Apply, null when they cancel.
class _LibraryFilterSheet extends StatefulWidget {
  const _LibraryFilterSheet({
    required this.initial,
    required this.allGenres,
    required this.allStatuses,
  });

  final LibraryFilters initial;
  final List<String> allGenres;
  final List<String> allStatuses;

  @override
  State<_LibraryFilterSheet> createState() => _LibraryFilterSheetState();
}

class _LibraryFilterSheetState extends State<_LibraryFilterSheet> {
  late LibraryFilters _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter library',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _draft.isEmpty
                      ? null
                      : () => setState(() => _draft = const LibraryFilters()),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.allGenres.isNotEmpty) ...[
              _sectionLabel(theme, 'Genre'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final genre in widget.allGenres)
                    FilterChip(
                      label: Text(genre),
                      selected: _draft.genres.contains(genre),
                      onSelected: (selected) {
                        final next = {..._draft.genres};
                        if (selected) {
                          next.add(genre);
                        } else {
                          next.remove(genre);
                        }
                        setState(
                          () => _draft = _draft.copyWith(genres: next),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (widget.allStatuses.isNotEmpty) ...[
              _sectionLabel(theme, 'Reading status'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in widget.allStatuses)
                    FilterChip(
                      label: Text(_titleCase(status)),
                      selected: _draft.statuses.contains(status),
                      onSelected: (selected) {
                        final next = {..._draft.statuses};
                        if (selected) {
                          next.add(status);
                        } else {
                          next.remove(status);
                        }
                        setState(
                          () => _draft = _draft.copyWith(statuses: next),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _sectionLabel(theme, 'Downloaded'),
            _triStateRow(
              value: _draft.downloaded,
              labels: const ['Any', 'Downloaded', 'Not yet'],
              onChanged: (v) => setState(
                () => _draft = _draft.copyWith(downloaded: v),
              ),
            ),
            const SizedBox(height: 16),
            _sectionLabel(theme, 'Volumes'),
            _triStateRow(
              value: _draft.multiVolume,
              labels: const ['Any', 'Multi-volume', 'Single volume'],
              onChanged: (v) => setState(
                () => _draft = _draft.copyWith(multiVolume: v),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// A three-state segmented control: any / true / false.
  Widget _triStateRow({
    required bool? value,
    required List<String> labels,
    required ValueChanged<bool?> onChanged,
  }) {
    assert(labels.length == 3);
    return SegmentedButton<int>(
      segments: [
        ButtonSegment(value: 0, label: Text(labels[0])),
        ButtonSegment(value: 1, label: Text(labels[1])),
        ButtonSegment(value: 2, label: Text(labels[2])),
      ],
      selected: {value == null ? 0 : (value ? 1 : 2)},
      onSelectionChanged: (selection) {
        final v = selection.first;
        onChanged(v == 0 ? null : v == 1);
      },
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
