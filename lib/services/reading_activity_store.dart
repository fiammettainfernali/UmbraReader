import 'dart:convert';

import 'dart:math';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/volume.dart';
import 'cloud_sync_service.dart';

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

  /// Seconds read today (local time).
  int todaySeconds({DateTime? now}) =>
      dailySeconds[_dateKey(_today(now))] ?? 0;

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
/// Cross-device: the local tables are THIS device's ledger; other devices'
/// ledgers arrive via iCloud sync and are cached in the kv table. [load]
/// sums every ledger, so totals — and streaks — span all devices without
/// double counting (each device only ever writes its own ledger).
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

  /// Stable id for this install, distinguishing its ledger in the sync map.
  static const _kDeviceId = 'sync_device_id';

  /// kv key caching other devices' ledgers (JSON map deviceId -> ledger).
  static const _kRemote = 'activity_remote_ledgers';

  static Future<void>? _migration;

  AppDatabase get _db => AppDatabase.instance;

  Future<ReadingActivity> load() async {
    final local = await _loadLocal();
    final daily = Map<String, int>.of(local.dailySeconds);
    final perVolume = Map<String, int>.of(local.perVolumeSeconds);
    // Fold in every other device's ledger.
    for (final ledger in (await _remoteLedgers()).values) {
      ledger.dailySeconds.forEach(
        (k, v) => daily[k] = (daily[k] ?? 0) + v,
      );
      ledger.perVolumeSeconds.forEach(
        (k, v) => perVolume[k] = (perVolume[k] ?? 0) + v,
      );
    }
    return ReadingActivity(dailySeconds: daily, perVolumeSeconds: perVolume);
  }

  /// This device's own ledger only.
  Future<ReadingActivity> _loadLocal() async {
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

  /// A stable random id naming this install's ledger in the sync map.
  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      final rng = Random.secure();
      id = List.generate(
        16,
        (_) => rng.nextInt(16).toRadixString(16),
      ).join();
      await prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  Future<Map<String, ReadingActivity>> _remoteLedgers() async {
    final raw = await _db.kvGet(_kRemote);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, ReadingActivity>{};
      for (final entry in decoded.entries) {
        final v = entry.value;
        if (entry.key is! String || v is! Map) continue;
        out[entry.key as String] = _ledgerFromJson(v);
      }
      return out;
    } on FormatException {
      return const {};
    }
  }

  ReadingActivity _ledgerFromJson(Map<dynamic, dynamic> json) {
    final daily = <String, int>{};
    final perVolume = <String, int>{};
    final d = json['daily'];
    if (d is Map) {
      d.forEach((k, v) {
        if (v is num) daily[k.toString()] = v.toInt();
      });
    }
    final p = json['perVolume'];
    if (p is Map) {
      p.forEach((k, v) {
        if (v is num) perVolume[k.toString()] = v.toInt();
      });
    }
    return ReadingActivity(dailySeconds: daily, perVolumeSeconds: perVolume);
  }

  Map<String, dynamic> _ledgerToJson(ReadingActivity a) => {
    'daily': a.dailySeconds,
    'perVolume': a.perVolumeSeconds,
  };

  // ── iCloud sync (see CloudSyncService) ──────────────────────────────────

  /// The full multi-device ledger map (every known device, this one's
  /// ledger fresh from its tables) as the sync blob.
  Future<String> exportSyncBlob() async {
    final id = await _deviceId();
    final map = <String, dynamic>{
      for (final entry in (await _remoteLedgers()).entries)
        entry.key: _ledgerToJson(entry.value),
      id: _ledgerToJson(await _loadLocal()),
    };
    return jsonEncode(map);
  }

  /// Caches every ledger in the cloud map EXCEPT this device's own (the
  /// local tables are always authoritative for it). Returns true when the
  /// remote cache changed.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    final id = await _deviceId();
    final remote = <String, dynamic>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.key == id) continue;
      if (entry.value is! Map) continue;
      remote[entry.key as String] = entry.value;
    }
    final encoded = jsonEncode(remote);
    final existing = await _db.kvGet(_kRemote);
    if (existing == encoded) return false;
    await _db.kvSet(_kRemote, encoded);
    return true;
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
    CloudSyncService().pushActivitySoon();
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
  /// Empty when there is no activity yet. Exports THIS device's ledger only
  /// — remote ledgers re-arrive via sync.
  Future<Map<String, Object>> exportBackupEntries() async {
    final activity = await _loadLocal();
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
