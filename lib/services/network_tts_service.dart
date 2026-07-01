import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'tts_engine.dart';

/// A synthesized clip: its local MP3 path plus optional word marks. Each mark
/// is `[charStart, charEnd, startSeconds]` within the chunk's text, letting the
/// reader highlight word-by-word as the clip plays.
class _Clip {
  const _Clip(this.path, this.marks);
  final String path;
  final List<List<num>> marks;
}

/// Read-aloud engine backed by a self-hosted Kokoro voice server.
///
/// Each paragraph chunk is synthesized to an MP3 by the server (`POST /tts`),
/// cached on disk, and played gaplessly via [AudioPlayer]. While one chunk
/// plays, the next couple are fetched ahead so playback rarely stalls.
///
/// The server returns per-word timing in an `X-Tts-Marks` header; as a clip
/// plays we watch the playback position and fire [onWord] for the current
/// word, so the reader highlight follows along word-by-word.
class NetworkTtsService implements TtsEngine {
  NetworkTtsService({String baseUrl = '', String token = ''})
      : _baseUrl = _normalize(baseUrl),
        _token = token;

  final AudioPlayer _player = AudioPlayer();

  String _baseUrl;
  String _token;

  List<String> _chunks = const [];
  int _index = 0;
  TtsPlaybackState _state = TtsPlaybackState.stopped;

  String _voice = 'af_heart';
  double _speed = 1.0;
  Map<String, String> _pron = const {};
  String _pronSig = '';

  /// Generation token: bumped on every [start]/[stop] so a stale playback loop
  /// or in-flight request from a previous run can detect it should bail out.
  int _gen = 0;

  bool _sessionReady = false;
  Completer<void>? _clipDone;
  StreamSubscription<ProcessingState>? _stateSub;
  Timer? _hlTimer;
  int _lastMarkFired = -1;
  int _pendingSeekChar = -1;
  Directory? _cacheDir;
  final Map<String, Future<_Clip?>> _inflight = {};

  @override
  void Function(TtsPlaybackState state)? onStateChanged;
  @override
  void Function(int chunkIndex, int charStart, int charEnd)? onWord;
  @override
  void Function()? onChapterFinished;

  @override
  TtsPlaybackState get state => _state;

  bool get isConfigured => _baseUrl.isNotEmpty;

  /// Updates the server location/token (e.g. after the user edits settings).
  void configure({required String baseUrl, required String token}) {
    _baseUrl = _normalize(baseUrl);
    _token = token;
  }

  /// Sets the term → sounds-like pronunciation overrides sent with each
  /// synthesis request. Part of the cache key, so changing them re-synthesizes.
  void setPronunciations(Map<String, String> pron) {
    _pron = pron;
    final keys = pron.keys.toList()..sort();
    _pronSig = keys.map((k) => '$k=${pron[k]}').join('|');
  }

  static String _normalize(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, String> get _authHeaders => {
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  /// Configures the iOS audio session for spoken-audio playback (playback
  /// category, A2DP for Bluetooth) so the voices don't route through the
  /// earpiece or the low-quality HFP codec and sound robotic.
  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      _sessionReady = true;
    } on Exception {
      // Best-effort; playback still works with the default session.
    }
  }

  void _ensureStateSub() {
    _stateSub ??= _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) {
        final c = _clipDone;
        if (c != null && !c.isCompleted) c.complete();
      }
    });
  }

  /// Lists the server's voices, or an empty list if unreachable.
  @override
  Future<List<TtsVoice>> availableVoices() async {
    if (!isConfigured) return const [];
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/voices'), headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = (data['voices'] as List?) ?? const [];
      final voices = raw
          .map((v) => TtsVoice(name: v.toString(), locale: TtsVoice.kokoroLocale))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return voices;
    } on Exception {
      return const [];
    } on Object {
      return const [];
    }
  }

  /// Quick health probe used by the settings screen to confirm reachability.
  Future<bool> ping() async {
    if (!isConfigured) return false;
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 12));
      return resp.statusCode == 200;
    } on Exception {
      return false;
    } on Object {
      return false;
    }
  }

  /// Synthesizes and plays a one-line sample of [voice] — used by the settings
  /// screen so a voice can be auditioned before it's chosen.
  Future<void> previewVoice(String voice, {double rate = 0.5}) async {
    if (!isConfigured || voice.isEmpty) return;
    await _ensureSession();
    _ensureStateSub();
    _voice = voice;
    _speed = _rateToSpeed(rate);
    const sample =
        'The candle flickered as she opened the old book and began to read.';
    final clip = await _resolveAudio(_cacheKey(_voice, _speed, sample), sample);
    if (clip == null) return;
    try {
      await _player.setFilePath(clip.path);
      await _player.play();
    } on Exception {
      // Preview is best-effort.
    }
  }

  @override
  Future<void> setVoice(String name, String locale) async {
    if (name.isNotEmpty) _voice = name;
  }

  @override
  Future<void> setRate(double rate) async {
    _speed = _rateToSpeed(rate);
  }

  // flutter_tts rate (0.5 ≈ normal) -> Kokoro speed (1.0 ≈ normal), up to 3×.
  double _rateToSpeed(double rate) => (rate * 2.0).clamp(0.5, 3.0);

  @override
  Future<void> start(
    List<String> chunks, {
    int from = 0,
    required double rate,
    String voiceName = '',
    String voiceLocale = '',
    int startCharOffset = 0,
  }) async {
    await _abortCurrent();
    await _ensureSession();
    _ensureStateSub();
    if (voiceName.isNotEmpty && voiceLocale == TtsVoice.kokoroLocale) {
      _voice = voiceName;
    }
    _speed = _rateToSpeed(rate);
    _chunks = chunks;
    _index = chunks.isEmpty ? 0 : from.clamp(0, chunks.length - 1);
    _pendingSeekChar = startCharOffset > 0 ? startCharOffset : -1;
    final gen = ++_gen;
    _setState(TtsPlaybackState.playing);
    unawaited(_run(gen));
  }

  Future<void> _run(int gen) async {
    while (_index < _chunks.length) {
      if (gen != _gen || _state != TtsPlaybackState.playing) return;
      final text = _chunks[_index].trim();
      if (text.isEmpty) {
        _index++;
        continue;
      }
      final clip = await _ensureAudio(_index);
      if (gen != _gen || _state != TtsPlaybackState.playing) return;
      if (clip == null) {
        // Synthesis failed even after a retry — skip rather than stall.
        _index++;
        continue;
      }
      // Prefetch the next two chunks while this one plays.
      _prefetch(_index + 1);
      _prefetch(_index + 2);
      await _playClip(_index, clip);
      if (gen != _gen || _state != TtsPlaybackState.playing) return;
      _index++;
    }
    _setState(TtsPlaybackState.stopped);
    onChapterFinished?.call();
  }

  Future<void> _playClip(int chunkIndex, _Clip clip) async {
    final done = Completer<void>();
    _clipDone = done;
    _lastMarkFired = -1;
    _hlTimer?.cancel();
    _hlTimer = null;

    final marks = clip.marks;
    try {
      await _player.setFilePath(clip.path);
      // Word-exact resume: on the first clip after a resume, jump to the word
      // at/just before the saved character offset.
      if (_pendingSeekChar >= 0 && marks.isNotEmpty) {
        var idx = 0;
        for (var k = 0; k < marks.length; k++) {
          if (marks[k][0] <= _pendingSeekChar) {
            idx = k;
          } else {
            break;
          }
        }
        _lastMarkFired = idx - 1;
        final ms = (marks[idx][2].toDouble() * 1000).round();
        try {
          await _player.seek(Duration(milliseconds: ms));
        } on Exception {
          // ignore seek failure
        }
      }
      _pendingSeekChar = -1;
      // Start highlighting BEFORE play(): on the first clip, play() can take a
      // beat to spin up the audio session, and starting the timer after it left
      // the opening paragraph with no highlight.
      if (marks.isEmpty) {
        // No word timing: highlight the whole chunk for the duration.
        onWord?.call(chunkIndex, 0, _chunks[chunkIndex].length);
      } else {
        // Drive the highlight from the playback position on a steady tick.
        _hlTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
          final t = _player.position.inMilliseconds / 1000.0;
          var idx = _lastMarkFired;
          while (idx + 1 < marks.length && marks[idx + 1][2] <= t) {
            idx++;
          }
          if (idx >= 0 && idx != _lastMarkFired) {
            _lastMarkFired = idx;
            final m = marks[idx];
            onWord?.call(chunkIndex, m[0].toInt(), m[1].toInt());
          }
        });
      }
      await _player.play();
    } on Exception {
      if (!done.isCompleted) done.complete();
    }

    await done.future;
    _hlTimer?.cancel();
    _hlTimer = null;
  }

  void _prefetch(int i) {
    if (i < 0 || i >= _chunks.length) return;
    unawaited(_ensureAudio(i));
  }

  /// Returns the clip for chunk [i], synthesizing + caching on miss.
  Future<_Clip?> _ensureAudio(int i) {
    final text = _chunks[i].trim();
    final key = _cacheKey(_voice, _speed, text);
    final existing = _inflight[key];
    if (existing != null) return existing;
    final fut = _resolveAudio(key, text);
    _inflight[key] = fut;
    fut.whenComplete(() => _inflight.remove(key));
    return fut;
  }

  Future<_Clip?> _resolveAudio(String key, String text) async {
    final dir = await _ensureCacheDir();
    final file = File('${dir.path}/$key.mp3');
    final marksFile = File('${dir.path}/$key.marks');
    // Require the marks sidecar too, so clips cached before word-timing was
    // added are re-fetched (otherwise their highlight would freeze).
    if (await file.exists() &&
        await file.length() > 0 &&
        await marksFile.exists()) {
      return _Clip(file.path, await _readMarks(marksFile));
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await http
            .post(
              Uri.parse('$_baseUrl/tts'),
              headers: {..._authHeaders, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'text': text,
                'voice': _voice,
                'speed': _speed,
                'lang': 'en-us',
                if (_pron.isNotEmpty) 'pron': _pron,
              }),
            )
            .timeout(const Duration(seconds: 40));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          await file.writeAsBytes(resp.bodyBytes, flush: true);
          final marks = _parseMarks(resp.headers['x-tts-marks']);
          // Always write the sidecar (even when empty) so the cache is
          // considered complete and isn't re-fetched on every play.
          await marksFile.writeAsString(jsonEncode(marks), flush: true);
          return _Clip(file.path, marks);
        }
      } on Exception {
        // Retry once, then give up on this chunk.
      } on Object {
        // Defensive: never let a synthesis error kill the reader.
      }
    }
    return null;
  }

  List<List<num>> _parseMarks(String? header) {
    if (header == null || header.isEmpty) return const [];
    try {
      final decoded = jsonDecode(header);
      if (decoded is! List) return const [];
      return [
        for (final m in decoded)
          if (m is List && m.length >= 3)
            [m[0] as num, m[1] as num, m[2] as num],
      ];
    } on Object {
      return const [];
    }
  }

  Future<List<List<num>>> _readMarks(File f) async {
    try {
      if (!await f.exists()) return const [];
      return _parseMarks(await f.readAsString());
    } on Object {
      return const [];
    }
  }

  Future<Directory> _ensureCacheDir() async {
    final cached = _cacheDir;
    if (cached != null) return cached;
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/umbra_tts_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  // Bump to invalidate every cached clip — e.g. after a server-side change to
  // pronunciation/normalization, so old audio (mispronounced money, etc.) is
  // re-synthesized instead of replayed from cache.
  static const _cacheVersion = 2;

  // Stable FNV-1a hash so cache filenames survive app restarts.
  String _cacheKey(String voice, double speed, String text) {
    final input =
        'v$_cacheVersion|$_pronSig|$voice|${speed.toStringAsFixed(2)}|$text';
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  @override
  Future<void> pause() async {
    if (_state != TtsPlaybackState.playing) return;
    _setState(TtsPlaybackState.paused);
    try {
      await _player.pause();
    } on Exception {
      // ignore
    }
  }

  @override
  Future<void> resume({required double rate}) async {
    if (_state != TtsPlaybackState.paused) return;
    _speed = _rateToSpeed(rate);
    _setState(TtsPlaybackState.playing);
    try {
      await _player.play();
    } on Exception {
      // ignore
    }
  }

  @override
  Future<void> stop() async {
    _index = 0;
    await _abortCurrent();
    _setState(TtsPlaybackState.stopped);
  }

  /// Stops playback and releases the current generation's loop.
  Future<void> _abortCurrent() async {
    _gen++;
    final c = _clipDone;
    if (c != null && !c.isCompleted) c.complete();
    _clipDone = null;
    _hlTimer?.cancel();
    _hlTimer = null;
    try {
      await _player.stop();
    } on Exception {
      // ignore
    }
  }

  /// Skips playback by [seconds] (negative = back). Seeks within the current
  /// paragraph clip, stepping to the adjacent paragraph at the boundaries.
  Future<void> nudge(int seconds) async {
    if (_state == TtsPlaybackState.stopped) return;
    final dur = _player.duration ?? Duration.zero;
    final pos = _player.position;
    final target = pos + Duration(seconds: seconds);
    if (seconds < 0 && target < const Duration(seconds: 1)) {
      // Near the start: jump to the previous paragraph, else restart this one.
      if (pos < const Duration(seconds: 2) && _index > 0) {
        await _jumpToChunk(_index - 1);
      } else {
        await _player.seek(Duration.zero);
        _lastMarkFired = -1;
      }
      return;
    }
    if (seconds > 0 && dur > Duration.zero && target >= dur) {
      await _jumpToChunk(_index + 1);
      return;
    }
    await _player.seek(target < Duration.zero ? Duration.zero : target);
    _lastMarkFired = -1;
  }

  /// Restarts the playback loop at [newIndex] (used for chunk-level seeking).
  Future<void> _jumpToChunk(int newIndex) async {
    final clamped = newIndex.clamp(0, _chunks.length - 1);
    final wasPlaying = _state == TtsPlaybackState.playing;
    _gen++;
    final c = _clipDone;
    if (c != null && !c.isCompleted) c.complete();
    _clipDone = null;
    _hlTimer?.cancel();
    _hlTimer = null;
    try {
      await _player.stop();
    } on Exception {
      // ignore
    }
    _index = clamped;
    if (wasPlaying) {
      final gen = ++_gen;
      unawaited(_run(gen));
    }
  }

  void _setState(TtsPlaybackState next) {
    _state = next;
    onStateChanged?.call(next);
  }

  @override
  Future<void> dispose() async {
    await _abortCurrent();
    await _stateSub?.cancel();
    await _player.dispose();
  }
}
