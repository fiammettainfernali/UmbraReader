import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/browser_scripts.dart';
import '../services/browser_store.dart';
import '../services/control_client.dart';
import '../services/library_cache.dart';
import '../services/library_storage.dart';
import '../services/novel_send_queue.dart';
import '../services/settings_service.dart';
import '../services/site_patterns.dart';
import '../widgets/browser_shell.dart';
import '../widgets/hawthorne_parts.dart';
import 'library_home.dart';
import 'novel_search_screen.dart';
import 'series_detail_screen.dart';

/// The browser for finding novels and sending them to your computer.
///
/// Most of the job is done from a site's lists rather than a novel's own page.
/// Going into a novel to send it and then finding the list again was the slowest
/// part of adding several, so each novel on a list gets its own send button and
/// the page stays exactly where it was.
///
/// It has its own sign-ins, separate from the comic browser's.
class NovelBrowserScreen extends StatefulWidget {
  const NovelBrowserScreen({
    super.key,
    required this.settings,
    this.initialUrl,
  });

  final OpdsSettings settings;
  final Uri? initialUrl;

  @override
  State<NovelBrowserScreen> createState() => _NovelBrowserScreenState();
}

class _NovelBrowserScreenState extends State<NovelBrowserScreen> {
  static const _lookupsAtOnce = 4;

  late final ControlClient _client = ControlClient(widget.settings);
  final BrowserStore _store = BrowserStore('novels');
  final GlobalKey<BrowserShellState> _shell = GlobalKey();
  late final NovelSendQueue _queue = NovelSendQueue(
    send: _send,
    forgetWaiting: forgetWaitingNovel,
  )..addListener(_onQueue);

  /// The library entry for the page on show, when there is one.
  DuplicateMatch? _alreadyHave;

  /// Guards against a slow answer for a page you've since left.
  int _lookupToken = 0;

  /// What the server has said about each link, so a page revisited doesn't ask
  /// again.
  final Map<String, bool> _known = {};
  final Map<String, String> _painted = {};

  /// The last thing asked of the computer never got there. Marks on books
  /// already in the library can't show until it's back, so the page says so
  /// rather than making them look like new finds.
  bool _computerAway = false;

  void _setComputerAway(bool away) {
    if (away == _computerAway || !mounted) return;
    setState(() => _computerAway = away);
  }

  @override
  void dispose() {
    _queue
      ..removeListener(_onQueue)
      ..dispose();
    super.dispose();
  }

  // ── sending ──────────────────────────────────────────────────────────────

  Future<SendResult> _send(String url, String title, bool force) async {
    final result = await sendNovelToComputer(_client, url, title, force: force);
    _setComputerAway(result.state == SendState.waiting);
    return result;
  }

  static String _buttonLook(SendState state) => switch (state) {
    SendState.holding || SendState.sending => 'hold',
    SendState.sent => 'sent',
    SendState.waiting => 'wait',
    SendState.duplicate => 'have',
    SendState.failed => 'none',
  };

  void _onQueue() {
    if (!mounted) return;
    final current = <String, String>{
      for (final item in _queue.items) item.url: _buttonLook(item.state),
    };
    current.forEach((url, look) {
      if (_painted[url] != look) {
        _shell.currentState?.runInAll(markSendButton(url, look));
      }
    });
    // Undone: the button goes back to how it was.
    for (final url in _painted.keys) {
      if (!current.containsKey(url)) {
        _shell.currentState?.runInAll(
          markSendButton(url, _known[url] == true ? 'have' : 'none'),
        );
      }
    }
    _painted
      ..clear()
      ..addAll(current);
    setState(() {});
  }

  void _sendFromPage(String url, String title) {
    unawaited(HapticFeedback.lightImpact());
    _queue.add(url, title.trim().isEmpty ? url : title.trim());
  }

  // ── what the page says ───────────────────────────────────────────────────

  void _onMessage(BrowserTab tab, Map<String, dynamic> message) {
    switch (message['type']) {
      case 'send':
        final url = message['url'];
        if (url is String) {
          _sendFromPage(url, message['title'] as String? ?? '');
        }
      case 'links':
        final urls = message['urls'];
        if (urls is List) {
          unawaited(_lookUpLinks(tab, urls.whereType<String>().toList()));
        }
    }
  }

  /// Marks what's already in the library, a few at a time. Silent on failure:
  /// with the computer away, all it costs is the marks.
  Future<void> _lookUpLinks(BrowserTab tab, List<String> urls) async {
    final shell = _shell.currentState;
    final waiting = <String>[];
    for (final url in urls) {
      final item = _queue.itemFor(url);
      if (item != null) {
        shell?.runIn(tab, markSendButton(url, _buttonLook(item.state)));
      } else if (_known[url] == true) {
        shell?.runIn(tab, markSendButton(url, 'have'));
      } else if (!_known.containsKey(url)) {
        waiting.add(url);
      }
    }
    Future<void> worker() async {
      while (waiting.isNotEmpty && mounted) {
        final url = waiting.removeLast();
        try {
          final result = await _client.lookup(url);
          _setComputerAway(false);
          _known[url] = result.known;
          if (result.known) {
            _shell.currentState?.runIn(tab, markSendButton(url, 'have'));
          }
        } on ControlException catch (e) {
          if (e.isUnreachable) _setComputerAway(true);
          waiting.clear();
        }
      }
    }

    await Future.wait([for (var i = 0; i < _lookupsAtOnce; i++) worker()]);
  }

  void _onPageChanged(BrowserTab tab) {
    final token = ++_lookupToken;
    setState(() => _alreadyHave = null);
    final url = tab.url;
    if (url == null || tab.atHome) return;
    final target = novelPageFor(url);
    if (target == null) return;
    unawaited(() async {
      try {
        final result = await _client.lookup(bareAddress(target));
        _setComputerAway(false);
        if (!mounted || token != _lookupToken) return;
        setState(() => _alreadyHave = result.known ? result.novel : null);
      } on ControlException catch (e) {
        // No hint, and the send button still works.
        if (e.isUnreachable) _setComputerAway(true);
      }
    }());
  }

  Future<void> _openInLibrary(DuplicateMatch match) async {
    final cache = LibraryCache(LibraryStorage());
    await cache.load();
    for (final series in cache.series) {
      if (series.opdsId == match.novelId) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                SeriesDetailScreen(series: series, settings: widget.settings),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('It\'s on your computer, but not on this phone yet.'),
      ),
    );
  }

  // ── drawing ──────────────────────────────────────────────────────────────

  Widget _home(BuildContext context, void Function(Uri) open) {
    // AllNovelFull only redirects to Novgo now, which has its own card. Its links
    // still get send buttons, since old ones are still around.
    final sites = [
      for (final site in kNovelSites)
        if (site.name != 'AllNovelFull') site,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const ScreenHeading(
          'Find Novels',
          subtitle: 'tap + on any novel to send it',
          padding: EdgeInsets.fromLTRB(0, 16, 0, 12),
        ),
        BrowserSiteGrid(
          children: [
            for (final site in sites)
              BrowserSiteCard(
                name: site.name,
                host: site.host,
                onTap: () => open(Uri.https(site.host)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  NovelSearchScreen(settings: widget.settings, sites: const []),
            ),
          ),
          icon: const Icon(Icons.travel_explore, size: 20),
          label: const Text('Search every site by title'),
        ),
        BrowserPagesSection(
          store: _store,
          open: open,
          heading: (title) => RowHeading(
            title: title,
            padding: const EdgeInsets.only(top: 22, bottom: 10),
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context, BrowserTab tab) {
    final bar = tab.atHome ? null : _pageBar(context, tab);
    return AnimatedBuilder(
      animation: _queue,
      builder: (context, _) {
        if (bar == null && _queue.items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_queue.items.isNotEmpty) _tray(context),
              if (_queue.items.isNotEmpty && bar != null)
                const SizedBox(height: 8),
              ?bar,
            ],
          ),
        );
      },
    );
  }

  Widget? _pageBar(BuildContext context, BrowserTab tab) {
    final theme = Theme.of(context);
    final url = tab.url;
    if (url == null) return null;
    final caption = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final target = novelPageFor(url);
    if (target == null) {
      return Text(
        siteFor(url) == null
            ? 'Your computer can\'t get novels from this site.'
            : _computerAway
            ? 'Can\'t reach your computer. Anything you send will wait, '
                  'and books you already have won\'t show.'
            : 'Tap + on any novel to send it to your computer.',
        textAlign: TextAlign.center,
        style: caption,
      );
    }
    final have = _alreadyHave;
    final clean = bareAddress(target);
    final item = _queue.itemFor(clean);
    final Widget action;
    if (have != null) {
      action = OutlinedButton.icon(
        onPressed: () => unawaited(_openInLibrary(have)),
        icon: const Icon(Icons.library_add_check, size: 20),
        label: const Text('In your library'),
      );
    } else if (item != null) {
      action = OutlinedButton.icon(
        onPressed: item.state == SendState.holding
            ? () => unawaited(_queue.undo(clean))
            : null,
        icon: Icon(
          item.state == SendState.holding ? Icons.undo : Icons.check,
          size: 20,
        ),
        label: Text(item.state == SendState.holding ? 'Undo' : _word(item)),
      );
    } else {
      action = FilledButton.icon(
        onPressed: () => _sendFromPage(clean, tab.title),
        icon: const Icon(Icons.send, size: 18),
        label: const Text('Send to computer'),
      );
    }
    return SizedBox(width: double.infinity, child: action);
  }

  static String _word(SendItem item) => switch (item.state) {
    SendState.holding => 'Sending in a moment',
    SendState.sending => 'Sending',
    SendState.sent => 'Sent',
    SendState.waiting => 'Waiting for your computer',
    SendState.duplicate => 'Already have this?',
    SendState.failed => 'Didn\'t send',
  };

  String _summary() {
    int count(List<SendState> states) =>
        _queue.items.where((i) => states.contains(i.state)).length;
    final parts = <String>[
      if (count([SendState.sent]) > 0) '${count([SendState.sent])} sent',
      if (count([SendState.holding, SendState.sending]) > 0)
        '${count([SendState.holding, SendState.sending])} sending',
      if (count([SendState.waiting]) > 0)
        '${count([SendState.waiting])} waiting',
      if (count([SendState.duplicate]) > 0)
        '${count([SendState.duplicate])} to check',
      if (count([SendState.failed]) > 0)
        '${count([SendState.failed])} didn\'t send',
    ];
    return parts.join('  ·  ');
  }

  Widget _tray(BuildContext context) {
    final theme = Theme.of(context);
    final newest = _queue.items.first;
    return DecoratedBox(
      decoration: panelDecoration(radius: 22),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => unawaited(_traySheet()),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.send, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _summary(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                if (newest.state == SendState.holding)
                  TextButton(
                    onPressed: () => unawaited(_queue.undo(newest.url)),
                    child: const Text('Undo'),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(Icons.expand_less, size: 20),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _traySheet() {
    var closing = false;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: _queue,
        builder: (sheetContext, _) {
          // Undoing the last one leaves nothing to show.
          if (_queue.items.isEmpty && !closing) {
            closing = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            });
          }
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Sent from this browser',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  for (final item in _queue.items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: panelDecoration(radius: 14),
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          dense: true,
                          title: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(item.note ?? _word(item)),
                          trailing: _trayAction(item),
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

  Widget? _trayAction(SendItem item) {
    return switch (item.state) {
      SendState.holding => TextButton(
        onPressed: () => unawaited(_queue.undo(item.url)),
        child: const Text('Undo'),
      ),
      SendState.waiting => TextButton(
        onPressed: () => unawaited(_queue.undo(item.url)),
        child: const Text('Remove'),
      ),
      SendState.duplicate => TextButton(
        onPressed: () => _queue.addAnyway(item.url),
        child: const Text('Add anyway'),
      ),
      SendState.failed => TextButton(
        onPressed: () => _queue.add(item.url, item.title),
        child: const Text('Try again'),
      ),
      SendState.sending || SendState.sent => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return BrowserShell(
      key: _shell,
      store: _store,
      profile: 'novels',
      initialUrl: widget.initialUrl,
      homeBuilder: _home,
      panelBuilder: _panel,
      onPageChanged: _onPageChanged,
      onMessage: _onMessage,
      pageScripts: (page) {
        final site = siteFor(page);
        return site == null
            ? const []
            : [sendButtonsScript(site.novelPath.pattern)];
      },
      linkActions: (url, text) {
        if (siteFor(url) == null) return const [];
        return [
          BrowserAction(
            label: 'Send to computer',
            icon: Icons.send,
            run: () =>
                _sendFromPage(bareAddress(novelPageFor(url) ?? url), text),
          ),
        ];
      },
      pageActions: (tab) {
        final url = tab.url;
        if (url == null || novelPageFor(url) != null) return const [];
        return [
          BrowserAction(
            label: 'Send this page anyway',
            icon: Icons.help_outline,
            subtitle: 'Your computer decides whether it can use it',
            run: () => _sendFromPage(url.toString(), tab.title),
          ),
        ];
      },
    );
  }
}
