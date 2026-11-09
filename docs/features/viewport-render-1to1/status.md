# Sharp live frames at 100%: implementation status

Owner: swift-macos-engineer. Spec: [`prd.md`](prd.md) (Approved),
[`design.md`](design.md) (Designed). Branch `feature/viewport-render-1to1`,
from `ca3f67d`.

**Status: Done.** Every acceptance criterion is built and checked or tested, and
every finding of `code-review.md` (C1–C13) and `review.md` (F1–F5) is fixed; see
"Review findings". Reviewers' confirmation is pending (not re-reviewed yet). The
reference display is a DELL U2723QE (owner, 2026-11-09: "Yes, the Dell"). On it the
original R7 target of 100 ms was not reachable as built (p95 139.5–159.2 ms). Offered
faster frames (A + C) or today's speed with the target restated, the owner ruled
**"Accept as measured"** (2026-11-09): R7/AC9 is 95% of frames under about 160 ms for
a typical stack on the Dell's two canvases, which is met. The product manager restates
it in the PRD. What only a person can judge is the manual rows of the acceptance table
and "Design §6 checks". Next step: code-reviewer's and the designer's second pass on
the fixes, then qa-tester.

States: Not started · In progress · Done · Blocked · Deferred.

## What changed

- `Sources/PhotoCore/Edits/LiveRegionRenderer.swift` (new): an actor holding
  the decoded master at full resolution in a GPU-private half-float texture
  (one RAW decode's settings at a time). Every frame renders the whole
  adjustment graph over that texture and Core Image evaluates only the region
  asked for, so everything that depends on the whole photo (local tone and
  dehaze estimates, masks, Color Alignment, vignette, grain) is exactly as in
  the full-resolution render. Frames come as a fully rendered BGRA8 `CGImage`
  in the display color space (`createCGImage(… deferred: false)`).
- `Sources/PhotoCore/Edits/LiveRenderSession.swift`: the mask overlay's blend is
  shared (`withOverlay`).
- `Sources/PhotoApp/Model/AdjustmentEditor.swift`: `loupeViewport`, `regionFrame`,
  the render loop (sharp region frames at covered zooms; a whole-photo frame on
  pause and at commit for the histogram, the soft base and the preview seed),
  decode-on-pause (`startRegionDecode`), the spinner's rule (design §2.1,
  `isAwaitingSharpFrame`), `setLoupeViewport`, `frameTrace` for the debug script.
- `Sources/PhotoApp/Loupe/LoupeView.swift`: a tile layer (`LoupeImageView.setTile`)
  over the whole image for the sharp frame; the visible area in unit coordinates
  (`updateLoupeViewport`, covered = 100% within a percent, as the toolbar);
  the tile stays until the full rendition lands; smooth enlargement of anything
  that is not real pixels (`updateFiltering`, design §2.2).
- `Sources/PhotoBench/ViewportBenchmark.swift` (new, `photobench viewport`): AC9.
- Debug script: `adjust scrub <name> <from> <to> <steps> [ms] [hold]`, `zoomstep [out]`,
  `print viewport`, `print frames`.
- Strings: the two hints (design §1), the spinner's widened comment
  (`Localizable.xcstrings`). `docs/USER_GUIDE.md`: the paragraph from design §1 and
  "100%" in the keys table.
- `Tests/PhotoCoreTests/LiveRegionRendererTests.swift` (new).
- After the review: `LiveFrameRules` (`LiveRegionRenderer.swift`) holds the decisions the editor
  and loupe share; `Frame.overlayMask` says which mask a frame's overlay is; `shouldDecode(whileMoving:)`
  starts one decode when a moving frame's settings settle. Debug script: `adjust scrub mask:<control>`,
  `pan <dx> <dy>`, `print previews`; `print viewport` also prints the sublayer order and the base's filter.

No golden moved, no pipeline version bump, no change to `CLAUDE.md` rules, no new
dependency, no bundle script change.

## Build and test

- Baseline at `ca3f67d`: `swift build` clean. `swift test` was not run before the
  first edit; the first full run (with the region renderer and 1 of its tests)
  was 635 tests, 1 known issue (the existing `LiveSessionTests` one).
- Latest (after the review fixes): `swift build` clean. `swift test`: **646 tests in 109 suites
  passed, 1 known issue (the existing one)**. Before that, on the first `swift test` after the
  fixes, two tests failed, once each: `SharpeningMapTests` "The map's input is the image the
  sharpening step sees" and `EffectsTests` `grainAddsTextureAroundTheSameLevel` (exact equality of
  two renders). Both passed on three reruns of those suites and on the rerun of the full suite;
  they exercise `AdjustmentRenderer` directly, which this diff doesn't change, and they passed on a
  build of the code before these fixes, so whether the failure predates this is not shown.
- `LARGE_RENDER_TESTS=1 swift test --filter LiveRegionRendererTests`: 12 of 12 passed. The AC1 scene
  is now `pixelGrid` (real one-pixel detail, code review C10).
- No `UPDATE_GOLDENS` was run. AC9 was not re-measured: the fixes change which frame reaches the
  screen and when a decode starts, not the render of a region frame, so frame time is unchanged.

## R12's tolerance (E2)

A frame must match the same area of the full-resolution render (R12, AC1, AC5,
AC12's comparison with the whole render). Two separate renders of the same image
can only differ through rounding, so the bound comes from the formats:

- The frame is rendered over the texture (RGBA16Float: one more half-float
  rounding than the whole render, 2⁻¹¹ relative) and the rest of the graph is the
  same; intermediates inside the graph are half-float in both (`.workingFormat`).
- A rounding is an absolute error up to 2⁻¹¹ of the larger of a pixel and the
  values it is mixed with (a blur, a neighbor, a gain), taken as 1 at most, and
  the stages after the texture enlarge a difference by a gain `g`.
- That error shows on screen through the display curve's slope at the pixel's
  own level (Display P3 uses the sRGB transfer: 12.92 below linear 0.0031, then
  0.44 × L^−0.583), so a level-dependent number of 8-bit steps.

**Tolerance per channel value:** `steps(g, v) = ⌈2⁻¹¹ · g · S(L(v)) · 255⌉ + 1`,
with `L(v)` the linear value of the 8-bit value `v`, `S` the slope above, and
`g` the product over the stages after the texture of `1 + 2 × strength` for each
sharpening or clarity step and the largest relative slope of the tone curve (the
reasoning `LiveSessionTests.gain` uses, in `LiveRegionRendererTests.typicalGain`,
now including Exposure's 2^ev and the local tone and Dehaze tables' gains: 10.0 for the typical stack).
Comparison rule: the frame's value is within `steps` of the whole render's
(`allowedSteps(gain:encoded:)` in the tests). Near white that is 2 steps; at black 18.

The two limits named in the PRD:

- `PHASE6_PLAN.md` finding 2 (up to 2.9 × 10⁻³ between two crops, at patch edges):
  did not appear in AC1's 24 MP comparisons, where the worst difference anywhere
  was 1 step, center, corner, cropped and straightened, and it is not
  claimed to be covered by `steps`.
- Finding 6 (`CIEdgePreserveUpsample` region-dependent edge pixels on macOS 26):
  not expected here (this machine runs macOS 27) and not seen; the estimates are
  always computed over the whole frame, so only the sampling differs. If CI on
  macOS 26 hits it, it is a known limit of the OS filter, not of this code.

Measured (6000 × 4000 `pixelGrid` scene, where every pixel differs from its neighbors,
`LARGE_RENDER_TESTS=1`, typical stack): worst 8 steps (center) and 2 (corner) uncropped,
7 and 2 cropped and straightened, across 24.5 million channel values; Show Original worst 1;
a synthetic raw worst 4, in values at black level. No value exceeded the tolerance. The
worst differences are in the darkest one-pixel detail, where the bound is loosest.

## Speed and memory (E1, E3, E4; AC9)

Apple M4 Pro (14-core CPU), 24 GB, macOS 27.2, release build, synthetic
6000 × 4000 DNG (`photobench viewport --windows 4976x2892,6000x2892,3024x1800,3872x2592`,
60 frames per case, nothing else running; frames include the GPU and reading the
pixels back). **Reference: the DELL U2723QE (owner, 2026-11-09).** The canvas is
what the loupe's region actually covers at 100%, in pixels, for a maximized
window (film strip as it defaults).

| Canvas (pixels) | Case | mean (ms) | p95 (ms) | Restated R7 (95% under about 160) |
|---|---|---|---|---|
| **4976 × 2892 (14.4 MP), sidebar and inspector showing** | Typical stack, Exposure moves | 135.8 | 139.5 | met |
| | Typical stack, Amount moves | 140.3 | 146.7 | met |
| | Typical stack, Saturation moves | 137.5 | 142.4 | met |
| | Typical stack, Shadows moves | 136.2 | 147.4 | met |
| | Three masks, first mask's Exposure moves (no target) | 266.9 | 288.6 | |
| | Three masks, last mask's Exposure moves (no target) | 266.2 | 279.2 | |
| **6000 × 2892 (17.4 MP, canvas 6016 × 2892, capped by the 6000-wide photo), both hidden** | Typical stack, Exposure moves | 154.6 | 157.4 | met |
| | Typical stack, Amount moves | 154.3 | 157.4 | met |
| | Typical stack, Saturation moves | 154.8 | 159.2 | met |
| | Typical stack, Shadows moves | 150.5 | 152.9 | met |
| | Three masks, first mask's Exposure moves (no target) | 395.4 | 415.6 | |
| | Three masks, last mask's Exposure moves (no target) | 402.0 | 436.1 | |
| 3024 × 1800 (5.4 MP), built-in display, comparison | Typical stack, Exposure moves | 61.1 | 62.4 | |
| | Typical stack, Amount / Saturation / Shadows | 61.1 / 61.1 / 60.0 | 62.4 / 62.5 / 61.4 | |
| | Three masks (first / last moves) | 91.2 / 88.0 | 110.4 / 93.5 | |
| 3872 × 2592 (10.0 MP), comparison | Typical stack, Exposure moves | 91.9 | 93.5 | |
| | Typical stack, Amount / Saturation / Shadows | 92.1 / 92.0 / 89.1 | 93.8 / 94.4 / 90.6 | |
| | Three masks (first / last moves) | 159.9 / 159.2 | 168.8 / 167.2 | |

The original target of 100 ms was missed at both Dell canvases; the owner restated it
(see RI1). The earlier run's 10 MP Exposure p95 of 110 ms was a noisy run; this clean run
is 93.5 ms. Frames stay sharp at every size; they come less often at the Dell's
sizes (about 6 to 7 a second).

- **E1 (corrected).** R7's reference is the owner's Dell (above), framebuffer
  6016 × 3384, looks like 3008 × 1692, visible frame 3008 × 1662 points. Measured
  with `print loupe`/`print viewport` on a scratch bundle with its own identifier,
  a `photobench` library and `--library-root`: maximized window, film strip
  default (136 pt), 100%. Canvas: 2488 × 1446 pt (4976 × 2892 px) with the sidebar
  and inspector showing; 3008 × 1446 pt (6016 × 2892 px, region 6000 wide because
  the photo is 6000 wide) with both hidden. The earlier built-in display figure
  (3024 × 1800) doesn't establish R7; it stays as a comparison row. See "Requirements issues".
- **E3, memory.** The texture is 192 MB for 24 MP (8 bytes a pixel), held only
  while the loupe is at covered zooms and freed on leaving them (`purge`). The
  process's physical footprint during a 5.4 MP run grew from 1.5 GB to 4.4 GB, most
  of it Core Image's and `CIRAWFilter`'s own working memory for a 24 MP decode and
  renders: a full-resolution rendition at 1:1 today pays for the same decode, and
  Core Image holds on to it; 24 MP is the reference (A5).
- **Larger photos.** 54 MP (9000 × 6000, 4 frames per case, while other work ran on
  this Mac, so upper bounds): the texture holds 432 MB, `prepare` 149 ms mean, the
  largest window's typical-stack frames 104–109 ms (p95 118) and 10 MP's 173–181 ms:
  above the 24 MP reference, over the 100 ms mark. The cost is the whole-photo
  work (estimates, the larger source), so a 54 MP raw meets R1/R2's "frames stay
  sharp" but not a 100 ms pace. Noted for the owner, who may rule on larger files;
  R7's reference is 24 MP. A 96 MP photo's texture would be 768 MB (the run was
  stopped: it needed over ten minutes on this Mac).
- **R4's sharp frame.** A new white balance at full resolution (decode, texture,
  first frame): decode 115 ms mean (p95 137), frame 68 ms (p95 80), so about 200 ms
  from a pause to a sharp frame on this file. No machine-learning decode is measured
  here (`ml-denoise/status.md`: about 1.4 s per 24 MP decode; R5 applies).
- **E4.** Today's sharp render after letting go (the whole 24 MP frame through
  `generator.cgImage`, with its pixels read): 656 ms mean, 867 ms p95, the baseline
  the live frame now covers; it is unchanged, the live frame is simply on screen
  until it lands. (`createCGImage` defers the render until the pixels are read, so
  the deferred path in `LiveRenderSession.base` and at the first full rendition
  pays this when the pixels are first read; the region renderer uses `deferred: false`.)

## Acceptance criteria

| # | How checked | State |
|---|---|---|
| AC1 (R1, R12) | `LiveRegionRendererTests`, scene with real one-pixel detail (`pixelGrid`, 6000 × 4000 with `LARGE_RENDER_TESTS=1`, 3000 × 2000 by default; code review C10), typical stack, center and corner, uncropped and cropped-and-straightened, against the same area of the full-resolution render, within `steps`; plus a raw | Done |
| AC2 (R1) | Debug script at 100%, 200%, 800% (`adjust scrub amount …`, `print frames`): every frame from the first sharp one is sharp; at fit, frames are whole-photo frames (`viewport covered no`). Draft tests pass unchanged. `print frames` blocks recorded below | Done |
| AC3 (R2) | Debug script with three masks with Clarity at 100%: `adjust scrub amount`, `print frames`: no soft frame after the first sharp one (8 soft frames before the first sharp one, while the masked stack's whole-sensor decode landed; the masked stack decodes the whole sensor, a new base) | Done |
| AC4 (R3) | Debug script at 100%: slider drags via `adjust scrub` (frame-by-frame), Show Original (`print viewport`: tile shown with the "other values", then `live no` when turned off), the mask overlay (tile "applied overlay", then gone) and a preset hover (`preset preview`, region frames). The curve, wheels, mask handles and brush go through the same `change` path as sliders; only the keyboard, curve, wheel and brush paths remain to a person | Done (the rest manual, `qa.md`) |
| AC5 (R3, R12) | `LiveRegionRendererTests`: Show Original's region vs the identity full render, worst 0 steps | Done |
| AC6 (R4) | Debug script at 100%, each control with no commit (Profile is a menu, so it commits): White Balance (`adjust scrub temperature … hold`): tile off at once, a frame of the applied values sharp 0.35–0.45 s after the last input; Luminance (`adjust scrub luminance-nr … hold`): sharp by 1.2 s; Profile (`adjust look neutral`): full rendition within 1 s. Times from `print viewport` polling | Done |
| AC7 (R5) | Debug script on this Mac (macOS 27, the synthetic DNG is supported): `ml on` at 100%, then `adjust scrub luminance-nr … hold`: the decode applies, the existing machine learning spinner is on (`ml badge … spinner true`) while the wait lasts and the window responds; a tile of the applied values is on screen after the hold. The timing of the final frame and a real raw are for a person (`qa.md`) | Done (final frame timing manual) |
| AC8 (R6) | Debug script, 5 snapshots on a 24 MP DNG: at the start of a change, during a pan (`pan`), during a zoom (`zoomstep`), a pan just after a commit, and settled; a scratch checker counts 64 px blocks of one identical color inside the canvas: 0 blank blocks of 713 in all five. A person still judges soft-looking areas (`qa.md`) | Done |
| AC9 (R7, restated: 95% of frames under about 160 ms for a typical stack on the Dell's two canvases; owner, 2026-11-09, "Accept as measured") | `photobench viewport --windows …`, table above: met, p95 139.5–147.4 ms at 4976 × 2892 and 152.9–159.2 ms at 6000 × 2892. The three-mask rows are recorded with no target | Done |
| AC10 (R8) | Debug script, three masks at 100%: on the Dell, 5576 × 2893 region (sidebar showing, inspector hidden; frames 640–690 ms), rating key `3` and `4` landed while a frame was rendering, and `key right` moved to the next photo; also `key right` at the smaller window earlier (`ml-denoise` AC8's check); the renderer's work is off the main actor (`LiveRegionRenderer` is an actor, CI rendering off main). Manual: no spinning cursor during a real drag | Done (manual part: `qa.md`) |
| AC11 (R9) | Whole-photo frames only ever feed the histogram (`Frame.histogram`), never region frames, by construction; on pause a whole frame renders and the histogram follows it (`print viewport` hist value changes on a pause, and stays the same during a drag). The script's `drag` did not pan the view in this run, so "panning leaves it unchanged" is by construction, not observed; a person can check it (`qa.md`) | Done |
| AC12 (R10, R14) | `GoldenTests` pass unchanged; `PreviewCacheKey.currentPipelineVersion` not changed | Done |
| AC13 (R11) | Debug script: after a drag at 100%, one commit; `undo` restores the previous stack hash (`print adjustments`) | Done |
| AC14 (R13) | Debug script: scrub then `zoom` (fit) at once, `print previews`: `previews hash` equals the saved hash, `memory preview true`, `disk preview true`, `disk thumbnail true`, in the loupe and in the grid after it (stale-preview rule unchanged) | Done |
| M1 (R1, R4, goal) | Owner, on a real 24 MP raw | Manual (`qa.md`) |

**Frame-by-frame (AC2/AC3).** Timeout for a sharp frame: none needed (R6 is a
moment, A8); recorded below. All with `print frames`, one block per scripted drag:
at 100%: the first drag's sharp frames from the first frame on (after the first
render 58 ms mean on a 2200 × 1289 window, p95 106 ms cold first frame), at 200%
and 800% every frame sharp from the first; no soft interactive frame after the first
sharp one in any block. With three masks the first sharp frame arrived after 8 soft
frames in the first drag at 100% (a masked stack decodes the whole sensor, a new
base), and every later block was sharp from its first frame.

**Time to the first sharp frame** (no target, A8, R6, recorded as required): after
a zoom to 100% and a pause, the first drag's first frame was sharp (the texture is
prepared on arrival at 100%). With three masks and the whole-sensor decode, see
above. White balance: about 200 ms after the hold (R4, the decode and first frame
above).

## Design §6 checks

These are for the designer review. Not run by engineering: DR2, DR3, DR5, DR6,
DR7 need a person at the bundled app (hint text and guide: done, see
Strings/guide above).

## Sharpening Map artifact (owner's report, 2026-11-09): existing on `develop`, not this branch's

Reported on a 20 MP Panasonic RW2 on the Dell: a hard-edged, noisier rectangle in
the map at Fit, and "not smooth at all in some cases".

**Not caused by this branch: `develop` has it.** Reproduced on `develop` at
`dfa0d5c` (the branch's base; `fafdec6` is older than the current refiner) and on
this branch, with a copy of the RW2 and the owner's stack in a scratch library: the
same wrong cells on both, at the owner's position (x 0.25–0.5, bottom half) and at
x 0.75–1.0, bottom half. The first refined map after turning the map on is clean;
later refinements, after moving a Sharpening value, show it. A headless repeat of the
refinement gave wrong tiles on 7 of 7 runs after the first. The same stack on the
24 MP synthetic DNG gave 0 of 5, so a test on the synthetic DNG would not catch it.

**Root cause.** `SharpeningMapRefiner.materialize` calls `createCGImage` without
`deferred: false`, so the input it keeps as "rendered once" is a lazy image rather
than pixels. When it is read again, some cells of a 4 × 2 grid come back wrong
(flipped or misplaced). With `deferred: false` on that line: 0 of 7 wrong. The same
change on the output (`RenderEngine.makeCGImage`) alone: still 7 of 7. Why Core Image
does this is not known. `SharpeningMapRefiner` and `RenderEngine` are unchanged here.

**Not fixed here: a separate bug fix is proposed** (the owner decides where it goes). Proposed: `deferred: false` in
`SharpeningMapRefiner.materialize`. It also speeds refinement: at Fit 545 → 62 ms; at
100%, render + first read 7 + 515 → 33 + 90 ms. `LiveRenderSession.materialize` and
`base(for:)` have the same pattern, not tested for this artifact. A regression test
needs a file that triggers it; the synthetic DNG does not.

**Real file, Dell** (mean / p95 ms, sidebar and inspector showing, region 4976 × 2893
at 100%, frame trace, map off):

| Case | Fit | 100% |
|---|---|---|
| Owner's stack, Amount | 49.9 / 59.1 (34 frames) | 92.0 / 103.2 (21 sharp, after 4 soft) |
| Owner's stack, Exposure | 53.2 / 57.4 (33) | 90.8 / 103.2 (20 sharp) |
| Owner's stack, White Balance (soft while moving, R4) | 141.8 / 231.6 (5) | 127.0 / 139.6 (4 soft) |
| AC9's typical stack, Exposure | not run | 149.5 / 156.8 (29); AC9 table 135.8 / 139.5 |
| AC9's typical stack, Amount | not run | 147.6 / 153.1 (29); AC9 table 140.3 / 146.7 |

The owner's stack has no Dehaze, curve or grading, hence the lower times. With the
same stack the RW2 is 5–10% slower than the synthetic DNG at this size.

**Map on (partial).** Measured headlessly on the RW2 with Masking moving; the frame
trace does not record map frames, so Exposure, White Balance and Amount with the map
on were not measured. Estimate frame: 25.7 ms to render + 11 ms first read. Refinement
after a pause: about 0.5 s (545 ms at Fit, off the main thread; at 100%, 7 ms to render
and 515 ms at first read). A sample of the app's main thread at 100% over 7 s and about
five Masking changes shows that first read inside the layer commit: 314 of 4031 samples,
about 0.5 s. That is a likely part of "not smooth" with the map on, and is in `develop`.

## Masking drag at Fit with the map on: this branch against `develop` (2026-11-09)

The owner's answer: "Zoom was to Fit and it was the masking slider where I noticed
it most." R1 and A4 say nothing changes below 100% and the map keeps its shipped
behavior, so a difference here would be a regression.

**Result: no regression.** The branch and `develop` (`dfa0d5c`) measure the same,
within run-to-run variation. Nothing was changed on this branch for it.

Method: the RW2 copy with the owner's stack (Amount 98, Radius 1.4, Detail 52) on the
Dell at Fit (magnification 0.766), sidebar and inspector showing, map on and already
refined. One identical throwaway probe was built into a scratch copy of each tree
(removed since): it recorded map frames shown, refinement starts and finishes, and
main-thread latency from a 4 ms ping. Scripted drags of Masking 15 to 31, 240 steps
at 16 ms, no commit, one build at a time, nothing else running, the owner's app not
running. Mean over the drags (4 per build per pattern, except the 800 ms pattern, 2):

| Pattern | Metric | `develop` | This branch |
|---|---|---|---|
| Steady | Frames per drag | 133.3 | 132.5 |
| | Map frame render, mean / p95 (ms) | 26.4 / 31.4 | 26.5 / 31.2 |
| | Interval between frames, mean / p95 (ms) | 30.2 / 34.7 | 30.5 / 34.9 |
| | Largest interval (ms) | 35.6–49.8 | 36.0–49.0 |
| | Main-thread latency, largest (ms) | 16.6–45.8 | 20.6–37.1 |
| | Stalls over 50 ms | 0 | 0 |
| Pause 220 ms every 40 steps | Frames per drag | 121.0 | 117.8 |
| | Map frame render, mean / p95 (ms) | 31.7 / 40.7 | 32.8 / 40.0 |
| | Interval p95 (ms) | 55.6 | 59.0 |
| | Refinements started / finished / shown, per drag | 6 / 4–5 / 0 | 6 / 5 / 0 |
| | Main-thread latency, largest (ms) | 17.7–53.6 | 24.4–52.2 |
| | Drags with a stall over 50 ms | 1 of 4 | 2 of 4 |
| Pause 800 ms every 40 steps | Frames per drag | 135.0 | 143.5 |
| | Refinements started / shown, per drag | 6 / 5 | 6 / 6 |
| | Main-thread latency, largest (ms) | 19.4–31.2 | 15.0–21.1 |

The three patterns' differences go both ways, and each build's own runs differ by as much.

**Existing behavior and its likely cause** (also on `develop`):
- Frames keep up at about 30 ms while the value moves steadily, with no main-thread
  stall over 50 ms. Where it gets rough is when the hand hesitates.
- Every pause of 150 ms or more starts the full-resolution refinement: 6 starts in a
  5.4 s drag with 220 ms pauses, none of which reached the screen. While refinements
  run, the estimate frames slow by about 25% (render 26 → 32 ms; interval p95 35 → 50–70
  ms). The estimate and the refinement share the two interactive render contexts,
  which is the likely reason (by code, not separately measured).
- With longer pauses the refined map lands (5–6 times a drag) and replaces the estimate,
  so the picture changes each time; the two are computed differently by design
  (`sharpen-mask-preview` R6). Those refined frames are where the wrong-tile artifact
  above appears, after the first refinement. So the roughness and the rectangle share
  the refinement path, but they are different effects: restarts and estimate-to-refined
  swaps for the first, the deferred input for the second. Whether the swap is what
  the owner felt is an inference; I can't see the screen.

## Review findings (`code-review.md`, `review.md`)

"Script" means the reviewers' sequences on a bundle copy with its own identifier and a scratch library:
each was run on the code before and after the fixes, with the before result noted.

| # | Finding | Fix | Check (before → after) |
|---|---|---|---|
| C1 | Photo's tile covers the maps | The editor drops `regionFrame` when a whole frame stands in for a region (a map, the replaced slot); the loupe has one tile rule | Script: map on at 100%: `tile shown` → `tile none` |
| C2/F1 | Raw WB, Profile, NR freeze on a stale tile | Same drop, when a moving frame can't be a region frame; the whole-frame guard no longer returns early (`wholeFrameGoesOnBase`) | Script: WB drag at the end of the drag: `tile shown` → `tile none`, sharp after the hold; unit test |
| C3 | Overlay doesn't follow the selected mask | `Frame.overlayMask` (the id), compared by `LiveFrameRules.isCurrent` in both checks | Script: select the other mask: `frames 0` → a new sharp frame; unit test (a mask's id on the frame, two masks differ) |
| C4 | Highlights < 0, Exposure crossing 0, first mask, drags after Show Original stay soft | `shouldDecode(whileMoving:)`: a moving frame starts one decode once its settings have stopped changing; R4's controls change every frame so still wait for the pause. Show Original off prepares the saved settings. R4 is not widened | Script: Highlights from 0: 1 sharp of 34 → 22 of 29, none soft after the first sharp; Exposure crossing 0: 20 soft after the first sharp → 6 (the crossing's decode, R6); drag after Show Original: 1 of 10 sharp → 19 of 20 from the first frame; first mask: unchanged (already sharp here). Unit test |
| F2/C7 | Spinner when nothing changed | `sharpFrameWaitApplies` needs a change under way (`showsLive` or the wait for a full rendition); `noteInput` in `catalogChanged`; refresh when the wait turns on | Script: arriving at a photo at 100%: `spinner yes` on the unfixed bundle → none; `Z` from fit showed none on both in this run |
| C5/F3 | Maps lost nearest-neighbor | Nearest-neighbor at 1 and above for maps and the replaced slot's preview (`usesNearestFiltering`) | Script: map at 400%: `nearest true`; unit test |
| C6 | Tile returns over the HDR rendition | The tile stays only while a full rendition is awaited | Script: after the full rendition, a rating key: `tile shown` → `tile none` (an SDR photo; an HDR photo was not run) |
| C8 | A previous save's rendition hides the tile | Every live revision cancels the loads and sets `rendition = .live`, as on `develop`, so a late rendition is ignored | By construction; timing not scriptable |
| C9 | A draft whole frame could seed the cached preview | `wholeFrameIsInteractive`: the short-circuit and `seedPreviewIfRendered` need a whole frame that isn't a draft | By construction; window too narrow to script |
| C10 | AC1 scene had no one-pixel detail | `pixelGrid` scene | Test results above |
| C11 | AC6, AC8, AC14 not checked | Now run and verified (rows above) | Rows above |
| C12/F4 | HDR badge during a tile-only drag | Cleared on any live revision | M10 (HDR, a person) |
| C13 | Comments and docs | `prepare`'s doc; `notReady` re-requests the frame; PROFILING's table; `typicalGain` now derived fully | Reading |
| F5 | (a) spinner after a too-large photo, (b) overlay ignored, (c) wait never cleared | (a) needs `regionRenderer`, (b) `isCurrent`, (c) cleared where no load starts or it fails | By construction |

The design question (mask handles over the tile): settled from layer order, `print viewport` shows
`layers tile,view`, the tile first, so the mask view's layer is above it. On screen it remains a manual check.

## Open questions and notes

**Requirements issues** (for the owner, via the product manager).

- **RI1: R7 on the reference display. Ruled by the owner, 2026-11-09: "Accept as measured".**
  R7/AC9 is restated to 95% of frames under about 160 ms for a typical stack on the Dell's
  two canvases, and that is met; the measurements and options stay for the record. The reference is the
  Dell (owner, 2026-11-09). At both real canvases, 95% of frames are not under
  100 ms: p95 139.5 ms (14.4 MP, sidebar and inspector showing) and 157.4 ms
  (17.4 MP, both hidden). Frames stay sharp (ruling 1), they just come at 6 to 7 a second.
  Nothing was changed; the options offered, measured (throwaway experiments, removed;
  30-frame runs, so "Today" differs a little from the 60-frame table above),
  mean / p95 for a typical-stack Exposure drag at 14.4 / 17.4 MP:

  | Option | 14.4 MP (ms) | 17.4 MP (ms) | Gets there? | Cost |
  |---|---|---|---|---|
  | Today | 138 / 142 | 153 / 157 | no | |
  | A. Frames rendered into a GPU surface (an `IOSurface` on the layer), no `CGImage` | 112 / 113 | 130 / 135 | **not alone** (−22 to −26 ms; the region's readback and the CGImage copy) | The layer takes an IOSurface (color space tag, debug `snapshot` won't see it) |
  | B. Region stage cache | Amount-like controls about 31–40 ms (bound: "Sharpening alone", measured) | same | **not for Exposure**: it only speeds controls after the estimates (Amount, Radius, Detail, tone curve, color...). Exposure, Highlights, Shadows and Dehaze change the estimates' input each frame, so AC9's case is unchanged | Cache and invalidation logic, more texture memory |
  | C. Whole-photo estimates (local tone, dehaze) from a reduced copy during a drag (1500 px proxy) | 94 / 104 | 105 / 108 | close alone, **not quite** | R12 weakens: mid-drag frames differ from the final render by up to 5 steps (mean 0.06, 0.001% of channel values over 2 steps) on the synthetic scene, unmeasured on harder content; R12/A1 would need the owner's ruling for mid-drag frames (exact on pause and commit, as today) |
  | **A + C together** | **72 / 75** | **81 / 85** | **yes, at both sizes** | A's and C's costs together |
  | D. Accept: 95% of frames under about 160 ms at these canvases (R7 restated for the Dell) | as measured | as measured | n/a | None to build; 6 to 7 frames a second at the largest window |
  | E. Sharp only a central ~10 MP while dragging (the 10 MP row: 92 / 94 ms) | ~92 / 94 | ~92 / 94 | yes, for the speed | Violates R1 at the edges; needs a ruling |

  Only A + C (or restating the target) reach the Dell; no single option does at the
  largest canvas. The owner chose D.

- **RI2: photos above 24 MP (E3). Noted, no ruling.** See "Larger photos" above: at 54 MP frames exceed
  100 ms even in the smaller windows, and the texture is 432 MB. R7's reference is
  24 MP; the owner may want a ruling on larger files.

**Follow-up for Ship.** If 100% feels slow on the Dell, faster region frames (A + C), which needs a ruling on A1/R12 for mid-drag frames.

**Design questions.** None.

**Noted, not fixed (out of scope):**
- `LiveRenderSession.base(for:)`, `materialize` and the 1:1 full rendition use
  `createCGImage` without `deferred: false`, which defers the pixels; the half-float
  base at 2560 px is therefore lazy and re-decoded on demand, and a 1:1 rendition
  is rendered at first read (`DecodedImage(cgImage:)`, a layer's first draw) rather
  than where it was produced. Worth its own bug and measurement, separately.

## README

No change to requirements, build commands or repository layout.
