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
// Position is kept as a panel index rather than a scroll offset. These
// chapters lazy-load their images, so a page reopened is briefly a fraction
// of its full height and a saved pixel position lands somewhere arbitrary.
// Panels survive that, and the restore below waits for the one it wants to
// exist rather than assuming it already does.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/web_series_store.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.series.openUrl;
    if (widget.series.lastChapterUrl == _currentUrl &&
        widget.series.lastPanel > 0) {
      _restoreTo = widget.series.lastPanel;
    }
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _restoreIfWanted();
          },
          // Chapter pagers on these sites are often pushState navigations
          // that never reload, so the address has to be tracked here rather
          // than inferred from a page load.
          onUrlChange: (change) {
            final url = change.url;
            if (url == null || url == _currentUrl) return;
            // Leaving the page the saved position described.
            _restoreTo = null;
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
      for (var n = 0; n < p.length; n++) {
        if (p[n].getBoundingClientRect().bottom > 0) return n;
      }
      return p.length ? p.length - 1 : 0;
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
      $_panelsJs
      var target = $target, tries = 0;
      // Held up for the duration so a save cannot land mid-restore and
      // record the top of a half-loaded page as the place you stopped.
      window.__umbraRestoring = 1;
      (function tick() {
        var p = __panels();
        if (p.length > target) {
          p[target].scrollIntoView();
          window.__umbraRestoring = 0;
          return;
        }
        if (++tries < 40) { setTimeout(tick, 250); return; }
        // Given up: this chapter is shorter than the one stopped in.
        window.__umbraRestoring = 0;
      })();
    })()''';

  Future<void> _restoreIfWanted() async {
    final target = _restoreTo;
    if (target == null || target <= 0) return;
    _restoreTo = null;
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
    await _store.notePosition(
      seriesUrl: widget.series.url,
      chapterUrl: _currentUrl,
      panel: await _currentPanel(),
    );
  }

  // ── ui ───────────────────────────────────────────────────────────────

  Future<void> _goToSeriesPage() async {
    _restoreTo = null;
    await _web.loadRequest(Uri.parse(widget.series.url));
  }

  Future<bool> _back() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
      return false;
    }
    return true;
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
        appBar: AppBar(
          title: Text(
            widget.series.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          bottom: _loading
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
          actions: [
            IconButton(
              tooltip: 'All chapters',
              icon: const Icon(Icons.list),
              onPressed: _goToSeriesPage,
            ),
          ],
        ),
        body: SafeArea(child: WebViewWidget(controller: _web)),
      ),
    );
  }
}
