import 'dart:async';

import 'package:flutter/material.dart';

import '../services/browser_policy.dart';
import '../services/browser_store.dart';
import '../services/web_series_metadata.dart';
import '../services/web_series_store.dart';
import '../widgets/browser_shell.dart';
import '../widgets/hawthorne_parts.dart';
import '../widgets/web_series_card.dart';
import 'library_home.dart';
import 'web_series_screen.dart';

/// The browser for finding comics and following them.
///
/// Nothing here goes near your computer. A comic stays on its own site, and
/// following one only remembers it, your place in it and when it grows.
///
/// It uses the same sign-ins as the comic reader, so being signed in to a site
/// here means being signed in there too. The novel browser keeps its own.
class ComicBrowserScreen extends StatefulWidget {
  const ComicBrowserScreen({super.key, this.initialUrl});

  final Uri? initialUrl;

  @override
  State<ComicBrowserScreen> createState() => _ComicBrowserScreenState();
}

class _ComicBrowserScreenState extends State<ComicBrowserScreen> {
  final BrowserStore _store = BrowserStore('comics');
  final WebSeriesStore _series = WebSeriesStore();

  bool _followed = false;
  bool _following = false;
  Uri? _checkedFor;

  void _onPageChanged(BrowserTab tab) {
    final url = tab.url;
    if (url == null || tab.atHome) return;
    final target = WebSeriesMetadata.seriesPageFor(url);
    if (target == _checkedFor) return;
    _checkedFor = target;
    unawaited(() async {
      final followed = await _series.isFollowed(target.toString());
      if (mounted && target == _checkedFor) {
        setState(() => _followed = followed);
      }
    }());
  }

  /// Keeps the address, and asks its page for a cover, a title and how many
  /// chapters there are. All of that can fail without losing the follow, since
  /// the address is what makes it work.
  Future<void> _follow(Uri page, String title) async {
    final target = WebSeriesMetadata.seriesPageFor(page);
    setState(() => _following = true);
    try {
      final info = await WebSeriesMetadata().fetch(target);
      await _series.follow(
        url: target.toString(),
        title: title.isEmpty ? displayHost(target) : title,
        info: info,
      );
      if (!mounted) return;
      if (target == _checkedFor) setState(() => _followed = true);
      final latest = info?.latestChapterNumber;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            latest == null
                ? 'Following. It\'s in the Comics side of your library.'
                : 'Following. Latest is chapter ${_plain(latest)}.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  Future<void> _unfollow(Uri page) async {
    final target = WebSeriesMetadata.seriesPageFor(page);
    await _series.unfollow(target.toString());
    if (!mounted) return;
    setState(() => _followed = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Unfollowed.')));
  }

  /// 260.0 is a chapter number nobody writes down that way.
  static String _plain(double n) =>
      n == n.roundToDouble() ? '${n.round()}' : '$n';

  Future<void> _read(Uri page) async {
    final series = await _series.find(
      WebSeriesMetadata.seriesPageFor(page).toString(),
    );
    if (series == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => WebSeriesScreen(series: series)),
    );
  }

  Widget _home(BuildContext context, void Function(Uri) open) {
    final theme = Theme.of(context);
    Widget heading(String title) => RowHeading(
      title: title,
      padding: const EdgeInsets.only(top: 22, bottom: 10),
    );
    return FutureBuilder<List<WebSeries>>(
      future: _series.all(),
      builder: (context, snapshot) {
        final followed = snapshot.data ?? const <WebSeries>[];
        final hosts = <String>{
          for (final series in followed)
            if (Uri.tryParse(series.url) case final Uri url
                when url.host.isNotEmpty)
              displayHost(url),
        };
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const ScreenHeading(
              'Find Comics',
              subtitle: 'follow one to read it here',
              padding: EdgeInsets.fromLTRB(0, 16, 0, 4),
            ),
            if (followed.isNotEmpty) ...[
              heading('Following'),
              SizedBox(
                height: 232,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: followed.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => SizedBox(
                    width: 124,
                    child: WebSeriesCard(
                      series: followed[index],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              WebSeriesScreen(series: followed[index]),
                        ),
                      ),
                      onLongPress: () {},
                    ),
                  ),
                ),
              ),
            ],
            if (hosts.isNotEmpty) ...[
              heading('Your sites'),
              BrowserSiteGrid(
                children: [
                  for (final host in hosts)
                    BrowserSiteCard(
                      name: host,
                      host: host,
                      onTap: () => open(Uri.https(host)),
                    ),
                ],
              ),
            ],
            if (followed.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Type a comic\'s name or a site\'s address in the bar above. '
                  'When you find one you like, tap Follow.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            BrowserPagesSection(store: _store, open: open, heading: heading),
          ],
        );
      },
    );
  }

  Widget? _panel(BuildContext context, BrowserTab tab) {
    final url = tab.url;
    if (url == null || tab.atHome) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _followed
                ? OutlinedButton.icon(
                    onPressed: () => unawaited(_unfollow(url)),
                    icon: const Icon(Icons.bookmark_added, size: 20),
                    label: const Text('Following'),
                  )
                : FilledButton.icon(
                    onPressed: _following
                        ? null
                        : () => unawaited(_follow(url, tab.title)),
                    icon: _following
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bookmark_add_outlined, size: 20),
                    label: const Text('Follow'),
                  ),
          ),
          if (_followed) ...[
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => unawaited(_read(url)),
                icon: const Icon(Icons.chrome_reader_mode_outlined, size: 20),
                label: const Text('Read'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BrowserShell(
      store: _store,
      // The default sign-ins, which the comic reader uses too.
      initialUrl: widget.initialUrl,
      homeBuilder: _home,
      panelBuilder: (context, tab) =>
          _panel(context, tab) ?? const SizedBox.shrink(),
      onPageChanged: _onPageChanged,
      linkActions: (url, text) => [
        BrowserAction(
          label: 'Follow this comic',
          icon: Icons.bookmark_add_outlined,
          run: () => unawaited(_follow(url, text)),
        ),
      ],
    );
  }
}
