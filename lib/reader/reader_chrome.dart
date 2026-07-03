/// The reader's overlay chrome: top bar (title + menu), bottom chapter
/// bar (progress scrubber, chapter stepper, read-aloud controls).
library;

import 'package:flutter/material.dart';

import '../feature_flags.dart';
import '../models/reader_theme.dart';
import '../widgets/seek_button.dart';

/// Overlay top bar: back, chapter title, reading settings, contents.
/// Actions in the reader's top-bar overflow menu.
enum ReaderMenu {
  contents,
  search,
  bookmarks,
  glossary,
  skip,
  pronunciations,
  prepareOffline,
  settings,
}

/// An icon + label row for a [PopupMenuItem].
class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.height,
    required this.title,
    required this.preset,
    required this.onBack,
    required this.onToggleListen,
    required this.onOpenSettings,
    required this.onShowContents,
    required this.onSearch,
    required this.onBookmarks,
    required this.onGlossary,
    required this.onOpenSkip,
    required this.onOpenPronunciations,
    required this.onPrepareOffline,
  });

  final double height;
  final String title;
  final ReaderThemePreset preset;
  final VoidCallback onBack;
  final VoidCallback onToggleListen;
  final VoidCallback onOpenSettings;
  final VoidCallback onShowContents;
  final VoidCallback onSearch;
  final VoidCallback onBookmarks;
  final VoidCallback onGlossary;
  final VoidCallback onOpenSkip;
  final VoidCallback onOpenPronunciations;
  final VoidCallback onPrepareOffline;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: preset.background,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      child: SizedBox(
        height: height,
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: preset.text,
                tooltip: 'Back',
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: preset.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (kReadAloudEnabled)
                IconButton(
                  icon: const Icon(Icons.headphones_outlined),
                  color: preset.text,
                  tooltip: 'Listen mode',
                  onPressed: onToggleListen,
                ),
              PopupMenuButton<ReaderMenu>(
                icon: Icon(Icons.more_vert, color: preset.text),
                tooltip: 'More',
                onSelected: (action) {
                  switch (action) {
                    case ReaderMenu.contents:
                      onShowContents();
                    case ReaderMenu.search:
                      onSearch();
                    case ReaderMenu.bookmarks:
                      onBookmarks();
                    case ReaderMenu.glossary:
                      onGlossary();
                    case ReaderMenu.skip:
                      onOpenSkip();
                    case ReaderMenu.pronunciations:
                      onOpenPronunciations();
                    case ReaderMenu.prepareOffline:
                      onPrepareOffline();
                    case ReaderMenu.settings:
                      onOpenSettings();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: ReaderMenu.contents,
                    child: _MenuRow(Icons.list, 'Contents'),
                  ),
                  const PopupMenuItem(
                    value: ReaderMenu.search,
                    child: _MenuRow(Icons.search, 'Search in book'),
                  ),
                  const PopupMenuItem(
                    value: ReaderMenu.bookmarks,
                    child: _MenuRow(Icons.bookmark_outline, 'Bookmarks'),
                  ),
                  const PopupMenuItem(
                    value: ReaderMenu.glossary,
                    child: _MenuRow(Icons.people_outline, 'Glossary'),
                  ),
                  if (kReadAloudEnabled) ...[
                    const PopupMenuItem(
                      value: ReaderMenu.skip,
                      child: _MenuRow(
                        Icons.filter_alt_outlined,
                        'Skip while reading',
                      ),
                    ),
                    const PopupMenuItem(
                      value: ReaderMenu.pronunciations,
                      child: _MenuRow(
                        Icons.record_voice_over_outlined,
                        'Pronunciations',
                      ),
                    ),
                    const PopupMenuItem(
                      value: ReaderMenu.prepareOffline,
                      child: _MenuRow(
                        Icons.download_for_offline_outlined,
                        'Prepare for offline',
                      ),
                    ),
                  ],
                  const PopupMenuItem(
                    value: ReaderMenu.settings,
                    child: _MenuRow(Icons.text_fields, 'Reading settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap = step one chapter; long-press opens a popup of larger jumps
/// (±5 / ±10 / ±25). Used for the prev/next chevrons in [ReaderChapterBar] —
/// scratches the very-long-webnovel itch where one chapter at a time is
/// useless when you want to leap across a 400-chapter book.
class _ChapterStepButton extends StatelessWidget {
  const _ChapterStepButton({
    required this.icon,
    required this.preset,
    required this.tooltip,
    required this.onTap,
    required this.onJump,
    required this.forward,
    required this.bound,
  });

  final IconData icon;
  final ReaderThemePreset preset;
  final String tooltip;
  final VoidCallback? onTap;
  final ValueChanged<int> onJump;

  /// Whether this button jumps forward (positive deltas) or back (negative).
  final bool forward;

  /// Largest absolute jump we should still offer, given how close to the
  /// book edge the reader is — caps the menu so an option doesn't run off
  /// the end of the book.
  final int bound;

  static const _jumps = [5, 10, 25];

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final available = _jumps.where((j) => j <= bound).toList();
    if (available.isEmpty) return;
    final picked = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.left,
        origin.top - 8 - 48.0 * available.length,
        origin.right,
        origin.bottom,
      ),
      items: [
        for (final j in available)
          PopupMenuItem<int>(
            value: forward ? j : -j,
            child: Text('${forward ? '+' : '−'}$j chapters'),
          ),
      ],
    );
    if (picked != null) onJump(picked);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onLongPress: enabled && bound > 1 ? () => _openMenu(context) : null,
        child: IconButton(
          icon: Icon(icon),
          color: preset.text,
          disabledColor: preset.secondary,
          onPressed: onTap,
        ),
      ),
    );
  }
}

/// Overlay bottom bar: previous / position / next chapter.
class ReaderChapterBar extends StatelessWidget {
  const ReaderChapterBar({
    super.key,
    required this.height,
    required this.preset,
    required this.index,
    required this.total,
    required this.progress,
    required this.minutesLeft,
    required this.bookMinutesLeft,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    required this.onJump,
    required this.isReading,
    required this.isPlaying,
    required this.canSeek,
    required this.onPlayPause,
    required this.onBack15,
    required this.onForward15,
  });

  final double height;
  final ReaderThemePreset preset;
  final int index;
  final int total;

  /// True when read-aloud is playing or paused (shows pause + seek controls).
  final bool isReading;
  final bool isPlaying;

  /// Whether the active engine supports 15-second seeking (Kokoro only).
  final bool canSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onBack15;
  final VoidCallback onForward15;

  /// Fraction (0..1) of the current chapter that has been read.
  final double progress;

  /// Estimated reading time remaining in the chapter, in minutes.
  final double minutesLeft;

  /// Estimated reading time remaining in the whole book, in minutes — null
  /// when no chapter word counts have been measured yet.
  final double? bookMinutesLeft;

  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Tap or drag along the progress bar to scrub to that fraction of the
  /// current chapter.
  final ValueChanged<double> onSeek;

  /// Skip forward (positive) or backward (negative) by N chapters — fired
  /// when the user picks a quick-skip option from the long-press menu on
  /// the prev/next chevrons.
  final ValueChanged<int> onJump;

  /// A short human label for the time left in the chapter and (when known)
  /// the rest of the book — e.g. "~5 min in chapter · ~2h left in book".
  String get _timeLabel {
    final chapter = minutesLeft < 0.5
        ? 'Almost done'
        : minutesLeft < 1.5
        ? '~1 min in chapter'
        : '~${minutesLeft.round()} min in chapter';
    final bk = bookMinutesLeft;
    if (bk == null || bk < 1) return chapter;
    return '$chapter · ${_formatBookLeft(bk)} in book';
  }

  /// Human-formatted book-remaining: "~12 min", "~2h", "~3h 25m".
  String _formatBookLeft(double minutes) {
    if (minutes < 60) return '~${minutes.round()} min';
    final h = minutes ~/ 60;
    final m = (minutes - h * 60).round();
    if (m == 0) return '~${h}h';
    return '~${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: preset.background,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      child: SizedBox(
        height: height,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A crisp hairline so the player reads as a distinct surface,
            // separated from the page content above it.
            Container(height: 0.5, color: preset.text.withValues(alpha: 0.10)),
            // Tap / drag along the bar to scrub through the current chapter.
            // Expanded vertically to make the touch target comfortable while
            // the actual visible bar stays a thin 3px line.
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                void seek(double localX) {
                  if (width <= 0) return;
                  onSeek((localX / width).clamp(0.0, 1.0));
                }

                final pct = (progress.clamp(0.0, 1.0) * 100).round();
                return Semantics(
                  slider: true,
                  label: 'Chapter progress',
                  value: '$pct percent',
                  // increase/decrease actions require the projected values
                  // to be annotated too — omitting them is a semantics-tree
                  // assertion (crash under VoiceOver).
                  increasedValue: '${(pct + 5).clamp(0, 100)} percent',
                  decreasedValue: '${(pct - 5).clamp(0, 100)} percent',
                  onIncrease: () => onSeek((progress + 0.05).clamp(0.0, 1.0)),
                  onDecrease: () => onSeek((progress - 0.05).clamp(0.0, 1.0)),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => seek(d.localPosition.dx),
                    onHorizontalDragStart: (d) => seek(d.localPosition.dx),
                    onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
                    child: SizedBox(
                      height: 16,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: preset.secondary.withValues(
                            alpha: 0.25,
                          ),
                          color: preset.text.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Chapter ${index + 1} of $total  ·  $_timeLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: preset.secondary, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ChapterStepButton(
                          icon: Icons.chevron_left,
                          preset: preset,
                          tooltip: 'Previous chapter (long-press to skip back)',
                          onTap: index > 0 ? onPrevious : null,
                          onJump: onJump,
                          forward: false,
                          bound: index,
                        ),
                        if (kReadAloudEnabled && isReading && canSeek)
                          SeekButton(
                            seconds: -15,
                            color: preset.text,
                            size: 32,
                            onTap: onBack15,
                          ),
                        if (kReadAloudEnabled)
                          IconButton(
                            iconSize: 40,
                            color: preset.text,
                            tooltip: isPlaying ? 'Pause' : 'Play',
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                            ),
                            onPressed: onPlayPause,
                          ),
                        if (kReadAloudEnabled && isReading && canSeek)
                          SeekButton(
                            seconds: 15,
                            color: preset.text,
                            size: 32,
                            onTap: onForward15,
                          ),
                        _ChapterStepButton(
                          icon: Icons.chevron_right,
                          preset: preset,
                          tooltip: 'Next chapter (long-press to skip ahead)',
                          onTap: index < total - 1 ? onNext : null,
                          onJump: onJump,
                          forward: true,
                          bound: total - index - 1,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
