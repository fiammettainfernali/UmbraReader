import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'opds_client.dart';
import 'settings_service.dart';

/// Raised when the control API can't be reached or returns an error.
class ControlException implements Exception {
  ControlException(this.message, {this.isUnreachable = false});

  final String message;

  /// True when the server could not be reached at all — offline, asleep,
  /// off the network — as opposed to reached and refusing.
  ///
  /// The difference decides whether an action is worth keeping for later:
  /// a request that never arrived can be retried unchanged, while a 400 is
  /// an answer, and retrying it would only produce the same answer.
  final bool isUnreachable;

  @override
  String toString() => message;
}

/// One item in Novel Grabber's download/update queue.
class QueueEntry {
  const QueueEntry({
    required this.novelId,
    required this.title,
    required this.action,
    this.chapterRange,
    this.uid,
  });

  final int novelId;
  final String title;

  /// "download" or "update".
  final String action;

  /// Inclusive (start, end) chapter range for a partial download, or null.
  final List<int>? chapterRange;

  /// This entry's stable identity on the server, used to reorder or remove
  /// it. Null against a Novel Grabber build older than the one that added
  /// it, in which case the caller has to fall back to a position.
  final int? uid;

  factory QueueEntry.fromJson(Map<String, dynamic> json) => QueueEntry(
    novelId: (json['novelId'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    action: json['action'] as String? ?? 'download',
    chapterRange: (json['chapterRange'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList(),
    uid: (json['uid'] as num?)?.toInt(),
  );
}

/// A novel already in the library that looks like one being added.
class DuplicateMatch {
  const DuplicateMatch({
    required this.novelId,
    required this.title,
    required this.sourceSite,
    required this.sourceUrl,
    required this.totalChapters,
    required this.similarity,
  });

  final int novelId;
  final String title;
  final String sourceSite;
  final String sourceUrl;
  final int totalChapters;

  /// 1.0 when the titles match exactly after normalisation.
  final double similarity;

  factory DuplicateMatch.fromJson(Map<String, dynamic> j) => DuplicateMatch(
    novelId: (j['novelId'] as num?)?.toInt() ?? 0,
    title: j['title'] as String? ?? '',
    sourceSite: j['sourceSite'] as String? ?? '',
    sourceUrl: j['sourceUrl'] as String? ?? '',
    totalChapters: (j['totalChapters'] as num?)?.toInt() ?? 0,
    similarity: (j['similarity'] as num?)?.toDouble() ?? 0,
  );
}

/// Thrown when the server refuses an add because it already has the novel.
///
/// Distinct from a plain [ControlException] so the caller can offer "add
/// anyway" rather than just reporting a failure — this is a question, not
/// an error.
class DuplicateNovelException extends ControlException {
  DuplicateNovelException(super.message, this.matches, this.reason);

  final List<DuplicateMatch> matches;

  /// "url" when the exact page is already known, "title" when a different
  /// source carries what looks like the same story.
  final String reason;

  bool get isSameUrl => reason == 'url';
}

/// Whether a URL is already in the library.
class NovelLookup {
  const NovelLookup({required this.known, this.novel});

  final bool known;
  final DuplicateMatch? novel;

  factory NovelLookup.fromJson(Map<String, dynamic> j) => NovelLookup(
    known: j['known'] == true,
    novel: j['novel'] is Map<String, dynamic>
        ? DuplicateMatch.fromJson(j['novel'] as Map<String, dynamic>)
        : null,
  );
}

/// How a single novel is doing on the server.
class NovelHealth {
  const NovelHealth({
    required this.novelId,
    required this.title,
    required this.total,
    required this.done,
    required this.pending,
    required this.errored,
    required this.lastError,
  });

  final int novelId;
  final String title;
  final int total;
  final int done;
  final int pending;
  final int errored;

  /// Why the most recent failure failed. Empty when nothing has.
  final String lastError;

  bool get hasFailures => errored > 0;

  factory NovelHealth.fromJson(Map<String, dynamic> j) => NovelHealth(
    novelId: (j['novelId'] as num?)?.toInt() ?? 0,
    title: j['title'] as String? ?? '',
    total: (j['total'] as num?)?.toInt() ?? 0,
    done: (j['done'] as num?)?.toInt() ?? 0,
    pending: (j['pending'] as num?)?.toInt() ?? 0,
    errored: (j['errored'] as num?)?.toInt() ?? 0,
    lastError: j['lastError'] as String? ?? '',
  );
}

/// Snapshot of Novel Grabber's job state.
class ControlStatus {
  const ControlStatus({
    required this.active,
    required this.paused,
    required this.current,
    required this.queue,
    required this.sources,
    required this.searchSites,
  });

  final bool active;
  final bool paused;
  final QueueEntry? current;
  final List<QueueEntry> queue;
  final List<String> sources;

  /// Scraper SITE_NAMEs that support keyword search (the search source picker).
  final List<String> searchSites;

  factory ControlStatus.fromJson(Map<String, dynamic> json) => ControlStatus(
    active: json['active'] == true,
    paused: json['paused'] == true,
    current: json['current'] is Map<String, dynamic>
        ? QueueEntry.fromJson(json['current'] as Map<String, dynamic>)
        : null,
    queue: [
      for (final e in (json['queue'] as List? ?? const []))
        if (e is Map<String, dynamic>) QueueEntry.fromJson(e),
    ],
    sources: [
      for (final s in (json['sources'] as List? ?? const [])) s.toString(),
    ],
    searchSites: [
      for (final s in (json['searchSites'] as List? ?? const [])) s.toString(),
    ],
  );
}

/// Novel Grabber's recurring auto-update setting.
class AutoUpdateSchedule {
  const AutoUpdateSchedule({required this.mode, required this.intervalMinutes});

  /// "off", "interval", or "schedule" (specific times — read-only in the app).
  final String mode;
  final int intervalMinutes;

  factory AutoUpdateSchedule.fromJson(Map<String, dynamic> j) =>
      AutoUpdateSchedule(
        mode: j['mode'] as String? ?? 'off',
        intervalMinutes: (j['intervalMinutes'] as num?)?.toInt() ?? 60,
      );
}

/// One result from a site search.
class SearchHit {
  const SearchHit({
    required this.title,
    required this.author,
    required this.url,
    required this.coverUrl,
    required this.latestChapter,
    required this.site,
  });

  final String title;
  final String author;
  final String url;
  final String coverUrl;
  final String latestChapter;
  final String site;

  factory SearchHit.fromJson(Map<String, dynamic> j) => SearchHit(
    title: j['title'] as String? ?? '',
    author: j['author'] as String? ?? '',
    url: j['url'] as String? ?? '',
    coverUrl: j['coverUrl'] as String? ?? '',
    latestChapter: j['latestChapter'] as String? ?? '',
    site: j['site'] as String? ?? '',
  );
}

/// What the server is doing, as opposed to merely how far through it is.
///
/// These were previously carried as a bare string and never branched on,
/// so every state rendered as a download. That is actively misleading for
/// [checking], whose counts are *novels swept*, not chapters — "40 / 486"
/// during a sweep and during a download describe unrelated quantities.
enum JobState {
  downloading('Downloading', 'chapters'),
  checking('Checking for updates', 'series'),
  batchPause('Pausing between batches', 'chapters'),
  compiling('Building EPUB', 'chapters'),
  idle('Idle', ''),
  unknown('Working', '');

  const JobState(this.label, this.unit);

  /// How to describe this state in the activity card.
  final String label;

  /// What [ControlProgress.current] and `total` are counting, so the
  /// caption can say "40 of 486 series" rather than implying chapters.
  final String unit;

  bool get isIdle => this == JobState.idle;

  /// True while the server is deliberately waiting rather than stalled —
  /// the bar should stay put and say so, not look frozen.
  bool get isWaiting => this == JobState.batchPause;

  /// Compiling arrives pinned at 100%, so a determinate bar reads as
  /// finished when work is still happening.
  bool get isIndeterminate => this == JobState.compiling;

  static JobState fromName(String? raw) => switch (raw) {
    'downloading' => JobState.downloading,
    'checking' => JobState.checking,
    'batch_pause' => JobState.batchPause,
    'compiling' => JobState.compiling,
    'idle' || '' || null => JobState.idle,
    // An unrecognised state means the server is newer than the app. Say
    // something true and vague rather than guessing at a label.
    _ => JobState.unknown,
  };
}

/// A live progress tick from the SSE stream.
class ControlProgress {
  const ControlProgress({
    required this.novelTitle,
    required this.chapterTitle,
    required this.current,
    required this.total,
    required this.percent,
    required this.state,
    this.novelId,
    this.queueSize,
    this.keepBar = false,
  });

  final String novelTitle;
  final String chapterTitle;
  final int current;
  final int total;
  final double percent;
  final JobState state;

  /// The novel this tick is about, when it is about one. Null during a
  /// parallel run, where the payload describes several at once.
  final int? novelId;

  /// How many items were queued when this tick was sent — a live count
  /// that arrives with every event, rather than waiting for a poll.
  final int? queueSize;

  /// The server asking that the bar be left as it is: it is pausing on
  /// purpose, and a bar that vanished or reset would read as a fault.
  final bool keepBar;

  bool get isIdle => state.isIdle;

  factory ControlProgress.fromJson(Map<String, dynamic> d) => ControlProgress(
    novelTitle: d['novel_title'] as String? ?? '',
    chapterTitle: d['chapter_title'] as String? ?? '',
    current: (d['current'] as num?)?.toInt() ?? 0,
    total: (d['total'] as num?)?.toInt() ?? 0,
    percent: (d['percent'] as num?)?.toDouble() ?? 0,
    state: JobState.fromName(d['state'] as String?),
    novelId: (d['novel_id'] as num?)?.toInt(),
    queueSize: (d['queue_size'] as num?)?.toInt(),
    keepBar: d['keep_bar'] == true,
  );

  /// The caption under the bar, naming what is being counted.
  ///
  /// Without the unit this read "40 / 486 · 8%" whatever the numbers
  /// meant, which is how a sweep came to look like a download.
  String get countLabel {
    if (total <= 0) return state.label;
    final unit = state.unit.isEmpty ? '' : ' ${state.unit}';
    return '$current of $total$unit  ·  ${percent.round()}%';
  }
}

/// A decoded Server-Sent Event from `/api/events`.
class ControlEvent {
  const ControlEvent(this.type, this.raw);
  final String type; // progress, status, queue, snapshot
  final Map<String, dynamic> raw;

  ControlProgress? get progress =>
      type == 'progress' && raw['data'] is Map<String, dynamic>
      ? ControlProgress.fromJson(raw['data'] as Map<String, dynamic>)
      : null;

  String? get message => raw['message'] as String?;

  /// The same-story warning the server emits after scraping a page it was
  /// asked to add. Null on every other event type.
  ({String url, String title, String reason, List<DuplicateMatch> matches})?
  get duplicate {
    // Checked against the exact type rather than bare Map: `is Map` admits
    // a Map<dynamic, dynamic>, which the cast below would then throw on.
    if (type != 'duplicate' || raw['data'] is! Map<String, dynamic>) {
      return null;
    }
    final d = raw['data'] as Map<String, dynamic>;
    return (
      url: d['url'] as String? ?? '',
      title: d['title'] as String? ?? '',
      reason: d['reason'] as String? ?? 'title',
      matches: [
        for (final m in (d['matches'] as List? ?? const []))
          if (m is Map<String, dynamic>) DuplicateMatch.fromJson(m),
      ],
    );
  }
}

/// How long to wait before the nth reconnection attempt.
///
/// Doubling from a second, capped at half a minute. The cap matters more
/// than the curve: the server is usually a desktop that was asleep, being
/// rebuilt, or briefly off the network, and a client that backs off to
/// minutes would leave the screen wrong long after the server came back.
/// Deterministic rather than jittered — there is exactly one client here,
/// so there is no thundering herd to spread out.
Duration reconnectBackoff(int attempt) {
  if (attempt <= 1) return const Duration(seconds: 1);
  final seconds = 1 << (attempt - 1).clamp(0, 5);
  return Duration(seconds: seconds > 30 ? 30 : seconds);
}

/// Talks to Novel Grabber's `/api/*` control endpoints (the command channel
/// that complements the read-only OPDS feed). Same base URL + basic auth as
/// [OpdsClient]; only works when the server is reachable.
class ControlClient {
  ControlClient(this.settings);

  final OpdsSettings settings;

  Map<String, String> get _auth => OpdsClient(settings).authHeaders;

  /// Commands go to the downloader, which need not be the machine the books
  /// are read from. A hub stores and serves but refuses every fetching route
  /// — correctly, because a datacenter IP is what the source sites screen
  /// hardest — so pointing the library at one used to leave the remote
  /// control with nowhere to send a sweep. [OpdsSettings.controlUrl] falls
  /// back to the library address, which is the whole story for anyone whose
  /// one server does both.
  Uri _u(String path) => Uri.parse('${settings.controlUrl}$path');

  Future<ControlStatus> status() async {
    final json = await _get('/api/status');
    return ControlStatus.fromJson(json);
  }

  /// Queues a novel. Throws [DuplicateNovelException] when the server
  /// already has this exact URL; pass [force] to add it regardless.
  ///
  /// The same story under a *different* URL cannot be judged here — that
  /// needs the title, which needs a fetch — so the server reports it over
  /// the event stream once it has scraped the page.
  Future<void> addNovel(String url, {bool force = false}) =>
      _post('/api/novels', {'url': url, if (force) 'force': true});

  /// Whether [url] is already in the library. A plain database read on the
  /// server, so it is cheap enough to ask on every page browsed.
  Future<NovelLookup> lookup(String url) async {
    final json = await _get(
      '/api/novels/lookup?url=${Uri.encodeQueryComponent(url)}',
    );
    return NovelLookup.fromJson(json);
  }

  /// Searches a single source (by SITE_NAME) for novels matching [query].
  Future<List<SearchHit>> search(
    String query, {
    required String site,
    int page = 1,
  }) async {
    final q = Uri.encodeQueryComponent(query);
    final s = Uri.encodeQueryComponent(site);
    // Searching scrapes a live results page (sometimes through anti-bot
    // layers), which is far slower than a status read — give it room so the
    // server's own search timeout governs instead of cutting off early.
    final json = await _get(
      '/api/search?q=$q&site=$s&page=$page',
      timeout: const Duration(seconds: 45),
    );
    return [
      for (final r in (json['results'] as List? ?? const []))
        if (r is Map<String, dynamic>) SearchHit.fromJson(r),
    ];
  }

  Future<void> checkAllUpdates() => _post('/api/updates/check-all', null);

  /// Reads the auto-update schedule: {mode, intervalMinutes}.
  Future<AutoUpdateSchedule> schedule() async {
    final json = await _get('/api/schedule');
    return AutoUpdateSchedule.fromJson(json);
  }

  /// Sets the auto-update schedule. [intervalMinutes] applies when mode is
  /// "interval".
  Future<void> setSchedule(String mode, {int? intervalMinutes}) => _post(
    '/api/schedule',
    {'mode': mode, 'intervalMinutes': ?intervalMinutes},
  );

  /// How this novel is doing: chapter counts and the last failure.
  Future<NovelHealth> health(int novelId) async =>
      NovelHealth.fromJson(await _get('/api/novels/$novelId/health'));

  /// Puts failed chapters back in the queue. Additive — nothing already
  /// downloaded is touched. Returns how many were re-queued.
  Future<int> retryErrored(int novelId) async {
    final json = await _postJson('/api/novels/$novelId/retry-errored', null);
    return (json['requeued'] as num?)?.toInt() ?? 0;
  }

  /// Deletes every downloaded chapter and starts the novel again.
  ///
  /// [confirm] is passed through rather than defaulted: the server
  /// refuses without it, and that refusal is the point — this is minutes
  /// of work and a lot of requests for a large novel.
  Future<void> resetNovel(int novelId, {required bool confirm}) =>
      _post('/api/novels/$novelId/reset', {'confirm': confirm});

  Future<void> checkUpdates(int novelId) =>
      _post('/api/novels/$novelId/check-updates', null);

  Future<void> compile(int novelId) =>
      _post('/api/novels/$novelId/compile', null);

  Future<void> download(int novelId, {int? start, int? end}) => _post(
    '/api/novels/$novelId/download',
    start != null && end != null ? {'start': start, 'end': end} : null,
  );

  Future<void> pause() => _post('/api/queue/pause', null);
  Future<void> resume() => _post('/api/queue/resume', null);
  Future<void> stop() => _post('/api/queue/stop', null);
  Future<void> skip() => _post('/api/queue/skip', null);

  /// Reorders or removes one queue entry.
  ///
  /// These address the entry by [QueueEntry.uid] wherever the server offers
  /// one. A position is not a safe handle from here: the server pops the
  /// queue from the front while the app is showing a snapshot of it, so an
  /// index read a moment ago can already belong to a different novel. The
  /// index forms remain only as a fallback for an older server.
  Future<void> moveToTop(QueueEntry entry, {required int index}) =>
      entry.uid != null
      ? _post('/api/queue/move', {'uid': entry.uid, 'to': 0})
      : _post('/api/queue/move', {'index': index, 'delta': -index});

  Future<void> nudge(QueueEntry entry, int delta, {required int index}) =>
      entry.uid != null
      ? _post('/api/queue/move', {'uid': entry.uid, 'delta': delta})
      : _post('/api/queue/move', {'index': index, 'delta': delta});

  Future<void> removeFromQueue(QueueEntry entry) => entry.uid != null
      ? _post('/api/queue/remove', {'uid': entry.uid})
      : _post('/api/queue/remove', {'novel_id': entry.novelId});

  // ── low-level ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
    String path, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final http.Response res;
    try {
      res = await http.get(_u(path), headers: _auth).timeout(timeout);
    } on TimeoutException {
      throw ControlException(
        'The server took too long to respond. The source site may be slow '
        'or blocking requests — try again, or pick a different source.',
        isUnreachable: true,
      );
    } on Exception catch (e) {
      throw ControlException(
        'Could not reach Novel Grabber.\n($e)',
        isUnreachable: true,
      );
    }
    if (res.statusCode == 503) {
      throw ControlException(
        'The server is reachable but its control API is off — update Novel '
        'Grabber to a build that includes it.',
      );
    }
    if (res.statusCode != 200) {
      // Surface the server's own error message when it sent one.
      try {
        final d = jsonDecode(res.body);
        if (d is Map && d['error'] is String) {
          throw ControlException(d['error'] as String);
        }
      } on FormatException {
        // fall through to the generic message
      }
      throw ControlException('Server returned HTTP ${res.statusCode}.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw ControlException('Unexpected response from the server.');
    }
    return decoded;
  }

  /// [_post] for the endpoints whose answer matters.
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic>? body,
  ) async {
    final http.Response res;
    try {
      res = await http
          .post(
            _u(path),
            headers: {..._auth, 'Content-Type': 'application/json'},
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      throw ControlException(
        'Could not reach Novel Grabber.\n($e)',
        isUnreachable: true,
      );
    }
    if (res.statusCode >= 400) {
      String detail = 'HTTP ${res.statusCode}';
      try {
        final d = jsonDecode(res.body);
        if (d is Map && d['error'] is String) detail = d['error'] as String;
      } on FormatException {
        // keep the status-code detail
      }
      throw ControlException(detail);
    }
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  Future<void> _post(String path, Map<String, dynamic>? body) async {
    final http.Response res;
    try {
      res = await http
          .post(
            _u(path),
            headers: {..._auth, 'Content-Type': 'application/json'},
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
    } on Exception catch (e) {
      throw ControlException(
        'Could not reach Novel Grabber.\n($e)',
        isUnreachable: true,
      );
    }
    if (res.statusCode == 503) {
      throw ControlException('The server\'s control API is unavailable.');
    }
    if (res.statusCode >= 400) {
      String detail = 'HTTP ${res.statusCode}';
      Map<String, dynamic>? decoded;
      try {
        final d = jsonDecode(res.body);
        if (d is Map<String, dynamic>) {
          decoded = d;
          if (d['error'] is String) detail = d['error'] as String;
        }
      } on FormatException {
        // keep the status-code detail
      }
      // 409 is the server saying "you already have this", which the caller
      // can act on rather than merely report.
      if (res.statusCode == 409 && decoded != null) {
        throw DuplicateNovelException(detail, [
          for (final m in (decoded['matches'] as List? ?? const []))
            if (m is Map<String, dynamic>) DuplicateMatch.fromJson(m),
        ], decoded['reason'] as String? ?? 'url');
      }
      throw ControlException(detail);
    }
  }

  /// A live stream of control events from `/api/events` (SSE). The underlying
  /// connection opens on listen and closes when the subscription is cancelled.
  Stream<ControlEvent> events() {
    final client = http.Client();
    StreamSubscription<String>? sub;
    late StreamController<ControlEvent> controller;
    var cancelled = false;
    var attempt = 0;
    Timer? retry;

    late final Future<void> Function() connect;

    // A dropped connection is the normal case, not an error: the desktop
    // sleeps, gets rebuilt, changes network. Previously any drop closed
    // the stream for good and the screen froze on its last frame with
    // nothing to say so. Reconnecting is the stream's job, so no consumer
    // has to reimplement it.
    void scheduleReconnect() {
      if (cancelled || controller.isClosed) return;
      retry?.cancel();
      attempt++;
      retry = Timer(reconnectBackoff(attempt), () {
        if (!cancelled) connect();
      });
    }

    connect = () async {
      if (cancelled) return;
      try {
        final req = http.Request('GET', _u('/api/events'));
        req.headers.addAll(_auth);
        final res = await client.send(req);
        if (res.statusCode != 200) {
          // Reachable but refusing — auth wrong, or a build without the
          // control API. Retrying is still right: both get fixed on the
          // server, and the screen shows the silence meanwhile.
          scheduleReconnect();
          return;
        }
        // Connected. The server primes a snapshot immediately, so state
        // catches up without the consumer asking.
        attempt = 0;
        sub = res.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                if (!line.startsWith('data:')) return; // ignore ": ping"
                final payload = line.substring(5).trim();
                if (payload.isEmpty) return;
                try {
                  final m = jsonDecode(payload);
                  if (m is Map<String, dynamic>) {
                    controller.add(ControlEvent(m['type'] as String? ?? '', m));
                  }
                } on FormatException {
                  // skip a malformed event
                }
              },
              onError: (_) => scheduleReconnect(),
              onDone: scheduleReconnect,
              cancelOnError: true,
            );
      } on Exception {
        scheduleReconnect();
      }
    };

    controller = StreamController<ControlEvent>(
      onListen: connect,
      onCancel: () async {
        cancelled = true;
        retry?.cancel();
        await sub?.cancel();
        client.close();
      },
    );
    return controller.stream;
  }
}
