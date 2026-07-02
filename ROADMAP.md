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
- [ ] **4. Sync durability.** iCloud sync uses `NSUbiquitousKeyValueStore`
      (1 MB total / 1 KB-per-key limits — silently drops data for heavy
      users). Migrate to CloudKit records or iCloud Drive documents with
      per-book last-writer-wins conflict resolution.
- [x] **5. Dependency hygiene.** Upgraded (2026-07): archive 4, xml 7,
      google_fonts 8, file_picker 11, connectivity_plus 7, just_audio 0.10,
      audio_session 0.2 + all minors. Still held back: share_plus 13 and
      wakelock_plus 1.6 (need win32 6; file_picker 11 pins win32 5) and the
      `path_provider_foundation` 2.4.1 override (App Store 91080 — only an
      upload can verify newer versions). Repeat quarterly.
- [x] **6. Housekeeping.** Real pubspec description; semver version name
      (build number already comes from Codemagic `$BUILD_NUMBER`).

## Phase 2 — Ship quality (what reviewers and real users hit)

- [ ] **7. Accessibility (currently zero).** VoiceOver labels on all
      controls, Dynamic Type in app chrome, contrast check on all reader
      themes, reduced-motion support for paged animation.
- [ ] **8. Crash reporting.** Sentry Flutter SDK; wire `FlutterError.onError`
      + async guards. Can't run a business on emailed screenshots.
- [ ] **9. iPad + orientation.** Two-page spread in landscape, wider
      margins, keyboard page-turn, pointer support. Gets "Designed for iPad"
      on Apple Silicon Macs free.
- [ ] **10. Error-state UX audit.** Server unreachable, expired auth, corrupt
      EPUB, out-of-storage — designed states, not snackbars. Onboarding must
      work with *no* server (sideload-first) for Path A.
- [ ] **11. EPUB robustness.** Parser handles clean server EPUBs; wild EPUBs
      bring CSS-heavy layouts, tables, footnotes/endnotes, nested TOCs,
      RTL/vertical text, fixed-layout. Graceful degradation + a golden-test
      corpus of ~50 diverse public-domain EPUBs (Standard Ebooks, Gutenberg).
- [ ] **12. Testing depth.** Add integration tests for the money paths
      (onboarding → add server → download → read → progress sync), run in
      Codemagic on every push.

## Phase 3 — Reader feature parity (ranked impact-per-effort)

- [ ] **13.** Tap-hold dictionary lookup (`UIReferenceLibraryViewController`)
      + translate.
- [ ] **14.** Footnote popovers (ties into #11).
- [ ] **15.** Full-library search (falls out of the SQLite migration).
- [ ] **16.** Page-turn polish: curl/slide options, tap-zone customization,
      brightness swipe gesture.
- [ ] **17.** Typography depth: hyphenation, justification toggle, embedded
      reading fonts (Literata, Charter).
- [ ] **18.** Reading goals & streaks surfaced from the existing activity
      store — cheap, drives retention.
- [ ] **19.** Export highlights/notes to Markdown/CSV via the share sheet.
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
