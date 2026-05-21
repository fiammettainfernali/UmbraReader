import 'dart:io';

import 'package:flutter/material.dart';

import '../services/cover_cache.dart';
import '../services/library_storage.dart';

/// A series cover that loads from the on-disk cache when available, otherwise
/// downloads it (caching it for offline use) and shows [fallback] if there is
/// no cover or it can't be loaded.
class CachedCover extends StatefulWidget {
  const CachedCover({
    super.key,
    required this.seriesId,
    required this.coverUrl,
    required this.headers,
    required this.fallback,
  });

  final int seriesId;
  final String? coverUrl;
  final Map<String, String> headers;

  /// Shown when there is no cover, or it can't be fetched or decoded.
  final Widget fallback;

  @override
  State<CachedCover> createState() => _CachedCoverState();
}

class _CachedCoverState extends State<CachedCover> {
  final _cache = CoverCache(LibraryStorage());
  File? _file;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CachedCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seriesId != widget.seriesId ||
        oldWidget.coverUrl != widget.coverUrl) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _file = null;
      _loading = true;
    });
    final cached = await _cache.cached(widget.seriesId);
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _file = cached;
        _loading = false;
      });
      return;
    }
    final url = widget.coverUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final downloaded = await _cache.download(
      widget.seriesId,
      url,
      widget.headers,
    );
    if (!mounted) return;
    setState(() {
      _file = downloaded;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => widget.fallback,
      );
    }
    if (_loading) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }
    return widget.fallback;
  }
}
