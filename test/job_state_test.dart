// Tests for how the Discover tab reads the server's progress ticks.
//
// The server emits five distinct states; the app used to branch on one,
// so a checking sweep, a deliberate batch pause and an EPUB build all
// rendered as a download. The counts differ too — a sweep counts novels,
// a download counts chapters — so the same "40 / 486" meant unrelated
// things depending on state nobody was reading.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/control_client.dart';

ControlProgress _p(Map<String, dynamic> json) => ControlProgress.fromJson(json);

void main() {
  group('JobState.fromName', () {
    test('maps every state the server actually sends', () {
      // These strings are the server's, from Orchestrator._emit_progress.
      expect(JobState.fromName('downloading'), JobState.downloading);
      expect(JobState.fromName('checking'), JobState.checking);
      expect(JobState.fromName('batch_pause'), JobState.batchPause);
      expect(JobState.fromName('compiling'), JobState.compiling);
      expect(JobState.fromName('idle'), JobState.idle);
    });

    test('absence reads as idle', () {
      expect(JobState.fromName(null), JobState.idle);
      expect(JobState.fromName(''), JobState.idle);
    });

    test('an unknown state is admitted, not guessed at', () {
      // A newer server saying something this build has never heard of
      // should produce something true and vague, not a wrong label.
      final state = JobState.fromName('defragmenting');
      expect(state, JobState.unknown);
      expect(state.label, 'Working');
      expect(state.isIdle, isFalse);
    });
  });

  group('what each state means for the UI', () {
    test('only idle counts as idle', () {
      for (final state in JobState.values) {
        expect(state.isIdle, state == JobState.idle, reason: '$state');
      }
    });

    test('a batch pause is waiting, not stalled', () {
      expect(JobState.batchPause.isWaiting, isTrue);
      expect(JobState.downloading.isWaiting, isFalse);
    });

    test('compiling is indeterminate because it arrives at 100%', () {
      expect(JobState.compiling.isIndeterminate, isTrue);
      expect(JobState.downloading.isIndeterminate, isFalse);
    });

    test('a sweep counts series, a download counts chapters', () {
      // The heart of the bug: same numbers, different meaning.
      expect(JobState.checking.unit, 'series');
      expect(JobState.downloading.unit, 'chapters');
    });
  });

  group('ControlProgress parsing', () {
    test('reads a real downloading payload', () {
      final p = _p(const {
        'novel_id': 511,
        'novel_title': 'The Primal Hunter',
        'chapter_title': 'Chapter 12',
        'current': 12,
        'total': 340,
        'percent': 3.5,
        'state': 'downloading',
        'queue_size': 4,
      });
      expect(p.state, JobState.downloading);
      expect(p.novelId, 511);
      expect(p.queueSize, 4);
      expect(p.keepBar, isFalse);
      expect(p.isIdle, isFalse);
    });

    test('reads the keep_bar flag a batch pause sends', () {
      final p = _p(const {
        'state': 'batch_pause',
        'current': 40,
        'total': 340,
        'percent': 11.7,
        'keep_bar': true,
      });
      expect(p.state.isWaiting, isTrue);
      expect(p.keepBar, isTrue);
    });

    test('an empty payload is idle rather than a crash', () {
      final p = _p(const {});
      expect(p.state, JobState.idle);
      expect(p.novelId, isNull);
      expect(p.queueSize, isNull);
      expect(p.current, 0);
    });

    test('novel_id is null during a parallel run', () {
      // The server folds several novels onto one bar and omits the id,
      // because the tick is no longer about a single novel.
      final p = _p(const {
        'novel_title': '3 novels in parallel',
        'state': 'downloading',
        'current': 30,
        'total': 900,
      });
      expect(p.novelId, isNull);
    });
  });

  group('countLabel', () {
    test('names what is being counted during a sweep', () {
      final p = _p(const {
        'state': 'checking',
        'current': 40,
        'total': 486,
        'percent': 8.2,
      });
      expect(p.countLabel, '40 of 486 series  ·  8%');
    });

    test('and during a download', () {
      final p = _p(const {
        'state': 'downloading',
        'current': 12,
        'total': 340,
        'percent': 3.5,
      });
      expect(p.countLabel, '12 of 340 chapters  ·  4%');
    });

    test('falls back to the state label when there is no total', () {
      final p = _p(const {'state': 'compiling', 'current': 0, 'total': 0});
      expect(p.countLabel, 'Building EPUB');
    });

    test('an unknown state with counts still reads sensibly', () {
      final p = _p(const {
        'state': 'defragmenting',
        'current': 2,
        'total': 5,
        'percent': 40,
      });
      // No unit is known, so it says the numbers without inventing one.
      expect(p.countLabel, '2 of 5  ·  40%');
    });
  });
}
