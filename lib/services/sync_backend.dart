import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where a sync blob goes when it leaves the device, and where it comes
/// back from.
///
/// [CloudSyncService] owns *what* syncs and how conflicts merge — per-entry
/// last-writer-wins, unions by id, monotonic counters. That logic is
/// platform-agnostic and always was. This is the other half: the transport,
/// which is not.
///
/// The split exists for the Android port. iCloud has no Android equivalent,
/// and the alternatives are not equivalent to each other either — Drive, the
/// user's own Novel Grabber server, or nothing at all are three different
/// products, not three spellings of one. Rather than decide that question in
/// order to compile on Android, the transport became an interface with a
/// do-nothing implementation, so Android can ship local-only and pick a
/// backend later without the merge logic moving at all.
///
/// A backend is a dumb key/value store over strings. It may fail, and failure
/// is not exceptional: the local stores already hold the truth, so an
/// unreachable cloud is a no-op rather than an error. Implementations swallow
/// their own transport errors and return null / do nothing.
abstract class SyncBackend {
  const SyncBackend();

  /// Prepare the transport and register [onRemoteChange], which the backend
  /// calls when something upstream has changed and a pull is worth doing.
  ///
  /// Backends that cannot push notifications simply never call it.
  Future<void> initialize(void Function() onRemoteChange) async {}

  /// The blob stored under [key], or null if there is none (or no cloud).
  Future<String?> read(String key);

  /// Store [value] under [key]. Silently does nothing when there is no cloud.
  Future<void> write(String key, String value);

  /// The backend this platform gets by default.
  ///
  /// Android deliberately gets [NullSyncBackend] rather than a broken iCloud
  /// one: the channel would throw `MissingPluginException` on every call and
  /// be caught, which works, but spends a platform round-trip per store per
  /// sync to discover something known at compile time.
  static SyncBackend forPlatform() {
    return defaultTargetPlatform == TargetPlatform.iOS
        ? const ICloudSyncBackend()
        : const NullSyncBackend();
  }
}

/// No cloud. Reads find nothing, writes go nowhere.
///
/// This is not a stub awaiting an implementation — it is the correct backend
/// for a single-device install, and what Android ships with until there is a
/// reason for something else. Every store persists locally regardless; sync
/// is a layer on top, never a foundation.
class NullSyncBackend extends SyncBackend {
  const NullSyncBackend();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

/// JSON files in the app's private iCloud Drive container, bridged in
/// `ios/Runner/AppDelegate.swift`.
///
/// The previous transport was iCloud *key-value* storage (1 MB total cap —
/// too small for a large library). Reads fall back to the old KVS keys when a
/// document doesn't exist yet, so data synced by older builds migrates
/// seamlessly: the first pull reads KVS, the next push writes documents.
/// Writes fall back to KVS when the document container is unavailable (e.g.
/// an older provisioning profile without the container entitlement).
///
/// Every channel call is guarded. On a device without the native bridge, or
/// with iCloud switched off, this degrades to exactly [NullSyncBackend].
class ICloudSyncBackend extends SyncBackend {
  const ICloudSyncBackend();

  static const MethodChannel _docs = MethodChannel('umbra/icloud_docs');
  static const MethodChannel _kv = MethodChannel('umbra/icloud_kv');

  @override
  Future<void> initialize(void Function() onRemoteChange) async {
    Future<dynamic> handle(MethodCall call) async {
      if (call.method == 'changedExternally') onRemoteChange();
    }

    _docs.setMethodCallHandler(handle);
    _kv.setMethodCallHandler(handle);
  }

  @override
  Future<String?> read(String key) async {
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

  @override
  Future<void> write(String key, String value) async {
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
      // No cloud here — the local store already holds the truth.
    } on Error {
      // ignore
    }
  }
}
