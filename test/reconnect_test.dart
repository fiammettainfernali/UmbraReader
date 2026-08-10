// Tests for the event stream's reconnection schedule.
//
// The stream used to close for good on any drop — a server restart, a
// Wi-Fi handover, iOS suspending the app — and the screen froze on its
// last frame with nothing to say so. Reconnecting belongs to the stream
// rather than to every consumer of it.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/control_client.dart';
import 'package:umbra_reader/services/settings_service.dart';

void main() {
  group('reconnectBackoff', () {
    test('the first retry is prompt', () {
      // The common case is a desktop that was briefly away, so the first
      // attempt should not make the user wait.
      expect(reconnectBackoff(1), const Duration(seconds: 1));
    });

    test('it doubles', () {
      expect(reconnectBackoff(2), const Duration(seconds: 2));
      expect(reconnectBackoff(3), const Duration(seconds: 4));
      expect(reconnectBackoff(4), const Duration(seconds: 8));
      expect(reconnectBackoff(5), const Duration(seconds: 16));
    });

    test('it caps at half a minute', () {
      // The cap is the point: the server is usually a desktop that will
      // come back, and backing off to minutes would leave the screen
      // wrong long after it did.
      expect(reconnectBackoff(6), const Duration(seconds: 30));
      expect(reconnectBackoff(20), const Duration(seconds: 30));
      expect(reconnectBackoff(1000), const Duration(seconds: 30));
    });

    test('a zero or negative attempt is still a real delay', () {
      // Defensive: a caller confusing 0-based and 1-based must never
      // produce a zero delay and spin.
      expect(reconnectBackoff(0), const Duration(seconds: 1));
      expect(reconnectBackoff(-5), const Duration(seconds: 1));
    });

    test('every delay is positive and bounded', () {
      for (var attempt = 0; attempt < 50; attempt++) {
        final delay = reconnectBackoff(attempt);
        expect(
          delay.inMilliseconds,
          greaterThan(0),
          reason: 'attempt $attempt',
        );
        expect(
          delay.inSeconds,
          lessThanOrEqualTo(30),
          reason: 'attempt $attempt',
        );
      }
    });

    test('it never goes backwards as attempts climb', () {
      var previous = Duration.zero;
      for (var attempt = 1; attempt <= 12; attempt++) {
        final delay = reconnectBackoff(attempt);
        expect(
          delay,
          greaterThanOrEqualTo(previous),
          reason: 'attempt $attempt',
        );
        previous = delay;
      }
    });
  });

  group('the stream survives a server that is not there', () {
    test(
      'listening to an unreachable server does not close the stream',
      () async {
        // The old behaviour closed on the first failure, so the consumer
        // could never recover. It should stay open and keep retrying.
        final client = ControlClient(
          const OpdsSettings(
            baseUrl: 'http://127.0.0.1:59998',
            username: '',
            password: '',
          ),
        );
        var closed = false;
        final sub = client.events().listen((_) {}, onDone: () => closed = true);
        // Long enough for the first connection to fail and a retry to be
        // scheduled, well short of the first backoff elapsing.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(closed, isFalse, reason: 'a failed connection is not the end');
        await sub.cancel();
      },
    );

    test('cancelling stops it for good', () async {
      final client = ControlClient(
        const OpdsSettings(
          baseUrl: 'http://127.0.0.1:59997',
          username: '',
          password: '',
        ),
      );
      final sub = client.events().listen((_) {});
      await sub.cancel();
      // Past the first backoff: a cancelled stream must not reconnect
      // behind the caller's back.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    });
  });
}
