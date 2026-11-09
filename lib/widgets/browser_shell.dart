import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/app_motion.dart';
import '../services/browser_native.dart';
import '../services/browser_policy.dart';
import '../services/browser_scripts.dart';
import '../services/browser_store.dart';
import 'action_sheet.dart';
import 'hawthorne_parts.dart';
import 'living_surfaces.dart';

/// One open page in a browser.
class BrowserTab {
  BrowserTab(this.id);

  final int id;
  WebViewController? controller;
  Future<WebViewController>? _building;

  /// Null on a tab that hasn't gone anywhere yet.
  Uri? url;
  String title = '';

  /// Showing the browser's home instead of the page, which stays loaded behind.
  bool atHome = true;
  bool loading = false;
  int progress = 0;
  String? error;
  bool canGoBack = false;
  bool canGoForward = false;

  /// Until when jumps to other sites count as something the reader asked for.
  DateTime trustedUntil = DateTime.fromMillisecondsSinceEpoch(0);
}

/// Something a browser adds to one of the shared menus.
class BrowserAction {
  const BrowserAction({
    required this.label,
    required this.icon,
    required this.run,
    this.subtitle,
  });

  final String label;
  final IconData icon;
  final String? subtitle;
  final VoidCallback run;
}

/// The browser both the novel and comic browsers are built on: tabs, an address
/// bar that also searches, back and forward, favourites, history and the ad
/// blocker. It knows nothing about novels or comics. What's special to each
/// comes in through its home page, its panel and its scripts, and each keeps its
/// own history, favourites and sign-ins.
class BrowserShell extends StatefulWidget {
  const BrowserShell({
    super.key,
    required this.store,
    required this.homeBuilder,
    this.profile,
    this.initialUrl,
    this.pageScripts,
    this.panelBuilder,
    this.onPageChanged,
    this.onMessage,
    this.linkActions,
    this.pageActions,
  });

  final BrowserStore store;

  /// Null shares sign-ins with the app's other web views.
  final String? profile;
  final Uri? initialUrl;
  final Widget Function(BuildContext context, void Function(Uri) open)
  homeBuilder;

  /// Extra scripts for a page, run each time it finishes loading.
  final List<String> Function(Uri page)? pageScripts;

  /// What sits above the toolbar for the tab on show.
  final Widget Function(BuildContext context, BrowserTab tab)? panelBuilder;

  /// The tab on show moved somewhere, or a different tab came to the front.
  final void Function(BrowserTab tab)? onPageChanged;

  /// A message from a page's scripts.
  final void Function(BrowserTab tab, Map<String, dynamic> message)? onMessage;
  final List<BrowserAction> Function(Uri url, String text)? linkActions;
  final List<BrowserAction> Function(BrowserTab tab)? pageActions;

  @override
  State<BrowserShell> createState() => BrowserShellState();
}

class BrowserShellState extends State<BrowserShell> {
  /// Each open tab keeps a whole page in memory, so there's a limit.
  static const maxTabs = 8;

  final List<BrowserTab> _tabs = [];
  int _active = 0;
  int _nextId = 0;

  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  final ScrollController _addressScroll = ScrollController();

  bool _blocking = true;
  bool _favourite = false;
  bool _holdingStill = false;
  int _homeGeneration = 0;
  DateTime? _lastJumpNotice;

  BrowserTab get activeTab => _tabs[_active];

  @override
  void initState() {
    super.initState();
    _tabs.add(BrowserTab(_nextId++));
    _addressFocus.addListener(_onAddressFocus);
    widget.store.blocksAds().then((value) {
      if (mounted) setState(() => _blocking = value);
    });
    final start = widget.initialUrl;
    // After the first frame: opening tells the screen above this one, which is
    // still building at this point.
    if (start != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(open(start));
      });
    }
  }

  @override
  void dispose() {
    if (_holdingStill) AppMotion.stillScreens.value--;
    for (final tab in _tabs) {
      unawaited(_release(tab));
    }
    _address.dispose();
    _addressFocus.dispose();
    _addressScroll.dispose();
    super.dispose();
  }

  // ── what the browsers built on this can call ─────────────────────────────

  /// Goes to [url] in the tab on show, as something the reader asked for.
  Future<void> open(Uri url) => _load(activeTab, url);

  /// Opens [url] in a new tab behind this one.
  Future<void> openInBackground(Uri url) async {
    if (!_hasRoomForTab()) return;
    final tab = BrowserTab(_nextId++);
    setState(() => _tabs.add(tab));
    await _load(tab, url);
    if (mounted) _say('Opened in a new tab');
  }

  /// Runs [script] in one tab's page, if it has one.
  void runIn(BrowserTab tab, String script) {
    final controller = tab.controller;
    if (controller != null) unawaited(_run(controller, script));
  }

  /// Runs [script] in every open page.
  void runInAll(String script) {
    for (final tab in _tabs) {
      runIn(tab, script);
    }
  }

  // ── tabs ─────────────────────────────────────────────────────────────────

  bool _hasRoomForTab() {
    if (_tabs.length < maxTabs) return true;
    _say('That\'s the most tabs you can have open. Close one first.');
    return false;
  }

  void _newTab() {
    if (!_hasRoomForTab()) return;
    setState(() {
      _tabs.add(BrowserTab(_nextId++));
      _active = _tabs.length - 1;
    });
    _tabChanged();
  }

  void _switchTo(int index) {
    setState(() => _active = index);
    _tabChanged();
  }

  void _closeTab(BrowserTab tab) {
    final index = _tabs.indexOf(tab);
    if (index < 0) return;
    unawaited(_release(tab));
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) _tabs.add(BrowserTab(_nextId++));
      if (_active >= _tabs.length) _active = _tabs.length - 1;
      if (index < _active) _active--;
    });
    _tabChanged();
  }

  Future<void> _release(BrowserTab tab) async {
    final controller = tab.controller;
    if (controller == null) return;
    tab.controller = null;
    await BrowserNative.forget(controller);
    // Stops anything still playing or running in the closed page.
    try {
      await controller.loadRequest(Uri.parse('about:blank'));
    } on Exception {
      // It's going away regardless.
    }
  }

  void _tabChanged() {
    _showAddress();
    _syncStill();
    unawaited(_checkFavourite());
    widget.onPageChanged?.call(activeTab);
  }

  // ── loading ──────────────────────────────────────────────────────────────

  Future<WebViewController> _controllerFor(BrowserTab tab) =>
      tab._building ??= _build(tab);

  Future<WebViewController> _build(BrowserTab tab) async {
    final controller = WebViewController();
    final profile = widget.profile;
    if (profile != null) await BrowserNative.useProfile(controller, profile);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // White, as any browser has it. Plenty of pages set dark text and no
    // background of their own, which would be unreadable on the app's black.
    await controller.setBackgroundColor(Colors.white);
    await controller.addJavaScriptChannel(
      kBrowserChannel,
      onMessageReceived: (message) => _onMessage(tab, message.message),
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) => _judge(tab, request),
        onPageStarted: (url) {
          tab
            ..loading = true
            ..progress = 0
            ..error = null;
          if (_blocking) unawaited(_run(controller, kAdBlockScript));
          _tabUpdated(tab);
        },
        onProgress: (value) {
          tab.progress = value;
          if (identical(tab, activeTab) && mounted) setState(() {});
        },
        onPageFinished: (_) => unawaited(_finished(tab, controller)),
        // Fires on address changes that never reload the page, which is how
        // plenty of these sites move between chapters and lists.
        onUrlChange: (change) {
          final url = Uri.tryParse(change.url ?? '');
          if (url == null || url.scheme == 'about') return;
          tab.url = url;
          _tabUpdated(tab);
          unawaited(_refreshPageState(tab, controller));
          unawaited(_rememberOnceSettled(tab, controller, url));
          if (identical(tab, activeTab)) {
            unawaited(_checkFavourite());
            widget.onPageChanged?.call(tab);
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame != true) return;
          tab
            ..loading = false
            ..error = error.description;
          _tabUpdated(tab);
        },
      ),
    );
    if (_blocking) {
      await BrowserNative.setStartScript(controller, kAdBlockScript);
    }
    tab.controller = controller;
    return controller;
  }

  Future<void> _load(BrowserTab tab, Uri url) async {
    tab
      ..url = url
      ..atHome = false
      ..error = null
      ..loading = true
      ..progress = 0
      ..trustedUntil = DateTime.now().add(const Duration(seconds: 6));
    _tabUpdated(tab);
    if (identical(tab, activeTab)) {
      unawaited(_checkFavourite());
      widget.onPageChanged?.call(tab);
    }
    final controller = await _controllerFor(tab);
    if (!mounted) return;
    setState(() {});
    await controller.loadRequest(url);
  }

  NavigationDecision _judge(BrowserTab tab, NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final to = Uri.tryParse(request.url);
    if (to == null) return NavigationDecision.prevent;
    final verdict = judgeNavigation(
      from: tab.url,
      to: to,
      blocking: _blocking,
      userAsked: DateTime.now().isBefore(tab.trustedUntil),
    );
    switch (verdict) {
      case NavVerdict.allow:
        return NavigationDecision.navigate;
      case NavVerdict.refuse:
        return NavigationDecision.prevent;
      case NavVerdict.askFirst:
        _offerJump(tab, to);
        return NavigationDecision.prevent;
    }
  }

  /// An ad that's refused tends to try again straight away, and a pile of the
  /// same message would be worse than the redirect.
  void _offerJump(BrowserTab tab, Uri to) {
    final now = DateTime.now();
    final last = _lastJumpNotice;
    if (last != null && now.difference(last) < const Duration(seconds: 4)) {
      return;
    }
    _lastJumpNotice = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Stopped a jump to ${displayHost(to)}'),
          action: SnackBarAction(
            label: 'Go there',
            onPressed: () => unawaited(_load(tab, to)),
          ),
        ),
      );
  }

  Future<void> _finished(BrowserTab tab, WebViewController controller) async {
    tab.loading = false;
    await _run(controller, kLongPressScript);
    final url = tab.url;
    if (url != null) {
      for (final script in widget.pageScripts?.call(url) ?? const <String>[]) {
        await _run(controller, script);
      }
    }
    await _refreshPageState(tab, controller);
    await _remember(controller);
    _tabUpdated(tab);
    if (identical(tab, activeTab) && mounted) {
      widget.onPageChanged?.call(tab);
    }
  }

  Future<void> _refreshPageState(
    BrowserTab tab,
    WebViewController controller,
  ) async {
    try {
      tab
        ..title = (await controller.getTitle() ?? '').trim()
        ..canGoBack = await controller.canGoBack()
        ..canGoForward = await controller.canGoForward();
    } on Exception {
      return;
    }
    _tabUpdated(tab);
  }

  /// Adds the page to history, by what the web view says it's showing. The tab's
  /// own address moves on as soon as something new is asked for, while the title
  /// is still the old page's, which would file one page under another's name.
  Future<void> _remember(WebViewController controller) async {
    try {
      final url = await controller.currentUrl();
      final title = (await controller.getTitle() ?? '').trim();
      if (url == null || url.isEmpty || url == 'about:blank') return;
      await widget.store.remember(url, title);
    } on Exception {
      // A page that's going away just doesn't go in the history.
    }
  }

  /// For sites that change the address without loading a page, which never say
  /// they've finished. A real load is remembered when it finishes instead.
  Future<void> _rememberOnceSettled(
    BrowserTab tab,
    WebViewController controller,
    Uri url,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted || tab.loading || tab.url != url) return;
    await _refreshPageState(tab, controller);
    await _remember(controller);
  }

  Future<void> _run(WebViewController controller, String script) async {
    try {
      await controller.runJavaScript(script);
    } on Exception {
      // A page mid-navigation can't take a script, and it'll get it on load.
    }
  }

  void _onMessage(BrowserTab tab, String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    if (decoded['type'] == 'longpress') {
      final url = Uri.tryParse(decoded['url'] as String? ?? '');
      if (url != null && url.host.isNotEmpty) {
        unawaited(_linkMenu(url, decoded['text'] as String? ?? ''));
      }
      return;
    }
    widget.onMessage?.call(tab, decoded);
  }

  void _tabUpdated(BrowserTab tab) {
    if (!mounted || !identical(tab, activeTab)) return;
    _showAddress();
    _syncStill();
    setState(() {});
  }

  /// The embers rest while a page is on show. They're hidden behind it, and
  /// someone may stay on one page for a long while.
  void _syncStill() {
    final wanted = !activeTab.atHome;
    if (wanted == _holdingStill) return;
    _holdingStill = wanted;
    AppMotion.stillScreens.value += wanted ? 1 : -1;
  }

  // ── address bar ──────────────────────────────────────────────────────────

  void _showAddress() {
    if (_addressFocus.hasFocus) return;
    final tab = activeTab;
    final url = tab.url;
    final text = tab.atHome || url == null ? '' : shortAddress(url);
    if (_address.text != text) {
      _address.value = TextEditingValue(
        text: text,
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
    // A long address shows its beginning, wherever typing left it scrolled to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_addressScroll.hasClients && !_addressFocus.hasFocus) {
        _addressScroll.jumpTo(0);
      }
    });
  }

  void _onAddressFocus() {
    if (_addressFocus.hasFocus) {
      final tab = activeTab;
      final full = tab.atHome ? '' : tab.url?.toString() ?? '';
      _address.value = TextEditingValue(
        text: full,
        selection: TextSelection(baseOffset: 0, extentOffset: full.length),
      );
    } else {
      _showAddress();
    }
  }

  void _submitAddress(String text) {
    final url = addressFromInput(text);
    if (url != null) unawaited(open(url));
  }

  // ── buttons ──────────────────────────────────────────────────────────────

  void _goHome() {
    final tab = activeTab;
    setState(() {
      tab.atHome = true;
      _homeGeneration++;
    });
    _tabChanged();
  }

  Future<void> _back() async {
    final tab = activeTab;
    if (tab.atHome) return;
    final controller = tab.controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    } else {
      _goHome();
    }
  }

  Future<void> _forward() async {
    final tab = activeTab;
    if (tab.atHome) {
      if (tab.url != null) {
        setState(() => tab.atHome = false);
        _tabChanged();
      }
      return;
    }
    await tab.controller?.goForward();
  }

  void _reload() {
    final tab = activeTab;
    final url = tab.url;
    if (url == null) return;
    setState(() => tab.error = null);
    if (tab.controller == null) {
      unawaited(_load(tab, url));
    } else {
      unawaited(tab.controller!.reload());
    }
  }

  Future<void> _handleSystemBack() async {
    if (_addressFocus.hasFocus) {
      _addressFocus.unfocus();
      return;
    }
    final navigator = Navigator.of(context);
    if (activeTab.atHome) {
      navigator.pop();
      return;
    }
    await _back();
  }

  Future<void> _checkFavourite() async {
    final url = activeTab.url?.toString();
    final favourites = await widget.store.favourites();
    if (!mounted) return;
    setState(() => _favourite = favourites.any((p) => p.url == url));
  }

  Future<void> _toggleFavourite() async {
    final tab = activeTab;
    final url = tab.url;
    if (url == null || tab.atHome) return;
    final now = await widget.store.toggleFavourite(url.toString(), tab.title);
    if (!mounted) return;
    setState(() => _favourite = now);
    _say(now ? 'Added to favourites' : 'Removed from favourites');
  }

  Future<void> _setBlocking(bool value) async {
    await widget.store.setBlocksAds(value);
    if (!mounted) return;
    setState(() => _blocking = value);
    for (final tab in _tabs) {
      final controller = tab.controller;
      if (controller == null) continue;
      await BrowserNative.setStartScript(
        controller,
        value ? kAdBlockScript : null,
      );
    }
    _reload();
    _say(value ? 'Blocking ads and pop-ups' : 'Allowing ads and pop-ups');
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(Uri url) async {
    await Clipboard.setData(ClipboardData(text: url.toString()));
    _say('Link copied');
  }

  // ── menus ────────────────────────────────────────────────────────────────

  List<BrowserAction> _sharedLinkActions(Uri url) => [
    BrowserAction(
      label: 'Copy link',
      icon: Icons.link,
      run: () => unawaited(_copy(url)),
    ),
    BrowserAction(
      label: 'Share link',
      icon: Icons.share_outlined,
      run: () => unawaited(SharePlus.instance.share(ShareParams(uri: url))),
    ),
    BrowserAction(
      label: 'Open in my browser',
      icon: Icons.open_in_browser,
      subtitle: 'Your phone\'s own browser',
      run: () async {
        if (!await BrowserNative.openExternally(url)) {
          _say('Couldn\'t open that in another browser');
        }
      },
    ),
  ];

  Future<void> _runSheet(
    String? title,
    List<List<BrowserAction>> groups,
  ) async {
    final all = [for (final group in groups) ...group];
    final chosen = await showActionSheet<int>(
      context,
      title: title,
      groups: [
        for (final group in groups)
          if (group.isNotEmpty)
            SheetGroup(
              actions: [
                for (final action in group)
                  SheetAction(
                    value: all.indexOf(action),
                    icon: action.icon,
                    label: action.label,
                    subtitle: action.subtitle,
                  ),
              ],
            ),
      ],
    );
    if (chosen != null && mounted) all[chosen].run();
  }

  Future<void> _linkMenu(Uri url, String text) {
    return _runSheet(text.isEmpty ? displayHost(url) : text, [
      [
        BrowserAction(
          label: 'Open in new tab',
          icon: Icons.tab,
          subtitle: 'Stays behind this page',
          run: () => unawaited(openInBackground(url)),
        ),
        ...?widget.linkActions?.call(url, text),
      ],
      _sharedLinkActions(url),
    ]);
  }

  Future<void> _pageMenu() {
    final tab = activeTab;
    final url = tab.url;
    final onPage = url != null && !tab.atHome;
    return _runSheet('Browser', [
      [
        BrowserAction(
          label: _blocking ? 'Blocking ads: on' : 'Blocking ads: off',
          icon: _blocking ? Icons.shield : Icons.shield_outlined,
          subtitle: _blocking
              ? 'Stops pop-ups and hides most ads. Turn off if a site won\'t work'
              : 'Turn on to stop pop-ups and hide most ads',
          run: () => unawaited(_setBlocking(!_blocking)),
        ),
        if (onPage) ...?widget.pageActions?.call(tab),
      ],
      if (onPage) _sharedLinkActions(url),
      [
        BrowserAction(
          label: 'Clear history',
          icon: Icons.history_toggle_off,
          run: () async {
            await widget.store.clearHistory();
            if (!mounted) return;
            setState(() => _homeGeneration++);
            _say('History cleared');
          },
        ),
      ],
    ]);
  }

  Future<void> _tabsSheet() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final theme = Theme.of(sheetContext);
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_tabs.length} of $maxTabs tabs',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _newTab();
                        },
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('New tab'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final (index, tab) in _tabs.indexed)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: panelDecoration(radius: 14).copyWith(
                        border: index == _active
                            ? Border.all(color: const Color(0xFFE5121F))
                            : null,
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          title: Text(
                            tab.atHome || tab.url == null
                                ? 'Home'
                                : tab.title.isEmpty
                                ? displayHost(tab.url!)
                                : tab.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: tab.url == null
                              ? null
                              : Text(
                                  displayHost(tab.url!),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            tooltip: 'Close tab',
                            onPressed: () {
                              _closeTab(tab);
                              setSheet(() {});
                            },
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _switchTo(index);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── drawing ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tab = activeTab;
    final panel = widget.panelBuilder?.call(context, tab);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: _addressBar(theme),
          actions: [
            _TabsButton(count: _tabs.length, onPressed: _tabsSheet),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Browser menu',
              onPressed: _pageMenu,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: SizedBox(
              height: 3,
              child: !tab.atHome && tab.loading
                  ? StripedBar(
                      height: 3,
                      value: tab.progress <= 0 ? null : tab.progress / 100,
                    )
                  : null,
            ),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: tab.atHome,
              child: IndexedStack(
                index: _active,
                sizing: StackFit.expand,
                children: [
                  for (final each in _tabs)
                    KeyedSubtree(
                      key: ValueKey(each.id),
                      child: each.controller == null
                          ? const SizedBox.shrink()
                          : WebViewWidget(controller: each.controller!),
                    ),
                ],
              ),
            ),
            if (tab.atHome)
              KeyedSubtree(
                key: ValueKey(_homeGeneration),
                child: widget.homeBuilder(context, (url) => open(url)),
              )
            else if (tab.error != null)
              _ErrorPage(
                description: tab.error!,
                host: tab.url == null ? null : displayHost(tab.url!),
                onRetry: _reload,
                onHome: _goHome,
              ),
          ],
        ),
        bottomNavigationBar: ColoredBox(
          color: const Color(0xFF0A0506),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?panel,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: tab.atHome ? null : _back,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      tooltip: 'Forward',
                      onPressed:
                          tab.canGoForward || (tab.atHome && tab.url != null)
                          ? _forward
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Reload',
                      onPressed: tab.atHome ? null : _reload,
                    ),
                    IconButton(
                      icon: Icon(tab.atHome ? Icons.home : Icons.home_outlined),
                      tooltip: 'Browser home',
                      onPressed: tab.atHome ? null : _goHome,
                    ),
                    IconButton(
                      icon: Icon(_favourite ? Icons.star : Icons.star_border),
                      color: _favourite ? const Color(0xFFFF4B4B) : null,
                      tooltip: _favourite
                          ? 'Remove from favourites'
                          : 'Add to favourites',
                      onPressed: tab.atHome ? null : _toggleFavourite,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addressBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: TextField(
        controller: _address,
        focusNode: _addressFocus,
        scrollController: _addressScroll,
        keyboardType: TextInputType.url,
        autocorrect: false,
        textInputAction: TextInputAction.go,
        onSubmitted: _submitAddress,
        style: theme.textTheme.bodySmall,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search or type an address',
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: Icon(
            _blocking ? Icons.shield : Icons.public,
            size: 18,
            color: _blocking ? const Color(0xFFFF4B4B) : null,
          ),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide(color: Color(0x1FFFFFFF)),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide(color: Color(0x1FFFFFFF)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide(color: Color(0xFFE5121F)),
          ),
        ),
      ),
    );
  }
}

/// The square with the number of tabs in it, as in a phone's own browser.
class _TabsButton extends StatelessWidget {
  const _TabsButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '$count open tabs',
      onPressed: onPressed,
      icon: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface,
            width: 1.6,
          ),
        ),
        child: Text(
          '$count',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Said when a page won't load, instead of the web view's own error page.
class _ErrorPage extends StatelessWidget {
  const _ErrorPage({
    required this.description,
    required this.host,
    required this.onRetry,
    required this.onHome,
  });

  final String description;
  final String? host;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: const Color(0xFF0A0506),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 52,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 14),
              Text(
                host == null ? 'That page didn\'t load' : '$host didn\'t load',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Try again'),
                  ),
                  OutlinedButton(
                    onPressed: onHome,
                    child: const Text('Browser home'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A site on a browser's home page.
class BrowserSiteCard extends StatelessWidget {
  const BrowserSiteCard({
    super.key,
    required this.name,
    required this.host,
    required this.onTap,
  });

  final String name;
  final String host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      child: DecoratedBox(
        decoration: panelDecoration(radius: 16),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF5A0710), Color(0xFFE5121F)],
                      ),
                    ),
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two across, for a list of sites.
class BrowserSiteGrid extends StatelessWidget {
  const BrowserSiteGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// Favourites and recent pages, for a browser's home page.
class BrowserPagesSection extends StatelessWidget {
  const BrowserPagesSection({
    super.key,
    required this.store,
    required this.open,
    required this.heading,
  });

  final BrowserStore store;
  final void Function(Uri) open;
  final Widget Function(String title) heading;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: (store.favourites(), store.history()).wait,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        final (favourites, recent) = data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (favourites.isNotEmpty) ...[
              heading('Favourites'),
              for (final page in favourites)
                _PageRow(page: page, icon: Icons.star, open: open),
            ],
            if (recent.isNotEmpty) ...[
              heading('Recent'),
              for (final page in recent.take(12))
                _PageRow(page: page, icon: Icons.history, open: open),
            ],
          ],
        );
      },
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({required this.page, required this.icon, required this.open});

  final BrowserPage page;
  final IconData icon;
  final void Function(Uri) open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = Uri.tryParse(page.url);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: panelDecoration(radius: 14),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          leading: Icon(icon, size: 20, color: theme.colorScheme.primary),
          title: Text(page.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: url == null
              ? null
              : Text(
                  displayHost(url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: url == null ? null : () => open(url),
        ),
      ),
    );
  }
}
