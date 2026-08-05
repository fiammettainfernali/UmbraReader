import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/control_client.dart';
import '../services/settings_service.dart';
import '../services/site_patterns.dart';

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

class _BrowseScreenState extends State<BrowseScreen> {
  late final ControlClient _client = ControlClient(widget.settings);
  late final WebViewController _web;
  final TextEditingController _urlField = TextEditingController();

  Uri? _current;
  bool _loading = true;
  bool _sending = false;

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
            });
          },
        ),
      )
      ..loadRequest(start);
    _current = start;
    _urlField.text = start.toString();
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

  Future<void> _addCurrent() async {
    final page = _current;
    if (page == null) return;
    // From a chapter, offer the novel's main page when it can be derived —
    // that is the URL the scraper actually wants.
    final target = novelPageFor(page) ?? page;
    setState(() => _sending = true);
    try {
      await _client.addNovel(target.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sent to Novel Grabber — scraping started. '
            'Watch it on the Discover tab.',
          ),
        ),
      );
    } on ControlException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = _current == null ? PageKind.unsupported : classify(_current!);
    final site = _current == null ? null : siteFor(_current!);

    final (String label, IconData icon) = switch (kind) {
      PageKind.novel => ('Add this novel', Icons.library_add),
      PageKind.supportedSite => ('Add this page', Icons.add_link),
      PageKind.unsupported => ('Send anyway', Icons.help_outline),
    };

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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            onPressed: _sending ? null : _addCurrent,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon),
            label: Text(
              kind == PageKind.unsupported
                  ? '$label — this site may not be supported'
                  : label,
            ),
          ),
        ),
      ),
    );
  }
}
