// What another app's share turns into.
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/shared_link.dart';

void main() {
  group('reading a share', () {
    test('a bare novel link is ready to send, without its query', () {
      final link = readSharedText(
        'https://novelfull.com/a-book.html?page=2',
        null,
      );
      expect(link.kind, SharedKind.novel);
      expect(link.url, 'https://novelfull.com/a-book.html');
      expect(link.label, 'novelfull.com/a-book.html?page=2');
    });

    test('a chapter link sends the novel it belongs to', () {
      final link = readSharedText(
        'https://novelfull.com/a-book/chapter-12.html',
        null,
      );
      expect(link.kind, SharedKind.novel);
      expect(link.url, 'https://novelfull.com/a-book.html');
    });

    test('finds the link inside a sentence, and names it from the words', () {
      final link = readSharedText(
        'Read A Book on NovelFull: https://novelfull.com/a-book.html.',
        null,
      );
      expect(link.kind, SharedKind.novel);
      expect(link.url, 'https://novelfull.com/a-book.html');
      expect(link.label, 'Read A Book on NovelFull');
    });

    test('a subject makes the better name', () {
      final link = readSharedText(
        'https://novgo.net/a-book.html',
        'A Book - Novgo',
      );
      expect(link.label, 'A Book - Novgo');
    });

    test('a Wattpad story counts as a novel', () {
      final link = readSharedText(
        'https://www.wattpad.com/story/12345-a-story',
        null,
      );
      expect(link.kind, SharedKind.novel);
      expect(link.url, 'https://www.wattpad.com/story/12345-a-story');
    });

    test('elsewhere on a known site is not sent without asking', () {
      final link = readSharedText('https://novelfull.com/latest', null);
      expect(link.kind, SharedKind.otherPage);
      expect(link.url, 'https://novelfull.com/latest');
    });

    test('a site the computer does not know is not sent without asking', () {
      final link = readSharedText('https://example.com/a-book.html', null);
      expect(link.kind, SharedKind.unsupportedSite);
    });

    test('no link at all says so', () {
      expect(readSharedText('just some words', null).kind, SharedKind.noLink);
      expect(readSharedText('', null).kind, SharedKind.noLink);
      expect(readSharedText(null, null).kind, SharedKind.noLink);
    });
  });
}
