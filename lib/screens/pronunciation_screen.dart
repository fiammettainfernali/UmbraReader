import 'package:flutter/material.dart';

import '../services/pronunciation_store.dart';
import '../widgets/section_header.dart';

/// Manage read-aloud pronunciation overrides for the Kokoro engine — a global
/// list plus a per-series list. Speak a term the way you want (e.g. "Klein" →
/// "Kline"). Series entries take priority over global ones.
class PronunciationScreen extends StatefulWidget {
  const PronunciationScreen({
    super.key,
    required this.seriesId,
    required this.seriesTitle,
  });

  final int seriesId;
  final String seriesTitle;

  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen> {
  final _store = PronunciationStore();
  List<PronunciationEntry> _global = const [];
  List<PronunciationEntry> _series = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final global = await _store.global();
    final series = await _store.series(widget.seriesId);
    if (!mounted) return;
    setState(() {
      _global = global;
      _series = series;
      _loading = false;
    });
  }

  Future<void> _addOrEdit({
    required bool series,
    PronunciationEntry? existing,
    int? index,
  }) async {
    final result = await showDialog<PronunciationEntry>(
      context: context,
      builder: (_) => _PronEditor(existing: existing),
    );
    if (result == null || result.term.trim().isEmpty) return;
    final list = List<PronunciationEntry>.of(series ? _series : _global);
    if (index != null) {
      list[index] = result;
    } else {
      list.add(result);
    }
    if (series) {
      await _store.saveSeries(widget.seriesId, list);
    } else {
      await _store.saveGlobal(list);
    }
    await _load();
  }

  Future<void> _delete({required bool series, required int index}) async {
    final list = List<PronunciationEntry>.of(series ? _series : _global)
      ..removeAt(index);
    if (series) {
      await _store.saveSeries(widget.seriesId, list);
    } else {
      await _store.saveGlobal(list);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pronunciations')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    'Teach the natural (Kokoro) voice how to say names and '
                    'terms. Type the word as it appears, and how it should '
                    'sound. Series entries override global ones.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                const SectionHeader('This series'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    widget.seriesTitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                ..._rows(_series, series: true),
                _addTile(series: true),
                const SizedBox(height: 12),
                const SectionHeader('All books'),
                ..._rows(_global, series: false),
                _addTile(series: false),
              ],
            ),
    );
  }

  List<Widget> _rows(List<PronunciationEntry> entries, {required bool series}) {
    return [
      for (var i = 0; i < entries.length; i++)
        ListTile(
          title: Text(entries[i].term),
          subtitle: Text('sounds like “${entries[i].soundsLike}”'),
          onTap: () => _addOrEdit(
            series: series,
            existing: entries[i],
            index: i,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _delete(series: series, index: i),
          ),
        ),
    ];
  }

  Widget _addTile({required bool series}) {
    return ListTile(
      leading: const Icon(Icons.add),
      title: Text(series ? 'Add for this series' : 'Add for all books'),
      onTap: () => _addOrEdit(series: series),
    );
  }
}

/// Dialog to add or edit one pronunciation override.
class _PronEditor extends StatefulWidget {
  const _PronEditor({this.existing});

  final PronunciationEntry? existing;

  @override
  State<_PronEditor> createState() => _PronEditorState();
}

class _PronEditorState extends State<_PronEditor> {
  late final TextEditingController _term;
  late final TextEditingController _sounds;

  @override
  void initState() {
    super.initState();
    _term = TextEditingController(text: widget.existing?.term ?? '');
    _sounds = TextEditingController(text: widget.existing?.soundsLike ?? '');
  }

  @override
  void dispose() {
    _term.dispose();
    _sounds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add pronunciation' : 'Edit'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _term,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Word',
              hintText: 'Klein',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sounds,
            decoration: const InputDecoration(
              labelText: 'Sounds like',
              hintText: 'Kline',
              border: OutlineInputBorder(),
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
            PronunciationEntry(_term.text.trim(), _sounds.text.trim()),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
