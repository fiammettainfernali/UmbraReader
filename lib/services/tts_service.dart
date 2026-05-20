import 'package:flutter_tts/flutter_tts.dart';

/// Read-aloud playback state.
enum TtsPlaybackState { stopped, playing, paused }

/// Wraps [FlutterTts] to read a chapter aloud, chunk by chunk.
///
/// A chapter is supplied as a list of text chunks (one per paragraph). Chunks
/// are spoken sequentially; pausing remembers the current chunk so resuming
/// re-speaks it from its start.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  List<String> _chunks = const [];
  int _index = 0;
  TtsPlaybackState _state = TtsPlaybackState.stopped;

  /// Called when the whole chapter has finished being read.
  void Function()? onChapterFinished;

  /// Called with the chunk index as each chunk starts.
  void Function(int chunkIndex)? onChunkChanged;

  /// Called as each word is spoken, with the chunk index and the word's
  /// character range within that chunk's text.
  void Function(int chunkIndex, int charStart, int charEnd)? onWord;

  /// Called whenever playback state changes.
  void Function(TtsPlaybackState state)? onStateChanged;

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

  /// Begins reading [chunks] aloud from [from], at the given [rate] (0–1).
  Future<void> start(
    List<String> chunks, {
    int from = 0,
    required double rate,
  }) async {
    await _ensureInitialized();
    await _tts.stop();
    await _tts.setSpeechRate(rate);
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

  Future<void> pause() async {
    if (_state != TtsPlaybackState.playing) return;
    _setState(TtsPlaybackState.paused);
    await _tts.stop();
  }

  Future<void> resume({required double rate}) async {
    if (_state != TtsPlaybackState.paused) return;
    await _tts.setSpeechRate(rate);
    _setState(TtsPlaybackState.playing);
    _run();
  }

  Future<void> stop() async {
    _setState(TtsPlaybackState.stopped);
    _index = 0;
    await _tts.stop();
  }

  /// Applies a new speech rate; takes effect from the next chunk.
  Future<void> setRate(double rate) async {
    await _ensureInitialized();
    await _tts.setSpeechRate(rate);
  }

  void _setState(TtsPlaybackState next) {
    _state = next;
    onStateChanged?.call(next);
  }

  Future<void> dispose() async {
    _state = TtsPlaybackState.stopped;
    await _tts.stop();
  }
}
