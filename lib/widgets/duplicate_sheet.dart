import 'package:flutter/material.dart';

import '../services/control_client.dart';
import 'section_header.dart';

/// Asks whether to add a novel the server thinks you already have.
///
/// Deliberately a question rather than a refusal. The check is a
/// judgement — a title match with an author and chapter-count gate — and
/// it can be wrong: a genuine sequel, a rewrite, or a better translation
/// of the same work are all reasons to keep both. So it shows what it
/// found, says how sure it is, and leaves the decision alone.
///
/// Returns true when the reader wants it added anyway.
Future<bool> confirmDuplicateAdd(
  BuildContext context, {
  required String title,
  required List<DuplicateMatch> matches,
  required bool sameUrl,
}) async {
  final theme = Theme.of(context);
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: theme.colorScheme.surface,
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
            SectionHeader(
              sameUrl ? 'Already in your library' : 'You may already have this',
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Text(
                sameUrl
                    ? 'This is the same page you added before.'
                    : 'A different source in your library looks like the '
                          'same story as “$title”.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, m) in matches.indexed) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 16,
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.25,
                        ),
                      ),
                    ListTile(
                      title: Text(m.title),
                      subtitle: Text(
                        [
                          if (m.sourceSite.isNotEmpty) m.sourceSite,
                          if (m.totalChapters > 0)
                            '${m.totalChapters} chapters',
                          if (!sameUrl && m.similarity < 1.0)
                            '${(m.similarity * 100).round()}% title match',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: () => Navigator.of(sheetCtx).pop(false),
              child: const Text("Don't add it"),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(sheetCtx).pop(true),
              child: const Text('Add it anyway'),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
