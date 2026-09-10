// Asking followed sites whether anything new has appeared.
//
// The properties under test are the ones the Continue shelf had to learn
// the hard way: this talks to sites that may be unreachable, one request
// each, and away from a good connection those do not fail fast. So it is
// capped, it does not re-ask a site it asked an hour ago, and nothing it
// touches can throw.
//
// The fake here is an http client rather than a fake metadata reader, so
// each test runs the real fetch and the real parse as well as the refresh.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/services/web_series_metadata.dart';
import 'package:umbra_reader/services/web_series_refresh.dart';
import 'package:umbra_reader/services/web_series_store.dart';

import 'helpers/test_db.dart';

String _url(int n) => 'https://example.org/series/story-$n';

/// A series page offering chapters up to [latest].
String _page(int n, double latest) =>
    '''
<html><head>
<meta property="og:title" content="Story $n"/>
<meta property="og:image" content="https://cdn.example.org/$n.webp"/>
</head><body>
<a href="${Uri.parse(_url(n)).path}/chapter-1">1</a>
<a href="${Uri.parse(_url(n)).path}/chapter-${latest.round()}">latest</a>
</body></html>''';

/// Serves the pages it was given, and counts what was asked for.
class _Sites extends http.BaseClient {
  _Sites(this.pages);
  final Map<String, String> pages;
  final List<String> asked = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    asked.add(url);
    final body = pages[url];
    if (body == null) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        404,
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}

/// A site that is not there — the away-from-home case.
class _Dead extends http.BaseClient {
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    return Future.error(const SocketishException());
  }
}

class SocketishException implements Exception {
  const SocketishException();
}

void main() {
  late WebSeriesStore store;

  setUp(() async {
    await useInMemoryDatabase();
    store = WebSeriesStore();
  });

  tearDown(AppDatabase.reset);

  WebSeriesRefresh refresher(http.Client client) => WebSeriesRefresh(
    store: store,
    metadata: WebSeriesMetadata(client: client),
  );

  test('a series that has grown is noticed', () async {
    await store.follow(url: _url(1), title: 'Story 1');
    await store.notePosition(
      seriesUrl: _url(1),
      chapterUrl: '${_url(1)}/chapter-212',
    );

    final sites = _Sites({_url(1): _page(1, 260)});
    final learned = await refresher(sites).run(await store.all());

    expect(learned, 1);
    final after = (await store.find(_url(1)))!;
    expect(after.latestChapter, 260);
    expect(after.hasUnread, isTrue);
    expect(after.unreadCount, 48);
    // And the cover it did not have before.
    expect(after.coverUrl, 'https://cdn.example.org/1.webp');
  });

  test('a series that has not grown is not news', () async {
    await store.follow(url: _url(1), title: 'Story 1');
    await store.noteCheck(
      _url(1),
      const WebSeriesInfo(latestChapterNumber: 260),
    );
    final fresh = await store.all();

    // Force it past the staleness gate so the request is actually made.
    final sites = _Sites({_url(1): _page(1, 260)});
    final learned = await refresher(
      sites,
    ).run(fresh, now: DateTime.now().toUtc().add(const Duration(days: 1)));

    expect(sites.asked, hasLength(1));
    expect(learned, 0);
  });

  test('a site asked an hour ago is not asked again', () async {
    await store.follow(url: _url(1), title: 'Story 1');
    await store.noteCheck(_url(1), const WebSeriesInfo(latestChapterNumber: 9));

    final sites = _Sites({_url(1): _page(1, 260)});
    final learned = await refresher(sites).run(await store.all());

    expect(sites.asked, isEmpty, reason: 'it re-asked a site it just asked');
    expect(learned, 0);
  });

  test('it will not speak to a whole shelf in one pass', () async {
    // Forty followed comics must not answer a pull-to-refresh with forty
    // requests before anything can be drawn.
    expect(WebSeriesRefresh.maxPerPass, lessThanOrEqualTo(10));
    expect(WebSeriesRefresh.maxPerPass, greaterThan(0));

    final pages = <String, String>{};
    for (var n = 0; n < 20; n++) {
      await store.follow(url: _url(n), title: 'Story $n');
      pages[_url(n)] = _page(n, 100);
    }
    final sites = _Sites(pages);
    await refresher(sites).run(await store.all());

    expect(sites.asked, hasLength(WebSeriesRefresh.maxPerPass));
  });

  test('the least recently asked go first', () async {
    // Enough series that the cap bites, with one that has never been
    // checked at all. That one must not wait behind ones that have.
    final pages = <String, String>{};
    for (var n = 0; n < 12; n++) {
      await store.follow(url: _url(n), title: 'Story $n');
      pages[_url(n)] = _page(n, 100);
      // Every one but the last has been asked before.
      if (n < 11) {
        await store.noteCheck(
          _url(n),
          const WebSeriesInfo(latestChapterNumber: 50),
        );
      }
    }
    final sites = _Sites(pages);
    await refresher(sites).run(
      await store.all(),
      now: DateTime.now().toUtc().add(const Duration(days: 1)),
    );

    expect(sites.asked.first, _url(11));
  });

  test('an unreachable site changes nothing and raises nothing', () async {
    await store.follow(url: _url(1), title: 'Story 1');
    await store.notePosition(
      seriesUrl: _url(1),
      chapterUrl: '${_url(1)}/chapter-5',
    );

    final dead = _Dead();
    final learned = await refresher(dead).run(await store.all());

    expect(dead.calls, 1);
    expect(learned, 0);
    final after = (await store.find(_url(1)))!;
    expect(after.latestChapter, isNull);
    // Not marked as checked, so the next pass will try again rather than
    // treating silence as an answer.
    expect(after.checkedAt, isNull);
    // And the place you had is untouched.
    expect(after.readChapter, 5);
  });

  test('a page that has moved changes nothing', () async {
    await store.follow(url: _url(1), title: 'Story 1');
    final sites = _Sites(const {}); // every request 404s
    final learned = await refresher(sites).run(await store.all());
    expect(learned, 0);
    expect((await store.find(_url(1)))!.checkedAt, isNull);
  });

  test('a page it can fetch but not understand is left alone', () async {
    await store.follow(url: _url(1), title: 'Story 1');
    final sites = _Sites({_url(1): '<html></html>'});
    final learned = await refresher(sites).run(await store.all());
    expect(learned, 0);
    expect((await store.find(_url(1)))!.checkedAt, isNull);
  });

  test('nothing followed is no work at all', () async {
    final dead = _Dead();
    expect(await refresher(dead).run(const []), 0);
    expect(dead.calls, 0);
  });
}
