// Keeps the semantic index fresh, and owns the one copy of the model.
//
// Two jobs, both about not being noticed. The model is loaded once and kept,
// because loading 23MB on every library refresh would cost more than the
// embedding does. And every failure here is swallowed: the index makes
// suggestions better, and nothing in the app should fail to open because a
// model would not load. Callers get the old engine when the index is empty,
// which is exactly what an unindexed library looks like.

import 'dart:async';
import 'dart:typed_data';

import '../models/series.dart';
import 'series_indexer.dart';
import 'text_embedder.dart';

class SemanticIndexService {
  SemanticIndexService._();

  static final SemanticIndexService instance = SemanticIndexService._();

  final TextEmbedder _embedder = TextEmbedder();

  bool _running = false;

  /// Set after the runtime refuses to start, so a device that cannot run
  /// the model is asked once rather than on every library refresh.
  bool _unavailable = false;

  /// How many books one pass will embed.
  ///
  /// A first run over a thousand-book library is about a minute. Doing it
  /// in slices means the work lands across a few refreshes instead of
  /// holding a background task open through the whole of one, and the
  /// reader is reading the entire time either way.
  static const int passBudget = 400;

  bool get isUnavailable => _unavailable;

  /// Brings the index up to date. Never throws, never blocks the caller's
  /// own work, and does nothing at all if a pass is already running.
  Future<IndexOutcome?> refresh(List<Series> library) async {
    if (_unavailable || _running || library.isEmpty) return null;
    _running = true;
    try {
      final indexer = SeriesIndexer(embed: _embed);
      return await indexer.indexLibrary(library, budget: passBudget);
    } catch (_) {
      // A missing model, a runtime that will not start, a device without
      // the native library: all the same answer. Stop asking, and let the
      // old engine carry the shelves.
      _unavailable = true;
      return null;
    } finally {
      _running = false;
    }
  }

  Future<Float32List?> _embed(String text) => _embedder.embed(text);

  /// For tests and for a model swap, which has to drop the old vectors
  /// because two models' spaces are not comparable.
  Future<void> dispose() async {
    await _embedder.dispose();
    _running = false;
    _unavailable = false;
  }
}
