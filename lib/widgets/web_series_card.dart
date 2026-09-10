// A followed comic on the library shelf.
//
// Deliberately shaped like the book cards beside it: a followed series is a
// thing you are reading, and the fact that its pages happen to live on a
// website rather than in an EPUB on the device is not something the shelf
// should make you think about. The one honest difference is the subtitle,
// which counts chapters on the site rather than progress through a file.

import 'package:flutter/material.dart';

import '../services/web_series_store.dart';

class WebSeriesCard extends StatelessWidget {
  const WebSeriesCard({
    super.key,
    required this.series,
    this.onTap,
    this.onLongPress,
    this.width = 120,
  });

  final WebSeries series;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double width;

  /// "Chapter 212 of 260", or as much of that as is actually known.
  ///
  /// Nothing here is invented. Before a series has been opened there is no
  /// progress to report, and a site that does not number its chapters
  /// legibly gives no total — in both cases the card says less rather than
  /// guessing.
  String _subtitle() {
    final read = series.readChapter;
    final latest = series.latestChapter;
    if (read == null) {
      return latest == null ? 'Not started' : 'Not started · ${_n(latest)} up';
    }
    if (latest == null) return 'Chapter ${_n(read)}';
    return 'Chapter ${_n(read)} of ${_n(latest)}';
  }

  static String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = series.coverUrl;
    final unread = series.unreadCount;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 0.68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: cover == null
                        ? _placeholder(theme)
                        : Image.network(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder(theme),
                          ),
                  ),
                  if (series.hasUnread)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          unread == null ? 'New' : '$unread new',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onTertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              series.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _subtitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => ColoredBox(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.menu_book_outlined,
      color: theme.colorScheme.outline,
      size: 28,
    ),
  );
}
