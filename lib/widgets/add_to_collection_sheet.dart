import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../services/collection_store.dart';

/// Bottom sheet that toggles a series's membership in each of the user's
/// collections, with a "New collection" inline create at the top.
class AddToCollectionSheet extends StatefulWidget {
  const AddToCollectionSheet({
    super.key,
    required this.seriesId,
    required this.seriesTitle,
  });

  final int seriesId;
  final String seriesTitle;

  @override
  State<AddToCollectionSheet> createState() => _AddToCollectionSheetState();
}

class _AddToCollectionSheetState extends State<AddToCollectionSheet> {
  final _store = CollectionStore();
  List<Collection>? _collections;
  Set<String> _selected = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _store.list();
    final selected = await _store.collectionsContaining(widget.seriesId);
    if (!mounted) return;
    setState(() {
      _collections = all;
      _selected = selected;
    });
  }

  Future<void> _toggle(Collection c, bool member) async {
    await _store.setMembership(c.id, widget.seriesId, member: member);
    await _load();
  }

  Future<void> _createInline() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('New collection'),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final created = await _store.create(name);
    // Add the current series to the brand-new collection automatically —
    // that's almost always what the user wants.
    await _store.setMembership(
      created.id,
      widget.seriesId,
      member: true,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collections = _collections;
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
                    'Add to collection',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Done',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                widget.seriesTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _createInline,
              icon: const Icon(Icons.add),
              label: const Text('New collection'),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Flexible(
              child: collections == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : collections.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'You don\'t have any collections yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: collections.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = collections[index];
                        final selected = _selected.contains(c.id);
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected,
                          onChanged: (v) => _toggle(c, v ?? false),
                          title: Text(c.name),
                          subtitle: Text(
                            c.count == 1
                                ? '1 book'
                                : '${c.count} books',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
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
