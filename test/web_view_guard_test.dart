// Keeping a comic's WebView on the site it was opened for.
//
// The cases that matter are the ones an ad script actually uses: a jump to
// another domain, a lookalike domain that ends in the right letters, and
// the schemes that leave the app altogether.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/web_view_guard.dart';

final _origin = Uri.parse('https://vortexscans.org/series/rankers-return-c6f');

void main() {
  bool allows(String url) => sameSite(_origin, Uri.parse(url));

  group('the site it was opened for', () {
    test('another chapter is fine', () {
      expect(
        allows(
          'https://vortexscans.org/series/rankers-return-c6f/'
          'chapter-260',
        ),
        isTrue,
      );
    });

    test('so is anywhere else on the site', () {
      expect(allows('https://vortexscans.org/'), isTrue);
      expect(allows('https://vortexscans.org/browse?sort=new'), isTrue);
    });

    test('a subdomain of it passes', () {
      expect(allows('https://storage.vortexscans.org/upload/x.webp'), isTrue);
    });

    test('www and bare are one site', () {
      // Sites routinely serve a series page from one and its chapters from
      // the other; treating them as different would block a comic from its
      // own pages.
      expect(allows('https://www.vortexscans.org/series/x'), isTrue);
      expect(
        sameSite(
          Uri.parse('https://www.vortexscans.org/series/x'),
          Uri.parse('https://vortexscans.org/series/x/chapter-2'),
        ),
        isTrue,
      );
    });

    test('plain http on the same site still passes', () {
      // Downgrading is the site's business, not a reason to strand the
      // reader — and it is a navigation, not a place secrets are typed.
      expect(allows('http://vortexscans.org/series/x'), isTrue);
    });
  });

  group('anywhere else', () {
    test('another domain is refused', () {
      expect(allows('https://ads.example.com/win-a-prize'), isFalse);
    });

    test('a lookalike that merely ends the same way is refused', () {
      // The obvious way to get past a naive endsWith: register a domain
      // whose tail matches.
      expect(allows('https://notvortexscans.org/'), isFalse);
      expect(allows('https://vortexscans.org.evil.com/'), isFalse);
    });

    test('a domain that merely contains it is refused', () {
      expect(allows('https://vortexscans.org.co/'), isFalse);
    });

    test('case does not smuggle anything through', () {
      expect(allows('https://VORTEXSCANS.ORG/series/x'), isTrue);
      expect(allows('https://EVIL.COM/'), isFalse);
    });
  });

  group('leaving the app', () {
    test('the store-listing schemes are refused', () {
      // How an ad tries to put an install prompt in front of you.
      expect(allows('intent://details?id=com.bad.app#Intent;end'), isFalse);
      expect(allows('market://details?id=com.bad.app'), isFalse);
    });

    test('the dialler is refused', () {
      expect(allows('tel:+15550100'), isFalse);
    });

    test('script and inline data are refused', () {
      expect(allows('javascript:alert(1)'), isFalse);
      expect(allows('data:text/html,<h1>hi</h1>'), isFalse);
    });

    test('a local file is refused', () {
      expect(allows('file:///sdcard/Download/thing.apk'), isFalse);
    });

    test('a URL with no host at all is refused', () {
      expect(allows('https:///nowhere'), isFalse);
    });
  });
}
