// One voice for the semantic index, so a run can be read back off a device.
//
// This exists because of a day spent believing the index worked. It had
// never run once: the release build's shrinker had removed the runtime's
// classes, inference aborted in native code, and every surface the index
// feeds has a metadata fallback that looks fine. Nothing lied — nothing
// said anything at all. So now the index narrates itself, and "did it run,
// how many, how long" is a line in the log instead of an inference from
// how the shelves feel.
//
//   adb logcat | grep umbra/semantic
//
// Synchronous on purpose. debugPrint throttles, which queues lines and
// hands them over a second later; a native abort takes the process down
// with the queue still in it, and the line naming the book that killed it
// is exactly the line that would be lost.

import 'package:flutter/foundation.dart';

/// Prefix on every line, chosen to be greppable and to say whose it is.
const String kSemanticLogTag = 'umbra/semantic';

void semanticLog(String message) {
  debugPrintSynchronously('$kSemanticLogTag $message');
}

/// Durations the way a person reads them: milliseconds while it is quick,
/// seconds once it stops being.
String formatElapsed(Duration d) {
  final ms = d.inMilliseconds;
  if (ms < 1000) return '${ms}ms';
  return '${(ms / 1000).toStringAsFixed(1)}s';
}
