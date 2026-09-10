// Reading a followed web series' page the cheap way.
//
// A comic read on its own site needs three things from that site and none
// of them are the comic: a cover, a title, and whether there is a new
// chapter. All three sit in the series page's own HTML, and measured
// against vortexscans.org a plain client gets that page with HTTP 200 and
// no challenge at all -- no impersonation, no headless browser, nothing.
// So this is an ordinary GET, and the WebView is left to do the one job it
// is actually needed for, which is showing you the pages.
//
// Nothing here is site-specific. It reads the OpenGraph tags every one of
// these sites emits for link previews, and finds chapters by looking for
// links that live *under* the series' own URL. A site that breaks both of
// those conventions returns null and the follow still works -- you just
// keep the title you already had.

import 'package:http/http.dart' as http;

/// What a series page says about itself.
class WebSeriesInfo {
  const WebSeriesInfo({
    this.title,
    this.coverUrl,
    this.latestChapterUrl,
    this.latestChapterNumber,
  });

  final String? title;
  final String? coverUrl;

  /// The highest-numbered chapter linked from the series page.
  final String? latestChapterUrl;

  /// That chapter's number. The comparison that answers "is there a new
  /// one" — a count of the links would not, because these pages list only
  /// the newest handful.
  final double? latestChapterNumber;

  bool get isEmpty =>
      title == null && coverUrl == null && latestChapterNumber == null;
}

/// Fetches and reads series pages.
class WebSeriesMetadata {
  WebSeriesMetadata({http.Client? client, this.timeout = kTimeout})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// Short on purpose. This runs on the library's refresh pass, and a
  /// followed site that has gone away must not be able to hold the shelf
  /// up — the same rule the OPDS refresher had to learn.
  static const Duration kTimeout = Duration(seconds: 8);

  /// A phone browser's. Sent because these pages vary what they render by
  /// device, not to disguise anything: the fetch is not being challenged.
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like '
      'Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  /// Reads [seriesUrl]. Null when the page cannot be fetched at all;
  /// otherwise whatever of the three could be found.
  Future<WebSeriesInfo?> fetch(Uri seriesUrl) async {
    final String body;
    try {
      final res = await _client
          .get(seriesUrl, headers: const {'User-Agent': userAgent})
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      body = res.body;
    } on Exception {
      return null;
    }
    return read(body, seriesUrl);
  }

  /// The parsing half, split out so it can be tested against saved HTML
  /// without a network in the room.
  static WebSeriesInfo read(String body, Uri seriesUrl) {
    final chapters = _chaptersUnder(body, seriesUrl);
    double? bestNumber;
    Uri? bestUrl;
    for (final entry in chapters.entries) {
      if (bestNumber == null || entry.value > bestNumber) {
        bestNumber = entry.value;
        bestUrl = entry.key;
      }
    }
    return WebSeriesInfo(
      title: _meta(body, 'og:title') ?? _titleTag(body),
      coverUrl: _cover(body, seriesUrl) ?? _meta(body, 'og:image'),
      latestChapterUrl: bestUrl?.toString(),
      latestChapterNumber: bestNumber,
    );
  }

  /// The series' own cover art, when the page labels one.
  ///
  /// Tried before `og:image`, because `og:image` is often not a cover at
  /// all. The site this was built against generates a link-preview card at
  /// `/api/og-image/...` — a wide banner with the description written
  /// across it — and on a portrait shelf card that renders as a dark
  /// letterbox with a strip of text where the artwork should be.
  ///
  /// The signal is the accessible one rather than a guess at layout: the
  /// cover is the image whose alt text says it is a cover ("Cover of
  /// Ranker's Return"). Sites that label their images get the right
  /// picture; sites that do not fall back to `og:image`, which is still
  /// better than an empty card.
  static String? _cover(String body, Uri seriesUrl) {
    for (final match in RegExp(
      r'<img[^>]*>',
      caseSensitive: false,
    ).allMatches(body)) {
      final tag = match.group(0)!;
      final alt = _attribute(tag, 'alt');
      if (alt == null || !alt.trimLeft().toLowerCase().startsWith('cover')) {
        continue;
      }
      final src = _attribute(tag, 'src');
      if (src == null || src.isEmpty) continue;
      final resolved = _resolve(src, seriesUrl);
      if (resolved != null) return resolved.toString();
    }
    return null;
  }

  /// One attribute of a tag, unescaped.
  ///
  /// The leading boundary matters: without it, asking for `src` also
  /// matches the `data-src` of a lazily loaded image, which is a different
  /// attribute holding a different URL.
  static String? _attribute(String tag, String name) {
    final match = RegExp(
      '(?:^|\\s)$name="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(tag);
    final value = match?.group(1);
    return value == null ? null : unescape(value);
  }

  // ── parsing ──────────────────────────────────────────────────────────

  /// An OpenGraph meta tag's content. Both attribute orders are accepted
  /// because both are emitted in the wild, sometimes on the same page.
  static String? _meta(String body, String property) {
    for (final pattern in [
      '<meta[^>]+(?:property|name)="$property"[^>]+content="([^"]*)"',
      '<meta[^>]+content="([^"]*)"[^>]+(?:property|name)="$property"',
    ]) {
      final m = RegExp(pattern, caseSensitive: false).firstMatch(body);
      final value = m?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return unescape(value);
    }
    return null;
  }

  static String? _titleTag(String body) {
    final m = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body);
    final value = m?.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : unescape(value);
  }

  /// Links that live under the series' own path, mapped to their chapter
  /// number.
  ///
  /// Scoping to the series path is what keeps this site-agnostic: the
  /// navigation, the footer and the "you might also like" rail are all full
  /// of links, and the chapters are the ones that belong to this series.
  static Map<Uri, double> _chaptersUnder(String body, Uri seriesUrl) {
    final prefix = seriesUrl.path.endsWith('/')
        ? seriesUrl.path
        : '${seriesUrl.path}/';
    final found = <Uri, double>{};
    for (final m in RegExp(
      r'href="([^"]+)"',
      caseSensitive: false,
    ).allMatches(body)) {
      final raw = m.group(1);
      if (raw == null || raw.isEmpty) continue;
      final url = _resolve(raw, seriesUrl);
      if (url == null) continue;
      if (url.host != seriesUrl.host) continue;
      if (!url.path.startsWith(prefix)) continue;
      final number = chapterNumber(url.path.substring(prefix.length));
      if (number != null) found[url] = number;
    }
    return found;
  }

  static Uri? _resolve(String href, Uri base) {
    try {
      return base.resolve(href);
    } on FormatException {
      return null;
    }
  }

  /// The series page for [url], which may already be one.
  ///
  /// Follow is nearly always tapped from inside a chapter — that is where
  /// you are when you decide you want to keep reading something — but the
  /// chapter is not the series, and following one would pin the shelf to
  /// whichever chapter you happened to be on. Dropping the chapter segment
  /// and everything after it is enough for every layout seen so far, and a
  /// URL with no chapter segment is returned untouched, so a series page
  /// followed directly still works.
  static Uri seriesPageFor(Uri url) {
    final segments = url.pathSegments;
    for (var i = 0; i < segments.length; i++) {
      if (chapterNumber(segments[i]) != null) {
        return _bare(url, segments.sublist(0, i));
      }
    }
    return _bare(url, segments);
  }

  /// [url] rebuilt with [segments] and nothing after the path.
  ///
  /// Built rather than [Uri.replace]d. `replace` reads a null argument as
  /// "leave this component alone", so asking it for a null query is asking
  /// it to keep the query that is already there — which would make
  /// `…/a-story?ref=home` and `…/a-story` two different series to follow.
  static Uri _bare(Uri url, List<String> segments) => Uri(
    scheme: url.scheme,
    userInfo: url.userInfo,
    host: url.host,
    port: url.hasPort ? url.port : null,
    pathSegments: segments,
  );

  /// The chapter number in a trailing path segment.
  ///
  /// These slugs are not uniform even within one series: the first chapter
  /// of the one this was built against is `chapter-1-8mi19zhy` and the
  /// latest is plain `chapter-260`, so a hash suffix has to be tolerated
  /// rather than assumed absent. Decimals are kept — half-chapters and
  /// side stories are numbered 12.5.
  static double? chapterNumber(String slug) {
    final m = RegExp(
      r'chapter[-_ ]?(\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(slug);
    final digits = m?.group(1);
    return digits == null ? null : double.tryParse(digits);
  }

  /// The handful of HTML entities that actually turn up in a title.
  /// `Ranker&#x27;s Return` is the real example that made this necessary.
  static String unescape(String value) {
    var out = value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&apos;', "'");
    out = out.replaceAllMapped(
      RegExp(r'&#(x[0-9a-f]+|\d+);', caseSensitive: false),
      (m) {
        final raw = m.group(1)!;
        final code = raw.toLowerCase().startsWith('x')
            ? int.tryParse(raw.substring(1), radix: 16)
            : int.tryParse(raw);
        return code == null ? m.group(0)! : String.fromCharCode(code);
      },
    );
    // Last, so an escaped ampersand cannot resurrect another entity.
    return out.replaceAll('&amp;', '&');
  }
}
