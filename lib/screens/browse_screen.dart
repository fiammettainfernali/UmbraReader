import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/app_motion.dart';
import '../services/control_client.dart';
import '../services/settings_service.dart';
import '../services/pending_add_store.dart';
import '../services/site_patterns.dart';
import '../services/web_series_metadata.dart';
import '../services/web_series_store.dart';
import '../widgets/duplicate_sheet.dart';

/// An in-app browser for finding novels on the source sites and sending
/// them to Novel Grabber.
///
/// This is the browser extension's flow, on the phone: browse the real
/// site — a genuine WKWebView, so Cloudflare-gated pages render and a JS
/// challenge can be passed by hand — then send the current page's URL to
/// the server's `/api/novels`, exactly as the extension and "Add by URL"
/// already do. Finding happens here; downloading and reading stay in the
/// library, where progress and sync live.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.settings, this.initialUrl});

  final OpdsSettings settings;

  /// Where to start; defaults to the first supported site.
  final String? initialUrl;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> with HoldsMotionStill {
  late final ControlClient _client = ControlClient(widget.settings);
  late final WebViewController _web;
  final TextEditingController _urlField = TextEditingController();

  Uri? _current;
  bool _loading = true;
  bool _sending = false;

  /// The library entry for the page on screen, when there is one. Checked
  /// as you browse so a page you already have says so *before* you tap
  /// add — which is the whole point, since remembering 486 novels is not
  /// something anyone does.
  DuplicateMatch? _alreadyHave;

  /// Guards against a slow lookup for a page you have since left
  /// overwriting the answer for the page you are actually on.
  int _lookupToken = 0;

  final WebSeriesStore _webSeries = WebSeriesStore();

  /// Whether the series this page belongs to is already followed. Kept
  /// alongside [_alreadyHave] because the two answer different questions:
  /// one is "has the server scraped this", the other "am I reading this
  /// here". A comic can only ever be the second.
  bool _followed = false;
  bool _following = false;

  @override
  void initState() {
    super.initState();
    final start = Uri.parse(
      widget.initialUrl ?? 'https://${kNovelSites.first.host}',
    );
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          // Fires on every address change, including pushState navigations
          // that never reload the page — which is how these sites' chapter
          // pagers work, so the add button must track it rather than
          // onPageFinished alone.
          onUrlChange: (change) {
            final url = change.url;
            if (url == null) return;
            setState(() {
              _current = Uri.tryParse(url);
              _urlField.text = url;
              _alreadyHave = null;
            });
            _checkAlreadyHave();
            _checkFollowed();
          },
        ),
      )
      ..loadRequest(start);
    _current = start;
    _urlField.text = start.toString();
    _checkAlreadyHave();
    _checkFollowed();
  }

  /// The series the current page belongs to — a chapter resolves to the
  /// series it is a chapter of, so Follow can be tapped without first
  /// navigating back out to the series page.
  Uri? get _followTarget {
    final page = _current;
    return page == null ? null : WebSeriesMetadata.seriesPageFor(page);
  }

  Future<void> _checkFollowed() async {
    final target = _followTarget;
    if (target == null) return;
    final followed = await _webSeries.isFollowed(target.toString());
    if (!mounted) return;
    setState(() => _followed = followed);
  }

  /// Follows the current series: keeps the URL, and asks its page for a
  /// cover, a title and how many chapters there are.
  ///
  /// The fetch is allowed to fail. Everything it provides is a nicety —
  /// what makes the follow work is the URL, which is already known — so a
  /// site that is slow or unreachable costs a cover and not the follow.
  Future<void> _followCurrent() async {
    final target = _followTarget;
    if (target == null) return;
    setState(() => _following = true);
    try {
      final info = await WebSeriesMetadata().fetch(target);
      await _webSeries.follow(
        url: target.toString(),
        title: await _pageTitle() ?? target.toString(),
        info: info,
      );
      if (!mounted) return;
      setState(() => _followed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            info?.latestChapterNumber == null
                ? 'Following — it will show in your library.'
                : 'Following — latest is chapter '
                      '${_plain(info!.latestChapterNumber!)}.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  Future<void> _unfollowCurrent() async {
    final target = _followTarget;
    if (target == null) return;
    await _webSeries.unfollow(target.toString());
    if (!mounted) return;
    setState(() => _followed = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Unfollowed.')));
  }

  /// 260.0 is a chapter number nobody writes down that way.
  static String _plain(double n) =>
      n == n.roundToDouble() ? '${n.round()}' : '$n';

  /// Asks the server whether the current page is already in the library.
  /// Silent on failure: an older server without the endpoint, or no
  /// connection, should cost the hint and nothing else.
  Future<void> _checkAlreadyHave() async {
    final page = _current;
    if (page == null) return;
    final target = novelPageFor(page) ?? page;
    final token = ++_lookupToken;
    try {
      final result = await _client.lookup(target.toString());
      if (!mounted || token != _lookupToken) return;
      setState(() => _alreadyHave = result.known ? result.novel : null);
    } on ControlException {
      // no hint available
    }
  }

  @override
  void dispose() {
    _urlField.dispose();
    super.dispose();
  }

  void _go(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return;
    if (!text.contains('://')) text = 'https://$text';
    final url = Uri.tryParse(text);
    if (url == null) return;
    _web.loadRequest(url);
  }

  Future<void> _addCurrent({bool force = false}) async {
    final page = _current;
    if (page == null) return;
    // From a chapter, offer the novel's main page when it can be derived —
    // that is the URL the scraper actually wants.
    final target = novelPageFor(page) ?? page;
    setState(() => _sending = true);
    try {
      await _client.addNovel(target.toString(), force: force);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sent to your computer — scraping started. '
            'Watch it on the Discover tab.',
          ),
        ),
      );
      await _checkAlreadyHave();
    } on DuplicateNovelException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      final proceed = await confirmDuplicateAdd(
        context,
        title: _alreadyHave?.title ?? target.toString(),
        matches: e.matches,
        sameUrl: e.isSameUrl,
      );
      if (proceed && mounted) await _addCurrent(force: true);
      return;
    } on ControlException catch (e) {
      if (!mounted) return;
      if (e.isUnreachable) {
        // Out of reach, not refused — keep the intent and send it when the
        // server next answers. Finding something worth reading shouldn't
        // have to wait for the desktop to be awake.
        await PendingAddStore().enqueue(
          target.toString(),
          label: await _pageTitle() ?? target.toString(),
          force: force,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Your computer isn't reachable — saved, and it'll be added "
              'next time the app connects.',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// The page's own <title>, so a pending row reads as a book rather than
  /// a URL. Null when the WebView can't say.
  Future<String?> _pageTitle() async {
    try {
      final title = await _web.getTitle();
      final trimmed = (title ?? '').trim();
      return trimmed.isEmpty ? null : trimmed;
    } on Exception {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = _current == null ? PageKind.unsupported : classify(_current!);
    final site = _current == null ? null : siteFor(_current!);

    final have = _alreadyHave;
    // Short enough to be a button. The long form of the unsupported case
    // used to be the label itself, which wrapped to two lines on a phone
    // and shouted the wrong action while it did — it is a caption now.
    final (String label, IconData icon) = have != null
        ? ('In library', Icons.library_add_check)
        : switch (kind) {
            PageKind.novel => ('Add novel', Icons.library_add),
            PageKind.supportedSite => ('Add page', Icons.add_link),
            PageKind.unsupported => ('Send anyway', Icons.help_outline),
          };

    // Which action leads. On a site the scraper does not know — every comic
    // site — sending it to Novel Grabber is the trap and following is the
    // thing worth doing, so the emphasis follows the page instead of always
    // sitting on Add.
    final followLeads = have == null && kind == PageKind.unsupported;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _urlField,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.go,
            onSubmitted: _go,
            style: theme.textTheme.bodySmall,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHigh,
              prefixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Icon(
                      kind == PageKind.unsupported
                          ? Icons.public
                          : Icons.verified_outlined,
                      size: 18,
                      color: kind == PageKind.unsupported
                          ? null
                          : theme.colorScheme.tertiary,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            tooltip: 'Back',
            onPressed: () async {
              if (await _web.canGoBack()) await _web.goBack();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Reload',
            onPressed: _web.reload,
          ),
        ],
      ),
      body: Column(
        children: [
          // The supported sites, one tap away — this doubles as the list of
          // what the server can scrape.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in kNovelSites)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.name),
                      selected: site?.name == s.name,
                      onSelected: (_) => _go('https://${s.host}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: WebViewWidget(controller: _web)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The caveat, said once, as a caption. It was the Add
              // button's own label until a phone showed what that looks
              // like: a sentence wrapped over two lines, in the loudest
              // colour on screen, recommending the one action the page did
              // not want.
              if (followLeads)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Text(
                    "Your computer can't scrape this site — follow it to "
                    'read it here instead.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: _action(
                      theme: theme,
                      filled: !followLeads,
                      icon: icon,
                      label: label,
                      busy: _sending,
                      muted: have != null,
                      onPressed: _sending ? null : _addCurrent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // The other thing you can do with a page you like: keep
                  // reading it where it is. Nothing is scraped, downloaded
                  // or compiled — the library just remembers the series,
                  // your place in it, and when it grows.
                  Expanded(
                    child: _action(
                      theme: theme,
                      filled: followLeads,
                      icon: _followed
                          ? Icons.bookmark_added
                          : Icons.bookmark_add_outlined,
                      label: _followed ? 'Following' : 'Follow',
                      busy: _following,
                      tint: _followed ? theme.colorScheme.tertiary : null,
                      onPressed: _following
                          ? null
                          : (_followed ? _unfollowCurrent : _followCurrent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One of the two bottom actions.
  ///
  /// Both are the same size and both carry a word, so which one is meant is
  /// a question of emphasis rather than of guessing what an icon does.
  Widget _action({
    required ThemeData theme,
    required bool filled,
    required IconData icon,
    required String label,
    required bool busy,
    required VoidCallback? onPressed,
    bool muted = false,
    Color? tint,
  }) {
    final child = busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 18);
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: child,
        label: text,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: muted
              ? theme.colorScheme.surfaceContainerHighest
              : null,
          foregroundColor: muted ? theme.colorScheme.onSurfaceVariant : null,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: child,
      label: text,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: tint ?? (muted ? theme.colorScheme.outline : null),
      ),
    );
  }
}
