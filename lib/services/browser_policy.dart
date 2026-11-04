import 'site_patterns.dart';
import 'web_view_guard.dart';

/// What to do about a page trying to take over the whole tab.
enum NavVerdict {
  allow,

  /// Not a web address: `intent://` to reach the Play Store, `tel:` and so on.
  /// Nothing a browser tab here should act on, with or without the ad blocker.
  refuse,

  /// A jump to another site that nobody asked for. That's what an ad redirect
  /// looks like, but so is the odd real link, so it's offered instead of lost.
  askFirst,
}

/// Search engines' own pages exist to send people to other sites.
const _searchHosts = {
  'duckduckgo.com',
  'www.duckduckgo.com',
  'html.duckduckgo.com',
};

/// Judges a main-frame navigation. Page parts like images and frames never come
/// through here, so being strict costs a page nothing it needs to draw.
///
/// [userAsked] covers the moments just after someone typed an address or tapped
/// something in the app, including any redirects that load goes through.
NavVerdict judgeNavigation({
  required Uri? from,
  required Uri to,
  required bool blocking,
  required bool userAsked,
}) {
  if (to.scheme != 'http' && to.scheme != 'https') {
    return to.scheme == 'about' ? NavVerdict.allow : NavVerdict.refuse;
  }
  if (!blocking || userAsked || from == null) return NavVerdict.allow;
  if (from.scheme != 'http' && from.scheme != 'https') return NavVerdict.allow;
  if (sameSite(from, to)) return NavVerdict.allow;
  if (_searchHosts.contains(from.host.toLowerCase())) return NavVerdict.allow;
  // AllNovelFull redirects to Novgo, and neither is an ad.
  if (siteFor(from) != null && siteFor(to) != null) return NavVerdict.allow;
  return NavVerdict.askFirst;
}

/// Turns what was typed into the address bar into somewhere to go: an address
/// if it looks like one, otherwise a search. Null when nothing was typed.
Uri? addressFromInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final hasScheme = text.startsWith('http://') || text.startsWith('https://');
  if (hasScheme) return Uri.tryParse(text);
  final looksLikeHost =
      !text.contains(' ') &&
      RegExp(r'^[^/]+\.[a-zA-Z]{2,}(/.*)?$').hasMatch(text);
  if (looksLikeHost) return Uri.tryParse('https://$text');
  return Uri.https('duckduckgo.com', '/', {'q': text});
}

/// Shows an address the way people read it.
String displayHost(Uri url) {
  final host = url.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// A page's address for the address bar: the site and where on it, without what
/// every address starts with.
String shortAddress(Uri url) {
  final path = url.path == '/' ? '' : url.path;
  final query = url.hasQuery ? '?${url.query}' : '';
  return '${displayHost(url)}$path$query';
}
