import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/opds_client.dart';
import '../services/recommendation_loader.dart';
import '../services/settings_service.dart';
import '../widgets/section_header.dart';
import 'browse_screen.dart';
import 'library_cards.dart';
import 'library_recommendations.dart';
import 'library_search_screen.dart';
import 'novel_search_screen.dart';
import 'series_detail_screen.dart';

/// Finding something to read — from the library or from the sources.
///
/// This tab used to open the server controls, which is a different job
/// entirely: one is "what should I read", the other is "what is the
/// machine doing". The shelves were on the library screen, above the grid,
/// where they pushed the actual collection below the fold and only
/// appeared when nothing was filtered.
///
/// Continue reading deliberately stays on the library: resuming a book is
/// the most frequent thing anyone does here, and it belongs where the app
/// opens.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.settings});

  final OpdsSettings settings;

  @override
  State<DiscoverScreen> createState() => DiscoverScreenState();
}

class DiscoverScreenState extends State<DiscoverScreen>
    with LibraryRecommendations<DiscoverScreen> {
  List<Series> _library = const [];

  /// Download records, so the recently-updated shelf can mark the series
  /// whose new chapters aren't on the device yet — which is the whole
  /// reason to look at that shelf.
  DownloadStore? _downloads;

  bool _loading = true;

  /// What the library looked like the last time recommendations were fitted,
  /// so a reload that changes nothing doesn't refit or reshuffle them.
  String _librarySignature = '';

  @override
  void initState() {
    super.initState();
    _load();
    // This tab is kept alive by the shell's IndexedStack, so initState runs
    // once for the life of the app. Syncing happens on the library screen;
    // without this listener the shelves showed the library as it was at
    // launch, forever.
    libraryCacheRevision.addListener(_onCacheChanged);
  }

  @override
  void dispose() {
    libraryCacheRevision.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    if (mounted) _load();
  }

  // ── LibraryRecommendations proxies ──────────────────────────────────────
  @override
  OpdsSettings? get opdsSettings => widget.settings;

  @override
  Future<void> reloadReading() => _load();

  @override
  Future<void> openSeries(Series series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SeriesDetailScreen(series: series, settings: widget.settings),
      ),
    );
    if (mounted) await _load();
  }

  /// Reads the cached library, then works out what to suggest.
  ///
  /// The cache rather than the network: this tab is about the collection
  /// that is already known, and the library screen owns fetching. Sharing
  /// the cache means both see the same books without either waiting on the
  /// other.
  Future<void> _load({bool force = false}) async {
    final cache = LibraryCache(LibraryStorage());
    final downloads = DownloadStore(LibraryStorage());
    await (cache.load(), downloads.load()).wait;
    final library = cache.series;
    if (!mounted) return;
    setState(() {
      _library = library;
      _downloads = downloads;
      _loading = false;
    });

    // The shelves above are a cheap re-read and always refresh. The
    // recommendations are not: they read seven stores and refit the ranking
    // weights, and the shelf shuffles its pool — so recomputing them when
    // the library hasn't changed would both cost real work and make the tab
    // appear to reorder itself while being looked at.
    final signature = _signatureOf(library);
    if (!force && signature == _librarySignature) return;
    _librarySignature = signature;

    final recs = await const RecommendationLoader().load(library);
    if (!mounted) return;
    setRecommendations(recs);
  }

  /// Cheap stand-in for "the library changed in a way the shelves care
  /// about" — size, plus the newest date of each kind.
  static String _signatureOf(List<Series> library) {
    DateTime? updated;
    DateTime? added;
    for (final s in library) {
      final u = s.updatedAt;
      if (u != null && (updated == null || u.isAfter(updated))) updated = u;
      final a = s.addedAt;
      if (a != null && (added == null || a.isAfter(added))) added = a;
    }
    return '${library.length}|${updated?.toIso8601String()}'
        '|${added?.toIso8601String()}';
  }

  /// True when the server has content newer than anything downloaded.
  /// Nothing downloaded is not an update — it is simply not downloaded.
  bool _hasUpdate(Series series) {
    final downloads = _downloads;
    final updated = series.updatedAt;
    if (downloads == null || updated == null) return false;
    DateTime? newest;
    for (final record in downloads.recordsForSeries(series.opdsId)) {
      final t = record.volumeUpdatedAt;
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    if (newest == null) return false;
    return updated.isAfter(newest);
  }

  Future<void> _openSearchInBooks() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LibrarySearchScreen()),
    );
  }

  Future<void> _openFindNovels() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NovelSearchScreen(settings: widget.settings, sites: const []),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openBrowser() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowseScreen(settings: widget.settings),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openRandom() async {
    if (_library.isEmpty) return;
    final pick = (_library.toList()..shuffle()).first;
    await openSeries(pick);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = recentlyUpdated(_library);
    final added = recentlyAdded(_library);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.casino_outlined),
            tooltip: 'Open something at random',
            onPressed: _library.isEmpty ? null : _openRandom,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              // A deliberate pull means "redo it", including the parts the
              // signature check would otherwise skip.
              onRefresh: () => _load(force: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  0,
                  8,
                  0,
                  24 + MediaQuery.of(context).padding.bottom,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: _searchCard(theme),
                  ),
                  if (recent.isNotEmpty) ...[
                    const SectionHeader(
                      'Recently updated',
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    ),
                    _shelf(recent),
                  ],
                  // Below "updated" because new chapters in something you're
                  // already reading beat a book you haven't started — but
                  // above the recommendations, since these are books you
                  // chose yourself.
                  if (added.isNotEmpty) ...[
                    const SectionHeader(
                      'Recently added',
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    ),
                    _shelf(added),
                  ],
                  if (recommendations.isNotEmpty) buildRecommendedShelf(),
                  if (recent.isEmpty &&
                      added.isEmpty &&
                      recommendations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.travel_explore,
                            size: 56,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _library.isEmpty
                                ? 'Nothing to suggest yet'
                                : 'Read a little first',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _library.isEmpty
                                ? 'Add some novels and they will show up here.'
                                : 'Suggestions get better as you read — start '
                                      'a book and come back.',
                            textAlign: TextAlign.center,
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
    );
  }

  /// The three ways of looking for something, as one card.
  ///
  /// Grouped rather than scattered because they answer versions of the same
  /// question: two search the library, one goes out to the sources.
  Widget _searchCard(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _searchRow(
              theme,
              icon: Icons.manage_search,
              label: 'Search inside your books',
              subtitle: 'Find a passage across everything downloaded',
              onTap: _openSearchInBooks,
            ),
            _hairline(theme),
            _searchRow(
              theme,
              icon: Icons.travel_explore,
              label: 'Find new novels',
              subtitle: 'Search the source sites by title',
              onTap: _openFindNovels,
            ),
            _hairline(theme),
            _searchRow(
              theme,
              icon: Icons.language,
              label: 'Browse the sites',
              subtitle: 'Look around and send anything to Novel Grabber',
              onTap: _openBrowser,
            ),
          ],
        ),
      ),
    );
  }

  Widget _hairline(ThemeData theme) => Divider(
    height: 1,
    thickness: 1,
    indent: 68,
    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
  );

  Widget _searchRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 20, color: theme.colorScheme.tertiary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.outline.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  /// A horizontal run of covers.
  Widget _shelf(List<Series> series) {
    return SizedBox(
      height: 218,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: series.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: 110,
          child: SeriesCard(
            series: series[i],
            imageHeaders: OpdsClient(widget.settings).authHeaders,
            updateAvailable: _hasUpdate(series[i]),
            onTap: () => openSeries(series[i]),
            // No bulk actions on this tab, so a long press does the same
            // as a tap rather than being a gesture that goes nowhere.
            onLongPress: () => openSeries(series[i]),
          ),
        ),
      ),
    );
  }
}
