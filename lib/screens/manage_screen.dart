import 'dart:async';

import 'package:flutter/material.dart';

import '../services/control_client.dart';
import '../services/pending_add_store.dart';
import '../services/settings_service.dart';
import '../widgets/action_sheet.dart';
import '../widgets/duplicate_sheet.dart';
import '../widgets/section_header.dart';
import 'browse_screen.dart';
import 'novel_search_screen.dart';

/// The queue entries whose title matches [query], each paired with its real
/// position in the unfiltered queue.
///
/// Pulled out of the widget because that pairing is the load-bearing part: a
/// filtered row's position on screen says nothing about where it sits in the
/// queue, and acting on the wrong one is invisible until the wrong book
/// downloads.
List<(int, QueueEntry)> filterQueue(List<QueueEntry> queue, String query) {
  final q = query.trim().toLowerCase();
  return [
    for (final (i, e) in queue.indexed)
      if (q.isEmpty || e.title.toLowerCase().contains(q)) (i, e),
  ];
}

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

  /// Filters the queue by title. A library-wide "Check all" queues every
  /// series at once, so the queue is routinely hundreds of rows long and
  /// scrolling to the one you care about is hopeless.
  final TextEditingController _queueSearch = TextEditingController();
  String _queueQuery = '';

  /// Below this the list is short enough to read at a glance, and the field
  /// would be clutter.
  static const int _searchThreshold = 8;

  /// Adds made while the server was unreachable, waiting to be sent.
  List<PendingAdd> _pending = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _subscribe();
  }

  @override
  void dispose() {
    _events?.cancel();
    _queueSearch.dispose();
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
      // A status that came back is proof the server is answering, which is
      // the moment anything queued offline can finally go.
      await _flushPending();
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
          case 'duplicate':
            // The same story under a different URL can only be judged once
            // the server has fetched the page, so the answer arrives here
            // rather than in the add's response.
            _onDuplicateWarning(event);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A queued add turned out to look like something already in the
  /// library. The server stopped rather than adding it; offer the choice.
  Future<void> _onDuplicateWarning(ControlEvent event) async {
    final warning = event.duplicate;
    if (warning == null || warning.matches.isEmpty || !mounted) return;
    final proceed = await confirmDuplicateAdd(
      context,
      title: warning.title,
      matches: warning.matches,
      sameUrl: warning.reason == 'url',
    );
    if (!proceed || !mounted) return;
    await _run(
      () => _client.addNovel(warning.url, force: true),
      'Adding “${warning.title}” anyway',
    );
  }

  Future<void> _openBrowser() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowseScreen(settings: widget.settings),
      ),
    );
    // Anything added in the browser lands in the queue below — or in the
    // waiting list, if it was added while out of range.
    await _refreshQuiet();
    await _flushPending();
  }

  /// Sends anything queued while the server was unreachable.
  Future<void> _flushPending() async {
    final store = PendingAddStore();
    final waiting = await store.list();
    if (waiting.isEmpty) {
      if (mounted && _pending.isNotEmpty) setState(() => _pending = const []);
      return;
    }
    final report = await store.flush(_client);
    if (!mounted) return;
    setState(() => _pending = report.stillWaiting > 0 ? waiting : const []);
    final summary = report.summary;
    if (summary != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(summary)));
    }
    if (report.sent > 0) await _refreshQuiet();
    if (report.stillWaiting > 0) {
      final left = await store.list();
      if (mounted) setState(() => _pending = left);
    }
  }

  Future<void> _forgetPending(PendingAdd entry) async {
    final next = await PendingAddStore().remove(entry.id);
    if (mounted) setState(() => _pending = next);
  }

  Future<void> _openSearch() async {
    final sites = _status?.searchSites ?? const <String>[];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NovelSearchScreen(settings: widget.settings, sites: sites),
      ),
    );
    await _refreshQuiet();
  }

  Future<void> _editSchedule() async {
    final current =
        _schedule ?? const AutoUpdateSchedule(mode: 'off', intervalMinutes: 60);
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
    await _addUrl(url);
  }

  /// Adds [url], asking first if the server says it already has it.
  Future<void> _addUrl(String url, {bool force = false}) async {
    try {
      await _client.addNovel(url, force: force);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Queued — scraping started.')),
      );
      await _refreshQuiet();
    } on DuplicateNovelException catch (e) {
      if (!mounted) return;
      final proceed = await confirmDuplicateAdd(
        context,
        title: e.matches.isEmpty ? url : e.matches.first.title,
        matches: e.matches,
        sameUrl: e.isSameUrl,
      );
      if (proceed && mounted) await _addUrl(url, force: true);
    } on ControlException catch (e) {
      if (!mounted) return;
      if (e.isUnreachable) {
        final waiting = await PendingAddStore().enqueue(url, force: force);
        if (!mounted) return;
        setState(() => _pending = waiting);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Novel Grabber isn't reachable — saved for when it is.",
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage server'),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: 'Browse the source sites',
            onPressed: _openBrowser,
          ),
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
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
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
    final queue = status.queue;
    final query = _queueQuery.trim().toLowerCase();
    // Each entry keeps its real queue position: the row displays it (so a
    // filtered list still says where things actually sit) and falls back to
    // it when talking to a server too old to hand out uids.
    final visible = filterQueue(queue, query);

    return RefreshIndicator(
      onRefresh: _refresh,
      // A sliver list rather than a plain ListView: a progress tick arrives
      // several times a second and rebuilds this screen, and building every
      // queued row each time is what made a long queue stutter.
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList.list(
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
                            value: p.total > 0
                                ? (p.percent / 100).clamp(0, 1)
                                : null,
                            minHeight: 6,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
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

                // ── waiting to send ────────────────────────────────
                if (_pending.isNotEmpty) ...[
                  SectionHeader(
                    'Waiting to send (${_pending.length})',
                    padding: const EdgeInsets.only(bottom: 4),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Added while Novel Grabber was out of reach. These go '
                      'as soon as it answers.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  for (final entry in _pending)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.cloud_upload_outlined,
                        color: theme.colorScheme.outline,
                      ),
                      title: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.attempts == 0
                            ? 'Waiting'
                            : 'Waiting · ${entry.attempts} attempt'
                                  '${entry.attempts == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Forget this one',
                        onPressed: () => _forgetPending(entry),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],

                // ── queue ──────────────────────────────────────────────────
                SectionHeader(
                  query.isEmpty
                      ? 'Queue (${queue.length})'
                      : 'Queue (${visible.length} of ${queue.length})',
                  padding: const EdgeInsets.only(bottom: 4),
                ),
                if (queue.length >= _searchThreshold) _queueSearchField(theme),
              ],
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            sliver: visible.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        queue.isEmpty
                            ? 'Nothing queued.'
                            : 'No queued series matches “$_queueQuery”.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  )
                : SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) => _queueRow(
                      theme,
                      visible[i].$2,
                      visible[i].$1,
                      queue.length,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _queueSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TextField(
        controller: _queueSearch,
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _queueQuery = v),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Find in queue',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _queueQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Clear',
                  onPressed: () {
                    _queueSearch.clear();
                    setState(() => _queueQuery = '');
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
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

  /// What this entry will do, including the chapter range when it has one —
  /// without it, a novel queued twice shows two identical rows.
  static String _queueSubtitle(QueueEntry e) {
    final what = e.action == 'update' ? 'Check for updates' : 'Download';
    final r = e.chapterRange;
    if (r != null && r.length == 2) return '$what · ch. ${r[0]}–${r[1]}';
    return what;
  }

  Widget _queueRow(ThemeData theme, QueueEntry e, int index, int count) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      // The real position, which a filtered list would otherwise hide: the
      // point of finding a series here is usually to see how far down it is.
      leading: SizedBox(
        width: 34,
        child: Text(
          '${index + 1}',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: index == 0
                ? theme.colorScheme.tertiary
                : theme.colorScheme.outline,
            fontWeight: index == 0 ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _queueSubtitle(e),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      // Promoting something is the reason to come looking for it, so that
      // one action stays a single tap; the rest moved into the sheet, which
      // four cramped icon buttons were never a good substitute for.
      trailing: IconButton(
        icon: const Icon(Icons.vertical_align_top, size: 20),
        tooltip: 'Move to top',
        onPressed: _busy || index == 0
            ? null
            : () => _run(
                () => _client.moveToTop(e, index: index),
                'Moved “${e.title}” to the top — it goes next',
              ),
      ),
      onTap: _busy ? null : () => _openQueueItemSheet(e, index, count),
    );
  }

  Future<void> _openQueueItemSheet(QueueEntry e, int index, int count) async {
    final moves = <SheetAction<String>>[
      if (index > 0)
        const SheetAction(
          value: 'top',
          icon: Icons.vertical_align_top,
          label: 'Move to top',
          subtitle: 'Goes next, ahead of everything else',
        ),
      if (index > 0)
        const SheetAction(
          value: 'up',
          icon: Icons.arrow_upward,
          label: 'Move up one',
        ),
      if (index < count - 1)
        const SheetAction(
          value: 'down',
          icon: Icons.arrow_downward,
          label: 'Move down one',
        ),
    ];

    final choice = await showActionSheet<String>(
      context,
      title: e.title,
      groups: [
        if (moves.isNotEmpty)
          SheetGroup(title: 'Position ${index + 1} of $count', actions: moves),
        SheetGroup(
          actions: const [
            SheetAction(
              value: 'remove',
              icon: Icons.close,
              label: 'Remove from queue',
              subtitle: 'Chapters already downloaded are kept',
              isDestructive: true,
            ),
          ],
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'top':
        await _run(
          () => _client.moveToTop(e, index: index),
          'Moved “${e.title}” to the top — it goes next',
        );
      case 'up':
        await _run(() => _client.nudge(e, -1, index: index), 'Moved up');
      case 'down':
        await _run(() => _client.nudge(e, 1, index: index), 'Moved down');
      case 'remove':
        await _run(
          () => _client.removeFromQueue(e),
          'Removed “${e.title}” from the queue',
        );
    }
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
            final minutes =
                int.tryParse(_interval.text.trim()) ??
                widget.initial.intervalMinutes;
            Navigator.of(
              context,
            ).pop(AutoUpdateSchedule(mode: mode, intervalMinutes: minutes));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
