import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/volume.dart';
import '../reader/block_view.dart';
import '../screens/reader_screen.dart';
import '../services/bookmark_store.dart';
import '../services/library_storage.dart';
import '../services/reading_progress_store.dart';

/// Every highlight, note and bookmark across the whole library.
///
/// These previously had exactly one home — the bookmarks sheet *inside* the
/// reader — so annotations spanning every book could only be seen one book at
/// a time, and only by opening a book first. This is the library-wide view.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

/// A mark plus the book it came from, once the volume has been resolved.
typedef _Entry = ({Bookmark mark, Volume? volume, String title});

class _NotesScreenState extends State<NotesScreen> {
  /// Null while loading.
  List<_Entry>? _entries;

  /// Show only marks with a highlight or a note, hiding plain position
  /// bookmarks — those are navigation, not thoughts.
  bool _onlyAnnotated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final marks = await BookmarkStore().allMarks();
    // Rows carry only the volume key, so join against reading positions to
    // recover the volume (needed to open the passage) and its title.
    final byKey = {
      for (final e in await ReadingProgressStore().allEntries())
        '${e.volume.seriesOpdsId}/${e.volume.fileName}': e.volume,
    };
    if (!mounted) return;
    setState(() {
      _entries = [
        for (final m in marks)
          (
            mark: m.mark,
            volume: byKey[m.volumeKey],
            title: byKey[m.volumeKey]?.title ?? m.volumeKey.split('/').last,
          ),
      ];
    });
  }

  Future<void> _open(_Entry entry) async {
    final volume = entry.volume;
    // A mark whose book is no longer in the library has nowhere to go; it is
    // rendered untappable rather than failing on touch.
    if (volume == null) return;
    final file = await LibraryStorage().epubFile(volume);
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That book isn\'t downloaded any more.')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          volume: volume,
          initialChapterIndex: entry.mark.chapterIndex,
          initialBlockIndex: entry.mark.blockIndex,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final all = _entries;
    final visible = all == null
        ? const <_Entry>[]
        : all
              .where(
                (e) =>
                    !_onlyAnnotated ||
                    e.mark.isHighlight ||
                    e.mark.note.isNotEmpty,
              )
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          if (all != null && all.isNotEmpty)
            IconButton(
              icon: Icon(
                _onlyAnnotated
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
              ),
              tooltip: _onlyAnnotated
                  ? 'Showing highlights and notes'
                  : 'Show only highlights and notes',
              onPressed: () =>
                  setState(() => _onlyAnnotated = !_onlyAnnotated),
            ),
        ],
      ),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : visible.isEmpty
          ? _empty(context, all.isEmpty)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _NoteRow(entry: visible[i], onTap: () => _open(visible[i])),
            ),
    );
  }

  Widget _empty(BuildContext context, bool nothingAtAll) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              nothingAtAll ? 'No notes yet' : 'Nothing highlighted yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              nothingAtAll
                  ? 'Long-press a word while reading to select it, then '
                        'highlight it or attach a note. Long-pressing empty '
                        'space saves the spot instead.'
                  : 'These are your saved spots. Highlights and notes will '
                        'show here too.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.entry, required this.onTap});

  final _Entry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mark = entry.mark;
    final openable = entry.volume != null;
    final body = mark.selectedText.isNotEmpty ? mark.selectedText : mark.snippet;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      onTap: openable ? onTap : null,
      leading: Container(
        width: 6,
        height: 44,
        decoration: BoxDecoration(
          color: mark.isHighlight
              ? highlightPaintFor(mark.color)
              : theme.colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(
        body,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mark.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  mark.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            Text(
              '${entry.title} · ${mark.chapterTitle}',
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
}
