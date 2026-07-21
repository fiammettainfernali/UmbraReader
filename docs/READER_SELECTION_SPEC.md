# Tier 3 spec — free-text selection → highlight / copy / note / define / translate

The marquee gap from the reader-UX audit (`READER_UX_AUDIT.md`, T6). This is a
design + implementation spec, not applied work. It's deliberately detailed
because this is the one reader feature that warrants a new interaction layer,
and the naive approach has already failed once.

---

## 1. Goal

Select a range of text with your finger, then act on it: **copy, highlight (in a
colour), attach a note, look it up in the dictionary, translate, or share.**
Today you can long-press a single *word* for the dictionary and tint a whole
*paragraph* as a highlight — but you can't select a phrase.

## 2. Why it's hard (read before designing)

Four constraints shape every decision here:

1. **`SelectionArea` already lost.** Wrapping the reader in Flutter's
   `SelectionArea` fought the reader's gesture arena (taps, page-turns,
   long-press) and was abandoned (ROADMAP #13). We will **not** retry it. The
   selection layer must be custom.
2. **The pagination invariant.** Render and measurement must use identical text
   (`effectiveRuns` + the exact `TextStyle`, letter/word spacing explicit).
   Selection geometry has to reuse the *same* `TextPainter` inputs or the
   highlight rectangles drift from the glyphs — worst on fixation-anchor mode,
   which widens wrapping. `_wordAt` already does this correctly; extend it,
   don't reinvent it.
3. **The gesture arena is already crowded.** Taps (page turn / chrome),
   long-press (dictionary / quick-capture), conditional double-tap, the 24px
   brightness gutter, and the `PageView`'s own horizontal swipe all share the
   surface. A drag-to-select over the whole content area would fight the
   scroll/swipe — this is precisely what sank `SelectionArea`.
4. **Paged vs scroll geometry differ.** Scroll mode lays all blocks in one
   scrollable; paged mode slices blocks into discrete pages. Cross-paragraph
   selection is natural in scroll mode and awkward in paged mode.

## 3. The core idea that avoids the arena fight

**Don't make the content a drag-select surface. Seed a selection with a
long-press, then extend it by dragging discrete handle widgets.**

- **Long-press a word → select that word** (instead of immediately opening the
  dictionary). Show two draggable handles at the word's ends and a floating
  action toolbar. This is the iOS-native text pattern, so it's familiar.
- **The handles are their own hit targets.** Dragging a handle is a gesture on
  a small handle widget, not on the content — so it never competes with the
  scroll/swipe recogniser. This is the whole trick: the only new *content*
  gesture is the long-press we already have.
- **A tap anywhere else dismisses** the selection (and does nothing else that
  tap).
- While a selection is active, page-turn taps and swipes are suppressed; in
  scroll mode, auto-scroll is paused.

Cost: long-press-for-instant-dictionary becomes long-press → word selected →
tap **Define**. One extra tap for the dictionary, in exchange for copy /
highlight / note / translate. This matches every mainstream reader and iOS
itself. (Quick-capture on empty space is unchanged.)

## 4. Data model

Highlights are currently **block-level**: `Bookmark(chapterIndex, blockIndex,
isHighlight, color, note)` tints a whole paragraph. Range selection needs
**character offsets**, possibly spanning blocks.

Proposed: extend the annotation with an optional range, keeping the block anchor
for back-compat and list rendering.

```
// added to Bookmark (all optional, absent on legacy block highlights)
int?    endBlockIndex   // inclusive; == blockIndex for single-block ranges
int?    startChar       // char offset into blockIndex's joined run text
int?    endChar         // char offset into endBlockIndex's joined run text
String  selectedText    // the exact selected string (for copy/note/share/list)
```

- **Back-compat:** a highlight with no `startChar` is a whole-block highlight and
  renders exactly as today. New selections carry the range. `fromJson`/`toJson`
  gate the new keys behind presence, like the existing `isHighlight`/`color`
  keys.
- **Offsets are into the block's joined run text** — the same string `_wordAt`
  builds (`paragraph.runs.map((r) => r.text).join()`), so they survive font and
  margin changes just like `blockIndex` does. They do **not** survive a re-scrape
  that changes the text; acceptable and no worse than block indices today.
- Highlights already sync (BookmarkStore union-by-id); the extra fields ride
  along for free.

## 5. Rendering selections and highlights

Both the live selection and persisted highlights paint the same way, upgrading
today's block tint to a range tint.

- Per block in `[startBlock … endBlock]`, build the block's `TextPainter` with
  `effectiveRuns` + the block's style (reuse the `_wordAt` setup), then call
  `getBoxesForSelection(TextSelection(baseOffset, extentOffset))` to get the
  glyph rectangles. First block: `startChar…len`; middle blocks: `0…len`; last
  block: `0…endChar`.
- Paint those rects in an **overlay `CustomPainter`** positioned like
  `LineFocusOverlay` (pointer-transparent, theme-tinted). Live selection uses a
  system-blue-ish wash; saved highlights use the categorical colour blended
  against the theme (as today).
- Handles are two small widgets positioned at the first/last box edges.

## 6. The action toolbar

A floating bar above (or below) the selection: **Copy · Highlight ▸ (4 colours)
· Note · Define · Translate · Share.**

- **Copy** → clipboard (`selectedText`).
- **Highlight** → create/update a range `Bookmark(isHighlight: true)`; a colour
  sub-row. Tapping an existing highlight re-opens this bar to recolour/remove.
- **Note** → highlight + the existing one-field note sheet (reuse quick-capture's
  sheet).
- **Define** → `DictionaryService().define` (the current long-press action; if
  the selection is one word, identical result).
- **Translate** → open the OS translate sheet for `selectedText` (iOS has a
  system translate action; a share-sheet fallback otherwise).
- **Share** → the share sheet with `selectedText` + book/chapter attribution.

## 7. Paged-mode limitation (call it out now)

In scroll mode, cross-paragraph selection is natural. In paged mode, the next
paragraph may be on the next page, which isn't laid out contiguously. **v1
restricts a paged-mode selection to the current page** (clamp `endBlock` to the
last block whose box is on-screen). Scroll mode gets full cross-block selection.
This is an honest, documented limitation, not a bug — matching how several
readers behave.

## 8. Phasing

- **Phase A — single-block MVP. SHIPPED 2026-07-21.** Long-press selects the
  word (scroll mode); a long-press *drag* extends the selection within the
  paragraph out from the seed word (no separate handle widgets — the extension
  rides the long-press gesture that already won the arena, per §3); a Copy /
  Define / 4-colour-Highlight bar appears; a tap dismisses. Range model landed
  as four `Bookmark` fields + a drift schema v6 migration (`startChar`,
  `endChar`, `endBlockIndex`, `selectedText`); range *rendering* reuses
  `BlockView`'s span-splitting (generalised from the single read-aloud range to
  a list of coloured ranges), so no CustomPainter or `getBoxesForSelection` was
  needed and measure==render holds for free. Paged mode keeps the old
  instant-dictionary long-press until Phase D. Covered by `reader_tap_zones_test`
  (select→Define, Copy→clipboard, Highlight→persisted range) and an updated
  `reader_quick_capture_test`. Handle-drag *re-adjustment* after release,
  deferred to a follow-up.
- **Phase B — cross-block (scroll mode).** Extend handles across paragraphs;
  multi-block box painting; Note.
- **Phase C — Translate + Share**, and re-tapping a highlight to edit/remove.
- **Phase D — paged-mode selection** (single page), if wanted.

## 9. Testing

- **Geometry unit-ish:** feed known offsets through the block `TextPainter` and
  assert `getBoxesForSelection` rects are non-empty and ordered — pins the
  measure==render alignment.
- **Model:** range `Bookmark` round-trips `toJson`/`fromJson`; legacy block
  highlight still loads; sync union-by-id preserves ranges.
- **Widget:** long-press selects a word (handles + toolbar appear); Copy puts the
  right string on a mock clipboard; Highlight creates a persisted range;
  tap-away dismisses. Drive real gestures through `ReaderScreen` like
  `reader_tap_zones_test`.
- **Regression:** a tap still turns the page and a long-press on empty space
  still quick-captures, with selection enabled.

## 10. Risks & open questions

- **R1 — handle-drag precision on touch.** Handles need a generous invisible hit
  area (≥ 44px) offset from the glyph so the finger doesn't cover the text.
- **R2 — long-press repurposing.** Changing long-press from instant-dictionary
  to select-word is a behaviour change for an existing gesture. Mitigation: it's
  the platform-standard model and Define is one tap away; consider a settings
  note. (Predictability contract is fine — still user-initiated.)
- **R3 — paged geometry.** `getBoxesForSelection` in a multi-column / TV spread
  needs the per-column painter; reuse `_pagedColumnTextWidth`/`_pagedHit`, which
  already handle stride.
- **R4 — RTL / vertical text.** Out of scope for v1; selection assumes LTR
  (as `_wordAt` does).
- **Open:** does iOS expose a first-class Translate action to Flutter, or is it
  share-sheet only? Decide in Phase C.

## 11. Recommendation

Build **Phase A** as a self-contained slice and stop to evaluate on-device: it
proves the hard parts (range model, measure==render box painting, handle drag
without an arena fight) at the smallest scope, and it already delivers
copy + phrase-highlight, which is most of the felt value. Phases B–D are
incremental once A's geometry is trusted. Estimate: Phase A ~3–4 focused days;
B–D another ~1 week total. This stays a multi-slice project — do not attempt it
in one pass.
