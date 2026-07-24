import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_block.dart';
import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../models/volume.dart';
import '../services/reading_activity_store.dart';
import '../services/recommendation_feedback_store.dart';
import '../services/reminder_service.dart';
import 'block_view.dart';

/// The reader's session bookkeeping and its two gentle nudges, extracted from
/// the ReaderScreen State: how long this sitting has run, how many words of
/// the book have actually been consumed, the opt-in break check-in, and the
/// "Where was I?" re-entry aid.
///
/// These belong together because they all answer *how long and where have you
/// been reading* — the session clock feeds the break chip, and the same
/// foreground stretch that accumulates it is what writes the activity ledger.
///
/// The mixin owns every session-only field; everything it needs from the rest
/// of the reader goes through the abstract members below, which the State
/// implements as thin proxies onto its private fields.
mixin ReaderSession<T extends StatefulWidget> on State<T> {
  // ── what the reader State must provide ──────────────────────────────────

  Volume get readerVolume;
  ReaderSettings get readerSettings;
  List<ContentBlock>? get currentBlocks;

  /// Index of the block at the top of the viewport (page or scroll mode).
  int currentTopBlockIndex();

  /// Words of this book read so far, from the reading position — the input to
  /// the high-water mark below.
  int wordsReadInBook();

  /// Test-only overrides, proxied from the widget's static debug hooks so
  /// behaviours keyed on real reading time can be exercised without waiting.
  /// (Proxied rather than referenced directly to keep this file free of a
  /// dependency back on the screen that mixes it in.)
  Duration? get debugSessionElapsedOverride;
  Duration? get debugSessionDeltaOverride;

  // ── session state (owned by the mixin) ──────────────────────────────────

  final ReadingActivityStore _activityStore = ReadingActivityStore();

  /// When the current foreground stretch began; null while backgrounded.
  DateTime? _sessionStart;

  /// Foreground reading time already folded in by a flush. The live figure
  /// adds the time since [_sessionStart] on top.
  Duration _sessionElapsed = Duration.zero;
  Timer? _sessionTicker;

  /// The target has been passed and a break check-in is owed — it waits for
  /// the next chapter boundary rather than interrupting mid-page.
  bool _sessionBreakPending = false;
  bool _sessionBreakChip = false;
  Timer? _sessionBreakTimer;

  /// Furthest point in the book already counted into the words ledger, so
  /// re-reading adds nothing.
  int _wordsHighWater = 0;

  /// The paragraph to wash on re-entry after a gap, or null.
  int? _reentryBlock;
  Timer? _reentryTimer;

  // ── session clock ───────────────────────────────────────────────────────

  /// Live foreground reading time this open (accumulated + the current
  /// in-progress stretch).
  Duration get sessionLive {
    final override = debugSessionElapsedOverride;
    if (override != null) return override;
    final start = _sessionStart;
    return start == null
        ? _sessionElapsed
        : _sessionElapsed + DateTime.now().difference(start);
  }

  /// Progress toward the session target (0..1); 0 when the timer is off.
  double get sessionFraction {
    final target = readerSettings.sessionMinutes;
    if (target <= 0) return 0;
    return (sessionLive.inSeconds / (target * 60)).clamp(0.0, 1.0);
  }

  /// Starts a foreground stretch (reader opened).
  void beginSession() => _sessionStart = DateTime.now();

  /// Resumes a stretch after returning from the background.
  void resumeSession() => _sessionStart ??= DateTime.now();

  int get wordsHighWater => _wordsHighWater;

  /// Seeds the high-water mark when a book opens part-read, so resuming
  /// mid-book doesn't spike today's tally with words already consumed.
  set wordsHighWater(int value) => _wordsHighWater = value;

  /// A slow ticker so the quiet fill creeps forward and the target is noticed
  /// even while sitting on one page. Only runs when the timer is on.
  void startSessionTicker() {
    _sessionTicker?.cancel();
    _sessionTicker = null;
    if (readerSettings.sessionMinutes <= 0) return;
    _sessionTicker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {}); // refresh the fill
      noteSessionTarget();
    });
  }

  /// Marks the break check-in as due once the target is passed; the chip
  /// itself waits for the next chapter boundary.
  void noteSessionTarget() {
    if (readerSettings.sessionMinutes <= 0) return;
    if (_sessionBreakChip || _sessionBreakPending) return;
    if (sessionLive.inMinutes >= readerSettings.sessionMinutes) {
      _sessionBreakPending = true;
    }
  }

  bool get sessionBreakPending => _sessionBreakPending;
  bool get sessionBreakChipVisible => _sessionBreakChip;

  /// Surfaces the owed break check-in — called at a chapter boundary so it
  /// never interrupts mid-page. Auto-hides after a few seconds.
  void surfaceSessionBreak() {
    if (!_sessionBreakPending || _sessionBreakChip) return;
    _sessionBreakPending = false;
    setState(() => _sessionBreakChip = true);
    _sessionBreakTimer?.cancel();
    _sessionBreakTimer = Timer(const Duration(seconds: 14), () {
      if (mounted) setState(() => _sessionBreakChip = false);
    });
  }

  /// Clears both the owed check-in and any visible chip — used when the
  /// session target itself changes (including being turned off).
  void resetSessionBreak() {
    _sessionBreakPending = false;
    _sessionBreakTimer?.cancel();
    if (_sessionBreakChip) setState(() => _sessionBreakChip = false);
  }

  void dismissSessionBreak() {
    _sessionBreakTimer?.cancel();
    if (_sessionBreakChip) setState(() => _sessionBreakChip = false);
  }

  /// Records the time spent in the foreground reader since the last flush,
  /// plus the words newly consumed.
  Future<void> flushReadingSession() async {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;
    final delta =
        debugSessionDeltaOverride ?? DateTime.now().difference(start);
    if (delta.inSeconds <= 0) return;
    // A real reading session in this series is re-engagement: clear any
    // stale "no thanks" recommendation feedback (dismiss/reset) so the
    // series can participate in taste again. Fire-and-forget; forget() is
    // a no-op when there's nothing stored.
    if (delta.inMinutes >= 5) {
      RecommendationFeedbackStore().forget(readerVolume.seriesOpdsId);
    }
    // Fold the stretch into the gentle session-timer accumulator too.
    _sessionElapsed += delta;
    // New words this session = reading past the high-water mark. Re-reading
    // already-seen text adds nothing (mirrors TTS audio caching), so the
    // ledger measures genuine content consumed. The mark only advances when
    // the session is actually recorded, so a sub-second gap defers rather
    // than loses the words.
    final current = wordsReadInBook();
    final newWords = current > _wordsHighWater ? current - _wordsHighWater : 0;
    if (newWords > 0) _wordsHighWater = current;
    // Awaited so a background flush pushes the ledger that includes this
    // stretch, not the one before it.
    await _activityStore.record(readerVolume, delta, words: newWords);
    // Today now counts as read, so drop today's pending invitation. This
    // ordering matters: the reminder schedule is rebuilt from the ledger,
    // which has to have landed first.
    unawaited(ReminderService().refresh());
  }

  // ── "where was I?" re-entry ─────────────────────────────────────────────

  int? get reentryBlock => _reentryBlock;

  /// Sets the paragraph to wash on re-entry. Deliberately does not rebuild —
  /// the load path assigns it inside its own setState; call
  /// [armReentryTimer] afterwards to start the auto-hide.
  set reentryBlock(int? value) => _reentryBlock = value;

  /// Floats the "Where was I?" pill for a few seconds, then clears it.
  void armReentryTimer() {
    _reentryTimer?.cancel();
    _reentryTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _reentryBlock = null);
    });
  }

  void disposeSession() {
    _reentryTimer?.cancel();
    _sessionTicker?.cancel();
    _sessionBreakTimer?.cancel();
  }

  // ── chips + recap ───────────────────────────────────────────────────────

  /// The tappable "Where was I?" pill shown briefly on resume after a gap.
  Widget reentryChip(ReaderThemePreset preset) {
    return Material(
      color: preset.background.withValues(alpha: 0.96),
      elevation: 3,
      shape: StadiumBorder(
        side: BorderSide(color: preset.text.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          _reentryTimer?.cancel();
          setState(() => _reentryBlock = null);
          showRecap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history,
                size: 16,
                color: preset.text.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                'Where was I?',
                style: TextStyle(
                  color: preset.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The dismissible "good time for a break?" pill.
  Widget sessionBreakChip(ReaderThemePreset preset) {
    final mins = readerSettings.sessionMinutes;
    return Material(
      color: preset.background.withValues(alpha: 0.96),
      elevation: 3,
      shape: StadiumBorder(
        side: BorderSide(color: preset.text.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: dismissSessionBreak,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.self_improvement,
                size: 16,
                color: preset.text.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "You've been reading $mins min — a good time for a break?",
                  style: TextStyle(color: preset.text, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the previous few paragraphs leading up to the current spot, dimmed
  /// on the way in and brightest at the current paragraph — a gentle recap of
  /// context after being away.
  void showRecap() {
    final blocks = currentBlocks ?? const <ContentBlock>[];
    if (blocks.isEmpty) return;
    final end = currentTopBlockIndex().clamp(0, blocks.length - 1);
    // Walk back to include up to three text blocks before the current one.
    var start = end;
    var count = 0;
    for (var i = end - 1; i >= 0 && count < 3; i--) {
      if (blocks[i] is ParagraphBlock || blocks[i] is HeadingBlock) count++;
      start = i;
    }
    final preset = readerSettings.theme;
    final span = (end - start).clamp(1, 1 << 30);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: preset.background,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.62,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'WHERE YOU LEFT OFF',
                  style: TextStyle(
                    color: preset.secondary,
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = start; i <= end; i++)
                        if (blocks[i] is ParagraphBlock ||
                            blocks[i] is HeadingBlock)
                          Opacity(
                            opacity: i == end
                                ? 1.0
                                : (0.4 + 0.6 * ((i - start) / span))
                                      .clamp(0.4, 1.0),
                            child: BlockView(
                              block: blocks[i],
                              settings: readerSettings,
                              preset: preset,
                              isLast: i == end,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    child: const Text('Back to reading'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
