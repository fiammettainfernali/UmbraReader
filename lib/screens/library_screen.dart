import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/series.dart';
import '../models/volume.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/opds_client.dart';
import '../services/bookmark_store.dart';
import '../services/collection_store.dart';
import '../services/reading_progress_store.dart';
import '../services/rec_outcome_store.dart';
import '../services/rec_weight_learner.dart';
import '../services/recommendation_engine.dart';
import '../services/cloud_sync_service.dart';
import '../services/recommendation_feedback_store.dart';
import '../services/series_status_store.dart';
import '../services/reading_activity_store.dart';
import '../services/settings_service.dart';
import '../widgets/add_to_collection_sheet.dart';
import '../widgets/cached_cover.dart';
import '../widgets/section_header.dart';
import 'backup_screen.dart';
import 'collections_screen.dart';
import 'glossary_screen.dart';
import 'imported_books_screen.dart';
import 'library_downloads.dart';
import 'library_search_screen.dart';
import '../widgets/pro_sheet.dart';
import 'manage_screen.dart';
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

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver, LibraryDownloads {
  final _settingsService = SettingsService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// True when the grid is scrolled far enough to offer a "back to top" jump.
  bool _showBackToTop = false;

  /// An iCloud merge landed while this screen was on show, and its effect on
  /// the visible order is being held back until the user causes a reload.
  /// See the note in [initState].
  bool _remoteMergePending = false;

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

  /// Reading-time activity + daily goal for the home streak chip.
  ReadingActivity _activity = ReadingActivity.empty;
  int _dailyGoalMinutes = 0;

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

  /// Throttle for the background library-maintenance pass (auto-download next
  /// volume + auto-delete). It must NOT run on every sync/pull-to-refresh —
  /// doing so stacked sequential per-series network fetches and downloads
  /// that saturated the connection and slowed manual checking/downloading.
  // ── LibraryDownloads proxies ────────────────────────────────────────────
  @override
  OpdsSettings? get opdsSettings => _settings;
  @override
  SettingsService get settingsService => _settingsService;
  @override
  List<Series>? get librarySeries => _library;
  @override
  LibraryCache? get libraryCache => _cache;
  @override
  DownloadStore? get downloadStore => _downloads;
  @override
  List<ReadingEntry> get readingEntries => _allReadingEntries;
  @override
  Future<void> reloadDownloads() => _loadDownloads();
  @override
  Future<void> reloadReading() => _loadReading();
  @override
  void showSnack(String message) => _snack(message);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    // An iCloud sync from another device has merged new progress/feedback
    // into the stores. Deliberately do NOT repaint here: a shelf that
    // reorders under a reader's finger — because a phone across the room
    // synced — is the exact thing PREDICTABILITY.md forbids. The merged data
    // is already in the stores, so opening a book still uses the freshest
    // position; only the visible ordering waits for a moment the user caused
    // (returning from a book, pull-to-refresh, or coming back to the app).
    CloudSyncService().onRemoteMerge = () {
      if (mounted) _remoteMergePending = true;
    };
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the app is a user-caused boundary, so a merge that landed
    // while they were away can safely surface now.
    if (state == AppLifecycleState.resumed && _remoteMergePending) {
      _loadReading();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final show =
        _scrollController.hasClients && _scrollController.offset > 1200;
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
    // Whatever a remote merge was holding back is about to be shown.
    _remoteMergePending = false;
    // Nine independent store reads, awaited together rather than one after
    // another. This runs on every library load AND every return from a book,
    // so nine stacked round-trips (each a prefs check plus a query, and the
    // activity ledger folds in every other device's) is worth not paying in
    // series. Drift still serialises its own queries on one connection, so
    // the win is modest rather than 9x — but it costs nothing to not queue.
    // The stores' one-time migration guards are concurrency-safe: the
    // `_migration ??=` assignment runs synchronously after its await, so the
    // two ReadingProgressStore calls share one migration rather than racing.
    final (
      entries,
      feedback,
      status,
      hidden,
      activity,
      dailyGoal,
      highlights,
      collections,
      outcomes,
    ) = await (
      ReadingProgressStore().allEntries(),
      RecommendationFeedbackStore().load(),
      SeriesStatusStore().load(),
      ReadingProgressStore().hiddenFromContinue(),
      ReadingActivityStore().load(),
      SettingsService().readDailyMinuteGoal(),
      // Everything the app knows about HOW the user reads, folded into the
      // engine below: highlight density, collection membership, and
      // shown-and-ignored outcomes.
      BookmarkStore().countBySeries(),
      CollectionStore().list(),
      RecOutcomeStore().load(),
    ).wait;
    // The Continue shelf excludes volumes the user hid; the filter chips
    // (which use _allReadingEntries) still count them as in-progress.
    final inProgress = entries
        .where(
          (e) =>
              e.progress.isStarted &&
              !e.progress.isFinished &&
              !hidden.contains('${e.volume.seriesOpdsId}/${e.volume.fileName}'),
        )
        .take(12)
        .toList();
    final signals = RecSignals(
      volumeSeconds: activity.perVolumeSeconds,
      volumeWords: activity.perVolumeWords,
      highlightsPerSeries: highlights,
      hiddenVolumeKeys: hidden,
      collectionSeriesIds: {
        for (final c in collections) ...c.seriesIds,
      },
      outcomes: outcomes,
      // The user's own status picker, translated to engine vocabulary —
      // "caught up" on a series listened to entirely outside the app is a
      // full like even with zero in-app reading entries.
      statusOverrides: {
        for (final e in status.entries)
          if (e.value == SeriesStatus.caughtUp)
            e.key: 'completed'
          else if (e.value == SeriesStatus.dropped)
            e.key: 'dropped'
          else if (e.value == SeriesStatus.reading)
            e.key: 'ongoing',
      },
    );
    // Learn this user's feature-group weights from recommendation outcomes
    // (full refit from the prior each time — deterministic and cheap), then
    // rank under them. Zero outcomes → the hand-tuned prior, exactly.
    const recEngine = RecommendationEngine(maxResults: 40);
    final examples = buildRecTrainingExamples(
      engine: recEngine,
      allSeries: _library ?? const <Series>[],
      readingEntries: entries,
      feedback: feedback,
      signals: signals,
    );
    final learned = const RecWeightLearner().fit(examples);
    await RecWeightsStore().save(learned);
    final recs = recEngine.recommend(
      allSeries: _library ?? const <Series>[],
      readingEntries: entries,
      feedback: feedback,
      signals: signals,
      weights: learned,
      explore: true,
    );
    if (!mounted) return;
    setState(() {
      _allReadingEntries = entries;
      _activity = activity;
      _dailyGoalMinutes = dailyGoal;
      _seriesStatus = status;
      _reading = inProgress;
      _recommendations = recs;
      _recommendOffset = 0;
    });
    _recordShelfImpressions();
  }

  /// Records a "not interested" on a recommendation and refreshes the shelf
  /// without the dismissed pick.
  Future<void> _dismissRecommendation(Series series) async {
    await RecommendationFeedbackStore().recordDismiss(series.opdsId);
    await _loadReading();
  }

  /// Records a 👍 "more like this" and refreshes so the shelf leans into it.
  Future<void> _likeRecommendation(Series series) async {
    final messenger = ScaffoldMessenger.of(context);
    await RecommendationFeedbackStore().recordLike(series.opdsId);
    messenger.showSnackBar(
      SnackBar(content: Text('More picks like “${series.title}” coming up.')),
    );
    await _loadReading();
  }

  /// Records a "not now" (30-day snooze) and refreshes the shelf.
  Future<void> _snoozeRecommendation(Series series) async {
    final messenger = ScaffoldMessenger.of(context);
    await RecommendationFeedbackStore().recordSnooze(series.opdsId);
    messenger.showSnackBar(
      SnackBar(content: Text('“${series.title}” hidden for 30 days.')),
    );
    await _loadReading();
  }

  /// Long-press options for a recommendation card: the full feedback set.
  Future<void> _showRecommendationOptions(Series series) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.thumb_up_outlined),
              title: const Text('More like this'),
              onTap: () => Navigator.of(sheetCtx).pop('like'),
            ),
            ListTile(
              leading: const Icon(Icons.snooze),
              title: const Text('Not now'),
              subtitle: const Text('Hide for 30 days'),
              onTap: () => Navigator.of(sheetCtx).pop('snooze'),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Not interested'),
              onTap: () => Navigator.of(sheetCtx).pop('dismiss'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'like':
        await _likeRecommendation(series);
      case 'snooze':
        await _snoozeRecommendation(series);
      case 'dismiss':
        await _dismissRecommendation(series);
    }
  }

  /// The recommendations currently visible in the shelf window. The
  /// exploration wildcard (if any) is pinned as the last visible card in
  /// every window so it always gets its one slot.
  List<Recommendation> _visibleRecommendations() {
    final wildcard = _recommendations
        .where((r) => r.isWildcard)
        .toList();
    final pool = [
      for (final r in _recommendations)
        if (!r.isWildcard) r,
    ];
    final List<Recommendation> window;
    if (pool.length <= _recommendWindow) {
      window = pool;
    } else {
      final start = _recommendOffset % pool.length;
      final take = pool.skip(start).take(_recommendWindow).toList();
      if (take.length < _recommendWindow) {
        take.addAll(pool.take(_recommendWindow - take.length));
      }
      window = take;
    }
    return [...window, ...wildcard];
  }

  /// Counts an impression (once per series per day) for the recs on screen —
  /// the outcome data that lets repeatedly-ignored picks fade and, later,
  /// trains the per-user weights.
  void _recordShelfImpressions() {
    final visible = _visibleRecommendations();
    if (visible.isEmpty) return;
    RecOutcomeStore().recordImpressions([
      for (final rec in visible) rec.series.opdsId,
    ]);
  }

  /// Opens a series from a recommendation card, recording the tap outcome.
  void _openRecommended(Series series) {
    RecOutcomeStore().recordTap(series.opdsId);
    _openSeries(series);
  }

  /// Advances the visible recommendation window so "Show me different" gives
  /// you the next batch; wraps to the start when the pool runs out.
  void _rotateRecommendations() {
    if (_recommendations.length <= _recommendWindow) return;
    setState(() {
      _recommendOffset =
          (_recommendOffset + _recommendWindow) % _recommendations.length;
    });
    _recordShelfImpressions();
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
      unawaited(runLibraryMaintenance());
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
  ///
  /// Heavily throttled: it skips if a pass is already running or if one ran
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
    return (inProgress: inProgress, finished: finished, lastReadAt: lastReadAt);
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
        isDownloaded:
            downloads?.recordsForSeries(series.opdsId).isNotEmpty ?? false,
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

  /// Full-text search across every downloaded book. (Pro)
  Future<void> _openLibrarySearch() async {
    if (!await requirePro(context, feature: 'Search inside every book')) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LibrarySearchScreen()),
    );
    // A search hit may have been read — refresh positions.
    await _loadReading();
  }

  Future<void> _openStats() async {
    if (!await requirePro(
      context,
      feature: 'Reading stats, goals & streaks',
    )) {
      return;
    }
    if (!mounted) return;
    _openStatsUnlocked();
  }

  void _openStatsUnlocked() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const StatsScreen()));
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const BackupScreen()));
  }

  Future<void> _openImported() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ImportedBooksScreen()),
    );
    // An imported book may have gained reading progress.
    await _loadReading();
  }

  void _openManage() {
    final settings = _settings;
    if (settings == null || !settings.isConfigured) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ManageScreen(settings: settings)),
    );
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

  /// Long-press menu for a series cover in the grid: open, add to a
  /// collection, jump to the glossary, or set/clear the manual status.
  Future<void> _seriesCardMenu(Series series) async {
    final settings = _settings;
    final current = _seriesStatus[series.opdsId] ?? SeriesStatus.none;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                series.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(series.author),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Open'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            if (settings != null)
              ListTile(
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: const Text('Add to collection'),
                onTap: () => Navigator.pop(ctx, 'collection'),
              ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Character glossary'),
              onTap: () => Navigator.pop(ctx, 'glossary'),
            ),
            const Divider(height: 1),
            for (final s in const [
              SeriesStatus.reading,
              SeriesStatus.caughtUp,
              SeriesStatus.dropped,
            ])
              ListTile(
                leading: Icon(current == s ? Icons.check : Icons.label_outline),
                title: Text('Mark: ${s.label}'),
                onTap: () => Navigator.pop(ctx, 'status:${s.name}'),
              ),
            if (current != SeriesStatus.none)
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Clear status'),
                onTap: () => Navigator.pop(ctx, 'status:none'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'open') {
      _openSeries(series);
    } else if (action == 'glossary') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              GlossaryScreen(seriesId: series.opdsId, title: series.title),
        ),
      );
    } else if (action == 'collection' && settings != null) {
      if (!await requirePro(context, feature: 'Collections')) return;
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        builder: (_) => AddToCollectionSheet(
          seriesId: series.opdsId,
          seriesTitle: series.title,
        ),
      );
    } else if (action.startsWith('status:')) {
      final name = action.substring('status:'.length);
      final status = name == 'none'
          ? SeriesStatus.none
          : SeriesStatus.fromName(name);
      await SeriesStatusStore().setStatus(series.opdsId, status);
      await _loadReading();
    }
  }

  /// Long-press menu for a Continue Reading entry (hero or shelf card).
  Future<void> _continueCardMenu(ReadingEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                entry.volume.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Resume reading'),
              onTap: () => Navigator.pop(ctx, 'resume'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Open series'),
              onTap: () => Navigator.pop(ctx, 'series'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Mark as finished'),
              subtitle: const Text(
                'Leaves these shelves until new chapters arrive',
              ),
              onTap: () => Navigator.pop(ctx, 'finished'),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Remove from Currently Reading'),
              subtitle: const Text(
                'Keeps your place; reappears when you read it again',
              ),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'resume') {
      _openVolume(entry.volume);
    } else if (action == 'series') {
      final series = _seriesById(entry.volume.seriesOpdsId);
      if (series != null) {
        _openSeries(series);
      } else {
        _snack('That series isn\'t in the library list right now.');
      }
    } else if (action == 'finished') {
      await ReadingProgressStore().markFinished(entry.volume);
      await _loadReading();
    } else if (action == 'remove') {
      await ReadingProgressStore().hideFromContinue(entry.volume);
      await _loadReading();
    }
  }

  /// Finds a loaded series by its OPDS id, or null if not in the library list.
  Series? _seriesById(int opdsId) {
    for (final s in _library ?? const <Series>[]) {
      if (s.opdsId == opdsId) return s;
    }
    return null;
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
        (_library?.isNotEmpty ?? false) && !_offline && !bulkDownloading;
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
            SliverAppBar(
              // Compact + pinned instead of the big collapsing header: trims
              // the cluttered top space and, importantly, lets pull-to-refresh
              // trigger from anywhere at the top (the large app bar used to
              // swallow the downward drag to re-expand itself first).
              pinned: true,
              titleSpacing: 16,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.nightlight_round,
                    size: 20,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: 10),
                  const Text('Library'),
                ],
              ),
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
                    onPressed: confirmDownloadEverything,
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
                      case 'manage':
                        _openManage();
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
                      value: 'manage',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.cloud_sync_outlined),
                        title: Text('Manage server'),
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
      // Shelves are the "home" view: only show them on the default, unfiltered
      // list. Once the user narrows to a reading-state chip (Reading / Unread /
      // Finished / Dropped) or searches, drop straight to the matching grid —
      // recently-updated/recommended aren't relevant to a filtered browse.
      final showShelves =
          _searchQuery.trim().isEmpty &&
          _readingState == ReadingStateFilter.any;
      return [
        if (_offline) SliverToBoxAdapter(child: _buildOfflineBanner()),
        if (bulkDownloading) SliverToBoxAdapter(child: buildBulkBanner()),
        SliverToBoxAdapter(child: _buildControls(all.length, visible.length)),
        if (showShelves &&
            (_activity.currentStreak() > 0 || _dailyGoalMinutes > 0))
          SliverToBoxAdapter(child: _buildStreakChip()),
        if (showShelves && _reading.isNotEmpty)
          SliverToBoxAdapter(child: _buildContinueHero()),
        if (showShelves && _reading.length > 1)
          SliverToBoxAdapter(child: _buildContinueShelf()),
        if (showShelves && _recentlyUpdated.isNotEmpty)
          SliverToBoxAdapter(child: _buildRecentShelf()),
        if (showShelves && _recommendations.isNotEmpty)
          SliverToBoxAdapter(child: _buildRecommendedShelf()),
        // Distinct header so the full grid doesn't blend into the shelf above.
        if (showShelves && visible.isNotEmpty)
          SliverToBoxAdapter(child: _sectionHeader('All books')),
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
                onLongPress: () => _seriesCardMenu(visible[index]),
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
            icon: Icons.auto_stories_outlined,
            title: 'Add your first books',
            message:
                'Connect Umbra Reader to your library server, or import '
                'EPUB files straight from Files / iCloud Drive — no server '
                'needed.',
            actionLabel: 'Connect a server',
            onAction: _openSettings,
            secondaryLabel: 'Import EPUB files',
            onSecondary: _openImported,
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

  /// A compact, tappable streak + daily-goal line under the controls —
  /// the retention nudge lives where the user lands, not buried in Stats.
  Widget _buildStreakChip() {
    final theme = Theme.of(context);
    final streak = _activity.currentStreak();
    final todayMinutes = _activity.todaySeconds() ~/ 60;
    final goal = _dailyGoalMinutes;
    final goalMet = goal > 0 && todayMinutes >= goal;

    final restDay = _activity.streakUsedGrace();
    final parts = <String>[
      if (streak > 0) '$streak-day streak${restDay ? ' (rest day used)' : ''}',
      if (goal > 0)
        goalMet
            ? 'goal met — $todayMinutes min today'
            : '$todayMinutes of $goal min today',
    ];
    final label = parts.join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        button: true,
        label: 'Reading stats: $label',
        excludeSemantics: true,
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _openStats,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    streak > 0
                        ? Icons.local_fire_department
                        : Icons.timer_outlined,
                    size: 18,
                    color: goalMet || streak > 0
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  if (goal > 0) ...[
                    SizedBox(
                      width: 44,
                      child: LinearProgressIndicator(
                        value: (todayMinutes / goal).clamp(0.0, 1.0),
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
  Widget _sectionHeader(String title) => SectionHeader(title);

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
          onLongPress: () => _continueCardMenu(entry),
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
        _sectionHeader('Also in progress'),
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
                onLongPress: () => _continueCardMenu(entry),
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
    final headers = (_settings?.isConfigured ?? false)
        ? OpdsClient(_settings!).authHeaders
        : const <String, String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Recently updated'),
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
    final headers = (_settings?.isConfigured ?? false)
        ? OpdsClient(_settings!).authHeaders
        : const <String, String>{};
    // Slice the pool into a visible window; wrap past the end so the shuffle
    // button can cycle.
    final visible = _visibleRecommendations();
    final canRotate = _recommendations.length > _recommendWindow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Recommended for you',
          trailing: canRotate
              ? IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Show me different',
                  visualDensity: VisualDensity.compact,
                  onPressed: _rotateRecommendations,
                )
              : null,
        ),
        SizedBox(
          height: 244,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final rec = visible[index];
              final series = rec.series;
              return _RecommendCard(
                series: series,
                imageHeaders: headers,
                reason: rec.reason,
                isWildcard: rec.isWildcard,
                onTap: () => _openRecommended(series),
                onDismiss: () => _dismissRecommendation(series),
                onLike: () => _likeRecommendation(series),
                onLongPress: () => _showRecommendationOptions(series),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Progress banner shown while the whole library is downloading.
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
                icon: const Icon(Icons.manage_search),
                tooltip: 'Search inside books',
                onPressed: _openLibrarySearch,
              ),
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
                    onSelected: (_) => setState(() => _readingState = state),
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
    required this.onLongPress,
  });

  final Series series;
  final Map<String, String> imageHeaders;

  /// True when the series has content newer than what's been downloaded.
  final bool updateAvailable;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label:
          '${series.title} by ${series.author}'
          "${updateAvailable ? '. New chapters available' : ''}",
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
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
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: _VolumeBadge(),
                        ),
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
    required this.onLongPress,
  });

  final ReadingEntry entry;

  /// The owning series, if it's in the loaded library — for the cover art.
  final Series? series;
  final Map<String, String> imageHeaders;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = entry.progress;
    final title = series?.title ?? entry.volume.title;
    final chapterLabel = progress.chapterCount > 0
        ? 'Chapter ${progress.chapterIndex + 1} of ${progress.chapterCount}'
        : 'Chapter ${progress.chapterIndex + 1}';
    return Semantics(
      button: true,
      label: 'Continue reading $title, $chapterLabel',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
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
    this.reason = '',
    this.isWildcard = false,
    this.onDismiss,
    this.onLike,
    this.onLongPress,
  });

  final Series series;
  final Map<String, String> imageHeaders;
  final VoidCallback onTap;

  /// The engine's "Because…" line — why this pick is here.
  final String reason;

  /// True for the daily out-of-taste exploration pick.
  final bool isWildcard;

  final VoidCallback? onDismiss;

  /// 👍 "more like this" — the engine's explicit positive signal.
  final VoidCallback? onLike;

  /// Opens the full feedback options sheet (like / snooze / dismiss).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${series.title} by ${series.author}'
          '${reason.isEmpty ? '' : '. $reason'}',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
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
                        if (onLike != null)
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: _LikeChip(onPressed: onLike!),
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
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    // The wildcard's "Something different" reads as a badge.
                    color: isWildcard
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.85),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
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
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
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
    return Semantics(
      button: true,
      label: 'Not interested',
      child: Material(
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
      ),
    );
  }
}

/// The 👍 "more like this" chip on a recommendation card.
class _LikeChip extends StatelessWidget {
  const _LikeChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'More like this',
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.thumb_up, size: 14, color: Colors.white),
          ),
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
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  /// Optional second, lower-emphasis action (e.g. "Import books" next to
  /// "Connect" on the no-server state).
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

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
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
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
      final seriesGenres = {for (final g in series.genres) g.trim()};
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
                        setState(() => _draft = _draft.copyWith(genres: next));
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
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(downloaded: v)),
            ),
            const SizedBox(height: 16),
            _sectionLabel(theme, 'Volumes'),
            _triStateRow(
              value: _draft.multiVolume,
              labels: const ['Any', 'Multi-volume', 'Single volume'],
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(multiVolume: v)),
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
