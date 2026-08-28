/// Turning a page like a sheet of paper instead of sliding it.
///
/// The awkward part of a page turn in Flutter is paint order. A turn means
/// the page you are leaving lifts and rotates away while the next one lies
/// flat underneath â€” so the *outgoing* page has to be on top. A [PageView]
/// paints its children in index order, which puts the incoming page above
/// the outgoing one: exactly backwards, and not something a property can
/// change.
///
/// The way out is not to replace the pager. The [PageView] keeps doing all
/// the work it is good at â€” drag physics, snapping, scroll notifications,
/// keeping the reader's chapter-crossing and seeking intact â€” and the page
/// that is folding is simply drawn a second time in an overlay above it,
/// where paint order is ours to choose. In the pager itself that page is
/// left blank, so it is only ever built once.
///
/// The pages that are not folding are pinned in place against the pager's
/// own scrolling, which is what turns a slide into a turn: underneath, the
/// next page sits still and is revealed, rather than sliding in from the
/// side.
///
/// Nothing here rasterises a page. The text is the same widgets, transformed,
/// so it stays sharp at any angle â€” which is the practical reason to prefer
/// this hinged fold to a true paper curl.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which page is mid-turn, and how far through it is.
@immutable
class FoldFrame {
  const FoldFrame({required this.index, required this.turn});

  /// The page lifting away. Always the lower of the two pages on screen:
  /// going forward it is the one being left, going back it is the one
  /// settling down again.
  final int index;

  /// 0 flat, 1 edge-on. Never quite reaches either â€” see [foldFrameFor].
  final double turn;
}

/// Reads a [PageView]'s fractional position as a fold.
///
/// Returns null when no page is mid-turn, which is the overwhelmingly common
/// case: a settled pager has nothing to draw in the overlay, and the reader
/// is then pixel-for-pixel what it was before folding existed.
///
/// The epsilon matters. A pager at rest reports a position a hair off the
/// integer, and folding a page by a twentieth of a degree would keep the
/// overlay permanently alive â€” one page built twice, forever, for a fold
/// nobody can see.
FoldFrame? foldFrameFor(double? page) {
  if (page == null || !page.isFinite) return null;
  final index = page.floor();
  final turn = page - index;
  if (turn <= 0.002 || turn >= 0.998) return null;
  return FoldFrame(index: index, turn: turn);
}

/// The pager's fractional position, or null when it cannot be read yet.
///
/// `hasClients` is not a strong enough guard. During a rebuild that swaps one
/// pager for another â€” which is exactly what unfolding the phone does â€” the
/// controller is attached to both for a frame, and [ScrollController.position]
/// asserts on anything but precisely one. Reading it then takes the reader
/// down mid-unfold.
double? pagerPage(PageController controller) {
  if (controller.positions.length != 1) return null;
  if (!controller.position.hasContentDimensions) return null;
  final page = controller.page;
  if (page == null || !page.isFinite) return null;
  return page;
}

/// The single page the pager itself should paint at position [page].
///
/// Exactly one, always. Pinning pages against the pager's scrolling means
/// they no longer take turns occupying the viewport â€” they all sit at the
/// same place â€” so anything painted besides this one lands on top of it.
/// Pages are transparent (their colour belongs to the screen behind them), so
/// two of them is not a subtle overlap: it is both chapters legible at once.
///
/// While a sheet is turning that is the page *underneath* it, the one being
/// uncovered; the sheet itself is drawn by the overlay, above. Between turns
/// it is simply the page you are on.
int paintedPageFor(double page) {
  final frame = foldFrameFor(page);
  return frame != null ? frame.index + 1 : page.round();
}

/// One page, folding back on itself as it is turned.
///
/// Not a rotation. A rotation about the spine is how a hinged board moves,
/// and it looks like one however it is shaded or eased â€” the whole sheet
/// tilts at once, every line of type skewing with it.
///
/// Paper does something else. Drag the outer edge of a page across and the
/// sheet buckles into a crease: on one side of the crease the page is still
/// lying flat and perfectly readable, and beyond it the part you have pulled
/// over is folded back on itself, showing its own reverse â€” mirrored, and
/// darker for being the back of the sheet. The crease travels ahead of your
/// hand, and the next page is uncovered behind it.
///
/// So three bands, and only one of them is transformed at all:
///
///   * `[0, edge]`   the page still lying flat, untouched;
///   * `[edge, crease]` the flap, the same page mirrored about the crease;
///   * `[crease, 1]` uncovered â€” nothing drawn here, the pager's next page
///     shows through from underneath.
///
/// Cheaper than tilting it, as it happens: two copies of the page and no
/// perspective maths.
class FoldingPage extends StatelessWidget {
  const FoldingPage({super.key, required this.turn, required this.child});

  /// 0 flat, 1 fully turned.
  final double turn;
  final Widget child;

  /// Where the crease sits, as a fraction of the sheet's width.
  ///
  /// Travels from the outer edge to the spine over the turn. Everything
  /// beyond it has been uncovered.
  static double creaseFor(double turn) => 1 - turn.clamp(0.0, 1.0);

  /// Where the sheet's dragged edge has got to, same units.
  ///
  /// Twice the crease's travel, because folding a sheet in half moves its
  /// edge two units for every one the crease moves â€” which is what carries
  /// the flap off the near side of the screen by the end of the turn instead
  /// of leaving half a page lying there.
  static double edgeFor(double turn) => 1 - 2 * turn.clamp(0.0, 1.0);

  /// How much darker the back of the sheet is than its face.
  ///
  /// Paper is not opaque and not a mirror: its reverse reads as the same
  /// stock seen from behind, dimmer and lower in contrast. Fading it in over
  /// the first of the turn keeps the flap from appearing out of nowhere at
  /// the instant the crease forms.
  static double backingFor(double turn) =>
      0.55 * (turn.clamp(0.0, 1.0) * 6).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || width <= 0) return child;
        final crease = creaseFor(turn) * width;
        final edge = edgeFor(turn) * width;
        // The flap runs from the dragged edge to the crease. Once the edge
        // has passed the spine the flap simply continues off-screen, which
        // is why this clamps rather than stopping.
        final flapFrom = math.max(edge, 0.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Still flat, still being read.
            if (edge > 0)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: edge,
                child: _Slice(offset: 0, pageWidth: width, child: child),
              ),
            // Folded over: the same page, mirrored about the crease.
            if (crease > flapFrom)
              Positioned(
                left: flapFrom,
                top: 0,
                bottom: 0,
                width: crease - flapFrom,
                child: _Flap(
                  crease: crease,
                  from: flapFrom,
                  pageWidth: width,
                  backing: backingFor(turn),
                  child: child,
                ),
              ),
            // The shadow the raised sheet throws onto the page it is
            // uncovering. Without it the new page looks lit from nowhere and
            // the fold stops reading as a physical object above it.
            if (crease > 0 && crease < width)
              Positioned(
                left: crease,
                top: 0,
                bottom: 0,
                width: math.min(width - crease, width * 0.06),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.34),
                          Colors.black.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A vertical slice of the page, drawn in its own box.
///
/// The page is laid out at its full width and slid sideways, so every slice
/// keeps the pagination and margins the page was composed with â€” a slice is
/// a window onto the page, never a narrower version of it.
class _Slice extends StatelessWidget {
  const _Slice({
    required this.offset,
    required this.pageWidth,
    required this.child,
  });

  /// Distance from the page's left edge to this slice's left edge.
  final double offset;
  final double pageWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: 0,
        maxWidth: pageWidth,
        child: Transform.translate(
          offset: Offset(-offset, 0),
          child: SizedBox(width: pageWidth, child: child),
        ),
      ),
    );
  }
}

/// The part of the sheet that has been folded back on itself.
///
/// Its content is the page reflected about the crease: what was just to the
/// right of the crease is now just to the left of it, running backwards. That
/// reflection is the whole reason the effect reads as paper rather than as a
/// picture sliding about â€” you are seeing the back of a real sheet, and the
/// text on it is the text you were reading a moment ago, reversed.
class _Flap extends StatelessWidget {
  const _Flap({
    required this.crease,
    required this.from,
    required this.pageWidth,
    required this.backing,
    required this.child,
  });

  /// Position of the crease within the sheet.
  final double crease;

  /// Left edge of this flap within the sheet.
  final double from;

  final double pageWidth;

  /// Opacity of the darkening that makes this the reverse of the paper.
  final double backing;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: pageWidth,
            child: Transform(
              alignment: Alignment.topLeft,
              // Screen x within this box maps to page x = 2*crease - (x +
              // from): flip about the crease, then bring it into the box.
              transform: Matrix4.identity()
                ..translateByDouble(2 * crease - from, 0, 0, 1)
                ..scaleByDouble(-1, 1, 1, 1),
              child: SizedBox(width: pageWidth, child: child),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Darkest right at the crease, where the fold is tightest
                  // and least light reaches, easing off toward the free edge
                  // that is lifting away from the page.
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: backing * 0.72),
                      Colors.black.withValues(alpha: backing),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A [PageView] whose turns fold instead of sliding.
///
/// A drop-in replacement: with [folding] false it *is* a [PageView], which
/// is deliberate. Paging is the component every reading session runs
/// through, so the unfolded path stays the plain, long-proven one and the
/// setting can be switched back without a rebuild.
class FoldingPager extends StatefulWidget {
  const FoldingPager({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.background,
    this.onPageChanged,
    this.folding = true,
    this.spineFraction = 0,
  });

  /// What the page is printed on.
  ///
  /// Not decoration. A page widget draws its text and nothing else â€” the
  /// colour behind it belongs to the screen, not the page â€” so a sheet lifted
  /// into the overlay is transparent, and the page being uncovered reads
  /// straight through it. Two chapters of text superimposed, for the whole
  /// turn. The sheet needs something to be made of.
  final Color background;

  final PageController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int>? onPageChanged;

  /// When false this renders a bare [PageView] and nothing else happens.
  final bool folding;

  /// Where the hinge sits across the viewport, 0 at the left edge.
  ///
  /// 0 is a single page: the whole sheet turns about the left margin. 0.5 is
  /// a two-page spread, where only the right-hand page is a free leaf and the
  /// left one stays flat on the table.
  ///
  /// A spread does turn â€” one leaf, not two. A book open at 2|3 turns a
  /// single sheet and lands on 4|5, which is exactly one advance of a pager
  /// whose unit is the spread. Page 3 is on the front of that leaf and page 4
  /// on its back.
  final double spineFraction;

  @override
  State<FoldingPager> createState() => _FoldingPagerState();
}

class _FoldingPagerState extends State<FoldingPager> {
  // The overlay rebuilds on every frame of a turn, and rebuilding a page of
  // text sixty times a second is the one thing that would make this cost
  // anything. The folding page does not change during a turn, so it is built
  // once and held.
  int _heldIndex = -1;
  Widget? _held;

  @override
  void didUpdateWidget(FoldingPager old) {
    super.didUpdateWidget(old);
    // A new builder means new content â€” repagination, a font change, a new
    // chapter. Anything held is describing the old text.
    if (!identical(widget.itemBuilder, old.itemBuilder) ||
        widget.itemCount != old.itemCount ||
        widget.background != old.background) {
      _heldIndex = -1;
      _held = null;
    }
  }

  Widget _pageFor(BuildContext context, int index) {
    if (_heldIndex != index || _held == null) {
      _heldIndex = index;
      _held = ColoredBox(
        color: widget.background,
        child: widget.itemBuilder(context, index),
      );
    }
    return _held!;
  }

  @override
  Widget build(BuildContext context) {
    final pager = PageView.builder(
      controller: widget.controller,
      itemCount: widget.itemCount,
      onPageChanged: widget.onPageChanged,
      itemBuilder: (context, index) {
        final content = widget.itemBuilder(context, index);
        if (!widget.folding) return content;
        return _PinnedPage(
          controller: widget.controller,
          index: index,
          child: content,
        );
      },
    );
    if (!widget.folding) return pager;
    return Stack(
      fit: StackFit.expand,
      // A sheet lifting toward the reader is nearer than the screen, so
      // perspective draws it slightly larger than the page it came from and
      // its free edge passes outside the column. Clipping that would saw the
      // edge off at the exact moment the lift is most visible.
      clipBehavior: Clip.none,
      children: [
        pager,
        // Decoration only: every gesture belongs to the pager underneath, so
        // dragging, selecting and long-pressing behave exactly as they do
        // with folding switched off.
        IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final frame = foldFrameFor(pagerPage(widget.controller));
                if (frame == null ||
                    frame.index < 0 ||
                    frame.index >= widget.itemCount) {
                  return const SizedBox.shrink();
                }
                final leaving = _pageFor(context, frame.index);
                final hinge = constraints.maxWidth * widget.spineFraction;
                if (hinge <= 0) {
                  return FoldingPage(turn: frame.turn, child: leaving);
                }
                return _SpreadLeaf(
                  turn: frame.turn,
                  width: constraints.maxWidth,
                  hinge: hinge,
                  spread: leaving,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A two-page spread mid-turn: the left page flat, the right one lifting.
///
/// Only the right-hand page is a free leaf. The left one is resting on the
/// stack already and does not move â€” it is replaced when the leaf lands,
/// which is the moment a real book shows you what was on the back of it.
class _SpreadLeaf extends StatelessWidget {
  const _SpreadLeaf({
    required this.turn,
    required this.width,
    required this.hinge,
    required this.spread,
  });

  final double turn;
  final double width;

  /// Distance from the left edge to the spine.
  final double hinge;

  /// The whole outgoing spread. Shown twice â€” its left half flat, its right
  /// half turning â€” by clipping to one side and sliding the content across.
  final Widget spread;

  /// One side of [spread], clipped out of the full-width original so both
  /// halves keep the pagination and margins they were laid out with.
  Widget _half(Alignment side, double sliceWidth) => ClipRect(
    child: OverflowBox(
      alignment: side,
      minWidth: 0,
      maxWidth: width,
      child: SizedBox(width: width, child: spread),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: hinge,
          child: _half(Alignment.centerLeft, hinge),
        ),
        Positioned(
          left: hinge,
          top: 0,
          bottom: 0,
          width: width - hinge,
          // The clip sits inside the fold, so it is the leaf that is being
          // cut out of the spread â€” and it then rotates with it, rather than
          // shearing the sheet against a fixed rectangle as it lifts.
          child: FoldingPage(
            turn: turn,
            child: _half(Alignment.centerRight, width - hinge),
          ),
        ),
      ],
    );
  }
}

/// Holds one page still while the pager scrolls under it.
///
/// A [PageView] slides its children past the viewport; a book does not. This
/// cancels that movement for the two pages on screen so the one underneath
/// waits to be uncovered, and hides everything else â€” including the folding
/// page, which the overlay is drawing instead.
class _PinnedPage extends StatelessWidget {
  const _PinnedPage({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: controller,
        // Passed through rather than rebuilt: this runs every frame of a
        // turn, and the page's text does not change while it turns.
        child: child,
        builder: (context, child) {
          final page = pagerPage(controller);
          // Unreadable position: leave the page exactly where the pager put
          // it. Mid-swap that is a frame of ordinary sliding, which is far
          // better than a frame of nothing.
          if (page == null) return child!;
          // One page and no other. See [paintedPageFor] â€” pinned pages all
          // occupy the same rectangle, so a second one is not an overlap but
          // a second chapter printed over the first.
          if (index != paintedPageFor(page)) return const SizedBox.shrink();
          return Transform.translate(
            offset: Offset((page - index) * constraints.maxWidth, 0),
            child: child,
          );
        },
      ),
    );
  }
}
