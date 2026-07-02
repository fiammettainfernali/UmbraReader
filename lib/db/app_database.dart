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

/// The app's SQLite database (via drift).
///
/// Stores migrate here from SharedPreferences one at a time (roadmap Phase 1
/// item 1); each store owns its one-time import from the legacy prefs keys,
/// and imports are non-destructive — the prefs copies stay behind untouched.
@DriftDatabase(tables: [ReadingProgressRows])
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
  int get schemaVersion => 1;
}
