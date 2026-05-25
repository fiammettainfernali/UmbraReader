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
}
