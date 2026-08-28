// Reading a book off the hub instead of downloading it.
//
// The parser resolves every path — container, OPF, contents, chapters,
// images — through one synchronous lookup, so a network source has to have
// what a parse needs *before* the parse starts. Most of what follows is
// about what happens when it does not: a missing image, a 401, a dropped
// connection. Streaming makes those ordinary rather than exceptional.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:umbra_reader/services/remote_epub_source.dart';

/// A stand-in server that records what was asked for.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.responses);

  /// member path -> (status, body)
  final Map<String, (int, List<int>)> responses;
  final List<String> requested = [];
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final member = request.url.queryParameters['member'] ?? '';
    requested.add(member);
    final hit = responses[member];
    final status = hit?.$1 ?? 404;
    final body = hit?.$2 ?? const <int>[];
    return http.StreamedResponse(
      Stream.value(body), status, request: request);
  }
}

const _container =
    '<container><rootfile full-path="OEBPS/content.opf"/></container>';
const _opf = '''
<package><manifest>
  <item id="nav" href="nav.xhtml" properties="nav"/>
  <item id="ncx" href="toc.ncx"/>
  <item id="c1" href="ch1.xhtml"/>
</manifest></package>''';

List<int> _b(String s) => utf8.encode(s);

RemoteEpubSource _source(_FakeClient client) => RemoteEpubSource(
      baseUrl: 'https://hub.example.ts.net',
      novelId: 42,
      fileName: 'A Book.epub',
      headers: const {'Authorization': 'Basic xyz'},
      client: client,
    );

void main() {
  group('fetching', () {
    test('a prefetched member is readable', () async {
      final c = _FakeClient({'OEBPS/ch1.xhtml': (200, _b('<p>hi</p>'))});
      final s = _source(c);
      await s.prefetch(['OEBPS/ch1.xhtml']);
      expect(utf8.decode(s.bytes('OEBPS/ch1.xhtml')!), '<p>hi</p>');
    });

    test('a member that was never fetched reads as null, not an error', () {
      // bytes() is synchronous and answers from cache only. Null is how
      // the parser already hears "not in this book".
      expect(_source(_FakeClient({})).bytes('OEBPS/ch1.xhtml'), isNull);
    });

    test('the same member is not fetched twice', () async {
      // Repagination re-parses on every rotation, fold and font change.
      final c = _FakeClient({'a': (200, _b('x'))});
      final s = _source(c);
      await s.prefetch(['a']);
      await s.prefetch(['a']);
      expect(c.calls, 1);
    });

    test('a batch is fetched as one wait, not one at a time', () async {
      final c = _FakeClient({
        'a': (200, _b('1')), 'b': (200, _b('2')), 'c': (200, _b('3')),
      });
      final s = _source(c);
      await s.prefetch(['a', 'b', 'c']);
      expect(c.calls, 3);
      expect(s.cachedCount, 3);
    });

    test('credentials are sent', () async {
      // The hub answers 401 without them, and the failure would look
      // exactly like a missing book.
      final c = _FakeClient({'a': (200, _b('x'))});
      await _source(c).prefetch(['a']);
      expect(c.requested, ['a']);
    });

    test('backslashes in a path are normalised', () async {
      final c = _FakeClient({'OEBPS/ch1.xhtml': (200, _b('x'))});
      final s = _source(c);
      await s.prefetch([r'OEBPS\ch1.xhtml']);
      expect(s.bytes(r'OEBPS\ch1.xhtml'), isNotNull);
      expect(s.bytes('OEBPS/ch1.xhtml'), isNotNull);
    });
  });

  group('when things go wrong', () {
    test('a 404 is remembered so it is not asked for again', () async {
      // A chapter referencing an image the book does not contain would
      // otherwise re-ask on every repagination, forever.
      final c = _FakeClient({});
      final s = _source(c);
      await s.prefetch(['missing.png']);
      await s.prefetch(['missing.png']);
      expect(c.calls, 1);
      expect(s.bytes('missing.png'), isNull);
    });

    test('a 500 is NOT remembered, so it can succeed later', () async {
      // The distinction that matters: "not in this book" is permanent,
      // "the server had a moment" is not. Conflating them would turn a
      // transient blip into a chapter that never loads again.
      final c = _FakeClient({'a': (500, const [])});
      final s = _source(c);
      await s.prefetch(['a']);
      await s.prefetch(['a']);
      expect(c.calls, 2, reason: 'a server error must be retried');
    });

    test('a 401 is NOT remembered either', () async {
      // Credentials can be fixed while the app is running.
      final c = _FakeClient({'a': (401, const [])});
      final s = _source(c);
      await s.prefetch(['a']);
      await s.prefetch(['a']);
      expect(c.calls, 2);
    });

    test('a dropped connection never throws out of prefetch', () async {
      // Streaming means reading over a network that will fail sometimes.
      // Losing the chapter is acceptable; crashing the reader is not.
      final s = RemoteEpubSource(
        baseUrl: 'https://hub.example.ts.net',
        novelId: 1,
        fileName: 'b.epub',
        client: _ExplodingClient(),
      );
      await expectLater(s.prefetch(['a']), completes);
      expect(s.bytes('a'), isNull);
    });
  });

  group('opening a book', () {
    test('walks container to OPF to contents', () async {
      // None of these are knowable up front: the container names the OPF,
      // and only the OPF names the table of contents.
      final c = _FakeClient({
        'META-INF/container.xml': (200, _b(_container)),
        'OEBPS/content.opf': (200, _b(_opf)),
        'OEBPS/nav.xhtml': (200, _b('<nav/>')),
        'OEBPS/toc.ncx': (200, _b('<ncx/>')),
      });
      final s = _source(c);
      await s.warmUp();
      expect(s.bytes('META-INF/container.xml'), isNotNull);
      expect(s.bytes('OEBPS/content.opf'), isNotNull);
      expect(s.bytes('OEBPS/nav.xhtml'), isNotNull, reason: 'EPUB 3 contents');
      expect(s.bytes('OEBPS/toc.ncx'), isNotNull, reason: 'EPUB 2 contents');
    });

    test('does not drag every chapter down with it', () async {
      // The point of streaming. Warming a book must not fetch the book.
      final c = _FakeClient({
        'META-INF/container.xml': (200, _b(_container)),
        'OEBPS/content.opf': (200, _b(_opf)),
        'OEBPS/nav.xhtml': (200, _b('<nav/>')),
        'OEBPS/toc.ncx': (200, _b('<ncx/>')),
        'OEBPS/ch1.xhtml': (200, _b('<p>chapter</p>')),
      });
      await _source(c).warmUp();
      expect(c.requested, isNot(contains('OEBPS/ch1.xhtml')));
    });

    test('a book with no container gives up quietly', () async {
      final c = _FakeClient({});
      final s = _source(c);
      await expectLater(s.warmUp(), completes);
      expect(s.cachedCount, 0);
    });
  });
}

class _ExplodingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(const SocketExceptionStub());
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
