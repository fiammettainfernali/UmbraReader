# Umbra Reader — Business-Ready Roadmap

The goal: take Umbra from an excellent personal app to a shippable, sellable
e-reader. Feature set today is already strong (paged + scroll reading, theme
engine, highlights/notes, glossary, collections, stats, recommendations,
iCloud sync, backup/restore, sideloading, auto-download). The gap is the
invisible 20%: storage that scales, accessibility, crash visibility,
wild-EPUB tolerance, and a legal content story.

## Strategic decision (made first, shapes everything)

**Path A — general-purpose OPDS/EPUB reader.** Sell the *reader*, not the
content. Works with any OPDS catalog (Calibre-Web, Kavita, Komga, Standard
Ebooks) plus sideloaded EPUBs. Novel Grabber integration stays as an optional
power-user mode. A commercial product built on scraped webnovels is a legal
non-starter, so the personal pipeline never ships as part of the product.

---

## Phase 1 — Foundation & tech debt (everything else builds on this)

- [ ] **1. Storage engine.** All library state lives in `SharedPreferences`
      (progress, bookmarks, collections, activity — ~10 stores of string-blob
      JSON). Migrate to SQLite (`drift`) with a one-time import. Unlocks real
      queries for stats and full-library search.
      *In progress — done: `AppDatabase` (drift, schema v2) with
      `ReadingProgressStore`, `BookmarkStore`, `CollectionStore` and
      `ReadingActivityStore`, all with non-destructive one-time prefs
      imports; `BackupService` serialises SQLite stores back into the
      legacy prefs shape so old and new backup files stay interchangeable.
      Remaining (small, low-risk): glossary, series status, recommendation
      feedback, pronunciations — migrate opportunistically.*
- [x] **2. Credentials to Keychain.** OPDS password moved from plain
      SharedPreferences to `flutter_secure_storage` (Keychain), with one-time
      migration and a prefs fallback where Keychain is unavailable (tests).
- [ ] **3. Break up `reader_screen.dart`** (~3,900 lines, 25 `setState`
      sites; owns pagination, TTS, chrome, gestures, menus). Extract a
      `ReaderController` + separate widgets for chrome/page-view/selection.
      Biggest velocity tax in the codebase.
      *In progress — done: mechanical split into `lib/reader/` modules
      (layout/pagination engine, block renderer, chrome bars, book search,
      bookmarks sheet), plus the whole read-aloud session extracted into
      the `ReaderTtsSession` mixin behind an explicit interface;
      reader_screen.dart 3,910 → 1,732 lines. Remaining: the State still
      owns navigation/progress/build — extract further only if it keeps
      hurting; the file is now reviewable.*
- [x] **4. Sync durability.** Sync now rides on JSON documents in the app's
      private iCloud Drive container (`ICloudDocsBridge`, NSFileCoordinator
      + NSMetadataQuery live updates) — no more 1 MB key-value cap. Reads
      fall back to the legacy key-value store so data synced by older
      builds migrates on first pull; writes fall back when the container is
      unavailable. Conflict resolution unchanged (per-book last-write-wins,
      bookmark union-by-id, whole-set LWW collections).
- [x] **5. Dependency hygiene.** Upgraded (2026-07): archive 4, xml 7,
      google_fonts 8, file_picker 11, connectivity_plus 7, just_audio 0.10,
      audio_session 0.2 + all minors. Still held back: share_plus 13 and
      wakelock_plus 1.6 (need win32 6; file_picker 11 pins win32 5) and the
      `path_provider_foundation` 2.4.1 override (App Store 91080 — only an
      upload can verify newer versions). Repeat quarterly.
- [x] **6. Housekeeping.** Real pubspec description; semver version name
      (build number already comes from Codemagic `$BUILD_NUMBER`).

## Phase 2 — Ship quality (what reviewers and real users hit)

- [x] **7. Accessibility.** VoiceOver labels on all custom tap targets
      (library cards, swatches, dismiss chip), the chapter scrubber as an
      adjustable slider (crash found by the integration test, fixed),
      Reduce Motion honoured (page turns/follow-scrolls jump). Theme
      contrast is now enforced by test (WCAG AA 4.5:1 body / 3:1
      secondary; Sepia's secondary was nudged imperceptibly to clear it).
      Dynamic Type: onboarding + library verified overflow-free at 2.0x
      scale by test; the reader page intentionally ignores system scale
      (font size is a reader setting). Remaining niceties (on-device
      VoiceOver sweep of every sheet) fold into normal QA.
- [x] **8. Crash reporting.** Sentry wired in main.dart — crashes/uncaught
      errors only (no PII, no tracing, no screenshots). Compiled out unless
      a `SENTRY_DSN` --dart-define is provided; codemagic.yaml passes it
      from an env var. *User setup: free sentry.io account → Flutter
      project → copy DSN → add `SENTRY_DSN` env var in Codemagic.*
- [x] **9. iPad + orientation.** Two-page spread ships: paged mode on a
      tablet-sized landscape viewport (shortestSide ≥ 700dp — iPad mini up;
      big phones stay single-page) renders facing pages via _pageStride = 2,
      riding the proven TV-mode column layout (gutter, per-column margins,
      centred-column cap bypassed for spreads). Rotation now preserves the
      reading position: didChangeMetrics captures block+char on a width
      change BEFORE repagination, so the new layout restores the spread
      containing it (was: jump to a stale spread index). Keyboard page-turn
      already existed (arrows/space/page keys). Remaining nicety: pointer/
      scroll-wheel paging — backlog.
- [x] **10. Error-state UX audit.** Much already existed (offline banner +
      cached-library fallback, 401 auth messages, sync-failed retry state,
      reader corrupt-EPUB screen, skippable onboarding). Added for Path A:
      the no-server library state is now sideload-first ("Add your first
      books" with Connect + Import EPUB actions), onboarding's skip is
      framed as the import path, and out-of-space downloads get a specific
      actionable message (ENOSPC detection) instead of a raw error dump.
- [ ] **11. EPUB robustness.** Parser handles clean server EPUBs; wild EPUBs
      bring CSS-heavy layouts, tables, footnotes/endnotes, nested TOCs,
      RTL/vertical text, fixed-layout. Graceful degradation + a golden-test
      corpus of ~50 diverse public-domain EPUBs (Standard Ebooks, Gutenberg).
      *In progress — corpus harness landed: `tool/fetch_epub_corpus.sh`
      pulls 23 books (Standard Ebooks EPUB3, Gutenberg epub2+epub3 in five
      languages, W3C/IDPF conformance samples incl. RTL + vertical
      Japanese) into gitignored `test/corpus/`;
      `test/epub_corpus_test.dart` asserts open + every-chapter parse +
      content volume, and skips itself when the corpus is absent. Fixed
      three real parser bugs it caught: a crash on illegal
      percent-encoding in hrefs, non-ASCII (Japanese) chapter filenames
      never matching the archive, and SVG spine pages dropped silently.
      Remaining: grow the corpus, on-device visual spot checks; SVG
      rasterisation is backlog.*
- [x] **12. Testing depth.** `test/integration_flow_test.dart` runs the
      money path against a real in-test HTTP server playing OPDS: browse →
      volumes → streamed download → parse → resume position, plus the
      downloaded book rendering in the real ReaderScreen (which builds the
      semantics tree — it immediately caught a VoiceOver crash in the
      scrubber). Codemagic now gates every build on `flutter analyze` +
      `flutter test`. On-device integration_test runs remain out of reach
      without a Mac; the in-process harness is the pragmatic substitute.

## Phase 3 — Reader feature parity (ranked impact-per-effort)

- [x] **13.** Tap-hold dictionary lookup: long-press any word in the
      reader → the system dictionary (UIReferenceLibraryViewController via
      the `umbra/define` bridge). Word resolution uses the pagination's own
      TextPainter math (scroll + paged/TV modes), so it's exact and has no
      gesture-arena conflicts with taps/page-turns. Translate + text
      selection/copy deferred to their own slice — SelectionArea fought
      the reader's gesture stack and lost.
- [ ] **14.** Footnote popovers (ties into #11).
- [x] **15.** Full-library search: `LibrarySearch` streams full-text
      matches across every downloaded book (index-free scan, per-book +
      total caps, unreadable books skipped); `LibrarySearchScreen` (via
      the manage-search icon next to the library search bar) streams
      results grouped by book, and tapping a hit opens the reader at that
      exact chapter + paragraph (new ReaderScreen initial-position
      params). Upgrade path if it ever crawls: FTS5 in AppDatabase.
- [~] **16.** Page-turn polish: curl/slide options, tap-zone customization,
      brightness swipe gesture. *Done (Tier 1 of the reader-UX audit —
      `docs/READER_UX_AUDIT.md`): configurable tap zones (left-hand swap,
      turn-zone size defaulting to thirds so the forward zone grew from 28%
      and the centre menu shrank from 44%, plus a swipe-only accidental-turn
      guard) and edge-slide brightness (a left-edge vertical drag with a
      heads-up readout, opaque 24px gutter so it wins the drag reliably;
      toggle it off to restore full-edge swipe). All synced as
      accessibility/ergonomic prefs. Remaining: curl/slide page-turn style
      option (Tier 2, T4).*
- [x] **17.** Typography: Literata, Lora and Atkinson Hyperlegible are
      now bundled app assets (regular/bold/italic/bold-italic, OFL
      licences included) — correct rendering offline from first launch,
      no google_fonts network fetch (dependency removed). The
      justification toggle already existed. Hyphenation consciously
      deferred: Flutter has no engine hyphenation, and soft-hyphen
      injection would desync every char-offset feature (highlights,
      lookup, search).
- [x] **18.** Reading goals & streaks surfaced on the library home: a
      tappable chip under the controls shows the current streak and
      today-vs-goal progress (goal + full stats already lived in the Stats
      screen; the chip is the daily-visibility nudge and opens it).
- [x] **19.** Annotations → Markdown: the per-book copy/share already
      existed on the Highlights screen; added the library-wide export
      (`AnnotationsExport`) — every highlight and note from every book in
      one document, grouped book → chapter in reading order, shared as a
      .md file from Backup & restore.
- [ ] **20.** Series intelligence as the marketing wedge: "the reader built
      for 400-chapter series."

## Phase 4 — Business mechanics

- [ ] **21. Monetization.** Free + one-time "Umbra Pro" unlock — e-reader
      users are subscription-hostile. No accounts; iCloud is the sync
      identity. *In progress — entitlement layer landed: `ProService`
      (build-flag `UMBRA_PRO`, defaults UNLOCKED until launch; persisted
      purchase flag), `requirePro` gate + upsell sheet, and the power-user
      split wired: Pro = custom themes, full-library search, stats/goals/
      streaks, Markdown export, iCloud sync, collections, TV mode. Free =
      the complete reading experience. Remaining: the StoreKit flow via
      `in_app_purchase` (needs the IAP product created in App Store
      Connect first) and the launch-pipeline `UMBRA_PRO=false` flip.*
- [ ] **22. App Store package.** Privacy policy + nutrition labels (nothing
      is collected — say so loudly), screenshots per device class,
      description, support URL, EULA. Verify font licensing (OFL is fine).
- [ ] **23. Android.** No `android/` exists; Star Library is a separate
      codebase. Decision: unify into Umbra (one codebase, both stores, e-ink
      mode as a theme preset) — more work now, half the maintenance forever.
- [ ] **24. Beta pipeline.** TestFlight external group, staged rollouts,
      generalized feature flags (`lib/feature_flags.dart` is the seed).
- [ ] **25. Localization.** Do `intl`/ARB *extraction* early (brutal to
      retrofit); translate only when downloads justify it.

## Phase 6 — Focus & sensory accessibility (ADHD / autism)

Principle: **accessibility features are never Pro-gated.** They ship free.
Second principle: everything here is opt-in, individually toggleable, and
never shames the reader. Existing foundations already serving this:
word-highlighted read-aloud (dormant, resurrectable), full theme engine,
Atkinson Hyperlegible bundled, Reduce Motion support, glossary,
distraction-free immersive mode, line-precision resume.

### Quick wins (days each)
- [x] **Reading ruler / line focus.** "Reading ruler" toggle in Layout &
      motion: dims all but a ~3-line band at the teleprompter position
      (LineFocusOverlay — pure pointer-transparent overlay, theme-tinted
      scrims so dimmed text ghosts through); text scrolls/pages through
      the fixed band. Pairs naturally with auto-scroll.
- [x] **Focus-paragraph mode.** "Focus paragraph" toggle: renders one
      paragraph at a time, vertically centred, with an "N / M" counter; tap
      the page edges to step (reuses the _advance zones) and roll into the
      adjacent chapter. Threaded through the position system (save/restore,
      scrubber, bookmarks, Continue shelf); ruler/auto-scroll/auto-page
      suppressed while active. (Word-lookup long-press disabled here for now.)
- [x] **Fixation anchors (Bionic-style).** "Fixation anchors" toggle: bolds
      the first 1-3 letters of each word (length-scaled). Pure fixationRuns()
      transform preserves the exact text so every char offset stays valid;
      applied through EVERY measure + render path (measureBlockHeight,
      layoutParagraph, BlockView, _wordAt) so pagination and pixels agree
      (proven by pagination-overflow variants). Joins the paged page key.
- [x] **Streak grace.** currentStreak now forgives one missed day per
      rolling week (shown honestly: chip reads "(rest day used)"), and a
      not-yet-read today no longer zeroes the streak before the day is
      over. Two gaps in a week still end it.
- [x] **Letter/word/paragraph spacing controls.** Three sliders in Text
      size/style: letter (0-4px), word (0-8px), paragraph (0-24px extra).
      Threaded through the shared paragraphStyle/headingStyle and a new
      paragraphGap(settings) so measurement, page packing and render use one
      set of values — the pinned-to-0 spacing is now the *default*, not a
      hard constant. Synced taste; joins the paged page key. (Overflow test
      gains letter/word/para variants proving measure==render.)
- [x] **OpenDyslexic font option** (bundled, OFL) — dyslexia co-occurs
      heavily with both communities. Four faces (Regular/Italic/Bold/
      Bold-Italic .otf) bundled with the OFL licence; added to kReaderFonts
      so it appears in the Font picker. A font-wiring guard test asserts every
      offered family is declared in pubspec and its face files exist on disk
      (a missing asset would silently fall back to the system font).
- [x] **In-app animation kill-switch** (beyond honouring system Reduce
      Motion) + haptics toggle — sensory control shouldn't require
      changing system settings. "Reduce animations" folds into the existing
      _reduceMotion getter (OS Reduce Motion OR the in-app toggle) so every
      page-turn/scroll and the chrome fade jump instantly; "Haptic feedback"
      gates all reader taps via _hapticSelection/Light/Medium wrappers. Both
      synced. (Test mocks the platform channel and asserts the kill-switch
      fires zero HapticFeedback calls on a page turn.)

### Medium (a week-ish each)
- [x] **"Where was I?" re-entry aid.** Reopening a book after a gap (>20 min
      since last read; skipped for search/TOC jumps and the very start)
      briefly washes the restored paragraph in the highlight tint (fades over
      ~3s) and floats a tappable "Where was I?" pill for ~6s. Tapping opens a
      recap sheet with the previous few paragraphs, dimmed on the way in and
      brightest at the current one. Tests cover gap-shows / immediate-hides.
- [x] **Gentle session timers.** Opt-in target (Off/15/30/45/60 min) with a
      quiet fill creeping along the very bottom edge — no alarm. Once the
      target is passed, a dismissible "good time for a break?" pill surfaces
      only at the next chapter boundary (never mid-page), auto-hiding after
      ~14s. Accumulates foreground reading time via the existing session
      flush; synced. (Tests cover fill-presence, break-at-chapter, and
      under-target-silence via a debug elapsed hook.)
- [x] **Exact-numbers mode.** "Exact numbers" toggle: the reader's position
      label becomes "page 5 of 12 · 41.7% · 12.5 min · 182.4 min in book" —
      no tildes, one decimal, real page counts in paged mode. Bonus for all
      modes: time-left estimates now use the user's own measured words/min
      from the activity ledger (clamped 80–800, fallback 220) instead of a
      hardcoded 220 — the estimate is calibrated to the actual reader.
      (Focus mode already shows its exact "N / M" paragraph counter; stats
      screen numbers were already unpadded.)
- [x] **Quick thought capture.** A long-press on empty space (any spot the
      dictionary finds no word — margins, inter-paragraph gaps, past a
      line's end) instantly drops a bookmark at the current paragraph with
      no dialog in the way; a snack confirms and offers an optional "Add
      words" one-line note (single autofocused field, save-on-submit, upserts
      the same marker by id). Long-pressing ON a word still opens the
      dictionary. Reuses the existing bookmark store, so captures show in the
      bookmarks sheet and iCloud-sync. (Voice note optional later.)
- [x] **Tinted overlays.** A colour-wash layer over the page (severity
      slider), independent of theme — visual-stress relief (Irlen-style),
      also useful for night reading. Nine tints (none + blue…grey) in
      Appearance, with a strength slider that appears once a tint is picked.
      Modelled as a *multiply* filter, the way physical acetate works: an
      alpha overlay would drag text and background toward the tint alike and
      eat contrast, whereas multiply absorbs the bright background and leaves
      near-black text near-black. Applied inside `ReaderSettings.theme`, the
      single choke point every reader surface reads colours from, so page,
      text and chrome tint together with no plumbing. Mid-tone secondary text
      *is* compressed by a wash (Black + Violet bottomed out at 2.25:1), so
      `withOverlay` lifts it back over 3:1 — `reader_overlay_test.dart` holds
      every theme × tint to AA body / 3:1 secondary at full strength. Syncs
      across devices rather than being device-local like `brightness`: a
      visual-stress need belongs to the person, not the screen.
- [x] **Character memory.** Extend the existing glossary: per-series
      character notes with "last seen in chapter N" — working-memory
      support for 800-chapter webnovels. Tracked automatically: opening a
      chapter scans its text for every glossary term and stamps the sighting,
      so nobody has to hand-maintain it at 800 chapters. Deliberately
      *monotonic* — a re-read of chapter 5 must not rewrite "last seen in
      chapter 489", since the question being answered is "how long since they
      turned up?", which lives at the furthest point reached, not the most
      recent one visited. Ordering is (volume, chapter): chapter indices
      restart in each volume's EPUB, so v2c1 has to outrank v1c99. The label
      shown is the chapter's TOC title rather than a computed number, which
      is what the reader sees everywhere else and needs no inference.
      Matching uses word-boundary lookarounds so "Al" doesn't match "Also",
      degrading to substring for scripts where `\w` doesn't apply.

- [x] **Migraine mode.** A one-switch comfort preset for reading through an
      attack, first in the settings sheet because mid-migraine is the worst
      time to hunt through a list. Composed from primitives that already
      existed rather than new machinery: the charcoal/soft-grey Dark theme
      (stark black-on-white or white-on-black is itself a trigger), a green
      overlay wash, low brightness, `reduceAnimations` + instant page turns,
      haptics off, auto-scroll/auto-page off, and roomier text (sizes only
      ever grow, so a large-print reader keeps theirs). Green is on by default
      with its own sub-toggle — research (Burstein, *Brain*) found green is the
      one band migraine photophobia tends to spare while blue is the worst,
      but a green cast on text isn't for everyone. **Fully reversible:**
      switching on snapshots the overridden settings and switching off restores
      them exactly, so it can't eat your normal setup; a missing snapshot
      leaves settings untouched rather than stranding you in the preset.
      Honest scope: a comfort preset, not a treatment — a phone's green
      primary is not the narrow-band 530nm light the studies used.

### Bigger bets
- [ ] **Read-aloud resurrection as an accessibility feature.** The whole
      TTS + word-highlighting stack exists behind kReadAloudEnabled.
      On-device system voices (free, offline) with the existing follow
      highlighting is a first-class multimodal reading aid for both
      communities — no server needed. Ship the on-device engine free;
      premium voices can be a paid layer later.
- [x] **Routine anchoring.** Opt-in reading reminders tied to the user's
      chosen time, phrased as invitations not obligations; pairs with
      streak grace. Off until asked for, with the iOS permission prompt at
      the moment of opting in rather than at launch; if permission is
      refused the switch stays off, because a switch that can't deliver is a
      lie. Never fires on a day already read — `refresh()` rebuilds the
      schedule after each session is recorded, which is what makes that
      true. No badge (a red dot is a demand) and the copy never mentions
      streaks or guilt; `reminder_service_test.dart` asserts that against a
      banned-word list, so the principle survives future edits.
      Implementation note: these are 14 individual one-shots, re-armed on
      every launch and session, *not* one repeating daily notification —
      iOS's `DateTimeComponents.time` matches on time and ignores the date,
      so a repeat physically cannot skip a day. The 14-day horizon means
      invitations keep arriving while you're away but stop after a fortnight
      of silence, which is what an invitation implies. Added
      flutter_local_notifications 22 / flutter_timezone 5 / timezone; no
      entitlement needed (local ≠ push), and the plugin's iOS 13 target
      matches the app's.
- [x] **Predictability audit.** A pass over the whole app against a
      written principle: nothing moves, reorders, or pops up without the
      user causing it. Document it and keep it true (this is a design
      contract, not a feature). The contract now lives in
      `PREDICTABILITY.md`: the rule, why it costs more here than elsewhere,
      the boundaries that count as "the reader caused it" (note that *time
      passing* and *another device* are not among them), a named-exceptions
      table, and the audit itself. One real violation found and fixed — an
      iCloud merge from another device rebuilt the Continue Reading shelf and
      the recommendation row *live*, so a phone in another room could reorder
      the covers while a finger was already moving toward one. Merges now
      land in the stores immediately (a book still opens at the newest
      position) while the visible reorder waits for a boundary the reader
      caused. Everything else audited clean: the wildcard is `Random(daySeed)`
      and stable all day, `requirePro` only ever fires from a tap, and the
      reminder copy is asserted against a banned-word list.

## Phase 7 — Recommendation system overhaul (audited 2026-07-10)

**Audit verdict:** the content-based engine (signed tag affinity: genres,
author ×2, length bucket, 8 TF-IDF keywords; 30-day half-life; √n damping;
diversity caps) is a solid foundation with a hard ceiling. Findings:
(1) it ignores the app's richest signals — per-volume seconds AND words from
the activity ledger, highlight density, binge velocity, hidden-from-continue,
hiatus status, collections membership, downloaded-but-unopened; (2) no
outcome tracking — impressions are never recorded, so repeatedly-ignored recs
never fade, and there is no positive feedback at all; (3) fixed hand weights
(author ×2 forever) that can't adapt to whether THIS user is author-loyal or
trope-driven; (4) scoring math: raw tag-sum (no normalization → many-genre
series inflate), no IDF on genre/author tags (a genre shared by 80% of the
library counts full weight), tokenizer drops <4-char words (war/god/sect) and
all non-ASCII, unigrams only, `l:unknown` is matchable, decay zeroes all-time
favourites (~0.02% after a year), stalled reads stay positive forever;
(5) BUG: `similarTo` lets the source's own dropped-status/reset-feedback flip
the fake entry negative → "More like this" returns anti-recommendations;
(6) dismisses suppress forever and there is zero exploration.

### Phase A — Signal foundation
- [x] **Rec outcome store** (SQLite v5, RecOutcomeRows): impressions (max one
      per series per day) + taps; 3+ ignored impressions soften a candidate
      ×0.85 each (floor 35%); the training data for Phase B's learner.
- [x] **Explicit 👍 "More like this"** on rec cards; feedback enum grew
      liked/snoozed with timestamps ("kind|iso", legacy bare names still
      parse); sync merge is newest-wins with strength tie-break; snoozes
      expire after 30 days.
- [x] **Rich like-weight:** engagement multiplier from time-in-book + words
      read vs the user's own median volume (sqrt, clamped 0.6–1.5),
      highlight density up to +0.3, stall taper (<30% and untouched 60+
      days → up to −0.2), decay floor 0.15× for finished favourites,
      hidden-from-continue −0.15, collections membership +0.25.
- [x] Fixed the `similarTo` polarity bug (status-neutral source copy +
      stripped feedback for the seed).

### Phase B — Matching + per-user learning
- [x] Scoring reworked into per-group affinities (author/genre/keyword/
      length), each √count-normalized and squashed to (-1,1); tag IDF
      log(1+N/df) discounts ubiquitous genres; `l:unknown` no longer
      matchable; tokenizer ≥3 chars + adjacent-pair bigrams; 12 keywords.
      The author double-yield hack is gone — RecWeights owns group scale.
- [x] **Per-user learned feature-group weights:** RecWeightLearner — batch
      logistic regression (pure Dart, 4 features) L2-regularized toward the
      hand-tuned prior, full deterministic refit per library refresh, floored
      at 0. Labels: tapped & read past 20% or 👍 = 1; dismissed/reset or 5+
      ignored impressions = 0. Training features come from a profile that
      EXCLUDES each labeled series' own contribution (no label leakage);
      serving and training share one feature extractor (buildProfile).
      Weights are device-local by design (their training outcomes are; LWW
      sync would let a barely-used device clobber the better-trained one) —
      binge affinity folded into the engagement multiplier rather than a
      fifth group.

### Phase C — Presentation & trust
- [x] "Because…" explanation line on every rec card: the profile tracks
      which positive seed carries each tag hardest, and reasonFor() names
      the dominant connection ("By the author of X" / "Cultivation, like X"
      / "Echoes X") under the learned weights.
- [x] "Something different" wildcard: recommend(explore: true) appends one
      zero/negative-affinity pick, rotated daily (seeded by date — stable
      within a day), pinned as the window's last card; its outcomes feed the
      same feedback/learning loops. Opt-in so similarTo stays taste-pure.
- [x] Feedback aging: dismisses expire after 90 days (resets persist);
      legacy un-timestamped entries get their clock started on first load
      so nothing resurfaces all at once; long-press on a rec card opens the
      full options sheet (More like this / Not now 30d / Not interested).
      Bonus: substantially reading a series since dismissing it outranks
      the stale dismissal.

### Phase D — Prove it
- [x] Offline replay evaluation (recommendation_replay_test.dart): a
      synthetic-but-realistic library (favourite author spanning genres,
      cultivation cluster, fresher romance/sci-fi distractors) with a
      Jan–May reading history. Proven at T: (1) both actually-read-after-T
      series appear in the top 10; (2) the engine beats the recently-updated
      baseline, which scores 0 against the freshness trap; (3) the FULL loop
      — outcomes (tapped+read the author match, dismissed/ignored genre
      picks) → learner raises author / lowers genre → the next shelf ranks
      the author-only match above every genre match. Engine changes are now
      validated against reading patterns, not vibes.

**Post-ship fix (external-binge workflow):** the in-app status picker
(SeriesStatusStore) was UI-only — never fed to the engine, which read only
the server-side readingStatus; and "completed" required at least one in-app
reading entry to count. Both fixed: RecSignals.statusOverrides carries the
user's own statuses (caughtUp→completed, dropped, reading→ongoing) and
outranks the server value; caught-up with ZERO in-app entries is a full
like — so "listened in Natural Reader, marked caught-up in Umbra" is a
first-class taste signal. similarTo uses the overrides for candidate
exclusion only (dropped/caught-up don't appear) without polluting the
source-similarity seed.

**Ceiling to remember:** the engine ranks only what's already in the Novel
Grabber library; true discovery of new novels is a Novel Grabber server
feature, not an Umbra change.

**Source discovery — tried and removed (2026-07-13):** an app-side
"Discover from your sources" shelf (taste-driven queries through
/api/search, one-tap add) was built, shipped and REMOVED by user decision —
they didn't like it (commit 32de277, reverted). Don't rebuild an in-app
source-discovery surface unless asked; if discovery comes back, it should
be the Novel Grabber-side options (harvest "readers also liked" during
scrapes, or a server /api/discover feed).

## Phase 5 — Differentiators (after it's a business)

- [ ] **26.** Read-aloud resurrected properly (`kReadAloudEnabled` flag
      restores the whole stack); a Pro tier could fund managed cloud voices.
- [ ] **27.** OPDS ecosystem play: one-tap setup guides for
      Calibre-Web/Kavita/Komga — those communities market for you.
- [ ] **28.** Stats export, Obsidian highlight sync, Shortcuts/App Intents.

---

**Sequence:** Phase 1 items 1–3 before adding any new features → Phase 2 in
full before charging money → Phases 3/4 interleaved → Phase 5 when revenue
exists.
