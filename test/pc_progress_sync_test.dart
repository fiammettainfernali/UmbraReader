// Reading places between the phone and the computer: newest wins, each side
// keeps its own, and nothing is sent twice. A local server plays the computer.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/library_cache.dart';
import 'package:umbra_reader/services/library_storage.dart';
import 'package:umbra_reader/services/pc_progress_sync.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/settings_service.dart';

import 'helpers/test_db.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// The computer's side of it.
class _Computer {
  List<Map<String, dynamic>> places = [];
  final List<Map<String, dynamic>> received = [];
  Map<String, dynamic> answer = {'applied': true};
  late HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response..headers.contentType = ContentType.json;
      if (request.uri.path == '/api/progress' && request.method == 'GET') {
        response.write(jsonEncode({'now': '2026-11-09T12:00:00+00:00', 'novels': places}));
      } else if (request.uri.path == '/api/progress' && request.method == 'POST') {
        received.add(jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>);
        response.write(jsonEncode(answer));
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  }
}

const _file = 'The Road Volume 01.epub';
final _volume = Volume(
  seriesOpdsId: 7,
  title: 'The Road — Volume 1',
  fileName: _file,
  downloadUrl: 'http://pc/opds/download/7/$_file',
  fileSizeBytes: 1000,
  updatedAt: DateTime(2026, 11, 1),
);

void main() {
  late Directory tempDir;
  late _Computer computer;
  late OpdsSettings settings;
  final store = ReadingProgressStore();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
    tempDir = Directory.systemTemp.createTempSync('umbra_pc_sync');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    await cache.saveVolumes(7, [_volume]);
    computer = _Computer();
    await computer.start();
    settings = OpdsSettings(
      baseUrl: 'http://127.0.0.1:${computer.server.port}',
      username: 'me',
      password: 'pw',
    );
  });

  tearDown(() async {
    await computer.server.close(force: true);
    await AppDatabase.reset();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold handles briefly; leaking a temp dir is harmless.
    }
  });

  Map<String, dynamic> place(String at, {String path = 'chapter_0003.xhtml', double share = 0.4}) =>
      {'novel': 7, 'chapter': 3, 'share': share, 'at': at, 'file': _file, 'path': path};

  test('a place read on the computer is taken, at the time it was read there', () async {
    computer.places = [place('2026-11-09T10:00:00+00:00')];
    expect(await PcProgressSync.instance.sync(settings), isTrue);
    final saved = await store.load(_volume);
    expect(saved.chapterPath, 'chapter_0003.xhtml');
    expect(saved.chapterIndex, 2);
    expect(saved.updatedAt!.toUtc(), DateTime.utc(2026, 11, 9, 10));
    expect(await store.takeIncomingShare(_volume, 'EPUB/chapter_0003.xhtml'), 0.4);
    expect(await store.takeIncomingShare(_volume, 'EPUB/chapter_0003.xhtml'), isNull,
        reason: 'used once, then the reader keeps its own place');
    expect(computer.received, isEmpty, reason: 'nothing to send back');
  });

  test('a place read here goes to the computer, once', () async {
    await store.save(
      _volume,
      const ReadingProgress(chapterIndex: 1, blockIndex: 5, chapterPath: 'EPUB/chapter_0002.xhtml', chapterCount: 9),
      share: 0.25,
    );
    await PcProgressSync.instance.sync(settings);
    expect(computer.received, hasLength(1));
    expect(computer.received.single['novel'], 7);
    expect(computer.received.single['file'], _file);
    expect(computer.received.single['path'], 'EPUB/chapter_0002.xhtml');
    expect(computer.received.single['share'], 0.25);
    await PcProgressSync.instance.sync(settings);
    expect(computer.received, hasLength(1), reason: 'already sent');
  });

  test("an older place from the computer doesn't move a newer one here", () async {
    await store.save(
      _volume,
      const ReadingProgress(chapterIndex: 4, blockIndex: 2, chapterPath: 'EPUB/chapter_0005.xhtml', chapterCount: 9),
      share: 0.5,
    );
    computer.places = [place('2001-01-01T00:00:00+00:00')];
    expect(await PcProgressSync.instance.sync(settings), isFalse);
    expect((await store.load(_volume)).chapterPath, 'EPUB/chapter_0005.xhtml');
    expect(computer.received, hasLength(1), reason: 'and the newer one goes to the computer');
  });

  test("when the computer's is newer after all, it answers with it and that is taken", () async {
    await store.save(
      _volume,
      const ReadingProgress(chapterIndex: 0, blockIndex: 3, chapterPath: 'EPUB/chapter_0001.xhtml', chapterCount: 9),
      share: 0.1,
    );
    computer.answer = {'applied': false, 'newer': place('2099-01-01T00:00:00+00:00', path: 'chapter_0008.xhtml')};
    expect(await PcProgressSync.instance.sync(settings), isTrue);
    expect((await store.load(_volume)).chapterPath, 'chapter_0008.xhtml');
  });

  test('a computer that cannot be reached is simply tried next time', () async {
    await computer.server.close(force: true);
    expect(await PcProgressSync.instance.sync(settings), isFalse);
  });

  test('chapter paths match with or without the book\'s folder', () {
    expect(ReadingProgressStore.samePath('EPUB/chapter_0007.xhtml', 'chapter_0007.xhtml'), isTrue);
    expect(ReadingProgressStore.samePath('chapter_0007.xhtml', 'OEBPS/chapter_0007.xhtml'), isTrue);
    expect(ReadingProgressStore.samePath('EPUB/chapter_0007.xhtml', 'chapter_0017.xhtml'), isFalse);
  });
}
