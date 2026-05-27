import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';

/// Backup & restore screen — lets the user export every locally-stored
/// SharedPreferences value as a JSON file via the share sheet, and import
/// one back from pasted text. The only safety net for reading data since
/// Umbra Reader has no cloud sync yet.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _service = BackupService();
  bool _exporting = false;
  bool _importing = false;
  String? _status;
  bool _statusIsError = false;

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _status = null;
    });
    try {
      final file = await _service.exportToFile();
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Umbra Reader backup',
          sharePositionOrigin: box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        ),
      );
      _setStatus('Backup ready — save it somewhere safe.');
    } on Exception catch (e) {
      _setStatus('Backup failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportAnnotations() async {
    setState(() {
      _exporting = true;
      _status = null;
    });
    try {
      final file = await _service.exportAnnotationsToFile();
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Umbra Reader annotations',
          sharePositionOrigin: box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        ),
      );
      _setStatus('Annotations exported.');
    } on Exception catch (e) {
      _setStatus('Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importAnnotationsFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      _setStatus('Nothing in the clipboard to restore.', isError: true);
      return;
    }
    setState(() {
      _importing = true;
      _status = null;
    });
    try {
      final n = await _service.importAnnotations(text);
      _setStatus('Restored annotations for $n book${n == 1 ? '' : 's'}.');
    } on BackupException catch (e) {
      _setStatus(e.message, isError: true);
    } on Exception catch (e) {
      _setStatus('Restore failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _restoreFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      _setStatus('Nothing in the clipboard to restore.', isError: true);
      return;
    }
    await _restore(text);
  }

  Future<void> _restoreFromText() async {
    final controller = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Paste backup JSON'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: 'Paste the contents of your backup file here',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(controller.text),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pasted == null || pasted.trim().isEmpty) return;
    await _restore(pasted);
  }

  Future<void> _restore(String text) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'This replaces all current reading data — progress, bookmarks, '
          'collections, settings — with the backup. There is no undo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _importing = true;
      _status = null;
    });
    try {
      final count = await _service.importFromJson(text);
      _setStatus(
        'Restored $count setting(s). Close and reopen the app to make sure '
        'every screen picks up the changes.',
      );
    } on BackupException catch (e) {
      _setStatus(e.message, isError: true);
    } on Exception catch (e) {
      _setStatus('Restore failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _setStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Save a copy of your reading data',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Umbra Reader stores reading progress, bookmarks, collections, '
            'recommendation feedback and settings on this device. Export a '
            'backup occasionally so you can restore everything after an app '
            'reinstall or when moving to a new device.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            label: Text(_exporting ? 'Exporting…' : 'Export full backup'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _exporting ? null : _exportAnnotations,
            icon: const Icon(Icons.bookmarks_outlined),
            label: const Text('Export annotations only'),
          ),
          const SizedBox(height: 4),
          Text(
            'Just your bookmarks and highlights — restorable on top of an '
            'existing install without overwriting other settings.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Restore from a backup',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Copy the contents of a backup file to your clipboard and tap '
            '"Restore from clipboard", or paste the JSON in manually.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _importing ? null : _restoreFromClipboard,
            icon: const Icon(Icons.content_paste),
            label: const Text('Restore from clipboard'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _importing ? null : _restoreFromText,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Paste manually'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _importing ? null : _importAnnotationsFromClipboard,
            icon: const Icon(Icons.bookmarks_outlined),
            label: const Text('Merge annotations from clipboard'),
          ),
          const SizedBox(height: 4),
          Text(
            'Adds bookmarks and highlights from a clipboard JSON without '
            'wiping anything else — accepts both annotation-only files and '
            'full backups.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusIsError
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _statusIsError
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
