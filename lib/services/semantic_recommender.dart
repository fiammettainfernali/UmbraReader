// Ranking by what a book is about.
//
// The engine this sits beside ranks on four hand-weighted groups — author,
// genre, keyword, length — and those weights are the problem. Not because
// they were tuned badly, but because they exist at all: every number in
// them is somebody's guess about how much a shared genre is worth against
// a shared word, and the genre side is a vocabulary of 1,213 labels for
// 1,016 books. "Xianxia" and "Cultivation" are unrelated tokens to it.
//
// Here there are no weights. Two books are close if the model puts them
// close, and shared meaning does the work that shared spelling was doing.

import 'dart:typed_data';

import '../models/series.dart';
import 'text_embedder.dart';

/// A pick with the distance that produced it, so a caller can show a reason
/// or set a floor rather than trusting the order blindly.
class SemanticPick {
  const SemanticPick(this.series, this.similarity);

  final Series series;

  /// −1 to 1. Around 0.3 is "loosely related"; above 0.5 is usually the
  /// same sort of book.
  final double similarity;
}

/// Books most like [source], nearest first.
///
/// Returns empty rather than guessing when the source has no vector — an
/// unindexed book should fall back to the old engine, not quietly produce
/// a list ranked on nothing.
List<SemanticPick> mostSimilarTo({
  required Series source,
  required List<Series> library,
  required Map<int, Float32List> vectors,
  int limit = 6,
  Set<int> exclude = const {},
  double floor = 0.15,
}) {
  final seed = vectors[source.opdsId];
  if (seed == null) return const [];
  return _rank(
    seed: seed,
    library: library,
    vectors: vectors,
    limit: limit,
    exclude: {...exclude, source.opdsId},
    floor: floor,
  );
}

/// Books most like everything the reader has actually read.
///
/// [weights] is how much each read counts — depth, recency, time in the
/// book — and it is the engine's existing judgement, not a new one. A
/// weight at or below zero drops that book rather than subtracting it: not
/// finishing something is not a wish for its opposite.
List<SemanticPick> mostSimilarToTaste({
  required Map<int, double> readWeights,
  required List<Series> library,
  required Map<int, Float32List> vectors,
  int limit = 12,
  Set<int> exclude = const {},
  double floor = 0.15,
}) {
  final read = <Float32List>[];
  final weights = <double>[];
  readWeights.forEach((seriesId, weight) {
    final vector = vectors[seriesId];
    if (vector == null || weight <= 0) return;
    read.add(vector);
    weights.add(weight);
  });
  final taste = centroid(read, weights: weights);
  if (taste == null) return const [];
  return _rank(
    seed: taste,
    library: library,
    vectors: vectors,
    limit: limit,
    exclude: {...exclude, ...readWeights.keys},
    floor: floor,
  );
}

/// Books matching a phrase, for search that understands what was meant.
List<SemanticPick> matching({
  required Float32List query,
  required List<Series> library,
  required Map<int, Float32List> vectors,
  int limit = 20,
  double floor = 0.2,
}) => _rank(
  seed: query,
  library: library,
  vectors: vectors,
  limit: limit,
  exclude: const {},
  floor: floor,
);

List<SemanticPick> _rank({
  required Float32List seed,
  required List<Series> library,
  required Map<int, Float32List> vectors,
  required int limit,
  required Set<int> exclude,
  required double floor,
}) {
  final scored = <SemanticPick>[];
  for (final series in library) {
    if (exclude.contains(series.opdsId)) continue;
    final vector = vectors[series.opdsId];
    if (vector == null) continue;
    final similarity = cosineSimilarity(seed, vector);
    // A floor rather than "the best six of whatever exists". In a library
    // of one genre everything is related and the list is fine; in a
    // library with one lonely horror novel, the six nearest things to it
    // are not horror, and saying so is better than filling the shelf.
    if (similarity < floor) continue;
    scored.add(SemanticPick(series, similarity));
  }
  scored.sort((a, b) => b.similarity.compareTo(a.similarity));
  return scored.length <= limit ? scored : scored.sublist(0, limit);
}
