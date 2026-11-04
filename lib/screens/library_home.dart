import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/series.dart';
import '../services/app_motion.dart';
import '../services/reading_progress_store.dart';
import '../services/series_status_store.dart';
import '../widgets/living_surfaces.dart';
import 'library_cards.dart';

/// The Library's streaming layout, the same one the desktop program uses: a
/// spotlight slideshow, a toolbar card, and rows of covers that drift on their
/// own. These are the parts; [LibraryScreen] decides what goes where.

const _ink = Color(0xFF060304);
const _red = Color(0xFFE5121F);
const _hot = Color(0xFFFF4B4B);
const _paper = Color(0xFFF7EFEF);
const _panel = Color(0xFF10060A);
const _edge = Color(0x3DFF5A5A);

/// Kept out of the spotlight and the named rows, though never out of the
/// library. The same words the desktop's spotlight goes by.
const _adultWords = [
  'adult',
  'mature',
  'smut',
  'ecchi',
  'lemon',
  'erotica',
  'harem',
];

bool isAdultSeries(Series series) {
  final genres = series.genres.join(',').toLowerCase();
  return _adultWords.any(genres.contains);
}

/// What the spotlight shows: up to two books being read, then a set that
/// changes daily rather than on every launch. The desktop's rule.
List<Series> pickSpotlight(
  List<Series> library,
  List<int> readingIds,
  DateTime today, {
  int size = 5,
}) {
  final usable = [
    for (final series in library)
      if (series.coverUrl != null &&
          series.description.length > 80 &&
          !isAdultSeries(series))
        series,
  ];
  final byId = {for (final series in usable) series.opdsId: series};
  final chosen = <Series>[];
  for (final id in readingIds) {
    final series = byId[id];
    if (series != null && !chosen.contains(series)) chosen.add(series);
    if (chosen.length == 2) break;
  }
  final others = [
    for (final series in usable)
      if (!chosen.contains(series)) series,
  ];
  others.shuffle(
    math.Random(today.year * 10000 + today.month * 100 + today.day),
  );
  return [...chosen, ...others].take(size).toList();
}

/// What belongs on Continue reading, from [entries] newest first: one volume
/// per series, the one read most recently, and only books actually being read.
///
/// A series set to Dropped or Caught up has been put down, whatever chapter it
/// was left on. Hiding the newest volume hides the series: its older volumes are
/// the same book as far as the shelf is concerned, and them taking its place
/// looked like the removal hadn't worked. Reading any volume brings it back,
/// because that volume is then newest and not hidden.
///
/// A book only counts as finished once the very end of its last page is reached,
/// so most books read up to date never quite get there, and sat here for good
/// on "Chapter 191 of 191". Left on the last chapter for [caughtUpAfter], a book
/// counts as caught up. New chapters raise its count, which takes it off the
/// last chapter and brings it back without anyone doing anything.
List<ReadingEntry> continueShelf(
  List<ReadingEntry> entries, {
  required Set<String> hidden,
  required Map<int, SeriesStatus> statuses,
  int limit = 12,
  Duration caughtUpAfter = const Duration(days: 3),
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  bool caughtUp(ReadingProgress progress) {
    if (progress.chapterCount <= 0) return false;
    if (progress.chapterIndex < progress.chapterCount - 1) return false;
    final at = progress.updatedAt;
    return at == null || today.difference(at) > caughtUpAfter;
  }

  final settled = <int>{};
  final shelf = <ReadingEntry>[];
  for (final entry in entries) {
    final progress = entry.progress;
    if (!progress.isStarted || progress.isFinished) continue;
    final id = entry.volume.seriesOpdsId;
    if (!settled.add(id)) continue;
    final status = statuses[id];
    if (status == SeriesStatus.dropped || status == SeriesStatus.caughtUp) {
      continue;
    }
    if (hidden.contains('$id/${entry.volume.fileName}')) continue;
    if (caughtUp(progress)) continue;
    shelf.add(entry);
    if (shelf.length == limit) break;
  }
  return shelf;
}

/// One row of covers on the home view.
class HomeRow {
  const HomeRow({
    required this.title,
    required this.tag,
    required this.series,
    required this.seeAll,
    this.reverse = false,
  });

  final String title;
  final String tag;
  final List<Series> series;
  final HomeRowTarget seeAll;
  final bool reverse;
}

/// Where a row's See all goes.
sealed class HomeRowTarget {
  const HomeRowTarget();
}

class SeeNewest extends HomeRowTarget {
  const SeeNewest();
}

class SeeLongest extends HomeRowTarget {
  const SeeLongest();
}

class SeeGenre extends HomeRowTarget {
  const SeeGenre(this.genre);
  final String genre;
}

/// Newest, longest, then the library's biggest genres. A row needs at least
/// four covers to read as a row. As on the desktop, adult titles and books
/// with no cover stay out of the rows, and remain in the full grid below.
List<HomeRow> buildHomeRows(List<Series> library) {
  final safe = [
    for (final series in library)
      if (series.coverUrl != null && !isAdultSeries(series)) series,
  ];
  final dated = [
    for (final series in safe)
      if (series.addedAt != null) series,
  ]..sort((a, b) => b.addedAt!.compareTo(a.addedAt!));
  final longest = [...safe]
    ..sort((a, b) => b.totalChapters.compareTo(a.totalChapters));

  final counts = <String, int>{};
  for (final series in safe) {
    for (final genre in series.genres) {
      counts[genre] = (counts[genre] ?? 0) + 1;
    }
  }
  final biggest = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final rows = <HomeRow>[
    HomeRow(
      title: 'Recently added',
      tag: 'Newest first',
      series: dated.take(30).toList(),
      seeAll: const SeeNewest(),
    ),
    HomeRow(
      title: 'Longest series',
      tag: 'Thousands of chapters',
      series: longest.take(30).toList(),
      seeAll: const SeeLongest(),
      reverse: true,
    ),
    for (final (index, entry) in biggest.take(7).indexed)
      HomeRow(
        title: entry.key,
        tag:
            '${library.where((s) => s.genres.contains(entry.key)).length} '
            'novels',
        series: [
          for (final series in safe)
            if (series.genres.contains(entry.key)) series,
        ].take(30).toList(),
        seeAll: SeeGenre(entry.key),
        reverse: index.isOdd,
      ),
  ];
  return [
    for (final row in rows)
      if (row.series.length >= 4) row,
  ];
}

/// The logo and name, as they sit at the top of the desktop window.
class HawthorneBrand extends StatelessWidget {
  const HawthorneBrand({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Image.asset('assets/logo/hawthorne_emblem.png', height: 30),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                text: 'Hawthorne ',
                children: [
                  TextSpan(
                    text: 'Codex',
                    style: style?.copyWith(color: _hot),
                  ),
                ],
              ),
              style: style,
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

/// A cover blown up, soft and drifting slowly behind a spotlight or a novel's
/// page. The softness comes from decoding it very small, so the slow zoom only
/// moves a small image rather than blurring a big one again every frame.
class CoverBackdrop extends StatefulWidget {
  const CoverBackdrop({super.key, required this.series, required this.headers});

  final Series series;
  final Map<String, String> headers;

  @override
  State<CoverBackdrop> createState() => _CoverBackdropState();
}

class _CoverBackdropState extends State<CoverBackdrop> with SlowClock {
  late final double _start = seconds.value;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRect(
        child: ValueListenableBuilder<double>(
          valueListenable: seconds,
          child: SizedBox.expand(
            child: CoverImage(
              series: widget.series,
              headers: widget.headers,
              decodeWidth: 64,
            ),
          ),
          builder: (context, now, child) {
            final zoom = ((now - _start) / 14).clamp(0.0, 1.0);
            return Transform.scale(scale: 1.24 - 0.1 * zoom, child: child);
          },
        ),
      ),
    );
  }
}

/// The big slideshow at the top of the Library. It moves on by itself, and can
/// be swiped through to look for something particular.
class SpotlightCarousel extends StatefulWidget {
  const SpotlightCarousel({
    super.key,
    required this.series,
    required this.isReading,
    required this.headers,
    required this.onRead,
    required this.onDetails,
    this.height = 530,
  });

  final List<Series> series;
  final bool Function(Series series) isReading;
  final Map<String, String> headers;
  final ValueChanged<Series> onRead;
  final ValueChanged<Series> onDetails;
  final double height;

  @override
  State<SpotlightCarousel> createState() => _SpotlightCarouselState();
}

class _SpotlightCarouselState extends State<SpotlightCarousel> with SlowClock {
  /// The desktop's seven seconds at Medium speed.
  static const _hold = 9.7;

  // Starting far along means it can be swiped either way from the first slide.
  late final PageController _pages = PageController(
    initialPage: widget.series.length * 1000,
  );
  late int _page = widget.series.length * 1000;
  late double _shownAt = seconds.value;
  bool _held = false;

  @override
  void initState() {
    super.initState();
    seconds.addListener(_onBeat);
  }

  void _onBeat() {
    if (_held || !_pages.hasClients) return;
    if (seconds.value - _shownAt < _hold) return;
    _shownAt = seconds.value;
    _pages.animateToPage(
      _page + 1,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    seconds.removeListener(_onBeat);
    _pages.dispose();
    super.dispose();
  }

  void _select(int slide) {
    final current = _page % widget.series.length;
    _pages.animateToPage(
      _page + slide - current,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.series.length;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: SizedBox(
        height: widget.height,
        child: Listener(
          onPointerDown: (_) => _held = true,
          onPointerUp: (_) => _held = false,
          onPointerCancel: (_) => _held = false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pages,
                onPageChanged: (page) {
                  setState(() => _page = page);
                  _shownAt = seconds.value;
                },
                itemBuilder: (context, index) {
                  final series = widget.series[index % count];
                  return _SpotlightSlide(
                    key: ValueKey(index),
                    series: series,
                    active: index == _page,
                    reading: widget.isReading(series),
                    headers: widget.headers,
                    clock: seconds,
                    onRead: () => widget.onRead(series),
                    onDetails: () => widget.onDetails(series),
                  );
                },
              ),
              Positioned(
                right: 16,
                bottom: 14,
                child: ValueListenableBuilder<double>(
                  valueListenable: seconds,
                  builder: (context, now, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < count; i++)
                        _Pip(
                          label: 'Show ${widget.series[i].title}',
                          on: i == _page % count,
                          fill: ((now - _shownAt) / _hold).clamp(0.0, 1.0),
                          onTap: () => _select(i),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip({
    required this.label,
    required this.on,
    required this.fill,
    required this.onTap,
  });

  final String label;
  final bool on;
  final double fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              width: 34,
              height: 3,
              child: ColoredBox(
                color: const Color(0x4DFFFFFF),
                child: on
                    ? FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fill,
                        child: const ColoredBox(color: _hot),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpotlightSlide extends StatefulWidget {
  const _SpotlightSlide({
    super.key,
    required this.series,
    required this.active,
    required this.reading,
    required this.headers,
    required this.clock,
    required this.onRead,
    required this.onDetails,
  });

  final Series series;
  final bool active;
  final bool reading;
  final Map<String, String> headers;
  final ValueListenable<double> clock;
  final VoidCallback onRead;
  final VoidCallback onDetails;

  @override
  State<_SpotlightSlide> createState() => _SpotlightSlideState();
}

class _SpotlightSlideState extends State<_SpotlightSlide>
    with SingleTickerProviderStateMixin {
  // The arrival runs once per slide and then stops, so nothing ticks at rest.
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.isReduced(context)) {
      _arrive.value = 1;
    } else if (widget.active && _arrive.isDismissed) {
      _arrive.forward();
    }
  }

  @override
  void didUpdateWidget(_SpotlightSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && _arrive.isDismissed) {
      _arrive.forward();
    }
  }

  @override
  void dispose() {
    _arrive.dispose();
    super.dispose();
  }

  /// The piece of the arrival between [from] and [to], eased.
  Widget _rise(double from, double to, Widget child, {double dx = 0}) {
    final part = CurvedAnimation(
      parent: _arrive,
      curve: Interval(from, to, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: part,
      child: child,
      builder: (context, child) => Opacity(
        opacity: part.value,
        child: Transform.translate(
          offset: Offset(dx * (1 - part.value), 18 * (1 - part.value)),
          child: child,
        ),
      ),
    );
  }

  /// Sites run sentences together, and mark up what they think matters.
  String get _blurb => widget.series.description
      .replaceAll('**', '')
      .replaceAllMapped(RegExp(r'([.!?”"])(?=[A-Z])'), (m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = widget.series;
    final chips = [
      if (series.totalChapters > 0) '${series.totalChapters} chapters',
      ...series.genres.take(2),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final artWidth = math.min(150.0, box.maxWidth * 0.38);
        final artHeight = artWidth * 1.5;
        return Stack(
          fit: StackFit.expand,
          children: [
            CoverBackdrop(series: series, headers: widget.headers),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x59060304),
                    Color(0x26060304),
                    Color(0xCC060304),
                    _ink,
                  ],
                  stops: [0, 0.4, 0.74, 1],
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 18,
              width: artWidth,
              height: artHeight,
              child: _rise(
                0,
                0.8,
                _FloatingArt(
                  series: series,
                  headers: widget.headers,
                  clock: widget.clock,
                ),
                dx: 46,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 46),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: artHeight + 14,
                    child: Padding(
                      padding: EdgeInsets.only(right: artWidth + 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _rise(
                            0.05,
                            0.45,
                            _Kicker(
                              widget.reading ? 'Keep reading' : 'Spotlight',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Flexible(
                            child: _rise(
                              0.12,
                              0.6,
                              Text(
                                series.title,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0x80E5121F),
                                      blurRadius: 22,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _rise(
                    0.35,
                    0.75,
                    SizedBox(
                      height: 30,
                      child: ClipRect(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 8,
                          children: [
                            for (final chip in chips) _GlassChip(chip),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _rise(
                      0.45,
                      0.85,
                      Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          _blurb,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                            color: const Color(0xFFE9DFDF),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _rise(
                    0.5,
                    0.9,
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 12),
                      child: Text(
                        'by ${series.author}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  _rise(
                    0.58,
                    1,
                    Row(
                      children: [
                        Flexible(
                          child: GlowButton(
                            clock: widget.clock,
                            icon: Icons.play_arrow_rounded,
                            label: widget.reading ? 'Continue' : 'Read now',
                            onPressed: widget.onRead,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: OutlinedButton.icon(
                            onPressed: widget.onDetails,
                            icon: const Icon(
                              Icons.menu_book_outlined,
                              size: 18,
                            ),
                            label: const Text('Details'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: _hot,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: _hot, blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _hot,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: const Color(0x17FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x29FFFFFF)),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// The tilted cover floating in a spotlight, with a sheen crossing it now and
/// then.
class _FloatingArt extends StatelessWidget {
  const _FloatingArt({
    required this.series,
    required this.headers,
    required this.clock,
  });

  final Series series;
  final Map<String, String> headers;
  final ValueListenable<double> clock;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: clock,
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0xBF000000),
                blurRadius: 34,
                offset: Offset(0, 16),
              ),
              BoxShadow(color: Color(0x8CE5121F), blurRadius: 36),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoverImage(series: series, headers: headers),
                _Sheen(clock: clock),
              ],
            ),
          ),
        ),
      ),
      builder: (context, now, child) => Transform.translate(
        offset: Offset(0, 6 * math.sin(now * 0.55)),
        child: Transform.rotate(
          angle: 0.07 + 0.012 * math.sin(now * 0.4),
          child: child,
        ),
      ),
    );
  }
}

class _Sheen extends StatelessWidget {
  const _Sheen({required this.clock});

  final ValueListenable<double> clock;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: clock,
        builder: (context, now, _) {
          final sweep = (now % 7) / 1.8;
          if (sweep >= 1) return const SizedBox.shrink();
          return FractionalTranslation(
            translation: Offset(-1 + 2.2 * sweep, 0),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1, -0.5),
                  end: Alignment(1, 0.5),
                  colors: [
                    Color(0x00FFFFFF),
                    Color(0x47FFFFFF),
                    Color(0x00FFFFFF),
                  ],
                ),
              ),
              child: SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

/// The red button with a glow that pulses, as on the desktop's spotlight.
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.clock,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final ValueListenable<double> clock;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: clock,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
      builder: (context, now, child) {
        final pulse = 0.5 + 0.5 * math.sin(now * 1.8);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _red.withValues(alpha: 0.35 + 0.35 * pulse),
                blurRadius: 12 + 12 * pulse,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// The panel holding the Library's title, count and controls.
class LibraryToolbarCard extends StatelessWidget {
  const LibraryToolbarCard({
    super.key,
    required this.count,
    required this.child,
  });

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _edge),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Library',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(color: Color(0x8CE5121F), blurRadius: 18),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count novels',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A row of equal choices with a white pill that slides to the chosen one.
class SlidingPillBar<T> extends StatelessWidget {
  const SlidingPillBar({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final count = values.length;
    final chosen = values.indexOf(selected);
    final reduced = AppMotion.isReduced(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0B0E),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              alignment: Alignment(
                count == 1 ? 0 : -1 + 2 * chosen / (count - 1),
                0,
              ),
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 620),
              curve: const Cubic(0.34, 1.4, 0.64, 1),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: _paper,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(color: Color(0x73FF4B4B), blurRadius: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == chosen,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(values[i]),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AnimatedDefaultTextStyle(
                            duration: reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: i == chosen
                                  ? const Color(0xFF150608)
                                  : const Color(0xFFCDBCBD),
                            ),
                            child: Text(labels[i], maxLines: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A row's heading: a bold title, an amber tag and See all.
class RowHeading extends StatelessWidget {
  const RowHeading({
    super.key,
    required this.title,
    this.tag,
    this.onSeeAll,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 10),
  });

  final String title;
  final String? tag;
  final VoidCallback? onSeeAll;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RiseIn(
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            // The tag drops under the title when both won't fit on a line,
            // so neither gets cut short.
            Expanded(
              child: Wrap(
                spacing: 9,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (tag != null) _AmberTag(tag!),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onSeeAll != null)
              Semantics(
                button: true,
                label: 'See every novel in $title',
                excludeSemantics: true,
                child: PressScale(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSeeAll,
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.only(left: 12, right: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: const Color(0x33FFFFFF)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'See all',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 17),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AmberTag extends StatelessWidget {
  const _AmberTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x29F09628),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x6BF09628)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFFFD9B0),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// A row of covers that drifts along by itself and loops, and stops for a
/// finger. It's built lazily with the rest of the page, so a row out of sight
/// isn't moving.
class DriftingRow extends StatefulWidget {
  const DriftingRow({
    super.key,
    required this.itemCount,
    required this.itemExtent,
    required this.height,
    required this.itemBuilder,
    this.reverse = false,
  });

  final int itemCount;
  final double itemExtent;
  final double height;
  final bool reverse;

  /// Gets the row's clock too, so its covers can bob on the same beat.
  final Widget Function(
    BuildContext context,
    int index,
    ValueListenable<double> clock,
  )
  itemBuilder;

  @override
  State<DriftingRow> createState() => _DriftingRowState();
}

class _DriftingRowState extends State<DriftingRow> with SlowClock {
  /// Logical pixels a second: enough to notice, slow enough to read.
  static const _speed = 13.0;
  static const _resumeAfter = Duration(milliseconds: 1600);

  /// A short row doesn't fill the screen, and looping it shows gaps.
  bool get _loops => widget.itemCount >= 4;

  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _loops
        ? widget.itemExtent * widget.itemCount * 500
        : 0,
  );
  bool _held = false;
  Timer? _resume;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _last = seconds.value;
    seconds.addListener(_onBeat);
  }

  void _onBeat() {
    final now = seconds.value;
    final passed = (now - _last).clamp(0.0, 0.2);
    _last = now;
    if (!_loops || _held || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.isScrollingNotifier.value) return;
    _scroll.jumpTo(
      position.pixels + (widget.reverse ? -_speed : _speed) * passed,
    );
  }

  void _hold() {
    _resume?.cancel();
    _held = true;
  }

  void _letGo() {
    _resume?.cancel();
    _resume = Timer(_resumeAfter, () => _held = false);
  }

  @override
  void dispose() {
    seconds.removeListener(_onBeat);
    _resume?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Listener(
        onPointerDown: (_) => _hold(),
        onPointerUp: (_) => _letGo(),
        onPointerCancel: (_) => _letGo(),
        // The drift is this row's own business, not the page's.
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) => true,
          child: ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemExtent: widget.itemExtent,
            itemCount: _loops ? null : widget.itemCount,
            itemBuilder: (context, index) =>
                widget.itemBuilder(context, index % widget.itemCount, seconds),
          ),
        ),
      ),
    );
  }
}

/// A cover in a row, bobbing gently, with its title under it.
class RowCard extends StatelessWidget {
  const RowCard({
    super.key,
    required this.series,
    required this.headers,
    required this.phase,
    required this.clock,
    required this.fresh,
    required this.onTap,
    required this.onLongPress,
    this.progress,
  });

  final Series series;
  final Map<String, String> headers;
  final double phase;
  final ValueListenable<double> clock;

  /// Whether there's something newer than the copy on this device.
  final bool fresh;

  /// How far through it is, for a row of books being read.
  final double? progress;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label:
          '${series.title} by ${series.author}'
          "${fresh ? '. New chapters available' : ''}",
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.only(right: 14),
          child: PressScale(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ValueListenableBuilder<double>(
                    valueListenable: clock,
                    child: RepaintBoundary(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          // A hard edge rather than a blurred glow, as in the
                          // grid: a row redraws these on every beat.
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x59E5121F),
                              spreadRadius: 1.5,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CoverImage(series: series, headers: headers),
                              if (fresh)
                                const Positioned(
                                  top: 7,
                                  left: 7,
                                  child: _NewBadge(),
                                ),
                              if (progress != null)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: 4,
                                  child: ColoredBox(
                                    color: const Color(0x8C000000),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: progress!.clamp(0.0, 1.0),
                                      child: const ColoredBox(color: _hot),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    builder: (context, now, child) => Transform.translate(
                      offset: Offset(0, 2.5 * math.sin(now * 0.8 + phase)),
                      child: child,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _red,
        borderRadius: BorderRadius.circular(9),
        boxShadow: const [BoxShadow(color: Color(0x99E5121F), blurRadius: 8)],
      ),
      child: const Text(
        'New',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// A compact notice that the library is the saved copy, with a way to retry and
/// the full reason a tap away, so it doesn't push the page down a whole screen.
class OfflineStrip extends StatelessWidget {
  const OfflineStrip({super.key, required this.reason, required this.onRetry});

  final String? reason;
  final VoidCallback onRetry;

  void _explain(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Showing your saved library'),
        content: Text(
          'Downloaded books can still be read.'
          '${reason == null || reason!.isEmpty ? '' : '\n\n$reason'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: const Color(0xFF1E0D10),
        shape: const StadiumBorder(side: BorderSide(color: _edge)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _explain(context),
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 4),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Offline — showing your saved library',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
