# Predictability — a design contract

> **Nothing moves, reorders, or pops up unless the reader caused it.**

This is not a feature and not a nice-to-have. It is a constraint every change
to Umbra is checked against, in the same way that reader `TextStyle`s must
carry explicit `letterSpacing` or pagination breaks. Features get built and
shipped; this gets *kept true*.

## Why it is worth a document

Umbra is built for a reader who reads for hours a day and whose attention is
expensive to re-establish. Unexpected motion costs more here than it does in
a general-purpose app:

- A shelf that reorders while a finger is descending means opening the wrong
  book, then having to find your way back.
- A dialog that appears unbidden takes the page away and does not say what it
  interrupted.
- Anything that changes when you did not touch it has to be *re-read* to find
  out whether it still says what it said.

The cost is not aesthetic. It is that the reader loses their place — in the
book, and in what they were doing.

## The rules

1. **No unprompted popups.** Dialogs, sheets, and snackbars follow a tap. If
   the reader did not just do something, nothing appears in front of the
   thing they were looking at.
2. **Order is stable within a session.** Lists reorder at boundaries the
   reader caused, never underneath them.
3. **Randomness is seeded, never live.** Anything that varies must vary on a
   stable seed (the date), so the same screen shows the same thing when
   re-opened. Rolling dice per build is forbidden.
4. **Timed UI is opt-in.** Nothing appears on a clock unless the reader
   switched that clock on.
5. **Background data merges silently; its visible effect waits.** Data may
   arrive whenever it likes. It may not rearrange the screen on arrival.
6. **No demands.** No badge counts, no streak pressure, no "you haven't…".
   See `reminder_service.dart`, whose copy is asserted against a banned-word
   list.

## What counts as "the reader caused it"

These are the boundaries at which deferred changes may surface:

- Opening the app, or returning to it from the background.
- Pull-to-refresh.
- Returning from a screen (closing a book, leaving settings).
- Any tap, drag, or scroll.

Note that *time passing* is not on this list, and neither is *another device
doing something*.

## Named exceptions

Exceptions are allowed, but they are named here, and each states why the rule
does not apply. An exception not on this list is a bug.

| Surface | Why it may move on its own |
| --- | --- |
| **Manage screen** (`manage_screen.dart`) | It is a live monitor of Novel Grabber's download queue. A remote process moving *is* the content; a queue view that froze would be broken. |
| **Read-aloud auto-advance** | The reader pressed play. Advancing is the thing they asked for. |
| **Auto-scroll / auto-page** | Explicitly opted into, with a speed the reader sets. |
| **Session break chip** | Only exists when `sessionMinutes > 0`, which is opt-in. |
| **"Where was I?" chip** | Appears because the reader opened a book after a gap. Additive chrome that moves no content, and it withdraws by itself. |
| **Download progress** | The reader started the download. |

## Audit — 2026-07-16

A pass over every timer, listener, stream, and popup in `lib/`.

### Fixed

- **The Continue Reading shelf reordered on iCloud merge.**
  `library_screen.dart` wired `CloudSyncService().onRemoteMerge` straight to
  `_loadReading()`, so progress syncing from another device rebuilt and
  reordered the shelf and the recommendation row *live* — at an arbitrary
  moment, caused by a phone in another room, potentially while a finger was
  already moving toward a cover. This was the clearest violation in the app.
  The merge now sets a pending flag; the stores still take the fresh data
  immediately (so opening a book uses the newest position), but the visible
  order waits for a boundary the reader caused: returning from a book,
  pull-to-refresh, or coming back to the app.

### Held — checked and already compliant

- **Recommendations do not reshuffle.** The out-of-taste wildcard picks with
  `Random(daySeed)` where the seed is the calendar date
  (`recommendation_engine.dart`), so it is stable all day rather than
  changing per open. Impressions are likewise recorded once per series per
  day.
- **No unprompted upsells.** Every `requirePro(...)` call sits inside a tap
  handler for a Pro feature. Nothing sells anything to a reader who was
  reading.
- **Reminders never surprise.** Off until asked for; permission requested at
  opt-in rather than launch; never fires on a day already read; no badge.
- **The end-of-volume prompt** follows the reader paging past the last page.
- **Search is debounced, not live-reordering** — the reader is typing, so
  they caused it.
- **`didChangeMetrics` repagination** follows a rotation, which the reader
  performed.

## Keeping it true

When adding anything that calls `setState`, `showDialog`,
`showModalBottomSheet`, `showSnackBar`, or sorts a visible list, ask what
caused it. If the honest answer is "a timer", "a stream", "a sync", or "a
background task", it belongs behind a boundary from the list above — or in
the exceptions table, with a reason.
