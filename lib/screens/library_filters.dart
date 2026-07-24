import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/library_storage.dart';
import '../services/reading_progress_store.dart';
import '../services/series_status_store.dart';

/// How the library grid is ordered.
enum LibrarySort {
  titleAsc('Title (A–Z)'),
  recentlyUpdated('Recently updated'),
  recentlyRead('Recently read'),
  author('Author'),
  readingStatus('Reading status');

  const LibrarySort(this.label);

  /// Human-readable label shown in the sort menu.
  final String label;
}

/// Quick reading-state chip selection above the library grid.
enum ReadingStateFilter {
  any('All'),
  inProgress('Reading'),
  unread('Unread'),
  finished('Finished'),
  dropped('Dropped');

  const ReadingStateFilter(this.label);

  final String label;
}


/// Sort rank for reading statuses — active series first, finished/abandoned last.
int _statusRank(String status) => switch (status.toLowerCase()) {
  'ongoing' => 0,
  'hiatus' => 1,
  'completed' => 2,
  'dropped' => 3,
  _ => 4,
};

/// Search, filtering and sort for the library grid, extracted from its State.
///
/// This owns what the reader has *asked to see* — the query, the filter set,
/// the reading-state chip and the sort order — and derives [visibleLibrary]
/// from it. Everything it needs about the library itself comes in through the
/// abstract members below as reads, so the mixin narrows the view without
/// ever driving the screen.
mixin LibraryFiltering<T extends StatefulWidget> on State<T> {
  // ── what the library State must provide ─────────────────────────────────

  List<Series>? get librarySeries;
  DownloadStore? get downloadStore;
  List<ReadingEntry> get readingEntries;
  Map<int, SeriesStatus> get seriesStatuses;

  /// Opens full-text search across every downloaded book.
  void openLibrarySearch();

  // ── view state (owned by the mixin) ─────────────────────────────────────

  final TextEditingController searchController = TextEditingController();

  String searchQuery = '';
  LibrarySort sort = LibrarySort.titleAsc;
  ReadingStateFilter readingState = ReadingStateFilter.any;
  LibraryFilters filters = const LibraryFilters();

  /// True when nothing is narrowing the grid — the empty state differs
  /// between "no books" and "no matches".
  bool get filtersAreClear =>
      filters.isEmpty &&
      searchQuery.trim().isEmpty &&
      readingState == ReadingStateFilter.any;

  void disposeFiltering() => searchController.dispose();

  /// Per-series reading state, derived from saved progress entries. A series
  /// counts as "in progress" if any of its volumes has been started and not
  /// finished, and "finished" if every started volume is finished.
  ({Set<int> inProgress, Set<int> finished, Map<int, DateTime> lastReadAt})
  get _seriesReadingState {
    final inProgress = <int>{};
    final finished = <int>{};
    final lastReadAt = <int, DateTime>{};
    for (final e in readingEntries) {
      final id = e.volume.seriesOpdsId;
      if (e.progress.isFinished) {
        finished.add(id);
      } else if (e.progress.isStarted) {
        inProgress.add(id);
      } else {
        inProgress.add(id); // saved entry but at the start = still "reading"
      }
      final updated = e.progress.updatedAt;
      if (updated != null) {
        final prev = lastReadAt[id];
        if (prev == null || updated.isAfter(prev)) {
          lastReadAt[id] = updated;
        }
      }
    }
    // A series with both an in-progress entry and a finished one is still
    // "in progress" — the user hasn't put it down.
    finished.removeAll(inProgress);
    return (inProgress: inProgress, finished: finished, lastReadAt: lastReadAt);
  }

  /// The library after applying the active search, filter set, and sort.
  List<Series> get visibleLibrary {
    final all = librarySeries ?? const <Series>[];
    final query = searchQuery.trim().toLowerCase();
    final downloads = downloadStore;
    final readState = _seriesReadingState;
    final filtered = <Series>[];
    for (final series in all) {
      if (query.isNotEmpty) {
        if (!series.title.toLowerCase().contains(query) &&
            !series.author.toLowerCase().contains(query)) {
          continue;
        }
      }
      if (!filters.matches(
        series,
        isDownloaded:
            downloads?.recordsForSeries(series.opdsId).isNotEmpty ?? false,
      )) {
        continue;
      }
      if (readingState != ReadingStateFilter.any &&
          _resolvedState(series, readState) != readingState) {
        continue;
      }
      filtered.add(series);
    }
    filtered.sort(_comparatorFor(sort, readState.lastReadAt));
    return filtered;
  }

  /// Resolves a series to a single reading state for the filter chips. A
  /// manual [SeriesStatus] (set on the detail screen) wins; otherwise the
  /// state is inferred from reading progress.
  ReadingStateFilter _resolvedState(
    Series series,
    ({Set<int> inProgress, Set<int> finished, Map<int, DateTime> lastReadAt})
    readState,
  ) {
    switch (seriesStatuses[series.opdsId]) {
      case SeriesStatus.dropped:
        return ReadingStateFilter.dropped;
      case SeriesStatus.caughtUp:
        return ReadingStateFilter.finished;
      case SeriesStatus.reading:
        return ReadingStateFilter.inProgress;
      case SeriesStatus.none:
      case null:
        break;
    }
    if (readState.finished.contains(series.opdsId)) {
      return ReadingStateFilter.finished;
    }
    if (readState.inProgress.contains(series.opdsId)) {
      return ReadingStateFilter.inProgress;
    }
    return ReadingStateFilter.unread;
  }

  /// Every distinct genre tag present across the library — used to build the
  /// filter sheet's genre chip set.
  List<String> get _allGenres {
    final set = <String>{};
    for (final s in librarySeries ?? const <Series>[]) {
      for (final g in s.genres) {
        final clean = g.trim();
        if (clean.isNotEmpty) set.add(clean);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Every distinct reading status the library uses.
  List<String> get _allStatuses {
    final set = <String>{};
    for (final s in librarySeries ?? const <Series>[]) {
      final clean = s.readingStatus.trim().toLowerCase();
      if (clean.isNotEmpty) set.add(clean);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _openFilters() async {
    final next = await showModalBottomSheet<LibraryFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (_) => _LibraryFilterSheet(
        initial: filters,
        allGenres: _allGenres,
        allStatuses: _allStatuses,
      ),
    );
    if (next == null) return;
    setState(() => filters = next);
  }

  Comparator<Series> _comparatorFor(
    LibrarySort sort,
    Map<int, DateTime> lastReadAt,
  ) {
    int byTitle(Series a, Series b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return switch (sort) {
      LibrarySort.titleAsc => byTitle,
      LibrarySort.recentlyUpdated => (a, b) {
        final at = a.updatedAt;
        final bt = b.updatedAt;
        if (at == null && bt == null) return byTitle(a, b);
        if (at == null) return 1; // undated series sink to the bottom
        if (bt == null) return -1;
        return bt.compareTo(at); // newest first
      },
      LibrarySort.recentlyRead => (a, b) {
        final at = lastReadAt[a.opdsId];
        final bt = lastReadAt[b.opdsId];
        if (at == null && bt == null) return byTitle(a, b);
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      },
      LibrarySort.author => (a, b) {
        final c = a.author.toLowerCase().compareTo(b.author.toLowerCase());
        return c != 0 ? c : byTitle(a, b);
      },
      LibrarySort.readingStatus => (a, b) {
        final c = _statusRank(
          a.readingStatus,
        ).compareTo(_statusRank(b.readingStatus));
        return c != 0 ? c : byTitle(a, b);
      },
    };
  }

  void clearSearch() {
    searchController.clear();
    setState(() => searchQuery = '');
  }

  /// The search field, sort menu, and result-count line.
  Widget buildControls(int total, int visible) {
    final theme = Theme.of(context);
    final searching = searchQuery.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SearchBar(
                  controller: searchController,
                  hintText: 'Search by title or author',
                  leading: const Icon(Icons.search),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12),
                  ),
                  trailing: [
                    if (searching)
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear',
                        onPressed: clearSearch,
                      ),
                  ],
                  onChanged: (value) => setState(() => searchQuery = value),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.manage_search),
                tooltip: 'Search inside books',
                onPressed: openLibrarySearch,
              ),
              IconButton(
                icon: Badge(
                  isLabelVisible: !filters.isEmpty,
                  smallSize: 8,
                  child: const Icon(Icons.filter_list),
                ),
                tooltip: 'Filter library',
                onPressed: _openFilters,
              ),
              PopupMenuButton<LibrarySort>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort',
                initialValue: sort,
                onSelected: (value) => setState(() => sort = value),
                itemBuilder: (context) => [
                  for (final option in LibrarySort.values)
                    PopupMenuItem<LibrarySort>(
                      value: option,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: option == sort
                                ? const Icon(Icons.check, size: 18)
                                : null,
                          ),
                          Text(option.label),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Quick reading-state chips: a tap-friendly way to narrow the grid
          // down to what's actually being read (or the unread backlog) without
          // diving into the full filter sheet.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final state in ReadingStateFilter.values) ...[
                  ChoiceChip(
                    label: Text(state.label),
                    selected: readingState == state,
                    onSelected: (_) => setState(() => readingState = state),
                  ),
                  if (state != ReadingStateFilter.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            visible == total
                ? '$total series  ·  ${sort.label}'
                : '$visible of $total series  ·  ${sort.label}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// The active set of library filters, applied alongside search + sort.
class LibraryFilters {
  const LibraryFilters({
    this.genres = const {},
    this.statuses = const {},
    this.downloaded,
    this.multiVolume,
  });

  /// Genres the user wants to see; empty = no genre filter.
  final Set<String> genres;

  /// Reading statuses the user wants to see; empty = no status filter.
  final Set<String> statuses;

  /// null = either, true = only downloaded series, false = only not-downloaded.
  final bool? downloaded;

  /// null = either, true = only multi-volume, false = only single-volume.
  final bool? multiVolume;

  bool get isEmpty =>
      genres.isEmpty &&
      statuses.isEmpty &&
      downloaded == null &&
      multiVolume == null;

  /// True when [series] satisfies every active filter clause.
  bool matches(Series series, {required bool isDownloaded}) {
    if (genres.isNotEmpty) {
      final seriesGenres = {for (final g in series.genres) g.trim()};
      if (!seriesGenres.any(genres.contains)) return false;
    }
    if (statuses.isNotEmpty &&
        !statuses.contains(series.readingStatus.trim().toLowerCase())) {
      return false;
    }
    if (downloaded != null && isDownloaded != downloaded) return false;
    if (multiVolume != null && series.hasMultipleVolumes != multiVolume) {
      return false;
    }
    return true;
  }

  LibraryFilters copyWith({
    Set<String>? genres,
    Set<String>? statuses,
    Object? downloaded = _unset,
    Object? multiVolume = _unset,
  }) {
    return LibraryFilters(
      genres: genres ?? this.genres,
      statuses: statuses ?? this.statuses,
      downloaded: identical(downloaded, _unset)
          ? this.downloaded
          : downloaded as bool?,
      multiVolume: identical(multiVolume, _unset)
          ? this.multiVolume
          : multiVolume as bool?,
    );
  }

  static const Object _unset = Object();
}

/// Bottom-sheet UI for picking [LibraryFilters]. Returns the new filter set
/// when the user taps Apply, null when they cancel.
class _LibraryFilterSheet extends StatefulWidget {
  const _LibraryFilterSheet({
    required this.initial,
    required this.allGenres,
    required this.allStatuses,
  });

  final LibraryFilters initial;
  final List<String> allGenres;
  final List<String> allStatuses;

  @override
  State<_LibraryFilterSheet> createState() => _LibraryFilterSheetState();
}

class _LibraryFilterSheetState extends State<_LibraryFilterSheet> {
  late LibraryFilters _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter library',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _draft.isEmpty
                      ? null
                      : () => setState(() => _draft = const LibraryFilters()),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.allGenres.isNotEmpty) ...[
              _sectionLabel(theme, 'Genre'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final genre in widget.allGenres)
                    FilterChip(
                      label: Text(genre),
                      selected: _draft.genres.contains(genre),
                      onSelected: (selected) {
                        final next = {..._draft.genres};
                        if (selected) {
                          next.add(genre);
                        } else {
                          next.remove(genre);
                        }
                        setState(() => _draft = _draft.copyWith(genres: next));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (widget.allStatuses.isNotEmpty) ...[
              _sectionLabel(theme, 'Reading status'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in widget.allStatuses)
                    FilterChip(
                      label: Text(_titleCase(status)),
                      selected: _draft.statuses.contains(status),
                      onSelected: (selected) {
                        final next = {..._draft.statuses};
                        if (selected) {
                          next.add(status);
                        } else {
                          next.remove(status);
                        }
                        setState(
                          () => _draft = _draft.copyWith(statuses: next),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _sectionLabel(theme, 'Downloaded'),
            _triStateRow(
              value: _draft.downloaded,
              labels: const ['Any', 'Downloaded', 'Not yet'],
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(downloaded: v)),
            ),
            const SizedBox(height: 16),
            _sectionLabel(theme, 'Volumes'),
            _triStateRow(
              value: _draft.multiVolume,
              labels: const ['Any', 'Multi-volume', 'Single volume'],
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(multiVolume: v)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// A three-state segmented control: any / true / false.
  Widget _triStateRow({
    required bool? value,
    required List<String> labels,
    required ValueChanged<bool?> onChanged,
  }) {
    assert(labels.length == 3);
    return SegmentedButton<int>(
      segments: [
        ButtonSegment(value: 0, label: Text(labels[0])),
        ButtonSegment(value: 1, label: Text(labels[1])),
        ButtonSegment(value: 2, label: Text(labels[2])),
      ],
      selected: {value == null ? 0 : (value ? 1 : 2)},
      onSelectionChanged: (selection) {
        final v = selection.first;
        onChanged(v == 0 ? null : v == 1);
      },
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
