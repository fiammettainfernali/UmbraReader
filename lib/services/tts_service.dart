import 'package:flutter_tts/flutter_tts.dart';

import 'tts_engine.dart';

export 'tts_engine.dart' show TtsPlaybackState, TtsVoice, TtsEngine;

/// Wraps [FlutterTts] to read a chapter aloud, chunk by chunk.
///
/// A chapter is supplied as a list of text chunks (one per paragraph). Chunks
/// are spoken sequentially; pausing remembers the current chunk so resuming
/// re-speaks it from its start.
class TtsService implements TtsEngine {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  List<String> _chunks = const [];
  int _index = 0;
  TtsPlaybackState _state = TtsPlaybackState.stopped;

  /// Called when the whole chapter has finished being read.
  void Function()? onChapterFinished;

  /// Unused by the on-device engine (local synthesis doesn't fail this way);
  /// present to satisfy [TtsEngine].
  @override
  void Function()? onSynthesisFailed;

  /// Called with the chunk index as each chunk starts.
  void Function(int chunkIndex)? onChunkChanged;

  /// Called as each word is spoken, with the chunk index and the word's
  /// character range within that chunk's text.
  void Function(int chunkIndex, int charStart, int charEnd)? onWord;

  /// Called whenever playback state changes.
  void Function(TtsPlaybackState state)? onStateChanged;

  @override
  TtsPlaybackState get state => _state;
  int get chunkIndex => _index;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _tts.awaitSpeakCompletion(true);
    _tts.setProgressHandler((text, start, end, word) {
      onWord?.call(_index, start, end);
    });
    try {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ],
      );
    } on Exception {
      // Audio-session setup is best-effort; speech still works without it.
    }
    _initialized = true;
  }

  /// Lists the installed English text-to-speech voices, sorted by name.
  @override
  Future<List<TtsVoice>> availableVoices() async {
    await _ensureInitialized();
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final seen = <String>{};
      final voices = <TtsVoice>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final name = entry['name']?.toString();
        final locale = entry['locale']?.toString();
        if (name == null || name.isEmpty || locale == null) continue;
        if (!locale.toLowerCase().startsWith('en')) continue;
        final voice = TtsVoice(name: name, locale: locale);
        if (seen.add(voice.id)) voices.add(voice);
      }
      voices.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return voices;
    } on Exception {
      return const [];
    }
  }

  /// Sets the active voice (best-effort; falls back to the system default).
  @override
  Future<void> setVoice(String name, String locale) async {
    await _ensureInitialized();
    await _applyVoice(name, locale);
  }

  Future<void> _applyVoice(String name, String locale) async {
    if (name.isEmpty || locale.isEmpty) return;
    try {
      await _tts.setVoice({'name': name, 'locale': locale});
    } on Exception {
      // Voice unavailable — the system default voice is used instead.
    }
  }

  /// Begins reading [chunks] aloud from [from], at the given [rate] (0–1) and
  /// (optionally) a chosen voice.
  @override
  Future<void> start(
    List<String> chunks, {
    int from = 0,
    required double rate,
    String voiceName = '',
    String voiceLocale = '',
    int startCharOffset = 0, // on-device engine can't seek within an utterance
  }) async {
    await _ensureInitialized();
    await _tts.stop();
    await _tts.setSpeechRate(rate);
    await _applyVoice(voiceName, voiceLocale);
    _chunks = chunks;
    _index = chunks.isEmpty ? 0 : from.clamp(0, chunks.length - 1);
    _setState(TtsPlaybackState.playing);
    _run();
  }

  Future<void> _run() async {
    while (_index < _chunks.length) {
      if (_state != TtsPlaybackState.playing) return;
      onChunkChanged?.call(_index);
      try {
        await _tts.speak(_chunks[_index]);
      } on Exception {
        // Skip a chunk that fails to speak rather than stalling.
      }
      if (_state != TtsPlaybackState.playing) return;
      _index++;
    }
    _setState(TtsPlaybackState.stopped);
    onChapterFinished?.call();
  }

  @override
  Future<void> pause() async {
    if (_state != TtsPlaybackState.playing) return;
    _setState(TtsPlaybackState.paused);
    await _tts.stop();
  }

  @override
  Future<void> resume({required double rate}) async {
    if (_state != TtsPlaybackState.paused) return;
    await _tts.setSpeechRate(rate);
    _setState(TtsPlaybackState.playing);
    _run();
  }

  @override
  Future<void> stop() async {
    _setState(TtsPlaybackState.stopped);
    _index = 0;
    await _tts.stop();
  }

  /// Applies a new speech rate; takes effect from the next chunk.
  @override
  Future<void> setRate(double rate) async {
    await _ensureInitialized();
    await _tts.setSpeechRate(rate);
  }

  void _setState(TtsPlaybackState next) {
    _state = next;
    onStateChanged?.call(next);
  }

  @override
  Future<void> dispose() async {
    _state = TtsPlaybackState.stopped;
    await _tts.stop();
  }
}
