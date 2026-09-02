// Keeping a streamed book's chapter count current on the shelf.
//
// A downloaded volume learns its own size: downloading it re-reads the EPUB
// and writes the count. A streamed one is never downloaded, so nothing
// re-reads it — the shelf went on saying "Chapter 12 of 76" after the book
// had grown, until it was opened, which is the one thing the shelf exists
// to save you.
//
// The feed's own count cannot stand in: it counts the novel's chapters,
// while the reader counts spine entries, and a compiled book has one more
// of those than it has chapters — a front-matter page. Measured against a
// real library: catalogue_total = chapter files, spine = chapter files + 1,
// on every book checked. A denominator off by one from the reader's own
// display is a different bug, not a fix.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/library_storage.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';
import 'package:umbra_reader/services/settings_service.dart';
import 'package:umbra_reader/services/streamed_count_refresh.dart';

import 'helpers/test_db.dart';

Volume _volume({String fileName = 'book.epub'}) => Volume(
  seriesOpdsId: 7,
  title: 'A Book',
  fileName: fileName,
  downloadUrl: 'https://hub.example/epub/7/$fileName',
  fileSizeBytes: 1000,
  updatedAt: DateTime.utc(2026, 5, 1),
);

Series _series({required DateTime? updatedAt}) => Series(
  opdsId: 7,
  title: 'A Book',
  author: '',
  description: '',
  genres: const [],
  readingStatus: 'ongoing',
  totalChapters: 0,
  downloadedChapters: 0,
  updatedAt: updatedAt,
  coverUrl: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

const _container =
    '<container><rootfile full-path="OEBPS/content.opf"/></container>';

/// An OPF whose spine has [n] entries.
String _opf(int n) {
  final items = [
    for (var i = 0; i < n; i++)
      '<item id="c$i" href="ch$i.xhtml" media-type="application/xhtml+xml"/>',
  ].join();
  final refs = [for (var i = 0; i < n; i++) '<itemref idref="c$i"/>'].join();
  return '<package><manifest>$items</manifest><spine>$refs</spine></package>';
}

/// Serves a book with [spine] entries, and counts what was asked for.
class _Hub extends http.BaseClient {
  _Hub(this.spine);
  final int spine;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final member = request.url.queryParameters['member'] ?? '';
    final body = switch (member) {
      'META-INF/container.xml' => _container,
      'OEBPS/content.opf' => _opf(spine),
      _ => null,
    };
    if (body == null) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(), 404, request: request);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)), 200, request: request);
  }
}

/// A device that already holds every volume — the state a downloaded
/// library is in, and the one where reaching for the server costs most.
class _AllDownloaded extends DownloadStore {
  _AllDownloaded() : super(LibraryStorage());

  @override
  bool isDownloaded(Volume volume) => true;
}

/// A hub that is not there.
class _Dead extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(const _Unreachable());
}

class _Unreachable implements Exception {
  const _Unreachable();
}

const _settings = OpdsSettings(
  baseUrl: 'https://hub.example',
  username: '',
  password: '',
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await useInMemoryDatabase();
  });

  tearDown(AppDatabase.reset);

  Future<ReadingEntry> seed({
    required int count,
    required DateTime savedAt,
    bool finished = false,
  }) async {
    final store = ReadingProgressStore();
    await store.save(
      _volume(),
      ReadingProgress(
        chapterIndex: 11,
        blockIndex: 3,
        chapterCount: count,
        endReached: finished,
      ),
    );
    final entries = await store.allEntries();
    return entries.single;
  }

  test('a grown book gets its new count', () async {
    final entry = await seed(count: 76, savedAt: DateTime.now());
    final hub = _Hub(82);
    final updated = await StreamedCountRefresh(
      settings: _settings,
      client: hub,
    ).run(
      [entry],
      [_series(updatedAt: DateTime.now().add(const Duration(hours: 1)))],
    );

    expect(updated, 1);
    final after = await ReadingProgressStore().load(_volume());
    expect(after.chapterCount, 82);
    // And the place in the book is kept: the new chapters are at the end.
    expect(after.chapterIndex, 11);
    expect(after.blockIndex, 3);
    // Two requests, not a download: container, then the package file.
    expect(hub.calls, 2);
  });

  test('a finished book that grew stops being finished', () async {
    // The count changing is what clears it, which save() already knows how
    // to do — so this needs no separate rule, and would break if one were
    // added.
    final entry =
        await seed(count: 76, savedAt: DateTime.now(), finished: true);
    expect(entry.progress.isFinished, isTrue);

    await StreamedCountRefresh(settings: _settings, client: _Hub(82)).run(
      [entry],
      [_series(updatedAt: DateTime.now().add(const Duration(hours: 1)))],
    );

    expect((await ReadingProgressStore().load(_volume())).isFinished, isFalse);
  });

  test('a book whose size has not changed is not rewritten', () async {
    final entry = await seed(count: 76, savedAt: DateTime.now());
    final updated = await StreamedCountRefresh(
      settings: _settings,
      client: _Hub(76),
    ).run(
      [entry],
      [_series(updatedAt: DateTime.now().add(const Duration(hours: 1)))],
    );
    expect(updated, 0);
  });

  test('a hub that cannot be reached changes nothing', () async {
    final entry = await seed(count: 76, savedAt: DateTime.now());
    final updated = await StreamedCountRefresh(
      settings: _settings,
      client: _Dead(),
    ).run(
      [entry],
      [_series(updatedAt: DateTime.now().add(const Duration(hours: 1)))],
    );
    expect(updated, 0);
    expect((await ReadingProgressStore().load(_volume())).chapterCount, 76);
  });

  test('a book that has not been rebuilt is left alone', () async {
    final entry = await seed(count: 76, savedAt: DateTime.now());
    final updated = await StreamedCountRefresh(settings: _settings).run(
      [entry],
      [_series(updatedAt: DateTime.now().subtract(const Duration(days: 2)))],
    );
    expect(updated, 0);
    expect((await ReadingProgressStore().load(_volume())).chapterCount, 76);
  });

  test('a series with no timestamp is left alone', () async {
    // A server that does not report one must not send the app measuring
    // every book on every refresh.
    final entry = await seed(count: 76, savedAt: DateTime.now());
    final updated = await StreamedCountRefresh(settings: _settings)
        .run([entry], [_series(updatedAt: null)]);
    expect(updated, 0);
  });

  test('an unread book is left alone', () async {
    // Nothing has been read, so no denominator is on screen to be wrong.
    final store = ReadingProgressStore();
    await store.save(
      _volume(),
      const ReadingProgress(chapterIndex: 0, blockIndex: 0, chapterCount: 76),
    );
    final entry = (await store.allEntries()).single;
    final updated = await StreamedCountRefresh(settings: _settings).run(
      [entry],
      [_series(updatedAt: DateTime.now().add(const Duration(hours: 1)))],
    );
    expect(updated, 0);
  });

  test('it will not measure a whole library in one pass', () async {
    // A refresh should not answer fifty recompiles with a hundred requests
    // before the shelf will draw.
    expect(StreamedCountRefresh.maxPerPass, lessThanOrEqualTo(10));
    expect(StreamedCountRefresh.maxPerPass, greaterThan(0));
  });

  group('it must never be on the critical path for the shelf', () {
    // The Continue shelf is built entirely from local stores. It went
    // missing off the home network because the library screen awaited this
    // refresher before drawing it: two requests per book, and away from
    // home they do not fail fast -- a connect timeout plus two retries
    // apiece, up to maxPerPass books. The shelf is now drawn first and this
    // runs after, so these guard the properties that make that safe.

    test('a downloaded book is never reached for over the network', () async {
      // The common case once a library is downloaded. If this asks the
      // server anything, an offline start pays for it.
      final entry = await seed(count: 76, savedAt: DateTime.now());
      final hub = _Hub(82);
      await StreamedCountRefresh(
        settings: _settings,
        downloads: _AllDownloaded(),
        client: hub,
      ).run(
        [entry],
        [_series(updatedAt: DateTime.now().add(const Duration(hours: 1)))],
      );
      expect(hub.calls, 0, reason: 'it touched the network for a local book');
    });

    test('an unreachable server costs nothing and changes nothing', () async {
      final entry = await seed(count: 76, savedAt: DateTime.now());
      final updated = await StreamedCountRefresh(
        settings: _settings,
        client: _Dead(),
      ).run(
        [entry],
        [_series(updatedAt: DateTime.now().add(const Duration(hours: 1)))],
      );
      expect(updated, 0);
      expect((await ReadingProgressStore().load(_volume())).chapterCount, 76);
    });

    test('the library screen draws the shelf before calling this', () async {
      // Checked against the source: the ordering is the whole fix, and
      // nothing else in the file expresses it.
      final source =
          File('lib/screens/library_screen.dart').readAsStringSync();
      final drawn = source.indexOf('_reading = shelf(revived)');
      final refreshed = source.indexOf('StreamedCountRefresh(');
      expect(drawn, greaterThan(-1), reason: 'shelf assignment moved');
      expect(refreshed, greaterThan(-1), reason: 'refresher call moved');
      expect(drawn, lessThan(refreshed),
          reason: 'the shelf must be on screen before the network is asked');
    });

    test('downloads are loaded before the reading shelf', () async {
      // With no download store the refresher assumes nothing is local and
      // reaches for the network on behalf of books already on the device.
      final source =
          File('lib/screens/library_screen.dart').readAsStringSync();
      final init = source.substring(source.indexOf('Future<void> _initialize'));
      expect(init.indexOf('_loadDownloads()'),
          lessThan(init.indexOf('_loadReading()')),
          reason: 'downloads must be known before the shelf is built');
    });
  });
}
