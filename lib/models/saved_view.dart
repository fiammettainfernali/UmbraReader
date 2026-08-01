import 'library_view.dart';

/// A named arrangement of the library — a search, a filter set and a sort,
/// kept together so it can be returned to in one tap.
///
/// This is the answer to a library too big to browse: "unread Cultivation,
/// longest first" stops being something you rebuild every time you want it
/// and becomes somewhere you go. It is deliberately a *view*, not a folder —
/// nothing is filed into it, so a series that later matches appears in it
/// without being added, and one that stops matching leaves.
///
/// Unlike the live [LibraryView], a saved view *does* carry its query: here
/// the query was named and chosen deliberately, so restoring it is the point
/// rather than a surprise.
class SavedView {
  const SavedView({
    required this.id,
    required this.name,
    required this.query,
    required this.view,
    required this.createdAt,
  });

  /// Stable id, assigned at creation.
  final String id;

  final String name;

  /// The search text, if the view was saved with one.
  final String query;

  final LibraryView view;

  final DateTime createdAt;

  SavedView copyWith({String? name, String? query, LibraryView? view}) =>
      SavedView(
        id: id,
        name: name ?? this.name,
        query: query ?? this.query,
        view: view ?? this.view,
        createdAt: createdAt,
      );

  /// A one-line description of what the view actually narrows by, for the
  /// list — the name alone can drift from what was saved.
  String get summary {
    final parts = <String>[
      if (query.trim().isNotEmpty) '“${query.trim()}”',
      if (view.readingState != ReadingStateFilter.any) view.readingState.label,
      if (view.filters.genres.isNotEmpty)
        view.filters.genres.length == 1
            ? view.filters.genres.first
            : '${view.filters.genres.length} genres',
      if (view.filters.length != LengthBand.any) view.filters.length.label,
      if (view.filters.updated != UpdatedWithin.any) view.filters.updated.label,
      if (view.filters.downloaded == true) 'Downloaded',
      if (view.filters.downloaded == false) 'Not downloaded',
      if (view.filters.multiVolume == true) 'Multi-volume',
      if (view.filters.multiVolume == false) 'Single volume',
      if (view.filters.statuses.isNotEmpty)
        view.filters.statuses.length == 1
            ? _titleCase(view.filters.statuses.first)
            : '${view.filters.statuses.length} statuses',
    ];
    final sort =
        '${view.sort.label}, '
                '${view.descending ? view.sort.directionLabels.$2 : view.sort.directionLabels.$1}'
            .toLowerCase();
    if (parts.isEmpty) return 'Everything · $sort';
    return '${parts.join(' · ')} · $sort';
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'query': query,
    'view': view.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  static SavedView? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final name = j['name'] as String?;
    if (id == null || id.isEmpty || name == null) return null;
    return SavedView(
      id: id,
      name: name,
      query: j['query'] as String? ?? '',
      view: j['view'] is Map<String, dynamic>
          ? LibraryView.fromJson(j['view'] as Map<String, dynamic>)
          : LibraryView.initial,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
