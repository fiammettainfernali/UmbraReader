import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../models/saved_view.dart';
import '../models/series.dart';
import '../models/volume.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/opds_client.dart';
import '../services/bookmark_store.dart';
import '../services/collection_store.dart';
import '../services/reading_progress_store.dart';
import '../services/streamed_count_refresh.dart';
import '../services/rec_outcome_store.dart';
import '../services/cloud_sync_service.dart';
import '../services/control_client.dart';
import '../services/recommendation_feedback_store.dart';
import '../services/saved_view_store.dart';
import '../services/series_status_store.dart';
import '../services/reading_activity_store.dart';
import '../services/settings_service.dart';
import '../widgets/add_to_collection_sheet.dart';
import '../widgets/action_sheet.dart';
import '../widgets/section_header.dart';
import 'backup_screen.dart';
import 'collections_screen.dart';
import 'glossary_screen.dart';
import 'imported_books_screen.dart';
import 'library_cards.dart';
import 'library_downloads.dart';
import 'library_filters.dart';
import 'library_search_screen.dart';
import '../widgets/pro_sheet.dart';
import 'reader_screen.dart';
import 'saved_views_screen.dart';
import 'series_detail_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'storage_screen.dart';

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
    with WidgetsBindingObserver, LibraryDownloads, LibraryFiltering {
  final _settingsService = SettingsService();
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

  /// Why the last library fetch failed, when it did. Shown in the offline
  /// banner: see the note where it is set.
  String? _offlineReason;

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

  /// Reading-time activity + daily goal for the home streak chip. Its
  /// per-volume seconds also drive the library's "Time spent" sort.
  ReadingActivity _activity = ReadingActivity.empty;

  /// The user's collections — loaded for the recommendation signals, and
  /// reused so the library can be narrowed to one.
  List<Collection> _collections = const [];
  int _dailyGoalMinutes = 0;

  /// True while Novel Grabber is working on something.
  ///
  /// The server moved to its own tab, so downloads no longer announce
  /// themselves on the way past. This is a quiet pulse on the app bar —
  /// enough to notice, and a tap away from the detail.
  bool _serverBusy = false;
  StreamSubscription<ControlEvent>? _serverEvents;

  /// Download records, used to flag series with content newer than what's
  /// been downloaded. Null until first loaded.
  DownloadStore? _downloads;

  /// Throttle for the background library-maintenance pass (auto-download next
  /// volume + auto-delete). It must NOT run on every sync/pull-to-refresh —
  /// doing so stacked sequential per-series network fetches and downloads
  /// that saturated the connection and slowed manual checking/downloading.
  @override
  Map<int, SeriesStatus> get seriesStatuses => _seriesStatus;
  @override
  List<Collection> get libraryCollections => _collections;
  @override
  Map<String, int> get volumeSecondsRead => _activity.perVolumeSeconds;

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
    loadSavedView();
    _refreshSavedViewCount();
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Returning to the app is a user-caused boundary, so a merge that landed
    // while they were away can safely surface now.
    if (_remoteMergePending) {
      _loadReading();
      // The merge may have carried a newer arrangement from the other
      // device. Same reasoning as the shelf reload: apply it at a boundary
      // the user caused, never under their finger.
      reloadSavedView();
    }
    _syncIfStale();
  }

  /// Fetches the library again if the last fetch is old enough to be worth
  /// redoing.
  ///
  /// Until this existed, the app fetched exactly once per launch — plus
  /// whatever pull-to-refresh the reader did on this screen. An app left
  /// open for a day showed the library as it was when it started, and no
  /// other screen could fix that: they all read the cache this screen
  /// writes. Novel Grabber compiles all day, so that is a lot of missed
  /// news.
  ///
  /// Resume rather than a timer: it is the moment the reader came back and
  /// is a boundary they caused, and iOS freezes Dart timers on suspend
  /// anyway. The interval keeps flicking in and out of the app from
  /// hammering a server that is usually mid-download.
  static const _resyncAfter = Duration(minutes: 5);
  DateTime? _lastSyncAt;

  void _syncIfStale() {
    final last = _lastSyncAt;
    if (last != null && DateTime.now().difference(last) < _resyncAfter) return;
    _sync();
  }

  /// Watches the server only for whether it is busy — the Server tab owns
  /// the detail. Failure is silence, which is the correct answer when the
  /// server cannot be reached anyway.
  void _watchServer() {
    final settings = _settings;
    if (settings == null || !settings.isConfigured) return;
    _serverEvents?.cancel();
    _serverEvents = ControlClient(settings).events().listen(
      (event) {
        if (!mounted) return;
        final progress = event.progress;
        if (progress == null) return;
        final busy = !progress.isIdle;
        if (busy != _serverBusy) setState(() => _serverBusy = busy);
      },
      onError: (_) {
        if (mounted && _serverBusy) setState(() => _serverBusy = false);
      },
    );
  }

  @override
  void dispose() {
    _serverEvents?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (CloudSyncService().onRemoteMerge != null) {
      CloudSyncService().onRemoteMerge = null;
    }
    disposeFiltering();
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
    // Downloads first. The reading shelf asks which volumes are already on
    // the device before deciding whether any need re-measuring from the
    // server, and with no answer it assumes none are — so a cold start used
    // to reach for the network on behalf of books sitting in local storage.
    await _loadDownloads();
    await _loadReading();
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
    // A finished book whose EPUB has been rebuilt since has more in it than
    // when it was finished. Downloaded volumes learn that by being
    // re-downloaded and re-read; streamed ones are never downloaded, so
    // without this they stayed finished for good however many chapters
    // arrived. Costs nothing: the timestamps are already in hand.
    var revived = entries;
    final rebuilt = <int, DateTime?>{
      for (final s in _library ?? const <Series>[]) s.opdsId: s.updatedAt,
    };
    if (rebuilt.isNotEmpty) {
      var any = false;
      for (final e in entries.where((e) => e.progress.isFinished)) {
        if (await ReadingProgressStore()
            .unfinishIfRebuilt(e.volume, rebuilt[e.volume.seriesOpdsId])) {
          any = true;
        }
      }
      if (any) revived = await ReadingProgressStore().allEntries();
    }

    // The Continue shelf excludes volumes the user hid; the filter chips
    // (which use _allReadingEntries) still count them as in-progress.
    List<ReadingEntry> shelf(List<ReadingEntry> from) => from
        .where(
          (e) =>
              e.progress.isStarted &&
              !e.progress.isFinished &&
              !hidden.contains('${e.volume.seriesOpdsId}/${e.volume.fileName}'),
        )
        .take(12)
        .toList();

    if (!mounted) return;
    setState(() {
      _allReadingEntries = revived;
      _activity = activity;
      _collections = collections;
      _dailyGoalMinutes = dailyGoal;
      _seriesStatus = status;
      _reading = shelf(revived);
    });

    // Only now, with the shelf already on screen, re-measure streamed books.
    //
    // A streamed book never learns its own new size: only downloading
    // re-reads an EPUB, and a streamed one is never downloaded, so the shelf
    // went on saying "Chapter 12 of 76" after the book had grown to 82.
    // Worth doing — but not worth waiting for, which is what this used to
    // do. Every one of these is two requests to the server, and away from
    // home they do not fail fast: they sit through a connect timeout and two
    // retries apiece. Awaiting that before the first setState meant the
    // Continue shelf simply did not appear on a cold start off the home
    // network, which read as the reading list having been lost.
    //
    // Skipped outright when the library fetch already failed. There is
    // nothing to learn from a server that just refused to answer.
    if (_settings == null || rebuilt.isEmpty || _offline) return;
    final refreshed = await StreamedCountRefresh(
      settings: _settings!,
      downloads: _downloads,
    ).run(revived, _library ?? const <Series>[]);
    if (refreshed == 0 || !mounted) return;
    final remeasured = await ReadingProgressStore().allEntries();
    if (!mounted) return;
    setState(() {
      _allReadingEntries = remeasured;
      _reading = shelf(remeasured);
    });
  }

  /// Records a "not interested" on a recommendation and refreshes the shelf
  /// without the dismissed pick.
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
      _lastSyncAt = DateTime.now();
      if (!mounted) return;
      setState(() {
        _library = library;
        _offline = false;
        _offlineReason = null;
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
          // Kept, and shown. Going quietly offline threw away the only
          // account of why, and "Offline" is a guess the app makes rather
          // than something it knows: a refused password, an expired
          // certificate and a sleeping server all arrive here and all read
          // as "no signal". Hours went into one of these from the outside —
          // hub logs, packet counts, DNS checks — for a reason the app had
          // in its hand the whole time.
          _offlineReason = e.message;
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
    _watchServer();
    if (settings.isConfigured) await _sync();
  }

  /// Opens a series, then reloads so anything read or downloaded inside is
  /// reflected on return.
  Future<void> openSeries(Series series) async {
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
  @override
  Future<void> openLibrarySearch() async {
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
    if (!await requirePro(context, feature: 'Reading stats, goals & streaks')) {
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
    openSeries(pick);
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
      openSeries(series);
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
        openSeries(series);
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
                // Random and download-all moved into the menu below: both are
                // occasional, and permanent bar space belongs to what is used
                // often. Search is the exception — it earns its place.
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search inside your books',
                  onPressed: openLibrarySearch,
                ),
                // Download-all earns a bar slot: on a library this size it
                // is a real, repeated action, not an occasional one.
                if (canDownloadAll)
                  IconButton(
                    icon: const Icon(Icons.download_for_offline_outlined),
                    tooltip: 'Download whole library',
                    onPressed: confirmDownloadEverything,
                  ),
                if (_serverBusy)
                  IconButton(
                    icon: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                    tooltip: 'Novel Grabber is working — see the Server tab',
                    onPressed: () => _snack(
                      'Novel Grabber is working. Open the Server tab for '
                      'details.',
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  tooltip: 'More',
                  onPressed: _openLibraryMenu,
                ),
              ],
            ),
            ..._buildContentSlivers(),
            // Clears the glass bar the grid now scrolls behind, so the last
            // row of covers can still be reached and tapped.
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.of(context).padding.bottom),
            ),
          ],
        ),
      ),
    );
  }

  /// The library's "more" menu.
  ///
  /// A sheet rather than a popup: it opens under the thumb instead of in the
  /// top-right corner, has room to say what each destination is for, and
  /// groups jumping-off points apart from the things you only visit
  /// occasionally.
  Future<void> _openLibraryMenu() async {
    final action = await showActionSheet<String>(
      context,
      title: 'Library',
      groups: [
        SheetGroup(
          actions: [
            SheetAction(
              value: 'collections',
              icon: Icons.collections_bookmark_outlined,
              label: 'Collections',
              subtitle: 'Your own shelves',
            ),
            SheetAction(
              value: 'imported',
              icon: Icons.upload_file_outlined,
              label: 'Imported books',
              subtitle: 'EPUBs you added from Files',
            ),
            if (_library?.isNotEmpty ?? false)
              SheetAction(
                value: 'random',
                icon: Icons.shuffle,
                label: 'Open a random book',
                subtitle: 'Pick something for me',
              ),
          ],
        ),
        SheetGroup(
          title: 'Views',
          actions: [
            SheetAction(
              value: 'savedViews',
              icon: Icons.bookmarks_outlined,
              label: 'Saved views',
              subtitle: _savedViewCount == 0
                  ? 'Arrangements you can return to'
                  : '$_savedViewCount saved',
            ),
            // Only offered when there is something worth saving; a view of
            // the whole library sorted by title is not one.
            if (!filtersAreClear)
              const SheetAction(
                value: 'saveView',
                icon: Icons.bookmark_add_outlined,
                label: 'Save this view',
                subtitle: 'Name the way the library is narrowed right now',
              ),
          ],
        ),
        SheetGroup(
          title: 'Manage',
          actions: const [
            SheetAction(
              value: 'storage',
              icon: Icons.sd_storage_outlined,
              label: 'Manage storage',
              subtitle: 'See what downloads are taking up space',
            ),
            SheetAction(
              value: 'backup',
              icon: Icons.cloud_upload_outlined,
              label: 'Backup & restore',
              subtitle: 'Export your library, progress and notes',
            ),
            SheetAction(
              value: 'settings',
              icon: Icons.settings_outlined,
              label: 'Server settings',
              subtitle: 'Where your books come from',
            ),
          ],
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'savedViews':
        _openSavedViews();
      case 'saveView':
        _saveCurrentView();
      case 'collections':
        _openCollections();
      case 'imported':
        _openImported();
      case 'random':
        _openRandom();
      case 'storage':
        _openStorage();
      case 'backup':
        _openBackup();
      case 'settings':
        _openSettings();
    }
  }

  /// How many saved views exist, for the menu subtitle. Loaded lazily so an
  /// install that never saves one never reads the store.
  int _savedViewCount = 0;

  Future<void> _openSavedViews() async {
    final chosen = await Navigator.of(context).push<SavedView>(
      MaterialPageRoute(builder: (_) => const SavedViewsScreen()),
    );
    await _refreshSavedViewCount();
    if (!mounted || chosen == null) return;
    applySavedView(chosen);
    _snack('Showing “${chosen.name}”');
  }

  Future<void> _refreshSavedViewCount() async {
    final views = await SavedViewStore().list();
    if (mounted) setState(() => _savedViewCount = views.length);
  }

  Future<void> _saveCurrentView() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save this view'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. Unread cultivation',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    await SavedViewStore().create(name, currentView, query: currentQuery);
    await _refreshSavedViewCount();
    if (mounted) _snack('Saved “$name”');
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
      final visible = visibleLibrary;
      // Shelves are the "home" view: only show them on the default, unfiltered
      // list. Once the user narrows to a reading-state chip (Reading / Unread /
      // Finished / Dropped) or searches, drop straight to the matching grid —
      // recently-updated/recommended aren't relevant to a filtered browse.
      // "Home" extras — the streak and Continue reading — only belong on an
      // unfiltered list. Once a chip or a query narrows things, the screen
      // is answering a question and everything else is in the way.
      //
      // Recently updated and Recommended now live on Discover: they are
      // about choosing something, not about the collection, and here they
      // pushed the actual grid below the fold.
      final showHome =
          searchQuery.trim().isEmpty && readingState == ReadingStateFilter.any;
      final hasHomeContent =
          showHome &&
          (_reading.isNotEmpty ||
              _activity.currentStreak() > 0 ||
              _dailyGoalMinutes > 0);
      return [
        if (_offline) SliverToBoxAdapter(child: _buildOfflineBanner()),
        if (bulkDownloading) SliverToBoxAdapter(child: buildBulkBanner()),
        SliverToBoxAdapter(child: buildControls(all.length, visible.length)),
        if (showHome &&
            (_activity.currentStreak() > 0 || _dailyGoalMinutes > 0))
          SliverToBoxAdapter(child: _buildStreakChip()),
        if (showHome && _reading.isNotEmpty)
          SliverToBoxAdapter(child: _buildContinueHero()),
        if (showHome && _reading.length > 1)
          SliverToBoxAdapter(child: _buildContinueShelf()),
        // Only worth a heading when something sits above it. With nothing
        // in progress the grid starts right under the controls, and
        // "All books" would just be a label on the only thing there is.
        if (hasHomeContent && visible.isNotEmpty)
          SliverToBoxAdapter(child: _sectionHeader('All books')),
        if (visible.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: buildEmptyState())
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
              itemBuilder: (context, index) => SeriesCard(
                series: visible[index],
                imageHeaders: _settings!.isConfigured
                    ? OpdsClient(_settings!).authHeaders
                    : const {},
                updateAvailable: _seriesHasUpdate(visible[index]),
                onTap: () => openSeries(visible[index]),
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
          child: MessageView(
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
          child: MessageView(
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
        child: MessageView(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Offline — showing your saved library. Downloaded books '
                  'can still be read.',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_offlineReason != null && _offlineReason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _offlineReason!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ),
              ],
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
                          ? CoverImage(series: series, headers: headers)
                          : TitleCover(title: entry.volume.title),
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
              final series = seriesById[entry.volume.seriesOpdsId];
              return ContinueCard(
                entry: entry,
                series: series,
                // Whether the library holds something newer than the copy
                // on this device. Deliberately a yes/no and not a count:
                // the card's "of 76" is the spine of one volume, while the
                // library's number is chapters across the whole series, so
                // subtracting them produces a figure that is wrong in a
                // different way for every book.
                hasUpdate: series != null && _seriesHasUpdate(series),
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
}
