import 'dart:convert';

import 'dart:math';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/volume.dart';
import 'cloud_sync_service.dart';

/// The window the stats screen is reporting on.
///
/// Sized in days rather than calendar months/years deliberately: a rolling
/// window compares cleanly against the one before it ("this week vs last
/// week"), whereas calendar periods would compare a part-finished month
/// against a whole one and look like a collapse every time a month turned.
enum StatsPeriod {
  week('Week', 7),
  month('Month', 30),
  year('Year', 365),
  all('All', 0);

  const StatsPeriod(this.label, this.days);

  final String label;

  /// Length of the window; 0 means all recorded history.
  final int days;

  bool get isAllTime => this == StatsPeriod.all;
}

/// A snapshot of the user's reading-time activity: how many seconds were
/// spent reading on each calendar day, and the per-volume total.
class ReadingActivity {
  const ReadingActivity({
    required this.dailySeconds,
    required this.perVolumeSeconds,
    this.dailyWords = const <String, int>{},
    this.perVolumeWords = const <String, int>{},
  });

  /// Reading time per day. Keys are local-time `YYYY-MM-DD` strings.
  final Map<String, int> dailySeconds;

  /// Reading time per downloaded volume. Keys are `seriesOpdsId/fileName`.
  final Map<String, int> perVolumeSeconds;

  /// New words read per day (forward progress only). Same keys as
  /// [dailySeconds]; drives reading pace and TTS-cost estimates.
  final Map<String, int> dailyWords;

  /// Words read per volume — the high-water mark used to keep re-reads from
  /// double-counting. Same keys as [perVolumeSeconds].
  final Map<String, int> perVolumeWords;

  static const empty = ReadingActivity(
    dailySeconds: <String, int>{},
    perVolumeSeconds: <String, int>{},
    dailyWords: <String, int>{},
    perVolumeWords: <String, int>{},
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
  int todaySeconds({DateTime? now}) => dailySeconds[_dateKey(_today(now))] ?? 0;

  /// Total words read across every day on record.
  int get totalWords {
    var total = 0;
    for (final v in dailyWords.values) {
      total += v;
    }
    return total;
  }

  /// Words read today (local time).
  int todayWords({DateTime? now}) => dailyWords[_dateKey(_today(now))] ?? 0;

  /// Words read across the last seven days, inclusive of today.
  int weekWords({DateTime? now}) {
    final today = _today(now);
    var total = 0;
    for (var i = 0; i < 7; i++) {
      total += dailyWords[_dateKey(today.subtract(Duration(days: i)))] ?? 0;
    }
    return total;
  }

  /// Average reading pace in words per minute across all recorded time, or 0
  /// when there is not yet any measured time.
  int get wordsPerMinute {
    final minutes = totalSeconds / 60.0;
    if (minutes <= 0) return 0;
    return (totalWords / minutes).round();
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

  // ── period windows ──────────────────────────────────────────────────────
  //
  // The daily ledger has always held enough to answer "how did last month go";
  // only today and this week had accessors, so the stats screen fell back to
  // all-time everywhere else. These read the same maps over an arbitrary
  // window, which is what lets the screen offer Week / Month / Year / All.

  /// Seconds read across the [days] ending today, inclusive.
  int secondsInLast(int days, {DateTime? now}) =>
      _sumLast(dailySeconds, days, now);

  /// Words read across the [days] ending today, inclusive.
  int wordsInLast(int days, {DateTime? now}) => _sumLast(dailyWords, days, now);

  /// Seconds read across the [days] ending [days] ago — the window
  /// immediately before [secondsInLast], for period-on-period comparison.
  int secondsInPrevious(int days, {DateTime? now}) =>
      _sumLast(dailySeconds, days, now, skip: days);

  /// Days with any reading in the [days] ending today. Distinct from the
  /// streak: this counts total days, not consecutive ones.
  int daysReadInLast(int days, {DateTime? now}) {
    final today = _today(now);
    var count = 0;
    for (var i = 0; i < days; i++) {
      final v = dailySeconds[_dateKey(today.subtract(Duration(days: i)))] ?? 0;
      if (v > 0) count++;
    }
    return count;
  }

  /// Per-day seconds over the [days] ending today, oldest first — the series
  /// a trend bar chart draws.
  List<int> dailySeriesLast(int days, {DateTime? now}) {
    final today = _today(now);
    return [
      for (var i = days - 1; i >= 0; i--)
        dailySeconds[_dateKey(today.subtract(Duration(days: i)))] ?? 0,
    ];
  }

  /// Seconds read in [period] — all-time when the period is [StatsPeriod.all].
  int secondsIn(StatsPeriod period, {DateTime? now}) =>
      period.isAllTime ? totalSeconds : secondsInLast(period.days, now: now);

  /// Words read in [period].
  int wordsIn(StatsPeriod period, {DateTime? now}) =>
      period.isAllTime ? totalWords : wordsInLast(period.days, now: now);

  /// Days with any reading in [period].
  int daysReadIn(StatsPeriod period, {DateTime? now}) => period.isAllTime
      ? dailySeconds.values.where((v) => v > 0).length
      : daysReadInLast(period.days, now: now);

  /// Reading pace in [period], or 0 without measured time. The lifetime figure
  /// ([wordsPerMinute]) still drives the reader's time-left estimate, which
  /// wants stability over recency.
  int wordsPerMinuteIn(StatsPeriod period, {DateTime? now}) {
    final minutes = secondsIn(period, now: now) / 60.0;
    if (minutes <= 0) return 0;
    return (wordsIn(period, now: now) / minutes).round();
  }

  /// Change in reading time against the window immediately before [period],
  /// as a fraction (0.38 = up 38%). Null when there is no prior window to
  /// compare against, or it was empty — a first week has no "last week", and
  /// dividing by zero would read as an infinite improvement.
  double? trendAgainstPrevious(StatsPeriod period, {DateTime? now}) {
    if (period.isAllTime) return null;
    final prev = secondsInPrevious(period.days, now: now);
    if (prev <= 0) return null;
    final current = secondsInLast(period.days, now: now);
    return (current - prev) / prev;
  }

  /// The heaviest single day in [period], or null when nothing was read.
  ({DateTime day, int seconds})? bestDayIn(
    StatsPeriod period, {
    DateTime? now,
  }) {
    final today = _today(now);
    ({DateTime day, int seconds})? best;
    void consider(DateTime day, int seconds) {
      if (seconds <= 0) return;
      if (best == null || seconds > best!.seconds) {
        best = (day: day, seconds: seconds);
      }
    }

    if (period.isAllTime) {
      dailySeconds.forEach((key, value) {
        final day = DateTime.tryParse(key);
        if (day != null) consider(day, value);
      });
    } else {
      for (var i = 0; i < period.days; i++) {
        final day = today.subtract(Duration(days: i));
        consider(day, dailySeconds[_dateKey(day)] ?? 0);
      }
    }
    return best;
  }

  /// The heaviest rolling seven days ending inside [period], or null when
  /// nothing was read. Rolling rather than calendar weeks, to match how the
  /// periods themselves are measured.
  int bestWeekIn(StatsPeriod period, {DateTime? now}) {
    final today = _today(now);
    // Across all time, walk back to the oldest recorded day.
    var span = period.days;
    if (period.isAllTime) {
      var oldest = 0;
      dailySeconds.forEach((key, _) {
        final day = DateTime.tryParse(key);
        if (day == null) return;
        final age = today.difference(day).inDays;
        if (age > oldest) oldest = age;
      });
      span = oldest + 1;
    }
    var best = 0;
    for (var offset = 0; offset < span; offset++) {
      var total = 0;
      for (var i = 0; i < 7; i++) {
        total +=
            dailySeconds[_dateKey(
              today.subtract(Duration(days: offset + i)),
            )] ??
            0;
      }
      if (total > best) best = total;
    }
    return best;
  }

  /// Buckets for the trend chart, oldest first: one per day for week and
  /// month, one per calendar month for year. Empty for all-time, where the
  /// heatmap is the better tool.
  ///
  /// Month buckets are unlabelled — thirty labels are unreadable at this size
  /// and the shape is the point.
  List<({String label, int seconds})> trendBuckets(
    StatsPeriod period, {
    DateTime? now,
  }) {
    const weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const monthInitials = [
      'J',
      'F',
      'M',
      'A',
      'M',
      'J',
      'J',
      'A',
      'S',
      'O',
      'N',
      'D',
    ];
    final today = _today(now);
    switch (period) {
      case StatsPeriod.all:
        return const [];
      case StatsPeriod.week:
      case StatsPeriod.month:
        final days = period.days;
        return [
          for (var i = days - 1; i >= 0; i--)
            (
              label: period == StatsPeriod.week
                  ? weekdayInitials[today.subtract(Duration(days: i)).weekday -
                        1]
                  : '',
              seconds:
                  dailySeconds[_dateKey(today.subtract(Duration(days: i)))] ??
                  0,
            ),
        ];
      case StatsPeriod.year:
        // Twelve calendar months ending with the current one.
        final out = <({String label, int seconds})>[];
        for (var back = 11; back >= 0; back--) {
          final month = DateTime(today.year, today.month - back);
          var total = 0;
          dailySeconds.forEach((key, value) {
            final parts = key.split('-');
            if (parts.length < 2) return;
            if (int.tryParse(parts[0]) == month.year &&
                int.tryParse(parts[1]) == month.month) {
              total += value;
            }
          });
          out.add((label: monthInitials[month.month - 1], seconds: total));
        }
        return out;
    }
  }

  int _sumLast(Map<String, int> src, int days, DateTime? now, {int skip = 0}) {
    final today = _today(now);
    var total = 0;
    for (var i = skip; i < skip + days; i++) {
      total += src[_dateKey(today.subtract(Duration(days: i)))] ?? 0;
    }
    return total;
  }

  /// Consecutive reading days ending today — with grace:
  ///
  ///  - Today without reading yet does NOT break the streak (the day isn't
  ///    over); the count then ends at yesterday.
  ///  - One missed day per rolling 7 is forgiven (a "rest day"), so a
  ///    single off-day doesn't zero weeks of momentum. Two gaps within a
  ///    week ends the streak. [streakUsedGrace] reports honestly when the
  ///    current streak leans on a rest day.
  int currentStreak({DateTime? now}) => _streak(now).$1;

  /// True when the current streak leans on a rest day forgiven within the
  /// last 7 days. Clears once a week of clean reading rolls the rest day out
  /// of the window (it does not stay lit for the whole streak's life).
  bool streakUsedGrace({DateTime? now}) => _streak(now).$2;

  (int, bool) _streak(DateTime? now) {
    final today = _today(now);
    var cursor = (dailySeconds[_dateKey(today)] ?? 0) > 0
        ? today
        : today.subtract(const Duration(days: 1));
    var streak = 0;
    var usedGrace = false;
    var daysSinceGrace = 8; // no forgiveness spent yet
    while (true) {
      final read = (dailySeconds[_dateKey(cursor)] ?? 0) > 0;
      if (read) {
        streak++;
      } else {
        // A gap: forgivable only if reading continues on the far side and
        // no other rest day was spent in the trailing week.
        final dayBefore = cursor.subtract(const Duration(days: 1));
        final continues = (dailySeconds[_dateKey(dayBefore)] ?? 0) > 0;
        if (streak > 0 && continues && daysSinceGrace >= 7) {
          // The forgiveness is spent (so a second gap this week still breaks),
          // but only surface "(rest day used)" while the rest day is still in
          // the trailing 7-day window. Older forgiven gaps keep extending the
          // streak silently — otherwise the label sticks on forever once any
          // rest day is baked into a long streak.
          if (today.difference(cursor).inDays < 7) {
            usedGrace = true;
          }
          daysSinceGrace = 0;
        } else {
          break;
        }
      }
      daysSinceGrace++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return (streak, usedGrace);
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
    final dailyWords = Map<String, int>.of(local.dailyWords);
    final perVolumeWords = Map<String, int>.of(local.perVolumeWords);
    // Fold in every other device's ledger.
    for (final ledger in (await _remoteLedgers()).values) {
      ledger.dailySeconds.forEach((k, v) => daily[k] = (daily[k] ?? 0) + v);
      ledger.perVolumeSeconds.forEach(
        (k, v) => perVolume[k] = (perVolume[k] ?? 0) + v,
      );
      ledger.dailyWords.forEach(
        (k, v) => dailyWords[k] = (dailyWords[k] ?? 0) + v,
      );
      ledger.perVolumeWords.forEach(
        (k, v) => perVolumeWords[k] = (perVolumeWords[k] ?? 0) + v,
      );
    }
    return ReadingActivity(
      dailySeconds: daily,
      perVolumeSeconds: perVolume,
      dailyWords: dailyWords,
      perVolumeWords: perVolumeWords,
    );
  }

  /// This device's own ledger only.
  Future<ReadingActivity> _loadLocal() async {
    await _ensureMigrated();
    final daily = <String, int>{};
    final dailyWords = <String, int>{};
    for (final row in await _db.select(_db.dailyActivityRows).get()) {
      daily[row.day] = row.seconds;
      dailyWords[row.day] = row.words;
    }
    final perVolume = <String, int>{};
    final perVolumeWords = <String, int>{};
    for (final row in await _db.select(_db.volumeActivityRows).get()) {
      perVolume[row.volumeKey] = row.seconds;
      perVolumeWords[row.volumeKey] = row.words;
    }
    return ReadingActivity(
      dailySeconds: daily,
      perVolumeSeconds: perVolume,
      dailyWords: dailyWords,
      perVolumeWords: perVolumeWords,
    );
  }

  /// A stable random id naming this install's ledger in the sync map.
  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      final rng = Random.secure();
      id = List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
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
    Map<String, int> parseMap(Object? raw) {
      final out = <String, int>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is num) out[k.toString()] = v.toInt();
        });
      }
      return out;
    }

    return ReadingActivity(
      dailySeconds: parseMap(json['daily']),
      perVolumeSeconds: parseMap(json['perVolume']),
      dailyWords: parseMap(json['dailyWords']),
      perVolumeWords: parseMap(json['perVolumeWords']),
    );
  }

  Map<String, dynamic> _ledgerToJson(ReadingActivity a) => {
    'daily': a.dailySeconds,
    'perVolume': a.perVolumeSeconds,
    'dailyWords': a.dailyWords,
    'perVolumeWords': a.perVolumeWords,
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

  /// Folds every ledger in the cloud map EXCEPT this device's own into the
  /// cache (the local tables are always authoritative for this device).
  /// Returns true when the cache changed.
  ///
  /// Folds rather than replaces, which is the difference between a streak
  /// crossing devices and not. A blob is only ever as complete as the device
  /// that wrote it: whenever the other device pushes before it has seen this
  /// one — a push triggered by some unrelated store, or a read of the
  /// activity key that came back empty because iCloud hadn't materialised
  /// the file yet — the cloud copy is missing a device outright. Replacing
  /// the cache with that blob dropped a whole device's history, and its
  /// share of the daily totals with it.
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
    final merged = Map<String, ReadingActivity>.of(await _remoteLedgers());
    for (final entry in decoded.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key == id || value is! Map) continue;
      final incoming = _ledgerFromJson(value);
      final existing = merged[key];
      merged[key] = existing == null
          ? incoming
          : _mergeLedgers(existing, incoming);
    }
    final encoded = jsonEncode({
      for (final e in merged.entries) e.key: _ledgerToJson(e.value),
    });
    final existing = await _db.kvGet(_kRemote);
    if (existing == encoded) return false;
    await _db.kvSet(_kRemote, encoded);
    return true;
  }

  /// Combines two copies of one device's ledger by taking the larger value
  /// for each day and volume.
  ///
  /// A tally only ever grows, and only on the device that owns it, so the
  /// bigger number is always the newer one. That makes the merge
  /// order-independent: a blob that arrives late carrying an out-of-date
  /// copy of a device can no longer walk that device's totals backwards.
  static ReadingActivity _mergeLedgers(ReadingActivity a, ReadingActivity b) {
    Map<String, int> larger(Map<String, int> x, Map<String, int> y) {
      final out = Map<String, int>.of(x);
      y.forEach((k, v) => out[k] = max(out[k] ?? 0, v));
      return out;
    }

    return ReadingActivity(
      dailySeconds: larger(a.dailySeconds, b.dailySeconds),
      perVolumeSeconds: larger(a.perVolumeSeconds, b.perVolumeSeconds),
      dailyWords: larger(a.dailyWords, b.dailyWords),
      perVolumeWords: larger(a.perVolumeWords, b.perVolumeWords),
    );
  }

  /// Adds [delta] seconds to today's tally and to the per-volume tally for
  /// [volume]. Sessions shorter than a second are ignored so app-switch
  /// noise can't poison the streak.
  /// Adds [delta] seconds to today's tally and to the per-volume tally for
  /// [volume], plus [words] newly-read words to both. Sessions shorter than a
  /// second are ignored so app-switch noise can't poison the streak; [words]
  /// is the caller's already-deduplicated forward progress (see the reader's
  /// word high-water mark), so it is safe to add straight onto both tallies.
  Future<void> record(
    Volume volume,
    Duration delta, {
    int words = 0,
    DateTime? now,
  }) async {
    final seconds = delta.inSeconds;
    if (seconds <= 0) return;
    final newWords = words < 0 ? 0 : words;
    await _ensureMigrated();
    final dateKey = _dateKey(_today(now));
    final volumeKey = '${volume.seriesOpdsId}/${volume.fileName}';
    await _db
        .into(_db.dailyActivityRows)
        .insert(
          DailyActivityRowsCompanion(
            day: Value(dateKey),
            seconds: Value(seconds),
            words: Value(newWords),
          ),
          onConflict: DoUpdate(
            (old) => DailyActivityRowsCompanion.custom(
              seconds: old.seconds + Constant(seconds),
              words: old.words + Constant(newWords),
            ),
          ),
        );
    await _db
        .into(_db.volumeActivityRows)
        .insert(
          VolumeActivityRowsCompanion(
            volumeKey: Value(volumeKey),
            seconds: Value(seconds),
            words: Value(newWords),
          ),
          onConflict: DoUpdate(
            (old) => VolumeActivityRowsCompanion.custom(
              seconds: old.seconds + Constant(seconds),
              words: old.words + Constant(newWords),
            ),
          ),
        );
    CloudSyncService().pushActivitySoon();
  }

  /// This device's recorded word count for [volume] — the reader seeds its
  /// word high-water mark from this on open so re-reads don't re-count.
  Future<int> wordsForVolume(Volume volume) async {
    final key = '${volume.seriesOpdsId}/${volume.fileName}';
    return (await _loadLocal()).perVolumeWords[key] ?? 0;
  }

  // ── one-time import from SharedPreferences ──────────────────────────────

  Future<void> _ensureMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrated) ?? false) return;
    _migration ??= _importFromPrefs(
      prefs,
    ).whenComplete(() => _migration = null);
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
          final dailyWordsRaw = decoded['dailyWords'];
          final volumeWordsRaw = decoded['perVolumeWords'];
          int wordsFor(Object? raw, String key) {
            if (raw is Map) {
              final v = raw[key];
              if (v is num) return v.toInt();
            }
            return 0;
          }

          await _db.batch((b) {
            if (dailyRaw is Map) {
              b.insertAll(_db.dailyActivityRows, [
                for (final entry in dailyRaw.entries)
                  if (entry.value is num)
                    DailyActivityRowsCompanion(
                      day: Value(entry.key.toString()),
                      seconds: Value((entry.value as num).toInt()),
                      words: Value(
                        wordsFor(dailyWordsRaw, entry.key.toString()),
                      ),
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
                      words: Value(
                        wordsFor(volumeWordsRaw, entry.key.toString()),
                      ),
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
        'dailyWords': activity.dailyWords,
        'perVolumeWords': activity.perVolumeWords,
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
