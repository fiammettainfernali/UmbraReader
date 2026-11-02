// Keeps the semantic index fresh, and owns the one copy of the model.
//
// Two jobs, both about not being noticed. The model is loaded once and kept,
// because loading 23MB on every library refresh would cost more than the
// embedding does. And every failure here is swallowed: the index makes
// suggestions better, and nothing in the app should fail to open because a
// model would not load. Callers get the old engine when the index is empty,
// which is exactly what an unindexed library looks like.
//
// Swallowed, but no longer silent. Every branch out of here says why in the
// log (see semantic_log.dart), because a fallback that looks like success
// is indistinguishable from success until somebody checks.

import 'dart:async';
import 'dart:typed_data';

import '../db/app_database.dart';
import '../models/series.dart';
import 'semantic_log.dart';
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

  /// Bumped whenever a release changes how inference is done.
  ///
  /// The two markers below are evidence about one build's behaviour, and a
  /// build that fixes what they were recording deserves a clean slate —
  /// otherwise a phone that switched the index off keeps it off through
  /// every later fix, and the shipped repair never gets to run.
  static const int _generation = 2;

  /// Counts passes that started and never finished. Written before the
  /// first inference and cleared after the last one.
  static const String _attemptsKey = 'semantic_index_unfinished_v$_generation';

  /// Set once the index has given up for good on this device.
  static const String _disabledKey = 'semantic_index_disabled_v$_generation';

  /// How many unfinished passes it takes to stop trying.
  ///
  /// Two, not one: swiping the app away mid-pass also leaves the marker
  /// behind, and losing the index because somebody closed the app would be
  /// its own bug. Two in a row is a pattern.
  static const _giveUpAfter = 2;

  bool get isUnavailable => _unavailable;

  /// Brings the index up to date. Never blocks the caller's own work, and
  /// does nothing at all if a pass is already running.
  ///
  /// The marker around the pass exists because a Dart catch is not enough
  /// protection here. The inference runs through a native library, and a
  /// native abort — a JNI lookup that fails, for instance — takes the whole
  /// process down without raising anything Dart can see. The first version
  /// of this swallowed every exception and called itself safe; what it
  /// actually did was leave an app that could not be opened, because the
  /// indexer runs on every library load and died the same way each time.
  /// So the attempt is recorded BEFORE it is made: a pass that never
  /// reports back is evidence, and after two of those the index switches
  /// itself off and the shelves fall back to metadata ranking.
  Future<IndexOutcome?> refresh(List<Series> library) async {
    if (_unavailable || library.isEmpty) return null;
    if (_running) {
      semanticLog('refresh ignored: a pass is already running');
      return null;
    }

    final db = AppDatabase.instance;
    final disabledAt = await db.kvGet(_disabledKey) ?? '';
    if (disabledAt.isNotEmpty) {
      semanticLog('index is off on this device, switched off $disabledAt');
      _unavailable = true;
      return null;
    }
    final unfinished = int.tryParse(await db.kvGet(_attemptsKey) ?? '') ?? 0;
    if (unfinished >= _giveUpAfter) {
      semanticLog('switching the index off: $unfinished passes were started '
          'and none of them reported back');
      await db.kvSet(_disabledKey, DateTime.now().toIso8601String());
      await db.kvSet(_attemptsKey, '0');
      _unavailable = true;
      return null;
    }

    _running = true;
    final clock = Stopwatch()..start();
    try {
      await db.kvSet(_attemptsKey, '${unfinished + 1}');
      semanticLog('pass starting over ${library.length} books, '
          'budget $passBudget, attempt ${unfinished + 1} of $_giveUpAfter');
      final indexer = SeriesIndexer(embed: _embed);
      final outcome = await indexer.indexLibrary(library, budget: passBudget);
      await db.kvSet(_attemptsKey, '0');
      semanticLog(outcome.isComplete
          ? 'index up to date after ${formatElapsed(clock.elapsed)}'
          : '${outcome.remaining} books wait for the next launch');
      return outcome;
    } catch (error, stack) {
      // A missing model, a runtime that will not start, a device without
      // the native library: all the same answer for this launch. Stop
      // asking, and let the old engine carry the shelves — but say so,
      // because this catch spent a day being the reason nobody knew the
      // index was dead.
      //
      // The attempt marker is cleared on the way out. A thrown exception
      // means the pass reported back, which is precisely what the marker
      // counts the absence of; leaving it set would spend one of two
      // lives on a failure that is already visible in the log, and two
      // bad launches would switch the index off for good over something
      // a later build fixes.
      try {
        await db.kvSet(_attemptsKey, '0');
      } catch (_) {
        // A failed write here is not worth losing the error below.
      }
      semanticLog('pass failed after ${formatElapsed(clock.elapsed)}: $error');
      semanticLog('$stack');
      _unavailable = true;
      return null;
    } finally {
      _running = false;
    }
  }

  Future<Float32List?> _embed(String text) async {
    if (!_embedder.isLoaded) {
      final clock = Stopwatch()..start();
      await _embedder.load();
      semanticLog('model loaded in ${formatElapsed(clock.elapsed)}');
    }
    return _embedder.embed(text);
  }

  /// For tests and for a model swap, which has to drop the old vectors
  /// because two models' spaces are not comparable.
  Future<void> dispose() async {
    await _embedder.dispose();
    _running = false;
    _unavailable = false;
  }
}
