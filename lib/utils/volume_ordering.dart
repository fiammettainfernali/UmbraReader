import '../models/volume.dart';

/// Extracts a sortable volume number from a volume — the last run of digits
/// in its title (or filename), e.g. "… Volume 03" → 3. Returns null when
/// there's no number to key on (single-volume / oddly-named series).
int? volumeNumber(Volume v) {
  for (final source in [v.title, v.fileName]) {
    final matches = RegExp(r'\d+').allMatches(source).toList();
    if (matches.isNotEmpty) {
      final n = int.tryParse(matches.last.group(0)!);
      if (n != null) return n;
    }
  }
  return null;
}

/// Volumes sorted into ascending reading order — by volume number, falling
/// back to compile time then title.
///
/// OPDS feeds usually arrive newest-first, so relying on raw feed order sent
/// the reader's "next volume" prompt backwards into older volumes (or off the
/// end of the latest one). Sorting here makes "the one after the current"
/// mean the same thing everywhere.
List<Volume> volumesInReadingOrder(List<Volume> volumes) {
  final ordered = [...volumes];
  ordered.sort((a, b) {
    final an = volumeNumber(a);
    final bn = volumeNumber(b);
    if (an != null && bn != null && an != bn) return an.compareTo(bn);
    final at = a.updatedAt;
    final bt = b.updatedAt;
    if (at != null && bt != null && at != bt) return at.compareTo(bt);
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return ordered;
}
