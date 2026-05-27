import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/bookmark.dart';
import '../models/volume.dart';
import '../services/bookmark_store.dart';

/// Full-screen list of every saved highlight (and plain bookmark) in a
/// volume, grouped by chapter and with one-tap copy/share — built to dump
/// straight into Obsidian or any other note-taking app.
class HighlightsScreen extends StatefulWidget {
  const HighlightsScreen({
    super.key,
    required this.volume,
    required this.bookTitle,
  });

  final Volume volume;

  /// Human-readable book title for the screen header and export text.
  final String bookTitle;

  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  final _store = BookmarkStore();
  List<Bookmark>? _marks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.list(widget.volume);
    if (!mounted) return;
    // Order chronologically through the book (chapter then block index) so
    // the list reads in the same order as the book itself.
    list.sort((a, b) {
      final byChapter = a.chapterIndex.compareTo(b.chapterIndex);
      if (byChapter != 0) return byChapter;
      return a.blockIndex.compareTo(b.blockIndex);
    });
    setState(() => _marks = list);
  }

  /// Renders the annotations as a markdown-ish text blob suitable for
  /// pasting into Obsidian / a journal.
  String _toExportText(List<Bookmark> marks) {
    final buffer = StringBuffer('# ${widget.bookTitle}\n\n');
    String? lastChapter;
    for (final mark in marks) {
      if (mark.chapterTitle != lastChapter) {
        buffer.writeln('## ${mark.chapterTitle}\n');
        lastChapter = mark.chapterTitle;
      }
      final tag = mark.isHighlight ? 'Highlight' : 'Bookmark';
      buffer.writeln('- **$tag** — ${mark.snippet}');
      if (mark.note.isNotEmpty) {
        buffer.writeln('  > ${mark.note.replaceAll('\n', '\n  > ')}');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  Future<void> _copyAll() async {
    final marks = _marks;
    if (marks == null || marks.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _toExportText(marks)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  Future<void> _shareAll() async {
    final marks = _marks;
    if (marks == null || marks.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: _toExportText(marks),
        subject: 'Annotations from ${widget.bookTitle}',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marks = _marks;
    final hasAny = marks != null && marks.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy all',
            onPressed: hasAny ? _copyAll : null,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share',
            onPressed: hasAny ? _shareAll : null,
          ),
        ],
      ),
      body: marks == null
          ? const Center(child: CircularProgressIndicator())
          : marks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No bookmarks or highlights yet.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : _AnnotationList(marks: marks),
    );
  }
}

/// Grouped list — one section per chapter, each entry showing the snippet,
/// any note, and a chip distinguishing highlights from plain bookmarks.
class _AnnotationList extends StatelessWidget {
  const _AnnotationList({required this.marks});

  final List<Bookmark> marks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Build a flat item list of [header, mark, mark, header, mark, ...].
    final items = <_Item>[];
    String? lastChapter;
    for (final mark in marks) {
      if (mark.chapterTitle != lastChapter) {
        items.add(_HeaderItem(mark.chapterTitle));
        lastChapter = mark.chapterTitle;
      }
      items.add(_MarkItem(mark));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is _HeaderItem) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              item.title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        final mark = (item as _MarkItem).mark;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: mark.isHighlight
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        mark.isHighlight ? 'Highlight' : 'Bookmark',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: mark.isHighlight
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  mark.snippet,
                  style: theme.textTheme.bodyMedium,
                ),
                if (mark.note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      mark.note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

sealed class _Item {
  const _Item();
}

class _HeaderItem extends _Item {
  const _HeaderItem(this.title);
  final String title;
}

class _MarkItem extends _Item {
  const _MarkItem(this.mark);
  final Bookmark mark;
}
