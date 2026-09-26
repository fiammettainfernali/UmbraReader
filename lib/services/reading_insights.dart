// Things that are true about how someone reads, found in the ledger they
// already have.
//
// This is the half of the rewards system that cannot run out, and it earns
// that the same way the ladders do — by not being a list. Every insight here
// is a QUESTION asked of the data rather than a fact written down, so the
// answers keep changing as the reading does, and several of them cannot even
// be asked until enough history exists to answer them (a year against last
// year needs two years first). A handful are shown at a time and they rotate
// on a weekly clock, so the screen has something different to say most times
// it is opened without anything having been invented for it.

import 'awards.dart';
import 'reading_activity_store.dart';

/// One observation, ready to show.
class ReadingInsight {
  const ReadingInsight({
    required this.id,
    required this.headline,
    required this.detail,
  });

  /// Stable across regenerations, so the UI can animate rather than flicker.
  final String id;

  /// The finding itself, short enough to read at a glance.
  final String headline;

  /// The context that makes it mean something.
  final String detail;
}

/// A year, summarised. The retrospective that gets richer every year simply
/// because there is another one of these each January.
class YearInReview {
  const YearInReview({
    required this.year,
    required this.hours,
    required this.booksFinished,
    required this.daysRead,
    required this.busiestMonth,
    required this.busiestMonthHours,
    required this.topSeries,
    required this.genres,
  });

  final int year;
  final int hours;
  final int booksFinished;
  final int daysRead;

  /// 1-12, or 0 when the year holds no reading at all.
  final int busiestMonth;
  final int busiestMonthHours;

  /// Title of the series that took the most time that year, if any.
  final String? topSeries;

  /// Distinct genres finished that year.
  final int genres;

  bool get isEmpty => hours == 0 && booksFinished == 0 && daysRead == 0;
}

// ── helpers over the daily ledger ────────────────────────────────────────

Map<DateTime, int> _byDate(ReadingActivity activity) => {
  for (final e in activity.dailySeconds.entries)
    if (e.value > 0 && DateTime.tryParse(e.key) != null)
      DateTime.parse(e.key): e.value,
};

String _hoursPhrase(int seconds) {
  final hours = seconds / 3600;
  if (hours >= 10) return '${hours.round()} hours';
  if (hours >= 1) return '${hours.toStringAsFixed(1)} hours';
  return '${(seconds / 60).round()} minutes';
}

const _weekdayNames = [
  'Mondays',
  'Tuesdays',
  'Wednesdays',
  'Thursdays',
  'Fridays',
  'Saturdays',
  'Sundays',
];

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Total seconds per series id, from the per-volume ledger whose keys are
/// `seriesOpdsId/fileName`.
Map<int, int> secondsBySeries(ReadingActivity activity) {
  final out = <int, int>{};
  for (final e in activity.perVolumeSeconds.entries) {
    final id = int.tryParse(e.key.split('/').first);
    if (id == null) continue;
    out[id] = (out[id] ?? 0) + e.value;
  }
  return out;
}

// ── the questions ────────────────────────────────────────────────────────

ReadingInsight? _longestDay(AwardContext c) {
  final days = _byDate(c.activity);
  if (days.isEmpty) return null;
  final best = days.entries.reduce((a, b) => b.value > a.value ? b : a);
  if (best.value < 1800) return null;
  return ReadingInsight(
    id: 'longest-day',
    headline: 'Your longest day was ${_hoursPhrase(best.value)}',
    detail:
        '${_monthNames[best.key.month - 1]} ${best.key.day}, '
        '${best.key.year}.',
  );
}

ReadingInsight? _favouriteWeekday(AwardContext c) {
  final days = _byDate(c.activity);
  if (days.length < 21) return null; // three weeks before this means anything
  final totals = List<int>.filled(7, 0);
  for (final e in days.entries) {
    totals[e.key.weekday - 1] += e.value;
  }
  final total = totals.reduce((a, b) => a + b);
  if (total == 0) return null;
  var bestDay = 0;
  for (var i = 1; i < 7; i++) {
    if (totals[i] > totals[bestDay]) bestDay = i;
  }
  final share = (100 * totals[bestDay] / total).round();
  // A perfectly even week is 14%; below ~18% there is no real preference to
  // report and saying one anyway would be noise dressed as insight.
  if (share < 18) return null;
  return ReadingInsight(
    id: 'weekday',
    headline: '${_weekdayNames[bestDay]} are your reading day',
    detail:
        '$share% of all your reading time lands on a '
        '${_weekdayNames[bestDay].substring(0, _weekdayNames[bestDay].length - 1)}.',
  );
}

ReadingInsight? _bestWeek(AwardContext c) {
  final days = _byDate(c.activity);
  if (days.length < 7) return null;
  final sorted = days.keys.toList()..sort();
  var best = 0;
  DateTime? bestStart;
  for (final start in sorted) {
    var total = 0;
    for (var i = 0; i < 7; i++) {
      total += days[start.add(Duration(days: i))] ?? 0;
    }
    if (total > best) {
      best = total;
      bestStart = start;
    }
  }
  if (bestStart == null || best < 3600) return null;
  return ReadingInsight(
    id: 'best-week',
    headline: 'Your best week was ${_hoursPhrase(best)}',
    detail:
        'The seven days from ${_monthNames[bestStart.month - 1]} '
        '${bestStart.day}, ${bestStart.year}.',
  );
}

ReadingInsight? _pace(AwardContext c) {
  final wpm = c.activity.wordsPerMinute;
  if (wpm <= 0 || c.activity.totalSeconds < 3600) return null;
  // A 90,000-word novel is the usual yardstick for "a book".
  final hours = (90000 / wpm / 60).round();
  return ReadingInsight(
    id: 'pace',
    headline: 'You read about $wpm words a minute',
    detail: 'A 90,000-word novel takes you around $hours hours.',
  );
}

ReadingInsight? _thisYearAgainstLast(AwardContext c) {
  final days = _byDate(c.activity);
  if (days.isEmpty) return null;
  final year = c.now.year;
  var thisYear = 0;
  var lastYear = 0;
  for (final e in days.entries) {
    if (e.key.year == year) thisYear += e.value;
    if (e.key.year == year - 1) lastYear += e.value;
  }
  // Only worth saying once last year is a real comparison.
  if (lastYear < 3600 || thisYear < 3600) return null;
  final change = ((thisYear - lastYear) / lastYear * 100).round();
  final direction = change >= 0 ? 'up' : 'down';
  return ReadingInsight(
    id: 'year-on-year',
    headline: '$year is $direction ${change.abs()}% on ${year - 1}',
    detail:
        '${_hoursPhrase(thisYear)} so far, against ${_hoursPhrase(lastYear)} '
        'across all of ${year - 1}.',
  );
}

ReadingInsight? _mostReadSeries(AwardContext c) {
  final seconds = secondsBySeries(c.activity);
  if (seconds.isEmpty) return null;
  final top = seconds.entries.reduce((a, b) => b.value > a.value ? b : a);
  if (top.value < 3600) return null;
  final series = c.library.where((s) => s.opdsId == top.key).firstOrNull;
  if (series == null) return null;
  final share = (100 * top.value / c.activity.totalSeconds).round();
  return ReadingInsight(
    id: 'top-series',
    headline: 'You have spent ${_hoursPhrase(top.value)} in ${series.title}',
    detail: share >= 5
        ? 'That is $share% of all the reading you have ever done here.'
        : 'More than any other series in your library.',
  );
}

ReadingInsight? _steadiness(AwardContext c) {
  final days = _byDate(c.activity);
  if (days.length < 30) return null;
  final year = c.now.year;
  final readThisYear = days.keys.where((d) => d.year == year).length;
  final soFar = c.now.difference(DateTime(year)).inDays + 1;
  if (soFar < 60) return null;
  final share = (100 * readThisYear / soFar).round();
  return ReadingInsight(
    id: 'steadiness',
    headline: 'You read on $share% of the days this year',
    detail: '$readThisYear days out of $soFar.',
  );
}

ReadingInsight? _shelfDepth(AwardContext c) {
  final finished = c.booksFinished;
  if (finished < 3 || c.library.isEmpty) return null;
  final started = c.entries.where((e) => e.progress.isStarted).length;
  return ReadingInsight(
    id: 'shelf-depth',
    headline: '$finished finished, $started opened',
    detail: 'Out of ${c.library.length} books on the shelf.',
  );
}

ReadingInsight? _genreSpread(AwardContext c) {
  final byId = {for (final s in c.library) s.opdsId: s};
  final genres = <String>{};
  for (final e in c.finishedEntries) {
    for (final g in byId[e.volume.seriesOpdsId]?.genres ?? const <String>[]) {
      final key = g.trim();
      if (key.isNotEmpty) genres.add(key);
    }
  }
  if (genres.length < 3) return null;
  return ReadingInsight(
    id: 'genre-spread',
    headline: 'You have finished books in ${genres.length} genres',
    detail: (genres.toList()..sort()).take(4).join(', '),
  );
}

/// Every question, in a fixed order. The rotation below is what decides
/// which get asked today.
const _generators = <ReadingInsight? Function(AwardContext)>[
  _longestDay,
  _bestWeek,
  _favouriteWeekday,
  _pace,
  _thisYearAgainstLast,
  _mostReadSeries,
  _steadiness,
  _shelfDepth,
  _genreSpread,
];

/// Everything currently answerable, in generator order.
List<ReadingInsight> allInsights(AwardContext ctx) => [
  for (final g in _generators) ?g(ctx),
];

/// The [count] insights to show now.
///
/// Rotates on a weekly clock rather than randomly: the same week always
/// shows the same set, so the screen is stable if it is opened twice in an
/// afternoon, and it has moved on by the following week. Random selection
/// would make the page feel unreliable — a reader who saw something
/// interesting yesterday could not find it again today.
List<ReadingInsight> rotatingInsights(
  AwardContext ctx, {
  int count = 3,
  DateTime? now,
}) {
  final all = allInsights(ctx);
  if (all.length <= count) return all;
  final clock = now ?? ctx.now;
  // Counted from a Monday, so a "week" here is the week the reader is
  // actually living in. Blocks measured from the 1st of January instead
  // would turn over mid-week — and reset every New Year, repeating a set
  // — which is a strange thing for a page to do for no visible reason.
  const anchor = 4; // 1970-01-01 was a Thursday; +4 days reaches Monday.
  final week = ((clock.difference(DateTime(1970)).inDays - anchor) ~/ 7).abs();
  final offset = (week * count) % all.length;
  return [for (var i = 0; i < count; i++) all[(offset + i) % all.length]];
}

// ── the yearly retrospective ─────────────────────────────────────────────

/// What [year] looked like. Empty years are returned as empty rather than
/// null so a caller can show "nothing here yet" without special-casing.
YearInReview yearInReview(AwardContext ctx, int year) {
  final days = _byDate(ctx.activity);
  var seconds = 0;
  var daysRead = 0;
  final monthly = List<int>.filled(12, 0);
  for (final e in days.entries) {
    if (e.key.year != year) continue;
    seconds += e.value;
    daysRead++;
    monthly[e.key.month - 1] += e.value;
  }

  final finished = [
    for (final e in ctx.finishedEntries)
      if (e.progress.updatedAt?.year == year) e,
  ];

  final byId = {for (final s in ctx.library) s.opdsId: s};
  final genres = <String>{};
  for (final e in finished) {
    for (final g in byId[e.volume.seriesOpdsId]?.genres ?? const <String>[]) {
      final key = g.trim().toLowerCase();
      if (key.isNotEmpty) genres.add(key);
    }
  }

  var busiest = 0;
  for (var m = 1; m < 12; m++) {
    if (monthly[m] > monthly[busiest]) busiest = m;
  }

  // Time per series is a lifetime tally, so the top series of a given year
  // can only be named from what was finished in it — claiming otherwise
  // would credit this year with last year's reading.
  String? topSeries;
  var topSeconds = 0;
  final seriesSeconds = secondsBySeries(ctx.activity);
  for (final e in finished) {
    final id = e.volume.seriesOpdsId;
    final s = seriesSeconds[id] ?? 0;
    if (s > topSeconds) {
      topSeconds = s;
      topSeries = byId[id]?.title;
    }
  }

  return YearInReview(
    year: year,
    hours: seconds ~/ 3600,
    booksFinished: finished.length,
    daysRead: daysRead,
    busiestMonth: seconds == 0 ? 0 : busiest + 1,
    busiestMonthHours: monthly[busiest] ~/ 3600,
    topSeries: topSeries,
    genres: genres.length,
  );
}

/// Years with any reading at all, newest first — the retrospectives worth
/// offering.
List<int> yearsWithReading(AwardContext ctx) {
  final years = <int>{
    for (final d in _byDate(ctx.activity).keys) d.year,
    for (final e in ctx.finishedEntries)
      if (e.progress.updatedAt != null) e.progress.updatedAt!.year,
  };
  return years.toList()..sort((a, b) => b.compareTo(a));
}

String monthName(int month) =>
    month >= 1 && month <= 12 ? _monthNames[month - 1] : '';
