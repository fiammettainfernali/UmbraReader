import 'dart:convert';

import '../db/app_database.dart';
import 'control_client.dart';
import 'settings_service.dart';

/// How long a novel is, and whether its story has finished.
class BookLength {
  const BookLength({
    required this.words,
    required this.estimated,
    required this.finished,
  });

  final int words;

  /// Some chapters weren't counted, so part of [words] is their average.
  final bool estimated;

  /// The story itself is complete, not still being written.
  final bool finished;
}

/// Each novel's length, from the computer, kept on the phone for a day.
///
/// A 6-hour book and a 300-hour one looked alike in the library. The
/// computer knows every chapter's word count; this keeps its answer so a
/// pick can say how big a commitment it is, even away from home.
class BookLengthStore {
  BookLengthStore._();
  static final BookLengthStore instance = BookLengthStore._();

  static const _kLengths = 'book_lengths';
  static const _kFetchedAt = 'book_lengths_at';
  static const maxAge = Duration(days: 1);

  Map<int, BookLength>? _byId;

  /// What is kept on the phone, possibly empty. Never asks the computer.
  Future<Map<int, BookLength>> load() async {
    return _byId ??= _parse(await AppDatabase.instance.kvGet(_kLengths));
  }

  /// Asks the computer again when what is kept is a day old. True when
  /// something new arrived. Never throws: an old answer is still an answer.
  Future<bool> refresh(OpdsSettings settings, {DateTime? now}) async {
    if (!settings.isConfigured || !settings.hasAuth) return false;
    final clock = now ?? DateTime.now();
    final at = DateTime.tryParse(
      await AppDatabase.instance.kvGet(_kFetchedAt) ?? '',
    );
    if (at != null && clock.difference(at) < maxAge) return false;
    try {
      final answer = await ControlClient(settings).lengths();
      final raw = jsonEncode(answer);
      await AppDatabase.instance.kvSet(_kLengths, raw);
      await AppDatabase.instance.kvSet(_kFetchedAt, clock.toIso8601String());
      _byId = _parse(raw);
      return true;
    } on Exception {
      return false;
    }
  }

  static Map<int, BookLength> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      final novels = decoded is Map ? decoded['novels'] : null;
      if (novels is! List) return {};
      return {
        for (final n in novels)
          if (n is Map && n['novel'] is num)
            (n['novel'] as num).toInt(): BookLength(
              words: (n['words'] as num?)?.toInt() ?? 0,
              estimated: n['estimated'] == true,
              finished: n['finished'] == true,
            ),
      };
    } on FormatException {
      return {};
    }
  }
}

/// A reading pace to use before the phone has measured one, or when the
/// measured one can't be right.
const fallbackWordsPerMinute = 250;

/// Paces worth believing. The reading ledger has logged time with no words
/// on some days, which put the measured pace near 26 words a minute and
/// every length in hours about ten times too long.
bool plausiblePace(int wordsPerMinute) =>
    wordsPerMinute >= 100 && wordsPerMinute <= 800;

/// "about 12 h", "about 40 min", or null when the length isn't known.
String? hoursToRead(BookLength? length, int wordsPerMinute) {
  if (length == null || length.words <= 0) return null;
  final pace = plausiblePace(wordsPerMinute)
      ? wordsPerMinute
      : fallbackWordsPerMinute;
  final minutes = length.words / pace;
  if (minutes < 55) return 'about ${(minutes / 5).ceil() * 5} min';
  final hours = minutes / 60;
  return hours < 10
      ? 'about ${hours.toStringAsFixed(hours < 2 ? 1 : 0)} h'
      : 'about ${hours.round()} h';
}

/// "A finished story · about 9 h", for a book not yet started.
String? lengthLine(BookLength? length, int wordsPerMinute) {
  if (length == null) return null;
  final hours = hoursToRead(length, wordsPerMinute);
  final kind = length.finished ? 'A finished story' : 'Still being written';
  return hours == null ? kind : '$kind · $hours';
}
