# What the Fold makes possible that the iPhone did not

**Written:** 2026-08-26, the night before the device arrives.

Two separate questions, deliberately kept apart:

- What the **foldable hardware** enables — two panels, a hinge, postures.
- What **Android as a platform** allows that iOS refused. This is the larger
  of the two and the one nothing in the port plan covers.

Specs below are *reported*, not measured. The rule from `ANDROID_PORT_PLAN.md`
stands: measure both panels on day one and correct anything here that the
device contradicts.

---

## The device, and what it already tells us

| | Cover | Inner |
|---|---|---|
| Size | 6.5" | 8.0" |
| Resolution | 2520 x 1080 (21:9) | 2504 x 2256 |
| Aspect (portrait) | **0.43** | **0.90** |
| Aspect (landscape) | 2.33 | 1.11 |

Three things fall out of this immediately.

**`kSpreadMinAspectRatio = 0.8` appears to be right.** It was set as a
placeholder chosen to leave iOS unchanged, with no knowledge of the panel. The
inner display in portrait is 0.90 — above the threshold, so it opens the
spread. That is exactly the case the old `width > height` flag refused, and
the reason the rule was rewritten. Confirm it against the real number, but the
guess landed.

**Both gates in `shouldUseSpread` are load-bearing, and each covers a case the
other does not.** The cover screen *in landscape* has a ratio of 2.33, which
sails past the ratio gate; only `shortestSide >= 700` stops it from splitting a
415dp strip into two columns. Remove either gate and this device breaks.

**One number is worth checking carefully.** The inner panel clears the 700dp
gate with room at most densities (859dp at 2.625) but only 752dp at 3.0. If
Samsung's default display scaling — or the user's own "make everything
smaller/larger" setting — pushes the inner shortest side under 700, the spread
silently stops appearing. Read `MediaQuery.devicePixelRatio` alongside the
sizes on day one, and try the display-size slider at both extremes.

**The S Pen is out.** Samsung dropped stylus support with the Fold 7 and the
Fold 8 Ultra does not have it. Handwritten margin notes and stylus highlighting
are off the table — worth stating plainly, because it is the first idea a
foldable e-reader suggests and it is not available.

---

## Group A — the hinge and the two panels

### A1. Table-top reading (Flex Mode). *The genuine differentiator.*

Half-folded, hinge horizontal: text on the upper half, controls on the lower.
The book stands on a table and reads hands-free — while eating, while cooking,
on a train tray. No phone does this and no iPad does it without a case.

Flutter needs no plugin: `MediaQuery.displayFeatures` exposes the hinge with
its bounds, state (flat / half-opened) and orientation, sourced from Jetpack
WindowManager. The reader already repaginates on resize, so the work is a
layout that reads the hinge rather than new machinery.

Cost: medium. Value: this is the feature that makes the device worth having.

### A2. Per-posture reading settings

A 17pt measure tuned for a 415dp cover strip is wrong on an 859dp panel, and
vice versa. Today `ReaderSettings` is one global set, so unfolding gives you
the cover's type size on a screen twice the width.

Store the size-dependent settings (font size, margin, centred column, spread)
per *posture class* rather than globally — cover / inner / table-top. Unfolding
then lands on the measure you chose for that panel instead of one you chose for
the other.

This is small, invisible when it works, and the single thing most likely to
make the device feel considered rather than merely supported.

### A3. Cover-screen reading as its own mode

21:9 at ~415dp is narrower than any phone the reader has been tuned on. One
column, larger relative type, fewer chrome affordances. Position continuity
already works; the measure does not exist yet.

### A4. Fold-aware continuity polish

Already largely working — the unfold test passes. What is missing is the
*flourish*: unfolding mid-paragraph could land with the same word at the top of
the left page of the new spread, rather than merely on the correct page.

---

## Group B — what Android allows and iOS did not

This group is where the unexplored value is. None of it is foldable-specific;
all of it was simply unavailable before.

### B1. Share a novel URL straight into the app. *Highest value per hour.*

`ControlClient.addNovel(url)` already exists and posts to `/api/novels`. The
Chrome extension does exactly this from the desktop. On Android the app can
register as a **share target**, so sharing a URL from mobile Chrome hands it
directly to Umbra, which forwards it to Novel Grabber.

That is the desktop extension's entire job, on the phone, with the plumbing
already written. iOS could only have done this through a separate share
extension target.

`launchMode` is already `singleTop`, which is what the share intent needs.
Cost: an intent filter and a handler. Value: removes the laptop from the
"I found a novel" loop entirely.

### B2. Open an `.epub` from anywhere

Register as a VIEW handler for `application/epub+zip` and Umbra becomes the
thing that opens a book from a file manager, a download notification, an email
attachment, or a browser. `imported_books_store.dart` already knows how to take
a file and shelve it.

Note the connection to the known picker risk: the same MIME string that may
grey files out in the picker is the one this registers. Testing them together
on day one answers both.

### B3. Home screen widget — "continue reading"

Cover, title, progress, tap to resume where you stopped. `home_widget` covers
the Flutter side. Android's widgets are richer and more prominent than iOS's,
and a reader is close to the ideal widget: one glanceable state, one action.

A second candidate: the reading streak and daily goal, which `StatsScreen`
already computes.

### B4. Background downloads that actually finish

iOS background limits are why auto-download-next was the feature "most likely
to quietly stop working". Android's foreground service can pull a whole series
while the phone is in a pocket. The permissions are already in the manifest and
`background_downloader` already handles the service — this is mostly a matter
of trusting it with more work than iOS ever allowed.

### B5. A watched folder

Point Umbra at a real directory over SAF and let anything dropped there appear
in the library. On iOS the file system was a locked box; on Android this is a
normal thing an app may do.

### B6. Multi-window, App Pair, and DeX

Mostly free rather than mostly work. `resizeableActivity` is on, and
repagination on resize is tested. What is worth adding:

- **Drag text out of the reader** into a notes app in the adjacent window.
  Android supports cross-app drag in multi-window; iOS never offered it here.
- **App Pair**: Umbra beside a notes app, launched as one icon.
- **DeX**: an external monitor is just a very wide viewport, which
  `shouldUseSpread` already handles correctly.

---

## Group C — Android platform polish

Small, mostly self-contained, and the difference between an iOS app that runs
on Android and one that belongs there. Three of these are already *missing*
rather than merely absent — checked against the manifest tonight.

### C1. Opt into predictive back. *One line, and it finishes tonight's work.*

`android:enableOnBackInvokedCallback="true"` is **not set**. The `PopScope`
added to `HomeShell` works, but without this the system cannot draw the
predictive preview — the peel-back animation showing where the gesture will
land before you commit to it. Flutter's `PopScope` was designed for exactly
this and already supplies `canPop` ahead of time, which is the hard part.

The one thing to verify: with the shell intercepting back on sub-tabs, the
preview should show the Library rather than the home screen.

### C2. App shortcuts

Long-press the launcher icon: *Continue reading*, *Library*, *Search*. Static
shortcuts are an XML file; a dynamic one could name the actual current book.
These also populate Samsung's Edge panel, so C2 quietly does D3's work.

### C3. A themed (monochrome) app icon

**Not present.** On One UI's themed-icon setting every other icon tints to the
wallpaper and Umbra stays full-colour — conspicuous in the wrong way. A single
monochrome drawable fixes it.

### C4. Dynamic colour, as an option rather than a default

The theme is a fixed dusk-plum seed, deliberately — the "comfy witchy library"
identity is the app's own. Android can theme from the wallpaper instead.

Offer it as a setting, off by default. The reader's own page themes should stay
untouched either way: what you read on is a reading decision, not a system one.

### C5. Respect the system font scale in the chrome

The reader has its own size control, so it is exempt. The library, settings and
stats are not, and One UI's font-size slider is prominent enough that people
actually move it. Worth a pass at the largest setting.

### C6. A Quick Settings tile

One pull-down, straight back into the current book. Cheap, and it suits a
reader better than most app types.

---

## Group D — One UI and Samsung

### D1. The Now Bar. *The most interesting thing Samsung has opened up.*

One UI 8 opens the Now Bar to third-party apps, built on Android 16's **Live
Updates** — an ongoing notification with `Notification.ProgressStyle` and
`setRequestPromotedOngoing(true)`, promoted to the lock screen and the Now Bar.
This is Android's answer to iOS Live Activities, and it arrived after the iOS
app was written.

It requires targeting API 36. **The app already does.**

The natural fit is a series download: chapters fetched, volumes remaining,
progress advancing on the lock screen without unlocking. `background_downloader`
already emits exactly that progress. A second candidate is the daily reading
goal, which `StatsScreen` already computes.

Of everything in this document, this is the one with the largest gap between
"clearly possible" and "nobody has done it in a reading app".

### D2. Samsung DeX

An external monitor is a very wide viewport, and `shouldUseSpread` already
handles those correctly. Mostly a matter of trying it and seeing what the
chrome does at desktop scale. Free until proven otherwise.

### D3. Edge panel

No API to integrate with — but the Apps edge panel picks up app shortcuts, so
C2 delivers this without extra work. Worth knowing rather than planning.

### D4. Modes and Routines — *speculative, verify before believing*

One UI 8 expanded Routines with new triggers and actions. A "Reading" mode that
dims the screen, silences notifications and opens the current book is obviously
attractive. What I could not confirm is how much a third-party app can *expose*
to Routines versus merely being launched by one. Treat as an experiment to run
on the device, not a feature to plan around.

### D5. Quick Share for backups

`backup_service.dart` already writes a file and hands it to the system share
sheet. On a Samsung device that sheet includes Quick Share, so the backup can
go straight to another device. Already works — worth testing rather than
building.

---

## Suggested order

Measurement first, then the things that are nearly free, then the big ones.

**Day one, before anything is built**

1. **Measure both panels, both postures, and both display-scaling extremes.**
   Everything here is calibrated against those numbers, and C1's 752dp margin
   at density 3.0 is the one that could quietly disable the spread.

**Then the cheap wins — roughly an evening for all four together**

2. **C1 predictive back** — one manifest line, and it completes the back-gesture
   work already done.
3. **C3 themed icon** — one drawable; without it the icon stands out on a
   themed home screen.
4. **C2 app shortcuts** — an XML file, and it populates the Edge panel for free.
5. **D5 / D2 / B6** — Quick Share, DeX and multi-window need *testing*, not
   building. Find out what already works before planning anything.

**Then the real features, in value order**

6. **B1 share a URL to add a novel.** Highest value per hour in the document.
   The server call already exists; this removes the laptop from the loop.
7. **A2 per-posture reading settings.** Small, and it is what stops an
   unfolded device feeling like a big phone.
8. **B2 open `.epub` from anywhere.** Test with the picker MIME question.
9. **D1 the Now Bar via Live Updates.** The largest gap between "clearly
   possible" and "nobody has done this in a reading app". Needs no new
   permissions and the target SDK is already right.
10. **A1 table-top reading.** The differentiator, and the biggest single piece.
11. **B3 the home screen widget.**

**As appetite allows:** A3, A4, B4, B5, C4, C5, C6, D3, D4.

---

## Excluded, and why

- **Anything needing the S Pen.** The Fold 8 Ultra does not have it.
- **Anything that changes iOS behaviour to suit Android.** The port has held
  that line so far and it is worth keeping.
- **Dynamic colour as a default** (C4). The app's identity is deliberate; the
  wallpaper should be able to override it only on request.
- **D4 Modes and Routines** is listed but unverified — how much a third-party
  app can expose to Routines is a question for the device, not a plan.
