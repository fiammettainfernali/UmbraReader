import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../feature_flags.dart';
import '../models/content_block.dart';
import '../models/epub_book.dart';
import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../models/volume.dart';
import '../screens/pronunciation_screen.dart';
import '../services/epub_parser.dart';
import '../services/network_tts_service.dart';
import '../services/now_playing_service.dart';
import '../services/pronunciation_store.dart';
import '../services/tts_engine.dart';
import '../services/tts_service.dart';
import '../services/tts_skip.dart';
import '../widgets/listen_view.dart';
import '../widgets/reader_settings_sheet.dart';

/// The reader's read-aloud session, extracted from the ReaderScreen State:
/// engine lifecycle (on-device ↔ Kokoro), pronunciations, chunk building,
/// word-highlight callbacks, sleep timer, Listen mode, lock-screen controls
/// and background audio pre-caching.
///
/// The mixin owns every TTS-only field; everything it needs from the rest of
/// the reader goes through the abstract members below, which the State
/// implements as thin proxies onto its private fields. The whole feature is
/// currently dormant behind [kReadAloudEnabled].
mixin ReaderTtsSession<T extends StatefulWidget> on State<T> {
  // ── what the reader State must provide ──────────────────────────────────

  Volume get readerVolume;
  ReaderSettings get readerSettings;
  List<ContentBlock>? get currentBlocks;
  EpubBook? get currentBook;
  EpubParser? get currentParser;
  int get currentChapterIndex;
  int get currentChapterWordCount;

  /// Progress through the current chapter (0..1) — read-aloud drives it in
  /// Listen mode, where no scroll/page view is built.
  double get chapterFraction;
  set chapterFraction(double value);

  /// Index of the block at the top of the viewport (page or scroll mode).
  int currentTopBlockIndex();

  /// Plain text of a block — exactly the runs as rendered, so TTS word
  /// offsets line up with the on-screen text for highlighting.
  String plainBlockText(ContentBlock block);

  void goToChapter(int index, {bool landOnLastPage = false, bool fromTts = false});
  void saveReadingProgress();

  /// Scrolls/pages so the block being read stays visible.
  void followSpeaking(int blockIndex);

  /// Forgets the last auto-followed block/page so following re-engages.
  void resetFollow();

  Future<void> applyReaderSettings(ReaderSettings next);
  Future<void> openReaderSettings();

  // ── session state (owned by the mixin) ──────────────────────────────────

  TtsEngine ttsEngine = TtsService();
  TtsEngineKind _engineKind = TtsEngineKind.system;
  Map<String, String> _pronunciations = const {};

  /// Word-level resume point loaded on open (block index + char offset);
  /// used once for the first read-aloud play, then cleared.
  int ttsResumeBlock = -1;
  int ttsResumeChar = 0;

  /// Local file path of the series cover, for the lock-screen artwork.
  String? ttsCoverPath;

  /// Background audio pre-processing (cache warming) progress + cancel token.
  int ttsPrepDone = 0;
  int ttsPrepTotal = 0;
  int _prepGen = 0;

  final _nowPlaying = NowPlayingService();

  /// When true, the reader is replaced by the full-screen "Listen" player —
  /// a cover-art transport for hands-off listening.
  bool listenMode = false;

  /// The block currently being read aloud, and the character range of the
  /// active sentence within it. Null when read-aloud is stopped.
  int? speakingBlock;
  int speakingStart = 0;
  int speakingEnd = 0;

  /// Maps a TTS chunk index back to its block index in the chapter blocks.
  List<int> _ttsBlockForChunk = const [];

  /// Active sleep-timer choice and its countdown.
  SleepTimerOption sleepOption = SleepTimerOption.off;
  Timer? _sleepTimer;

  // ── lifecycle ────────────────────────────────────────────────────────────

  /// Wires the engine callbacks and lock-screen remote handlers. Call from
  /// initState.
  void initTtsSession() {
    _wireTts();
    _nowPlaying.onPlay = _remotePlay;
    _nowPlaying.onPause = _remotePause;
    _nowPlaying.onToggle = toggleTts;
    _nowPlaying.onNext = () => _remoteSkipChapter(1);
    _nowPlaying.onPrevious = () => _remoteSkipChapter(-1);
  }

  /// Tears down the engine, timers and lock-screen state. Call from dispose.
  void disposeTtsSession() {
    _sleepTimer?.cancel();
    _nowPlaying.clear();
    _nowPlaying.dispose();
    ttsEngine.dispose();
  }

  /// Attaches the reader's callbacks to the active TTS engine. Called on init
  /// and again whenever the engine is swapped.
  void _wireTts() {
    ttsEngine.onStateChanged = (state) {
      _updateNowPlaying();
      if (!mounted) return;
      setState(() {
        if (state == TtsPlaybackState.stopped) {
          speakingBlock = null;
          resetFollow();
        }
      });
    };
    ttsEngine.onWord = _onTtsWord;
    ttsEngine.onChapterFinished = _onTtsChapterFinished;
  }

  /// Rebuilds (or reconfigures) the read-aloud engine to match the settings.
  /// Switching engines stops any active playback; reconfiguring the same
  /// Kokoro engine just pushes the new URL/token.
  void syncEngineToSettings() {
    final settings = readerSettings;
    final desired = settings.ttsEngine;
    if (desired == _engineKind) {
      final engine = ttsEngine;
      if (desired == TtsEngineKind.kokoro && engine is NetworkTtsService) {
        engine.configure(
          baseUrl: settings.ttsServerUrl,
          token: settings.ttsServerToken,
        );
      }
      return;
    }
    final old = ttsEngine;
    old.stop();
    old.dispose();
    ttsEngine = desired == TtsEngineKind.kokoro
        ? NetworkTtsService(
            baseUrl: settings.ttsServerUrl,
            token: settings.ttsServerToken,
          )
        : TtsService();
    _engineKind = desired;
    _wireTts();
    _applyPronunciations();
  }

  // ── pronunciations ───────────────────────────────────────────────────────

  /// Loads this series' pronunciation overrides (global + per-series) and
  /// pushes them to the active engine.
  Future<void> loadPronunciations() async {
    final map = await PronunciationStore().merged(readerVolume.seriesOpdsId);
    if (!mounted) return;
    _pronunciations = map;
    _applyPronunciations();
  }

  void _applyPronunciations() {
    final engine = ttsEngine;
    if (engine is NetworkTtsService) {
      engine.setPronunciations(_pronunciations);
    }
  }

  /// Opens the pronunciation editor; on return, re-applies overrides and
  /// re-synthesizes from the current spot if reading.
  Future<void> openPronunciations() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PronunciationScreen(
          seriesId: readerVolume.seriesOpdsId,
          seriesTitle: readerVolume.title,
        ),
      ),
    );
    await loadPronunciations();
    // Re-read from the current word with the new pronunciations, rather than
    // restarting the chapter.
    if (ttsEngine.state == TtsPlaybackState.playing) {
      _restartFromSpoken();
    }
  }

  /// Restarts read-aloud from the paragraph (and word) currently being spoken,
  /// e.g. after changing pronunciations — without jumping to the chapter start.
  void _restartFromSpoken() {
    final block = speakingBlock;
    if (block == null) {
      startTts(fromCurrentPosition: true);
      return;
    }
    final chunk = _ttsBlockForChunk.indexOf(block);
    if (chunk < 0) {
      startTts(fromCurrentPosition: true);
      return;
    }
    ttsResumeBlock = block;
    ttsResumeChar = speakingStart;
    startTts(startAtChunk: chunk);
  }

  // ── playback ─────────────────────────────────────────────────────────────

  void startTts({bool fromCurrentPosition = true, int? startAtChunk}) {
    final blocks = currentBlocks ?? const <ContentBlock>[];
    final settings = readerSettings;
    final texts = <String>[];
    final blockForChunk = <int>[];
    final skips = settings.ttsSkips;
    final skipHeadings = skips.contains(TtsSkip.headings);
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (skipHeadings && block is HeadingBlock) continue;
      // Redact (not delete) skipped spans so spoken offsets — and therefore
      // the highlight — stay aligned with the displayed text.
      final text = redactForSpeech(plainBlockText(block), skips);
      if (text.trim().isEmpty) continue;
      texts.add(text);
      blockForChunk.add(i);
    }
    if (texts.isEmpty) return;
    // Begin from the paragraph currently in view, not the chapter top.
    var fromChunk = 0;
    if (startAtChunk != null) {
      fromChunk = startAtChunk.clamp(0, blockForChunk.length - 1);
    } else if (fromCurrentPosition) {
      final topBlock = currentTopBlockIndex();
      fromChunk = blockForChunk.length - 1;
      for (var c = 0; c < blockForChunk.length; c++) {
        if (blockForChunk[c] >= topBlock) {
          fromChunk = c;
          break;
        }
      }
    }
    _ttsBlockForChunk = blockForChunk;
    resetFollow();
    // Word-exact resume: applies whenever the starting chunk is the paragraph
    // the resume point belongs to (initial open, or a restart-in-place).
    var startChar = 0;
    if (ttsResumeBlock >= 0 &&
        fromChunk < blockForChunk.length &&
        blockForChunk[fromChunk] == ttsResumeBlock) {
      startChar = ttsResumeChar;
    }
    ttsResumeBlock = -1; // consume — it only applies to this play
    ttsEngine.start(
      texts,
      from: fromChunk,
      rate: settings.speechRate,
      voiceName: settings.voiceName,
      voiceLocale: settings.voiceLocale,
      startCharOffset: startChar,
    );
  }

  void toggleTts() {
    final state = ttsEngine.state;
    if (state == TtsPlaybackState.playing) {
      ttsEngine.pause();
    } else if (state == TtsPlaybackState.paused) {
      ttsEngine.resume(rate: readerSettings.speechRate);
    } else {
      startTts();
    }
  }

  /// Swaps between the reader and the full-screen "Listen" player.
  void toggleListen() {
    setState(() => listenMode = !listenMode);
  }

  /// Skips read-aloud by [seconds] (negative = back). Only the Kokoro engine
  /// plays seekable audio clips, so this is a no-op on the on-device engine.
  void nudgeTts(int seconds) {
    final engine = ttsEngine;
    if (engine is NetworkTtsService) engine.nudge(seconds);
  }

  /// Cycles the read-aloud speed through common multipliers (1×–3×) for the
  /// listen player's quick speed button.
  void _cycleSpeed() {
    const rates = [0.5, 0.625, 0.75, 0.875, 1.0, 1.25, 1.5];
    final current = readerSettings.speechRate;
    var next = rates.first;
    for (var i = 0; i < rates.length; i++) {
      if ((rates[i] - current).abs() < 0.02) {
        next = rates[(i + 1) % rates.length];
        break;
      }
    }
    applyReaderSettings(readerSettings.copyWith(speechRate: next));
  }

  /// Read-aloud speed as a playback multiplier label, e.g. "1.5×".
  String _speedLabel() {
    final m = readerSettings.speechRate * 2;
    var s = m.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return '$s×';
  }

  /// When read-aloud reaches the end of a chapter, roll into the next one and
  /// keep reading — unless the sleep timer is set to stop at the chapter end.
  void _onTtsChapterFinished() {
    if (sleepOption == SleepTimerOption.endOfChapter) {
      if (mounted) setState(() => sleepOption = SleepTimerOption.off);
      return;
    }
    final book = currentBook;
    if (book == null) return;
    if (currentChapterIndex < book.chapters.length - 1) {
      goToChapter(currentChapterIndex + 1, fromTts: true);
      // A TTS-driven advance reads the new chapter from its start.
      startTts(fromCurrentPosition: false);
    }
  }

  /// Arms (or clears) the read-aloud sleep timer.
  void setSleepTimer(SleepTimerOption option) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    setState(() => sleepOption = option);
    final duration = option.duration;
    if (duration != null) {
      _sleepTimer = Timer(duration, () {
        ttsEngine.pause();
        if (mounted) setState(() => sleepOption = SleepTimerOption.off);
      });
    }
  }

  // ── word highlighting ────────────────────────────────────────────────────

  /// Highlights the word being read and keeps it on screen. Falls back to the
  /// enclosing sentence when a precise word range isn't available.
  void _onTtsWord(int chunkIndex, int start, int end) {
    if (!mounted) return;
    if (chunkIndex < 0 || chunkIndex >= _ttsBlockForChunk.length) return;
    final blockIndex = _ttsBlockForChunk[chunkIndex];
    final blocks = currentBlocks ?? const <ContentBlock>[];
    if (blockIndex < 0 || blockIndex >= blocks.length) return;
    final text = plainBlockText(blocks[blockIndex]);
    final int hlStart;
    final int hlEnd;
    if (end > start && start >= 0 && end <= text.length) {
      hlStart = start;
      hlEnd = end;
    } else {
      final range = _sentenceRangeAt(text, start);
      hlStart = range.$1;
      hlEnd = range.$2;
    }
    final blockChanged = blockIndex != speakingBlock;
    setState(() {
      speakingBlock = blockIndex;
      speakingStart = hlStart;
      speakingEnd = hlEnd;
      // In listen mode the page/scroll isn't built, so drive the chapter
      // progress bar from how far read-aloud has moved instead.
      if (listenMode && _ttsBlockForChunk.length > 1) {
        chapterFraction =
            (chunkIndex / (_ttsBlockForChunk.length - 1)).clamp(0.0, 1.0);
      }
    });
    followSpeaking(blockIndex);
    // Persist the spot each time read-aloud crosses into a new paragraph, so
    // leaving mid-listen (or a background kill) resumes where the voice is.
    if (blockChanged) saveReadingProgress();
  }

  /// The character range of the sentence containing [offset] in [text].
  (int, int) _sentenceRangeAt(String text, int offset) {
    if (text.isEmpty) return (0, 0);
    final o = offset.clamp(0, text.length - 1);
    var start = 0;
    for (var i = o - 1; i >= 0; i--) {
      final c = text[i];
      if (c == '.' || c == '!' || c == '?' || c == '\n') {
        start = i + 1;
        break;
      }
    }
    while (start < text.length && text[start] == ' ') {
      start++;
    }
    var end = text.length;
    for (var i = o; i < text.length; i++) {
      final c = text[i];
      if (c == '.' || c == '!' || c == '?' || c == '\n') {
        end = i + 1;
        break;
      }
    }
    return (start, end);
  }

  // ── audio pre-caching ────────────────────────────────────────────────────

  /// Builds the read-aloud chunk texts for [blocks] — the same redacted,
  /// skip-filtered strings playback uses, so warmed cache entries match.
  List<String> _chunkTextsForBlocks(List<ContentBlock> blocks) {
    final skips = readerSettings.ttsSkips;
    final skipHeadings = skips.contains(TtsSkip.headings);
    final texts = <String>[];
    for (final block in blocks) {
      if (skipHeadings && block is HeadingBlock) continue;
      final text = redactForSpeech(plainBlockText(block), skips);
      if (text.trim().isNotEmpty) texts.add(text);
    }
    return texts;
  }

  Future<bool> _onWifi() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet);
    } on Exception {
      return false;
    }
  }

  /// Quietly pre-synthesizes the current chapter (and the next) into the cache
  /// on Wi-Fi, so play is instant/gapless. Kokoro engine only.
  Future<void> prepareAudio() async {
    if (!kReadAloudEnabled) return;
    final engine = ttsEngine;
    if (engine is! NetworkTtsService) return;
    if (!await _onWifi()) return;
    final book = currentBook;
    final blocks = currentBlocks;
    final parser = currentParser;
    if (book == null || blocks == null) return;
    final texts = <String>[..._chunkTextsForBlocks(blocks)];
    final next = currentChapterIndex + 1;
    if (parser != null && next < book.chapters.length) {
      try {
        texts.addAll(
          _chunkTextsForBlocks(parser.parseChapter(book.chapters[next])),
        );
      } on Object {
        // Next-chapter parse is best-effort.
      }
    }
    if (texts.isEmpty) return;
    final gen = ++_prepGen;
    if (mounted) {
      setState(() {
        ttsPrepDone = 0;
        ttsPrepTotal = texts.length;
      });
    }
    await engine.precache(
      texts,
      voice: readerSettings.voiceName,
      rate: readerSettings.speechRate,
      onProgress: (done, total) {
        if (!mounted || gen != _prepGen) return;
        setState(() {
          ttsPrepDone = done;
          ttsPrepTotal = total;
        });
      },
      shouldCancel: () => !mounted || gen != _prepGen,
    );
    if (mounted && gen == _prepGen) {
      setState(() {
        ttsPrepDone = 0;
        ttsPrepTotal = 0;
      });
    }
  }

  /// Caches every chapter's audio so the whole volume plays offline, with a
  /// progress dialog.
  Future<void> prepareVolumeForOffline() async {
    final engine = ttsEngine;
    final book = currentBook;
    final parser = currentParser;
    if (engine is! NetworkTtsService) {
      _showSnack('Switch to the Natural voice to prepare offline audio.');
      return;
    }
    if (book == null || parser == null) return;
    final texts = <String>[];
    for (final chapter in book.chapters) {
      try {
        texts.addAll(_chunkTextsForBlocks(parser.parseChapter(chapter)));
      } on Object {
        // Skip an unparseable chapter.
      }
    }
    if (texts.isEmpty) return;
    final total = texts.length;
    final gen = ++_prepGen;
    final progress = ValueNotifier<int>(0);
    var stopped = false;
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Preparing for offline'),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: total == 0 ? 0 : done / total),
                const SizedBox(height: 12),
                Text('$done of $total paragraphs'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                stopped = true;
                _prepGen++;
                dialogOpen = false;
                Navigator.of(dialogCtx).pop();
              },
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
    await engine.precache(
      texts,
      voice: readerSettings.voiceName,
      rate: readerSettings.speechRate,
      onProgress: (done, _) => progress.value = done,
      shouldCancel: () => stopped || gen != _prepGen,
    );
    if (mounted && dialogOpen) {
      dialogOpen = false;
      Navigator.of(context).pop();
    }
    progress.dispose();
    if (mounted && !stopped) {
      _showSnack('This volume is ready to listen offline.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// A subtle "Preparing audio · N%" pill shown while the cache warms.
  Widget ttsPrepChip(ReaderThemePreset preset) {
    final pct = ttsPrepTotal == 0
        ? 0
        : (ttsPrepDone * 100 / ttsPrepTotal).round();
    return Material(
      color: preset.background.withValues(alpha: 0.92),
      shape: StadiumBorder(
        side: BorderSide(color: preset.text.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(preset.text),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Preparing audio · $pct%',
              style: TextStyle(color: preset.text, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ── Listen mode ──────────────────────────────────────────────────────────

  Widget buildListenView(EpubBook book, ReaderThemePreset preset) {
    final minutesLeft =
        currentChapterWordCount * (1 - chapterFraction) / 220.0;
    return Scaffold(
      backgroundColor: preset.background,
      body: ListenView(
        seriesId: readerVolume.seriesOpdsId,
        title: readerVolume.title,
        chapterTitle: book.chapters[currentChapterIndex].title,
        chapterIndex: currentChapterIndex,
        chapterTotal: book.chapters.length,
        progress: chapterFraction.clamp(0.0, 1.0),
        minutesLeft: minutesLeft,
        isPlaying: ttsEngine.state == TtsPlaybackState.playing,
        speedLabel: _speedLabel(),
        sleepActive: sleepOption != SleepTimerOption.off,
        canSeek: ttsEngine is NetworkTtsService,
        preset: preset,
        onClose: toggleListen,
        onPlayPause: toggleTts,
        onPrevChapter: () => goToChapter(currentChapterIndex - 1),
        onNextChapter: () => goToChapter(currentChapterIndex + 1),
        onBack15: () => nudgeTts(-15),
        onForward15: () => nudgeTts(15),
        onCycleSpeed: _cycleSpeed,
        onOpenSettings: openReaderSettings,
      ),
    );
  }

  // ── lock-screen / Control Center controls ────────────────────────────────

  /// Publishes the current chapter and play state to the iOS lock screen, or
  /// clears it when read-aloud is stopped.
  void _updateNowPlaying() {
    final book = currentBook;
    if (book == null || ttsEngine.state == TtsPlaybackState.stopped) {
      _nowPlaying.clear();
      return;
    }
    final index = currentChapterIndex;
    final title = (index >= 0 && index < book.chapters.length)
        ? book.chapters[index].title
        : readerVolume.title;
    _nowPlaying.update(
      title: title,
      book: readerVolume.title,
      isPlaying: ttsEngine.state == TtsPlaybackState.playing,
      artworkPath: ttsCoverPath,
    );
  }

  /// Lock-screen "play": resume if paused, otherwise start from the top of
  /// what's on screen.
  void _remotePlay() {
    switch (ttsEngine.state) {
      case TtsPlaybackState.paused:
        ttsEngine.resume(rate: readerSettings.speechRate);
      case TtsPlaybackState.stopped:
        startTts();
      case TtsPlaybackState.playing:
        break;
    }
  }

  /// Lock-screen "pause".
  void _remotePause() {
    if (ttsEngine.state == TtsPlaybackState.playing) {
      ttsEngine.pause();
    }
  }

  /// Lock-screen next/previous-track: jump a chapter and, if read-aloud was
  /// active, keep reading from the new chapter's start.
  void _remoteSkipChapter(int delta) {
    final book = currentBook;
    if (book == null) return;
    final target = currentChapterIndex + delta;
    if (target < 0 || target >= book.chapters.length) return;
    final wasActive = ttsEngine.state != TtsPlaybackState.stopped;
    goToChapter(target, fromTts: wasActive);
    if (wasActive) startTts(fromCurrentPosition: false);
  }
}
