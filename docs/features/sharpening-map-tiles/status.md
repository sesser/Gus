# Sharpening map tiles: implementation status

Owner: swift-macos-engineer. Bug fix (no `prd.md` or `design.md`). Branch
`bug/sharpening-map-tiles`, cut from `develop` at `dfa0d5c`.

**Status: Done.** Code review round 1 (C1–C5) is addressed below. Next, at the
owner's direction for this branch: a second code-review pass, then QA, then a
product manager review, then the owner's checks. The UI did not change, so no
design review.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

### Steps to reproduce

On a real 20 MP camera raw (`P1040037.RW2`, 5472 × 3648, Panasonic, no camera
crop), with Sharpening Amount 98, Radius 1.4, Detail 52, Masking near 23, no
other edits:

1. Show the Sharpening Map at Fit.
2. Wait for the refinement after the pause.
3. Move Masking and wait for the next one.

Headless, on the unfixed code: `SharpeningMapRawFileTests` below (no
full-resolution render of the file earlier in the process; see the order
dependence). The loupe's order also reproduces it headlessly (Reproduction
counts, the reviewer's numbers).

### Expected

Every refinement is the map computed directly from the full-resolution master
(R6 of `sharpen-mask-preview`), apart from the half-float rounding of the kept
input.

### Actual

Some cells of a 4 × 2 grid of the map come back wrong and visibly noisier. In
the headless runs the wrong cells are column 2 of 4 (x 0.25–0.5) in the bottom
half and column 4 of 4 (x 0.75–1.0) in either half; the owner saw the bottom
half. Worst difference 255 of 255. A wrong cell can be flipped or misplaced.
The first refinement is often wrong too (below), which differs from the
original report.

### Root cause

`SharpeningMapRefiner.materialize` (`SharpeningMapRefiner.swift:127` at
`dfa0d5c`) called `createCGImage(_:from:format:colorSpace:)` without
`deferred:`. The image it kept as "rendered once" was therefore lazy on files
this size, and when the mask graph read that lazy image it got wrong cells.

**Known (measured on macOS 27.2 with a counting `CIImageProvider` or on the
real file):**

- The short overload is not always deferred. The header doesn't say when it
  renders. It renders at once when both sides are at most 4096 and defers when
  either is larger (4096 × 8 and 4096 × 4096 at once; 4097 × 8, 8 × 4097,
  4097 × 3072 deferred). Area doesn't matter for this step.
- `CIImage(cgImage:)` of a deferred image reads it at once up to at least
  8192 × 2048 (16.8 MP). At 5472 × 3648 (20 MP) it stays lazy: the first read
  pulled its source 24 times, a second read 0 more. The reviewer's probes put
  the limit for RGBAh between 16.8 and 17.5 MP: 5120 × 3413 stays lazy (0 pulls
  at create, 0 when wrapped, 20 on read), and 4928 × 3264 (16.1 MP) is deferred
  at create but read when wrapped.
- So on this file the kept input stays lazy until the mask graph reads it.
  The refiner's inputs below these sizes were never lazy, which is why smaller
  files can't show this.
- The fault needs that read. Against an eager render, the lazy image's own
  pixels are right read whole (data provider, and a whole-frame
  `CIImage(cgImage:)` render; 5 of 5 processes, 3 of them cold, every 4th
  pixel each way) and read one 4 × 2 cell at a time (8 cells, 3 of 3 cold
  processes).
- `deferred: false` on that one render: 0 wrong (table below). The same change
  on the output only (`RenderEngine.makeCGImage`): 17 of 21 kept refinements
  still wrong. Reading the lazy image's pixels right after creating it: 20 of
  21 still wrong.
- Order matters, in one specific way. One direct, full-resolution render of
  the file earlier in the process hides the fault for the rest of it (0 of 7,
  and 0 of 21 with 6 direct renders first), so the test's reference is rendered
  last. The loupe's order does not hide it (Reproduction counts).
- A synthetic 24 MP DNG did not trigger it in the earlier report. It was not
  re-run here; laziness is necessary but evidently not sufficient.

**Not known:** why Core Image returns wrong cells when the mask graph reads a
lazy image. Core Image is closed source, and the tile pulls and the 4 × 2 grid
are only suggestive. Nothing here identifies the component at fault (`CIRAWFilter`,
tiling, resource reuse) and no theory of it was tested.

### Test that fails without the fix

- `SharpeningMapSessionTests.keptInputIsRendered` (normal suite).
- `SharpeningMapRawFileTests.refinedMapsMatchRenderedPixels` (needs the file).

Failure output and how each was shown to fail are under "Regression checks".

## Fix

`deferred: false` on the render in `SharpeningMapRefiner.materialize`, so what
is kept is pixels, with a comment saying why. `materialize` is now `internal`,
like `holdsInput`, for the test. No `PreviewCacheKey.currentPipelineVersion`
bump and no golden touched: the map is a view that is never saved.

## Reproduction counts

All on `P1040037.RW2` at Fit (2560 long edge), each process cold, 7 runs per
process. A run is a refiner's first refinement (Masking 23), one from its kept
input (30), and a first refinement of another refiner (30). "Wrong" means more
pixels than `allowedSteps` allows differ from the direct map rendered last in
the process.

| Code | Kept input wrong | First wrong | Other refiner's first wrong |
| --- | --- | --- | --- |
| Unfixed, first session (3 processes) | 18 of 21 | 18 of 21 | 18 of 21 |
| Unfixed, second session (3 processes) | 21 of 21 | 21 of 21 | 18 of 21 |
| Unfixed, one direct render first (1 process) | 0 of 7 | 0 of 7 | 0 of 7 |
| `deferred: false` (3 processes) | 0 of 21 | 0 of 21 | 0 of 21 |
| Unfixed, eager output only (3 processes) | 17 of 21 | 16 of 21 | 15 of 21 |
| Unfixed, immediate read (3 processes) | 20 of 21 | 19 of 21 | 19 of 21 |

In those rows "wrong" means the comparison with the direct map at the
`allowedSteps` tolerance, which C1 showed has no margin on this file. The
classification isn't in doubt: the wrong runs that were printed have a worst of
255, and clean runs a worst of 5 (Masking 23) or 3 (Masking 30).

At 100% (3 runs in one process): unfixed, kept input wrong 1 of 3, first and
other refiner 0 of 3; `deferred: false`, 0 of 3 for all.

**The reviewer's numbers** (cold processes, `code-review.md`):

- At 100%: unfixed, 25 of 30 refinements wrong (9, 9 and 7 of 10 per process);
  fixed, 0 of 30. My 1 of 3 above undercounts it.
- The loupe's order (session photo and map frames first, then the refiner, the
  direct map last): unfixed, 28 of 30; fixed, 0 of 20. So the hiding under Root
  cause is specific to a full-resolution direct render, and the order the owner
  used does show the fault.

The task's suggested oracle, a kept refinement against a fresh refiner's first
one, flagged 24 of 42 unfixed runs: a first refinement can be the wrong image,
or both can be wrong in the same cell. The direct map rendered last is what
the test uses instead. It also needs no knowledge of the tile positions.

The plain stack reproduced it; nothing else was needed.

## Timings

`P1040037.RW2`, `RenderEngine.interactive()`, debug build, first read included.
Medians in ms: a fill over iterations 2–5 of 5 (iteration 1 is cold-process,
listed separately), a kept refinement over all 10 of them.

| | Fit, fill | Fit, kept input | 100%, fill | 100%, kept input |
| --- | --- | --- | --- | --- |
| Before | 232 | 42 | 244 (render 28 + read 216) | 51 (render 3.6 + read 47.4) |
| After | 206 | 32 | 202 (render 140 + read 60) | 40 (render 3.5 + read 36.5) |

Cold-process iteration 1, before → after: Fit fill 362 → 269; 100% fill
351 → 272.

Faster, but much less than the earlier report (Fit 545 → 62 ms; 100%
7 + 515 → 33 + 90 ms); that report's conditions aren't known. At 100% the
cost moves from the output's first read into the fill, so a fill no longer
hides its cost in the read; at Fit the output is small enough to render when
created either way.

`LARGE_RENDER_TESTS=1 swift test --filter LargeSharpeningMapTests` passes with
the fix on the synthetic 24 MP DNG (refined whole 0.045–0.078 s).

## Cancellation

The doc on `render` says it is cancellable before and after the expensive
stage, and that an input rendered before a cancellation is kept.
Unchanged by the fix: the fill still assigns `input` before the check, so the
eager render only makes the stage's cost real.

- Checked with a temporary line cancelling the token right after the fill, on
  the real file: the call threw `CancellationError`, the input was held, the
  next refinement had `filledCache` false and matched the direct map (worst 3,
  allowed 4). With the lazy render the same flow still gave wrong cells (worst 255).
  The temporary line is gone.
- New test `cancelledRefinementKeepsTheInput` (normal suite) pins the contract
  for a request cancelled before it starts: the input stays and the next
  request reuses it. It passes with and without the fix; it is a guard, not a
  regression test. Its mid-fill counterpart needs a test-only hook in
  production code, so the mid-fill check stays the one-off above.

## Regression checks

Both, as the task asked. Chosen because the artifact needs a real file while
the mechanism doesn't.

1. **`keptInputIsRendered`** (normal suite, deterministic, no file). A
   `CIImage` from a counting `CIImageProvider` goes through `materialize`:
   the provider must have been called before it returns and not again on two
   reads of the result. The image is 5472 × 3648, the real file's size, on
   purpose: Core Image defers only above the limits listed under Root cause,
   and an earlier 64 × 64 version passed with or without the fix. It pins the
   mechanism, not the symptom. Its limits are measured, not documented, so it
   now carries a control (C2): the same image through the call `materialize`
   used before the fix must still be asked for nothing. If a later macOS
   stops deferring it, the test fails, names the macOS version and says it
   needs revisiting, instead of passing without testing anything.
2. **`SharpeningMapRawFileTests`** (needs `CAMERA_RAW_SAMPLE`, run alone). The
   symptom on the real file: 5 runs of first, kept and other-refiner
   refinements, each required to equal, pixel for pixel, the same mask graph
   over the same input rendered eagerly in the test, last. See "The direct-map
   tolerance" for why it no longer compares with the direct map. It reuses
   `CAMERA_RAW_SAMPLE` rather than adding a variable: it accepts any raw, so a
   cropped sample that `CameraRAWMaskTests` needs works too, and the setting is
   already in `.claude/settings.json`. A file that doesn't trigger the fault
   passes and shows nothing. `CameraRAWMaskTests` needs a file with a camera
   crop, which this one lacks (`CameraFrame.rect` is nil), so use `--filter`.

**Shown failing without the fix** (only `deferred: false` removed, `internal`
kept; restored afterwards, hash matched):

- `keptInputIsRendered`: 2 issues, `Expectation failed: pulled > 0`, then
  `Expectation failed: provider.calls.withLock { $0 } == pulled`. The control
  passes: Core Image still defers this image on macOS 27.2, so the failure is
  the one the test states.
- `refinedMapsMatchRenderedPixels`, 3 cold processes: 15, 12 and 13 of 15
  comparisons failed, for example `run 1, first: worst 255 against the same
  pixels` and `run 1, kept input: worst 255 against the same pixels`.

**The control fires when its premise goes** (temporary, fix on, then restored
with a matching hash): at 4096 × 3072, where `keptInputIsRendered` would
otherwise pass with or without the fix, the test fails with 1 issue:
`Core Image no longer defers this image on Version 27.2 (Build 26B123): this
test can't detect a lazy input here and needs revisiting (see its comment)`.

With the fix: `keptInputIsRendered` passes; `refinedMapsMatchRenderedPixels`
passes in 7 of 7 cold processes (4 before and 3 after the last test-file edit,
which changed only the control's message), with a worst of 0 in every
comparison.

## The direct-map tolerance (code review C1)

The first version of the gated test compared each refinement with the direct
map, at `allowedSteps(roundings: 1, upstream: 1, ...)`. On this file that had no
margin: Masking 23 was worst 5, allowed 5, and my "a file that doesn't trigger
the fault can only pass" was wrong.

**The reviewer's numbers** (with the fix, no fault, the same refiner and
formula): Masking 5, worst 29, allowed 22 (1260 components over); Masking 10,
18, allowed 15 (543 over); Masking 15, 9, allowed 9; Masking 20, 6, allowed 6.

**What I measured looking for the missing term** (real file, temporary probes,
at Fit and at 1:1):

- A float32 render of the input is bit-identical to the direct graph (worst 0
  in all 24 measurements, in both working formats), so the whole difference
  comes from the input's half-float step.
- That step is not a nearest rounding. Against float32 pixels the half-float
  write truncates: of 59,885,568 components, 59,878,294 are below the float32
  value, 10 above, 7,264 equal; mean error −0.9997 half-steps; worst 1.9998
  half-steps (one full step), in both working formats. So one "rounding" is up
  to 2⁻¹⁰ relative, not the 2⁻¹¹ the formula assumes: a real error in the
  model.
- It does not close the gap. Truncation is one-sided, so `high` and `low` errors
  can't add. Through the encoding, one rounding can move the range by at most
  3.2 × 10⁻⁴ (measured 3.215 × 10⁻⁴ at v ≈ 0.5, the sRGB slope at 0.5 times one
  step). That gives 16.4 steps at Masking 5 and 2.97 at 23; measured, 29 and 5.
- A further half-float pass in the encoded domain would fit those numbers (one
  encoded step is 4.5 steps at Masking 23), but a float32 working format doesn't
  make the gap go away (38 against 29 at Masking 5), so I can't confirm it from
  outside Core Image.

**Why the model is too small remains unexplained**, and I have not derived a
per-pixel bound that holds, so I did not adjust the number. What is known is
that truncation accounts for at least part of it.

**What the test measures now**, and why: the bug is whole cells of wrong
content, not rounding, so the test compares the refinement with the same graph
over the same pixels (an eager render of the same input). Both sides then have
the same half-float image, so rounding isn't part of the comparison: the fixed
result was `worst == 0` in every comparison across 7 cold processes, and the
fault is worst 255. No tolerance to derive. The cost is that this test no longer
checks refined against direct on a real file; `refinedIsFullResolution` still
does on a synthetic image, with the formula above (see Follow-ups).

## `LiveRenderSession`

`LiveRenderSession.materialize` and `base(for:)` use the same overload, but no
defect was reproduced, so they are unchanged. Against direct references
rendered last, cold processes, 3 runs each (photo and map frames, plus the
stage path with masks moved):

| Case | Base size | Frames wrong |
| --- | --- | --- |
| Default long edge 2560, plain and masked stacks (3 processes) | long edge 2560 | 0 of 54 |
| Crop to 50%, decoded at 5120 (3 processes) | 5120 long edge, 17.5 MP; lazy (reviewer's probe: 0 pulls at create, 0 when wrapped, 20 on read) | 0 of 36 |
| Masks, crop to 50%: the stage cache `materialize` at base size (2 processes) | as above | 0 of 24 |
| Plain and masked, crop to 40%: native 20 MP decode (2 processes) | 5472 × 3648 | 0 of 36 |

At sizes up to 4096 on a side the short overload isn't lazy at all, so the
usual path there is already eager. **Follow-up:** if the fault ever shows there
(a crop that decodes a large base), the same one-word change applies; not made
now because nothing reproduced it.

## Build and test

- Baseline at `dfa0d5c`: `swift build` clean. `swift test`: **634 tests in 108
  suites passed**, 1 known issue (`LiveSessionTests`, "Values above white
  survive the cached stages", pre-existing `withKnownIssue`). One pre-existing
  warning: `SmartAlbumTests.swift:165` (unused result).
- Latest (after round 1 of code review): `swift build` clean. `swift test`:
  **637 tests in 109 suites passed**, 1 known issue (the same), no new
  warnings. No golden moved; `UPDATE_GOLDENS` was not run.
- `CAMERA_RAW_SAMPLE=.../P1040037.RW2 swift test --filter SharpeningMapRawFileTests`:
  1 test, passes, 3 of 3 cold processes on the final tree.
- No linter or formatter is configured in the repository.

## Bug checks

| # | Item | How checked | State |
| --- | --- | --- | --- |
| 1 | Wrong cells reproduced on the real file | Harness and `SharpeningMapRawFileTests` on unfixed code (39 of 42 cold kept runs) | Done |
| 2 | Fix | `deferred: false` in `materialize`; evidence above | Done |
| 3 | Timing | Table above | Done |
| 4 | Cancellation | One-off mid-fill check; `cancelledRefinementKeepsTheInput` | Done |
| 5 | Regression tests shown failing without the fix | `keptInputIsRendered`, `refinedMapsMatchRenderedPixels` | Done |
| 6 | `LiveRenderSession` | 150 frames tried, 0 wrong; follow-up recorded | Done |
| 7 | `docs/USER_GUIDE.md` | Unchanged: it describes the map and its refinement; correct cells restore what it already says | Done |

## For QA (in the bundled app)

Not run by engineering. Use a copy of the bundle with its own bundle
identifier and a scratch library, importing only a scratch copy of the RAW (an
in-place import can write a sidecar beside the file, so never the owner's
original), and pass `--library-root` on every launch.

1. Open the RW2 in the loupe, set Sharpening Amount 98, Radius 1.4, Detail 52,
   Masking 23, and show the Sharpening Map at Fit. Wait for each refinement
   and look for a rectangular cell that is flipped, misplaced or noisier than
   its surroundings.
2. Move Masking several times and repeat. Also at 100%.
3. Cancel a refinement by moving a slider while the spinner shows; the next
   refinement must still be correct.

The app itself was not run. Its order (live frames first, then the refiner)
was reproduced headlessly by the reviewer (Reproduction counts): unfixed 28 of
30, fixed 0 of 20.

## Follow-ups

1. **Proposed roadmap Idea: full-size renders reach the screen unrendered.**
   At 100% the loupe and the sharpening map show an image Core Image hasn't
   rendered yet. `RenderEngine.makeCGImage` uses the short `createCGImage`, which
   defers an image with a side over 4096, and nothing reads the result before
   the loupe hands it to the layer. The render then runs at the first read, which
   `CLAUDE.md` says belongs off the main thread ("Images are fully decoded…
   before they reach layers"). This corrects my earlier note that such outputs
   "aren't kept and read again": at 100% the frame is kept and read by the layer.
   Changing the output alone did not change this bug, and it isn't changed here:
   it predates this branch.
   - Reviewer's evidence (`code-review.md` C3): BGRA8 at 5472 × 3648 through
     the short overload makes 0 pulls when created; `longEdge: nil` gives that
     size (`RenderEngine.swift:103`, reached from `SharpeningMapRefiner.swift:79,107`
     and shown at `LoupeView.swift:414,1054`); nothing reads it between
     `makeCGImage` and `layer?.contents = image`. `PreviewService.fullResolutionImage`
     (`PreviewService.swift:236`) takes the same path, and its header (`:39`)
     says returned images are fully decoded.
   - Cost if it runs on the main thread: the render's time at each new frame
     (first read 36.5 to 60 ms in the 100% rows of Timings).
   - **Not confirmed:** which thread does the first read; that needs the app.
   - No wrong pixels from it: 0 of 30 at 100% with the fix (the reviewer's count).
2. **`allowedSteps` is too small for real files** (`SharpeningMapSessionTests.swift`).
   It assumes a half-float rounding of 2⁻¹¹ relative, but the write truncates (up
   to 2⁻¹⁰), and that does not explain the whole gap (see "The direct-map
   tolerance"). `refinedIsFullResolution` and `cachedMapMatchesWhole` use it on a
   synthetic image and pass, so it is left unchanged here: loosening it for tests
   that aren't failing isn't this branch's job.
3. **`LiveRenderSession`:** see above; the same one-word change would apply if
   the fault ever shows there.

## Code review, round 1 (`code-review.md`)

| # | Finding | Outcome |
| --- | --- | --- |
| C1 | The gated test's tolerance has no margin; "can only pass" is wrong | **Changed what the test measures**: same graph over the same pixels, `worst == 0` (7 cold processes), the fault 255. False claim corrected in the suite's comment and here. Masking 23 recorded (worst 5, allowed 5), with the reviewer's other numbers. Missing term looked for: the half-float write truncates, which is a real error in the model, but why the model is too small is not fully explained, so no bound was derived or adjusted ("The direct-map tolerance"). |
| C2 | `keptInputIsRendered` can go blind silently | **Control added**: the same image through the old call must still be asked for nothing; otherwise the test fails, names the macOS version and says it needs revisiting. Comment beside the test says so. Still fails without the fix for its stated reason (2 issues, control passing); control shown firing at 4096 × 3072. |
| C3 | "Aren't kept and read again" is wrong at 100% | **Note corrected** and recorded as Follow-up 1, worded for the product manager as a roadmap Idea, with the reviewer's evidence and the thread unconfirmed. `RenderEngine.makeCGImage` not changed. |
| C4 | `materialize` comment gives the `createCGImage` limit only | **Fixed**: both limits named (a side over 4096 at create, about 17 MP when wrapped). |
| C5 | Three places say less than the measurements show | **Fixed**: the 5120 row (it did test a lazy base); 100% counts (25 of 30, 0 of 30); the loupe's order (28 of 30, 0 of 20) and the "hides the fault" wording. All marked as the reviewer's numbers. |

## Open questions

None. No design questions; no requirements issues.

## README

No change: requirements, build commands and repository layout are unchanged.
