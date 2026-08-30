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

  String? _lastFailure;

  /// Why the last fetch failed, or null when none has.
  ///
  /// Only set for failures that are *not* a plain 404: a missing entry is an
  /// ordinary answer about the book, while everything else is an answer
  /// about the connection.
  @override
  String? get lastFailure => _lastFailure;

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

  /// Statuses worth asking again for.
  ///
  /// These come from the reverse proxy in front of the library, not from the
  /// library: they mean the request was never delivered. One was seen doing
  /// exactly that — a book refused to open with a 502 while the server sat
  /// idle and listening, having never been asked, and the same book opened
  /// twelve minutes later without a change to anything.
  ///
  /// A 404 is not here: that is the library answering, and answering the
  /// same way however many times it is asked. Nor is 401 — a password does
  /// not become right on the second try.
  static const _worthRetrying = {502, 503, 504};

  /// How long to wait before each retry.
  ///
  /// Short, and only twice. This runs while someone is looking at a spinner
  /// waiting for a page, so the budget is a moment's hesitation rather than
  /// a genuine backoff schedule.
  static const _retryDelays = [
    Duration(milliseconds: 250),
    Duration(milliseconds: 750),
  ];

  Future<void> _fetchInto(String path) async {
    for (var attempt = 0; ; attempt++) {
      final again = await _attemptFetch(path);
      if (!again || attempt >= _retryDelays.length) return;
      await Future<void>.delayed(_retryDelays[attempt]);
    }
  }

  /// One try. Returns true when it is worth another.
  Future<bool> _attemptFetch(String path) async {
    try {
      final res = await _client
          .get(_uriFor(path), headers: headers)
          .timeout(timeout);
      if (res.statusCode == 200) {
        _cache[path] = res.bodyBytes;
        _lastFailure = null;
        return false;
      }
      if (res.statusCode == 404) {
        _absent.add(path);
        return false;
      }
      // Anything else — 401, 500, a proxy error — is left uncached and
      // untracked, so a later attempt can still succeed. Treating a
      // transient failure as "not in this book" would make a dropped
      // connection look like a corrupt one.
      //
      // Kept as a reason, though. Without it the parser sees only absent
      // bytes and says the book is not a valid EPUB, which sends the reader
      // hunting a fault in a file that was never opened.
      _lastFailure = switch (res.statusCode) {
        401 || 403 => 'The server refused the request (HTTP '
            '${res.statusCode}) — check the username and password.',
        502 || 503 || 504 => 'The server could not be reached through its '
            'proxy (HTTP ${res.statusCode}). It may be starting up.',
        _ => 'The server answered HTTP ${res.statusCode}.',
      };
      return _worthRetrying.contains(res.statusCode);
    } on Exception catch (e) {
      // Same reasoning: no cache entry, no absence record, try again later.
      final timedOut = e.toString().contains('TimeoutException');
      _lastFailure = timedOut
          ? 'The server did not answer in time.'
          : 'Could not reach the server. ($e)';
      // A connection that never opened is the same kind of nothing as a 502,
      // and just as likely to work a moment later. A timeout is not: it
      // already waited, and waiting again doubles the spinner.
      return !timedOut;
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
