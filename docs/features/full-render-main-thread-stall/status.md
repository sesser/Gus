Issue: #65

# Full render main thread stall: status

States: Not started · In progress · Done · Blocked · Deferred.

**State: Done.**

## Bug

**Steps to reproduce.** A 24 MP raw (synthetic 6000 × 4000 DNG) with a typical stack,
inspector hidden, window 3008 × 1662 on the 2× display, at 100%. Press → to arrive at
the next photo, or change a value with no pause (`adjust amount 55`), or let go of a
White Balance drag.

**Expected.** The window keeps responding (viewport-render-1to1 R8; `CLAUDE.md`:
images are fully decoded before they reach layers).

**Actual.** The main thread blocks for about 0.4 s on each arrival and each saved change
(1.3 to 2.7 s with machine learning noise reduction on).

**Root cause (confirmed by a main-thread sample).** `PreviewGenerator.cgImage` (the
loupe's full-resolution rendition, through `PreviewService.fullResolutionImage`) called
`RenderEngine.makeCGImage`, Core Image's short `createCGImage`, which defers an image
with a side over 4096 pixels (docs/features/sharpening-map-tiles/status.md). So the
rendition came back at once with nothing decoded or rendered, and the first reader was
Core Animation at the commit after `LoupeImageView.setImage`, on the main thread:
`CA::Transaction::commit` → `CA::Render::copy_image` → `CI::copyIOSurfaceCallback` →
`-[CIContext startTaskToRender:…]` → the RAW decode and the whole adjustment stack
(510 of 4781 main-thread samples over two arrivals, `sample` at 1 ms).

**Tests that fail without the fix** (`Tests/PhotoCoreTests/DeferredRenderTests.swift`):
`renderedWhereMade` (with the old deferred call: `pulled > 0` and the re-read both fail)
and `matchesCoreAnimationsRender` (with a bitmap render, the first attempt below: 3146
rows differ, by up to 24 levels).

## Ruling

The first attempt, `deferred: false` on `makeCGImage`, removed the stall but rendered
into a CPU bitmap: the photo got sharp about 0.7 s later (1.15–1.19 s instead of about
0.4 s) and showed slightly different values from what Core Animation used to show (up to
52 levels in 0.6% of values). Owner ruling (2026-11-15): **option B**, render the
full-resolution rendition into an IOSurface off the main thread and hand the layer that,
keeping today's time to sharp. The bitmap route is reverted.

## The fix

- `Sources/PhotoCore/Preview/RenderEngine.swift`: `makeSurfaceImage(_:colorSpace:)`
  renders with `CIRenderDestination` into a 32BGRA IOSurface on the caller's thread,
  waits for the GPU, and returns a `CGImage` over the surface's pixels (locked for
  reading for the image's life; the data provider's release unlocks and frees it). It is
  the same Core Image call Core Animation made from its commit, so the pixels are the ones
  it showed, within the one level Core Image varies by between any two renders, and it is
  as fast.
- `Sources/PhotoCore/Preview/PreviewGenerator.swift`: `cgImage(source:…)`, the 1:1
  rendition, uses it. It runs in `PreviewService`'s full-resolution lane (a background
  task), so the decode and render are off the main thread; the main thread only commits a
  ready image (7–14 ms headless).
- `makeCGImage` (live frames, maps, thumbnails), the file overload (exports, goldens,
  `photocli render`) and `makeHDRCGImage` are unchanged. **HDR keeps its deferred call:**
  its headroom is read off the main thread, which renders it, and Core Animation does not
  render an image again whose pixels were read (`coreAnimationRendersDeferredImages`,
  the HDR rendition itself included). So the HDR rendition had no main-thread render to
  remove; the `deferred: false` edit there is reverted too.
- Comments: `ViewportBenchmark` E4 (the rendition is rendered before the generator
  returns) and `AdjustmentEditor.loupeLoadsFullRendition`.
- `docs/USER_GUIDE.md`, Editing at 100%: the spinner can show after letting go while the
  full detail arrives; moving between photos at 100% doesn't pause the window.

**Tests** (`DeferredRenderTests`, serialized; Core Animation driven headless by
`CARenderer` in the image's own color space, which passes pixels through unchanged, on a
command queue of the test's so its work is awaited, not slept on):

- `renderedWhereMade`: a 5472 × 3648 image from a counting provider is rendered when
  `makeSurfaceImage` returns; reading it or drawing it through Core Animation asks its
  source for nothing more. Control: the short call still defers that image, so a macOS
  that stops deferring fails the test instead of passing blind.
- `coreAnimationRendersDeferredImages`: Core Animation renders an unread deferred image
  when it draws it (the old stall, so `CARenderer` stands for the window's commit), and
  does not render one again whose pixels were read, nor the HDR rendition.
- `matchesCoreAnimationsRender`: a 24 MP synthetic raw, typical stack, a radial mask and a
  vignette. Core Animation's own render of the deferred image (the old screen) and its
  draw of the new rendition are equal within one level per byte, and the latter equals
  the rendition's own pixels byte for byte (Core Animation passes them through). This is
  the GPU-surface output of the same Core Image call compared with the old lazy path,
  headless. Within one level, not exactly: Core Image's 8-bit output varies by one level
  between two renders of the same graph on either route (code review C1: up to 486 rows,
  never more than 1). A control in the test requires a bitmap render to differ by more
  than one level, so it still tells the routes apart; and with the bitmap route in
  `PreviewGenerator.cgImage` the test fails (3146 of 4000 rows, up to 24 levels). At
  4400 × 2934 the routes weren't told apart, hence the size.

No pipeline bump, no golden changed, `UPDATE_GOLDENS` not run.

## Measurements

Release bundles built by `Scripts/build-app.sh` in a scratch clone (macOS 27.2 SDK):
**before** is `476d6a9`, **B** is this fix, and **bitmap** is the first attempt
(`deferred: false`), kept for the ruling's comparison. Each was copied with the
identifier `me.sesser.gus.debug65` and `NSAppSleepDisabled`, and used a scratch
`photobench` library of four synthetic 6000 × 4000 DNGs, with `--library-root` on every
launch. MacBook Pro M4 Pro, macOS 27.2, the Dell (6016 × 3384) as main display, typical
stack, inspector hidden, window 3008 × 1662, at 100% (every heartbeat line reads
magnification 1.000). The display was asleep and the screen locked throughout (no
`caffeinate`), and nothing else built or ran. The old stall still shows that way:
Core Animation commits and renders the layer whether or not the display is lit. The
first measurements (before the ruling) were taken with the display awake and gave the
same figures (arrival 367–394 ms, commit 373–461 ms, ML 1352–2668 ms).

Method (QA's, viewport-render-1to1 `qa.md`): a marker (`print selection`) just before
each event, then a 20 ms heartbeat (`print loupe; wait 0.02` × 90) for the gaps, or
`print viewport` every 20 ms for the wait. A line's time is stamped as it arrives
(`ts.py`); 80 ms comes off the gap spanning a `key`. Median heartbeat 21.5–22.3 ms
everywhere, so nothing was throttled. Two rounds in alternating build order
(before, B, bitmap, then bitmap, B, before).

**Longest main-thread gap per event:**

| Case | Before | B (this fix) | Bitmap (`deferred: false`) |
|---|---|---|---|
| Arriving at a photo (→ / ←), 16 | 366–396 ms | 23–75 ms | 23–70 ms |
| Saved change (Amount, Temperature), 16 | 362–466 ms | 33–63 ms | 30–65 ms |
| Saved change, machine learning on, 8 | 1332–2067 ms | 31–84 ms | 55–92 ms |

The 30–65 ms right after a saved change is on every build (the save's own work).

**Time to sharp after a saved change**, from when the loupe starts waiting for the full
rendition to when it is on screen (before: the end of the main-thread stall, since its
wait clears at once and the render happens in the draw; B: the wait's end). Eight changes
per row:

| Case | Before | B | Bitmap (pre-ruling, display awake) |
|---|---|---|---|
| Amount, no pause | 407–475 ms (median 418) | 399–522 ms (median 424; one at 522) | 1.15–1.19 s |
| Amount, machine learning on | 1337–2056 ms | 1327–2095 ms | 1.82–2.19 s |
| White Balance drag let go | 419–491 ms | 380–463 ms | 1.17–1.19 s |

The spinner: never on before (the wait cleared at once). With B it shows after a White
Balance release, from 0.5 s after the last input to when the rendition lands, 40–260 ms
on screen; never after Amount (a sharp frame of the values is already showing). That is
design §2.1 as the designer expected (viewport-render-1to1 `review.md`, L1).

**Headless, the same work through Core Animation** (debug test build, 6000 × 4000, the
interactive engine, `CARenderer` standing for the window's commit, five alternating
rounds; scratch harness, not committed):

| | Rendition made (background) | Core Animation's draw (main thread) | Time to sharp |
|---|---|---|---|
| Before, typical stack | 31–32 ms | 361–395 ms | 392–427 ms |
| B, typical stack | 388–416 ms | 7–9 ms | 397–424 ms |
| Before, machine learning on | 33–38 ms | 1309–1413 ms | 1342–1447 ms |
| B, machine learning on | 1323–1377 ms | 7–14 ms | 1330–1391 ms |

The draw of B's IOSurface-backed image costs Core Animation 10–15 ms against about 5 ms
for an image in ordinary memory (headless). A copy out of the surface would trade that
for a 96 MB copy before the image is ready; not done.

## Memory at 100% (code review's question)

The app process's `footprint` (physical footprint), 30 s after arriving at a 24 MP raw
at 100% with the typical stack, same release bundles and scratch library as above (display
asleep, screen locked, no `caffeinate`), alternating builds:

| Build | Physical footprint | IOSurface, dirty |
|---|---|---|
| Before (`476d6a9`), 3 runs | 619, 694, 716 MB | 92 MB each |
| This fix, 2 runs | 628, 629 MB | 92 MB each |

So the app holds no second 96 MB copy: before, the 92 MB of IOSurface was the surface
Core Animation had Core Image render into; now it is the rendition's own, which Core
Animation draws from. The footprint is within the runs' spread (before varies by about
100 MB between runs). The window server's side is not measured here.

## Checks for a person

The scripted runs time the main thread and the wait, but not what the screen looks like.

- At 100% on a real 24 MP raw, arrow through photos: the window keeps responding (no
  hitch, no spinning cursor), and each photo turns sharp about as quickly as on `develop`.
- Let go of White Balance at 100%: the soft frame stays, a spinner may show briefly, and
  the sharp photo replaces it with no shift or flash. After Amount, the sharp frame stays
  until the full rendition replaces it, with no visible change.
- The same with machine learning noise reduction on (macOS 27): the window keeps
  responding during the 1.3–2 s wait.
- With machine learning on, at 100%, press → several times quickly (or hold it) and stop:
  the window keeps responding, and the photo you stop on may stay soft for up to one
  extra render (1.3–2 s) before it turns sharp (C2). Say whether that is objectionable.

## Not fixed here (noted, not filed, per the ruling)

- **`LiveRenderSession.base(for:)` and `materialize`** use the same short call, but not on
  the main thread: they run in the session actor, and at the loupe's 2560 px fit size
  Core Image doesn't defer at all (both sides ≤ 4096). Only a base a crop enlarges past
  4096, or a LibRaw full-frame base, is deferred, and then each frame reads it lazily
  (slower frames; the lazy-input fault seen in `SharpeningMapRefiner` is possible). Worth
  its own measurement. The issue's note that the 2560 px base is lazy is out of date.
- **The refined sharpening map at 100%** goes through `makeCGImage`; where its size
  passes 4096 it is likely deferred, and Core Animation would render it at first draw on
  the main thread as it did the full rendition. Not checked or measured here; the same
  fix would apply (`makeSurfaceImage`).
- **A bitmap render and a GPU-surface render of the same stack differ** (up to 52 levels
  in 0.6% of values on the typical stack at 6000 × 4000, a cluster along one row that
  looks like a tile seam; identical with no adjustments). Exports and the live region
  frames use the bitmap route, the loupe's full rendition the surface route, as before
  this fix, so the swap from a sharp tile to the full rendition can shift values slightly.
- **A full render can't be cancelled once it has started**, and the full-resolution lane
  has one slot (code review C2). Arrowing quickly through photos at 100% with machine
  learning on, the photo you stop on starts rendering only when the previous photo's
  render ends, so it can stay soft up to one more 1.3–2 s render. Before this fix each of
  those arrivals froze the window for as long instead.
- **Scripted first `Z`** after `windowsize`, with the display asleep or on first launch:
  the magnification stays at fit while the editor treats the view as at 100%; the next
  arrow key applies it. Possibly related to #153.

## Build and test

- Baseline: `swift build` clean at `476d6a9` before any edit.
- Fix commit `23c71f4`: `swift build` clean, `swift test` 1040 tests in 155 suites passed.
- Review fixes (C1, C2, memory): `swift build` clean, no new warnings. `swift test`,
  five full runs in a row: **1040 tests in 155 suites passed, 5 of 5** (65.9–70.2 s each). `UPDATE_GOLDENS` not run; no golden or
  pipeline version touched.
- Shown failing without the fix: `renderedWhereMade` with the old deferred call (2
  issues); `matchesCoreAnimationsRender` with the bitmap route (3146 rows, up to 24 levels).

## Review findings

| # | Finding | Answer |
|---|---|---|
| C1 (Blocker) | `matchesCoreAnimationsRender` compared two Core Image renders byte for byte; Core Image varies by one level between renders (2 of 5 full runs failed) | Fixed: one level per byte allowed, worst and row count in the message; a control requires the bitmap route to differ by more than one level; with the bitmap route in the product code the test fails (3146 rows, up to 24 levels). "Byte for byte" claims about the on-screen render reworded here, in the test and in `makeSurfaceImage`'s comment (the user guide made none). Five full runs pass |
| C2 (Nit) | A started full render can't be cancelled; one lane slot | Noted under "Not fixed here" and added to the checks for a person; no code change, as asked |
| Question: memory | Two 96 MB copies at 100%? | Measured: no; see "Memory at 100%" |

## Open questions

None. The spinner now shows after letting go of a raw setting at 100% when the full
rendition takes over half a second from the last input (design §2.1, the designer's L1
note at viewport-render-1to1); the UI changed in that sense, so the designer's review
applies.

## README

No change.
