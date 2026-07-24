import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/reading_progress_store.dart';
import '../widgets/cached_cover.dart';

/// A single cover in the library grid: cover art, title, author.
class SeriesCard extends StatelessWidget {
  const SeriesCard({super.key, 
    required this.series,
    required this.imageHeaders,
    required this.updateAvailable,
    required this.onTap,
    required this.onLongPress,
  });

  final Series series;
  final Map<String, String> imageHeaders;

  /// True when the series has content newer than what's been downloaded.
  final bool updateAvailable;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label:
          '${series.title} by ${series.author}'
          "${updateAvailable ? '. New chapters available' : ''}",
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CoverImage(series: series, headers: imageHeaders),
                      if (series.hasMultipleVolumes)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: VolumeBadge(),
                        ),
                      if (updateAvailable)
                        const Positioned(
                          top: 6,
                          left: 6,
                          child: UpdateBadge(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              series.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              series.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card on the "Continue reading" shelf: cover, title, and progress.
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, 
    required this.entry,
    required this.series,
    required this.imageHeaders,
    required this.onTap,
    required this.onLongPress,
  });

  final ReadingEntry entry;

  /// The owning series, if it's in the loaded library — for the cover art.
  final Series? series;
  final Map<String, String> imageHeaders;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = entry.progress;
    final title = series?.title ?? entry.volume.title;
    final chapterLabel = progress.chapterCount > 0
        ? 'Chapter ${progress.chapterIndex + 1} of ${progress.chapterCount}'
        : 'Chapter ${progress.chapterIndex + 1}';
    return Semantics(
      button: true,
      label: 'Continue reading $title, $chapterLabel',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 124,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 124,
                height: 165,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: series != null
                        ? CoverImage(series: series!, headers: imageHeaders)
                        : TitleCover(title: entry.volume.title),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                chapterLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card showing a series cover, title and author. Used by both the
/// "Recommended for you" and "Recently updated" shelves; the ✕ dismiss
/// button only appears when [onDismiss] is supplied.
class RecommendCard extends StatelessWidget {
  const RecommendCard({super.key, 
    required this.series,
    required this.imageHeaders,
    required this.onTap,
    this.reason = '',
    this.isWildcard = false,
    this.onDismiss,
    this.onLike,
    this.onLongPress,
  });

  final Series series;
  final Map<String, String> imageHeaders;
  final VoidCallback onTap;

  /// The engine's "Because…" line — why this pick is here.
  final String reason;

  /// True for the daily out-of-taste exploration pick.
  final bool isWildcard;

  final VoidCallback? onDismiss;

  /// 👍 "more like this" — the engine's explicit positive signal.
  final VoidCallback? onLike;

  /// Opens the full feedback options sheet (like / snooze / dismiss).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${series.title} by ${series.author}'
          '${reason.isEmpty ? '' : '. $reason'}',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 124,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 124,
                height: 165,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedCover(
                          seriesId: series.opdsId,
                          coverUrl: series.coverUrl,
                          headers: imageHeaders,
                          fallback: TitleCover(title: series.title),
                        ),
                        if (onDismiss != null)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: DismissChip(onPressed: onDismiss!),
                          ),
                        if (onLike != null)
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: LikeChip(onPressed: onLike!),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: Text(
                  series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                series.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    // The wildcard's "Something different" reads as a badge.
                    color: isWildcard
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.85),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled gradient panel used when no cover art is available.
class TitleCover extends StatelessWidget {
  const TitleCover({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
          ),
        ),
      ),
    );
  }
}

/// Cover art for a series — the network image, or a titled gradient fallback
/// when there is no cover or it fails to load.
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.series, required this.headers});

  final Series series;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return CachedCover(
      seriesId: series.opdsId,
      coverUrl: series.coverUrl,
      headers: headers,
      fallback: _fallback(context),
    );
  }

  /// A gradient panel showing the title — looks intentional, not broken.
  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Center(
          child: Text(
            series.title,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small corner badge marking a series that has more than one volume.
class VolumeBadge extends StatelessWidget {
  const VolumeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.collections_bookmark,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}

/// A small "not interested" ✕ button overlaid on a recommendation card. Taps
/// dismiss the recommendation and feed a soft-negative back to the engine.
class DismissChip extends StatelessWidget {
  const DismissChip({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Not interested',
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// The 👍 "more like this" chip on a recommendation card.
class LikeChip extends StatelessWidget {
  const LikeChip({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'More like this',
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.thumb_up, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Corner badge marking a series with content newer than what's downloaded.
class UpdateBadge extends StatelessWidget {
  const UpdateBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.update, size: 15, color: Colors.white),
    );
  }
}

/// A centered icon + message + action button, used for the empty / error /
/// not-connected / no-matches states.
class MessageView extends StatelessWidget {
  const MessageView({super.key, 
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  /// Optional second, lower-emphasis action (e.g. "Import books" next to
  /// "Connect" on the no-server state).
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
