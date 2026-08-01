import '../models/series.dart';

/// Matching and ranking for the library grid's search box.
///
/// The old behaviour was `title.contains(query)` on the raw strings, which
/// fails in ways that matter for a library of long, similar, translated
/// titles: "hunter primal" found nothing, neither did "primalhunter", and a
/// single typo or accent killed the query outright. Nor was there any notion
/// of a better match — results came back in whatever order the sort happened
/// to impose, so an exact title match could sit below a series that merely
/// mentioned the word in its description.
///
/// Everything here is pure so the rules can be tested directly.

/// Normalises text for comparison: lower-cases, strips accents, and reduces
/// punctuation to spaces.
///
/// Reducing punctuation to spaces rather than deleting it is what lets
/// "Re:Zero" answer to "re zero". Matching it to "rezero" as well needs the
/// space-free comparison in [scoreSeries] — folding alone cannot do it.
String foldForSearch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final folded = _accents[char];
    if (folded != null) {
      buffer.write(folded);
    } else if (_isAlphanumeric(rune)) {
      buffer.write(char);
    } else {
      buffer.write(' ');
    }
  }
  return buffer.toString().trim();
}

bool _isAlphanumeric(int rune) {
  // Anything beyond Latin is kept as-is: CJK titles have no case or accents
  // to fold, and treating them as punctuation would erase them entirely.
  if (rune > 0x7F) return true;
  return (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7A);
}

const _accents = <String, String>{
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ß': 'ss',
  'œ': 'oe',
  'æ': 'ae',
};

/// Splits a folded query into the terms that must all be present.
///
/// Every term has to match somewhere, so extra words narrow rather than
/// widen — which is how people actually refine a search. Because terms are
/// matched independently, word order stops mattering.
List<String> searchTerms(String query) {
  final folded = foldForSearch(query);
  if (folded.isEmpty) return const [];
  return folded.split(' ').where((t) => t.isNotEmpty).toList();
}

/// Shortest term allowed to match mid-word rather than at a word boundary.
///
/// Below this, a loose match is almost always a coincidence — "two" sits
/// inside "network" and "between" — and those coincidences swamp the real
/// answer.
const int _minLooseTerm = 4;

/// Where a term was found, worst to best. The score of a series is the sum
/// of its best field per term, so a title hit always outranks a description
/// hit for the same query.
class _FieldWeight {
  static const description = 1;
  static const genre = 3;
  static const author = 6;
  static const titleWord = 10;
  static const titlePrefix = 14;
}

/// How well [series] answers [terms], or null when it doesn't.
///
/// Null rather than 0 so "matched nothing" can't be confused with "matched
/// everything weakly".
int? scoreSeries(Series series, List<String> terms) {
  if (terms.isEmpty) return 0;
  final title = foldForSearch(series.title);
  final author = foldForSearch(series.author);
  final genres = foldForSearch(series.genres.join(' '));
  final description = foldForSearch(series.description);

  // Folding turns "Re:Zero" into "re zero", which a reader typing "rezero"
  // would still never reach. Comparing against a space-free copy as well
  // closes that gap — people routinely drop the spaces a title has and add
  // ones it doesn't.
  final titleCompact = title.replaceAll(' ', '');

  var total = 0;
  // A description is the weakest possible evidence: "two" occurs in a large
  // share of blurbs ("two years later…") with no bearing on what the reader
  // is looking for. It can support a term once the series has been
  // established as relevant, but it can never make a series relevant on its
  // own — otherwise a common word returns most of the library.
  var qualified = false;

  for (final term in terms) {
    final int best;
    if (title.startsWith(term)) {
      best = _FieldWeight.titlePrefix;
      qualified = true;
    } else if (_containsWordStart(title, term)) {
      best = _FieldWeight.titleWord;
      qualified = true;
    } else if (term.length >= _minLooseTerm &&
        titleCompact.contains(term.replaceAll(' ', ''))) {
      // Mid-word matching is what reaches "rezero" and unspaced CJK, but on
      // a short term it is mostly accidents — "two" inside "network".
      best = _FieldWeight.titleWord - 3;
      qualified = true;
    } else if (_containsWordStart(author, term)) {
      best = _FieldWeight.author;
      qualified = true;
    } else if (_containsWordStart(genres, term)) {
      best = _FieldWeight.genre;
      qualified = true;
    } else if (_containsWordStart(description, term)) {
      best = _FieldWeight.description;
    } else {
      return null; // every term must land somewhere
    }
    total += best;
  }
  if (!qualified) return null;
  // A short title carrying the same terms is the more precise answer:
  // "Shadow Slave" should beat "The Shadow Slave Chronicles of Something".
  return total * 1000 - title.length.clamp(0, 999);
}

/// True when [term] begins a word in [haystack] — "hunter" matches
/// "primal hunter" more strongly than it matches "gunhunterly".
bool _containsWordStart(String haystack, String term) {
  var from = 0;
  while (true) {
    final i = haystack.indexOf(term, from);
    if (i < 0) return false;
    if (i == 0 || haystack.codeUnitAt(i - 1) == 0x20) return true;
    from = i + 1;
  }
}

/// The series matching [query], best first.
///
/// Ranking deliberately replaces the user's sort while a query is active:
/// having asked a question, the best answer belongs at the top, not whatever
/// answer happens to sort first alphabetically. The sort returns the moment
/// the query is cleared.
List<Series> rankedSearch(List<Series> series, String query) {
  final terms = searchTerms(query);
  if (terms.isEmpty) return List<Series>.of(series);
  final scored = <(int, Series)>[];
  for (final s in series) {
    final score = scoreSeries(s, terms);
    if (score != null) scored.add((score, s));
  }
  scored.sort((a, b) {
    final byScore = b.$1.compareTo(a.$1);
    return byScore != 0
        ? byScore
        : a.$2.title.toLowerCase().compareTo(b.$2.title.toLowerCase());
  });
  return [for (final (_, s) in scored) s];
}

/// One genre and how many series carry it.
typedef GenreFacet = ({String name, int count});

/// Every genre in [series], most-used first.
///
/// Frequency order rather than alphabetical is the difference between a
/// usable filter and a wall: in a real library the tag list is dominated by
/// one-offs — hundreds of genres carried by a single series each — and
/// sorting A–Z buries the handful of tags that describe most of the library
/// somewhere in the middle of them.
List<GenreFacet> genreFacets(List<Series> series) {
  final counts = <String, int>{};
  for (final s in series) {
    for (final raw in s.genres) {
      final genre = raw.trim();
      if (genre.isEmpty) continue;
      counts[genre] = (counts[genre] ?? 0) + 1;
    }
  }
  final out = [for (final e in counts.entries) (name: e.key, count: e.value)];
  out.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0
        ? byCount
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

/// [facets] narrowed to those matching [query], with [selected] kept
/// regardless so an active filter can never scroll out of existence.
List<GenreFacet> filterFacets(
  List<GenreFacet> facets,
  String query,
  Set<String> selected,
) {
  final terms = searchTerms(query);
  final matches = <GenreFacet>[];
  final pinned = <GenreFacet>[];
  for (final facet in facets) {
    if (selected.contains(facet.name)) {
      pinned.add(facet);
      continue;
    }
    if (terms.isEmpty) {
      matches.add(facet);
      continue;
    }
    final folded = foldForSearch(facet.name);
    if (terms.every(folded.contains)) matches.add(facet);
  }
  return [...pinned, ...matches];
}
