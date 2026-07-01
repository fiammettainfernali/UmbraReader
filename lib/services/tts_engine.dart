/// Read-aloud playback state, shared by every TTS engine.
enum TtsPlaybackState { stopped, playing, paused }

/// A selectable read-aloud voice.
///
/// For the on-device engine, [name]/[locale] are the iOS voice identifiers.
/// For the Kokoro network engine, [name] is the Kokoro voice id (e.g.
/// `af_heart`) and [locale] is the sentinel [TtsVoice.kokoroLocale], which also
/// tells the reader which engine a saved voice belongs to.
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  /// Locale sentinel marking a voice as belonging to the Kokoro engine.
  static const kokoroLocale = 'kokoro';

  bool get isKokoro => locale == kokoroLocale;

  /// Stable key for matching a saved voice against the available list.
  String get id => '$name|$locale';
}

/// Which read-aloud engine produces speech.
enum TtsEngineKind {
  /// On-device iOS voices (free, offline, instant).
  system,

  /// Self-hosted Kokoro neural voices streamed from a server (more natural,
  /// unmoderated; needs the voice server reachable).
  kokoro,
}

/// Common surface every read-aloud engine implements, so the reader can drive
/// the on-device synthesizer and the networked Kokoro server interchangeably.
abstract class TtsEngine {
  TtsPlaybackState get state;

  /// Called whenever playback state changes.
  set onStateChanged(void Function(TtsPlaybackState state)? cb);

  /// Called as speech advances, with the chunk index and the character range
  /// within that chunk being spoken. The network engine reports the whole
  /// chunk at once (sentence-level highlighting).
  set onWord(void Function(int chunkIndex, int charStart, int charEnd)? cb);

  /// Called once the whole chapter has finished.
  set onChapterFinished(void Function()? cb);

  /// Lists the voices this engine can use, sorted by name.
  Future<List<TtsVoice>> availableVoices();

  /// Selects a voice (best-effort).
  Future<void> setVoice(String name, String locale);

  /// Begins reading [chunks] (one per paragraph) from [from]. [startCharOffset]
  /// is an optional character position within the first chunk to resume from
  /// (word-exact resume; honoured only by engines that can seek, i.e. Kokoro).
  Future<void> start(
    List<String> chunks, {
    int from,
    required double rate,
    String voiceName,
    String voiceLocale,
    int startCharOffset,
  });

  Future<void> pause();

  Future<void> resume({required double rate});

  Future<void> stop();

  /// Applies a new speech rate, taking effect from the next chunk.
  Future<void> setRate(double rate);

  Future<void> dispose();
}
