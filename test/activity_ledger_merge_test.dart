// Tests for the cross-device fold in ReadingActivityStore.mergeSyncBlob.
//
// The activity ledger is the one synced store that is not per-entry
// last-writer-wins: each device owns its own ledger and totals are the sum
// across all of them. That makes the cache of *other* devices' ledgers
// load-bearing, and it used to be replaced wholesale by whatever the last
// blob contained — so a blob written by a device that hadn't yet seen its
// peer erased that peer's history, and its share of every daily total.
// Symptom: a streak built on one device never showed up on the other.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';

import 'helpers/test_db.dart';

Volume _volume({int seriesId = 1, String fileName = 'book.epub'}) => Volume(
  seriesOpdsId: seriesId,
  title: 'A Book',
  fileName: fileName,
  downloadUrl: '',
  fileSizeBytes: 0,
  updatedAt: null,
);

/// A blob as some other device would have written it.
String _blob(Map<String, Map<String, Map<String, int>>> devices) => jsonEncode({
  for (final d in devices.entries)
    d.key: {
      'daily': d.value['daily'] ?? const <String, int>{},
      'perVolume': d.value['perVolume'] ?? const <String, int>{},
      'dailyWords': d.value['dailyWords'] ?? const <String, int>{},
      'perVolumeWords': d.value['perVolumeWords'] ?? const <String, int>{},
    },
});

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  test('a blob missing a device no longer erases that device', () async {
    final store = ReadingActivityStore();

    // The iPad has seen the phone's reading.
    await store.mergeSyncBlob(
      _blob({
        'phone': {
          'daily': {'2026-07-20': 600, '2026-07-21': 900},
        },
      }),
    );
    expect((await store.load()).dailySeconds['2026-07-20'], 600);

    // Now a blob arrives that predates the phone being known — written by a
    // third device, or by a peer whose own read of the activity key came
    // back empty. It says nothing about the phone at all.
    await store.mergeSyncBlob(
      _blob({
        'laptop': {
          'daily': {'2026-07-22': 300},
        },
      }),
    );

    final totals = (await store.load()).dailySeconds;
    expect(totals['2026-07-20'], 600, reason: 'phone history must survive');
    expect(totals['2026-07-21'], 900);
    expect(totals['2026-07-22'], 300, reason: 'laptop history must arrive');
  });

  test('a stale copy of a device cannot walk its totals backwards', () async {
    final store = ReadingActivityStore();

    await store.mergeSyncBlob(
      _blob({
        'phone': {
          'daily': {'2026-07-20': 900},
        },
      }),
    );
    // The same device, seen in an older state — blobs are not ordered.
    await store.mergeSyncBlob(
      _blob({
        'phone': {
          'daily': {'2026-07-20': 300},
        },
      }),
    );

    expect((await store.load()).dailySeconds['2026-07-20'], 900);
  });

  test('a growing ledger for a known device still moves forward', () async {
    final store = ReadingActivityStore();
    await store.mergeSyncBlob(
      _blob({
        'phone': {
          'daily': {'2026-07-20': 300},
        },
      }),
    );
    await store.mergeSyncBlob(
      _blob({
        'phone': {
          'daily': {'2026-07-20': 1200, '2026-07-21': 60},
        },
      }),
    );

    final totals = (await store.load()).dailySeconds;
    expect(totals['2026-07-20'], 1200);
    expect(totals['2026-07-21'], 60);
  });

  test(
    'a remote streak survives an unrelated blob and reaches the UI',
    () async {
      final store = ReadingActivityStore();
      // Three consecutive days read on the phone.
      await store.mergeSyncBlob(
        _blob({
          'phone': {
            'daily': {'2026-07-20': 600, '2026-07-21': 600, '2026-07-22': 600},
          },
        }),
      );
      await store.mergeSyncBlob(
        _blob({
          'laptop': {'daily': <String, int>{}},
        }),
      );

      final activity = await store.load();
      expect(
        activity.currentStreak(now: DateTime(2026, 7, 22, 20)),
        3,
        reason: 'the streak is the reason this sync exists',
      );
    },
  );

  test('this device is never taken from the cloud copy', () async {
    final store = ReadingActivityStore();
    await store.record(
      _volume(),
      const Duration(seconds: 400),
      now: DateTime(2026, 7, 20),
    );

    // The cloud's idea of this device is wrong/stale; the local tables win.
    final id = jsonDecode(await store.exportSyncBlob()) as Map<String, dynamic>;
    final myId = id.keys.single;
    await store.mergeSyncBlob(
      _blob({
        myId: {
          'daily': {'2026-07-20': 99999},
        },
      }),
    );

    expect((await store.load()).dailySeconds['2026-07-20'], 400);
    CloudSyncService().cancelPendingTimers();
  });

  test('the exported blob carries both this device and its peers', () async {
    final store = ReadingActivityStore();
    await store.record(
      _volume(),
      const Duration(seconds: 120),
      now: DateTime(2026, 7, 20),
    );
    await store.mergeSyncBlob(
      _blob({
        'phone': {
          'daily': {'2026-07-19': 500},
        },
      }),
    );

    final out =
        jsonDecode(await store.exportSyncBlob()) as Map<String, dynamic>;
    expect(out.keys, contains('phone'));
    expect(out.keys.length, 2, reason: 'this device plus the phone');
    CloudSyncService().cancelPendingTimers();
  });
}
