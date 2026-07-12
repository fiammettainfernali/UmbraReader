// Tests for RecommendationFeedbackStore — the persisted "no thanks" signal.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/services/recommendation_feedback_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('load returns an empty map when nothing is stored', () async {
    expect(await RecommendationFeedbackStore().load(), isEmpty);
  });

  test('records a dismiss and a reset and reads both back', () async {
    final store = RecommendationFeedbackStore();
    await store.recordDismiss(7);
    await store.recordReset(9);
    final state = await store.load();
    expect(state[7], RecommendationFeedback.dismissed);
    expect(state[9], RecommendationFeedback.reset);
  });

  test('reset beats a previously-recorded dismiss', () async {
    final store = RecommendationFeedbackStore();
    await store.recordDismiss(1);
    await store.recordReset(1);
    expect((await store.load())[1], RecommendationFeedback.reset);
  });

  test('a later dismiss does not weaken a prior reset', () async {
    final store = RecommendationFeedbackStore();
    await store.recordReset(1);
    await store.recordDismiss(1);
    expect((await store.load())[1], RecommendationFeedback.reset);
  });

  test('forget removes an entry', () async {
    final store = RecommendationFeedbackStore();
    await store.recordDismiss(5);
    await store.forget(5);
    expect((await store.load()).containsKey(5), isFalse);
  });

  test('a like supersedes an earlier dismiss (mind changed)', () async {
    final store = RecommendationFeedbackStore();
    final t0 = DateTime(2026, 7, 1);
    await store.recordDismiss(3, now: t0);
    await store.recordLike(3, now: t0.add(const Duration(days: 1)));
    expect((await store.load())[3], RecommendationFeedback.liked);
  });

  test('a snooze hides now but expires after 30 days', () async {
    final store = RecommendationFeedbackStore();
    final t0 = DateTime(2026, 7, 1);
    await store.recordSnooze(4, now: t0);
    expect(
      (await store.load(now: t0.add(const Duration(days: 10))))[4],
      RecommendationFeedback.snoozed,
    );
    expect(
      (await store.load(now: t0.add(const Duration(days: 31))))
          .containsKey(4),
      isFalse,
      reason: 'a lapsed snooze is no feedback at all',
    );
  });

  test('sync merge: the newer action wins across devices', () async {
    final store = RecommendationFeedbackStore();
    final t0 = DateTime(2026, 7, 1);
    // This device dismissed on day 1; the other device liked on day 3.
    await store.recordDismiss(6, now: t0);
    final changed = await store.mergeSyncBlob(
      '{"6":"liked|${t0.add(const Duration(days: 2)).toIso8601String()}"}',
    );
    expect(changed, isTrue);
    expect((await store.load())[6], RecommendationFeedback.liked);
    // An OLDER cloud dismiss must not overwrite the newer local like.
    final again = await store.mergeSyncBlob(
      '{"6":"dismissed|${t0.toIso8601String()}"}',
    );
    expect(again, isFalse);
    expect((await store.load())[6], RecommendationFeedback.liked);
  });

  test('sync merge: legacy un-timestamped entries still parse and merge',
      () async {
    final store = RecommendationFeedbackStore();
    // Legacy blob format was a bare kind name. Merge both BEFORE any load():
    // loading upgrades legacy epochs to "now", which would end the tie.
    final changed = await store.mergeSyncBlob('{"8":"dismissed"}');
    expect(changed, isTrue);
    // Legacy tie (both epoch): the stronger reset wins.
    await store.mergeSyncBlob('{"8":"reset"}');
    expect((await store.load())[8], RecommendationFeedback.reset);
  });

  test('a dismiss ages out after 90 days; a reset does not', () async {
    final store = RecommendationFeedbackStore();
    final t0 = DateTime(2026, 7, 1);
    await store.recordDismiss(1, now: t0);
    await store.recordReset(2, now: t0);
    final later = t0.add(const Duration(days: 91));
    final state = await store.load(now: later);
    expect(state.containsKey(1), isFalse,
        reason: '"not interested" in March should not gag a series in July');
    expect(state[2], RecommendationFeedback.reset);
  });

  test('legacy entries get their expiry clock started on first load',
      () async {
    // Simulate a pre-timestamp store: bare kind names.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'recommendation_feedback': '{"5":"dismissed"}',
    });
    final store = RecommendationFeedbackStore();
    final now = DateTime(2026, 7, 10);
    // Without the upgrade this would age out instantly (epoch + 90 days).
    expect((await store.load(now: now))[5], RecommendationFeedback.dismissed);
    // And it still expires 90 days from the upgrade, not never.
    expect(
      (await store.load(now: now.add(const Duration(days: 91))))
          .containsKey(5),
      isFalse,
    );
  });
}
