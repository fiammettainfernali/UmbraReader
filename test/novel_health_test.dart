// Tests for the per-novel repair data the series screen reads.
//
// Retrying failed chapters and starting a novel over were desktop-only,
// which is what made running the server headless awkward: when something
// broke there was nothing the phone could do about it.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/control_client.dart';

void main() {
  group('NovelHealth', () {
    test('reads the server payload', () {
      final h = NovelHealth.fromJson(const {
        'novelId': 511,
        'title': 'The Primal Hunter',
        'total': 1366,
        'done': 1300,
        'pending': 54,
        'errored': 12,
        'lastError': '403 Forbidden',
      });
      expect(h.novelId, 511);
      expect(h.total, 1366);
      expect(h.errored, 12);
      expect(h.lastError, '403 Forbidden');
      expect(h.hasFailures, isTrue);
    });

    test('a healthy novel has nothing to report', () {
      final h = NovelHealth.fromJson(const {
        'total': 100,
        'done': 100,
        'errored': 0,
        'lastError': '',
      });
      expect(h.hasFailures, isFalse);
      expect(h.lastError, isEmpty);
    });

    test('a missing payload degrades to zeroes rather than throwing', () {
      final h = NovelHealth.fromJson(const {});
      expect(h.total, 0);
      expect(h.errored, 0);
      expect(h.hasFailures, isFalse);
      expect(h.title, isEmpty);
    });

    test('hasFailures is about errors, not undownloaded chapters', () {
      // A novel mid-download has pending chapters and nothing wrong.
      final h = NovelHealth.fromJson(const {
        'total': 500,
        'done': 100,
        'pending': 400,
        'errored': 0,
      });
      expect(h.hasFailures, isFalse);
    });
  });
}
