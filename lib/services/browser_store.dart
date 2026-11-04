import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A page remembered by a browser.
class BrowserPage {
  const BrowserPage({required this.url, required this.title});

  final String url;
  final String title;

  Map<String, String> toJson() => {'url': url, 'title': title};
}

/// One browser's history, favourites and ad-blocking choice.
///
/// Kept under the browser's own name, so the novel and comic browsers share
/// nothing: looking up a comic never shows up among the novel sites.
class BrowserStore {
  BrowserStore(this.name);

  final String name;

  static const _historyLimit = 40;

  String get _historyKey => 'browser_${name}_history';
  String get _favouritesKey => 'browser_${name}_favourites';
  String get _blockKey => 'browser_${name}_block_ads';

  Future<bool> blocksAds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_blockKey) ?? true;
  }

  Future<void> setBlocksAds(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_blockKey, value);
  }

  Future<List<BrowserPage>> history() => _read(_historyKey);
  Future<List<BrowserPage>> favourites() => _read(_favouritesKey);

  /// Newest first, and a page already there moves up rather than appearing
  /// twice. A title arriving late replaces the address it was shown under.
  Future<void> remember(String url, String title) async {
    final pages = await history();
    pages.removeWhere((p) => p.url == url);
    pages.insert(0, BrowserPage(url: url, title: title.isEmpty ? url : title));
    await _write(_historyKey, pages.take(_historyLimit).toList());
  }

  Future<void> clearHistory() => _write(_historyKey, const []);

  /// Adds or removes a favourite. Returns whether it's a favourite now.
  Future<bool> toggleFavourite(String url, String title) async {
    final pages = await favourites();
    final had = pages.any((p) => p.url == url);
    if (had) {
      pages.removeWhere((p) => p.url == url);
    } else {
      pages.insert(
        0,
        BrowserPage(url: url, title: title.isEmpty ? url : title),
      );
    }
    await _write(_favouritesKey, pages);
    return !had;
  }

  Future<List<BrowserPage>> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map && item['url'] is String)
            BrowserPage(
              url: item['url'] as String,
              title: item['title'] as String? ?? item['url'] as String,
            ),
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> _write(String key, List<BrowserPage> pages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode([for (final page in pages) page.toJson()]),
    );
  }
}
