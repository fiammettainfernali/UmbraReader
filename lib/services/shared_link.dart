import 'browser_policy.dart';
import 'site_patterns.dart';

/// What kind of thing another app shared with this one.
enum SharedKind {
  /// A novel's page, or a chapter of one, on a site the computer can get from.
  novel,

  /// Somewhere else on one of those sites: a list, or the front page.
  otherPage,

  /// A site the computer doesn't know.
  unsupportedSite,

  /// The share had no web address in it.
  noLink,
}

class SharedLink {
  const SharedLink({required this.kind, required this.label, this.url});

  final SharedKind kind;

  /// What to send, tidied up. Null when the share had no link.
  final String? url;

  /// What to call it on screen.
  final String label;
}

final _webAddress = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);

/// Punctuation that's part of the sentence around an address, not the address.
final _trailing = RegExp(r'[.,;:!?)\]}]+$');

/// Works out what was shared. Apps rarely send a bare address: browsers send it
/// alone, but others wrap it in a sentence like "Read this on NovelFull: …", and
/// some put the page's title in the subject.
SharedLink readSharedText(String? text, String? subject) {
  final body = (text ?? '').trim();
  final match = _webAddress.firstMatch(body);
  final found = match?.group(0)?.replaceFirst(_trailing, '');
  final url = found == null ? null : Uri.tryParse(found);
  if (url == null || url.host.isEmpty) {
    return const SharedLink(kind: SharedKind.noLink, label: '');
  }

  final words = body.replaceRange(match!.start, match.end, '').trim();
  final title = (subject ?? '').trim();
  final label = title.isNotEmpty
      ? title
      : words.length > 1
      ? words.replaceFirst(RegExp(r'[\s:\-–—|]+$'), '')
      : shortAddress(url);

  final novel = novelPageFor(url);
  if (novel != null) {
    return SharedLink(
      kind: SharedKind.novel,
      url: bareAddress(novel),
      label: label,
    );
  }
  return SharedLink(
    kind: siteFor(url) == null
        ? SharedKind.unsupportedSite
        : SharedKind.otherPage,
    url: url.toString(),
    label: label,
  );
}
