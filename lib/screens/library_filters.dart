import 'dart:async';

import 'package:flutter/material.dart';

import '../models/library_view.dart';
import '../models/series.dart';
import '../services/library_storage.dart';
import '../services/library_view_store.dart';
import '../services/reading_progress_store.dart';
import '../services/recent_searches_store.dart';
import '../services/series_search.dart';
import '../services/series_status_store.dart';
import '../widgets/action_sheet.dart';
import '../widgets/section_header.dart';
import 'library_cards.dart';

export '../models/library_view.dart';

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

  /// The persisted arrangement: sort, direction, chip and filter set. The
  /// search query is deliberately not part of it — see [LibraryView].
  LibraryView view = LibraryView.initial;

  final LibraryViewStore _viewStore = LibraryViewStore();
  final RecentSearchesStore _recentStore = RecentSearchesStore();

  /// Past searches, shown under an empty search box.
  List<String> recentSearches = const [];

  /// Debounces recording: a search is only worth remembering once the user
  /// has stopped typing it, or every prefix of it would be stored.
  Timer? _recordDebounce;

  LibrarySort get sort => view.sort;
  bool get sortDescending => view.descending;
  ReadingStateFilter get readingState => view.readingState;
  LibraryFilters get filters => view.filters;

  /// Loads the saved arrangement. Call from the screen's initState; the grid
  /// renders unsorted-by-preference for the one frame before this lands,
  /// which is invisible next to the library fetch it happens under.
  Future<void> loadSavedView() async {
    final saved = await _viewStore.load();
    final recent = await _recentStore.load();
    if (mounted) {
      setState(() {
        view = saved;
        recentSearches = recent;
      });
    }
  }

  /// Applies a change and persists it. Every mutation goes through here so
  /// there is no way to change the view without saving it.
  void _updateView(LibraryView next) {
    setState(() => view = next);
    _viewStore.save(next);
  }

  /// Re-reads the arrangement after a sync merged a newer one from another
  /// device, so the grid doesn't keep showing the superseded view.
  Future<void> reloadSavedView() => loadSavedView();

  void setSort(LibrarySort next) => _updateView(view.copyWith(sort: next));

  void setSortDescending(bool value) =>
      _updateView(view.copyWith(descending: value));

  void setReadingState(ReadingStateFilter next) =>
      _updateView(view.copyWith(readingState: next));

  /// Clears every filter clause and the reading-state chip, but leaves the
  /// sort alone — the arrangement isn't what made the grid empty.
  void clearAllFilters() => _updateView(
    view.copyWith(
      filters: const LibraryFilters(),
      readingState: ReadingStateFilter.any,
    ),
  );

  /// True when nothing is narrowing the grid — the empty state differs
  /// between "no books" and "no matches".
  bool get filtersAreClear =>
      filters.isEmpty &&
      searchQuery.trim().isEmpty &&
      readingState == ReadingStateFilter.any;

  void disposeFiltering() {
    _recordDebounce?.cancel();
    searchController.dispose();
  }

  /// Applies a query and, once typing settles, remembers it.
  void setSearchQuery(String value) {
    setState(() => searchQuery = value);
    _recordDebounce?.cancel();
    _recordDebounce = Timer(const Duration(milliseconds: 900), () async {
      final next = await _recentStore.record(value);
      if (mounted) setState(() => recentSearches = next);
    });
  }

  void applyRecentSearch(String query) {
    searchController.text = query;
    searchController.selection = TextSelection.collapsed(offset: query.length);
    setSearchQuery(query);
  }

  Future<void> forgetRecentSearch(String query) async {
    final next = await _recentStore.remove(query);
    if (mounted) setState(() => recentSearches = next);
  }

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

  /// True while a query is narrowing the grid — the point at which relevance
  /// order takes over from the chosen sort.
  bool get isSearching => searchTerms(searchQuery).isNotEmpty;

  /// The library after applying the active search, filter set, and sort.
  List<Series> get visibleLibrary {
    final all = librarySeries ?? const <Series>[];
    final terms = searchTerms(searchQuery);
    final downloads = downloadStore;
    final readState = _seriesReadingState;
    final filtered = <Series>[];
    for (final series in all) {
      if (terms.isNotEmpty && scoreSeries(series, terms) == null) continue;
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
    final compare = _comparatorFor(sort, readState.lastReadAt);
    filtered.sort(sortDescending ? (a, b) => compare(b, a) : compare);
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

  /// Every genre in the library with its series count, most-used first.
  List<GenreFacet> get _allGenres =>
      genreFacets(librarySeries ?? const <Series>[]);

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
    _updateView(view.copyWith(filters: next));
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

  String get _directionLabel =>
      sortDescending ? sort.directionLabels.$2 : sort.directionLabels.$1;

  /// The sort picker.
  ///
  /// A sheet rather than the popup this used to be — same reasons as
  /// everywhere else in the app — and with a direction row, which the popup
  /// had no room for. Each option names its own directions: "Oldest first"
  /// means something for a date and nothing for a title.
  Future<void> _openSortSheet() async {
    final choice = await showActionSheet<String>(
      context,
      title: 'Sort library',
      groups: [
        SheetGroup(
          actions: [
            for (final option in LibrarySort.values)
              SheetAction(
                value: 'sort:${option.name}',
                icon: option == sort ? Icons.check : Icons.sort,
                label: option.label,
                subtitle: option == sort ? 'Current order' : null,
              ),
          ],
        ),
        SheetGroup(
          title: 'Direction',
          actions: [
            SheetAction(
              value: 'dir:asc',
              icon: Icons.arrow_upward,
              label: sort.directionLabels.$1,
              subtitle: sortDescending ? null : 'Current direction',
            ),
            SheetAction(
              value: 'dir:desc',
              icon: Icons.arrow_downward,
              label: sort.directionLabels.$2,
              subtitle: sortDescending ? 'Current direction' : null,
            ),
          ],
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('dir:')) {
      setSortDescending(choice == 'dir:desc');
    } else {
      setSort(LibrarySort.fromName(choice.substring(5)));
    }
  }

  /// Why the grid came back empty, and the way out of it.
  ///
  /// This used to be one message that blamed the search — so narrowing with
  /// only a filter produced 'No series match ""' and offered "Clear search"
  /// as the fix, which did nothing. Name whichever thing is actually
  /// responsible, and clear all of them.
  Widget buildEmptyState() {
    if (filtersAreClear) {
      return const MessageView(
        icon: Icons.menu_book_outlined,
        title: 'Your library is empty',
        message: 'Series you add in Novel Grabber appear here.',
        actionLabel: '',
        onAction: _noop,
      );
    }
    final query = searchQuery.trim();
    final narrowedBy = <String>[
      if (query.isNotEmpty) '“$query”',
      if (readingState != ReadingStateFilter.any)
        'the ${readingState.label} chip',
      if (!filters.isEmpty)
        '${filters.activeCount} filter${filters.activeCount == 1 ? '' : 's'}',
    ];
    return MessageView(
      icon: Icons.filter_alt_off_outlined,
      title: 'Nothing matches',
      message: 'No series get past ${_join(narrowedBy)}.',
      actionLabel: 'Clear all',
      onAction: () {
        clearSearch();
        clearAllFilters();
      },
    );
  }

  static void _noop() {}

  /// "a, b and c" — so the message reads as a sentence rather than a list.
  static String _join(List<String> parts) {
    if (parts.length <= 1) return parts.join();
    return '${parts.sublist(0, parts.length - 1).join(', ')} '
        'and ${parts.last}';
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
                  hintText: 'Search title, author, genre…',
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
                  onChanged: setSearchQuery,
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
                  label: Text('${filters.activeCount}'),
                  child: const Icon(Icons.filter_list),
                ),
                tooltip: 'Filter library',
                onPressed: _openFilters,
              ),
              IconButton(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort',
                onPressed: _openSortSheet,
              ),
            ],
          ),
          if (searchQuery.trim().isEmpty && recentSearches.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.history,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  for (final query in recentSearches)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(query),
                        onPressed: () => applyRecentSearch(query),
                        onDeleted: () => forgetRecentSearch(query),
                        deleteIcon: const Icon(Icons.close, size: 15),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
                    onSelected: (_) => setReadingState(state),
                  ),
                  if (state != ReadingStateFilter.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSearching
                ? '$visible of $total series  ·  Best match'
                : visible == total
                ? '$total series  ·  ${sort.label} · $_directionLabel'
                : '$visible of $total series  ·  ${sort.label} · '
                      '$_directionLabel',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
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
  final List<GenreFacet> allGenres;
  final List<String> allStatuses;

  @override
  State<_LibraryFilterSheet> createState() => _LibraryFilterSheetState();
}

class _LibraryFilterSheetState extends State<_LibraryFilterSheet> {
  late LibraryFilters _draft;

  /// Narrows the genre list. A real library carries hundreds of genres, most
  /// of them on a single series, so scanning for one is hopeless without it.
  final TextEditingController _genreSearch = TextEditingController();
  String _genreQuery = '';

  /// Whether the long tail is expanded. Collapsed, the card shows the genres
  /// that describe most of the library; the rest are a tap away.
  bool _showAllGenres = false;

  /// How many genres to show before collapsing. Enough to cover the bulk of
  /// a typical library, short enough to read without scrolling far.
  static const _genreCollapsedCount = 24;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  void dispose() {
    _genreSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: SectionHeader(
                          'Filter library',
                          padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
                        ),
                      ),
                      TextButton(
                        onPressed: _draft.isEmpty
                            ? null
                            : () => setState(
                                () => _draft = const LibraryFilters(),
                              ),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (widget.allGenres.isNotEmpty)
                    _card(theme, 'Genre', _genrePicker(theme)),
                  if (widget.allStatuses.isNotEmpty)
                    _card(
                      theme,
                      'Reading status',
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
                                  () =>
                                      _draft = _draft.copyWith(statuses: next),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  _card(
                    theme,
                    'Downloaded',
                    _triStateRow(
                      value: _draft.downloaded,
                      labels: const ['Any', 'Downloaded', 'Not yet'],
                      onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(downloaded: v),
                      ),
                    ),
                  ),
                  _card(
                    theme,
                    'Volumes',
                    _triStateRow(
                      value: _draft.multiVolume,
                      labels: const ['Any', 'Multi', 'Single'],
                      onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(multiVolume: v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Pinned rather than scrolled away: with a long genre list, Apply
          // used to sit below the fold on a phone.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
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
          ),
        ],
      ),
    );
  }

  /// The genre picker.
  ///
  /// Every genre in the library used to be rendered as a chip, alphabetically
  /// — which at this library's 658 genres, two thirds of them carried by a
  /// single series, meant the handful of tags that actually describe the
  /// collection were lost among hundreds of one-offs. Three things fix that:
  /// frequency order, a count on each chip so you can see what a filter is
  /// worth before applying it, and a search box over the tail.
  Widget _genrePicker(ThemeData theme) {
    final matching = filterFacets(widget.allGenres, _genreQuery, _draft.genres);
    final searching = _genreQuery.trim().isNotEmpty;
    // Searching or expanded, show everything that matched; otherwise the
    // head of the list, plus any selected genres pinned ahead of it.
    final visible = (searching || _showAllGenres)
        ? matching
        : matching.take(_genreCollapsedCount).toList();
    final hidden = matching.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.allGenres.length > _genreCollapsedCount)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _genreSearch,
              onChanged: (v) => setState(() => _genreQuery = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Find a genre',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Clear',
                        onPressed: () {
                          _genreSearch.clear();
                          setState(() => _genreQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No genre matches “$_genreQuery”.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final facet in visible)
                FilterChip(
                  label: Text('${facet.name}  ${facet.count}'),
                  selected: _draft.genres.contains(facet.name),
                  onSelected: (selected) {
                    final next = {..._draft.genres};
                    if (selected) {
                      next.add(facet.name);
                    } else {
                      next.remove(facet.name);
                    }
                    setState(() => _draft = _draft.copyWith(genres: next));
                  },
                ),
            ],
          ),
        if (!searching && hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAllGenres = true),
              child: Text('Show all ${matching.length} genres'),
            ),
          )
        else if (!searching && _showAllGenres)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAllGenres = false),
              child: const Text('Show fewer'),
            ),
          ),
      ],
    );
  }

  /// One filter group as a rounded card, matching the action sheets.
  Widget _card(ThemeData theme, String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.tertiary,
                ),
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
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
