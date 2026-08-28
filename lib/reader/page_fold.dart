/// Turning a page like a sheet of paper instead of sliding it.
///
/// The awkward part of a page turn in Flutter is paint order. A turn means
/// the page you are leaving lifts and rotates away while the next one lies
/// flat underneath — so the *outgoing* page has to be on top. A [PageView]
/// paints its children in index order, which puts the incoming page above
/// the outgoing one: exactly backwards, and not something a property can
/// change.
///
/// The way out is not to replace the pager. The [PageView] keeps doing all
/// the work it is good at — drag physics, snapping, scroll notifications,
/// keeping the reader's chapter-crossing and seeking intact — and the page
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
/// so it stays sharp at any angle — which is the practical reason to prefer
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

  /// 0 flat, 1 edge-on. Never quite reaches either — see [foldFrameFor].
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
/// overlay permanently alive — one page built twice, forever, for a fold
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
/// pager for another — which is exactly what unfolding the phone does — the
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

/// One page, rotated about its spine.
///
/// The hinge is the left edge because that is where the spine is in a
/// left-to-right book: the sheet's free edge is on the right, and turning
/// forward sweeps it leftward until the page is edge-on and the next one is
/// fully uncovered.
class FoldingPage extends StatelessWidget {
  const FoldingPage({super.key, required this.turn, required this.child});

  /// 0 flat, 1 edge-on.
  final double turn;
  final Widget child;

  /// How much of a right angle the sheet has swung through.
  static double angleFor(double turn) => -turn.clamp(0.0, 1.0) * math.pi / 2;

  /// How dark the sheet has gone as it turns out of the light.
  ///
  /// Held well below opaque: the page is turning away, not being switched
  /// off, and a fold that ends in black reads as a flicker.
  static double shadeFor(double turn) => 0.34 * turn.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        // Perspective. Without it the page shrinks horizontally instead of
        // rotating, which looks like a window blind rather than paper.
        ..setEntry(3, 2, 0.0012)
        ..rotateY(angleFor(turn)),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Darkest at the spine, where the sheet has turned furthest
                // from the reader.
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: shadeFor(turn)),
                    Colors.black.withValues(alpha: shadeFor(turn) * 0.25),
                  ],
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
    this.onPageChanged,
    this.folding = true,
  });

  final PageController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int>? onPageChanged;

  /// When false this renders a bare [PageView] and nothing else happens.
  final bool folding;

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
    // A new builder means new content — repagination, a font change, a new
    // chapter. Anything held is describing the old text.
    if (!identical(widget.itemBuilder, old.itemBuilder) ||
        widget.itemCount != old.itemCount) {
      _heldIndex = -1;
      _held = null;
    }
  }

  Widget _pageFor(BuildContext context, int index) {
    if (_heldIndex != index || _held == null) {
      _heldIndex = index;
      _held = widget.itemBuilder(context, index);
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
      children: [
        pager,
        // Decoration only: every gesture belongs to the pager underneath, so
        // dragging, selecting and long-pressing behave exactly as they do
        // with folding switched off.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final frame = foldFrameFor(pagerPage(widget.controller));
              if (frame == null ||
                  frame.index < 0 ||
                  frame.index >= widget.itemCount) {
                return const SizedBox.shrink();
              }
              return FoldingPage(
                turn: frame.turn,
                child: _pageFor(context, frame.index),
              );
            },
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
/// waits to be uncovered, and hides everything else — including the folding
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
          final delta = page - index;
          // Anything a full page away is off screen in a book even though
          // the pager keeps it alive.
          if (delta.abs() >= 1) return const SizedBox.shrink();
          // The folding page is drawn by the overlay, on top, where it
          // belongs. Drawing it here as well would put a flat copy of it
          // under the next page.
          final frame = foldFrameFor(page);
          if (frame != null && frame.index == index) {
            return const SizedBox.shrink();
          }
          return Transform.translate(
            offset: Offset(delta * constraints.maxWidth, 0),
            child: child,
          );
        },
      ),
    );
  }
}
