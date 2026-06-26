import 'dart:async';

import 'package:flutter/material.dart';

import '../services/control_client.dart';
import '../services/settings_service.dart';
import '../widgets/section_header.dart';
import 'novel_search_screen.dart';

/// Remote control for Novel Grabber: server/job status, a live download
/// queue, add-by-URL, and library-wide update checks — over the control API.
class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key, required this.settings});

  final OpdsSettings settings;

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  late final ControlClient _client = ControlClient(widget.settings);

  ControlStatus? _status;
  AutoUpdateSchedule? _schedule;
  ControlProgress? _progress;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  StreamSubscription<ControlEvent>? _events;

  @override
  void initState() {
    super.initState();
    _refresh();
    _subscribe();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _client.status();
      AutoUpdateSchedule? schedule;
      try {
        schedule = await _client.schedule();
      } on ControlException {
        schedule = null; // older server without the schedule endpoint
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _schedule = schedule;
        _loading = false;
      });
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _subscribe() {
    _events?.cancel();
    _events = _client.events().listen(
      (event) {
        if (!mounted) return;
        switch (event.type) {
          case 'progress':
            setState(() => _progress = event.progress);
          case 'queue':
          case 'snapshot':
            _refreshQuiet();
        }
      },
      onError: (_) {
        // The SSE drop is non-fatal; status polling / Retry still works.
      },
    );
  }

  /// Re-fetch status without flipping the screen into the loading state.
  Future<void> _refreshQuiet() async {
    try {
      final status = await _client.status();
      if (mounted) setState(() => _status = status);
    } on ControlException {
      // ignore — keep showing the last good status
    }
  }

  /// Runs a control action, surfacing errors as a snackbar.
  Future<void> _run(Future<void> Function() action, String ok) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      }
      await _refreshQuiet();
    } on ControlException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSearch() async {
    final sites = _status?.searchSites ?? const <String>[];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NovelSearchScreen(
          settings: widget.settings,
          sites: sites,
        ),
      ),
    );
    await _refreshQuiet();
  }

  Future<void> _editSchedule() async {
    final current = _schedule ??
        const AutoUpdateSchedule(mode: 'off', intervalMinutes: 60);
    final result = await showDialog<AutoUpdateSchedule>(
      context: context,
      builder: (_) => _ScheduleDialog(initial: current),
    );
    if (result == null) return;
    await _run(
      () => _client.setSchedule(
        result.mode,
        intervalMinutes: result.intervalMinutes,
      ),
      'Auto-update schedule saved',
    );
    try {
      final s = await _client.schedule();
      if (mounted) setState(() => _schedule = s);
    } on ControlException {
      // keep last known
    }
  }

  Future<void> _addByUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add novel by URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'https://…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;
    await _run(() => _client.addNovel(url), 'Queued — scraping started.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage server'),
        actions: [
          IconButton(
            icon: const Icon(Icons.travel_explore),
            tooltip: 'Find novels',
            onPressed: _status == null ? null : _openSearch,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorView()
          : _content(),
    );
  }

  Widget _errorView() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text("Can't reach the server", style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final theme = Theme.of(context);
    final status = _status!;
    final p = _progress;
    final showProgress = p != null && !p.isIdle;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── activity card ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      status.paused
                          ? Icons.pause_circle
                          : status.active
                          ? Icons.downloading
                          : Icons.check_circle_outline,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      status.paused
                          ? 'Paused'
                          : status.active
                          ? 'Working'
                          : 'Idle',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (showProgress) ...[
                  const SizedBox(height: 12),
                  Text(
                    p.novelTitle.isEmpty ? '—' : p.novelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    p.chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: p.total > 0 ? (p.percent / 100).clamp(0, 1) : null,
                      minHeight: 6,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.total > 0
                        ? '${p.current} / ${p.total}  ·  ${p.percent.round()}%'
                        : p.state,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ] else if (status.current != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    status.current!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    if (status.paused)
                      FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () => _run(_client.resume, 'Resumed'),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Resume'),
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () => _run(_client.pause, 'Paused'),
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(_client.skip, 'Skipped current'),
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Skip'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(_client.stop, 'Stopped'),
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── actions ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _addByUrl,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add by URL'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          _client.checkAllUpdates,
                          'Checking all series for new chapters…',
                        ),
                  icon: const Icon(Icons.sync),
                  label: const Text('Check all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── auto-update schedule ───────────────────────────────────
          if (_schedule != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Auto-update'),
              subtitle: Text(
                _scheduleLabel(_schedule!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              trailing: TextButton(
                onPressed: _busy ? null : _editSchedule,
                child: const Text('Edit'),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── queue ──────────────────────────────────────────────────
          SectionHeader(
            'Queue (${status.queue.length})',
            padding: const EdgeInsets.only(bottom: 4),
          ),
          if (status.queue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Nothing queued.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            )
          else
            for (var i = 0; i < status.queue.length; i++)
              _queueRow(theme, status.queue[i], i, status.queue.length),
        ],
      ),
    );
  }

  String _scheduleLabel(AutoUpdateSchedule s) {
    switch (s.mode) {
      case 'interval':
        final m = s.intervalMinutes;
        if (m % 60 == 0) {
          final h = m ~/ 60;
          return 'Every $h hour${h == 1 ? '' : 's'}';
        }
        return 'Every $m min';
      case 'schedule':
        return 'On a set schedule (edit times in the desktop app)';
      default:
        return 'Off';
    }
  }

  Widget _queueRow(ThemeData theme, QueueEntry e, int index, int count) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        e.action == 'update' ? 'Check for updates' : 'Download',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 20),
            tooltip: 'Move up',
            onPressed: _busy || index == 0
                ? null
                : () => _run(() => _client.move(index, -1), 'Moved up'),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 20),
            tooltip: 'Move down',
            onPressed: _busy || index == count - 1
                ? null
                : () => _run(() => _client.move(index, 1), 'Moved down'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Remove',
            onPressed: _busy
                ? null
                : () => _run(
                    () => _client.removeFromQueue(e.novelId),
                    'Removed from queue',
                  ),
          ),
        ],
      ),
    );
  }
}

/// Editor for the auto-update schedule. Supports Off and Every-N (interval).
/// A server already on the desktop-only "schedule" (specific times) mode keeps
/// that noted but switching away here is one-way.
class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.initial});

  final AutoUpdateSchedule initial;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late String _mode = widget.initial.mode;
  late final TextEditingController _interval = TextEditingController(
    text: '${widget.initial.intervalMinutes}',
  );

  @override
  void dispose() {
    _interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isScheduleMode = _mode == 'schedule';
    return AlertDialog(
      title: const Text('Auto-update'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'off', label: Text('Off')),
              ButtonSegment(value: 'interval', label: Text('Interval')),
            ],
            selected: {isScheduleMode ? 'interval' : _mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          if (isScheduleMode)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Currently on a fixed-times schedule set in the desktop app. '
                'Choosing Off or Interval here replaces it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_mode == 'interval' && !isScheduleMode) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _interval,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Every (minutes)',
                hintText: 'e.g. 360 for 6 hours',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final mode = isScheduleMode ? 'interval' : _mode;
            final minutes = int.tryParse(_interval.text.trim()) ??
                widget.initial.intervalMinutes;
            Navigator.of(context).pop(
              AutoUpdateSchedule(mode: mode, intervalMinutes: minutes),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
