import 'package:flutter/services.dart';

/// Bridges read-aloud playback to the iOS lock screen and Control Center.
///
/// Talks to the native `NowPlayingBridge` (in `AppDelegate.swift`) over a
/// method channel: [update]/[clear] push metadata to the system, while remote
/// transport buttons call back through [onPlay], [onPause], [onToggle],
/// [onNext] and [onPrevious]. Every call is a no-op on platforms without the
/// native handler (e.g. widget tests), so it is always safe to invoke.
class NowPlayingService {
  static const _channel = MethodChannel('umbra/now_playing');

  /// Lock-screen / Control Center "play" button.
  void Function()? onPlay;

  /// Lock-screen / Control Center "pause" button.
  void Function()? onPause;

  /// Headphone or remote play/pause toggle.
  void Function()? onToggle;

  /// "Next track" — advances a chapter.
  void Function()? onNext;

  /// "Previous track" — goes back a chapter.
  void Function()? onPrevious;

  NowPlayingService() {
    _channel.setMethodCallHandler(_handle);
  }

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'play':
        onPlay?.call();
      case 'pause':
        onPause?.call();
      case 'toggle':
        onToggle?.call();
      case 'next':
        onNext?.call();
      case 'previous':
        onPrevious?.call();
    }
    return null;
  }

  /// Publishes the current chapter/book, play state, and optional cover
  /// artwork (a local image file path) to the lock screen.
  Future<void> update({
    required String title,
    required String book,
    required bool isPlaying,
    String? artworkPath,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'book': book,
        'isPlaying': isPlaying,
        'artwork': ?artworkPath,
      });
    } on PlatformException {
      // Native bridge unavailable — lock-screen controls just won't appear.
    } on MissingPluginException {
      // Running without the bridge (e.g. tests) — silently ignore.
    }
  }

  /// Removes the app from the lock screen / Control Center.
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException {
      // Ignore — nothing to tear down.
    } on MissingPluginException {
      // Ignore — bridge not present.
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
