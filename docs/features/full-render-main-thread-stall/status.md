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

## Owner's finding: the photo jumps when arriving at 100%

**Finding (owner's manual check, 2026-11-15).** At 100%, moving from photo to photo with
the arrow keys, the photo jumps down and to the left by about 25–50 px every time, on
the owner's Sony ARW files. Not acceptable.

**Also on `develop`; made more visible here.** On 476d6a9 the same resize happens at the
same moment (the tables below), but the window was frozen during the wait, so it read as
part of the stall. With this fix the window responds while the wrongly sized preview is
on screen, then the photo jumps. The IOSurface rendition itself is not the cause: headless
on real ORF and RAF files it lands exactly where the old lazy image did (shift 0,0,
identical pixels), and a probe with the image's extent away from the origin renders the
same through both routes.

**Cause.** `LoupeView.show(index:)` (and the comparison pane's `show`) sized the image
view on arrival from `CatalogItem.orientedSize`, which is the file's metadata as imported.
ExifTool, which imports use when it is installed, gives a raw its raw data's size
(`ImageWidth`): a Sony ARW is 6048 × 4024 in the catalog and renders at 6000 × 4000
(ExifTool's own `ExifImageWidth` and `DefaultCropSize` say 6000 × 4000); an Olympus ORF
is 4640 × 3472 against 4608 × 3072. A crop in the edit stack is in neither. When the
full-resolution rendition landed, `matchFrame(to:exact:)` resized the view to its real
size and re-centred it, so the photo shrank and moved.

**Fix.**
- `PreviewGenerator.outputSize(source:stack:)` reads the size the rendition will have
  from the same lazy graph `cgImage` renders, with nothing decoded or rendered (a header
  read, 20–100 ms): the decoder's frame, the orientation, turns, straightening and crop are
  all in it. Nil for a video, a raw only LibRaw decodes and a linear DNG, where only a
  decode would tell.
- `PreviewService.outputSize(for:)` computes it off the main thread and keeps it
  (`memoryCachedOutputSize(for:)`, at most 4096 entries); every full rendition records its
  own size there too.
- `LoupeArrivalSize.size(knownOutput:catalog:)` (PhotoCore) is the arrival rule: the
  rendition's size when known, else the catalog's. `LoupeView` and `ComparisonView` use it.
  The loupe asks for its neighbors' sizes along with their previews, so arrow-key arrivals
  know it. When it isn't known (a jump to a photo not visited or prefetched), the size is
  corrected as soon as it is learned, about 100–150 ms after arriving and before the full
  rendition, keeping the same place in the middle (at fit, it fits again).
- `matchFrame(to:exact:)` at a zoom other than fit now keeps the same place in the middle
  when a rendition's size differs (`matchFrame(toOutput:)`), instead of re-centring on the
  photo; at fit it fits again as before. That only applies where the size wasn't known.
- No catalog change, no migration: the catalog's size still feeds the film strip's cell
  proportions and the preset tiles, where a fraction of a percent doesn't show.

**Tests** (`Tests/PhotoCoreTests/OutputSizeTests.swift`): the size learned before
rendering equals the rendition's, is kept, and the rendition records its own; the
arrival rule gives the rendered size once the size was asked ahead. Cases: a synthetic
DNG with a crop and a quarter turn (catalog 1200 × 800, rendered 480 × 600), a JPEG with
EXIF orientation 6, an untouched DNG, and a real raw through `CAMERA_RAW_SAMPLE` (skipped
when unset), read with the importer's own metadata reader. Shown failing without the fix
(the rule back to the catalog's size first): the cropped DNG arrives at 1200 × 800 against
480 × 600 rendered, and the real ARW at 6048 × 4024 against 6000 × 4000. With
`outputSize` replaced by the file's own size, the rotated JPEG and the cropped DNG fail.
Real files run: `DSC00329.ARW` (catalog 6048 × 4024, rendered 6000 × 4000) and
`10M10288.ORF` (4640 × 3472, 4608 × 3072), both pass.

**Measurements.** Release bundles of 476d6a9, 23c71f4 and this fix (identifier
`me.sesser.gus.debug65`, `--library-root` on every launch), window 3008 × 1662, inspector
hidden, display asleep (no `caffeinate`). Libraries: three copies of the owner's ARWs
(copied from `~/Pictures`, originals untouched), the real ORF and RAF folder imported in
place read-only, four JPEG copies. After each arrow (or a `focus` jump), `print loupe` and
`print viewport` every 20 ms for 1.4 s; a row lists each state the image view took (its
size in points and the visible origin) with the time it appeared.

| Case | 476d6a9 | 23c71f4 | This fix |
|---|---|---|---|
| ARW at 100%, arrows (4) | 3024 × 2012 pt at 83–88 ms, then 3000 × 2000 at 154–269 ms | the same, 3000 × 2000 at 265–286 ms | 3000 × 2000 throughout |
| ORF at 100%, arrows (4) | 2320 × 1547 (origin x −234), then 2304 × 1536 (−242) at 154–318 ms | the same at 307–323 ms | 2304 × 1536 (−242) throughout |
| ORF at 100%, jump to a photo not seen yet | 2320 × 1547, then 2304 × 1536 at 378 ms | at 314 ms | 2320 × 1547 at 38 ms, 2304 × 1536 at 171 ms (size learned, before the full rendition) |
| ORF cropped and turned, at 100% | 1450 × 2320, then 864 × 1382 at 263–278 ms | not run | 864 × 1382 throughout |
| RAF, landscape and rotated, TIFF, at 100% | steady (metadata right) | not run | steady |
| JPEG at 100% | steady | not run | steady |
| ORF at fit | 2320 × 1547 at fit (no full rendition at fit) | not run | 2304 × 1536 at fit, steady |

The film strip and Compare (a pair of ARWs, arrow in Compare, leaving it) were exercised
with the fix: panes fit, captions and positions as before.

## Checks for a person

The scripted runs time the main thread and the wait, but not what the screen looks like.

- At 100% on a real 24 MP raw, arrow through photos: the window keeps responding (no
  hitch, no spinning cursor), and each photo turns sharp about as quickly as on `develop`.
- Let go of White Balance at 100%: the soft frame stays, a spinner may show briefly, and
  the sharp photo replaces it with no shift or flash. After Amount, the sharp frame stays
  until the full rendition replaces it, with no visible change.
- The same with machine learning noise reduction on (macOS 27): the window keeps
  responding during the 1.3–2 s wait.
- **The jump (owner's finding):** at 100% on Sony ARWs, arrow from photo to photo: the
  photo must not move or resize when it turns sharp. Also after jumping to a photo by a
  click in the film strip or the grid: at most one early correction (about 0.1 s after
  arriving), none when it turns sharp. Same check on a cropped photo and in Compare.
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
- **The catalog's pixel size for raws** comes from ExifTool's `ImageWidth`, the raw
  data's size (ARW 6048 × 4024 against a 6000 × 4000 image; ExifTool's `ExifImageWidth`
  and `DefaultCropSize` give the image). The loupe no longer depends on it; the film strip
  and preset tiles use its proportions, which are off by a fraction of a percent. Reading
  the image size at import would change catalog data and need a re-read of existing
  libraries.
- **A jump to a photo whose size isn't known** (not visited, not a neighbor) still
  corrects once, about 0.1 s after arriving, before it turns sharp. Prefetching sizes
  further (the film strip's visible cells) would remove that.
- **`PreviewService.outputSize` doesn't coalesce** two identical requests running at once
  (each reads the header), and always runs at `.userInitiated`, prefetches included (code
  review C4). Each read is 20–100 ms and a held arrow key now cancels them (C3); no lane or
  in-flight map was added.
- **Scripted first `Z`** after `windowsize`, with the display asleep or on first launch:
  the magnification stays at fit while the editor treats the view as at 100%; the next
  arrow key applies it. Possibly related to #153.

## Build and test

- Baseline: `swift build` clean at `476d6a9` before any edit.
- Fix commit `23c71f4`: `swift build` clean, `swift test` 1040 tests in 155 suites passed.
- Review fixes (C1, C2, memory): `swift build` clean, no new warnings. `swift test`,
  five full runs in a row: **1040 tests in 155 suites passed, 5 of 5** (65.9–70.2 s each). `UPDATE_GOLDENS` not run; no golden or
  pipeline version touched.
- Arrival size fix: `swift build` clean, no new warnings. `swift test` twice: **1044 tests in 156 suites passed, 2 of 2** (the real-raw case skipped without `CAMERA_RAW_SAMPLE`; run by hand on the ARW and the ORF, both pass).
- Review fixes C3, C4: `swift build` clean, no new warnings. `swift test` twice: **1045 tests in 156 suites passed, 2 of 2**.
- Shown failing without the fix: `renderedWhereMade` with the old deferred call (2
  issues); `matchesCoreAnimationsRender` with the bitmap route (3146 rows, up to 24 levels).

## Review findings

| # | Finding | Answer |
|---|---|---|
| C1 (Blocker) | `matchesCoreAnimationsRender` compared two Core Image renders byte for byte; Core Image varies by one level between renders (2 of 5 full runs failed) | Fixed: one level per byte allowed, worst and row count in the message; a control requires the bitmap route to differ by more than one level; with the bitmap route in the product code the test fails (3146 rows, up to 24 levels). "Byte for byte" claims about the on-screen render reworded here, in the test and in `makeSurfaceImage`'s comment (the user guide made none). Five full runs pass |
| C2 (Nit) | A started full render can't be cancelled; one lane slot | Noted under "Not fixed here" and added to the checks for a person; no code change, as asked |
| Question: memory | Two 96 MB copies at 100%? | Measured: no; see "Memory at 100%" |
| C3 (Should fix, second pass) | A cancelled neighbour prefetch still started a size read (`try?` swallowed the cancellation; the detached read didn't inherit it), so a held arrow key started unbounded reads | Fixed: the prefetch stops when cancelled before the size read and before the HDR one; `outputSize` returns nil without starting a read for a cancelled caller, and cancelling it while the stack loads stops the read before it starts (`withTaskCancellationHandler`). Test `cancelledCallerStartsNoRead` (fails 3 of 3 without the entry guard) |
| C4 (Nit, second pass) | No coalescing of identical size requests; always `.userInitiated` | Noted under "Not fixed here", as asked |
| Owner (sign-off check) | At 100% the photo jumps 25–50 px on each arrow key (Sony ARW) | Also on `develop`, more visible since the window no longer freezes. Fixed: the photo is sized on arrival from the rendition's size, learned without rendering; see "Owner's finding" |

## Open questions

None. The spinner now shows after letting go of a raw setting at 100% when the full
rendition takes over half a second from the last input (design §2.1, the designer's L1
note at viewport-render-1to1); the UI changed in that sense, so the designer's review
applies.

## README

No change.
