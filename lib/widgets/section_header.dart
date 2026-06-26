import 'package:flutter/material.dart';

/// The app's shared "witchy library" section heading — a serif title, a
/// candlelight sparkle, and a trailing rule — so every section reads the same
/// across screens. Optional [trailing] sits at the far right (e.g. an action).
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
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 15, color: theme.colorScheme.tertiary),
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
    );
  }
}
