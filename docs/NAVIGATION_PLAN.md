# Navigation — audit + improvement plan

Written 2026-07-24. Plan, not applied work.

---

## What the structure actually is

Eighteen screens, **no bottom bar, no tabs, no drawer**. One home screen
(Library) and a push stack on top of it. Everything that isn't a book is
reached through a single **"More" overflow menu** in the library app bar,
which currently holds seven unrelated destinations in a flat list:

> Collections · Stats · Storage · Imported books · Manage · Backup · Settings

That is a junk drawer. It mixes *content* (Collections, Imported books),
*insight* (Stats), *maintenance* (Storage, Backup), *a remote control*
(Manage) and *configuration* (Settings) at one level with no grouping, so
finding anything means reading all seven every time.

## The concrete problems

**1. Your highlights are hidden inside a book.**
`HighlightsScreen` has exactly one entry point in the whole app: the bookmarks
sheet *inside the reader*. So seeing annotations across your library means
opening some book, opening its bookmarks sheet, then tapping through — and
there is no route to them from the library at all. For a feature that spans
every book, living inside one book is the wrong home.

**2. Adding a book is three taps behind a misleading name.**
`NovelSearchScreen` is reachable only from `ManageScreen`. So: More → Manage →
search icon. "Manage" reads as queue administration, not "get new books", so
the most expansive thing you can do with the app is also among the hardest to
find.

**3. Stats is a dead end.**
`stats_screen.dart` contains no route to a book or series. You can see that a
series took forty hours — including in the new by-series breakdown — and cannot
tap it to go there. Every other list in the app leads somewhere.

**4. There is no cross-navigation generally.**
Screens are leaves. The reader can reach the glossary, but not the series it
belongs to. Collections reach series (via detail), which is right, but that is
the exception.

**5. Depth is inconsistent for equally common actions.**
Continue reading is one tap from the library. Checking your own highlights is
four. Adding a book is three. None of that reflects how often each is done.

## What is already good (do not break it)

- **Continue reading is one tap** from the library — the most common action is
  correctly the cheapest, and the shelf is the first thing on screen.
- The reader's own menu (contents / search / bookmarks / glossary / settings)
  is well-grouped and stays out of the way.
- Long-press on a library cover gives a useful shortcut menu.
- Back behaviour is plain and predictable — a straight push stack with no
  surprise interception, which the predictability contract wants.

---

## Plan

### Tier 1 — Give the app a spine — SHIPPED 2026-07-24

Both parts built. Scope grew once constructors were checked: `HighlightsScreen`
turned out to be *per-book* (it requires a Volume) and `BookmarkStore` had no
cross-volume query, so a Notes tab meant a new `allMarks()` and a new
library-wide `NotesScreen`, not wiring. That is also why the dead end was so
complete — nothing in the app could ask the question.

`HomeShell` holds Library / Discover / Notes / You in an `IndexedStack`, so
tabs keep their scroll position (Tier 3's item, free). Stats and Manage left
the More menu; settings, storage, backup and imported books stayed there as
configuration. The reader still pushes over the shell, so reading is
full-screen. 4 tests.

**T1a. Replace the "More" junk drawer with a bottom navigation bar.**
Four destinations, chosen by how often they are actually used:

| Tab | Holds |
| --- | --- |
| **Library** | the grid, Continue shelf, recommendations (unchanged) |
| **Discover** | add a book (novel search), Manage/download queue |
| **Notes** | highlights, bookmarks, glossaries across all books |
| **You** | stats, goals, streaks |

Settings, Storage, Backup and Imported books move to a **single Settings
screen** reached from a gear in the Library app bar — they are configuration
and maintenance, not places you go.

This fixes problems 1, 2 and 5 at once: highlights get a home, adding a book
becomes one tap, and depth starts matching frequency.

*Effort ~2–3 days. Risk: moderate — it restructures the app's root, so the
reader's push-over-everything behaviour and the predictability contract both
need checking.*

**T1b. Make Stats tappable.** Every series row in the by-series breakdown
routes to that series. One line of wiring; removes the dead end.

*Effort: under a day.*

### Tier 2 — Cross-navigation — SHIPPED 2026-07-24

Reader gains **Go to series**, so finishing a volume leads to the next rather
than ending at the back button; a series no longer in the library says so
instead of failing. Notes → passage already landed with the Notes screen.
Library search was promoted to a permanent app-bar icon, so the three search
entry points (library, in-book, novel) are each one tap from their context.

- **Reader → series.** A "go to series" item in the reader menu, so finishing a
  volume leads naturally to the next.
- **Notes tab → the passage.** Tapping a highlight opens the book at it —
  `ReaderScreen` already takes an initial position, so the mechanism exists.
- **Search everywhere.** Library search, in-book search and novel search are
  three separate entry points; at minimum they should be findable from one
  another.

### Tier 3 — Polish — SHIPPED 2026-07-24

Per-tab scroll position and the Notes empty state both landed with the shell
(`IndexedStack`). The two rare app-bar icons — random book, download-whole-
library — moved into the menu, and search took the freed space: permanent bar
real estate should go to what is used often.

- A consistent empty state per tab (Notes with no highlights should explain how
  to make one).
- Preserve scroll position per tab across switches.
- Reconsider the two library app-bar icons (random book, download-all) — both
  are rare actions occupying permanent space.

---

## Principles this must respect

- **The predictability contract.** A bottom bar changes what is on screen
  without the reader asking, once, at launch — that is a structural change they
  opt into by updating, not motion during use. But tab switches must not
  reorder anything, and the reader must still push *over* the bar so reading
  stays full-screen.
- **Continue reading stays one tap.** Any restructure that costs a tap on the
  most common action has failed regardless of what else it fixes.
- Accessibility: tab targets ≥ 44px, and the bar must carry proper semantics
  labels.

## Recommendation

**T1b first** — it is under a day and removes a real dead end. Then **T1a**,
which is the actual fix but reshapes the app's root and deserves its own
session. Tiers 2–3 only make sense once the spine exists.
