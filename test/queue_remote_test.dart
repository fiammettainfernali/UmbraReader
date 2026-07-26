import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/screens/manage_screen.dart';
import 'package:umbra_reader/services/control_client.dart';

QueueEntry _e(String title, {int? uid, String action = 'download'}) =>
    QueueEntry(novelId: 1, title: title, action: action, uid: uid);

void main() {
  group('filterQueue', () {
    final queue = [
      _e('Lord of the Mysteries'),
      _e('Reverend Insanity'),
      _e('Shadow Slave'),
      _e('The Beginning After The End'),
    ];

    test('an empty query keeps everything in order', () {
      final out = filterQueue(queue, '');
      expect(out.map((r) => r.$2.title), queue.map((e) => e.title));
      expect(out.map((r) => r.$1), [0, 1, 2, 3]);
    });

    test('matches anywhere in the title, not just the start', () {
      expect(filterQueue(queue, 'slave').map((r) => r.$2.title), [
        'Shadow Slave',
      ]);
    });

    test('is case-insensitive and ignores surrounding whitespace', () {
      expect(filterQueue(queue, '  REVEREND ').map((r) => r.$2.title), [
        'Reverend Insanity',
      ]);
    });

    test('a filtered row carries its real queue position, not its own', () {
      // The whole point: "Shadow Slave" is 3rd in the queue but 1st on
      // screen. Acting on the on-screen index would promote the wrong book.
      final out = filterQueue(queue, 'shadow');
      expect(out.single.$1, 2);
    });

    test('positions survive a filter that keeps a scattered subset', () {
      expect(filterQueue(queue, 'the').map((r) => r.$1), [0, 3]);
    });

    test('no match yields an empty list rather than the whole queue', () {
      expect(filterQueue(queue, 'zzz'), isEmpty);
    });
  });

  group('QueueEntry', () {
    test('reads the uid the server sends', () {
      final e = QueueEntry.fromJson(const {
        'novelId': 7,
        'title': 'A book',
        'action': 'update',
        'uid': 42,
      });
      expect(e.uid, 42);
      expect(e.action, 'update');
    });

    test('a server without uids parses to null rather than a bogus id', () {
      // The app falls back to position-based calls on this, so it must not
      // be mistaken for a real handle.
      final e = QueueEntry.fromJson(const {'novelId': 7, 'title': 'A book'});
      expect(e.uid, isNull);
    });

    test('keeps the chapter range that tells two entries apart', () {
      final e = QueueEntry.fromJson(const {
        'novelId': 7,
        'title': 'A book',
        'chapterRange': [1, 10],
      });
      expect(e.chapterRange, [1, 10]);
    });
  });
}
