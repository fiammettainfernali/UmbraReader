# Menus, sheets and dialogs — audit

Written 2026-07-24, after the navigation work. Findings and a plan; not
applied work.

Surface inventory: **7 popup menus, 15 modal sheets, 17 dialogs.**

---

## The one that matters: destructive actions are inconsistently guarded

Deleting a **collection** — a shelf you can rebuild in seconds — pops a
confirmation dialog. Deleting a **glossary entry you hand-wrote** or a
**highlight you saved from a passage** does neither: one tap on a trash icon
and it is gone, with no dialog, no snackbar, and no undo.

```
collections_screen   delete → AlertDialog confirm      ✓
glossary_screen      delete → store.remove(), reload   ✗  no confirm, no undo
bookmarks_sheet      delete → store.remove(), reload   ✗  no confirm, no undo
```

That is backwards. The guard is on the cheap, recreatable thing and absent on
the authored, unrecoverable ones — a glossary entry is typed by hand, and a
highlight marks a passage you had to find. Both now sync, so a mis-tap
propagates to every device.

There is exactly **one** `SnackBarAction` in the entire app (quick-capture's
"Add words"), so undo is not an established pattern to lean on.

**Fix:** give both an undo snackbar rather than a confirmation dialog. Undo
suits a reading app better than a modal — it does not interrupt, it costs
nothing when the tap was intended, and it matches the "never nag" principle
the reminders and streak grace already follow. A confirm dialog on every
highlight delete would be its own kind of friction.

## Second: three different menu-item styles

| Surface | Item rendering |
| --- | --- |
| Reader menu | custom `_MenuRow` — icon + label |
| Library, Series detail, Bookmarks, Filters | `ListTile` with zeroed padding |
| Collections | **plain `Text`**, no icon at all |

Three renderings of the same control. Collections is the outlier worth fixing
first — its "Rename / Delete" items have no icons while every other menu in
the app does, so it reads as a different app. `_MenuRow` is the nicest of the
three and is already written; promoting it out of `reader_chrome.dart` into a
shared widget would let every menu use one thing.

## Third: sheet mechanics are good, and worth keeping

Genuinely well done, and I want it recorded so it does not drift:

- **All 15 modal sheets set `showDragHandle`.** Not one was missed.
- Height caps and `isScrollControlled` are applied where sheets can grow and
  skipped where they cannot — that variance is correct, not sloppiness.
- The note-input sheet owns its controller through a StatefulWidget, so the
  framework disposes it after the close animation (fixed earlier this session
  when the eager dispose surfaced in a test).

## Fourth: smaller observations

- **Reader menu is long.** Contents, Go to series, Search, Bookmarks,
  Glossary, Settings — plus four more when read-aloud is enabled. Ten items in
  one list is at the edge of scannable; if it grows again it wants dividers by
  group (navigate / annotate / configure).
- **`_MenuRow` is private to `reader_chrome.dart`** but is the best pattern —
  it should be shared rather than re-implemented.
- **No menu carries semantics labels** beyond its visible text. The tooltips on
  the buttons that open them do, so this is minor, but a menu item with only an
  icon would be unreadable to VoiceOver.
- Dialog button ordering (Cancel left, action right) is consistent everywhere
  checked — no finding.

---

## Plan

**Tier 1 — undo for destructive edits. SHIPPED 2026-07-24.** Both deletions
now offer an undo via a shared `showUndoSnackBar`, which also establishes the
pattern the app was missing (it had exactly one SnackBarAction before). The
restore paths are exact: a highlight comes back with its colour, note and
character range; a glossary entry with its term, note and accumulated
last-seen sighting. Tested, including that a double-tap on Undo doesn't
duplicate. Original item: Glossary entry delete and
bookmark/highlight delete both get an undo snackbar. Small, self-contained,
and it closes the only place where a single tap silently destroys something
the reader authored.

**Tier 2 — one menu-item widget.** Promote `_MenuRow` to a shared widget and
adopt it in all six popups, starting with Collections, which currently has no
icons at all.

**Tier 3 — group the reader menu** with dividers if it gains anything further,
and add semantics labels to menu items.

## Recommendation

Tier 1 alone. It is the only finding with a real cost to the reader; the rest
is consistency work that can ride along with whatever next touches those
screens.
