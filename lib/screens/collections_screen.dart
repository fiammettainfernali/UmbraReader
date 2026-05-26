import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../services/collection_store.dart';
import '../services/settings_service.dart';
import 'collection_detail_screen.dart';

/// User's library shelves — list of every collection they've created.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key, required this.settings});

  final OpdsSettings settings;

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  final _store = CollectionStore();
  List<Collection>? _collections;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.list();
    if (!mounted) return;
    setState(() => _collections = list);
  }

  Future<void> _create() async {
    final name = await _promptName(context, title: 'New collection');
    if (name == null) return;
    await _store.create(name);
    await _load();
  }

  Future<void> _rename(Collection c) async {
    final name = await _promptName(
      context,
      title: 'Rename collection',
      initial: c.name,
    );
    if (name == null) return;
    await _store.rename(c.id, name);
    await _load();
  }

  Future<void> _delete(Collection c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: const Text(
          'This removes the collection. The books in it stay in your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.delete(c.id);
    await _load();
  }

  Future<void> _open(Collection c) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollectionDetailScreen(
          collection: c,
          settings: widget.settings,
        ),
      ),
    );
    // Membership may have changed inside.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collections = _collections;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New collection',
            onPressed: _create,
          ),
        ],
      ),
      body: collections == null
          ? const Center(child: CircularProgressIndicator())
          : collections.isEmpty
          ? _empty(theme)
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: collections.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final c = collections[index];
                return ListTile(
                  leading: const Icon(Icons.collections_bookmark_outlined),
                  title: Text(c.name),
                  subtitle: Text(
                    c.count == 1 ? '1 book' : '${c.count} books',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  onTap: () => _open(c),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) {
                      if (action == 'rename') _rename(c);
                      if (action == 'delete') _delete(c);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _empty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.collections_bookmark_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No collections yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Create a collection to group books your own way — favourites, '
              'comfort reads, save-for-later, whatever fits.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Create collection'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pops a small text-input dialog and returns the entered name, or null if
/// the user cancelled or entered nothing.
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'e.g. Favourites',
          border: OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(dialogCtx).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogCtx).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.isEmpty) return null;
  return result;
}
