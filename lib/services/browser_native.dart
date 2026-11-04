import 'dart:io';

import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// What the in-app browsers need from Android that the web view plugin doesn't
/// offer itself. Every call reports false rather than failing, because a phone
/// that can't do one of these still has a working browser.
class BrowserNative {
  BrowserNative._();

  static const _channel = MethodChannel('umbra/browser');

  static int? _viewId(WebViewController controller) {
    final platform = controller.platform;
    return platform is AndroidWebViewController
        ? platform.webViewIdentifier
        : null;
  }

  static Future<bool> _call(String method, Map<String, Object?> args) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Gives a new web view its own sign-ins and site data. Has to happen before
  /// it loads anything.
  static Future<bool> useProfile(WebViewController controller, String profile) {
    final id = _viewId(controller);
    if (id == null) return Future.value(false);
    return _call('setProfile', {'viewId': id, 'profile': profile});
  }

  /// Runs [script] ahead of every page's own scripts. Null removes it.
  static Future<bool> setStartScript(
    WebViewController controller,
    String? script,
  ) {
    final id = _viewId(controller);
    if (id == null) return Future.value(false);
    return _call('setStartScript', {'viewId': id, 'script': script});
  }

  /// Lets go of what's kept for a closed tab.
  static Future<void> forget(WebViewController controller) async {
    final id = _viewId(controller);
    if (id != null) await _call('forget', {'viewId': id});
  }

  static Future<bool> openExternally(Uri url) =>
      _call('openExternally', {'url': url.toString()});
}
