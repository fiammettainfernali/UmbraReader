// Keeping a followed comic's WebView on the site it was opened for.
//
// The pages themselves are not the hazard. Android renders them in a
// sandboxed process that cannot install anything, and a site can only ask
// for permissions the app itself holds -- Umbra declares INTERNET,
// ACCESS_NETWORK_STATE, two foreground-service flags and POST_NOTIFICATIONS,
// so there is no camera, microphone, location or storage for a page to ask
// after. A request for any of them is refused by Android before this code
// is consulted.
//
// What is left is advertising. A script on one of these sites will happily
// throw the top-level frame at a "your device is infected" page, a store
// listing, or a file download, and none of that is anything the reader
// asked for. So the reader stays on the site it was opened for, and
// anywhere else is refused.
//
// This gates *navigations* only, which is what makes it safe to be strict:
// the panels are subresources fetched by the page (on this site from a
// different host entirely, storage.vortexscans.org), and subresources never
// pass through here. Blocking every other site does not cost the comic a
// single image.

/// Whether [candidate] may be navigated to from a comic opened at [origin].
///
/// Deliberately conservative, in two ways.
///
/// Only `http` and `https` are allowed at all. The interesting schemes are
/// the ones a page uses to leave the app -- `intent://` and `market://` to
/// reach the Play Store, `tel:` to put a number in the dialler -- and a
/// comic has no reason to use any of them.
///
/// And "same site" is judged by the host rather than by a registrable
/// domain, because doing that properly needs a public-suffix list this app
/// has no other use for. A subdomain of the origin passes; a different
/// domain does not, even one owned by the same people. The failure mode is
/// a blocked link the reader can still reach in a real browser, which is
/// the right direction for this to fail in.
bool sameSite(Uri origin, Uri candidate) {
  if (candidate.scheme != 'http' && candidate.scheme != 'https') return false;
  final from = _base(origin.host);
  final to = _base(candidate.host);
  if (from.isEmpty || to.isEmpty) return false;
  return to == from || to.endsWith('.$from');
}

/// The host, with a leading `www.` removed.
///
/// Only `www`, and only at the front: sites routinely serve a series page
/// from one and its chapters from the other, and treating those as two
/// different sites would block a comic from its own pages. Every other
/// subdomain is left alone to be judged on its merits.
String _base(String host) {
  final lower = host.toLowerCase();
  return lower.startsWith('www.') ? lower.substring(4) : lower;
}
