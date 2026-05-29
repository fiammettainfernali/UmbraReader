import 'dart:async';

import 'package:flutter/services.dart';

import 'collection_store.dart';
import 'reading_progress_store.dart';
import 'recommendation_feedback_store.dart';

/// Syncs a small slice of the user's data across their Apple devices via
/// iCloud key-value storage (`NSUbiquitousKeyValueStore`), bridged in
/// `ios/Runner/AppDelegate.swift` over the `umbra/icloud_kv` channel.
///
/// Synced: reading progress (per-volume, last-write-wins by `updatedAt`),
/// collections (whole-set, last-write-wins), and recommendation feedback
/// (per-series, stronger signal wins). Bookmarks, highlights and reader
/// settings stay device-local by design.
///
/// Every platform-channel call is guarded: on a device without the native
/// bridge (Android, tests, desktop) or with iCloud unavailable, all methods
/// become no-ops and the app runs exactly as it did before — local-only.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();
  factory CloudSyncService() => instance;

  static const MethodChannel _channel = MethodChannel('umbra/icloud_kv');

  static const _kProgress = 'cloud_reading_progress';
  static const _kCollections = 'cloud_collections';
  static const _kRecFeedback = 'cloud_rec_feedback';

  /// True while a cloud→local merge is in flight, so the store-write hooks
  /// don't bounce the just-merged data straight back up to the cloud.
  bool _merging = false;

  /// Called after a remote change has been merged into local stores, so the
  /// UI (e.g. the library's Continue Reading shelf) can refresh.
  void Function()? onRemoteMerge;

  Timer? _progressDebounce;

  /// Wires the external-change listener and kicks off the initial pull.
  /// The pull runs unawaited so a slow iCloud round-trip never delays app
  /// launch — merged data lands via [onRemoteMerge] when it arrives.
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleNative);
    unawaited(pullAndMerge());
  }

  Future<void> _handleNative(MethodCall call) async {
    if (call.method == 'changedExternally') {
      await pullAndMerge();
    }
  }

  // ── low-level channel helpers (all swallow missing-plugin / iCloud errors)

  Future<String?> _get(String key) async {
    try {
      return await _channel.invokeMethod<String>('get', {'key': key});
    } on Exception {
      return null;
    } on Error {
      return null;
    }
  }

  Future<void> _set(String key, String value) async {
    try {
      await _channel.invokeMethod<void>('set', {'key': key, 'value': value});
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

  Future<void> pushCollections() async {
    if (_merging) return;
    _set(_kCollections, await CollectionStore().exportSyncBlob());
  }

  Future<void> pushRecFeedback() async {
    if (_merging) return;
    _set(_kRecFeedback, await RecommendationFeedbackStore().exportSyncBlob());
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
      onRemoteMerge?.call();
    }
  }
}
