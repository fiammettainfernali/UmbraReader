# Making the Discover tab tell the truth

An audit of Umbra's Manage/Discover screen against what Novel Grabber
actually reports, and a plan to close the gap.

The screen's job is to answer *"what is my server doing right now?"*. It
currently answers approximately, and in several situations it answers
wrongly — which is worse than not answering, because there is no way to
tell the difference from the phone.

## What the server actually emits

`Orchestrator._emit_progress` sends five states, each with a full payload:

| state | when | `current` / `total` mean |
| --- | --- | --- |
| `downloading` | fetching chapters | chapters done / chapters in this novel |
| `batch_pause` | the deliberate pause between batches | unchanged, plus `keep_bar: true` |
| `checking` | update sweep | **novels checked / novels in the sweep** |
| `compiling` | building the EPUB | pinned to total / total, 100% |
| `idle` | queue drained | zeroes |

Every payload also carries `novel_id` and `queue_size`. Parallel runs are
folded into one bar by `_emit_progress`, which relabels `novel_title` as
"N novels in parallel" and sums the counts.

## What the app does with it

`ControlProgress` keeps six fields and the screen renders three of them.
The problems, worst first.

### 1. Three of the five states are invisible

`isIdle` is the only state the UI branches on. Everything else renders the
same bar with the same "12 / 340 · 4%" line, so:

* **`checking` looks like downloading.** During an update sweep the numbers
  are *novels checked out of novels in the sweep* — a completely different
  quantity from chapters — and the UI presents them in the identical
  format. "40 / 486 · 8%" during a sweep and during a download mean
  unrelated things.
* **`batch_pause` looks like a stall.** The server is deliberately waiting
  out its rate-limit pause, and sends `keep_bar: true` to say "this is
  fine". The app ignores the flag and shows a frozen bar.
* **`compiling` looks finished.** It arrives pinned at 100%, so the last
  thing seen before an EPUB build is a full bar that then sits there.

### 2. "Working" and "Idle" come from a different source than the bar

The heading reads `status.active`, from the polled `/api/status`. The bar
reads the SSE `progress` stream. Those update independently, so the card
routinely shows **"Idle" above a moving progress bar**, or "Working" with
nothing under it, for as long as it takes the next poll to land.

### 3. A dead stream looks like a healthy idle server

`_subscribe`'s `onError` is an empty block with a comment saying polling
still works — but nothing re-subscribes and nothing polls on a timer. If
the SSE connection drops (server restart, Wi-Fi handover, iOS suspending
the app), progress silently stops updating forever. The screen keeps
showing the last frame it received, which after a completed download is
an entirely plausible "Idle".

**This is the most serious item on the list**: the failure is invisible
and indistinguishable from correct behaviour.

### 4. Nothing survives backgrounding

There is no `AppLifecycleState` handling. iOS suspends the app, the SSE
socket dies, and coming back shows stale state until something else
triggers a refresh.

### 5. The queue count is the only thing that is definitely right

`/api/status` is re-fetched on every `queue` event, so the list itself is
sound. It is the *activity* half of the screen that is unreliable.

### 6. Smaller gaps

* `queue_size` is in every progress payload and never read — the queue
  length could update live rather than waiting for a poll.
* `novel_id` is in every payload and never read, so the progress card
  can't link to the series it is talking about.
* "Check all" still promises a full sweep; the server's `update_policy`
  now skips finished and dropped novels most sweeps.
* Nothing shows *when* the last successful contact was, so a frozen
  screen looks identical to a quiet one.

---

## Plan

### Tier 1 — stop it lying — **done**

1. **Render each state distinctly.** A label per state — "Downloading",
   "Checking for updates", "Paused between batches", "Building EPUB" — and
   for `checking`, count *novels* in the caption rather than reusing the
   chapter wording.
2. **Respect `keep_bar`** so a batch pause reads as a deliberate wait.
3. **One source of truth for the heading.** Derive the headline state from
   the progress stream when it is live, falling back to `status.active`
   only when it isn't, so heading and bar can never disagree.
4. **Detect a dead stream.** Track the time of the last event; if nothing
   arrives for ~40s while the server claims to be working, show
   "Reconnecting…" rather than a confident stale frame.

### Tier 2 — make it recover — **done**

5. **Reconnect the SSE stream** with backoff on error/done, instead of the
   current empty `onError`.
6. **Resubscribe and refresh on resume** via `AppLifecycleState`, so
   returning to the app shows current state rather than the last frame
   before suspension.
7. **A "last updated" line**, so a stale screen is legible as stale.

### Tier 3 — use what is already being sent — **done**

8. **Live queue count** from `queue_size` rather than waiting for a poll.
   Falls back to the polled list when no tick has arrived.
9. **Tap the progress card to open the series**, using `novel_id` resolved
   against the offline library cache. Only offered when there is somewhere
   to go: a parallel run names no single novel and the server omits the id,
   and a series missing from the cache cannot be opened.
10. **"Check all" is now "Check updates".** The old label promised a full
    sweep; `update_policy` checks ongoing series every sweep but finished
    and dropped ones only after a few days. The server already reports how
    many it skipped, so the honest label is the smaller claim.

### Tier 4 — worth considering, not obviously right

11. Per-novel repair from the phone — retry errored chapters, reset a
    novel. The two highest-value things the GUI can do that the API
    cannot, and the answer to "what if a novel breaks while I'm running
    headless". Needs new endpoints, so it is its own piece of work.

## Where to start

**Tier 1, then Tier 2.** Tier 1 is presentation-only against data the
server already sends — no protocol changes, no server rebuild. Tier 2 is
what makes the screen trustworthy over hours rather than minutes, and item
4 is arguably Tier 1 material given how badly a dead stream currently
fails.
