import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'opds_client.dart';
import 'settings_service.dart';

/// Which of your computer's two addresses to use right now.
///
/// One address was the whole story until Tailscale was switched off at home:
/// the Tailscale address timed out, the Wi-Fi address would have answered, and
/// the app said it couldn't reach the computer. With a second address saved,
/// both are asked at once and the first one is preferred: it is usually
/// Tailscale, which is encrypted, while plain Wi-Fi carries the password in
/// the clear. The second is used only while the first doesn't answer.
///
/// The library's links are stored under the first address whichever one
/// fetched them ([canonical]), and pointed at the one in use when fetched
/// ([link]), so switching never re-downloads a cover or orphans a download.
class ServerRoute {
  ServerRoute({
    http.Client Function()? client,
    Stream<Object?> Function()? networkChanges,
  }) : _newClient = client ?? http.Client.new,
       _networkChanges = networkChanges ?? _platformChanges;

  static final ServerRoute instance = ServerRoute();

  final http.Client Function() _newClient;

  /// Wi-Fi joined or left, Tailscale switched on or off. Without listening,
  /// the first sign of Tailscale going off was a request waiting out its
  /// whole timeout (about 16 seconds on the Server tab); with it, the next
  /// request asks both addresses, which takes at most [preferFirstFor].
  final Stream<Object?> Function() _networkChanges;
  StreamSubscription<Object?>? _watching;
  bool _networkChanged = false;

  static Stream<Object?> _platformChanges() =>
      Connectivity().onConnectivityChanged;

  void _watchNetwork() {
    if (_watching != null) return;
    _watching = const Stream<Object?>.empty().listen(null);
    // Guarded: with no plugin (a test, a desktop build) the platform channel
    // fails a moment later rather than here. Failures still recover without it.
    runZonedGuarded(() {
      _watching = _networkChanges().listen(
        (_) => _networkChanged = true,
        onError: (_) {},
      );
    }, (_, _) {});
  }

  /// How long the first address gets before the second is taken instead.
  static const preferFirstFor = Duration(milliseconds: 2500);

  /// How long either address gets to answer at all.
  static const answerWithin = Duration(seconds: 5);

  /// How often to look again for the first address while on the second.
  static const lookAgainAfter = Duration(minutes: 5);

  String _first = '';
  String _second = '';
  String _using = '';
  DateTime _decidedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String>? _deciding;

  /// Bumped when the address in use changes, for screens that show it.
  final ValueNotifier<String> using = ValueNotifier<String>('');

  /// True while the second address is the one in use.
  bool get onSecond => _second.isNotEmpty && _using == _second;

  /// The address to use now for [settings], without asking the network.
  String baseFor(OpdsSettings settings) {
    _adopt(settings);
    return _using.isEmpty ? settings.baseUrl : _using;
  }

  /// Makes sure the choice has been made, asking both addresses if needed.
  Future<String> ready(OpdsSettings settings) {
    _adopt(settings);
    if (_second.isEmpty) return Future.value(settings.baseUrl);
    _watchNetwork();
    final stale =
        _using.isEmpty ||
        _networkChanged ||
        (onSecond && DateTime.now().difference(_decidedAt) > lookAgainAfter);
    if (!stale) return Future.value(_using);
    return _decide(settings);
  }

  /// Waits for a choice already being made, for callers with no settings to
  /// start one (covers, which only hold a link).
  Future<void> settled() => _deciding ?? Future<void>.value();

  /// A request could not reach [failed]: ask both again. True if the address
  /// in use is now a different one, so the request is worth one more try.
  Future<bool> recover(OpdsSettings settings, String failed) async {
    _adopt(settings);
    if (_second.isEmpty) return false;
    final now = await _decide(settings);
    return now != failed;
  }

  /// Runs [call] against the address in use. If it can't reach the computer
  /// there and the other address answers, runs it once more against that.
  Future<T> run<T>(
    OpdsSettings settings,
    Future<T> Function(String base) call, {
    required bool Function(Object error) unreachable,
  }) async {
    final base = await ready(settings);
    try {
      return await call(base);
    } catch (e) {
      if (!unreachable(e) || !await recover(settings, base)) rethrow;
      return call(_using);
    }
  }

  /// [url] as stored: under the first address, whichever one fetched it.
  String canonical(String url) => _swap(url, from: _second, to: _first);

  /// [url] pointed at the address in use.
  String link(String url) {
    if (_second.isEmpty || _using.isEmpty) return url;
    final other = _using == _first ? _second : _first;
    return _swap(url, from: other, to: _using);
  }

  static String _swap(String url, {required String from, required String to}) {
    if (from.isEmpty || to.isEmpty || from == to) return url;
    if (url == from) return to;
    return url.startsWith('$from/') ? to + url.substring(from.length) : url;
  }

  void _adopt(OpdsSettings settings) {
    if (settings.baseUrl == _first && settings.secondUrl == _second) return;
    _first = settings.baseUrl;
    _second = settings.secondUrl == settings.baseUrl ? '' : settings.secondUrl;
    _using = _second.isEmpty ? _first : '';
    _deciding = null;
    using.value = _using;
  }

  Future<String> _decide(OpdsSettings settings) {
    return _deciding ??= _askBoth(settings).whenComplete(() => _deciding = null);
  }

  Future<String> _askBoth(OpdsSettings settings) async {
    _networkChanged = false;
    final first = _answers(_first, settings);
    final second = _answers(_second, settings);
    var choice = _first;
    final firstQuickly = await first
        .timeout(preferFirstFor, onTimeout: () => false);
    if (!firstQuickly) {
      if (await second) {
        choice = _second;
      } else if (await first) {
        // Slow, but there: the first address it is.
        choice = _first;
      }
      // Neither answered: stay on the first, and let the request say so.
    }
    if (settings.baseUrl != _first || settings.secondUrl != _second) {
      return baseFor(settings); // settings changed while asking
    }
    _using = choice;
    _decidedAt = DateTime.now();
    using.value = _using;
    return _using;
  }

  /// Whether anything is listening at [base]. Any HTTP answer counts, even a
  /// refusal: a wrong password is still the right computer.
  Future<bool> _answers(String base, OpdsSettings settings) async {
    final client = _newClient();
    try {
      await client
          .get(Uri.parse('$base/opds'), headers: OpdsClient(settings).authHeaders)
          .timeout(answerWithin);
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Forgets everything; for tests.
  @visibleForTesting
  void reset() {
    _first = _second = _using = '';
    _deciding = null;
    _networkChanged = false;
    _decidedAt = DateTime.fromMillisecondsSinceEpoch(0);
    using.value = '';
  }
}
