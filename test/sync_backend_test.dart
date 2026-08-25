// The transport is now a seam, and the Android port rests on it.
//
// CloudSyncService owns what syncs and how it merges; SyncBackend owns where
// the blobs go. iCloud has no Android equivalent, so rather than decide the
// Android sync product in order to compile, the transport became an interface
// with a do-nothing implementation.
//
// Two properties have to hold for that to be safe, and neither is obvious:
//
//   1. With no cloud, every sync method still runs and changes nothing. The
//      local stores already hold the truth — an absent backend is a normal
//      state, not a degraded one.
//   2. The merge logic never learns which backend it has. If a push or pull
//      starts special-casing the transport, the split has failed and Android
//      will diverge from iOS the first time someone fixes a bug in one.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/sync_backend.dart';

import 'helpers/test_db.dart';

/// Records everything written, and serves back whatever it was given.
class _RecordingBackend extends SyncBackend {
  _RecordingBackend([Map<String, String>? seed])
    : store = {...?seed};

  final Map<String, String> store;
  final List<String> reads = [];
  int initializeCalls = 0;
  void Function()? remoteChange;

  @override
  Future<void> initialize(void Function() onRemoteChange) async {
    initializeCalls++;
    remoteChange = onRemoteChange;
  }

  @override
  Future<String?> read(String key) async {
    reads.add(key);
    return store[key];
  }

  @override
  Future<void> write(String key, String value) async => store[key] = value;
}

Volume _volume() => Volume(
  seriesOpdsId: 3,
  title: 'Backend Test',
  fileName: 'backend-test.epub',
  downloadUrl: 'http://unused/backend-test.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(() {
    CloudSyncService().cancelPendingTimers();
    CloudSyncService().backend = SyncBackend.forPlatform();
  });

  group('platform default', () {
    test('anything that is not iOS gets no cloud', () {
      // The port depends on this: Android must not reach for a channel that
      // is not there and spend a round-trip per store discovering it.
      expect(SyncBackend.forPlatform(), isA<NullSyncBackend>());
      expect(defaultTargetPlatform, isNot(TargetPlatform.iOS),
          reason: 'this assertion is only meaningful off iOS');
    });

    test('iOS gets iCloud', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(SyncBackend.forPlatform(), isA<ICloudSyncBackend>());
    });
  });

  group('no cloud', () {
    test('a read finds nothing and a write goes nowhere', () async {
      const backend = NullSyncBackend();
      await backend.write('cloud_reading_progress', '{"anything": true}');
      expect(await backend.read('cloud_reading_progress'), isNull);
    });

    test('pushing and pulling still run, and change nothing', () async {
      CloudSyncService().backend = const NullSyncBackend();
      await ReadingProgressStore().save(
        _volume(),
        const ReadingProgress(chapterIndex: 12, blockIndex: 1,
            chapterCount: 40),
      );

      // Neither of these may throw, and the local position must survive.
      await CloudSyncService().flushReadingProgress();
      await CloudSyncService().pullAndMerge();

      final progress = await ReadingProgressStore().load(_volume());
      expect(progress.chapterIndex, 12);
    });

    test('initialize is safe without a cloud', () async {
      CloudSyncService().backend = const NullSyncBackend();
      await CloudSyncService().initialize();
      CloudSyncService().cancelPendingTimers();
    });
  });

  group('the service talks only to its backend', () {
    test('a push reaches the backend it was given', () async {
      final backend = _RecordingBackend();
      CloudSyncService().backend = backend;

      await ReadingProgressStore().save(
        _volume(),
        const ReadingProgress(chapterIndex: 5, blockIndex: 0, chapterCount: 40),
      );
      await CloudSyncService().flushReadingProgress();

      expect(backend.store.keys, contains('cloud_reading_progress'));
    });

    test('the key is transport-agnostic', () async {
      // No '.json', no container path, nothing iCloud-shaped. Turning the key
      // into a filename is the iCloud backend's business, and a backend that
      // wants a column or an HTTP path must be free to do that instead.
      final backend = _RecordingBackend();
      CloudSyncService().backend = backend;
      await CloudSyncService().pullAndMerge();

      expect(backend.reads, isNotEmpty);
      for (final key in backend.reads) {
        expect(key, isNot(contains('.json')));
        expect(key, isNot(contains('/')));
      }
    });

    test('a pull merges what the backend serves', () async {
      // Seed a backend from one device, then read it back on another.
      final source = _RecordingBackend();
      CloudSyncService().backend = source;
      await ReadingProgressStore().save(
        _volume(),
        const ReadingProgress(chapterIndex: 88, blockIndex: 2,
            chapterCount: 120),
      );
      await CloudSyncService().flushReadingProgress();

      // A fresh device: same backend contents, empty local stores.
      await useInMemoryDatabase();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      CloudSyncService().backend = _RecordingBackend(source.store);

      await CloudSyncService().pullAndMerge();

      final progress = await ReadingProgressStore().load(_volume());
      expect(progress.chapterIndex, 88,
          reason: 'the pulled position did not reach the local store');
    });

    test('initialize hands the backend a way to ask for a pull', () async {
      final backend = _RecordingBackend();
      CloudSyncService().backend = backend;
      await CloudSyncService().initialize();
      CloudSyncService().cancelPendingTimers();

      expect(backend.initializeCalls, 1);
      expect(backend.remoteChange, isNotNull,
          reason: 'a backend that can push notifications has no way to say so');
    });
  });
}
