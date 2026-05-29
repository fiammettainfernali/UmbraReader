import 'package:flutter/material.dart';

import '../models/download_record.dart';
import '../models/volume.dart';
import '../services/download_service.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/reading_progress_store.dart';
import '../services/settings_service.dart';

/// Shows how much space downloaded books use, broken down by series, with
/// per-volume delete and a "delete finished" bulk action. Reading progress
/// is never touched — only the on-device EPUB files.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key, required this.settings});

  final OpdsSettings settings;

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  final _storage = LibraryStorage();
  late final DownloadStore _store = DownloadStore(_storage);
  late final DownloadService _service = DownloadService(
    settings: widget.settings,
    storage: _storage,
    store: _store,
  );

  bool _loading = true;

  /// seriesId → title, from the library cache.
  Map<int, String> _titles = const {};

  /// `seriesId/fileName` → whether that volume's reading is finished.
  Map<String, bool> _finished = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _store.load();
    final cache = LibraryCache(_storage);
    await cache.load();
    final entries = await ReadingProgressStore().allEntries();
    if (!mounted) return;
    setState(() {
      _titles = {for (final s in cache.series) s.opdsId: s.title};
      _finished = {
        for (final e in entries)
          '${e.volume.seriesOpdsId}/${e.volume.fileName}':
              e.progress.isFinished,
      };
      _loading = false;
    });
  }

  Volume _volumeFor(String key, DownloadRecord record) {
    final slash = key.indexOf('/');
    final seriesId =
        slash < 0 ? 0 : int.tryParse(key.substring(0, slash)) ?? 0;
    return Volume(
      seriesOpdsId: seriesId,
      title: record.fileName,
      fileName: record.fileName,
      downloadUrl: '',
      fileSizeBytes: record.sizeBytes,
      updatedAt: record.volumeUpdatedAt,
    );
  }

  Future<void> _delete(String key, DownloadRecord record) async {
    await _service.delete(_volumeFor(key, record));
    await _store.load();
    await _load();
  }

  Future<void> _deleteFinished() async {
    final confirmed = await _confirm(
      'Delete finished downloads?',
      'Removes the EPUB files of every volume you\'ve finished reading. '
          'Your progress is kept and you can re-download anytime.',
    );
    if (confirmed != true) return;
    for (final entry in _store.allRecords.entries) {
      if (_finished[entry.key] == true) {
        await _service.delete(_volumeFor(entry.key, entry.value));
      }
    }
    await _store.load();
    await _load();
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = _store.allRecords;
    final totalBytes = records.values.fold<int>(0, (s, r) => s + r.sizeBytes);
    final finishedCount = records.keys.where((k) => _finished[k] == true).length;

    // Group by series, sorted by size descending.
    final bySeries = <int, List<MapEntry<String, DownloadRecord>>>{};
    for (final e in records.entries) {
      final slash = e.key.indexOf('/');
      final id = slash < 0 ? 0 : int.tryParse(e.key.substring(0, slash)) ?? 0;
      bySeries.putIfAbsent(id, () => []).add(e);
    }
    final seriesGroups = bySeries.entries.toList()
      ..sort((a, b) {
        final aSize = a.value.fold<int>(0, (s, e) => s + e.value.sizeBytes);
        final bSize = b.value.fold<int>(0, (s, e) => s + e.value.sizeBytes);
        return bSize.compareTo(aSize);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Manage storage')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No downloads on this device.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sd_storage_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatBytes(totalBytes),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${records.length} volume'
                              '${records.length == 1 ? '' : 's'} downloaded',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (finishedCount > 0)
                  FilledButton.tonalIcon(
                    onPressed: _deleteFinished,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(
                      'Delete $finishedCount finished '
                      'download${finishedCount == 1 ? '' : 's'}',
                    ),
                  ),
                const SizedBox(height: 16),
                for (final group in seriesGroups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      _titles[group.key] ?? 'Series ${group.key}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final e in group.value)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        e.value.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_formatBytes(e.value.sizeBytes)}'
                        '${_finished[e.key] == true ? '  ·  Finished' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete download',
                        onPressed: () => _delete(e.key, e.value),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

/// Human-readable byte size: B / KB / MB / GB.
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}
