# Reading stats — audit + improvement plan

Written 2026-07-24. Plan, not applied work.

---

## The complaint, confirmed

> "it just seems to be just all time and its kind of hard to understand"

Both halves check out.

**Six of the eight headline cards are all-time totals**: books started, finished,
chapters read, time read, words read, words/min. All-time numbers only ever go
up. After a year they are a trophy case, not feedback — "Time read: 340h"
cannot tell you whether this week went well.

**The genuinely useful figures are the least prominent.** "This week: 4h 12m"
is a small outline-coloured `labelMedium` line tucked under the heatmap.
Today-vs-goal sits below eight cards. The numbers that answer *how am I doing
right now* are the ones you have to hunt for.

**And it is a flat wall.** Eight equal-weight cards mixing units and meanings —
a lifetime count (books started) next to a current state (in progress) next to
a lifetime duration (time read) next to a live run (day streak). Nothing is
emphasised, so nothing reads as the answer to anything. That is the "hard to
understand" part.

## The good news: this is a presentation gap, not a data gap

`ReadingActivity` already holds the full per-day ledger — `dailySeconds` and
`dailyWords`, keyed by date, plus `perVolumeSeconds`/`perVolumeWords`. But the
only period accessors on it are `todaySeconds()`, `todayWords()`,
`weekSeconds()` and `weekWords()`. Everything else aggregates to all-time.

So every number below is already computable. Nothing needs new tracking, no
migration, no lost history.

## Smaller problems found on the way

- **"Chapters read" is not chapters read.** It is
  `sum(progress.chapterIndex + 1)` across entries — furthest *position*, not
  chapters actually consumed. It never decreases, and a book opened once and
  closed counts as 1. Either rename it to something honest or compute it
  properly.
- **The per-book list is unordered.** It iterates `entries` as they come, so a
  book you gave 40 hours can sit below one you opened by accident. It should
  rank by time spent.
- **words/min is a lifetime average**, so it drifts less and less as history
  grows — and it is the figure feeding time-left estimates in the reader.
- The heatmap is fixed at 13 weeks regardless of what else is on screen.

---

## Plan

### Tier 1 — Periods and hierarchy (the actual fix) — SHIPPED 2026-07-24

Built as described. `StatsPeriod` (week/month/year/all, sized in rolling days
so a part-finished calendar month can't read as a collapse) plus period
accessors on `ReadingActivity`; the screen now leads with the window's reading
time, the change against the previous window, then today-vs-goal, then
supporting figures, with lifetime totals demoted to a quiet `All time` strip.
14 tests on the period maths, 3 driving the real screen — it had none before.

**T1a. A period selector.** Segmented control at the top: **Week · Month ·
Year · All**, defaulting to **Week**, not All. Every headline figure respects
it. This alone answers the complaint.

Needs three small additions to `ReadingActivity`, all trivial over the existing
daily maps and all pure/testable:
`secondsIn(from, to)`, `wordsIn(from, to)`, `daysReadIn(from, to)`.

**T1b. One hero figure, not eight equals.** Lead with time read *in the
selected period*, large, with a comparison against the previous equivalent
period — "4h 12m this week · up 38% on last week". That comparison is the
thing all-time totals can never give you: direction. Then a compact supporting
row (days read, words, average per reading day), then the lifetime totals
demoted to a quiet "All time" strip at the bottom where a trophy case belongs.

**T1c. Promote today-vs-goal** to just under the hero. It is the most
actionable number in the screen and currently sits below everything.

*Effort ~1–2 days. Risk low: additive to a well-covered store.*

### Tier 2 — Show the shape

**T2. A small bar chart of the period's buckets** — 7 days for Week, ~4–5 weeks
for Month, 12 months for Year. The heatmap answers "did I read"; bars answer
"how much, and is it trending". Keep the heatmap for the All view, where it is
genuinely the right tool.

*Effort ~1–2 days. No dependency needed — this is a row of `FractionallySized`
bars, not a charting library.*

### Tier 3 — Honesty and ranking

- **Fix or rename "Chapters read"** so it stops overstating.
- **Make words/min period-aware** (keep the lifetime figure for the reader's
  time-left estimate, which wants stability).
- **Sort the per-book list by time in the selected period**, so it shows where
  the time actually went. Cap it, with a "show all" expander.
- **"Finished" should be finished *in this period*** when a period is selected;
  lifetime finished moves to the All-time strip.

*Effort ~1 day.*

### Tier 4 — Optional colour

Best day and best week; a "you read on N of the last 30 days" line; per-series
rather than per-volume totals, which for a 40-volume webnovel is far more
meaningful than 40 separate rows.

---

## Principles this must respect

- **Exact-numbers mode** exists (Phase 6) — these figures should honour it
  rather than rounding when it is on.
- **Never shaming.** Same rule as the reminders and streak grace: a down week
  is information, not a failure. Phrase comparisons neutrally ("down 12% on
  last week"), no red, no warning iconography.
- Stats/goals/streaks are Pro-side per the roadmap, so this is not
  accessibility work and may be gated — but the *reading* experience it
  describes never is.

## Recommendation

Build **Tier 1** and stop to look at it. It is the whole complaint: periods
plus hierarchy. Tiers 2–4 are polish that only make sense once the structure is
right, and Tier 2's value depends on how the hero figure ends up reading in
practice.
