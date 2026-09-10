// Reading a followed comic on its own site, without losing your place.
//
// The reader proper is built for prose: it paginates lines, measures text
// and compiles books. A comic chapter is forty-odd images and no prose, so
// none of that applies — but the one thing a browser will not do for you is
// remember, across days and devices' worth of tabs, that you were on panel
// 31 of chapter 212. That is all this adds. The pages stay on the site, and
// the site renders them itself, which is also why no anti-bot machinery is
// needed here: it is a real browser.
//
// Position is kept as a panel index rather than a scroll offset, because a
// chapter's height is not stable: it settles as images decode, so a saved
// pixel offset means something different by the time it is used. A panel is
// the same panel either way.
//
// The restore is stubborn for a reason worth writing down, because it cost
// three wrong attempts to find. This page finishes loading TWICE, seconds
// apart, and the second finish puts the scroll back at the top. A restore
// that lands on the first finish and considers itself done is undone
// shortly afterwards — and, since the position is saved on a timer, the
// top of the page is then written over the place the reader had actually
// reached. Each attempt destroyed the evidence for the next one.
//
// So it does not trust a single landing. It re-asserts until the panel has
// held for three consecutive checks, treats a bounce back to the top as
// the second load rather than as a decision, and stops the moment the page
// is somewhere else entirely — which is the reader scrolling, and must
// never be fought.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/web_series_store.dart';
import '../services/web_view_guard.dart';

class WebSeriesScreen extends StatefulWidget {
  const WebSeriesScreen({super.key, required this.series, this.store});

  final WebSeries series;
  final WebSeriesStore? store;

  @override
  State<WebSeriesScreen> createState() => _WebSeriesScreenState();
}

class _WebSeriesScreenState extends State<WebSeriesScreen>
    with WidgetsBindingObserver {
  late final WebSeriesStore _store = widget.store ?? WebSeriesStore();
  late final WebViewController _web;

  /// Saved on a timer as well as on the way out. A reading session that
  /// ends because the phone was locked or the app was killed is the common
  /// one, and neither of those runs dispose.
  Timer? _ticker;

  String _currentUrl = '';
  bool _loading = true;

  /// The panel to return to, cleared once it has been used or once the
  /// reader has navigated somewhere the saved position does not describe.
  int? _restoreTo;

  /// The site this comic was opened for. Navigations anywhere else are
  /// refused — see [sameSite].
  late final Uri _origin = Uri.parse(widget.series.url);

  /// When the reader was last told something was blocked. An ad script that
  /// is being refused tends to try again immediately, and a queue of
  /// identical snackbars is worse than the redirect was.
  DateTime? _lastBlockNotice;

  /// Whether the bar is on screen. It leaves while you read downward and
  /// comes back when you read up — a panel is the full width of a phone
  /// and as tall as it likes, so a bar that sits there permanently is
  /// simply less comic.
  bool _chromeVisible = true;

  /// Whether a page has finished loading yet. Until one has, an address
  /// change is the first load settling rather than the reader going
  /// somewhere.
  bool _settled = false;

  /// Stops the restore holding on forever. It waits through a second page
  /// load on purpose, so it cannot simply give up on the first finish —
  /// but a page that never reports back must not leave a target armed to
  /// yank the reader somewhere minutes later.
  Timer? _restoreGiveUp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.series.openUrl;
    if (widget.series.lastChapterUrl == _currentUrl &&
        widget.series.lastPanel > 0) {
      _restoreTo = widget.series.lastPanel;
      _restoreGiveUp = Timer(
        const Duration(seconds: 30),
        () => _restoreTo = null,
      );
    }
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _chromeChannel,
        onMessageReceived: (message) {
          // The position stuck, or the reader moved on. Either way there is
          // nothing left to restore, and holding the target would fight the
          // next thing they do.
          if (message.message == 'done') {
            _restoreTo = null;
            return;
          }
          final wanted = message.message == 'show';
          if (wanted == _chromeVisible || !mounted) return;
          setState(() => _chromeVisible = wanted);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _restoreIfWanted();
            _hookChrome();
            _settled = true;
          },
          // Only the top frame is gated. An ad in an iframe navigating
          // itself is contained already; an ad throwing the *page* at a
          // store listing is the thing worth refusing, and that arrives
          // here as a main-frame request. Subresources — every panel in the
          // chapter, served from a different host on this site — never pass
          // through this callback at all, which is what makes it safe to be
          // this strict.
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final target = Uri.tryParse(request.url);
            if (target != null && sameSite(_origin, target)) {
              return NavigationDecision.navigate;
            }
            _reportBlocked(target?.host ?? request.url);
            return NavigationDecision.prevent;
          },
          // Chapter pagers on these sites are often pushState navigations
          // that never reload, so the address has to be tracked here rather
          // than inferred from a page load.
          onUrlChange: (change) {
            final url = change.url;
            if (url == null || url == _currentUrl) return;
            // Leaving the page the saved position described — but only
            // once one has actually been shown. The address settles during
            // the first load (a redirect, a trailing slash, the site
            // normalising its own URL), and treating that as navigation
            // cancelled the restore before it had a chance to run.
            if (_settled) _restoreTo = null;
            _currentUrl = url;
            _save();
          },
        ),
      )
      ..loadRequest(Uri.parse(_currentUrl));
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) => _save());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _save();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _restoreGiveUp?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Not awaited: dispose cannot, and the write is a single row.
    unawaited(_save());
    super.dispose();
  }

  // ── position ─────────────────────────────────────────────────────────

  /// Panels, as the page sees them.
  ///
  /// Filtered by size on purpose: a chapter page is full of images that are
  /// not panels — the site's logo, avatars on the comment thread, thumbnails
  /// in the "read next" rail — and counting those would make the index mean
  /// nothing. A panel is the width of the column it is read in.
  static const String _panelsJs = '''
    function __panels() {
      return Array.prototype.slice.call(document.images).filter(function (i) {
        return i.clientWidth > window.innerWidth * 0.5 && i.clientHeight > 200;
      });
    }''';

  /// The panel at the top of the view, or -1 while a restore is still
  /// working.
  ///
  /// That -1 is the whole point. Saving runs on a timer, and a chapter
  /// reopened is a handful of panels long while the rest load — so a save
  /// that landed during the restore would read "panel 0", write it over the
  /// panel 31 it was in the middle of returning to, and quietly lose the
  /// place it was restoring.
  static const String _readPanelJs =
      '''
    (function () {
      $_panelsJs
      if (window.__umbraRestoring) return -1;
      var p = __panels();
      // The panel filling most of the screen, not the first one still
      // technically on it. A panel is taller than the viewport, so at the
      // moment you stop reading there is usually a sliver of the previous
      // one left at the top — and taking that as the answer put every
      // restore one panel further back than where the reader had been.
      var best = 0, most = -1;
      for (var n = 0; n < p.length; n++) {
        var r = p[n].getBoundingClientRect();
        var seen = Math.min(r.bottom, window.innerHeight) - Math.max(r.top, 0);
        if (seen > most) { most = seen; best = n; }
      }
      return best;
    })()''';

  /// Scrolls the wanted panel into view once it exists.
  ///
  /// It usually does not exist yet: the images below the fold load as you
  /// approach them, so at page-finished the chapter may be four panels long
  /// on its way to fifty. Polling in the page is simpler and far less
  /// chatty than polling it from Dart, and it gives up rather than spinning
  /// on a chapter that really is shorter than the one left off in.
  static String _restoreJs(int target) =>
      '''
    (function () {
      // Already working. The page finishing twice re-runs this, and two
      // loops chasing the same panel is waste at best.
      if (window.__umbraRestoring) return;
      $_panelsJs
      var target = $target, tries = 0;
      // Held up for the duration so a save cannot land mid-restore and
      // record the top of a half-loaded page as the place you stopped.
      window.__umbraRestoring = 1;
      var settled = 0;
      function done() {
        window.__umbraRestoring = 0;
        try { $_chromeChannel.postMessage('done'); } catch (e) {}
      }
      (function tick() {
        var p = __panels();
        if (p.length > target) {
          var box = p[target].getBoundingClientRect();
          if (Math.abs(box.top) < 40) {
            // Arrived. Watched for a moment rather than trusted: the page
            // finishes loading twice, and the second one puts the scroll
            // back at the top after the first restore has already landed.
            if (++settled >= 3) return done();
          } else if (window.scrollY < 200) {
            // Back at the top without the reader having done anything —
            // that is the second load, not a decision. Land again.
            p[target].scrollIntoView();
            settled = 0;
          } else {
            // Somewhere else entirely: the reader has moved on, and this
            // must not drag them back.
            return done();
          }
        } else if (p.length) {
          // The panel is not in the list yet. Walking down to the last one
          // that is pulls in the next few, which gets there sooner than
          // waiting on a page that only loads what is approached.
          p[p.length - 1].scrollIntoView(false);
        } else {
          window.scrollBy(0, window.innerHeight);
        }
        // Long enough to outlast the second load. The page finishes twice,
        // several seconds apart, and giving up before the second one is
        // what let it end at the top with the position already spent.
        if (++tries < 90) {
          setTimeout(tick, 200);
          return;
        }
        // Given up: this chapter is shorter than the one stopped in, or it
        // never loaded. Wherever the walk reached is closer than the top.
        done();
      })();
    })()''';

  /// The channel the page reports scrolling on.
  static const String _chromeChannel = 'UmbraChrome';

  /// Teaches the page to say which way it is being read.
  ///
  /// A scroll listener in the page rather than a poll from here: reading a
  /// comic is one long scroll, and asking every few hundred milliseconds
  /// whether it has moved would be both later and more expensive than being
  /// told. Guarded so a re-run on the same page does not stack listeners,
  /// and given a threshold so the bar does not flicker on the small
  /// corrections a finger makes while it settles.
  Future<void> _hookChrome() async {
    try {
      await _web.runJavaScript('''
        (function () {
          if (window.__umbraChromeHooked) return;
          window.__umbraChromeHooked = 1;
          var last = window.scrollY, ticking = false;
          window.addEventListener('scroll', function () {
            if (ticking) return;
            ticking = true;
            requestAnimationFrame(function () {
              var y = window.scrollY, dy = y - last;
              if (Math.abs(dy) > 12) {
                // Reading downward hides it; reading back up, or being near
                // the top at all, brings it back.
                $_chromeChannel.postMessage(dy > 0 && y > 80 ? 'hide' : 'show');
                last = y;
              }
              ticking = false;
            });
          }, { passive: true });
        })()''');
    } on Exception {
      // A page that will not run it simply keeps the bar.
    }
  }

  /// Says once, quietly, that a redirect was refused.
  ///
  /// Worth saying at all rather than silently swallowing: a link that does
  /// nothing looks like a broken app, and if a site turns out to route its
  /// own chapters through another domain this is the only way that would
  /// ever be noticed.
  void _reportBlocked(String where) {
    if (!mounted) return;
    final now = DateTime.now();
    final last = _lastBlockNotice;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastBlockNotice = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Stayed on ${_origin.host} — blocked $where'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _restoreIfWanted() async {
    final target = _restoreTo;
    if (target == null || target <= 0) return;
    // Deliberately NOT cleared here. The page finishes loading twice, and
    // the second one puts the scroll back at the top — so a restore that
    // spends its target on the first finish lands correctly, is undone
    // seconds later, and has nothing left to land with. It is cleared when
    // the page says the position stuck, or by [_restoreGiveUp].
    try {
      await _web.runJavaScript(_restoreJs(target));
    } on Exception {
      // A page that will not run it is one we simply open at the top.
    }
  }

  /// Null when the page cannot say — a restore in flight, or a page that
  /// will not run script. Never 0 in those cases: 0 is a real answer, and
  /// writing it over a saved position is how a place gets lost.
  Future<int?> _currentPanel() async {
    try {
      final raw = await _web.runJavaScriptReturningResult(_readPanelJs);
      // Android hands back a String, iOS a num, and either can arrive
      // quoted. Parsing the toString covers all three without caring.
      final text = raw.toString().replaceAll('"', '').trim();
      final panel = int.tryParse(text);
      if (panel == null || panel < 0) return null;
      return panel;
    } on Exception {
      return null;
    }
  }

  /// The chapter is always recorded; the panel only when it is known.
  Future<void> _save() async {
    if (_currentUrl.isEmpty) return;
    final panel = await _currentPanel();
    await _store.notePosition(
      seriesUrl: widget.series.url,
      chapterUrl: _currentUrl,
      panel: panel,
    );
  }

  // ── ui ───────────────────────────────────────────────────────────────

  Future<void> _goToSeriesPage() async {
    _restoreTo = null;
    await _web.loadRequest(Uri.parse(widget.series.url));
  }

  /// Steps back a page, or reports that there is nowhere left to go.
  ///
  /// Only the system back gesture uses this. Walking the page history is
  /// what that gesture means everywhere else on the phone, so it means it
  /// here too.
  Future<bool> _back() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
      return false;
    }
    return true;
  }

  /// Leaves the comic and returns to the library.
  ///
  /// Deliberately not [Navigator.maybePop]: that consults the [PopScope]
  /// below, which spends the page history first. An arrow in the reader's
  /// own bar does not mean "the page before this one" — after four chapters
  /// that made it a button which visibly did something and yet never
  /// arrived anywhere, and the way out was to press it once per page you
  /// had read.
  Future<void> _leave() async {
    final navigator = Navigator.of(context);
    await _save();
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Taken before the first await: back inside a comic means back a
        // page, and only once the page history is spent does it mean
        // leaving — by which time this context may be gone.
        final navigator = Navigator.of(context);
        if (!await _back()) return;
        await _save();
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        // Laid over the page rather than above it. An AppBar that comes and
        // goes changes the height the page is given, and a comic re-flowed
        // mid-read jumps under the eye — which is the thing the saved panel
        // exists to prevent, undone by the chrome that was meant to get out
        // of its way.
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: _web)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_chromeVisible,
                  child: AnimatedSlide(
                    offset: _chromeVisible ? Offset.zero : const Offset(0, -1),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: AnimatedOpacity(
                      opacity: _chromeVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: _bar(Theme.of(context)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The comic's own bar: back, what you are reading, and the chapter list.
  ///
  /// Everything else a reader needs here — the next and previous chapter,
  /// the comments — the site already puts on the page, and duplicating them
  /// would spend the little height a phone has saying things twice.
  Widget _bar(ThemeData theme) {
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      elevation: 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to library',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _leave,
                ),
                Expanded(
                  child: Text(
                    widget.series.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'All chapters',
                  icon: const Icon(Icons.list),
                  onPressed: _goToSeriesPage,
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
