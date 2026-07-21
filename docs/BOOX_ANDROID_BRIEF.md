# Brief: standalone Android e-reader for the Boox Palma 2 (Umbra feature parity)

Paste this into a fresh chat to kick off the build. It is self-contained, but
its single most important instruction is to read the reference implementation.

---

## What you're building

A **standalone, single-device Android e-reader** for the **Boox Palma 2** (a
6" e-ink Android phone), replicating the full feature set of an existing,
mature iOS e-reader called **Umbra Reader**. This is a personal app for one
user. There is **no sync, no accounts, no monetization, no cloud** — reading
state lives locally on the device, permanently. It reads EPUBs, primarily
webnovels (often 400–800 chapters across many volumes) downloaded from a
self-hosted Novel Grabber server, plus sideloaded EPUB files.

## The reference implementation — read this first

The iOS app's full source is on this machine at **`D:\UmbraReader`** (Flutter/
Dart, ~80 files, ~29,700 lines). **It is the behavioral ground truth for every
feature below.** Do not reinvent behavior from my prose — open the Dart and
match it. Key reading:

- `D:\UmbraReader\lib\` — all logic and UI.
- `D:\UmbraReader\ROADMAP.md` — every feature, why it exists, how it works.
- `D:\UmbraReader\PREDICTABILITY.md` — a design contract you must honor.
- `D:\UmbraReader\docs\` — supporting specs.
- The custom EPUB parser and pagination engine (`lib/services/epub_parser.dart`,
  `lib/reader/reader_layout.dart`) are the crown jewels — study them closely.

## First decision: tech stack

Two honest paths. Pick one before writing code.

- **Standalone Flutter app (recommended for feature parity).** Start a *new,
  independent* Flutter project (its own repo — NOT a branch of Umbra, NOT
  shared code) and fork Umbra's Dart into it. Almost every feature comes across
  for free because all 20 of Umbra's dependencies are already cross-platform;
  only ~4 iOS-native bridges need replacing (see "What to strip/replace").
  Fastest route to "all the features," at the cost of e-ink polish being a
  Flutter-over-e-ink adaptation rather than native.
- **Native Kotlin (best e-ink feel, far more work).** A prior native attempt
  exists at **`D:\The Star Library`** (Kotlin/Gradle) — build on it or start
  fresh. You get first-class access to the Boox refresh-mode SDK and the
  crispest e-ink experience, but you re-implement ~30k lines of reader logic
  from scratch, which is a multi-month solo effort. Only choose this if e-ink
  fidelity matters more than feature completeness at launch.

Unless told otherwise, **go standalone Flutter** — it's the only realistic way
to hit "all the features" for a solo build.

## Complete feature inventory (from Umbra)

Match these. Behavior details live in the Umbra source; this is the checklist.

### Core reading
- Custom EPUB parser (handles messy real-world EPUBs: odd encodings, non-ASCII
  chapter filenames, SVG spine pages, nested TOCs).
- Custom pagination engine with an invariant you must preserve: **measurement
  and render must use identical text styles** (Umbra sets `letterSpacing`/
  `wordSpacing` explicitly, never null, or pages overflow). Read
  `pagination_overflow_test.dart`.
- Two reading modes: continuous **scroll** and discrete **paged** (swipe).
- Reading position tracked as (chapterIndex, blockIndex, blockChar,
  chapterPath) — survives repagination, font changes, rotation.
- Chapter navigation, scrubber/slider, TOC, keyboard/remote page-turn
  (arrows/space/page keys — important, the user reads with a Bluetooth remote).
- Two-page spread on wide/landscape (tablet-class viewports).

### Typography & themes
- Font family incl. bundled **OpenDyslexic**, **Atkinson Hyperlegible**,
  Literata, Lora (all OFL, bundled as assets — no network fetch).
- Font size, line height, letter/word/paragraph spacing sliders, bold, italic,
  text alignment (left/justify), margins, brightness.
- Theme engine: light/sepia/dark/grey/black + user-defined custom themes.
  Contrast is enforced to WCAG AA (4.5:1 body, 3:1 secondary) by test.
- **Tinted overlays** (Irlen-style): 9 color washes + strength slider,
  modelled as a *multiply* filter (not alpha) so text contrast survives. See
  `reader_theme.dart` `withOverlay` and `reader_overlay_test.dart`.

### Focus & sensory accessibility (NEVER gate these — they ship free)
- Reading ruler / line focus (dims all but a ~3-line band).
- Focus-paragraph mode (one paragraph centered, N/M counter).
- Fixation anchors (Bionic-style bolded word-openings; text-preserving).
- In-app reduce-animations kill-switch + haptics toggle (critical for e-ink —
  see below).
- "Where was I?" re-entry aid (recap after a gap).
- Gentle session timers (opt-in, no alarm, break suggestion at chapter
  boundary only).
- Exact-numbers mode (precise page/percent/time, calibrated to measured WPM).
- Quick thought capture (long-press empty space → instant bookmark + optional
  note).
- Character memory (per-series glossary with automatic "last seen in chapter
  N" tracking — monotonic, ordered by (volume, chapter)).
- Reading reminders (opt-in, invitations-not-obligations, never on a day
  already read, no badge, no streak-guilt — copy is asserted against a
  banned-word list). On Android use `flutter_local_notifications` (already a
  dependency; works cross-platform).
- Streaks with grace (one forgiven rest day per rolling week).

### Read-aloud (TTS)
- Full TTS stack exists (system voices + optional network voice server) with
  word-highlight follow, sleep timer, lock-screen controls. On Android:
  `flutter_tts` uses Android TTS directly; replace the iOS now-playing bridge
  with an Android MediaSession (or the `audio_service` plugin). Note: the user
  currently reads aloud via a *separate* app (Natural Reader), so in-app TTS is
  present-but-optional — ship it working but don't over-invest.

### Library & content
- Library grid, series detail, collections/shelves, series status
  (reading/caught-up/etc.), filtered views.
- Full-library full-text search (streams matches across every downloaded book,
  opens the reader at the exact paragraph).
- Highlights & notes (bookmarks), per-book and library-wide **Markdown export**.
- Glossary per series (see character memory above).
- Pronunciation overrides (for TTS).
- Recommendation engine: taste profile (tag affinity × IDF), a per-user
  weight learner, outcome tracking, daily wildcard, human-readable reasons,
  feedback (like/snooze/dismiss). Study `recommendation_engine.dart`.
- Stats: reading time, words read, streaks, daily goal, measured WPM.
- Reading activity ledger (words + time per day/volume) — **local only, no
  cross-device merge** on this build.

### Content acquisition (Novel Grabber)
- OPDS client: browse/search/stream-download EPUBs from the user's self-hosted
  Novel Grabber server (HTTP, basic auth, reachable on LAN or over Tailscale).
- Remote-control API (`/api/*`): drive Novel Grabber's download queue from the
  app — search sites, add a novel by URL, queue/pause/resume/skip/stop, move a
  queued item to the top, check for updates, auto-update schedule, live
  progress via SSE (`/api/events`). See `lib/services/control_client.dart` and
  Novel Grabber at `D:\novel grabber\core\control_api.py`.
- Auto-download next volume (Wi-Fi-only option), auto-delete finished volumes.
- Sideload EPUBs via the system file picker.
- Backup/restore (export/import the whole library as a file). Storage-usage
  management screen. Onboarding flow.

## What to strip or replace (iOS-only in Umbra)

- **iCloud sync** (`umbra/icloud_kv`, `umbra/icloud_docs`) — **delete entirely.**
  This build is single-device. Every store already persists locally (drift/
  SQLite + SharedPreferences); just remove the sync layer
  (`cloud_sync_service.dart`) and the merge-on-pull calls. Keep the local
  persistence untouched.
- **Pro gating** (`ProService`, `requirePro`, upsell sheets) — **remove;
  everything unlocked.** This is a personal app.
- **Dictionary** (`umbra/define`, iOS `UIReferenceLibraryViewController`) —
  Android has no system dictionary UI. Options: disable tap-to-define, or fire
  an `ACTION_PROCESS_TEXT` intent to the user's dictionary app. Low priority.
- **Now-playing bridge** — replace with Android MediaSession only if you ship
  TTS lock-screen controls.
- **StoreKit / in_app_purchase** — not needed.

## E-ink requirements (Boox Palma 2 — this is what makes it feel right)

The Palma 2 is a grayscale e-ink panel. An OLED-tuned UI ghosts and flickers on
it. Non-negotiable adaptations:

- **Animations off by default.** Page turns, transitions, fades, the rec shelf,
  chip animations — all fight e-ink refresh. Umbra already has a
  `reduceAnimations` setting and a `_reduceMotion` getter that makes page-turns/
  scrolls jump instantly; default it ON and extend it everywhere.
- **Light background, dark text — always.** E-ink is reflective, not emissive;
  OLED-style dark mode (light text on black) looks wrong and ghosts. Force
  high-contrast light themes. Re-check the tinted overlays against grayscale.
- **No full-screen black flashes;** make repaints deliberate.
- **Large, high-contrast tap targets;** e-ink touch is less precise and slower.
- **Bluetooth remote page-turn must be flawless** (the user reads with one) —
  and must NOT double-advance or fight the reading ruler (a bug that was
  specifically fixed in Umbra; check `_advanceRulerScroll` and
  `reader_ruler_key_test.dart`).
- **Optional, high-value:** integrate Boox's refresh-mode SDK (regal/A2) via a
  small Kotlin platform channel to control ghosting — the difference between
  "acceptable" and "native-feeling." Even in a Flutter build this is a
  worthwhile native bridge.

## Non-negotiable design principles (inherited from Umbra)

1. **Predictability contract.** Nothing moves, reorders, or pops up unless the
   user caused it. Read `PREDICTABILITY.md` and keep it true — it matters even
   more on e-ink, where unexpected repaints are physically jarring.
2. **Accessibility features are never gated.** They are the point of the app.
3. **Calm, never nagging.** No badges, no streak-guilt, no urgency, no dark
   patterns. Invitations, not demands.
4. **Test the load-bearing invariants.** Umbra pins pagination (measure==render),
   theme contrast, and the reminder copy with tests. Match that discipline;
   port the relevant tests when you fork.

## Suggested build order

1. New Flutter project; fork Umbra's Dart; strip iCloud/Pro/define; get it
   launching on the Palma 2 with a sideloaded EPUB.
2. E-ink pass: force light themes, animations off, verify the remote.
3. Novel Grabber OPDS + remote control (the content pipeline).
4. Walk the feature checklist above against the Umbra source, section by
   section, confirming parity on-device.
5. Boox refresh-SDK bridge (polish).

The whole thing already exists and works on iOS. Your job is to make it run —
and feel right — on e-ink, standalone. When in doubt, match `D:\UmbraReader`.
