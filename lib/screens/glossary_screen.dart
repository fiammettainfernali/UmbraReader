import 'package:flutter/material.dart';

import '../services/glossary_store.dart';

/// A per-series character / term glossary the user builds as they read —
/// handy for webnovels with sprawling casts and unfamiliar translated names.
class GlossaryScreen extends StatefulWidget {
  const GlossaryScreen({
    super.key,
    required this.seriesId,
    required this.title,
  });

  final int seriesId;

  /// Series (or volume) title for the app-bar.
  final String title;

  @override
  State<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends State<GlossaryScreen> {
  final _store = GlossaryStore();
  List<GlossaryEntry>? _entries;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _store.list(widget.seriesId);
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  Future<void> _edit({GlossaryEntry? existing}) async {
    final result = await showDialog<({String term, String note})>(
      context: context,
      builder: (_) => _GlossaryEditor(existing: existing),
    );
    if (result == null) return;
    if (result.term.isEmpty) return;
    if (existing == null) {
      await _store.create(widget.seriesId, result.term, result.note);
    } else {
      await _store.upsert(
        widget.seriesId,
        existing.copyWith(term: result.term, note: result.note),
      );
    }
    await _load();
  }

  Future<void> _delete(GlossaryEntry entry) async {
    await _store.remove(widget.seriesId, entry.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = _entries;
    final q = _query.trim().toLowerCase();
    final visible = all == null
        ? const <GlossaryEntry>[]
        : q.isEmpty
        ? all
        : all
              .where((e) =>
                  e.term.toLowerCase().contains(q) ||
                  e.note.toLowerCase().contains(q))
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Glossary'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        tooltip: 'Add entry',
        child: const Icon(Icons.add),
      ),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
          ? _empty(theme)
          : Column(
              children: [
                if (all.length > 6)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: SearchBar(
                      hintText: 'Filter terms',
                      leading: const Icon(Icons.search),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = visible[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          entry.term,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: entry.note.isEmpty && entry.lastSeen == null
                            ? null
                            : Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  if (entry.note.isNotEmpty)
                                    Text(entry.note),
                                  if (entry.lastSeen case final seen?)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 3),
                                      child: Text(
                                        seen.label.isEmpty
                                            ? 'Seen while reading'
                                            : 'Last seen in ${seen.label}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                        onTap: () => _edit(existing: entry),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () => _delete(entry),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('No glossary entries yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Add characters, places or terms as you read so you can keep '
            'this series\' cast straight. Umbra then tracks which chapter '
            'each one last appeared in.',
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

/// Add/edit dialog returning the entered (term, note), or null on cancel.
class _GlossaryEditor extends StatefulWidget {
  const _GlossaryEditor({this.existing});

  final GlossaryEntry? existing;

  @override
  State<_GlossaryEditor> createState() => _GlossaryEditorState();
}

class _GlossaryEditorState extends State<_GlossaryEditor> {
  late final TextEditingController _term;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _term = TextEditingController(text: widget.existing?.term ?? '');
    _note = TextEditingController(text: widget.existing?.note ?? '');
  }

  @override
  void dispose() {
    _term.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New entry' : 'Edit entry'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _term,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Term',
              hintText: 'Character, place, or term',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Who/what they are, relationships, reminders…',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            (term: _term.text.trim(), note: _note.text.trim()),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
