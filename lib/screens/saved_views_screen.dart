import 'package:flutter/material.dart';

import '../models/saved_view.dart';
import '../services/saved_view_store.dart';
import '../widgets/action_sheet.dart';
import '../widgets/undo_snack.dart';
import 'library_cards.dart';

/// The user's named library arrangements. Tapping one returns it to the
/// library, which applies it.
///
/// A view is not a folder: nothing is filed into it, so a series that later
/// matches turns up without being added, and one that stops matching leaves.
/// That is the difference between this and Collections, and why both exist.
class SavedViewsScreen extends StatefulWidget {
  const SavedViewsScreen({super.key});

  @override
  State<SavedViewsScreen> createState() => _SavedViewsScreenState();
}

class _SavedViewsScreenState extends State<SavedViewsScreen> {
  final _store = SavedViewStore();
  List<SavedView>? _views;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final views = await _store.list();
    if (mounted) setState(() => _views = views);
  }

  Future<void> _openMenu(SavedView view) async {
    final choice = await showActionSheet<String>(
      context,
      title: view.name,
      groups: [
        SheetGroup(
          actions: const [
            SheetAction(
              value: 'apply',
              icon: Icons.play_arrow,
              label: 'Use this view',
              subtitle: 'Apply it to the library',
            ),
            SheetAction(
              value: 'rename',
              icon: Icons.drive_file_rename_outline,
              label: 'Rename',
            ),
          ],
        ),
        SheetGroup(
          actions: const [
            SheetAction(
              value: 'delete',
              icon: Icons.delete_outline,
              label: 'Delete view',
              subtitle: 'Your books are untouched — only the shortcut goes',
              isDestructive: true,
            ),
          ],
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'apply':
        Navigator.of(context).pop(view);
      case 'rename':
        await _rename(view);
      case 'delete':
        await _delete(view);
    }
  }

  Future<void> _rename(SavedView view) async {
    final controller = TextEditingController(text: view.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename view'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final next = await _store.rename(view.id, name);
    if (mounted) setState(() => _views = next);
  }

  Future<void> _delete(SavedView view) async {
    final next = await _store.delete(view.id);
    if (!mounted) return;
    setState(() => _views = next);
    showUndoSnackBar(
      context,
      'Deleted “${view.name}”',
      onUndo: () async {
        // Re-created rather than restored in place: the store keeps no
        // tombstones, so the honest thing is a fresh entry with the same
        // contents. It lands at the end of the list.
        final restored = await _store.create(
          view.name,
          view.view,
          query: view.query,
        );
        if (mounted) setState(() => _views = restored);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final views = _views;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved views')),
      body: views == null
          ? const Center(child: CircularProgressIndicator())
          : views.isEmpty
          ? MessageView(
              icon: Icons.bookmarks_outlined,
              title: 'No saved views yet',
              message:
                  'Narrow the library how you like it, then choose '
                  '"Save this view" from the library menu.',
              actionLabel: 'Back to library',
              onAction: () => Navigator.of(context).pop(),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: views.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final view = views[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.bookmarks_outlined,
                      size: 20,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                  title: Text(view.name),
                  subtitle: Text(
                    view.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(view),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_horiz, size: 20),
                    tooltip: 'More',
                    onPressed: () => _openMenu(view),
                  ),
                );
              },
            ),
    );
  }
}
