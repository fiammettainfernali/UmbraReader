// Tests for the offline add queue: novels asked for while Novel Grabber
// was unreachable, replayed when it answers again.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/services/control_client.dart';
import 'package:umbra_reader/services/pending_add_store.dart';
import 'package:umbra_reader/services/settings_service.dart';

import 'helpers/test_db.dart';

/// A client that answers however the test needs it to.
class _FakeClient implements ControlClient {
  _FakeClient(this._answer);

  /// Given a URL, either returns (accepted) or throws.
  final void Function(String url, bool force) _answer;

  final List<(String, bool)> calls = [];

  @override
  Future<void> addNovel(String url, {bool force = false}) async {
    calls.add((url, force));
    _answer(url, force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not needed by these tests');

  @override
  OpdsSettings get settings => throw UnimplementedError();
}

void _accepts(String url, bool force) {}

void _offline(String url, bool force) =>
    throw ControlException('no route to host', isUnreachable: true);

void _refuses(String url, bool force) => throw ControlException('bad url');

void _alreadyHas(String url, bool force) =>
    throw DuplicateNovelException('already have it', const [], 'url');

void main() {
  setUp(() async => useInMemoryDatabase());
  tearDown(AppDatabase.reset);

  group('queueing', () {
    test('starts empty and keeps what it is given', () async {
      final store = PendingAddStore();
      expect(await store.list(), isEmpty);

      await store.enqueue('https://novgo.net/a.html', label: 'A Book');

      final all = await store.list();
      expect(all.single.url, 'https://novgo.net/a.html');
      expect(all.single.label, 'A Book');
      expect(all.single.attempts, 0);
    });

    test('falls back to the URL when there is no title', () async {
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html');
      expect((await store.list()).single.label, 'https://novgo.net/a.html');
      await store.clear();
      await store.enqueue('https://novgo.net/b.html', label: '   ');
      expect((await store.list()).single.label, 'https://novgo.net/b.html');
    });

    test('the same URL twice is one entry, not two', () async {
      // Tapping add twice while offline is one intention.
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html');
      await store.enqueue('https://novgo.net/a.html');
      expect((await store.list()).length, 1);
    });

    test('re-queuing with force upgrades the existing entry', () async {
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html');
      await store.enqueue('https://novgo.net/a.html', force: true);
      final all = await store.list();
      expect(all.length, 1);
      expect(all.single.force, isTrue);
    });

    test('an empty url is ignored', () async {
      final store = PendingAddStore();
      await store.enqueue('   ');
      expect(await store.list(), isEmpty);
    });

    test('an entry can be forgotten', () async {
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html');
      await store.enqueue('https://novgo.net/b.html');
      final id = (await store.list()).first.id;
      final left = await store.remove(id);
      expect(left.single.url, 'https://novgo.net/b.html');
    });

    test(
      'the list is capped so a long spell offline cannot run away',
      () async {
        final store = PendingAddStore();
        for (var i = 0; i < PendingAddStore.maxPending + 10; i++) {
          await store.enqueue('https://novgo.net/$i.html');
        }
        expect((await store.list()).length, PendingAddStore.maxPending);
      },
    );

    test('corrupt storage reads as empty rather than throwing', () async {
      await AppDatabase.instance.kvSet('pending_novel_adds', 'not json');
      expect(await PendingAddStore().list(), isEmpty);
    });
  });

  group('flushing', () {
    test('an empty queue does nothing and says nothing', () async {
      final report = await PendingAddStore().flush(_FakeClient(_accepts));
      expect(report.didAnything, isFalse);
      expect(report.summary, isNull);
    });

    test('everything accepted is sent and cleared', () async {
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html');
      await store.enqueue('https://novgo.net/b.html');

      final client = _FakeClient(_accepts);
      final report = await store.flush(client);

      expect(report.sent, 2);
      expect(report.stillWaiting, 0);
      expect(await store.list(), isEmpty);
      expect(client.calls.length, 2);
    });

    test('force is carried through to the server', () async {
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html', force: true);
      final client = _FakeClient(_accepts);
      await store.flush(client);
      expect(client.calls.single.$2, isTrue);
    });

    test('still offline keeps everything, and counts the attempt', () async {
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html');
      await store.enqueue('https://novgo.net/b.html');

      final client = _FakeClient(_offline);
      final report = await store.flush(client);

      expect(report.sent, 0);
      expect(report.stillWaiting, 2);
      final left = await store.list();
      expect(left.length, 2);
      expect(left.first.attempts, 1);
      expect(
        client.calls.length,
        1,
        reason:
            'stop at the first failure rather than hammering a server '
            'that plainly is not there',
      );
      expect(left.map((p) => p.url), [
        'https://novgo.net/a.html',
        'https://novgo.net/b.html',
      ], reason: 'original order preserved');
    });

    test('a novel the server already has is not kept nagging', () async {
      // That is an answer, not a failure; replaying it would re-ask a
      // question already settled.
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html');

      final report = await store.flush(_FakeClient(_alreadyHas));

      expect(report.alreadyHad, 1);
      expect(await store.list(), isEmpty);
    });

    test('a rejection is dropped rather than retried forever', () async {
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html');

      final report = await store.flush(_FakeClient(_refuses));

      expect(report.failed, 1);
      expect(report.sent, 0);
      expect(await store.list(), isEmpty);
    });

    test('a queue that survives a flush is still there next time', () async {
      final store = PendingAddStore();
      await store.enqueue('https://novgo.net/a.html');
      await store.flush(_FakeClient(_offline));

      // A fresh store instance reads the same persisted queue.
      expect((await PendingAddStore().list()).length, 1);

      final report = await PendingAddStore().flush(_FakeClient(_accepts));
      expect(report.sent, 1);
      expect(await PendingAddStore().list(), isEmpty);
    });
  });

  group('FlushReport.summary', () {
    test('names each outcome that happened', () {
      const r = FlushReport(sent: 2, alreadyHad: 1, failed: 1, stillWaiting: 3);
      expect(r.summary, contains('2 sent'));
      expect(r.summary, contains('1 already'));
      expect(r.summary, contains('1 rejected'));
      expect(r.summary, contains('3 still waiting'));
    });

    test('says nothing when nothing happened', () {
      expect(const FlushReport(stillWaiting: 2).summary, isNull);
    });
  });
}
