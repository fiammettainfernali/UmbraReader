import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bookmark_store.dart';
import 'collection_store.dart';
import 'custom_theme_store.dart';
import 'glossary_store.dart';
import 'library_view_store.dart';
import 'reader_preferences.dart';
import 'saved_view_store.dart';
import 'reading_activity_store.dart';
import 'reading_progress_store.dart';
import 'recommendation_feedback_store.dart';
import 'series_status_store.dart';
import 'sync_backend.dart';

/// Syncs a slice of the user's data across their devices.
///
/// Synced: reading progress (per-volume, last-write-wins by `updatedAt`),
/// collections (whole-set, last-write-wins), bookmarks (union by id),
/// reader settings, recommendation feedback, the reading-activity ledger,
/// manual series status (per-series LWW, feeds the recommendation engine),
/// per-series glossaries (union by id; sightings keep the furthest-along
/// one), and user-defined themes (union by id).
///
/// This class owns *what* syncs and how it merges. Where the blobs actually
/// go is a [SyncBackend] — iCloud documents on iOS, nothing at all on
/// Android until there is a reason for something else. That split is what
/// lets Android ship local-only without any of the merge logic below moving:
/// every store persists locally regardless, so sync is a layer, not a
/// foundation.
///
/// A backend that cannot reach its cloud is not an error. All methods here
/// stay safe to call — reads find nothing, writes go nowhere, and the app
/// runs exactly as it does offline.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();
  factory CloudSyncService() => instance;

  /// The transport in use. Assign before [initialize] to override the
  /// platform default — tests do this to exercise a specific backend, and
  /// it is the seam a future Android backend plugs into.
  SyncBackend backend = SyncBackend.forPlatform();

  static const _kProgress = 'cloud_reading_progress';
  static const _kCollections = 'cloud_collections';
  static const _kRecFeedback = 'cloud_rec_feedback';
  static const _kBookmarks = 'cloud_bookmarks';
  static const _kReaderSettings = 'cloud_reader_settings';
  static const _kActivity = 'cloud_activity';
  static const _kSeriesStatus = 'cloud_series_status';
  static const _kGlossary = 'cloud_glossary';
  static const _kCustomThemes = 'cloud_custom_themes';
  static const _kLibraryView = 'cloud_library_view';
  static const _kSavedViews = 'cloud_saved_views';

  /// True while a cloud→local merge is in flight, so the store-write hooks
  /// don't bounce the just-merged data straight back up to the cloud.
  bool _merging = false;

  /// Called after a remote change has been merged into local stores, so the
  /// UI (e.g. the library's Continue Reading shelf) can refresh.
  void Function()? onRemoteMerge;

  Timer? _progressDebounce;
  Timer? _activityDebounce;
  Timer? _mergeDebounce;
  Timer? _libraryViewDebounce;

  /// Cancels any pending debounced work. Tests use this so a 3-second push
  /// timer armed by a progress save can't outlive the test body.
  @visibleForTesting
  void cancelPendingTimers() {
    _progressDebounce?.cancel();
    _progressDebounce = null;
    _activityDebounce?.cancel();
    _activityDebounce = null;
    _mergeDebounce?.cancel();
    _mergeDebounce = null;
    _libraryViewDebounce?.cancel();
    _libraryViewDebounce = null;
  }

  /// Wires the external-change listeners and kicks off the initial pull.
  /// The pull runs unawaited so a slow iCloud round-trip never delays app
  /// launch — merged data lands via [onRemoteMerge] when it arrives.
  Future<void> initialize() async {
    await backend.initialize(_onRemoteChange);
    unawaited(pullAndMerge());
  }

  /// The backend saw something change upstream.
  ///
  /// Coalesced: iCloud's metadata query fires in bursts as files download,
  /// and merging once per file would read every store eleven times over.
  void _onRemoteChange() {
    _mergeDebounce?.cancel();
    _mergeDebounce = Timer(const Duration(seconds: 2), pullAndMerge);
  }

  // ── transport ──────────────────────────────────────────────────────────
  // Thin, and deliberately so: these were the only two methods that knew
  // about iCloud, which is why the whole port comes down to swapping what
  // sits behind them.

  Future<String?> _get(String key) => backend.read(key);

  Future<void> _set(String key, String value) => backend.write(key, value);

  // ── push: local → cloud ────────────────────────────────────────────────

  /// Pushes reading progress, debounced — page-turn saves fire often, and
  /// batching avoids hammering the key-value store.
  void pushReadingProgressSoon() {
    if (_merging) return;
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(seconds: 3), pushReadingProgress);
  }

  Future<void> pushReadingProgress({bool force = false}) async {
    if (_merging && !force) return;
    await _set(_kProgress, await ReadingProgressStore().exportSyncBlob());
  }

  /// Forces an immediate reading-progress push, cancelling any pending
  /// debounced one.
  ///
  /// Call this when the app is backgrounding. iOS freezes Dart timers the
  /// instant the process suspends, so the 3-second [pushReadingProgressSoon]
  /// debounce armed by the last page turn usually never fires — the freshest
  /// position stays on this device and the user's other device resumes at an
  /// older spot. Pushing synchronously here hands the write to the native
  /// iCloud bridge before suspension, where its own background queue and the
  /// iCloud daemon can finish the upload.
  ///
  /// A flush pushes even mid-merge. The [_merging] guard exists to stop
  /// routine pushes stampeding a pull, but silently dropping the one push
  /// that happens as the process suspends strands the session that just
  /// ended. Overlapping is safe: every merge here is either per-entry
  /// last-writer-wins or monotonic, so a push that crosses one cannot take
  /// data away.
  Future<void> flushReadingProgress() async {
    _progressDebounce?.cancel();
    _progressDebounce = null;
    await pushReadingProgress(force: true);
  }

  Future<void> pushCollections() async {
    if (_merging) return;
    await _set(_kCollections, await CollectionStore().exportSyncBlob());
  }

  Future<void> pushRecFeedback() async {
    if (_merging) return;
    await _set(
      _kRecFeedback,
      await RecommendationFeedbackStore().exportSyncBlob(),
    );
  }

  /// Pushes the reading-activity ledger, debounced — session flushes fire
  /// on every reader close/background.
  void pushActivitySoon() {
    if (_merging) return;
    _activityDebounce?.cancel();
    _activityDebounce = Timer(const Duration(seconds: 5), pushActivity);
  }

  Future<void> pushActivity({bool force = false}) async {
    if (_merging && !force) return;
    await _set(_kActivity, await ReadingActivityStore().exportSyncBlob());
  }

  /// Forces an immediate activity-ledger push, cancelling any pending
  /// debounced one. Same rationale as [flushReadingProgress]: the 5-second
  /// [pushActivitySoon] debounce is frozen when iOS suspends the app, so
  /// reading time and streaks would otherwise lag behind on the other device.
  Future<void> flushActivity() async {
    _activityDebounce?.cancel();
    _activityDebounce = null;
    await pushActivity(force: true);
  }

  Future<void> pushBookmarks() async {
    if (_merging) return;
    await _set(_kBookmarks, await BookmarkStore().exportSyncBlob());
  }

  Future<void> pushReaderSettings() async {
    if (_merging) return;
    await _set(_kReaderSettings, await ReaderPreferences().exportSyncBlob());
  }

  Future<void> pushSeriesStatus() async {
    if (_merging) return;
    await _set(_kSeriesStatus, await SeriesStatusStore().exportSyncBlob());
  }

  Future<void> pushGlossary() async {
    if (_merging) return;
    await _set(_kGlossary, await GlossaryStore().exportSyncBlob());
  }

  /// Pushes the library view, debounced — toggling filter chips in a sheet
  /// fires on every tap, and only the arrangement you settle on matters.
  void pushLibraryViewSoon() {
    if (_merging) return;
    _libraryViewDebounce?.cancel();
    _libraryViewDebounce = Timer(const Duration(seconds: 2), pushLibraryView);
  }

  Future<void> pushLibraryView() async {
    if (_merging) return;
    await _set(_kLibraryView, await LibraryViewStore().exportSyncBlob());
  }

  /// Pushed immediately rather than debounced: saving, renaming or deleting
  /// a view is a deliberate act, not a stream of them.
  Future<void> pushSavedViews() async {
    if (_merging) return;
    await _set(_kSavedViews, await SavedViewStore().exportSyncBlob());
  }

  Future<void> pushCustomThemes() async {
    if (_merging) return;
    await _set(_kCustomThemes, await CustomThemeStore().exportSyncBlob());
  }

  // ── pull + merge: cloud → local ────────────────────────────────────────

  Future<void> pullAndMerge() async {
    _merging = true;
    var changed = false;
    try {
      final progress = await _get(_kProgress);
      if (progress != null &&
          await ReadingProgressStore().mergeSyncBlob(progress)) {
        changed = true;
      }
      final collections = await _get(_kCollections);
      if (collections != null &&
          await CollectionStore().mergeSyncBlob(collections)) {
        changed = true;
      }
      final rec = await _get(_kRecFeedback);
      if (rec != null &&
          await RecommendationFeedbackStore().mergeSyncBlob(rec)) {
        changed = true;
      }
      final bookmarks = await _get(_kBookmarks);
      if (bookmarks != null && await BookmarkStore().mergeSyncBlob(bookmarks)) {
        changed = true;
      }
      final readerSettings = await _get(_kReaderSettings);
      if (readerSettings != null &&
          await ReaderPreferences().mergeSyncBlob(readerSettings)) {
        changed = true;
      }
      final activity = await _get(_kActivity);
      if (activity != null &&
          await ReadingActivityStore().mergeSyncBlob(activity)) {
        changed = true;
      }
      final seriesStatus = await _get(_kSeriesStatus);
      if (seriesStatus != null &&
          await SeriesStatusStore().mergeSyncBlob(seriesStatus)) {
        changed = true;
      }
      final glossary = await _get(_kGlossary);
      if (glossary != null && await GlossaryStore().mergeSyncBlob(glossary)) {
        changed = true;
      }
      final savedViews = await _get(_kSavedViews);
      if (savedViews != null &&
          await SavedViewStore().mergeSyncBlob(savedViews)) {
        changed = true;
      }
      final libraryView = await _get(_kLibraryView);
      if (libraryView != null &&
          await LibraryViewStore().mergeSyncBlob(libraryView)) {
        changed = true;
      }
      final themes = await _get(_kCustomThemes);
      if (themes != null && await CustomThemeStore().mergeSyncBlob(themes)) {
        changed = true;
      }
    } finally {
      _merging = false;
    }
    if (changed) {
      // Our merged local state may now be ahead of the cloud (e.g. a volume
      // the other device hadn't seen). Push the union back up, then let the
      // UI repaint.
      await pushReadingProgress();
      await pushCollections();
      await pushRecFeedback();
      await pushBookmarks();
      await pushReaderSettings();
      await pushActivity();
      await pushSeriesStatus();
      await pushGlossary();
      await pushCustomThemes();
      await pushLibraryView();
      await pushSavedViews();
      onRemoteMerge?.call();
    }
  }
}
