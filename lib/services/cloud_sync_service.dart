import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bookmark_store.dart';
import 'collection_store.dart';
import 'reader_preferences.dart';
import 'reading_activity_store.dart';
import 'reading_progress_store.dart';
import 'recommendation_feedback_store.dart';

/// Syncs a slice of the user's data across their Apple devices via JSON
/// files in the app's private iCloud Drive container, bridged in
/// `ios/Runner/AppDelegate.swift` over the `umbra/icloud_docs` channel.
///
/// Synced: reading progress (per-volume, last-write-wins by `updatedAt`),
/// collections (whole-set, last-write-wins), bookmarks (union by id),
/// reader settings and recommendation feedback.
///
/// The previous transport was iCloud *key-value* storage (1 MB total cap —
/// too small for a large library). Reads fall back to the old KVS keys when
/// a document doesn't exist yet, so data synced by older builds migrates
/// seamlessly: the first pull reads KVS, the next push writes documents.
/// Writes fall back to KVS when the document container is unavailable
/// (e.g. an older provisioning profile without the container entitlement).
///
/// Every platform-channel call is guarded: on a device without the native
/// bridge (Android, tests, desktop) or with iCloud unavailable, all methods
/// become no-ops and the app runs exactly as it did before — local-only.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();
  factory CloudSyncService() => instance;

  static const MethodChannel _docs = MethodChannel('umbra/icloud_docs');
  static const MethodChannel _kv = MethodChannel('umbra/icloud_kv');

  static const _kProgress = 'cloud_reading_progress';
  static const _kCollections = 'cloud_collections';
  static const _kRecFeedback = 'cloud_rec_feedback';
  static const _kBookmarks = 'cloud_bookmarks';
  static const _kReaderSettings = 'cloud_reader_settings';
  static const _kActivity = 'cloud_activity';

  /// True while a cloud→local merge is in flight, so the store-write hooks
  /// don't bounce the just-merged data straight back up to the cloud.
  bool _merging = false;

  /// Called after a remote change has been merged into local stores, so the
  /// UI (e.g. the library's Continue Reading shelf) can refresh.
  void Function()? onRemoteMerge;

  Timer? _progressDebounce;
  Timer? _activityDebounce;
  Timer? _mergeDebounce;

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
  }

  /// Wires the external-change listeners and kicks off the initial pull.
  /// The pull runs unawaited so a slow iCloud round-trip never delays app
  /// launch — merged data lands via [onRemoteMerge] when it arrives.
  Future<void> initialize() async {
    _docs.setMethodCallHandler(_handleNative);
    _kv.setMethodCallHandler(_handleNative);
    unawaited(pullAndMerge());
  }

  Future<void> _handleNative(MethodCall call) async {
    if (call.method == 'changedExternally') {
      // The metadata query can fire in bursts as files download; coalesce.
      _mergeDebounce?.cancel();
      _mergeDebounce = Timer(const Duration(seconds: 2), pullAndMerge);
    }
  }

  // ── low-level channel helpers (all swallow missing-plugin / iCloud errors)

  Future<String?> _get(String key) async {
    try {
      final doc = await _docs.invokeMethod<String>('read', {
        'name': '$key.json',
      });
      if (doc != null) return doc;
    } on Exception {
      // fall through to the legacy key-value store
    } on Error {
      // fall through
    }
    try {
      return await _kv.invokeMethod<String>('get', {'key': key});
    } on Exception {
      return null;
    } on Error {
      return null;
    }
  }

  Future<void> _set(String key, String value) async {
    try {
      final ok = await _docs.invokeMethod<bool>('write', {
        'name': '$key.json',
        'value': value,
      });
      if (ok == true) return;
    } on Exception {
      // fall through to the legacy key-value store
    } on Error {
      // fall through
    }
    try {
      await _kv.invokeMethod<void>('set', {'key': key, 'value': value});
    } on Exception {
      // No cloud here — local store already holds the truth.
    } on Error {
      // ignore
    }
  }

  // ── push: local → cloud ────────────────────────────────────────────────

  /// Pushes reading progress, debounced — page-turn saves fire often, and
  /// batching avoids hammering the key-value store.
  void pushReadingProgressSoon() {
    if (_merging) return;
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(seconds: 3), pushReadingProgress);
  }

  Future<void> pushReadingProgress() async {
    if (_merging) return;
    _set(_kProgress, await ReadingProgressStore().exportSyncBlob());
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
  Future<void> flushReadingProgress() async {
    _progressDebounce?.cancel();
    _progressDebounce = null;
    await pushReadingProgress();
  }

  Future<void> pushCollections() async {
    if (_merging) return;
    _set(_kCollections, await CollectionStore().exportSyncBlob());
  }

  Future<void> pushRecFeedback() async {
    if (_merging) return;
    _set(_kRecFeedback, await RecommendationFeedbackStore().exportSyncBlob());
  }

  /// Pushes the reading-activity ledger, debounced — session flushes fire
  /// on every reader close/background.
  void pushActivitySoon() {
    if (_merging) return;
    _activityDebounce?.cancel();
    _activityDebounce = Timer(const Duration(seconds: 5), pushActivity);
  }

  Future<void> pushActivity() async {
    if (_merging) return;
    _set(_kActivity, await ReadingActivityStore().exportSyncBlob());
  }

  /// Forces an immediate activity-ledger push, cancelling any pending
  /// debounced one. Same rationale as [flushReadingProgress]: the 5-second
  /// [pushActivitySoon] debounce is frozen when iOS suspends the app, so
  /// reading time and streaks would otherwise lag behind on the other device.
  Future<void> flushActivity() async {
    _activityDebounce?.cancel();
    _activityDebounce = null;
    await pushActivity();
  }

  Future<void> pushBookmarks() async {
    if (_merging) return;
    _set(_kBookmarks, await BookmarkStore().exportSyncBlob());
  }

  Future<void> pushReaderSettings() async {
    if (_merging) return;
    _set(_kReaderSettings, await ReaderPreferences().exportSyncBlob());
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
      if (bookmarks != null &&
          await BookmarkStore().mergeSyncBlob(bookmarks)) {
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
      onRemoteMerge?.call();
    }
  }
}
