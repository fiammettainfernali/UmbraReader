// Tests for the client side of duplicate prevention: the 409 the server
// sends when it already has a URL, the lookup used to warn while browsing,
// and the event carrying a same-story warning that can only be judged
// after the server has fetched the page.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/control_client.dart';

void main() {
  group('DuplicateMatch', () {
    test('parses the server payload', () {
      final m = DuplicateMatch.fromJson(const {
        'novelId': 7,
        'title': 'The Primal Hunter',
        'sourceSite': 'novgo',
        'sourceUrl': 'https://novgo.net/primal.html',
        'totalChapters': 1366,
        'similarity': 0.93,
      });
      expect(m.novelId, 7);
      expect(m.title, 'The Primal Hunter');
      expect(m.sourceSite, 'novgo');
      expect(m.totalChapters, 1366);
      expect(m.similarity, closeTo(0.93, 1e-9));
    });

    test('missing fields degrade rather than throw', () {
      final m = DuplicateMatch.fromJson(const {});
      expect(m.novelId, 0);
      expect(m.title, isEmpty);
      expect(m.similarity, 0);
    });
  });

  group('NovelLookup', () {
    test('a known URL carries the novel', () {
      final l = NovelLookup.fromJson(const {
        'known': true,
        'novel': {'novelId': 7, 'title': 'Shadow Slave'},
      });
      expect(l.known, isTrue);
      expect(l.novel?.title, 'Shadow Slave');
    });

    test('an unknown URL has no novel', () {
      final l = NovelLookup.fromJson(const {'known': false, 'novel': null});
      expect(l.known, isFalse);
      expect(l.novel, isNull);
    });
  });

  group('DuplicateNovelException', () {
    test('a url reason is the same-page case', () {
      final e = DuplicateNovelException('already have it', const [], 'url');
      expect(e.isSameUrl, isTrue);
    });

    test('a title reason is the different-source case', () {
      final e = DuplicateNovelException('looks the same', const [], 'title');
      expect(e.isSameUrl, isFalse);
    });

    test('it is still a ControlException, so existing catches hold', () {
      // Callers that only know about ControlException must not break.
      expect(
        DuplicateNovelException('x', const [], 'url'),
        isA<ControlException>(),
      );
    });
  });

  group('the duplicate event', () {
    ControlEvent event(Map<String, dynamic> raw) =>
        ControlEvent(raw['type'] as String? ?? '', raw);

    test('decodes matches from the stream payload', () {
      final e = event(
        jsonDecode('''
        {"type":"duplicate","data":{
          "url":"https://other.site/x.html",
          "title":"The Primal Hunter",
          "reason":"title",
          "matches":[{"novelId":7,"title":"The Primal Hunter",
                      "sourceSite":"novgo","sourceUrl":"https://novgo.net/p.html",
                      "totalChapters":1366,"similarity":1.0}]}}
        ''')
            as Map<String, dynamic>,
      );
      final d = e.duplicate;
      expect(d, isNotNull);
      expect(d!.reason, 'title');
      expect(d.title, 'The Primal Hunter');
      expect(d.url, 'https://other.site/x.html');
      expect(d.matches.single.novelId, 7);
    });

    test('other event types carry no duplicate', () {
      expect(event(const {'type': 'progress', 'data': {}}).duplicate, isNull);
      expect(event(const {'type': 'queue'}).duplicate, isNull);
    });

    test('a malformed duplicate event is ignored rather than fatal', () {
      // No data at all, or data that isn't a string-keyed object, reads as
      // "no duplicate information" rather than throwing on the cast.
      expect(event(const {'type': 'duplicate'}).duplicate, isNull);
      expect(event(const {'type': 'duplicate', 'data': 42}).duplicate, isNull);
      expect(
        event(const {'type': 'duplicate', 'data': <int, String>{}}).duplicate,
        isNull,
      );
    });

    test('a well-formed event with no matches offers nothing', () {
      final d = event(const {
        'type': 'duplicate',
        'data': <String, dynamic>{'title': 'X'},
      }).duplicate;
      expect(d, isNotNull);
      expect(d!.matches, isEmpty, reason: 'nothing to offer, so nothing shown');
    });
  });
}
