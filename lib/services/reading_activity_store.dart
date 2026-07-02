import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/volume.dart';

/// A snapshot of the user's reading-time activity: how many seconds were
/// spent reading on each calendar day, and the per-volume total.
class ReadingActivity {
  const ReadingActivity({
    required this.dailySeconds,
    required this.perVolumeSeconds,
  });

  /// Reading time per day. Keys are local-time `YYYY-MM-DD` strings.
  final Map<String, int> dailySeconds;

  /// Reading time per downloaded volume. Keys are `seriesOpdsId/fileName`.
  final Map<String, int> perVolumeSeconds;

  static const empty = ReadingActivity(
    dailySeconds: <String, int>{},
    perVolumeSeconds: <String, int>{},
  );

  /// Total seconds across every day on record.
  int get totalSeconds {
    var total = 0;
    for (final v in dailySeconds.values) {
      total += v;
    }
    return total;
  }

  /// Total seconds across the last seven days, inclusive of today.
  int weekSeconds({DateTime? now}) {
    final today = _today(now);
    var total = 0;
    for (var i = 0; i < 7; i++) {
      total += dailySeconds[_dateKey(today.subtract(Duration(days: i)))] ?? 0;
    }
    return total;
  }

  /// Consecutive days up to and including today with at least one second
  /// of reading. Zero when the user hasn't read today.
  int currentStreak({DateTime? now}) {
    final today = _today(now);
    var streak = 0;
    var cursor = today;
    while ((dailySeconds[_dateKey(cursor)] ?? 0) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// The longest run of consecutive days with any reading, across all
  /// history.
  int longestStreak() {
    final dates = <DateTime>[];
    for (final entry in dailySeconds.entries) {
      if (entry.value <= 0) continue;
      final d = DateTime.tryParse(entry.key);
      if (d != null) dates.add(DateTime(d.year, d.month, d.day));
    }
    if (dates.isEmpty) return 0;
    dates.sort();
    var longest = 1;
    var run = 1;
    for (var i = 1; i < dates.length; i++) {
      if (dates[i].difference(dates[i - 1]).inDays == 1) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 1;
      }
    }
    return longest;
  }
}

/// Persists reading-time activity across app launches, in SQLite
/// ([AppDatabase]) — one row per day plus one row per volume, so recording
/// a session is two upsert-increments instead of rewriting a whole blob.
///
/// Activity recorded before the SQLite move (one JSON blob under the
/// `reading_activity` SharedPreferences key) is imported once on first use;
/// the old key stays behind untouched. The blob shape is still the backup
/// format.
class ReadingActivityStore {
  /// Legacy SharedPreferences key — import and backup format.
  static const _key = 'reading_activity';

  /// Set once the legacy prefs data has been imported into SQLite.
  static const _kMigrated = 'reading_activity_in_sqlite_v1';

  static Future<void>? _migration;

  AppDatabase get _db => AppDatabase.instance;

  Future<ReadingActivity> load() async {
    await _ensureMigrated();
    final daily = <String, int>{
      for (final row in await _db.select(_db.dailyActivityRows).get())
        row.day: row.seconds,
    };
    final perVolume = <String, int>{
      for (final row in await _db.select(_db.volumeActivityRows).get())
        row.volumeKey: row.seconds,
    };
    return ReadingActivity(dailySeconds: daily, perVolumeSeconds: perVolume);
  }

  /// Adds [delta] seconds to today's tally and to the per-volume tally for
  /// [volume]. Sessions shorter than a second are ignored so app-switch
  /// noise can't poison the streak.
  Future<void> record(Volume volume, Duration delta, {DateTime? now}) async {
    final seconds = delta.inSeconds;
    if (seconds <= 0) return;
    await _ensureMigrated();
    final dateKey = _dateKey(_today(now));
    final volumeKey = '${volume.seriesOpdsId}/${volume.fileName}';
    await _db
        .into(_db.dailyActivityRows)
        .insert(
          DailyActivityRowsCompanion(
            day: Value(dateKey),
            seconds: Value(seconds),
          ),
          onConflict: DoUpdate(
            (old) => DailyActivityRowsCompanion.custom(
              seconds: old.seconds + Constant(seconds),
            ),
          ),
        );
    await _db
        .into(_db.volumeActivityRows)
        .insert(
          VolumeActivityRowsCompanion(
            volumeKey: Value(volumeKey),
            seconds: Value(seconds),
          ),
          onConflict: DoUpdate(
            (old) => VolumeActivityRowsCompanion.custom(
              seconds: old.seconds + Constant(seconds),
            ),
          ),
        );
  }

  // ── one-time import from SharedPreferences ──────────────────────────────

  Future<void> _ensureMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrated) ?? false) return;
    _migration ??= _importFromPrefs(prefs).whenComplete(() => _migration = null);
    await _migration;
  }

  Future<void> _importFromPrefs(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final dailyRaw = decoded['daily'];
          final volumeRaw = decoded['perVolume'];
          await _db.batch((b) {
            if (dailyRaw is Map) {
              b.insertAll(_db.dailyActivityRows, [
                for (final entry in dailyRaw.entries)
                  if (entry.value is num)
                    DailyActivityRowsCompanion(
                      day: Value(entry.key.toString()),
                      seconds: Value((entry.value as num).toInt()),
                    ),
              ], mode: InsertMode.insertOrIgnore);
            }
            if (volumeRaw is Map) {
              b.insertAll(_db.volumeActivityRows, [
                for (final entry in volumeRaw.entries)
                  if (entry.value is num)
                    VolumeActivityRowsCompanion(
                      volumeKey: Value(entry.key.toString()),
                      seconds: Value((entry.value as num).toInt()),
                    ),
              ], mode: InsertMode.insertOrIgnore);
            }
          });
        }
      } on FormatException {
        // corrupt legacy blob — nothing to import
      }
    }
    await prefs.setBool(_kMigrated, true);
  }

  /// Backup entry in the legacy prefs shape (one `reading_activity` blob).
  /// Empty when there is no activity yet.
  Future<Map<String, Object>> exportBackupEntries() async {
    final activity = await load();
    if (activity.dailySeconds.isEmpty && activity.perVolumeSeconds.isEmpty) {
      return const {};
    }
    return {
      _key: jsonEncode({
        'daily': activity.dailySeconds,
        'perVolume': activity.perVolumeSeconds,
      }),
    };
  }
}

DateTime _today(DateTime? now) {
  final t = (now ?? DateTime.now()).toLocal();
  return DateTime(t.year, t.month, t.day);
}

String _dateKey(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}
