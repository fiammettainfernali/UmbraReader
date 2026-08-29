import 'package:flutter/material.dart';

/// Covers the frame in which a chapter changes.
///
/// Turning a page inside a chapter is a scroll the pager animates. Crossing
/// into the next chapter is not: the blocks are replaced, the new text is
/// paginated, and only *after* that frame is drawn does a post-frame
/// callback jump the pager to the start. In between, one frame renders the
/// new chapter at the page index the old one was on — a paragraph from the
/// middle of it, or a blank half-spread past its end.
///
/// That frame is the stutter people report at a chapter boundary, and it is
/// not the page-turn animation failing: a jump produces no intermediate
/// positions, so there is no turn to draw there in the first place.
///
/// So the arrival is held back and faded in. Sixteen milliseconds of nothing
/// would be its own flicker; a short fade reads as a deliberate transition,
/// and by the time it is over the jump has long since landed.
class ChapterFade extends StatefulWidget {
  const ChapterFade({
    super.key,
    required this.chapterIndex,
    required this.duration,
    required this.child,
  });

  /// Changing this is what counts as an arrival. Repagination within a
  /// chapter — the menu appearing, a font change — keeps the reader roughly
  /// where they were and does not need covering.
  final int chapterIndex;

  /// Zero for a reader who has asked for less motion: the frame is still
  /// hidden, it simply appears at once instead of fading.
  final Duration duration;

  final Widget child;

  @override
  State<ChapterFade> createState() => _ChapterFadeState();
}

class _ChapterFadeState extends State<ChapterFade> {
  // Opaque on first build. The reader opening a book is not an arrival to
  // cover — there is no previous chapter underneath to be caught between.
  double _opacity = 1;

  @override
  void didUpdateWidget(ChapterFade old) {
    super.didUpdateWidget(old);
    if (widget.chapterIndex == old.chapterIndex) return;
    // Hidden for the frame being built right now, and asked to come back on
    // the next one. Setting it straight back in a post-frame callback is
    // what makes this a fade rather than a permanent blanking: by then the
    // pager has been jumped and what fades in is the right page.
    _opacity = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: widget.duration,
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}
