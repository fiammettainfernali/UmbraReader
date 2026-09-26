// What the reading ledger adds up to: a level, a set of ladders that never
// top out, and the rare finds that are not on any list until they happen.
//
// Everything here is DERIVED from data the app already keeps — the daily
// activity ledger, reading positions, the library and its metadata. Nothing
// counts events as they occur. That choice is what makes the whole thing
// work on the first launch after it ships: a reader with two years of
// history opens the screen and their two years are already there, rather
// than starting from zero as though they had never read anything. It also
// means no counter can drift, double-count a re-read, or miss a session
// because the app was closed — re-evaluating is always safe and always
// gives the same answer.
//
// The only thing that has to be stored is WHEN something was first earned,
// because that is the one fact the data cannot reconstruct afterwards. See
// award_store.dart.

import 'dart:math';

import '../models/series.dart';
import 'reading_activity_store.dart';
import 'reading_progress_store.dart';

/// Everything the evaluator reads. Assembled once per pass so the ladders
/// cannot disagree with each other about the state of the library.
class AwardContext {
  const AwardContext({
    required this.activity,
    required this.entries,
    required this.library,
    this.highlightsPerSeries = const {},
    DateTime? now,
  }) : _now = now;

  final ReadingActivity activity;

  /// Reading positions, one per volume.
  final List<ReadingEntry> entries;

  /// Library metadata — genres, authors, chapter counts, when a book arrived.
  final List<Series> library;

  final Map<int, int> highlightsPerSeries;

  final DateTime? _now;
  DateTime get now => _now ?? DateTime.now();

  int get hoursRead => activity.totalSeconds ~/ 3600;
  int get wordsRead => activity.totalWords;
  int get daysRead => activity.dailySeconds.values.where((s) => s > 0).length;

  List<ReadingEntry> get finishedEntries => [
    for (final e in entries)
      if (e.progress.isFinished) e,
  ];

  int get booksFinished => finishedEntries.length;

  /// Series with at least one finished volume — the unit a reader thinks in
  /// ("I finished that novel"), where a volume is a packaging detail.
  Set<int> get seriesTouched => {
    for (final e in finishedEntries) e.volume.seriesOpdsId,
  };

  int get highlightsSaved =>
      highlightsPerSeries.values.fold(0, (sum, n) => sum + n);
}

/// A progression with no final rung.
///
/// The rungs are seeded by hand while the numbers are small and the spacing
/// matters, then doubled forever. A fixed list is the thing that kills these
/// systems: forty badges are picked clean in about six weeks and the screen
/// becomes a museum. Doubling keeps the next rung roughly a constant
/// *proportion* of the way off however far in someone gets, so the hundredth
/// hour and the five-thousandth both feel like the same kind of climb.
class AwardLadder {
  const AwardLadder({
    required this.id,
    required this.name,
    required this.unit,
    required this.seeds,
    required this.valueOf,
  });

  final String id;
  final String name;

  /// Plural noun for the count, e.g. 'hours'.
  final String unit;

  /// The hand-placed rungs, ascending. Past the last one, each rung is twice
  /// the one before.
  final List<int> seeds;

  final int Function(AwardContext) valueOf;

  /// The [n]th rung, counting from zero. Defined for every n, forever.
  int rung(int n) {
    if (n < seeds.length) return seeds[n];
    return seeds.last * pow(2, n - seeds.length + 1).toInt();
  }

  /// How many rungs [value] has passed.
  int reachedBy(int value) {
    var n = 0;
    while (value >= rung(n)) {
      n++;
      // Nothing real reaches this, and it stops a bad valueOf from hanging
      // the screen in a loop that has no other exit.
      if (n > 200) break;
    }
    return n;
  }

  LadderProgress progressFor(AwardContext ctx) {
    final value = valueOf(ctx);
    final reached = reachedBy(value);
    final previous = reached == 0 ? 0 : rung(reached - 1);
    final next = rung(reached);
    return LadderProgress(
      ladder: this,
      value: value,
      rungsReached: reached,
      previousRung: previous,
      nextRung: next,
      fraction: next <= previous
          ? 1
          : ((value - previous) / (next - previous)).clamp(0.0, 1.0),
    );
  }
}

/// Where a reader stands on one ladder.
class LadderProgress {
  const LadderProgress({
    required this.ladder,
    required this.value,
    required this.rungsReached,
    required this.previousRung,
    required this.nextRung,
    required this.fraction,
  });

  final AwardLadder ladder;
  final int value;

  /// Rungs passed — also the badge tier, so tier 3 of 'hours' is a thing
  /// that can be named and shown without storing a row per tier.
  final int rungsReached;
  final int previousRung;
  final int nextRung;

  /// 0..1 towards [nextRung], for a bar that is always visibly moving.
  final double fraction;

  /// Stable id for the tier currently held, e.g. `hours.4`. Empty before the
  /// first rung, because nothing has been earned yet.
  String get badgeId => rungsReached == 0 ? '' : '${ladder.id}.$rungsReached';

  int get remaining => (nextRung - value).clamp(0, 1 << 62);
}

/// The ladders themselves.
///
/// Time leads because it is the one thing every reader accrues, including
/// on the days they read a little of something they never finish.
const kAwardLadders = <AwardLadder>[
  AwardLadder(
    id: 'hours',
    name: 'Hours in books',
    unit: 'hours',
    seeds: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500],
    valueOf: _hours,
  ),
  AwardLadder(
    id: 'finished',
    name: 'Books finished',
    unit: 'books',
    seeds: [1, 3, 5, 10, 25, 50, 100, 250, 500],
    valueOf: _finished,
  ),
  AwardLadder(
    id: 'days',
    name: 'Days read',
    unit: 'days',
    seeds: [1, 7, 30, 100, 250, 365, 750, 1500],
    valueOf: _days,
  ),
  AwardLadder(
    id: 'words',
    name: 'Words read',
    unit: 'words',
    seeds: [50000, 250000, 1000000, 5000000, 10000000, 25000000, 50000000],
    valueOf: _words,
  ),
  AwardLadder(
    id: 'series',
    name: 'Series tasted',
    unit: 'series',
    seeds: [1, 3, 10, 25, 50, 100, 250],
    valueOf: _series,
  ),
  AwardLadder(
    id: 'highlights',
    name: 'Passages saved',
    unit: 'highlights',
    seeds: [1, 10, 50, 100, 500, 1000],
    valueOf: _highlights,
  ),
];

int _hours(AwardContext c) => c.hoursRead;
int _finished(AwardContext c) => c.booksFinished;
int _days(AwardContext c) => c.daysRead;
int _words(AwardContext c) => c.wordsRead;
int _series(AwardContext c) => c.seriesTouched.length;
int _highlights(AwardContext c) => c.highlightsSaved;

// ── level ────────────────────────────────────────────────────────────────

/// Experience: a minute read is a point, and finishing a book is worth
/// another hundred.
///
/// Time is the honest denominator — it is what the reader actually spent —
/// and the finish bonus stops a 250-chapter novel from being worth less per
/// hour than grazing. Nothing here can be farmed: both terms come from the
/// ledger's forward-progress-only accounting, so a re-read adds the time it
/// really took and no more.
int xpFor(AwardContext ctx) =>
    (ctx.activity.totalSeconds ~/ 60) + 100 * ctx.booksFinished;

/// Total XP needed to reach [level], for level >= 1.
///
/// 60·L^1.5. The exponent is what makes this last: levels arrive quickly at
/// first and then stretch, without ever stopping. Worked against two real
/// reading rates, where a year of half an hour a day is about 11k XP and two
/// hours a day about 44k:
///
///   level 10 →     1,897 XP   (~2 months at 30 min/day)
///   level 50 →    21,213 XP   (~2 years, or 6 months at 2 h/day)
///   level 100 →   60,000 XP   (~5.5 years, or 1.4 years at 2 h/day)
///   level 200 →  169,706 XP   (~15 years, or 3.9 years at 2 h/day)
///
/// So the ladder still has somewhere to go after a decade of half an hour a
/// night, and after four years of two hours a night. A linear curve would
/// have run out of interesting numbers inside one of those.
int xpForLevel(int level) => level <= 1 ? 0 : (60 * pow(level, 1.5)).round();

/// The level [xp] has reached — at least 1, never capped.
int levelForXp(int xp) {
  if (xp <= 0) return 1;
  // Inverse of the curve, then corrected: pow() rounding at the boundary can
  // put this one level either side, and a level that flickers as the ledger
  // ticks over would be worse than one that is briefly conservative.
  var level = max(1, (pow(xp / 60, 2 / 3)).floor());
  while (xpForLevel(level + 1) <= xp) {
    level++;
  }
  while (level > 1 && xpForLevel(level) > xp) {
    level--;
  }
  return level;
}

/// Where a reader is between two levels.
class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.xp,
    required this.levelStartXp,
    required this.nextLevelXp,
  });

  final int level;
  final int xp;
  final int levelStartXp;
  final int nextLevelXp;

  int get earnedIntoLevel => xp - levelStartXp;
  int get neededForLevel => nextLevelXp - levelStartXp;
  int get remaining => (nextLevelXp - xp).clamp(0, 1 << 62);

  double get fraction =>
      neededForLevel <= 0 ? 0 : (earnedIntoLevel / neededForLevel).clamp(0, 1);
}

LevelProgress levelProgressFor(AwardContext ctx) {
  final xp = xpFor(ctx);
  final level = levelForXp(xp);
  return LevelProgress(
    level: level,
    xp: xp,
    levelStartXp: xpForLevel(level),
    nextLevelXp: xpForLevel(level + 1),
  );
}

// ── rare finds ───────────────────────────────────────────────────────────

/// A one-off worth noticing, which nobody is told about in advance.
///
/// Ladders are for the reader who wants a number to climb; these are for the
/// pleasure of being told something true about a night you had. They are
/// deliberately not listed as goals anywhere — a hidden thing found is worth
/// more than a checklist item ticked, and a checklist is another way of
/// telling someone how they ought to read.
class RareFind {
  const RareFind({
    required this.id,
    required this.name,
    required this.describe,
    required this.earned,
  });

  final String id;
  final String name;

  /// Told in the past tense, after the fact — what actually happened.
  final String Function(AwardContext) describe;

  final bool Function(AwardContext) earned;
}

const kRareFinds = <RareFind>[
  RareFind(
    id: 'marathon',
    name: 'Lost the afternoon',
    describe: _marathonText,
    earned: _marathon,
  ),
  RareFind(
    id: 'comeback',
    name: 'Picked it back up',
    describe: _comebackText,
    earned: _comeback,
  ),
  RareFind(
    id: 'doorstop',
    name: 'Finished a doorstop',
    describe: _doorstopText,
    earned: _doorstop,
  ),
  RareFind(
    id: 'old-flame',
    name: 'Better late than never',
    describe: _oldFlameText,
    earned: _oldFlame,
  ),
  RareFind(
    id: 'wide-net',
    name: 'Casts a wide net',
    describe: _wideNetText,
    earned: _wideNet,
  ),
];

/// The longest single day on record, in seconds.
int _bestDaySeconds(AwardContext c) =>
    c.activity.dailySeconds.values.fold(0, (best, s) => s > best ? s : best);

bool _marathon(AwardContext c) => _bestDaySeconds(c) >= 4 * 3600;
String _marathonText(AwardContext c) =>
    '${(_bestDaySeconds(c) / 3600).toStringAsFixed(1)} hours of reading '
    'in a single day.';

/// The longest gap between two reading days, in days.
int _longestGap(AwardContext c) {
  final days =
      c.activity.dailySeconds.entries
          .where((e) => e.value > 0)
          .map((e) => DateTime.tryParse(e.key))
          .whereType<DateTime>()
          .toList()
        ..sort();
  var longest = 0;
  for (var i = 1; i < days.length; i++) {
    final gap = days[i].difference(days[i - 1]).inDays;
    if (gap > longest) longest = gap;
  }
  return longest;
}

bool _comeback(AwardContext c) => _longestGap(c) >= 30;
String _comebackText(AwardContext c) =>
    'Came back after ${_longestGap(c)} days away, and read again.';

int _longestFinished(AwardContext c) => c.finishedEntries.fold(
  0,
  (best, e) => e.progress.chapterCount > best ? e.progress.chapterCount : best,
);

bool _doorstop(AwardContext c) => _longestFinished(c) >= 200;
String _doorstopText(AwardContext c) =>
    'Finished something ${_longestFinished(c)} chapters long.';

/// A book that sat in the library a year or more before it was finished.
int _oldFlameDays(AwardContext c) {
  final addedById = {
    for (final s in c.library)
      if (s.addedAt != null) s.opdsId: s.addedAt!,
  };
  var longest = 0;
  for (final e in c.finishedEntries) {
    final added = addedById[e.volume.seriesOpdsId];
    final done = e.progress.updatedAt;
    if (added == null || done == null) continue;
    final waited = done.difference(added).inDays;
    if (waited > longest) longest = waited;
  }
  return longest;
}

bool _oldFlame(AwardContext c) => _oldFlameDays(c) >= 365;
String _oldFlameText(AwardContext c) =>
    'Finished a book that waited ${(_oldFlameDays(c) / 365).floor()} '
    'year(s) on the shelf.';

/// Distinct genres across everything finished.
Set<String> _finishedGenres(AwardContext c) {
  final byId = {for (final s in c.library) s.opdsId: s};
  return {
    for (final e in c.finishedEntries)
      ...?byId[e.volume.seriesOpdsId]?.genres.map(
        (g) => g.trim().toLowerCase(),
      ),
  }..removeWhere((g) => g.isEmpty);
}

bool _wideNet(AwardContext c) => _finishedGenres(c).length >= 10;
String _wideNetText(AwardContext c) =>
    'Finished books across ${_finishedGenres(c).length} different genres.';

// ── the whole picture ────────────────────────────────────────────────────

/// Everything earned, as of now.
class AwardSnapshot {
  const AwardSnapshot({
    required this.level,
    required this.ladders,
    required this.rareFinds,
  });

  final LevelProgress level;
  final List<LadderProgress> ladders;

  /// Only the finds actually earned, each with its own past-tense line.
  final List<({RareFind find, String description})> rareFinds;

  /// Every badge id currently held — ladder tiers plus rare finds. This is
  /// what the store diffs against to notice something new.
  Set<String> get badgeIds => {
    for (final l in ladders)
      if (l.badgeId.isNotEmpty) l.badgeId,
    for (final r in rareFinds) 'find.${r.find.id}',
  };
}

AwardSnapshot evaluateAwards(AwardContext ctx) => AwardSnapshot(
  level: levelProgressFor(ctx),
  ladders: [for (final l in kAwardLadders) l.progressFor(ctx)],
  rareFinds: [
    for (final f in kRareFinds)
      if (f.earned(ctx)) (find: f, description: f.describe(ctx)),
  ],
);
