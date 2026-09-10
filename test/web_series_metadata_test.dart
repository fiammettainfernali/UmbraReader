// Reading a series page for a cover, a title, and whether it has grown.
//
// The fixtures here mirror the shape of a real one rather than copying it:
// OpenGraph tags, a navigation full of links that are not chapters, and a
// chapter list that shows only the newest handful. That last detail is the
// one that matters — counting the links would say "26 chapters" about a
// series on its 260th, so the number has to come out of the slugs.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/web_series_metadata.dart';

final _series = Uri.parse('https://example.org/series/a-story-c6f3k3os');

String _page({
  String title = 'A Story',
  String? cover = 'https://cdn.example.org/cover.webp',
  List<String> chapters = const [],
  String extra = '',
}) =>
    '''
<html><head>
<meta property="og:title" content="$title"/>
${cover == null ? '' : '<meta property="og:image" content="$cover"/>'}
<title>$title - Example</title>
</head><body>
<nav><a href="/">Home</a><a href="/browse">Browse</a>
<a href="/series/another-story/chapter-999">Another Story ch.999</a></nav>
${chapters.map((c) => '<a href="${_series.path}/$c">$c</a>').join()}
$extra
</body></html>''';

void main() {
  test('it reads the title and cover a link preview would use', () {
    final info = WebSeriesMetadata.read(_page(), _series);
    expect(info.title, 'A Story');
    expect(info.coverUrl, 'https://cdn.example.org/cover.webp');
  });

  group('the cover', () {
    // og:image is a link-preview card on at least one of these sites — a
    // wide banner with the description written across it, which on a
    // portrait shelf card is a dark letterbox with a strip of text where
    // the artwork should be.
    const labelled =
        '<img alt="Cover of A Story" src="https://cdn.example.org/art.webp">';

    test('a labelled cover beats the link-preview image', () {
      final info = WebSeriesMetadata.read(
        _page(
          cover: 'https://example.org/api/og-image/a-story.webp',
          extra: labelled,
        ),
        _series,
      );
      expect(info.coverUrl, 'https://cdn.example.org/art.webp');
    });

    test('og:image is still used when nothing is labelled', () {
      final info = WebSeriesMetadata.read(_page(), _series);
      expect(info.coverUrl, 'https://cdn.example.org/cover.webp');
    });

    test('a relative cover is resolved against the series', () {
      final info = WebSeriesMetadata.read(
        _page(extra: '<img alt="Cover of A Story" src="/art/a.webp">'),
        _series,
      );
      expect(info.coverUrl, 'https://example.org/art/a.webp');
    });

    test('entities in the URL are decoded', () {
      // These come proxied, with query strings: ?w=400&amp;quality=100
      final info = WebSeriesMetadata.read(
        _page(
          extra:
              '<img alt="Cover of A Story" '
              'src="https://cdn.example.org/a.webp?w=400&amp;ssl=1">',
        ),
        _series,
      );
      expect(info.coverUrl, 'https://cdn.example.org/a.webp?w=400&ssl=1');
    });

    test('a lazily loaded image does not donate its data-src', () {
      // Asking for `src` without a boundary also matches `data-src`, which
      // is a different attribute holding a different URL.
      final info = WebSeriesMetadata.read(
        _page(
          extra:
              '<img alt="Cover of A Story" '
              'data-src="https://cdn.example.org/WRONG.webp" '
              'src="https://cdn.example.org/right.webp">',
        ),
        _series,
      );
      expect(info.coverUrl, 'https://cdn.example.org/right.webp');
    });

    test('an image that is not a cover is not taken for one', () {
      final info = WebSeriesMetadata.read(
        _page(extra: '<img alt="Vortex Scans logo" src="https://x/logo.webp">'),
        _series,
      );
      expect(info.coverUrl, 'https://cdn.example.org/cover.webp');
    });
  });

  test('it decodes entities in the title', () {
    // The real one is "Ranker&#x27;s Return", and an apostrophe in a title
    // is common enough that leaving it raw would be visible on the shelf.
    final info = WebSeriesMetadata.read(
      _page(title: 'Ranker&#x27;s Return &amp; Others'),
      _series,
    );
    expect(info.title, "Ranker's Return & Others");
  });

  test('the latest chapter comes from the slugs, not the link count', () {
    // A series page lists chapter 1 and then the newest few. Counting them
    // says 4; the series is on 260.
    final info = WebSeriesMetadata.read(
      _page(
        chapters: [
          'chapter-1-8mi19zhy',
          'chapter-258',
          'chapter-259',
          'chapter-260',
        ],
      ),
      _series,
    );
    expect(info.latestChapterNumber, 260);
    expect(info.latestChapterUrl, '${_series}/chapter-260');
  });

  test('a hashed slug is still a chapter number', () {
    final info = WebSeriesMetadata.read(
      _page(chapters: ['chapter-1-8mi19zhy']),
      _series,
    );
    expect(info.latestChapterNumber, 1);
  });

  test('half chapters are not rounded away', () {
    final info = WebSeriesMetadata.read(
      _page(chapters: ['chapter-12', 'chapter-12.5']),
      _series,
    );
    expect(info.latestChapterNumber, 12.5);
  });

  test('another series linked from the page is not counted as this one', () {
    // The fixture's nav links chapter 999 of a different series. Scoping to
    // the series' own path is the whole reason this stays site-agnostic.
    final info = WebSeriesMetadata.read(
      _page(chapters: ['chapter-3']),
      _series,
    );
    expect(info.latestChapterNumber, 3);
  });

  test('relative and absolute chapter links are both found', () {
    final info = WebSeriesMetadata.read(
      _page(
        chapters: ['chapter-3'],
        extra: '<a href="https://example.org${_series.path}/chapter-7">7</a>',
      ),
      _series,
    );
    expect(info.latestChapterNumber, 7);
  });

  test('a page with no chapters still yields its title', () {
    final info = WebSeriesMetadata.read(_page(), _series);
    expect(info.latestChapterNumber, isNull);
    expect(info.latestChapterUrl, isNull);
    expect(info.title, 'A Story');
    expect(info.isEmpty, isFalse);
  });

  test('it falls back to the title tag when there is no OpenGraph', () {
    const body =
        '<html><head><title>Plain Title</title></head><body></body></html>';
    expect(WebSeriesMetadata.read(body, _series).title, 'Plain Title');
  });

  test('a page it understands nothing of is empty, not an error', () {
    final info = WebSeriesMetadata.read('<html></html>', _series);
    expect(info.isEmpty, isTrue);
  });

  group('seriesPageFor', () {
    test('a chapter resolves to the series it belongs to', () {
      // Follow is tapped from inside a chapter far more often than from a
      // series page, and following the chapter would pin the shelf to it.
      expect(
        WebSeriesMetadata.seriesPageFor(
          Uri.parse('https://example.org/series/a-story-c6f/chapter-1-8mi19'),
        ).toString(),
        'https://example.org/series/a-story-c6f',
      );
    });

    test('a series page is left alone', () {
      expect(
        WebSeriesMetadata.seriesPageFor(Uri.parse('$_series')).toString(),
        '$_series',
      );
    });

    test('query and fragment are dropped either way', () {
      expect(
        WebSeriesMetadata.seriesPageFor(
          Uri.parse('$_series/chapter-4?theme=dark#top'),
        ).toString(),
        '$_series',
      );
      expect(
        WebSeriesMetadata.seriesPageFor(
          Uri.parse('$_series?ref=home'),
        ).toString(),
        '$_series',
      );
    });
  });

  group('chapterNumber', () {
    test('reads the shapes these slugs actually take', () {
      expect(WebSeriesMetadata.chapterNumber('chapter-260'), 260);
      expect(WebSeriesMetadata.chapterNumber('chapter-1-8mi19zhy'), 1);
      expect(WebSeriesMetadata.chapterNumber('Chapter_44'), 44);
      expect(WebSeriesMetadata.chapterNumber('chapter 7'), 7);
    });

    test('a segment with no chapter in it is not one', () {
      expect(WebSeriesMetadata.chapterNumber('about'), isNull);
      expect(WebSeriesMetadata.chapterNumber(''), isNull);
    });
  });
}
