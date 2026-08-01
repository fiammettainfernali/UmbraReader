# Finding a book: search, filter and sort

An audit of how books are found in a 486-series library, and a plan to fix it.

Scope is *discovery* — getting from "the library" to "this book". In-book
text search and library-wide full-text search are deliberately out of scope.

## Where it stands

Everything lives in `lib/screens/library_filters.dart` as the
`LibraryFiltering` mixin, rendered by `buildControls()` above the grid: a
search bar, three icon buttons (search-inside-books, filter, sort), five
reading-state chips, and a count line.

| Surface | What it does |
| --- | --- |
| Search | `contains()` on title and author |
| Sort | 5 options, ascending only, via `PopupMenuButton` |
| Filter sheet | genres (any-match), reading status, downloaded, multi-volume |
| Chips | All / Reading / Unread / Finished / Dropped, single-select |

## What's wrong

### 1. Nothing persists

Search, filters, sort and the chip all reset to defaults on every launch.
No writes to prefs or SQLite exist for any of them.

At 486 series this is the single biggest daily cost: every session starts
by rebuilding the view you were using yesterday. Every other piece of user
state in the app — progress, bookmarks, collections, reader settings,
themes — persists and syncs. The library view is the exception.

### 2. Search only matches a literal substring of title or author

`title.toLowerCase().contains(query)`. Consequences:

* **Word order matters.** "hunter primal" finds nothing.
* **Every gap matters.** "primalhunter" finds nothing.
* **Typos fail completely.** No tolerance of any kind.
* **Accents fail.** No diacritic folding.
* **Description and genres aren't searched**, so you cannot find a book by
  what it's about — only by remembering its exact name.

Translated webnovel titles are long, similar, and easy to half-remember
("Longevity by Picking up Attributes in the Battlefield"). Exact-substring
is the worst possible fit for this library.

### 3. Sort is thin, one-directional, and the last popup menu left

Five options, all ascending — no way to reverse any of them. Missing the
sorts the library actually invites: length, how far through you are, how
much time you've spent.

It is also still a `PopupMenuButton`, the pattern replaced everywhere else
in the app for being cramped, top-right, and unreachable one-handed.

### 4. Filters can't express the useful questions

Genres are **any-match**: picking Cultivation and Xianxia widens the result
rather than narrowing it, and there's no way to say "both". There is no
filter for length, update recency, how far through you are, or collection
membership.

The question you actually want to ask — *"a completed Cultivation series I
haven't started, under 800 chapters"* — cannot be expressed.

### 5. Controls don't exist outside the main grid

`collection_detail_screen`, `filtered_series_screen` and
`imported_books_screen` have no search, filter or sort at all. A collection
of 80 series is an unsorted, unsearchable wall.

### 6. Smaller things

* `filtersAreClear` is defined and **never used** — so the empty state
  can't tell "you have no books" from "nothing matched", and offers no way
  to clear the filter that caused it.
* The filter sheet is still the old stock modal, not the grouped-card
  action-sheet language the rest of the app now uses.
* No recent searches.
* The count line ("12 of 486 series") is the only indication that a filter
  is active besides a dot on the icon; you can't see *which* filters are on
  without opening the sheet.

### 7. Metadata held but unusable

`Series` carries `description`, `totalChapters`, `downloadedChapters`,
`updatedAt`, `genres` and `readingStatus`. Reading progress and per-series
reading time are available from the stores. Of these, only genres, status
and `updatedAt` (sort only) are reachable. Everything else is dead weight
in the model.

Novel Grabber also has a `smart_collections` table the app never reads.

---

## Plan

### Tier 1 — Make the view stick, and finish what's half-done

The cheapest work with the largest daily payoff.

1. **Persist search, sort, filters and the chip.** A `LibraryViewStore` on
   the SQLite kv table, following the existing store shape, with
   `exportSyncBlob`/`mergeSyncBlob` so the view follows you between phone
   and iPad like everything else does.
2. **Sort direction toggle** — every option gains an ascending/descending
   arrow.
3. **Sort menu becomes an action sheet**, matching the rest of the app.
4. **Filter sheet restyled** to the grouped-card language.
5. **Wire up `filtersAreClear`**: an empty state that distinguishes no
   books from no matches, with a one-tap "Clear filters".

### Tier 2 — Make search find things

6. **Tokenized matching.** Split the query on whitespace; a series matches
   when *every* token appears somewhere in its searchable text. Fixes word
   order and partial recall in one change.
7. **Normalise before comparing** — fold diacritics, strip punctuation, so
   "Re:Zero" and "rezero" both land.
8. **Widen the haystack** to genres and description, and **rank** results:
   title-start beats title-substring beats author beats genre beats
   description. When a query is active, ranking replaces the sort order —
   the best match should be first, not whichever match sorts first
   alphabetically.
9. **Recent searches** under an empty search bar.

Deliberately *not* doing fuzzy/edit-distance matching yet: tokenizing plus
a wider haystack fixes most real misses, and fuzzy matching at 486 series
risks burying exact matches under noise. Revisit if misses persist.

### Tier 3 — Slice by what the library actually holds

10. **New filters:** length band (chapters), updated-within, progress state
    (untouched / started / nearly done), collection membership.
11. **Genre AND/OR toggle**, defaulting to OR to preserve today's behaviour.
12. **New sorts:** length, progress, time spent reading.
13. **Active filters as inline chips** above the grid, each removable with
    one tap — so the filter state is visible and reversible without
    reopening the sheet.

### Tier 4 — Saved views

14. **Save the current query + filters + sort as a named shelf**, listed
    alongside Collections. This is the real answer to a 486-series library:
    "Unread Cultivation, longest first" becomes a place you go, not a thing
    you rebuild.
15. Optionally mirror Novel Grabber's `smart_collections` so a shelf
    defined on the desktop shows up here.

### Tier 5 — Optional, server-assisted

16. Novel Grabber's FTS5 index covers all 568k chapters, including books
    not downloaded. A control-API endpoint would let the app find a series
    by remembering a *scene* from it. Worth its own decision; it is a
    different feature from everything above.

---

## Where to start

**Tier 1, then Tier 2.** Persistence is the thing you feel every single
launch, and it's mostly plumbing against a store pattern that already
exists. Tier 2 is what makes the search bar trustworthy — and once search
is reliable, some of the pressure comes off filtering entirely.

Tier 3 and 4 are worth doing, but they're additive: they widen what you can
ask. Tiers 1 and 2 fix things that are actively wrong.
