// Tests for the bounded work pool that parallelises library scanning and
// downloading. The properties that matter are order and the ceiling: the
// callers sort recently-read series first so an interrupted run keeps what
// the reader wants, and the server is one machine on a home network.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/work_pool.dart';

void main() {
  group('mapPooled', () {
    test('an empty list does nothing', () async {
      var called = false;
      final out = await mapPooled<int, int>([], (i) async {
        called = true;
        return i;
      });
      expect(out, isEmpty);
      expect(called, isFalse);
    });

    test('results come back in input order, not completion order', () async {
      // The first item finishes last; it must still be first in the result.
      final out = await mapPooled<int, int>([1, 2, 3, 4], (i) async {
        await Future<void>.delayed(Duration(milliseconds: (5 - i) * 20));
        return i * 10;
      }, concurrency: 4);
      expect(out, [10, 20, 30, 40]);
    });

    test('every item is visited exactly once', () async {
      final seen = <int>[];
      await mapPooled<int, int>(List.generate(50, (i) => i), (i) async {
        seen.add(i);
        return i;
      }, concurrency: 7);
      expect(seen.length, 50);
      expect(seen.toSet().length, 50, reason: 'no item claimed twice');
    });

    test('never exceeds the concurrency ceiling', () async {
      var inFlight = 0;
      var peak = 0;
      await mapPooled<int, int>(List.generate(30, (i) => i), (i) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return i;
      }, concurrency: 4);
      expect(peak, lessThanOrEqualTo(4));
      expect(peak, greaterThan(1), reason: 'it should actually parallelise');
    });

    test(
      'work is claimed from the front, so priority order is honoured',
      () async {
        // The callers rely on this: recently-read series are sorted first, so
        // the first items must be the ones that get started.
        final started = <int>[];
        await mapPooled<int, int>(List.generate(20, (i) => i), (i) async {
          started.add(i);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return i;
        }, concurrency: 3);
        expect(started.take(3), [0, 1, 2]);
      },
    );

    test('more workers than items is harmless', () async {
      final out = await mapPooled<int, int>(
        [1, 2],
        (i) async => i,
        concurrency: 99,
      );
      expect(out, [1, 2]);
    });

    test('a concurrency below one still runs, serially', () async {
      var peak = 0;
      var inFlight = 0;
      final out = await mapPooled<int, int>([1, 2, 3], (i) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        inFlight--;
        return i;
      }, concurrency: 0);
      expect(out, [1, 2, 3]);
      expect(peak, 1);
    });

    test('a null result is kept in place, not dropped', () async {
      // Callers flatten these; a "nothing here" must not shift the rest.
      final out = await mapPooled<int, int>([1, 2, 3], (i) async {
        return i == 2 ? null : i;
      });
      expect(out, [1, null, 3]);
    });
  });

  group('stopping', () {
    test('shouldStop halts further work', () async {
      var processed = 0;
      var stop = false;
      final out = await mapPooled<int, int>(
        List.generate(40, (i) => i),
        (i) async {
          processed++;
          if (processed >= 5) stop = true;
          await Future<void>.delayed(const Duration(milliseconds: 2));
          return i;
        },
        concurrency: 2,
        shouldStop: () => stop,
      );
      expect(processed, lessThan(40), reason: 'it stopped early');
      expect(out.length, 40, reason: 'the shape of the result is preserved');
    });

    test(
      'items never reached are left null, so a cancelled run is visible',
      () async {
        final out = await mapPooled<int, int>(
          List.generate(10, (i) => i),
          (i) async => i,
          concurrency: 1,
          shouldStop: () => true,
        );
        expect(out.every((e) => e == null), isTrue);
      },
    );

    test('stopping before starting does no work at all', () async {
      var called = false;
      await mapPooled<int, int>([1, 2, 3], (i) async {
        called = true;
        return i;
      }, shouldStop: () => true);
      expect(called, isFalse);
    });
  });

  group('forEachPooled', () {
    test('visits everything', () async {
      final seen = <int>[];
      await forEachPooled<int>(List.generate(25, (i) => i), (i) async {
        seen.add(i);
      }, concurrency: 5);
      expect(seen.toSet().length, 25);
    });

    test('respects the ceiling', () async {
      var inFlight = 0;
      var peak = 0;
      await forEachPooled<int>(List.generate(20, (i) => i), (i) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 4));
        inFlight--;
      }, concurrency: 3);
      expect(peak, lessThanOrEqualTo(3));
    });
  });

  group('PoolSize', () {
    test('downloads are more restrained than metadata', () {
      // EPUBs share one pipe and only count once finished; metadata calls
      // are small and latency-bound, so more of them pay off.
      expect(PoolSize.downloads, lessThan(PoolSize.metadata));
      expect(PoolSize.downloads, greaterThan(0));
    });
  });
}
