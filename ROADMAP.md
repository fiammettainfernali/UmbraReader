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
- [ ] **9. iPad + orientation.** Two-page spread in landscape, wider
      margins, keyboard page-turn, pointer support. Gets "Designed for iPad"
      on Apple Silicon Macs free.
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
- [ ] **16.** Page-turn polish: curl/slide options, tap-zone customization,
      brightness swipe gesture.
- [ ] **17.** Typography depth: hyphenation, justification toggle, embedded
      reading fonts (Literata, Charter).
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

- [ ] **21. Monetization.** Free + one-time "Umbra Pro" unlock (themes,
      stats, sync) — e-reader users are subscription-hostile. StoreKit 2 via
      `in_app_purchase`. No accounts; iCloud is the sync identity.
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
