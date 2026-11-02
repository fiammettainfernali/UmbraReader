import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../widgets/menu_row.dart';
import '../widgets/undo_snack.dart';
import '../models/volume.dart';
import '../screens/highlights_screen.dart';
import '../services/bookmark_store.dart';
import 'block_view.dart';

/// Bottom sheet listing this volume's bookmarks, with an "Add bookmark here"
/// button at the top. Pops with the [Bookmark] the user tapped, or null if
/// they only added/removed entries.
/// Carry-result of the highlight prompt: the note text plus the picked
/// color. Used so the prompt can return both pieces with a single dialog.
class _HighlightFields {
  const _HighlightFields(this.note, this.color);
  final String note;
  final HighlightColor color;
}

class BookmarksSheet extends StatefulWidget {
  const BookmarksSheet({
    super.key,
    required this.volume,
    required this.currentChapterIndex,
    required this.currentBlockIndex,
    required this.currentChapterTitle,
    required this.currentSnippet,
  });

  final Volume volume;
  final int currentChapterIndex;
  final int currentBlockIndex;
  final String currentChapterTitle;
  final String currentSnippet;

  @override
  State<BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<BookmarksSheet> {
  final _store = BookmarkStore();
  List<Bookmark>? _bookmarks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.list(widget.volume);
    if (!mounted) return;
    setState(() => _bookmarks = list);
  }

  Future<void> _addHere({bool asHighlight = false}) async {
    String note = '';
    var color = HighlightColor.yellow;
    if (asHighlight) {
      final result = await _promptForHighlight(
        initialNote: '',
        initialColor: color,
      );
      if (result == null) return;
      note = result.note;
      color = result.color;
    }
    final mark = Bookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      chapterIndex: widget.currentChapterIndex,
      blockIndex: widget.currentBlockIndex,
      chapterTitle: widget.currentChapterTitle,
      snippet: widget.currentSnippet,
      createdAt: DateTime.now(),
      isHighlight: asHighlight,
      note: note,
      color: color,
    );
    await _store.add(widget.volume, mark);
    await _load();
  }

  /// Deletes [mark], offering to put it back. `add` upserts by id, so the
  /// undo restores it exactly — colour, note, range and all.
  Future<void> _remove(Bookmark mark) async {
    await _store.remove(widget.volume, mark.id);
    await _load();
    if (!mounted) return;
    showUndoSnackBar(
      context,
      mark.isHighlight ? 'Highlight deleted' : 'Bookmark deleted',
      onUndo: () async {
        await _store.add(widget.volume, mark);
        await _load();
      },
    );
  }

  Future<void> _editNote(Bookmark mark) async {
    final result = await _promptForHighlight(
      initialNote: mark.note,
      initialColor: mark.color,
    );
    if (result == null) return;
    await _store.remove(widget.volume, mark.id);
    await _store.add(
      widget.volume,
      mark.copyWith(note: result.note, color: result.color),
    );
    await _load();
  }

  /// Dialog that captures the highlight's note + color. Returns null when
  /// the user cancels.
  Future<_HighlightFields?> _promptForHighlight({
    required String initialNote,
    required HighlightColor initialColor,
  }) async {
    return showDialog<_HighlightFields>(
      context: context,
      builder: (_) => _HighlightDialog(
        initialNote: initialNote,
        initialColor: initialColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marks = _bookmarks;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Bookmarks',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.list_alt_outlined),
                  tooltip: 'View all annotations',
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HighlightsScreen(
                          volume: widget.volume,
                          bookTitle: widget.volume.title,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Done',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _addHere(),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Bookmark'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _addHere(asHighlight: true),
                    icon: const Icon(Icons.brush_outlined),
                    label: const Text('Highlight'),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'In: ${widget.currentChapterTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            Flexible(
              child: marks == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : marks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'No bookmarks yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: marks.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final mark = marks[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  mark.chapterTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (mark.isHighlight) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: highlightPaintFor(mark.color),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Highlight',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mark.snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              if (mark.note.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    mark.note,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'More',
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  _editNote(mark);
                                case 'delete':
                                  _remove(mark);
                              }
                            },
                            itemBuilder: (_) => [
                              if (mark.isHighlight)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: MenuRow(Icons.edit_note, 'Edit note'),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: MenuRow(
                                  Icons.delete_outline,
                                  'Delete',
                                  isDestructive: true,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => Navigator.of(context).pop(mark),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The highlight editor: a note and a colour.
///
/// A widget rather than an AlertDialog built inline, because it owns the
/// text controller. A controller created by the caller and disposed as soon
/// as showDialog returns is disposed while the dialog is still closing and
/// the field is still painting — which crashes with "_dependents.isEmpty".
/// Owned here, the framework disposes it after the animation instead.
///
/// The colour lived in a StatefulBuilder before, which handled the colour
/// correctly and left the controller with nobody to own it.
class _HighlightDialog extends StatefulWidget {
  const _HighlightDialog({
    required this.initialNote,
    required this.initialColor,
  });

  final String initialNote;
  final HighlightColor initialColor;

  @override
  State<_HighlightDialog> createState() => _HighlightDialogState();
}

class _HighlightDialogState extends State<_HighlightDialog> {
  late final TextEditingController _note = TextEditingController(
    text: widget.initialNote,
  );
  late HighlightColor _color = widget.initialColor;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Highlight'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _note,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Optional note for this passage',
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            children: [
              for (final c in HighlightColor.values)
                Semantics(
                  button: true,
                  selected: _color == c,
                  label: '${c.name} highlight',
                  child: GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: highlightPaintFor(c),
                        border: Border.all(
                          color: _color == c
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_HighlightFields(_note.text.trim(), _color)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
