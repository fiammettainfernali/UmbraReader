import '../models/series.dart';
import 'bookmark_store.dart';
import 'collection_store.dart';
import 'rec_outcome_store.dart';
import 'rec_weight_learner.dart';
import 'reading_activity_store.dart';
import 'reading_progress_store.dart';
import 'recommendation_engine.dart';
import 'recommendation_feedback_store.dart';
import 'series_status_store.dart';

/// Works out what to suggest reading next.
///
/// Lifted out of the library screen when recommendations moved to their own
/// tab. The computation reads from seven stores and fits the ranking
/// weights, which is a lot to carry inside a widget that also has a grid to
/// draw — and it now has two potential callers rather than one.
///
/// Everything it needs it loads itself: the signals come from local SQLite
/// and preferences, so a second read costs a few milliseconds and saves
/// threading a dozen values between screens.
class RecommendationLoader {
  const RecommendationLoader({this.maxResults = 40});

  /// A wider pool than is shown, so the shelf's shuffle has somewhere to go.
  final int maxResults;

  Future<List<Recommendation>> load(List<Series> library) async {
    if (library.isEmpty) return const [];

    final (
      entries,
      feedback,
      status,
      hidden,
      activity,
      highlights,
      collections,
      outcomes,
    ) = await (
      ReadingProgressStore().allEntries(),
      RecommendationFeedbackStore().load(),
      SeriesStatusStore().load(),
      ReadingProgressStore().hiddenFromContinue(),
      ReadingActivityStore().load(),
      // Everything the app knows about HOW the reader reads: highlight
      // density, collection membership, and shown-and-ignored outcomes.
      BookmarkStore().countBySeries(),
      CollectionStore().list(),
      RecOutcomeStore().load(),
    ).wait;

    final signals = RecSignals(
      volumeSeconds: activity.perVolumeSeconds,
      volumeWords: activity.perVolumeWords,
      highlightsPerSeries: highlights,
      hiddenVolumeKeys: hidden,
      collectionSeriesIds: {for (final c in collections) ...c.seriesIds},
      outcomes: outcomes,
      // The reader's own status picker, translated to engine vocabulary —
      // "caught up" on a series read entirely outside the app is a full
      // like even with zero in-app reading entries.
      statusOverrides: {
        for (final e in status.entries)
          if (e.value == SeriesStatus.caughtUp)
            e.key: 'completed'
          else if (e.value == SeriesStatus.dropped)
            e.key: 'dropped'
          else if (e.value == SeriesStatus.reading)
            e.key: 'ongoing',
      },
    );

    // Learn this reader's feature-group weights from recommendation
    // outcomes (a full refit from the prior each time — deterministic and
    // cheap), then rank under them. Zero outcomes gives the hand-tuned
    // prior, exactly.
    final engine = RecommendationEngine(maxResults: maxResults);
    final examples = buildRecTrainingExamples(
      engine: engine,
      allSeries: library,
      readingEntries: entries,
      feedback: feedback,
      signals: signals,
    );
    final learned = const RecWeightLearner().fit(examples);
    await RecWeightsStore().save(learned);

    return engine.recommend(
      allSeries: library,
      readingEntries: entries,
      feedback: feedback,
      signals: signals,
      weights: learned,
      explore: true,
    );
  }
}

/// The series that gained chapters most recently.
///
/// A pure view over the library, so it needs no stores at all — which is
/// why it can sit beside the recommendations without doubling the load.
List<Series> recentlyUpdated(List<Series> library, {int limit = 12}) {
  final dated = [for (final s in library) if (s.updatedAt != null) s];
  dated.sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
  return dated.take(limit).toList();
}
