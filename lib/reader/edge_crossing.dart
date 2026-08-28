/// Deciding when a swipe past the edge of a chapter means "next chapter".
///
/// This lives apart from the reader because getting it wrong is invisible:
/// the gesture simply does nothing, and the reader looks like it is working.
/// That is exactly what happened on Android, where the original test — "has
/// the scroll position moved past the extent?" — is always false no matter
/// how far the finger travels, so the whole feature was dead on the platform
/// while remaining fine on iOS.
///
/// The two platforms report the same drag in two unrelated ways:
///
///   * **Bouncing physics (iOS)** lets the position leave the content. The
///     distance shows up in the scroll metrics, and no overscroll
///     notification is sent at all.
///   * **Clamping physics (Android)** pins the position to the extent and
///     reports the delta it refused to apply as an `OverscrollNotification`.
///     The metrics never budge.
///
/// So both are fed in, and whichever actually moved decides.
library;

/// What a settled gesture asked for.
enum ChapterCross { none, next, previous }

/// Accumulates one gesture's travel past a content edge.
///
/// Feed it every notification of the gesture, then call [settle] when the
/// scroll ends. Signs follow the scroll axis: positive is past the end
/// (forward, later in the book), negative is past the start.
class EdgeCrossDetector {
  EdgeCrossDetector({this.threshold = 90});

  /// How far past the edge the drag must travel to count.
  ///
  /// Deliberately more than a stray flick: crossing a chapter by accident
  /// costs the reader their place, while a refused crossing costs one more
  /// swipe.
  final double threshold;

  double _bounced = 0;
  double _refused = 0;

  /// Travel recorded so far, signed, from whichever physics is reporting.
  double get travel =>
      _bounced.abs() >= _refused.abs() ? _bounced : _refused;

  /// Forget this gesture. Called at the start of a drag, and whenever a
  /// chapter change makes any travel recorded so far meaningless.
  void reset() {
    _bounced = 0;
    _refused = 0;
  }

  /// A delta the scrollable declined to apply (clamping physics).
  ///
  /// Summed rather than maximised: each update reports only that update's
  /// unapplied delta, so the total finger travel past the edge is the sum.
  /// Dragging back inside subtracts, which is the intent — a drag that
  /// returns to the edge is not a crossing.
  void noteRefused(double overscroll) => _refused += overscroll;

  /// The current scroll metrics (bouncing physics).
  ///
  /// Kept as a peak rather than a sum: the position genuinely sits out past
  /// the extent here, so its distance is already the total, and the release
  /// springs it back through smaller values that must not erase the reading.
  void noteMetrics({
    required double pixels,
    required double minExtent,
    required double maxExtent,
  }) {
    final pastEnd = pixels - maxExtent;
    final pastStart = pixels - minExtent;
    if (pastEnd > 0 && pastEnd > _bounced) _bounced = pastEnd;
    if (pastStart < 0 && pastStart < _bounced) _bounced = pastStart;
  }

  /// Reads the finished gesture and clears it.
  ChapterCross settle() {
    final amount = travel;
    reset();
    if (amount > threshold) return ChapterCross.next;
    if (amount < -threshold) return ChapterCross.previous;
    return ChapterCross.none;
  }
}
