/// Which webnovel sites Novel Grabber can scrape, and what their URLs look
/// like — ported from the browser extension's `sites.js`, which mirrors the
/// SUPPORTED_DOMAINS of the server's scrapers.
///
/// Used by the in-app browser to decide how to label the add button. The
/// heuristics only improve the hint: any URL is always *sendable*, and the
/// server is the authority on what it can actually scrape — a mismatch here
/// surfaces as the server's own error, not a client guess.
library;

/// One supported site.
class NovelSite {
  const NovelSite({
    required this.host,
    required this.name,
    required this.novelPath,
    this.chapterHint,
  });

  final String host;
  final String name;

  /// Matches the *path* of a novel's main page (as opposed to a chapter or
  /// listing page).
  final RegExp novelPath;

  /// Matches a chapter path whose first segment is the novel's slug, so the
  /// novel page can be offered from inside a chapter. Null when the site's
  /// chapter URLs don't carry the slug.
  final RegExp? chapterHint;
}

/// Mirrors the extension's NG_SITES table.
final List<NovelSite> kNovelSites = [
  for (final host in ['readnovelfull.com'])
    NovelSite(
      host: host,
      name: 'ReadNovelFull',
      novelPath: RegExp(r'^/[^/]+\.html$', caseSensitive: false),
      chapterHint: RegExp(r'^/([^/]+)/chapter-', caseSensitive: false),
    ),
  for (final host in ['novelfull.com'])
    NovelSite(
      host: host,
      name: 'NovelFull',
      novelPath: RegExp(r'^/[^/]+\.html$', caseSensitive: false),
      chapterHint: RegExp(r'^/([^/]+)/chapter-', caseSensitive: false),
    ),
  for (final host in ['allnovelfull.net', 'allnovelfull.com'])
    NovelSite(
      host: host,
      name: 'AllNovelFull',
      novelPath: RegExp(r'^/[^/]+\.html$', caseSensitive: false),
      chapterHint: RegExp(r'^/([^/]+)/chapter-', caseSensitive: false),
    ),
  for (final host in ['novgo.net'])
    NovelSite(
      host: host,
      name: 'Novgo',
      novelPath: RegExp(r'^/[^/]+\.html$', caseSensitive: false),
      chapterHint: RegExp(r'^/([^/]+)/chapter-', caseSensitive: false),
    ),
  for (final host in ['wattpad.com'])
    NovelSite(
      host: host,
      name: 'Wattpad',
      novelPath: RegExp(r'^/story/\d+', caseSensitive: false),
    ),
];

/// The site serving [url], or null when it's not one Novel Grabber scrapes.
/// Subdomains count: `www.novelfull.com` is still NovelFull.
NovelSite? siteFor(Uri url) {
  final host = url.host.toLowerCase();
  for (final site in kNovelSites) {
    if (host == site.host || host.endsWith('.${site.host}')) return site;
  }
  return null;
}

/// How the add button should read for [url].
enum PageKind {
  /// A novel's main page on a supported site — the ideal thing to send.
  novel,

  /// Somewhere else on a supported site (chapter, listing, front page).
  supportedSite,

  /// Not a site the server scrapes.
  unsupported,
}

PageKind classify(Uri url) {
  final site = siteFor(url);
  if (site == null) return PageKind.unsupported;
  return site.novelPath.hasMatch(url.path)
      ? PageKind.novel
      : PageKind.supportedSite;
}

/// For a chapter URL whose path carries the novel's slug, the URL of the
/// novel's main page — so the button can offer the *right* thing from
/// inside a chapter. Null when it can't be derived safely.
Uri? novelPageFor(Uri url) {
  final site = siteFor(url);
  if (site == null) return null;
  if (site.novelPath.hasMatch(url.path)) return url;
  final hint = site.chapterHint?.firstMatch(url.path);
  if (hint == null) return null;
  // Built fresh rather than via url.replace: replace(query: '') keeps the
  // component as present-but-empty, yielding a trailing "?#".
  return Uri(
    scheme: url.scheme,
    host: url.host,
    port: url.hasPort ? url.port : null,
    path: '/${hint.group(1)}.html',
  );
}
