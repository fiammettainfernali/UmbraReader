# Android port — one codebase, two platforms

**Target device:** Samsung Z Fold 8 Ultra (foldable, arriving soon)
**Written:** 2026-08-25

This supersedes `BOOX_ANDROID_BRIEF.md`, which planned a *fork* — a separate
standalone app for an e-ink Palma 2. That brief is now wrong on all three of
its main premises: this is one codebase shipping both platforms, the panel is
OLED rather than e-ink, and sync/accounts stay in. Keep the old brief for
reference, but do not build from it.

`D:\The Star Library` (the native Kotlin attempt, 30 files) is dead. Nothing
below reuses it.

---

## Where the code actually stands

Measured, not assumed:

| | |
|---|---|
| Dart | 107 files, 38,033 lines |
| Platform targets | **iOS only — there is no `android/` directory** |
| Dependencies | 22, **every one already supports Android** |
| Native bridges | 4 method channels, all iOS-only |
| CI | `codemagic.yaml`, single `ios-testflight` workflow |

The dependency list is the good news and it is worth being precise about why:
nothing in `pubspec.yaml` blocks Android. `drift`, `background_downloader`,
`flutter_tts`, `just_audio`, `flutter_secure_storage`, `webview_flutter`,
`flutter_local_notifications` — all cross-platform. There is no rewrite here.
The work is the four native bridges, the platform assumptions around storage
and permissions, and the foldable.

### The four bridges

These are the only places the Dart reaches into Swift:

| Channel | Used for | Android answer |
|---|---|---|
| `umbra/icloud_kv` | Settings + small state sync | See "the sync decision" |
| `umbra/icloud_docs` | Library document sync | See "the sync decision" |
| `umbra/define` | Tap-to-define (`UIReferenceLibraryViewController`) | `ACTION_PROCESS_TEXT` intent to whatever dictionary app is installed. Android has no system dictionary UI. |
| `umbra/now_playing` | Lock-screen TTS controls | `audio_service`, or a small Kotlin MediaSession bridge |

Only the first two are architectural. The other two are an afternoon each and
can ship disabled.

---

## The one decision to make first: sync

`cloud_sync_service.dart` is built on iCloud. Android has no iCloud, and this
is the only part of the port that is a design question rather than plumbing.
Three honest options:

**A. Platform-split.** iCloud on iOS, Google Drive on Android. Each platform
syncs with itself. A reader who owns both an iPhone and the Fold gets two
separate libraries that never meet — which, for the person writing this, is
exactly the wrong outcome.

**B. Sync through Novel Grabber.** It is already the hub, already self-hosted,
already exposes OPDS plus a `/api/*` control API, and is already reachable
over Tailscale. Genuinely cross-platform, no new vendor, and the reading
position could ride the same channel the downloads do. But `ROADMAP.md` commits
to Path A — selling a *general-purpose* OPDS reader — and most buyers will
never run Novel Grabber, so this cannot be the only answer for the product.

**C. Ship Android v1 local-only.** Every store already persists locally
(drift/SQLite + SharedPreferences). Sync is a layer on top, not a foundation.

**Recommendation: C now, B as the power-user path, A only if the product
demands it.** Concretely: extract a `SyncBackend` interface behind
`cloud_sync_service.dart`, make iCloud one implementation, and let Android
start with a null backend. That unblocks the entire port without deciding the
product question, and it is the smallest change that keeps the option open.

Do this *before* generating the Android target — it is much harder to unpick
once Android code is calling into the current shape.

---

## Phase 0 — before the device arrives

None of this needs the Fold. An emulator or any Android phone will do.

1. **Extract the sync interface** (above). One commit, iOS behaviour
   unchanged, tests still green.
2. **Generate the target**: `flutter create --platforms=android .` in the
   project root. This adds `android/` without touching `lib/` or `ios/`.
3. **Get it compiling.** Expect: Gradle/AGP versions, `minSdk` (set 26 —
   matches what the plugins want), Kotlin JVM target, NDK for `drift`'s
   SQLite.
4. **Permissions in the manifest**, all of which are runtime prompts on
   modern Android and none of which iOS needed in this form:
   - `POST_NOTIFICATIONS` — Android 13+, for the reading reminders.
     `flutter_local_notifications` schedules them; it does not ask for you.
   - `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` —
     `background_downloader` needs these to survive the app being backgrounded
     mid-volume.
   - `INTERNET`, `ACCESS_NETWORK_STATE`.
   - **Not** `MANAGE_EXTERNAL_STORAGE`. Star Library used it; it is a Play
     Store rejection risk and unnecessary. Use app-private storage via
     `path_provider`, and the Storage Access Framework for import/export.
5. **Boot it on an emulator** and open a sideloaded EPUB. That is the
   milestone for this phase — reader on screen, text laid out.

## Phase 1 — make it correct on Android

Walk the feature list and fix what the platform breaks. The likely list, in
rough order of how much trouble each will be:

- **Storage paths.** iOS documents dir vs Android app-private. `path_provider`
  abstracts it, but anything that stored an absolute path is now wrong.
  Check the EPUB store and backup/restore first.
- **Background downloads.** Foreground-service notification, Doze, and
  battery optimisation all bite here. Auto-download-next-volume is the
  feature most likely to quietly stop working.
- **Secure storage.** `flutter_secure_storage` maps to the Android Keystore.
  Verify the OPDS password round-trips.
- **File picker / share.** SAF behaves differently from the iOS document
  picker; `file_picker` and `share_plus` cover it but need testing.
- **Back gesture.** Android has a system back; iOS does not. Every sheet,
  the reader, and the nav shell need to do the right thing —
  `PopScope` on anything that currently relies on an explicit close button.
- **TTS voices.** `flutter_tts` on Android exposes a different voice set.
  Pronunciation overrides were tuned against AVSpeechSynthesizer.
- **Fonts and metrics.** The pagination invariant is *measure and render must
  use identical text styles*. Android's default font stack is not iOS's; if
  anything resolves a font differently between the measure pass and the render
  pass, pages overflow. `pagination_overflow_test.dart` is the guard — run it
  on Android before believing anything else.

## Phase 2 — the foldable

This is the part with no precedent in the codebase, and the reason the device
matters.

The good news, and it is substantial: **the reader already handles this class
of problem.** `reader_screen.dart` renders a two-page spread on
"tablet-sized and landscape" viewports and explicitly repaginates on iPad
split-view resize. Reading position is tracked as
`(chapterIndex, blockIndex, blockChar, chapterPath)` precisely so it survives
repagination. A fold/unfold is, mechanically, a very abrupt split-view resize
— the machinery is there.

What still needs doing:

- **Fold/unfold continuity.** The app moves between the cover display and the
  inner display. Position must survive it, mid-sentence, with no flash of the
  wrong page. This is the single acceptance test that matters: *unfold in the
  middle of a paragraph and land on the same word.*
- **Two-page spread on the inner screen.** The existing trigger is
  tablet-size + landscape. Unfolded the Fold is tablet-sized but likely
  *portrait-ish* and nearly square — so the current condition probably will
  not fire, or will fire wrongly. Re-derive it from aspect ratio and width
  rather than from an orientation flag.
- **Table-top posture.** Half-folded, hinge horizontal. The natural mapping is
  text on the upper half, controls on the lower. This is a genuine
  differentiator and also entirely optional — do it last, if at all.
- **Continuity when resuming on the cover screen.** The narrow outer display
  is a different reading measure. One column, larger relative type.
- **Multi-window / split-screen.** `resizeableActivity` is on by default;
  make sure a resize repaginates rather than clipping.

**I do not know the Z Fold 8 Ultra's exact panel sizes or aspect ratios** — it
is newer than anything I can verify, and I am not going to invent numbers that
layout code would then be written against. Measure the real device on day one
(`MediaQuery.sizeOf`, both postures, both displays), write the numbers down,
and derive the breakpoints from those. Jetpack WindowManager exposes the hinge
and posture; Flutter reaches it through `display_features` in `MediaQuery`,
which is the right source for table-top detection.

## Phase 3 — shipping

- **Signing + CI.** `codemagic.yaml` gains an `android` workflow alongside
  `ios-testflight`. Upload keystore, Play Console service account.
- **Pro gating.** `pro_service.dart` and six call sites currently assume
  StoreKit. `in_app_purchase` covers Play Billing, but products must be
  created in the Play Console and the restore path differs. For personal use
  a `--dart-define` that unlocks everything is a two-line stopgap.
- **Play Store review.** The listing must describe a general-purpose OPDS/EPUB
  reader. Per `ROADMAP.md`'s own strategic note, the Novel Grabber pipeline is
  an optional power-user integration, not the product — and a store listing
  that reads as a webnovel-scraping tool is the fastest way to a rejection.

---

## Order, and what to do first

The dependency chain is short and rigid at the front:

```
sync interface  →  flutter create android  →  compiles  →  runs  →  correct
                                                                      ↓
                                                          foldable  →  ship
```

Start with the sync extraction today; it is the only piece that gets harder
if deferred, and it needs no device.

## What this plan deliberately does not do

- **No fork.** 38k lines maintained twice is how the app dies. One codebase.
- **No e-ink work.** That was the Palma. Everything in the old brief about
  forcing light themes, killing animations and the Boox refresh SDK is
  irrelevant to an OLED foldable — and actively wrong, since the Fold should
  get the full animated UI.
- **No rewrite of the reader.** The EPUB parser and pagination engine are the
  crown jewels and they are platform-agnostic Dart. They come across untouched.
- **No Star Library salvage.**

## The risk worth naming

Pagination. Everything else on this list is plumbing with a known shape;
pagination is the one system where a platform difference produces a subtle,
data-dependent wrongness rather than a crash — a font resolving differently
between the measure pass and the render pass gives you pages that overflow on
some chapters and not others. It is also the system a foldable stresses
hardest, because the viewport changes size abruptly and often.

Run `pagination_overflow_test.dart` and `block_measure_test.dart` on Android
early — Phase 0, not Phase 2. If they pass on Android, the port is mostly
plumbing. If they do not, that is the project.
