import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

/// Plays the short paper sound on a page turn.
///
/// A UI sound has requirements a media player does not. It must be able to
/// fire again before the last one has finished (fast tapping through pages),
/// it must never make the caller wait, and it must never be the reason
/// something else in the app breaks — a page that refuses to turn because an
/// audio device is busy would be a far worse bug than a missing sound.
///
/// So every path here is best-effort: failures are swallowed, [play] returns
/// immediately, and the reader calls it without awaiting.
class PageTurnSound {
  PageTurnSound._();

  /// One instance for the app. The player holds a decoded asset and an
  /// audio-session registration; making one per reader screen would leak both.
  static final PageTurnSound instance = PageTurnSound._();

  static const _asset = 'assets/sounds/page-turn.mp3';

  AudioPlayer? _player;
  Future<void>? _loading;
  bool _broken = false;

  /// Decodes the asset so the first turn is not the one that pays for it.
  ///
  /// Safe to call repeatedly; the work happens once. Called when the reader
  /// opens with the sound enabled, and when the setting is switched on.
  Future<void> warmUp() {
    if (_broken) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final player = AudioPlayer(
        // A page turn is a sound effect, not playback, and every one of these
        // defaults exists for playback. Left on, the first turn would take
        // audio focus — pausing or ducking whatever the reader had running —
        // and then hand it back a fifth of a second later, on every page.
        handleAudioSessionActivation: false,
        // The app configures a speech session for read-aloud. This clip is
        // not speech and must not inherit that.
        androidApplyAudioAttributes: false,
        // Nothing to interrupt: by the time a phone call arrives the sound
        // has already finished.
        handleInterruptions: false,
      );
      // Classified as a UI sound rather than media, so the system treats it
      // the way it treats a keyboard click.
      await player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.assistanceSonification,
        ),
      );
      await player.setAsset(_asset);
      _player = player;
    } catch (_) {
      // No audio device, a codec the platform dislikes, a missing asset in
      // some future build — none of it is worth a crash for a page sound.
      _broken = true;
    }
  }

  /// Plays the sound, starting it over if it is already sounding.
  ///
  /// Deliberately not `async`: the caller is mid-gesture, and the page must
  /// turn on this frame whatever the audio stack is doing.
  void play() {
    if (_broken) return;
    final player = _player;
    if (player == null) {
      // First turn before the warm-up finished: load, then play once ready.
      // The turn itself already happened, so this is only ever the sound
      // arriving a beat late rather than the page waiting for it.
      warmUp().then((_) => play());
      return;
    }
    // seek-then-play rather than a fresh player each time: restarting is what
    // makes rapid page turns sound like rapid page turns instead of silence
    // while the previous one finishes.
    player.seek(Duration.zero).then((_) => player.play()).catchError((_) {});
  }

  /// Releases the decoded asset. The reader calls this when it closes.
  Future<void> dispose() async {
    final player = _player;
    _player = null;
    _loading = null;
    try {
      await player?.dispose();
    } catch (_) {
      // Disposing a player that never opened is not an error worth raising.
    }
  }
}

/// Whether a page turn should make a sound right now.
///
/// Pulled out as a plain function because it is the part with actual rules in
/// it, and because the reader that calls it cannot be constructed in a test.
///
/// [speaking] silences it during read-aloud: the sound is meant to punctuate
/// your own reading, and dropped into a spoken sentence it just sounds like a
/// glitch. [autoTurn] silences hands-free turning for the same reason a clock
/// that chimed every page would get switched off.
/// [reseating] silences the pager being re-anchored rather than turned.
/// Repagination — chrome appearing, a font change, a rotation — moves the
/// reader to whichever page now holds the words they were on. That is a
/// correction, and it reaches the pager as the same `jumpToPage` a real turn
/// does. Left ungated it was audible: tapping the middle of the screen to
/// open the menu played a page-turn sound, because opening the menu changes
/// the height the text is laid into.
bool shouldPlayPageTurnSound({
  required bool enabled,
  required bool speaking,
  required bool autoTurn,
  required bool reseating,
}) => enabled && !speaking && !autoTurn && !reseating;
