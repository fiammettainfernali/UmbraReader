// The computer as this phone's cloud. A local server plays the computer, and
// keeps whatever it is sent last, as the real one does.
//
// The one way to lose data here is a phone sending before it has read: a
// fresh install's nearly empty stores would replace the backup of the old
// ones. Most of these tests are about that.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/cloud_sync_service.dart';
import 'package:umbra_reader/services/pc_sync_backend.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/settings_service.dart';
import 'package:umbra_reader/services/sync_backend.dart';

import 'helpers/test_db.dart';

class _Computer {
  final Map<String, String> blobs = {};
  final List<String> requests = [];
  bool refuseWrites = false;
  late HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      requests.add('${request.method} $path');
      final response = request.response..headers.contentType = ContentType.json;
      const prefix = '/api/sync/';
      if (path.startsWith(prefix)) {
        final key = path.substring(prefix.length);
        if (request.method == 'GET') {
          final value = blobs[key];
          if (value == null) {
            response.statusCode = HttpStatus.notFound;
            response.write(jsonEncode({'error': 'nothing kept under that name'}));
          } else {
            response.write(jsonEncode({'key': key, 'value': value, 'savedAt': '2026-11-17'}));
          }
        } else if (refuseWrites) {
          response.statusCode = HttpStatus.internalServerError;
        } else {
          blobs[key] = await utf8.decoder.bind(request).join();
          response.write(jsonEncode({'ok': true}));
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  }
}

Volume _volume(int id) => Volume(
  seriesOpdsId: id,
  title: 'Backup Test $id',
  fileName: 'backup-test-$id.epub',
  downloadUrl: 'http://unused/backup-test-$id.epub',
  fileSizeBytes: 0,
  updatedAt: DateTime.utc(2026, 11, 1),
);

Future<void> _readTo(int id, int chapter) => ReadingProgressStore().save(
  _volume(id),
  ReadingProgress(chapterIndex: chapter, blockIndex: 0, chapterCount: 120),
);

Future<int> _chapterOf(int id) async => (await ReadingProgressStore().load(_volume(id))).chapterIndex;

void main() {
  late _Computer computer;
  late OpdsSettings settings;
  final sync = CloudSyncService();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    computer = _Computer();
    await computer.start();
    settings = OpdsSettings(
      baseUrl: 'http://127.0.0.1:${computer.server.port}',
      username: 'me',
      password: 'pw',
    );
    sync.backend = PcSyncBackend(settings: () async => settings);
  });

  tearDown(() async {
    sync.cancelPendingTimers();
    sync.backend = SyncBackend.forPlatform();
    await computer.server.close(force: true);
    await AppDatabase.reset();
  });

  /// The computer holding an older install's place in volume 1.
  Future<void> computerHoldsAnOldInstall() async {
    await _readTo(1, 88);
    await sync.flushReadingProgress();
    computer.blobs['cloud_reading_progress'] = await ReadingProgressStore().exportSyncBlob();
    await useInMemoryDatabase();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  }

  test('a fresh phone sends nothing until it has read the backup', () async {
    await computerHoldsAnOldInstall();
    final backup = computer.blobs['cloud_reading_progress'];

    await _readTo(2, 5);
    await sync.flushReadingProgress();

    expect(computer.blobs['cloud_reading_progress'], backup,
        reason: "the new install's places replaced the backup of the old ones");
    expect(await sync.backend.needsFullPush(), isTrue);
  });

  test('the first pull brings the backup back, and then everything goes up', () async {
    await computerHoldsAnOldInstall();
    await _readTo(2, 5);

    await sync.catchUp();

    expect(await _chapterOf(1), 88, reason: 'the backup did not come back');
    final kept = computer.blobs['cloud_reading_progress']!;
    expect(kept, contains('backup-test-1'));
    expect(kept, contains('backup-test-2'), reason: "this phone's own place never reached the computer");
    expect(computer.blobs.keys, containsAll(['cloud_bookmarks', 'cloud_activity', 'cloud_collections']));
    expect(await sync.backend.needsFullPush(), isFalse);
  });

  test('once caught up, each change goes straight to the computer', () async {
    await sync.catchUp();
    await _readTo(3, 40);
    await sync.flushReadingProgress();
    expect(computer.blobs['cloud_reading_progress'], contains('backup-test-3'));
  });

  test('a send that fails leaves it behind, and the next catch-up sends it all', () async {
    await sync.catchUp();
    computer.refuseWrites = true;
    await _readTo(4, 12);
    await sync.flushReadingProgress();
    expect(await sync.backend.needsFullPush(), isTrue);

    computer.refuseWrites = false;
    await sync.catchUp();
    expect(computer.blobs['cloud_reading_progress'], contains('backup-test-4'));
    expect(await sync.backend.needsFullPush(), isFalse);
  });

  test('a store never used sends nothing, and that is not a failure', () async {
    // Saved views export '' until one is made. The computer would refuse
    // it, and a refusal counted as a failure re-sent everything on every
    // return to the app.
    await sync.catchUp();
    expect(computer.blobs, isNot(contains('cloud_saved_views')));
    expect(computer.requests.where((r) => r == 'POST /api/sync/cloud_saved_views'), isEmpty);
    expect(await sync.backend.needsFullPush(), isFalse);
  });

  test('caught up, coming back to the app asks the computer nothing', () async {
    await sync.catchUp();
    computer.requests.clear();
    await sync.catchUp();
    expect(computer.requests, isEmpty);
  });

  test('a computer out of reach changes nothing on the phone and throws nothing', () async {
    await _readTo(5, 30);
    await computer.server.close(force: true);
    await sync.catchUp();
    expect(await _chapterOf(5), 30);
    expect(await sync.backend.needsFullPush(), isTrue);
  });

  test('a pull that could not read everything does not open the gate', () async {
    await computerHoldsAnOldInstall();
    await computer.server.close(force: true);
    await sync.pullAndMerge();
    expect(await AppDatabase.instance.kvGet(PcSyncBackend.kPulled), isNull);
  });

  test('with no computer set up, nothing is asked', () async {
    settings = OpdsSettings(baseUrl: '', username: '', password: '');
    await _readTo(6, 2);
    await sync.flushReadingProgress();
    await sync.catchUp();
    expect(computer.requests, isEmpty);
    expect(await sync.backend.needsFullPush(), isFalse);
  });
}
