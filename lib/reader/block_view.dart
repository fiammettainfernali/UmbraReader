import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/content_block.dart';
import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import 'reader_layout.dart';

/// Renders one [ContentBlock] with the active theme and typography.
class BlockView extends StatelessWidget {
  const BlockView({
    super.key,
    required this.block,
    required this.settings,
    required this.preset,
    this.isLast = false,
    this.highlightStart,
    this.highlightEnd,
    this.highlightColor,
  });

  final ContentBlock block;
  final ReaderSettings settings;
  final ReaderThemePreset preset;

  /// True for the last block on a page — its trailing gap is dropped so the
  /// content can sit flush against the page bottom.
  final bool isLast;

  /// Character range to highlight (the sentence being read aloud), or null.
  final int? highlightStart;
  final int? highlightEnd;

  /// Non-null when the user has saved a passage highlight on this block —
  /// the paragraph/heading body is painted with the matching tint.
  final HighlightColor? highlightColor;

  @override
  Widget build(BuildContext context) {
    switch (block) {
      case ParagraphBlock paragraph:
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : kParagraphGap),
          child: _maybeTint(
            child: Text.rich(
              TextSpan(
                children: _spansFor(
                  context,
                  paragraph.runs,
                  paragraphStyle(settings, preset.text),
                ),
              ),
              textAlign: settings.textAlign == ReaderTextAlign.justify
                  ? TextAlign.justify
                  : TextAlign.left,
              textScaler: TextScaler.noScaling,
            ),
          ),
        );
      case HeadingBlock heading:
        return Padding(
          padding: EdgeInsets.only(
            top: kHeadingTopGap,
            bottom: isLast ? 0 : kHeadingBottomGap,
          ),
          child: _maybeTint(
            child: Text.rich(
              TextSpan(
                children: _spansFor(
                  context,
                  heading.runs,
                  headingStyle(settings, heading.level, preset.text),
                ),
              ),
              textScaler: TextScaler.noScaling,
            ),
          ),
        );
      case DividerBlock _:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              '✶  ✶  ✶',
              // inherit: false + fixed height so the divider renders exactly
              // the kDividerHeight the pagination budgeted (40 + 16*1.25).
              style: TextStyle(
                inherit: false,
                letterSpacing: 0,
                wordSpacing: 0,
                color: preset.secondary,
                fontSize: 16,
                height: 1.25,
              ),
            ),
          ),
        );
      case ImageBlock image:
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : kParagraphGap),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 900),
            child: Image.memory(
              image.bytes,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              semanticLabel: image.alt.isEmpty ? null : image.alt,
              errorBuilder: (_, _, _) => Container(
                height: 80,
                color: preset.secondary.withValues(alpha: 0.15),
                alignment: Alignment.center,
                child: Text(
                  image.alt.isEmpty ? '[image]' : '[${image.alt}]',
                  style: TextStyle(color: preset.secondary, fontSize: 12),
                ),
              ),
            ),
          ),
        );
    }
  }

  /// Wraps [child] in a soft tint matching the saved [highlightColor] when
  /// present; returns it unchanged otherwise. The tints are semi-transparent
  /// so they blend acceptably on both light (sepia/paper) and dark themes.
  Widget _maybeTint({required Widget child}) {
    final hc = highlightColor;
    if (hc == null) return child;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: highlightPaintFor(hc),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }

  /// Builds the run spans, giving the highlighted character range a
  /// background colour (splitting runs at the highlight boundaries).
  List<InlineSpan> _spansFor(
    BuildContext context,
    List<TextRun> runs,
    TextStyle base,
  ) {
    final hs = highlightStart;
    final he = highlightEnd;
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final run in runs) {
      final runStart = offset;
      final runEnd = offset + run.text.length;
      offset = runEnd;
      final style = base.copyWith(
        fontWeight: run.bold ? FontWeight.bold : null,
        fontStyle: run.italic ? FontStyle.italic : null,
      );
      // Footnote: emit a tappable inline widget that pops the note body in
      // a bottom sheet. Highlight handling is skipped — the marker is short.
      final footnote = run.footnoteBody;
      if (footnote != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => _showFootnote(context, run.text, footnote),
              behavior: HitTestBehavior.opaque,
              child: Text(
                run.text,
                style: style.copyWith(
                  color: preset.text.withValues(alpha: 0.85),
                  fontSize: (style.fontSize ?? 16) * 0.85,
                  decoration: TextDecoration.underline,
                  decorationColor: preset.text.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      if (hs == null || he == null || he <= runStart || hs >= runEnd) {
        spans.add(TextSpan(text: run.text, style: style));
        continue;
      }
      final a = (hs - runStart).clamp(0, run.text.length);
      final b = (he - runStart).clamp(0, run.text.length);
      if (a > 0) {
        spans.add(TextSpan(text: run.text.substring(0, a), style: style));
      }
      spans.add(
        TextSpan(
          text: run.text.substring(a, b),
          style: style.copyWith(backgroundColor: preset.highlight),
        ),
      );
      if (b < run.text.length) {
        spans.add(TextSpan(text: run.text.substring(b), style: style));
      }
    }
    return spans;
  }

  /// Pops a small bottom sheet with the translator-note body when the
  /// inline marker is tapped.
  void _showFootnote(BuildContext context, String marker, String body) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Translator note  $marker',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// The translucent paint for a saved [HighlightColor] — shared by the
/// reader blocks and the bookmark/highlight pickers so swatches match the
/// painted passages. The tints are semi-transparent so they blend
/// acceptably on both light (sepia/paper) and dark themes.
Color highlightPaintFor(HighlightColor color) {
  switch (color) {
    case HighlightColor.yellow:
      return const Color(0xFFFFE066).withValues(alpha: 0.32);
    case HighlightColor.blue:
      return const Color(0xFF66B5FF).withValues(alpha: 0.30);
    case HighlightColor.pink:
      return const Color(0xFFFF8FB5).withValues(alpha: 0.30);
    case HighlightColor.green:
      return const Color(0xFF8FE08F).withValues(alpha: 0.30);
  }
}
