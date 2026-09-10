// Which comics you follow, where you got to, and whether they have grown.
//
// The shelf equivalent of ReadingProgressStore, for things that are read on
// their own site instead of being compiled into a book. It keeps three
// facts and no content: the chapter you were on, the panel you were on, and
// the highest chapter the series page was offering last time anyone looked.

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import 'web_series_metadata.dart';

/// A followed series, as a shelf needs it.
class WebSeries {
  const WebSeries({
    required this.url,
    required this.title,
    required this.addedAt,
    this.coverUrl,
    this.lastChapterUrl,
    this.lastPanel = 0,
    this.latestChapter,
    this.readChapter,
    this.checkedAt,
    this.openedAt,
  });

  final String url;
  final String title;
  final String? coverUrl;
  final String? lastChapterUrl;
  final int lastPanel;
  final double? latestChapter;
  final double? readChapter;
  final DateTime? checkedAt;
  final DateTime? openedAt;
  final DateTime addedAt;

  /// Where tapping the series should go: back to where you were, or to the
  /// series page if you have never opened it.
  String get openUrl => lastChapterUrl ?? url;

  bool get isStarted => readChapter != null || lastChapterUrl != null;

  /// Whether the site is offering something past the furthest chapter
  /// opened.
  bool get hasUnread {
    final latest = latestChapter;
    if (latest == null) return false;
    final read = readChapter;
    // Followed but never opened: anything at all is unread, which is the
    // honest answer and the one that makes a fresh follow look right.
    if (read == null) return true;
    return latest > read;
  }

  /// How many, when that can be said. Null before the series has been
  /// opened even once — the site's numbering is not a promise that every
  /// integer below it exists, so "260 new" on a fresh follow would be a
  /// guess dressed up as a count.
  int? get unreadCount {
    final latest = latestChapter;
    final read = readChapter;
    if (latest == null || read == null || latest <= read) return null;
    return (latest - read).floor().clamp(1, 9999);
  }
}

/// Reads and writes the followed-series table.
class WebSeriesStore {
  WebSeriesStore({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;

  /// Bumped whenever the followed set changes.
  ///
  /// Following happens in the browser and is shown in the library, and the
  /// two are separate tabs of an IndexedStack — both alive, neither
  /// rebuilt when the other is used. So a comic followed in one simply did
  /// not appear in the other until the app was restarted, which reads as
  /// the follow not having worked.
  ///
  /// A counter rather than a callback because more than one thing may want
  /// to know, and none of them should have to be wired to whoever did the
  /// writing.
  ///
  /// Only membership bumps this. Positions move every few seconds while a
  /// comic is being read, and nothing showing the shelf needs to hear about
  /// each one.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _changed() => revision.value++;

  /// Newest activity first: what you are actually reading rises, which is
  /// the order a shelf wants.
  Future<List<WebSeries>> all() async {
    final rows = await _db.select(_db.webSeriesRows).get();
    final out = rows.map(_toModel).toList();
    out.sort((a, b) {
      final at = a.openedAt ?? a.addedAt;
      final bt = b.openedAt ?? b.addedAt;
      return bt.compareTo(at);
    });
    return out;
  }

  Future<WebSeries?> find(String url) async {
    final row = await (_db.select(
      _db.webSeriesRows,
    )..where((t) => t.url.equals(url))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<bool> isFollowed(String url) async => (await find(url)) != null;

  /// Starts following [url], or refreshes what is known about it.
  ///
  /// Only ever fills gaps and moves the latest-chapter mark forward — a
  /// follow of a series already on the shelf must not throw away the place
  /// you had in it.
  Future<void> follow({
    required String url,
    required String title,
    String? coverUrl,
    WebSeriesInfo? info,
  }) async {
    final now = DateTime.now().toUtc();
    final existing = await find(url);
    final resolvedTitle = _firstNonEmpty([info?.title, title, url])!;
    await _db
        .into(_db.webSeriesRows)
        .insertOnConflictUpdate(
          WebSeriesRowsCompanion.insert(
            url: url,
            title: resolvedTitle,
            addedAt: (existing?.addedAt ?? now).toIso8601String(),
            coverUrl: Value(
              _firstNonEmpty([info?.coverUrl, coverUrl, existing?.coverUrl]),
            ),
            lastChapterUrl: Value(existing?.lastChapterUrl),
            lastPanel: Value(existing?.lastPanel ?? 0),
            latestChapter: Value(
              info?.latestChapterNumber ?? existing?.latestChapter,
            ),
            readChapter: Value(existing?.readChapter),
            checkedAt: Value(
              info == null
                  ? existing?.checkedAt?.toIso8601String()
                  : now.toIso8601String(),
            ),
            openedAt: Value(existing?.openedAt?.toIso8601String()),
          ),
        );
    if (existing == null) _changed();
  }

  Future<void> unfollow(String url) async {
    await (_db.delete(_db.webSeriesRows)..where((t) => t.url.equals(url))).go();
    _changed();
  }

  /// Records where reading stopped.
  ///
  /// [readChapter] only ever moves forward. Dipping back into chapter 3 of
  /// a series you have read 200 of should not make 197 of them unread
  /// again, which is exactly what storing "the chapter you were last on"
  /// would do.
  /// A null [panel] means "not known right now" and leaves the stored one
  /// alone — which is not the same as panel 0, and the difference is the
  /// reader's place. A page still loading its images, or one that will not
  /// run script, can only answer 0, and writing that would be recording the
  /// top of the page as where they stopped.
  Future<void> notePosition({
    required String seriesUrl,
    required String chapterUrl,
    int? panel,
  }) async {
    final existing = await find(seriesUrl);
    if (existing == null) return;
    final opened = WebSeriesMetadata.chapterNumber(chapterUrl);
    final furthest = [?existing.readChapter, ?opened];
    await (_db.update(
      _db.webSeriesRows,
    )..where((t) => t.url.equals(seriesUrl))).write(
      WebSeriesRowsCompanion(
        lastChapterUrl: Value(chapterUrl),
        lastPanel: panel == null
            ? const Value.absent()
            : Value(panel < 0 ? 0 : panel),
        readChapter: furthest.isEmpty
            ? const Value.absent()
            : Value(furthest.reduce((a, b) => a > b ? a : b)),
        openedAt: Value(DateTime.now().toUtc().toIso8601String()),
      ),
    );
  }

  /// Records what a check of the series page found.
  Future<void> noteCheck(String seriesUrl, WebSeriesInfo info) async {
    final existing = await find(seriesUrl);
    if (existing == null) return;
    await (_db.update(
      _db.webSeriesRows,
    )..where((t) => t.url.equals(seriesUrl))).write(
      WebSeriesRowsCompanion(
        title: info.title == null || info.title!.isEmpty
            ? const Value.absent()
            : Value(info.title!),
        coverUrl: info.coverUrl == null
            ? const Value.absent()
            : Value(info.coverUrl),
        // Never backwards: a page that renders its chapter list oddly on
        // one fetch should not un-announce chapters it already offered.
        latestChapter: _forward(
          existing.latestChapter,
          info.latestChapterNumber,
        ),
        checkedAt: Value(DateTime.now().toUtc().toIso8601String()),
      ),
    );
  }

  static Value<double?> _forward(double? current, double? found) {
    if (found == null) return const Value.absent();
    if (current != null && found <= current) return const Value.absent();
    return Value(found);
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }

  static WebSeries _toModel(WebSeriesRow row) => WebSeries(
    url: row.url,
    title: row.title,
    coverUrl: row.coverUrl,
    lastChapterUrl: row.lastChapterUrl,
    lastPanel: row.lastPanel,
    latestChapter: row.latestChapter,
    readChapter: row.readChapter,
    checkedAt: _parse(row.checkedAt),
    openedAt: _parse(row.openedAt),
    addedAt: _parse(row.addedAt) ?? DateTime.now().toUtc(),
  );

  static DateTime? _parse(String? iso) =>
      iso == null ? null : DateTime.tryParse(iso);
}
