import '../models/series.dart';

/// How the library grid is ordered.
enum LibrarySort {
  titleAsc('Title'),
  recentlyUpdated('Recently updated'),
  recentlyRead('Recently read'),
  author('Author'),
  readingStatus('Reading status'),
  length('Length'),
  progress('How far in'),
  timeSpent('Time spent');

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
    LibrarySort.length => ('Longest first', 'Shortest first'),
    LibrarySort.progress => ('Furthest in', 'Barely started'),
    LibrarySort.timeSpent => ('Most read', 'Least read'),
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

/// Length bands, in chapters.
///
/// The boundaries suit serialised webnovels rather than books: a "short"
/// series here is still a couple of hundred chapters, and the top band is
/// open-ended because the longest runs reach into the thousands.
enum LengthBand {
  any('Any length', 0, null),
  short('Under 300', 0, 300),
  medium('300 - 1000', 300, 1000),
  long('Over 1000', 1000, null);

  const LengthBand(this.label, this.min, this.max);

  final String label;
  final int min;
  final int? max;

  bool contains(int chapters) {
    if (this == LengthBand.any) return true;
    if (chapters < min) return false;
    return max == null || chapters < max!;
  }

  static LengthBand fromName(String? name) {
    for (final b in LengthBand.values) {
      if (b.name == name) return b;
    }
    return LengthBand.any;
  }
}

/// How recently a series gained anything.
enum UpdatedWithin {
  any('Any time', null),
  week('Past week', 7),
  month('Past month', 30),
  quarter('Past 3 months', 90),
  year('Past year', 365);

  const UpdatedWithin(this.label, this.days);

  final String label;
  final int? days;

  bool contains(DateTime? updatedAt, DateTime now) {
    if (days == null) return true;
    // An undated series cannot be shown to be recent, so it fails the
    // filter rather than slipping through it.
    if (updatedAt == null) return false;
    return now.difference(updatedAt).inDays <= days!;
  }

  static UpdatedWithin fromName(String? name) {
    for (final u in UpdatedWithin.values) {
      if (u.name == name) return u;
    }
    return UpdatedWithin.any;
  }
}

/// The active set of library filters, applied alongside search + sort.
class LibraryFilters {
  const LibraryFilters({
    this.genres = const {},
    this.matchAllGenres = false,
    this.statuses = const {},
    this.downloaded,
    this.multiVolume,
    this.length = LengthBand.any,
    this.updated = UpdatedWithin.any,
    this.collectionId,
  });

  /// Genres the user wants to see; empty = no genre filter.
  final Set<String> genres;

  /// When true a series must carry *every* selected genre rather than any
  /// one of them. Off by default: any-match is what this filter has always
  /// meant, and flipping it silently would rewrite saved views.
  final bool matchAllGenres;

  /// Reading statuses the user wants to see; empty = no status filter.
  final Set<String> statuses;

  /// null = either, true = only downloaded series, false = only not-downloaded.
  final bool? downloaded;

  /// null = either, true = only multi-volume, false = only single-volume.
  final bool? multiVolume;

  /// Chapter-count band.
  final LengthBand length;

  /// How recently the series was updated.
  final UpdatedWithin updated;

  /// Restrict to one collection, by its id; null = the whole library.
  final String? collectionId;

  bool get isEmpty =>
      genres.isEmpty &&
      statuses.isEmpty &&
      downloaded == null &&
      multiVolume == null &&
      length == LengthBand.any &&
      updated == UpdatedWithin.any &&
      collectionId == null;

  /// How many clauses are active — drives the badge on the filter button and
  /// the count in the empty state.
  int get activeCount =>
      (genres.isEmpty ? 0 : 1) +
      (statuses.isEmpty ? 0 : 1) +
      (downloaded == null ? 0 : 1) +
      (multiVolume == null ? 0 : 1) +
      (length == LengthBand.any ? 0 : 1) +
      (updated == UpdatedWithin.any ? 0 : 1) +
      (collectionId == null ? 0 : 1);

  /// True when [series] satisfies every active filter clause.
  ///
  /// [collectionSeriesIds] is the membership of [collectionId]; pass null
  /// when no collection filter is active or the collection is unknown.
  bool matches(
    Series series, {
    required bool isDownloaded,
    DateTime? now,
    Set<int>? collectionSeriesIds,
  }) {
    if (genres.isNotEmpty) {
      final seriesGenres = {for (final g in series.genres) g.trim()};
      final ok = matchAllGenres
          ? genres.every(seriesGenres.contains)
          : seriesGenres.any(genres.contains);
      if (!ok) return false;
    }
    if (!length.contains(series.totalChapters)) return false;
    if (!updated.contains(series.updatedAt, now ?? DateTime.now())) {
      return false;
    }
    if (collectionId != null &&
        !(collectionSeriesIds ?? const <int>{}).contains(series.opdsId)) {
      return false;
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
    bool? matchAllGenres,
    Set<String>? statuses,
    Object? downloaded = _unset,
    Object? multiVolume = _unset,
    LengthBand? length,
    UpdatedWithin? updated,
    Object? collectionId = _unset,
  }) {
    return LibraryFilters(
      genres: genres ?? this.genres,
      matchAllGenres: matchAllGenres ?? this.matchAllGenres,
      length: length ?? this.length,
      updated: updated ?? this.updated,
      collectionId: identical(collectionId, _unset)
          ? this.collectionId
          : collectionId as String?,
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
    'matchAllGenres': matchAllGenres,
    'statuses': statuses.toList()..sort(),
    'downloaded': downloaded,
    'multiVolume': multiVolume,
    'length': length.name,
    'updated': updated.name,
    'collectionId': collectionId,
  };

  static LibraryFilters fromJson(Map<String, dynamic> j) => LibraryFilters(
    genres: {for (final g in (j['genres'] as List? ?? const [])) g.toString()},
    statuses: {
      for (final s in (j['statuses'] as List? ?? const [])) s.toString(),
    },
    downloaded: j['downloaded'] as bool?,
    multiVolume: j['multiVolume'] as bool?,
    matchAllGenres: j['matchAllGenres'] == true,
    length: LengthBand.fromName(j['length'] as String?),
    updated: UpdatedWithin.fromName(j['updated'] as String?),
    collectionId: j['collectionId'] as String?,
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

  /// Selects the *second* of [LibrarySort.directionLabels] rather than
  /// meaning "descending" literally.
  ///
  /// Several sorts already run descending in their natural direction —
  /// Length, How far in and Time spent all lead with the big end, because
  /// that is the interesting one — so for those, false means longest-first
  /// and true means shortest-first. The labels are the source of truth for
  /// what the reader sees; this flag only picks which of the pair applies.
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
