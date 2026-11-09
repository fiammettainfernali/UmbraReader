import 'package:flutter/material.dart';

import 'living_surfaces.dart';

/// The app's shared section heading — a title, a glimmering sparkle, and a
/// trailing rule — so every section reads the same across screens. It rises in
/// when it first appears. Optional [trailing] sits at the far right (e.g. an
/// action).
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 8),
    this.trailing,
  });

  final String title;
  final EdgeInsets padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RiseIn(
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Twinkle(
              phase: title.length.toDouble(),
              child: Icon(
                Icons.auto_awesome,
                size: 15,
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Divider(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                thickness: 1,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}
