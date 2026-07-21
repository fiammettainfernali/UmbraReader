# Reader interaction audit + improvement plan

Scope: the *reading surface itself* — tap zones, gestures, page-turn mechanics,
in-page interaction. Not the library, settings, or chrome screens. Written
2026-07-18. This is a plan, not applied work.

---

## 1. What Umbra does today

Mapped from `reader_screen.dart` (`_onContentTap`, `_advance`,
`_advancePage`, `_onContentLongPress`, `_handleKey`).

**Tap zones** (fixed, not configurable):
- Chrome **visible** → any tap hides it (edge zones dormant, so a
  dismiss-tap near an edge can't also flip a page — a deliberate fix).
- Chrome **hidden** → left 28% = previous, right 28% (x > 72%) = next,
  middle 44% = toggle chrome.

**Swipe:**
- Paged mode: a native `PageView.builder` with default physics — horizontal
  swipe both directions, animated (220 ms easeOut) or jump under reduce-motion.
- Scroll mode: native vertical scroll; a tap-advance moves 85% of the viewport.

**Keyboard / Bluetooth remote** (`_handleKey`): forward = →/↓/PageDown/Space;
back = ←/↑/PageUp. Routes through the same `_advance` as taps (so the ruler and
focus-paragraph logic apply uniformly — this is why a past remote+ruler bug
existed and was fixed).

**Long-press:** on a word → system dictionary; on empty space (margins,
inter-paragraph gaps, past a line end) → quick thought-capture bookmark.

**Haptics:** light on a page turn, medium on a chapter cross, selection on
ruler/focus steps — all gated by the haptics setting.

**Brightness:** a dimming overlay driven by a settings *slider*. **No gesture.**

**Page-turn feel:** one style only (slide for paged via PageView, scroll-jump
for scroll). No user choice; no curl.

**Notably absent:** configurable tap zones, left-hand/RTL swap, an
accidental-turn guard, a brightness gesture, a skim/peek gesture, double-tap or
corner gestures, and free-text selection (select a phrase to highlight/copy/
translate). Text selection was tried and shelved — `SelectionArea` fought the
reader's gesture arena and lost (ROADMAP #13).

## 2. How the field does it

| Reader | Tap zones | Menu | Brightness gesture | Skim | Customization |
| --- | --- | --- | --- | --- | --- |
| **Kindle** | big right = next, narrow left = back | **top bar** | — | — | minimal |
| **Apple Books** | left = back, rest = next | tap/center | — | — | minimal |
| **Kobo** | right = next, left = back, middle = menu | **center** (matches Umbra) | **swipe up/down on left edge** | **hold bottom corner** | swipe-only guard |
| **Moon+ Reader** | fully configurable | any | **slide left edge** | yes | 24 actions × 15 events, tilt, BT keys, page-curl w/ speed/color |
| **KOReader** | custom % zones + corners | any | edge slide | yes | 200+ actions, double-tap, two-finger, per-corner |

**Ergonomics consensus (NN/g + thumb-zone research):** the center and lower
screen are the easy-reach zone; top and far corners are hard. Vital,
frequent actions belong lower-centre under the thumb; rare/secondary controls
can live in top corners. Tap targets ≥ 44–48 px. Edge-initiated swipes
(bottom/side) sidestep thumb-reach limits — which is exactly why brightness-on-
the-edge and skim-from-the-corner became conventions.

## 3. Gap analysis

**Where Umbra already matches or leads:**
- Center-tap-for-menu matches Kobo (the closest analogue) — good, keep it.
- Haptic page/chapter feedback is better than several mainstream apps.
- Bluetooth-remote support with unified routing is ahead of Apple Books.
- Long-press quick-capture and reduce-motion are genuinely nice touches.

**Where it lags the field (ranked by how universal the missing thing is):**
1. **No brightness gesture.** Kobo and Moon+ both do edge-slide brightness; it's
   a near-universal expectation. Umbra *already has* the brightness state and a
   dimming overlay — only the gesture is missing.
2. **Tap zones are fixed.** No left-hand swap, no adjustable split, no
   swipe-only guard against accidental turns (Kobo ships this explicitly). For
   an app whose ethos is accessibility and personalization, hardcoded zones are
   an outlier.
3. **The forward zone is under-sized.** Next-page is the dominant action, yet it
   gets 28% while the menu gets 44%. Kindle deliberately makes *next* the
   largest zone. The split is backwards relative to action frequency.
4. **No skim/peek.** Kobo's hold-a-corner-to-skim (and swipe-up scrubbers
   elsewhere) let you glance ahead and snap back. Umbra has a chapter scrubber
   only inside the chrome — a mode switch, not a peek.
5. **No page-turn style choice.** ROADMAP #16. A *slide vs none* option is the
   e-ink-friendly, predictability-friendly subset (skip curl).
6. **No free-text selection.** The single biggest *feature* gap vs every
   mainstream reader: you can dictionary-lookup one word but can't select a
   phrase to highlight, copy, or translate. Hard (the shelved SelectionArea
   problem), but this is the marquee omission.
7. **Unused gesture vocabulary.** No double-tap, no corner actions — free
   surface for opt-in shortcuts (bookmark, TOC).

## 4. The plan (prioritized by impact-per-effort)

Every item below is opt-in and respects the house rules: the **Predictability
contract** (nothing moves unless the reader caused it — all these are
user-initiated, fine), **accessibility is never gated** (tap-zone control,
left-hand mode, and brightness gesture are accessibility → free), and the
**pagination invariant** (measure == render) is untouched by any of this since
none change text layout.

### Tier 1 — high impact, low/moderate effort, strong convention backing — SHIPPED 2026-07-18

Both shipped. `tapTurnZones` / `leftHandedTaps` / `tapZoneWidth` /
`edgeBrightnessGesture` on `ReaderSettings` (synced as ergonomic prefs), a
"Tap zones & gestures" settings section, rewritten `_onContentTap`, and a
left-edge brightness gutter with a heads-up readout in `reader_screen.dart`.
Covered by `reader_tap_zones_test.dart` (left-hand swap, swipe-only guard,
brightness drag). Default zone split moved from 28/44/28 to thirds. Note: the
brightness gutter is an opaque 24px strip, so a swipe/scroll starting in the
leftmost 24px does brightness, not a page turn — turn the gesture off to
reclaim it.

- **T1. Edge-slide brightness.** A vertical drag on a narrow left-edge strip
  adjusts `brightness` live, with a brief on-screen indicator. Feasibility note:
  in paged mode this is safe (the drag is vertical, `PageView` swipe is
  horizontal — different axes, no arena fight). In scroll mode a raw vertical
  drag *is* the scroll, so the strip must be a dedicated ~24 px gutter that
  claims vertical drags only there. Wire to the existing brightness overlay.
  *Effort: ~1 day. Risk: low (scroll-mode gutter needs care).*

- **T2. Tap-zone settings.** A "Tap zones" section in reader settings:
  (a) **left-hand mode** — swap forward/back sides; (b) **adjustable split** —
  a slider for the edge-zone width, defaulting to a *larger forward zone*
  (fixing gap #3, e.g. back 25% / menu 30% / forward 45%); (c) **swipe-only
  guard** — disable edge taps entirely for readers who mis-tap (Kobo parity).
  These are three settings over the existing `_onContentTap` math — no new
  gesture plumbing. *Effort: ~1–2 days. Risk: low; must keep the ruler/remote
  routing intact.*

### Tier 2 — high value, moderate effort

- **T3. Skim / peek — SHIPPED 2026-07-18 (adapted).** Delivered the *core value*
  — reversible exploration ("go look somewhere, snap back") — as a **"Back to
  your spot" return chip** rather than Kobo's corner-hold filmstrip. A
  discontinuous jump (a TOC tap, or a multi-chapter scrubber skip) records the
  prior position via a `recordReturn` flag on `_goToChapter`; a persistent chip
  then offers one-tap return (reusing `_jumpToSearchHit`) or a × to dismiss.
  Chosen over the filmstrip because (a) it fits 400-chapter webnovels better —
  the pain is "I jumped and lost my place", not "I want to fan through pages" —
  and (b) it sidesteps piling another press-hold-drag onto an already-crowded
  gesture arena. Ephemeral (never saved/synced), one level of undo. Covered by
  `reader_tap_zones_test`. Gesture-arena note discovered here: when a
  double-tap action is set, single taps (including the chip) resolve only after
  the ~300ms double-tap window — expected, and the default no-double-tap path is
  instant. A literal corner-hold page-skim remains open as a future add.

- **T4. Page-turn style option — SHIPPED 2026-07-18.** `pageAnimations` bool +
  an `_instantPageTurns` getter (`_reduceMotion || !pageAnimations`) driving the
  animate-vs-jump branches in `_advancePage`/`_advanceRulerScroll`. Lets a reader
  snap pages while keeping other motion, decoupled from global reduce-motion.
  Curl skipped by design. "Animate page turns" toggle in the gestures section.

- **T5. Opt-in gesture shortcuts — SHIPPED 2026-07-18.** `doubleTapAction` enum
  (none/bookmark/contents/bookmarks-list). Crucially, `onDoubleTap` is only
  wired when an action is set, so default users pay no single-tap
  disambiguation latency. Dispatches to the existing
  `_quickCaptureThought`/`_showTableOfContents`/`_openBookmarks`. Corner taps
  deliberately deferred (more arena complexity for less value). Covered by
  `reader_tap_zones_test` (instant-turn still advances; double-tap opens the
  assigned action).

### Tier 3 — the marquee gap, genuinely hard

- **T6. Free-text selection → highlight / copy / translate.** The one thing
  every mainstream reader has that Umbra doesn't. `SelectionArea` already lost
  the gesture-arena fight once, so the realistic path is a **custom selection
  layer built on the reader's own `TextPainter` math** — the same word-hit
  geometry the dictionary long-press already uses, extended to a drag range with
  draggable handles. Highlights would fold into the existing bookmark/notes
  store. *Effort: ~1–2 weeks. Risk: high — this is the hard one, spec it on its
  own before committing.*

## 5. Suggested order

Ship **T1 + T2** first: they're cheap, they're the most universal missing
conventions, they're pure accessibility wins, and they touch code that's already
well-understood (`_onContentTap`, the brightness overlay). Then **T4** (trivial)
and **T3/T5** as a gesture-polish pass. Treat **T6** as its own project with a
dedicated spec — it's where the effort and risk concentrate, and it's the only
item that warrants building a new interaction layer.

## Sources

- [Kindle navigation & tap zones — BrainVoyage](https://brainvoyage.blog/kindle-paperwhite-navigation-guide),
  [Kindle Touch gestures — Thomas Park](https://thomaspark.co/2012/01/kindle-touch-gestures/)
- [Kobo touch gestures](https://help.kobo.com/hc/en-us/articles/360017639973-Use-gestures-on-the-touch-screen),
  [Kobo brightness swipe](https://help.kobo.com/hc/en-us/articles/360017864933-Adjust-screen-brightness-on-the-Kobo-Books-app-for-Android),
  [Kobo prevent accidental page turns](https://help.kobo.com/hc/en-us/articles/21346752946839-Prevent-accidental-page-turns-while-reading)
- [Moon+ Reader Pro — Google Play](https://play.google.com/store/apps/details?id=com.flyersoft.moonreaderp),
  [KOReader gestures](https://www.ereadersforum.com/threads/how-to-customize-page-turns-and-gestures-in-koreader-on-any-e-reader.7807/),
  [KOReader user guide](https://koreader.rocks/user_guide/)
- [Apple Books reading controls](https://support.apple.com/guide/iphone/read-books-iphab7f0a8fa/ios)
- [Thumb-zone mobile UX — Parachute](https://parachutedesign.ca/blog/thumb-zone-ux/),
  [Designing for the thumb zone — Tim Graf](https://timgraf.com/ux-design/designing-for-the-thumb-zone-a-modern-guide-to-mobile-ux-that-respects-human-anatomy/)
