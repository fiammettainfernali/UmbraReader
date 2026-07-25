import 'package:flutter/material.dart';

import 'section_header.dart';

/// One row in an [showActionSheet].
class SheetAction<T> {
  const SheetAction({
    required this.value,
    required this.icon,
    required this.label,
    this.subtitle,
    this.isDestructive = false,
  });

  final T value;
  final IconData icon;
  final String label;

  /// What the action actually does, when the label alone leaves a question —
  /// the room a popup menu never had.
  final String? subtitle;

  /// Tints the row with the error colour, for actions that remove something.
  final bool isDestructive;
}

/// A section of related actions, drawn as one rounded card. A [title] gets the
/// app's section heading above it.
class SheetGroup<T> {
  const SheetGroup({this.title, required this.actions});

  final String? title;
  final List<SheetAction<T>> actions;
}

/// Presents a list of actions as a bottom sheet, returning the chosen value.
///
/// Umbra uses this rather than `PopupMenuButton` for anything with more than a
/// couple of entries. A popup opens from the top-right — the hardest place to
/// reach one-handed, which is how a phone is held while reading — is cramped
/// enough that every item is a bare label, and covers the content it is
/// anchored to. A sheet comes up under the thumb, has room for a line of
/// explanation per row, and gives each row a full-width tap target.
///
/// Styled to the rest of the app rather than left as stock Material: grouped
/// rounded cards, the candlelight section heading, and each icon in its own
/// tinted tile.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  String? title,
  required List<SheetGroup<T>> groups,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              SectionHeader(
                title,
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              ),
            for (final (i, group) in groups.indexed) ...[
              if (group.title != null)
                SectionHeader(
                  group.title!,
                  padding: EdgeInsets.fromLTRB(4, i == 0 ? 0 : 18, 4, 10),
                )
              else if (i > 0)
                const SizedBox(height: 12),
              _GroupCard<T>(actions: group.actions),
            ],
          ],
        ),
      ),
    ),
  );
}

/// One group of actions as a single rounded surface, with hairline separators
/// between rows — so a group reads as one object rather than loose tiles.
class _GroupCard<T> extends StatelessWidget {
  const _GroupCard({required this.actions});

  final List<SheetAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, action) in actions.indexed) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 68,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.25,
                  ),
                ),
              _ActionTile<T>(action: action),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionTile<T> extends StatelessWidget {
  const _ActionTile({required this.action});

  final SheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = action.isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.tertiary;
    return InkWell(
      onTap: () => Navigator.pop(context, action.value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
        child: Row(
          children: [
            // The icon gets its own softly tinted tile — candlelight amber,
            // or the error colour when the action removes something.
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(action.icon, size: 20, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: action.isDestructive
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
                  if (action.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.outline.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
