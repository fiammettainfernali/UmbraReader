import 'dart:convert';
import 'dart:math' as math;

import '../db/app_database.dart';
import '../models/series.dart';
import '../models/volume.dart';
import '../screens/library_home.dart' show isAdultSeries;
import 'book_length_store.dart';
import 'reading_progress_store.dart';
import 'recommendation_feedback_store.dart';
import 'series_status_store.dart';

/// Help choosing what to read.
///
/// With a library of well over a thousand novels, every screen handed over
/// the whole pile at the moment of choosing. What is here shows a few
/// instead, makes starting a book cheap, and keeps the number of books on
/// the go small:
///
/// - [pickTonight]: three picks, each with a reason.
/// - [TryItFirst]: a new book is only being tried until it is kept.
/// - [ChoosingStore.booksAtOnce]: how many books can be in progress at once.
/// - [stalledBooks]: books left untouched for a month, to sort out.

enum TonightKind { carryOn, likeLast, wildcard }

class TonightPick {
  const TonightPick({
    required this.series,
    required this.kind,
    required this.reason,
    this.entry,
  });

  final Series series;
  final TonightKind kind;
  final String reason;

  /// Where to pick up, for [TonightKind.carryOn].
  final ReadingEntry? entry;
}

/// The latest entry per series, newest first, from entries in any order.
List<ReadingEntry> latestPerSeries(List<ReadingEntry> entries) {
  final sorted = [...entries]
    ..sort((a, b) {
      final at = a.progress.updatedAt, bt = b.progress.updatedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
  final seen = <int>{};
  return [
    for (final e in sorted)
      if (seen.add(e.volume.seriesOpdsId)) e,
  ];
}

/// Books being tried, newest first: one entry per series.
List<ReadingEntry> tryingShelf(
  List<ReadingEntry> entries,
  Map<int, SeriesStatus> statuses,
) => [
  for (final e in latestPerSeries(entries))
    if (statuses[e.volume.seriesOpdsId] == SeriesStatus.trying &&
        !e.progress.isFinished)
      e,
];

/// Three picks for tonight: one to carry on with, one like the last book
/// finished, and one wildcard. The same three all day (the wildcard is
/// shuffled by date), until one is set aside with Not now.
///
/// [shelf] is Continue reading as shown; [entries] every reading place.
/// [similar] answers "more like this" for a book. A new book is one never
/// opened, without a status, not set aside with Not now or ✕, with a cover
/// and a description, and not adult (the spotlight's rule).
List<TonightPick> pickTonight({
  required List<Series> library,
  required List<ReadingEntry> shelf,
  required List<ReadingEntry> entries,
  required Map<int, SeriesStatus> statuses,
  required Map<int, RecommendationFeedback> feedback,
  required List<Series> Function(Series source) similar,
  required DateTime today,
  Set<int> skipped = const {},
  Map<int, BookLength> lengths = const {},
  int wordsPerMinute = 0,
}) {
  final byId = {for (final s in library) s.opdsId: s};
  final opened = {
    for (final e in entries)
      if (e.progress.isStarted || e.progress.isFinished) e.volume.seriesOpdsId,
  };
  final chosen = <int>{};
  final picks = <TonightPick>[];

  bool isNew(Series s) =>
      !opened.contains(s.opdsId) &&
      (statuses[s.opdsId] ?? SeriesStatus.none) == SeriesStatus.none &&
      !feedback.containsKey(s.opdsId) &&
      !skipped.contains(s.opdsId) &&
      !chosen.contains(s.opdsId) &&
      s.coverUrl != null &&
      s.description.length > 80 &&
      !isAdultSeries(s);

  String newReason(Series s, String lead) {
    final line = lengthLine(lengths[s.opdsId], wordsPerMinute);
    return line == null ? lead : '$lead · $line';
  }

  // One to carry on with: whichever was read most recently, kept or tried.
  final onTheGo = latestPerSeries([
    ...shelf,
    ...tryingShelf(entries, statuses),
  ]);
  for (final entry in onTheGo) {
    final series = byId[entry.volume.seriesOpdsId];
    if (series == null || skipped.contains(series.opdsId)) continue;
    final p = entry.progress;
    final where = p.chapterCount > 0
        ? 'Chapter ${p.chapterIndex + 1} of ${p.chapterCount}'
        : 'Chapter ${p.chapterIndex + 1}';
    final trying = statuses[series.opdsId] == SeriesStatus.trying;
    picks.add(
      TonightPick(
        series: series,
        kind: TonightKind.carryOn,
        reason: trying ? 'Trying it · $where' : where,
        entry: entry,
      ),
    );
    chosen.add(series.opdsId);
    break;
  }

  // One like the last book finished, or failing that, the one on the go.
  final finished = latestPerSeries([
    for (final e in entries)
      if (e.progress.isFinished ||
          statuses[e.volume.seriesOpdsId] == SeriesStatus.caughtUp)
        e,
  ]);
  final source = finished.isNotEmpty
      ? byId[finished.first.volume.seriesOpdsId]
      : (picks.isNotEmpty ? picks.first.series : null);
  if (source != null) {
    final verb = finished.isNotEmpty ? 'finished' : 'are reading';
    for (final s in similar(source)) {
      if (!isNew(s)) continue;
      picks.add(
        TonightPick(
          series: s,
          kind: TonightKind.likeLast,
          reason: newReason(s, 'Like ${source.title}, which you $verb'),
        ),
      );
      chosen.add(s.opdsId);
      break;
    }
  }

  // And a wildcard, the same one all day.
  final pool = [
    for (final s in library)
      if (isNew(s)) s,
  ]..shuffle(math.Random(today.year * 10000 + today.month * 100 + today.day));
  for (final s in pool) {
    if (picks.length >= 3) break;
    picks.add(
      TonightPick(
        series: s,
        kind: TonightKind.wildcard,
        reason: newReason(s, 'Something different'),
      ),
    );
    chosen.add(s.opdsId);
  }
  return picks;
}

/// Picks one of tonight's new books for you: never the one on the go.
TonightPick? decideFor(List<TonightPick> picks, math.Random random) {
  final fresh = [
    for (final p in picks)
      if (p.kind != TonightKind.carryOn) p,
  ];
  return fresh.isEmpty ? null : fresh[random.nextInt(fresh.length)];
}

/// Books on the go, read or tried, left untouched for [after]: one entry per
/// series, longest untouched first. A book kept going at the last check-in
/// isn't asked about again until [after] has passed since.
List<ReadingEntry> stalledBooks(
  List<ReadingEntry> entries,
  Map<int, SeriesStatus> statuses, {
  required DateTime now,
  Set<String> hidden = const {},
  Map<int, DateTime> keptAt = const {},
  Duration after = const Duration(days: 30),
}) {
  final out = <ReadingEntry>[];
  for (final e in latestPerSeries(entries)) {
    final id = e.volume.seriesOpdsId;
    final status = statuses[id] ?? SeriesStatus.none;
    if (status != SeriesStatus.none &&
        status != SeriesStatus.reading &&
        status != SeriesStatus.trying) {
      continue;
    }
    final p = e.progress;
    if (!p.isStarted || p.isFinished) continue;
    if (hidden.contains('$id/${e.volume.fileName}')) continue;
    final at = p.updatedAt;
    if (at == null || now.difference(at) < after) continue;
    final kept = keptAt[id];
    if (kept != null && now.difference(kept) < after) continue;
    out.add(e);
  }
  return out.reversed.toList();
}

/// What choosing remembers on this phone.
class ChoosingStore {
  ChoosingStore._();
  static final ChoosingStore instance = ChoosingStore._();

  static const _kSkipped = 'tonight_skipped';
  static const _kBooksAtOnce = 'books_at_once';
  static const _kCheckInAt = 'stalled_checkin_at';
  static const _kKept = 'stalled_kept';
  static const _kAskAfter = 'try_ask_after';

  /// How many books can be in progress at once before starting another asks
  /// which to pause. 0 means no limit.
  static const defaultBooksAtOnce = 3;

  /// How often the stalled-books check-in comes round.
  static const checkInEvery = Duration(days: 7);

  AppDatabase get _db => AppDatabase.instance;

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Books set aside with Not now today. Tomorrow starts afresh.
  Future<Set<int>> skippedToday(DateTime today) async {
    final raw = _json(await _db.kvGet(_kSkipped));
    if (raw is! Map || raw['day'] != _day(today)) return {};
    return {
      for (final id in (raw['ids'] as List? ?? const []))
        if (id is num) id.toInt(),
    };
  }

  Future<void> skipToday(int seriesId, DateTime today) async {
    final ids = {...await skippedToday(today), seriesId};
    await _db.kvSet(
      _kSkipped,
      jsonEncode({'day': _day(today), 'ids': ids.toList()}),
    );
  }

  Future<int> booksAtOnce() async =>
      int.tryParse(await _db.kvGet(_kBooksAtOnce) ?? '') ?? defaultBooksAtOnce;

  Future<void> setBooksAtOnce(int count) =>
      _db.kvSet(_kBooksAtOnce, '${count < 0 ? 0 : count}');

  static const _kLimitCheck = 'books_at_once_check';

  /// A book was just kept in the reader; the library checks the limit on
  /// return, where there's room to show what's in progress.
  Future<void> markLimitCheck(int seriesId) =>
      _db.kvSet(_kLimitCheck, '$seriesId');

  /// The book waiting for a limit check, taken so it's asked once.
  Future<int?> takeLimitCheck() async {
    final id = int.tryParse(await _db.kvGet(_kLimitCheck) ?? '');
    if (id != null) await _db.kvSet(_kLimitCheck, '');
    return id;
  }

  /// Whether the stalled-books check-in is due: once a week at most.
  Future<bool> checkInDue(DateTime now) async {
    final at = DateTime.tryParse(await _db.kvGet(_kCheckInAt) ?? '');
    return at == null || now.difference(at) >= checkInEvery;
  }

  Future<void> checkedIn(DateTime now) =>
      _db.kvSet(_kCheckInAt, now.toIso8601String());

  Future<Map<int, DateTime>> keptAt() async {
    final raw = _json(await _db.kvGet(_kKept));
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (int.tryParse('${e.key}') != null &&
            DateTime.tryParse('${e.value}') != null)
          int.parse('${e.key}'): DateTime.parse('${e.value}'),
    };
  }

  Future<void> keepGoing(int seriesId, DateTime now) async {
    final kept = {
      for (final e in (await keptAt()).entries)
        '${e.key}': e.value.toIso8601String(),
      '$seriesId': now.toIso8601String(),
    };
    await _db.kvSet(_kKept, jsonEncode(kept));
  }

  /// The chapter index from which a book being tried asks to be kept.
  Future<int> askFrom(int seriesId) async {
    final raw = _json(await _db.kvGet(_kAskAfter));
    final at = raw is Map ? raw['$seriesId'] : null;
    return at is num ? at.toInt() : TryItFirst.askAtChapter;
  }

  Future<void> askAgainFrom(int seriesId, int chapterIndex) async {
    final raw = _json(await _db.kvGet(_kAskAfter));
    final all = raw is Map
        ? Map<String, dynamic>.of(raw.cast())
        : <String, dynamic>{};
    all['$seriesId'] = chapterIndex;
    await _db.kvSet(_kAskAfter, jsonEncode(all));
  }

  static Object? _json(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}

/// A new book is only being tried: it stays off Continue reading, and after
/// its third chapter asks whether to keep it.
class TryItFirst {
  const TryItFirst();

  /// The fourth chapter, by index: three read, and still going.
  static const askAtChapter = 3;

  /// How many chapters "Ask me later" waits.
  static const askAgainAfter = 3;

  /// Marks [volume]'s series as being tried when this is the first time any
  /// of it has been opened and it has no status. True when it was marked.
  Future<bool> markIfNew(Volume volume) async {
    final id = volume.seriesOpdsId;
    final store = SeriesStatusStore();
    if (await store.statusFor(id) != SeriesStatus.none) return false;
    final entries = await ReadingProgressStore().allEntries();
    final opened = entries.any(
      (e) =>
          e.volume.seriesOpdsId == id &&
          (e.progress.isStarted || e.progress.isFinished),
    );
    if (opened) return false;
    await store.setStatus(id, SeriesStatus.trying);
    return true;
  }

  /// Whether to ask now, on [chapterIndex] of a book in [seriesId].
  Future<bool> shouldAsk(int seriesId, int chapterIndex) async {
    if (chapterIndex < askAtChapter) return false;
    if (await SeriesStatusStore().statusFor(seriesId) != SeriesStatus.trying) {
      return false;
    }
    return chapterIndex >= await ChoosingStore.instance.askFrom(seriesId);
  }

  Future<void> keep(int seriesId) =>
      SeriesStatusStore().setStatus(seriesId, SeriesStatus.reading);

  Future<void> notForMe(int seriesId) =>
      SeriesStatusStore().setStatus(seriesId, SeriesStatus.dropped);

  Future<void> askLater(int seriesId, int chapterIndex) => ChoosingStore
      .instance
      .askAgainFrom(seriesId, chapterIndex + askAgainAfter);
}
