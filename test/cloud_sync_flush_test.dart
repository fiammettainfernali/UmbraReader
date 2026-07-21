// Backgrounding must push the freshest reading position to iCloud NOW, not on
// a 3-second debounce that iOS freezes the moment the app suspends.
//
// The bug this guards: you read to chapter 60 on the phone, lock it, pick up
// the iPad — and it resumes at chapter 50, because the last position never
// left the phone. See CloudSyncService.flushReadingProgress.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/reading_activity_store.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

import 'helpers/test_db.dart';

const _docs = MethodChannel('umbra/icloud_docs');

Volume _volume() => Volume(
  seriesOpdsId: 7,
  title: 'Sync Me',
  fileName: 'sync-me.epub',
  downloadUrl: 'http://unused/sync-me.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 6, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Records every document written to the fake iCloud container.
  late Map<String, String> written;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    written = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_docs, (call) async {
          if (call.method == 'write') {
            final args = (call.arguments as Map).cast<String, Object?>();
            written[args['name'] as String] = args['value'] as String;
            return true;
          }
          if (call.method == 'read') return null;
          return null;
        });
  });

  tearDown(() {
    CloudSyncService().cancelPendingTimers();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_docs, null);
  });

  test('flushReadingProgress writes the position to iCloud immediately', () async {
    await ReadingProgressStore().save(
      _volume(),
      const ReadingProgress(
        chapterIndex: 60,
        blockIndex: 3,
        chapterCount: 120,
      ),
    );

    // The save armed only a 3-second debounce — nothing has reached the cloud.
    expect(
      written,
      isEmpty,
      reason: 'the ordinary save must not push synchronously',
    );

    await CloudSyncService().flushReadingProgress();

    // Now the freshest position is in the cloud document.
    expect(written.keys, contains('cloud_reading_progress.json'));
    final blob = jsonDecode(written['cloud_reading_progress.json']!) as Map;
    final entry = blob['7/sync-me.epub'] as Map;
    expect(entry['chapterIndex'], 60);
    expect(entry['blockIndex'], 3);
  });

  test('flushActivity writes the reading ledger to iCloud immediately', () async {
    await ReadingActivityStore().record(
      _volume(),
      const Duration(minutes: 12),
      words: 2400,
    );

    // record() armed only the 5-second debounce — nothing pushed yet.
    expect(
      written,
      isEmpty,
      reason: 'recording activity must not push synchronously',
    );

    await CloudSyncService().flushActivity();

    expect(written.keys, contains('cloud_activity.json'));
    expect(written['cloud_activity.json'], isNotEmpty);
  });

  test('flush cancels the pending debounce so it does not double-push', () async {
    await ReadingProgressStore().save(
      _volume(),
      const ReadingProgress(chapterIndex: 12, blockIndex: 0, chapterCount: 120),
    );
    await CloudSyncService().flushReadingProgress();
    expect(written, hasLength(1));

    written.clear();
    // Let the original 3-second debounce window elapse. Because flush cancelled
    // it, no second write should land.
    await Future<void>.delayed(const Duration(seconds: 4));
    expect(
      written,
      isEmpty,
      reason: 'the cancelled debounce must not fire a redundant push',
    );
  });
}
