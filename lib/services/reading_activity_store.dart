import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

/// Persists reading-time activity across app launches.
///
/// Stored as one JSON blob in SharedPreferences under [_key]. Cheap to load
/// and write (tens of dates max in practice), so we don't bother with
/// per-day keys.
class ReadingActivityStore {
  static const _key = 'reading_activity';

  Future<ReadingActivity> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return ReadingActivity.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return ReadingActivity.empty;
      final daily = <String, int>{};
      final perVolume = <String, int>{};
      final dailyRaw = decoded['daily'];
      if (dailyRaw is Map) {
        dailyRaw.forEach((k, v) {
          if (v is num) daily[k.toString()] = v.toInt();
        });
      }
      final volumeRaw = decoded['perVolume'];
      if (volumeRaw is Map) {
        volumeRaw.forEach((k, v) {
          if (v is num) perVolume[k.toString()] = v.toInt();
        });
      }
      return ReadingActivity(
        dailySeconds: daily,
        perVolumeSeconds: perVolume,
      );
    } on FormatException {
      return ReadingActivity.empty;
    }
  }

  /// Adds [delta] seconds to today's tally and to the per-volume tally for
  /// [volume]. Sessions shorter than a second are ignored so app-switch
  /// noise can't poison the streak.
  Future<void> record(Volume volume, Duration delta, {DateTime? now}) async {
    final seconds = delta.inSeconds;
    if (seconds <= 0) return;
    final activity = await load();
    final dateKey = _dateKey(_today(now));
    final volumeKey = '${volume.seriesOpdsId}/${volume.fileName}';
    final daily = Map<String, int>.of(activity.dailySeconds);
    final perVolume = Map<String, int>.of(activity.perVolumeSeconds);
    daily[dateKey] = (daily[dateKey] ?? 0) + seconds;
    perVolume[volumeKey] = (perVolume[volumeKey] ?? 0) + seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({'daily': daily, 'perVolume': perVolume}),
    );
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
