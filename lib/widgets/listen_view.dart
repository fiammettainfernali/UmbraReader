import 'package:flutter/material.dart';

import '../models/reader_theme.dart';
import 'cached_cover.dart';
import 'seek_button.dart';

/// Full-screen "Listen" player — an Apple Music-style transport for hands-off
/// read-aloud. Shows the cover, title, current chapter, a progress bar, and
/// big play / chapter-skip controls, plus a quick speed toggle and a shortcut
/// into the read-aloud settings (voice, sleep timer, engine).
///
/// Stateless: the reader owns all state and rebuilds this as playback advances.
class ListenView extends StatelessWidget {
  const ListenView({
    super.key,
    required this.seriesId,
    required this.title,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterTotal,
    required this.progress,
    required this.minutesLeft,
    required this.isPlaying,
    required this.speedLabel,
    required this.sleepActive,
    required this.canSeek,
    required this.preset,
    required this.onClose,
    required this.onPlayPause,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onBack15,
    required this.onForward15,
    required this.onCycleSpeed,
    required this.onOpenSettings,
  });

  final int seriesId;
  final String title;
  final String chapterTitle;
  final int chapterIndex;
  final int chapterTotal;
  final double progress;
  final double minutesLeft;
  final bool isPlaying;
  final String speedLabel;
  final bool sleepActive;

  /// Whether the active engine supports 15-second seeking (Kokoro audio only).
  final bool canSeek;
  final ReaderThemePreset preset;

  final VoidCallback onClose;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onBack15;
  final VoidCallback onForward15;
  final VoidCallback onCycleSpeed;
  final VoidCallback onOpenSettings;

  Color get _text => preset.text;
  Color get _muted => preset.text.withValues(alpha: 0.6);
  Color get _accent => preset.isLight ? preset.secondary : preset.highlight;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Column(
          children: [
            // Top bar: collapse back to the reader + settings shortcut.
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  color: _text,
                  iconSize: 30,
                  tooltip: 'Back to reading',
                  onPressed: onClose,
                ),
                Expanded(
                  child: Text(
                    'Listening',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 13,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune),
                  color: _text,
                  tooltip: 'Read-aloud settings',
                  onPressed: onOpenSettings,
                ),
              ],
            ),
            const Spacer(flex: 2),
            // Cover art.
            Expanded(
              flex: 14,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedCover(
                      seriesId: seriesId,
                      coverUrl: null,
                      headers: const {},
                      fallback: ColoredBox(
                        color: _accent.withValues(alpha: 0.18),
                        child: Center(
                          child: Icon(
                            Icons.auto_stories_outlined,
                            color: _muted,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(flex: 2),
            // Title + current chapter.
            Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              chapterTitle,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _muted, fontSize: 15),
            ),
            const SizedBox(height: 18),
            // Progress bar + chapter / time-left labels.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: _text.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(_accent),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Chapter ${chapterIndex + 1} of $chapterTotal',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                Text(
                  _timeLeftLabel(),
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
            const Spacer(flex: 2),
            // Transport controls.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  color: _text,
                  iconSize: 32,
                  tooltip: 'Previous chapter',
                  onPressed: chapterIndex > 0 ? onPrevChapter : null,
                ),
                if (canSeek) ...[
                  const SizedBox(width: 8),
                  SeekButton(seconds: -15, color: _text, onTap: onBack15),
                ],
                const SizedBox(width: 16),
                _PlayButton(
                  isPlaying: isPlaying,
                  fill: _text,
                  icon: preset.background,
                  onPressed: onPlayPause,
                ),
                const SizedBox(width: 16),
                if (canSeek) ...[
                  SeekButton(seconds: 15, color: _text, onTap: onForward15),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  color: _text,
                  iconSize: 32,
                  tooltip: 'Next chapter',
                  onPressed:
                      chapterIndex < chapterTotal - 1 ? onNextChapter : null,
                ),
              ],
            ),
            const Spacer(flex: 2),
            // Quick controls: speed + sleep timer.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: onCycleSpeed,
                  icon: Icon(Icons.speed, color: _text, size: 20),
                  label: Text(
                    speedLabel,
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onOpenSettings,
                  icon: Icon(
                    sleepActive ? Icons.bedtime : Icons.bedtime_outlined,
                    color: sleepActive ? _accent : _text,
                    size: 20,
                  ),
                  label: Text(
                    sleepActive ? 'Sleep on' : 'Sleep',
                    style: TextStyle(
                      color: sleepActive ? _accent : _text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeLeftLabel() {
    if (!minutesLeft.isFinite || minutesLeft <= 0) return 'finishing up';
    final m = minutesLeft.ceil();
    return m >= 60
        ? '${m ~/ 60}h ${m % 60}m left'
        : '$m min left';
  }
}

/// The large circular play/pause button at the centre of the transport.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.fill,
    required this.icon,
    required this.onPressed,
  });

  final bool isPlaying;
  final Color fill;
  final Color icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 76,
          height: 76,
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: icon,
            size: 44,
          ),
        ),
      ),
    );
  }
}
