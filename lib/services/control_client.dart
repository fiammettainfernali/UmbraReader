import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'opds_client.dart';
import 'settings_service.dart';

/// Raised when the control API can't be reached or returns an error.
class ControlException implements Exception {
  ControlException(this.message);
  final String message;
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
  });

  final int novelId;
  final String title;

  /// "download" or "update".
  final String action;

  /// Inclusive (start, end) chapter range for a partial download, or null.
  final List<int>? chapterRange;

  factory QueueEntry.fromJson(Map<String, dynamic> json) => QueueEntry(
    novelId: (json['novelId'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    action: json['action'] as String? ?? 'download',
    chapterRange: (json['chapterRange'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList(),
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

/// A live progress tick from the SSE stream.
class ControlProgress {
  const ControlProgress({
    required this.novelTitle,
    required this.chapterTitle,
    required this.current,
    required this.total,
    required this.percent,
    required this.state,
  });

  final String novelTitle;
  final String chapterTitle;
  final int current;
  final int total;
  final double percent;
  final String state; // downloading, idle, paused, compiling, batch_pause…

  bool get isIdle => state == 'idle' || state.isEmpty;

  factory ControlProgress.fromJson(Map<String, dynamic> d) => ControlProgress(
    novelTitle: d['novel_title'] as String? ?? '',
    chapterTitle: d['chapter_title'] as String? ?? '',
    current: (d['current'] as num?)?.toInt() ?? 0,
    total: (d['total'] as num?)?.toInt() ?? 0,
    percent: (d['percent'] as num?)?.toDouble() ?? 0,
    state: d['state'] as String? ?? '',
  );
}

/// A decoded Server-Sent Event from `/api/events`.
class ControlEvent {
  const ControlEvent(this.type, this.raw);
  final String type; // progress, status, queue, snapshot
  final Map<String, dynamic> raw;

  ControlProgress? get progress => type == 'progress' && raw['data'] is Map
      ? ControlProgress.fromJson(raw['data'] as Map<String, dynamic>)
      : null;

  String? get message => raw['message'] as String?;
}

/// Talks to Novel Grabber's `/api/*` control endpoints (the command channel
/// that complements the read-only OPDS feed). Same base URL + basic auth as
/// [OpdsClient]; only works when the server is reachable.
class ControlClient {
  ControlClient(this.settings);

  final OpdsSettings settings;

  Map<String, String> get _auth => OpdsClient(settings).authHeaders;
  Uri _u(String path) => Uri.parse('${settings.baseUrl}$path');

  Future<ControlStatus> status() async {
    final json = await _get('/api/status');
    return ControlStatus.fromJson(json);
  }

  Future<void> addNovel(String url) =>
      _post('/api/novels', {'url': url});

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
    {
      'mode': mode,
      'intervalMinutes': ?intervalMinutes,
    },
  );

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
  Future<void> removeFromQueue(int novelId) =>
      _post('/api/queue/remove', {'novel_id': novelId});
  Future<void> move(int index, int delta) =>
      _post('/api/queue/move', {'index': index, 'delta': delta});

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
      );
    } on Exception catch (e) {
      throw ControlException('Could not reach Novel Grabber.\n($e)');
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
      throw ControlException('Could not reach Novel Grabber.\n($e)');
    }
    if (res.statusCode == 503) {
      throw ControlException('The server\'s control API is unavailable.');
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
  }

  /// A live stream of control events from `/api/events` (SSE). The underlying
  /// connection opens on listen and closes when the subscription is cancelled.
  Stream<ControlEvent> events() {
    final client = http.Client();
    StreamSubscription<String>? sub;
    late StreamController<ControlEvent> controller;

    Future<void> connect() async {
      try {
        final req = http.Request('GET', _u('/api/events'));
        req.headers.addAll(_auth);
        final res = await client.send(req);
        if (res.statusCode != 200) {
          controller.addError(
            ControlException('Event stream HTTP ${res.statusCode}'),
          );
          await controller.close();
          return;
        }
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
                    controller.add(
                      ControlEvent(m['type'] as String? ?? '', m),
                    );
                  }
                } on FormatException {
                  // skip a malformed event
                }
              },
              onError: controller.addError,
              onDone: controller.close,
              cancelOnError: false,
            );
      } on Exception catch (e) {
        controller.addError(ControlException('Event stream failed.\n($e)'));
        await controller.close();
      }
    }

    controller = StreamController<ControlEvent>(
      onListen: connect,
      onCancel: () async {
        await sub?.cancel();
        client.close();
      },
    );
    return controller.stream;
  }
}
