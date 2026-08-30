// Where a command goes, when the library is not the machine that downloads.
//
// The hub stores and serves but refuses every fetching route — correctly, a
// datacenter IP is what the source sites screen hardest. The control client
// built every URL from the library address, so pointing the reader at a hub
// sent "start a sweep" to the one server guaranteed to say no.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/settings_service.dart';

void main() {
  group('controlUrl', () {
    test('is the library when one machine does both', () {
      const s = OpdsSettings(
        baseUrl: 'http://192.168.1.42:8765',
        username: '',
        password: '',
      );
      expect(s.controlUrl, 'http://192.168.1.42:8765');
      expect(s.downloaderIsElsewhere, isFalse);
    });

    test('is the downloader when one is set', () {
      const s = OpdsSettings(
        baseUrl: 'https://umbra-hub.example.ts.net',
        downloaderUrl: 'http://100.111.233.59:8765',
        username: '',
        password: '',
      );
      expect(s.controlUrl, 'http://100.111.233.59:8765');
      expect(s.downloaderIsElsewhere, isTrue);
    });

    test('an empty downloader falls back rather than producing a bare path', () {
      // The fallback is what keeps every existing install working untouched.
      const s = OpdsSettings(
        baseUrl: 'http://host:8765',
        downloaderUrl: '',
        username: '',
        password: '',
      );
      expect(s.controlUrl, isNot(isEmpty));
      expect(s.controlUrl, 'http://host:8765');
    });

    test('the same address twice is not "elsewhere"', () {
      const s = OpdsSettings(
        baseUrl: 'http://host:8765',
        downloaderUrl: 'http://host:8765',
        username: '',
        password: '',
      );
      expect(s.downloaderIsElsewhere, isFalse);
    });

    test('copyWith carries it', () {
      const s = OpdsSettings(baseUrl: 'a', username: '', password: '');
      expect(s.copyWith(downloaderUrl: 'b').downloaderUrl, 'b');
      // And leaves it alone when changing something else.
      const set = OpdsSettings(
        baseUrl: 'a', username: '', password: '', downloaderUrl: 'b');
      expect(set.copyWith(username: 'u').downloaderUrl, 'b');
    });

    test('reading the library never follows the downloader', () {
      // Books come from the hub even when commands do not. Crossing these
      // would send every download to the machine that has no books on it.
      const s = OpdsSettings(
        baseUrl: 'https://hub.example',
        downloaderUrl: 'http://home:8765',
        username: '',
        password: '',
      );
      expect(s.baseUrl, 'https://hub.example');
    });
  });
}
