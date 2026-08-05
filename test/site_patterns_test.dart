// Tests for the in-app browser's site recognition — which URLs count as a
// novel page, and how a chapter URL is resolved back to its novel.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/site_patterns.dart';

Uri _u(String s) => Uri.parse(s);

void main() {
  group('siteFor', () {
    test('recognises a supported host', () {
      expect(siteFor(_u('https://novelfull.com/x.html'))?.name, 'NovelFull');
    });

    test('subdomains count', () {
      expect(
        siteFor(_u('https://www.novelfull.com/x.html'))?.name,
        'NovelFull',
      );
    });

    test('a lookalike host does not', () {
      // endsWith('.novelfull.com') must not be fooled by a suffix without
      // the dot boundary.
      expect(siteFor(_u('https://notnovelfull.com/x.html')), isNull);
      expect(siteFor(_u('https://example.com/novelfull.com')), isNull);
    });

    test('both allnovelfull TLDs map to one site', () {
      expect(
        siteFor(_u('https://allnovelfull.net/a.html'))?.name,
        'AllNovelFull',
      );
      expect(
        siteFor(_u('https://allnovelfull.com/a.html'))?.name,
        'AllNovelFull',
      );
    });
  });

  group('classify', () {
    test('a novel main page on the novelfull family', () {
      expect(
        classify(_u('https://novgo.net/the-primal-hunter.html')),
        PageKind.novel,
      );
    });

    test('a wattpad story page', () {
      expect(
        classify(_u('https://www.wattpad.com/story/123456-some-title')),
        PageKind.novel,
      );
    });

    test('a chapter page is supported-site, not novel', () {
      expect(
        classify(_u('https://novgo.net/the-primal-hunter/chapter-12.html')),
        PageKind.supportedSite,
      );
    });

    test('the front page is supported-site', () {
      expect(classify(_u('https://novelfull.com/')), PageKind.supportedSite);
    });

    test('anywhere else is unsupported', () {
      expect(
        classify(_u('https://royalroad.com/fiction/1234')),
        PageKind.unsupported,
      );
    });
  });

  group('novelPageFor', () {
    test('a novel page maps to itself', () {
      final url = _u('https://novgo.net/the-primal-hunter.html');
      expect(novelPageFor(url), url);
    });

    test('derives the novel page from a chapter URL', () {
      expect(
        novelPageFor(
          _u('https://novgo.net/the-primal-hunter/chapter-12.html'),
        ),
        _u('https://novgo.net/the-primal-hunter.html'),
      );
    });

    test('drops query and fragment from the derived URL', () {
      expect(
        novelPageFor(
          _u('https://novgo.net/the-primal-hunter/chapter-12.html?p=2#top'),
        ),
        _u('https://novgo.net/the-primal-hunter.html'),
      );
    });

    test('gives null where it cannot derive, rather than guessing', () {
      // A listing page has no slug to work from.
      expect(novelPageFor(_u('https://novelfull.com/genre/Fantasy')), isNull);
      // Wattpad chapter URLs do not carry the story slug in a usable form.
      expect(novelPageFor(_u('https://wattpad.com/98765-chapter')), isNull);
      // Unsupported site: nothing to say.
      expect(novelPageFor(_u('https://royalroad.com/x/chapter-1')), isNull);
    });
  });
}
