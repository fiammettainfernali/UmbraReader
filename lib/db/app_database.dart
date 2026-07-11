import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

part 'app_database.g.dart';

/// One saved reading position per volume — the SQLite home of what
/// [ReadingProgressStore] used to keep as loose SharedPreferences keys.
///
/// [updatedAt] is an ISO-8601 string (not a drift dateTime column) so
/// last-writer-wins comparisons against iCloud sync blobs keep the exact
/// precision and semantics the SharedPreferences era had.
class ReadingProgressRows extends Table {
  /// `seriesOpdsId/fileName` — the same composite key the prefs store used.
  TextColumn get volumeKey => text()();

  IntColumn get chapterIndex => integer().withDefault(const Constant(0))();
  IntColumn get blockIndex => integer().withDefault(const Constant(0))();

  /// Character offset of the first visible line within the block — Kindle
  /// "location" / EPUB-CFI-style precision, so a stop mid-way through a
  /// huge webnovel paragraph restores to the exact line, not the
  /// paragraph top.
  IntColumn get blockChar => integer().withDefault(const Constant(0))();

  /// The chapter's spine href at save time. If a recompiled volume shifts
  /// chapter indexes, the reader re-finds the chapter by path.
  TextColumn get chapterPath => text().nullable()();

  IntColumn get chapterCount => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();
  BoolColumn get endReached => boolean().withDefault(const Constant(false))();

  /// JSON snapshot of the [Volume] so shelves can list books without the
  /// OPDS feed. Null for rows created by hide/resume before a real read.
  TextColumn get volumeJson => text().nullable()();

  /// Hidden from the "Continue reading" shelf (position still kept).
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  /// Read-aloud word-exact resume point, "blockIndex:charOffset". Device
  /// local and ephemeral — never synced.
  TextColumn get ttsResume => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {volumeKey};
}

/// One bookmark / highlight per row (was: one JSON list per volume in
/// SharedPreferences). Timestamps are ISO-8601 text, like everywhere else.
class BookmarkRows extends Table {
  /// `seriesOpdsId/fileName`, same composite key as reading progress.
  TextColumn get volumeKey => text()();

  TextColumn get bookmarkId => text()();
  IntColumn get chapterIndex => integer().withDefault(const Constant(0))();
  IntColumn get blockIndex => integer().withDefault(const Constant(0))();
  TextColumn get chapterTitle => text().withDefault(const Constant(''))();
  TextColumn get snippet => text().withDefault(const Constant(''))();
  TextColumn get createdAt => text().withDefault(const Constant(''))();
  BoolColumn get isHighlight => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get color => text().withDefault(const Constant('yellow'))();

  @override
  Set<Column<Object>> get primaryKey => {volumeKey, bookmarkId};
}

/// A user-defined library shelf. Membership stays a JSON int list — it's
/// small, ordered, and only ever read whole.
class CollectionRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get seriesIdsJson => text().withDefault(const Constant('[]'))();
  TextColumn get createdAt => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Reading seconds (and words read) per local calendar day (`YYYY-MM-DD`).
class DailyActivityRows extends Table {
  TextColumn get day => text()();
  IntColumn get seconds => integer().withDefault(const Constant(0))();

  /// New words read that day — forward progress only, so re-reading never
  /// inflates the tally. Drives reading-pace and TTS-cost estimates.
  IntColumn get words => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {day};
}

/// Reading seconds (and words read) per volume (`seriesOpdsId/fileName`).
class VolumeActivityRows extends Table {
  TextColumn get volumeKey => text()();
  IntColumn get seconds => integer().withDefault(const Constant(0))();

  /// High-water mark of words read in this volume — the ceiling that keeps
  /// re-reads from double-counting into the daily tally.
  IntColumn get words => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {volumeKey};
}

/// Recommendation outcomes per series: how often a rec card was shown and
/// whether it was ever tapped. Impressions-without-taps soften a candidate's
/// score, and (with taps) they become the training labels for the learned
/// per-user weights. Device-local — each device learns from what its user
/// actually saw on that screen.
class RecOutcomeRows extends Table {
  IntColumn get seriesId => integer()();
  IntColumn get impressions => integer().withDefault(const Constant(0))();
  IntColumn get taps => integer().withDefault(const Constant(0))();

  /// Local `YYYY-MM-DD` of the last counted impression — impressions count
  /// at most once per series per day so one busy session can't spam the
  /// counter.
  TextColumn get lastShownDay => text().withDefault(const Constant(''))();
  TextColumn get lastTapAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {seriesId};
}

/// Small scalars owned by database-backed stores (e.g. the collections
/// last-modified timestamp that drives whole-set sync).
class KvRows extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// The app's SQLite database (via drift).
///
/// Stores migrate here from SharedPreferences one at a time (roadmap Phase 1
/// item 1); each store owns its one-time import from the legacy prefs keys,
/// and imports are non-destructive — the prefs copies stay behind untouched.
@DriftDatabase(
  tables: [
    ReadingProgressRows,
    BookmarkRows,
    CollectionRows,
    DailyActivityRows,
    VolumeActivityRows,
    RecOutcomeRows,
    KvRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(driftDatabase(name: 'umbra'));

  /// Test constructor — pass `NativeDatabase.memory()`.
  @visibleForTesting
  AppDatabase.forTesting(super.e);

  static AppDatabase? _instance;

  /// The shared app database. Stores grab this lazily so nothing opens
  /// SQLite until the first read/write.
  static AppDatabase get instance => _instance ??= AppDatabase._();

  /// Lets tests swap in an in-memory database before stores touch [instance].
  @visibleForTesting
  static set instance(AppDatabase db) => _instance = db;

  /// Closes and forgets the shared instance (tests only), so each test can
  /// start from a fresh in-memory database without tripping drift's
  /// multiple-instances warning.
  @visibleForTesting
  static Future<void> reset() async {
    final db = _instance;
    _instance = null;
    await db?.close();
  }

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v1 shipped with reading progress only; v2 adds the rest of the
        // prefs → SQLite move (bookmarks, collections, activity, kv).
        await m.createTable(bookmarkRows);
        await m.createTable(collectionRows);
        await m.createTable(dailyActivityRows);
        await m.createTable(volumeActivityRows);
        await m.createTable(kvRows);
      }
      if (from < 3) {
        // v3: character-precision reading positions + spine-path anchors.
        await m.addColumn(readingProgressRows, readingProgressRows.blockChar);
        await m.addColumn(
          readingProgressRows,
          readingProgressRows.chapterPath,
        );
      }
      if (from < 4) {
        // v4: words-read ledger alongside reading seconds.
        await m.addColumn(dailyActivityRows, dailyActivityRows.words);
        await m.addColumn(volumeActivityRows, volumeActivityRows.words);
      }
      if (from < 5) {
        // v5: recommendation outcome tracking (impressions/taps).
        await m.createTable(recOutcomeRows);
      }
    },
  );

  /// Empties every store table. Used by backup restore: the restored
  /// legacy-format SharedPreferences become the source of truth again and
  /// each store re-imports from them on next use.
  Future<void> clearStoreData() async {
    await batch((b) {
      b.deleteAll(readingProgressRows);
      b.deleteAll(bookmarkRows);
      b.deleteAll(collectionRows);
      b.deleteAll(dailyActivityRows);
      b.deleteAll(volumeActivityRows);
      b.deleteAll(recOutcomeRows);
      b.deleteAll(kvRows);
    });
  }

  // ── tiny kv helpers for store-owned scalars ─────────────────────────────

  Future<String?> kvGet(String key) async =>
      (await (select(kvRows)..where((t) => t.key.equals(key)))
              .getSingleOrNull())
          ?.value;

  Future<void> kvSet(String key, String value) => into(kvRows).insertOnConflictUpdate(
    KvRowsCompanion(key: Value(key), value: Value(value)),
  );
}
