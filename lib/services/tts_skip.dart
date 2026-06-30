/// Categories of content the read-aloud voice can skip over (Speechify-style).
///
/// Block-level kinds ([headings]) are dropped whole when building the spoken
/// chunks; inline kinds are redacted *in place* — replaced with equal-length
/// runs of spaces so the voice stays silent over them while the character
/// offsets (and therefore the on-screen highlight) stay perfectly aligned.
enum TtsSkip {
  headings,
  parentheses,
  brackets,
  braces,
  urls,
  citations,
  footnotes,
}

extension TtsSkipMeta on TtsSkip {
  String get label => switch (this) {
        TtsSkip.headings => 'Headings',
        TtsSkip.parentheses => 'Parentheses ( )',
        TtsSkip.brackets => 'Square brackets [ ]',
        TtsSkip.braces => 'Curly braces { }',
        TtsSkip.urls => 'Links / URLs',
        TtsSkip.citations => 'Citations',
        TtsSkip.footnotes => 'Footnote markers',
      };

  String get description => switch (this) {
        TtsSkip.headings => 'Chapter and section titles',
        TtsSkip.parentheses => 'Anything inside ( … )',
        TtsSkip.brackets => 'Anything inside [ … ]',
        TtsSkip.braces => 'Anything inside { … }',
        TtsSkip.urls => 'Web addresses like https://…',
        TtsSkip.citations => 'Refs like [12] or (Smith, 2020)',
        TtsSkip.footnotes => 'Reference numbers in the text',
      };
}

/// Parses a stored comma-separated list of skip names.
Set<TtsSkip> parseTtsSkips(String? stored) {
  if (stored == null || stored.isEmpty) return const {};
  final names = stored.split(',').map((s) => s.trim()).toSet();
  return TtsSkip.values.where((k) => names.contains(k.name)).toSet();
}

/// Serialises skip options to a comma-separated list of names.
String encodeTtsSkips(Set<TtsSkip> skips) =>
    skips.map((k) => k.name).join(',');

/// Replaces each skipped inline span in [text] with the same number of spaces,
/// so the voice goes silent over it without shifting any later character
/// offsets. Block-level skips (e.g. [TtsSkip.headings]) are handled by the
/// caller when assembling chunks, not here.
String redactForSpeech(String text, Set<TtsSkip> skips) {
  if (skips.isEmpty || text.isEmpty) return text;
  var t = text;
  void blank(RegExp re) {
    t = t.replaceAllMapped(re, (m) => ' ' * m.group(0)!.length);
  }

  // URLs first, before bracket/paren stripping might bisect them.
  if (skips.contains(TtsSkip.urls)) {
    blank(RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false));
  }
  if (skips.contains(TtsSkip.citations)) {
    blank(RegExp(r'\[\d+(?:\s*[,&–-]\s*\d+)*\]')); // [12], [3, 4]
    blank(RegExp(r'\([^)]*\b\d{4}\b[^)]*\)')); // (Smith, 2020)
  }
  if (skips.contains(TtsSkip.footnotes)) {
    blank(RegExp(r'\[\d+\]')); // [1]
    blank(RegExp(r'(?<=[A-Za-z.,;:!?”")])\d{1,3}\b')); // word13
  }
  if (skips.contains(TtsSkip.parentheses)) blank(RegExp(r'\([^)]*\)'));
  if (skips.contains(TtsSkip.brackets)) blank(RegExp(r'\[[^\]]*\]'));
  if (skips.contains(TtsSkip.braces)) blank(RegExp(r'\{[^}]*\}'));
  return t;
}
