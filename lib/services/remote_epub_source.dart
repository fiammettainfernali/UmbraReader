import 'dart:convert';

import 'package:http/http.dart' as http;

import 'epub_source.dart';

/// An EPUB read from the hub, a file at a time, without downloading it.
///
/// The server exposes any member of a book at
/// `/epub/<id>/<file>?member=<path>`, which is the same shape the parser
/// already asks its local archive for. That is the whole trick: nothing in
/// parsing, rendering or pagination changes, because none of it knows
/// where the bytes came from.
///
/// [bytes] is synchronous and answers only from cache, because image bytes
/// are resolved in the middle of parsing. So anything a parse will need has
/// to be fetched first — see [warmUp] for opening a book and [prefetch] for
/// a chapter.
class RemoteEpubSource implements EpubSource {
  RemoteEpubSource({
    required this.baseUrl,
    required this.novelId,
    required this.fileName,
    this.headers = const {},
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// Server root, no trailing slash — e.g. `https://hub.example.ts.net`.
  final String baseUrl;

  /// The novel this book belongs to, as the catalogue numbers it.
  final int novelId;

  /// The `.epub` filename within that novel's EPUBs folder.
  final String fileName;

  /// Basic-auth headers, as `OpdsClient.authHeaders` builds them.
  final Map<String, String> headers;

  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  final Map<String, List<int>> _cache = {};

  /// Paths the server has already said it does not have.
  ///
  /// Remembered so a chapter referencing a missing image does not re-ask
  /// on every repagination — which happens on every rotation, fold and
  /// font change.
  final Set<String> _absent = {};

  /// Members fetched so far, for tests and for deciding what to evict.
  int get cachedCount => _cache.length;

  String _key(String path) => path.replaceAll('\\', '/');

  Uri _uriFor(String path) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse(
      '$root/epub/$novelId/${Uri.encodeComponent(fileName)}',
    ).replace(queryParameters: {'member': _key(path)});
  }

  @override
  List<int>? bytes(String path) => _cache[_key(path)];

  @override
  Future<void> prefetch(Iterable<String> paths) async {
    final wanted = <String>{
      for (final p in paths)
        if (p.isNotEmpty) _key(p),
    }..removeWhere((p) => _cache.containsKey(p) || _absent.contains(p));
    if (wanted.isEmpty) return;
    // Concurrently: a chapter with a dozen images should cost one round
    // trip's worth of waiting, not a dozen.
    await Future.wait(wanted.map(_fetchInto));
  }

  Future<void> _fetchInto(String path) async {
    try {
      final res = await _client
          .get(_uriFor(path), headers: headers)
          .timeout(timeout);
      if (res.statusCode == 200) {
        _cache[path] = res.bodyBytes;
      } else if (res.statusCode == 404) {
        _absent.add(path);
      }
      // Anything else — 401, 500, a proxy error — is left uncached and
      // untracked, so a later attempt can still succeed. Treating a
      // transient failure as "not in this book" would make a dropped
      // connection look like a corrupt one.
    } on Exception {
      // Same reasoning: no cache entry, no absence record, try again later.
    }
  }

  /// Fetches what opening a book needs, in the order it becomes knowable.
  ///
  /// The parser cannot be handed a list up front: the container names the
  /// OPF, and only the OPF names the table of contents. Three sequential
  /// round trips, once per book.
  Future<void> warmUp() async {
    const container = 'META-INF/container.xml';
    await prefetch([container]);
    final containerBytes = _cache[container];
    if (containerBytes == null) return;

    final opfPath = _firstMatch(
      utf8.decode(containerBytes, allowMalformed: true),
      RegExp(r'full-path\s*=\s*"([^"]+)"'),
    );
    if (opfPath == null) return;
    await prefetch([opfPath]);
    final opfBytes = _cache[_key(opfPath)];
    if (opfBytes == null) return;

    // The table of contents is either an EPUB 3 nav document or an EPUB 2
    // ncx. Read hrefs straight out of the manifest rather than parsing it
    // properly — the parser does that job a moment later, and this only
    // needs to know which files to have ready.
    final opf = utf8.decode(opfBytes, allowMalformed: true);
    final dir = _dirOf(opfPath);
    final wanted = <String>{};
    for (final m in RegExp(r'<item\b[^>]*>').allMatches(opf)) {
      final tag = m.group(0)!;
      final href = _firstMatch(tag, RegExp(r'href\s*=\s*"([^"]+)"'));
      if (href == null) continue;
      final isNav = tag.contains('properties="nav"') ||
          tag.contains("properties='nav'");
      if (isNav || href.toLowerCase().endsWith('.ncx')) {
        wanted.add(_join(dir, href));
      }
    }
    if (wanted.isNotEmpty) await prefetch(wanted);
  }

  static String? _firstMatch(String text, RegExp re) =>
      re.firstMatch(text)?.group(1);

  static String _dirOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String _join(String dir, String href) {
    final clean = href.split('#').first;
    return dir.isEmpty ? clean : '$dir/$clean';
  }

  @override
  void dispose() {
    _cache.clear();
    _absent.clear();
    if (_ownsClient) _client.close();
  }
}
