import '../models/series.dart';

/// How the library grid is ordered.
enum LibrarySort {
  titleAsc('Title'),
  recentlyUpdated('Recently updated'),
  recentlyRead('Recently read'),
  author('Author'),
  readingStatus('Reading status');

  const LibrarySort(this.label);

  /// Human-readable label shown in the sort menu.
  final String label;

  /// What the two directions mean for this option. "A–Z / Z–A" is
  /// meaningless for a date, and "Oldest first" is meaningless for a title,
  /// so each option names its own.
  (String, String) get directionLabels => switch (this) {
    LibrarySort.titleAsc => ('A–Z', 'Z–A'),
    LibrarySort.author => ('A–Z', 'Z–A'),
    LibrarySort.recentlyUpdated => ('Newest first', 'Oldest first'),
    LibrarySort.recentlyRead => ('Most recent', 'Longest ago'),
    LibrarySort.readingStatus => ('Active first', 'Finished first'),
  };

  static LibrarySort fromName(String? name) {
    for (final s in LibrarySort.values) {
      if (s.name == name) return s;
    }
    return LibrarySort.titleAsc;
  }
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

  static ReadingStateFilter fromName(String? name) {
    for (final s in ReadingStateFilter.values) {
      if (s.name == name) return s;
    }
    return ReadingStateFilter.any;
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

  /// How many clauses are active — drives the badge on the filter button and
  /// the count in the empty state.
  int get activeCount =>
      (genres.isEmpty ? 0 : 1) +
      (statuses.isEmpty ? 0 : 1) +
      (downloaded == null ? 0 : 1) +
      (multiVolume == null ? 0 : 1);

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

  Map<String, dynamic> toJson() => {
    'genres': genres.toList()..sort(),
    'statuses': statuses.toList()..sort(),
    'downloaded': downloaded,
    'multiVolume': multiVolume,
  };

  static LibraryFilters fromJson(Map<String, dynamic> j) => LibraryFilters(
    genres: {
      for (final g in (j['genres'] as List? ?? const [])) g.toString(),
    },
    statuses: {
      for (final s in (j['statuses'] as List? ?? const [])) s.toString(),
    },
    downloaded: j['downloaded'] as bool?,
    multiVolume: j['multiVolume'] as bool?,
  );

  static const Object _unset = Object();
}

/// How the reader has arranged their library: the sort, its direction, the
/// reading-state chip and the filter set.
///
/// This is a durable preference, not a transient one — it is the shape the
/// library is kept in, the same way reader settings are the shape a page is
/// kept in, so it persists and syncs. The search query deliberately is not
/// part of it: a query is a question you ask once, and reopening the app to a
/// silently filtered library would be worse than retyping it.
class LibraryView {
  const LibraryView({
    this.sort = LibrarySort.titleAsc,
    this.descending = false,
    this.readingState = ReadingStateFilter.any,
    this.filters = const LibraryFilters(),
  });

  final LibrarySort sort;
  final bool descending;
  final ReadingStateFilter readingState;
  final LibraryFilters filters;

  static const initial = LibraryView();

  LibraryView copyWith({
    LibrarySort? sort,
    bool? descending,
    ReadingStateFilter? readingState,
    LibraryFilters? filters,
  }) => LibraryView(
    sort: sort ?? this.sort,
    descending: descending ?? this.descending,
    readingState: readingState ?? this.readingState,
    filters: filters ?? this.filters,
  );

  Map<String, dynamic> toJson() => {
    'sort': sort.name,
    'descending': descending,
    'readingState': readingState.name,
    'filters': filters.toJson(),
  };

  static LibraryView fromJson(Map<String, dynamic> j) => LibraryView(
    sort: LibrarySort.fromName(j['sort'] as String?),
    descending: j['descending'] == true,
    readingState: ReadingStateFilter.fromName(j['readingState'] as String?),
    filters: j['filters'] is Map<String, dynamic>
        ? LibraryFilters.fromJson(j['filters'] as Map<String, dynamic>)
        : const LibraryFilters(),
  );
}
