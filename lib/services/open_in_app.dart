// Handing a volume to another app to open — not to share.
//
// Those are different sets of apps, and the difference cost a reader their
// read-aloud setup. Natural Reader registers EPUB under ACTION_VIEW and only
// plain text under ACTION_SEND, so it was absent from the share sheet while
// being the one app on the phone able to read a whole volume out loud: on
// that device, sharing an EPUB offers Bluetooth and Gmail, and nothing else.
//
// The file is staged as a copy in the cache rather than offered where it
// lives. The library is app-private storage, so the only thing another app
// can be given is a content:// URI with a read grant, and that grant should
// point at something disposable rather than at the library itself.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class OpenInApp {
  const OpenInApp({this.channel = const MethodChannel('umbra/open_in')});

  final MethodChannel channel;

  static const epubMimeType = 'application/epub+zip';

  /// Offers [epub] to the apps that can open an EPUB, named after [title] so
  /// it arrives as the book rather than as `b1-v1.epub`.
  ///
  /// Returns false when nothing can open it — or on iOS, where the share
  /// sheet already *is* the open-in mechanism and the caller should use it.
  /// False means "tell the reader", not "it failed silently".
  Future<bool> openEpub(
    File epub, {
    required String title,
    Directory? stagingParent,
  }) async {
    // defaultTargetPlatform, not Platform.isAndroid: the dart:io answer is
    // about the machine the code is RUNNING on, which under `flutter test`
    // is a desktop. Using it here would have made every test of this pass
    // by taking the early exit, proving nothing.
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    if (!epub.existsSync()) return false;

    final parent = stagingParent ?? await getTemporaryDirectory();
    final staging = Directory('${parent.path}/open_in');
    // Cleared rather than added to. Each handover leaves a copy of a whole
    // volume behind, and a reader who listens to a hundred books should not
    // be paying for ninety-nine of them in cache.
    if (staging.existsSync()) {
      try {
        staging.deleteSync(recursive: true);
      } on FileSystemException {
        // A copy still held open by the app that received it. Leave it.
      }
    }
    staging.createSync(recursive: true);

    final staged = File('${staging.path}/${_fileName(title)}');
    try {
      epub.copySync(staged.path);
    } on FileSystemException {
      return false;
    }

    try {
      final opened = await channel.invokeMethod<bool>('open', {
        'path': staged.path,
        'mimeType': epubMimeType,
      });
      return opened ?? false;
    } on MissingPluginException {
      // A platform without the bridge. Same answer as "nothing can open it".
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// A filename the receiving app can show as-is.
  ///
  /// Reader apps list what they are given by filename, so the title is worth
  /// carrying across — but it has to survive being a filename first. Anything
  /// a path cannot hold becomes an underscore, and the length is capped well
  /// inside the usual 255-byte limit to leave room for multi-byte titles.
  static String _fileName(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[^\w\s.\-]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final safe = cleaned.isEmpty ? 'Book' : cleaned;
    final capped = safe.length <= 80 ? safe : safe.substring(0, 80).trim();
    return '$capped.epub';
  }
}
