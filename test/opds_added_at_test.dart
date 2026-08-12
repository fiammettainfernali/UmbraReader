// Tests that the add date survives the trip from Novel Grabber's feed.
//
// The "recently added" shelf sorts on a field that crosses two codebases
// and a JSON cache. Each half can be right on its own while the join is
// wrong — a namespace prefix that doesn't match, a field parsed but never
// passed to the constructor — so this pins the join with the literal XML
// the server emits.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/opds_client.dart';
import 'package:umbra_reader/services/settings_service.dart';

/// The shape of a real entry from `build_all_novels_feed`, trimmed to the
/// elements under test.
String _feed(String extra) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:dc="http://purl.org/dc/elements/1.1/"
      xmlns:ng="http://novel-grabber.local/">
  <id>urn:novel-grabber:all</id>
  <title>All Books</title>
  <entry>
    <title>Guiding Hands</title>
    <id>urn:novel-grabber:novel:434</id>
    <author><name>Someone</name></author>
    <updated>2026-08-11T23:33:00Z</updated>
    <summary>A summary.</summary>
    <ng:readingStatus>ongoing</ng:readingStatus>
    <ng:chapters total="340" downloaded="12"/>
$extra  </entry>
</feed>
''';

OpdsClient _client() => OpdsClient(
  const OpdsSettings(baseUrl: 'http://x', username: '', password: ''),
);

void main() {
  test('ng:addedAt reaches the model', () {
    final series = _client().parseLibraryFeed(
      _feed('    <ng:addedAt>2026-04-17T09:30:00Z</ng:addedAt>\n'),
    );
    expect(series, hasLength(1));
    expect(series.single.addedAt, DateTime.utc(2026, 4, 17, 9, 30));
  });

  test('added and updated are read independently', () {
    // They come from different sources on the server — the database and
    // EPUB mtime — and the shelves would be interchangeable if these were
    // ever crossed.
    final series = _client()
        .parseLibraryFeed(
          _feed('    <ng:addedAt>2026-04-17T09:30:00Z</ng:addedAt>\n'),
        )
        .single;
    expect(series.addedAt, isNot(series.updatedAt));
    expect(series.updatedAt, DateTime.utc(2026, 8, 11, 23, 33));
  });

  test('an older server that omits it still parses', () {
    // Novel Grabber only gained ng:addedAt alongside this shelf; a feed
    // from before it must not lose the entry.
    final series = _client().parseLibraryFeed(_feed(''));
    expect(series, hasLength(1));
    expect(series.single.addedAt, isNull);
    expect(series.single.title, 'Guiding Hands');
  });

  test('a malformed date is null rather than an exception', () {
    final series = _client().parseLibraryFeed(
      _feed('    <ng:addedAt>17/04/2026</ng:addedAt>\n'),
    );
    expect(series.single.addedAt, isNull);
  });
}
