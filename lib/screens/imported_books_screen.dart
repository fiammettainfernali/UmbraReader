import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/volume.dart';
import '../services/imported_books_store.dart';
import 'reader_screen.dart';

/// Lists EPUBs the user sideloaded from Files, with an import button. These
/// live outside the OPDS library so they survive syncs.
class ImportedBooksScreen extends StatefulWidget {
  const ImportedBooksScreen({super.key});

  @override
  State<ImportedBooksScreen> createState() => _ImportedBooksScreenState();
}

class _ImportedBooksScreenState extends State<ImportedBooksScreen> {
  final _store = ImportedBooksStore();
  List<Volume>? _books;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final books = await _store.list();
    if (!mounted) return;
    setState(() => _books = books);
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
        withData: false,
      );
      final picked = result?.files.singleOrNull;
      final path = picked?.path;
      if (path == null) return;
      await _store.import(File(path), picked!.name);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imported.')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _open(Volume volume) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(volume: volume)),
    );
  }

  Future<void> _delete(Volume volume) async {
    await _store.delete(volume);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = _books;
    return Scaffold(
      appBar: AppBar(title: const Text('Imported books')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_importing ? 'Importing…' : 'Import EPUB'),
      ),
      body: books == null
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.upload_file_outlined,
                        size: 56, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('No imported books', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Import an .epub from Files or iCloud Drive to read '
                      'books that aren\'t on your Novel Grabber server.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              itemCount: books.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final book = books[index];
                return ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _open(book),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: () => _delete(book),
                  ),
                );
              },
            ),
    );
  }
}
