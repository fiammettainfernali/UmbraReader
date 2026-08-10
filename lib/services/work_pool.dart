/// Runs a bounded number of async tasks at a time over an ordered list.
///
/// The library's scans and downloads were strictly sequential, which for a
/// few hundred series means a few hundred round-trips end to end — and the
/// metadata fetches are small requests where latency, not bandwidth, is
/// the cost. Running several at once is most of the win.
///
/// A pool rather than `Future.wait` over everything, for two reasons that
/// both matter here:
///
/// * **Order is meaningful.** The callers sort recently-read series first
///   so that stopping part-way keeps what the reader actually wants. Work
///   is therefore claimed from the front of the list, and results come
///   back in input order regardless of which task finished first.
/// * **The server is one machine.** Novel Grabber serves this from a
///   threaded HTTP server on a home network; a few concurrent requests are
///   free, hundreds are a self-inflicted denial of service.
library;

/// Applies [task] to every item, at most [concurrency] at a time.
///
/// Results are returned in the order of [items], not completion order.
/// Entries not reached — because [shouldStop] began returning true — are
/// left null, so a cancelled run is distinguishable from one that produced
/// nothing.
///
/// [task] is expected to handle its own failures. An exception escaping it
/// aborts the whole pool, which is right for a genuine bug and wrong for
/// one unreachable series, so callers doing best-effort work should catch
/// inside the task.
Future<List<R?>> mapPooled<T, R>(
  List<T> items,
  Future<R?> Function(T item) task, {
  int concurrency = 6,
  bool Function()? shouldStop,
}) async {
  if (items.isEmpty) return <R?>[];
  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      if (shouldStop?.call() ?? false) return;
      // Claiming the index is a single synchronous step, so no two workers
      // can take the same one — there is no await between read and write.
      final index = next;
      if (index >= items.length) return;
      next = index + 1;
      results[index] = await task(items[index]);
    }
  }

  final workers = concurrency.clamp(1, items.length);
  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  return results;
}

/// [mapPooled] for work done purely for its side effects.
Future<void> forEachPooled<T>(
  List<T> items,
  Future<void> Function(T item) task, {
  int concurrency = 6,
  bool Function()? shouldStop,
}) async {
  // Mapped to a bool rather than void: a void-returning task cannot say
  // "nothing here" the way mapPooled's nullable result does, and the
  // discarded value keeps the pool's single implementation.
  await mapPooled<T, bool>(
    items,
    (item) async {
      await task(item);
      return true;
    },
    concurrency: concurrency,
    shouldStop: shouldStop,
  );
}

/// How many requests to have in flight, by kind of work.
///
/// Metadata fetches are small and latency-bound, so more of them pay off;
/// EPUBs are large and bandwidth-bound, where past a handful the same pipe
/// is just being shared more ways, and each file takes longer to finish.
/// Finishing downloads matters — a half-finished one is worth nothing —
/// so this stays deliberately low.
class PoolSize {
  static const int metadata = 6;
  static const int downloads = 3;
}
