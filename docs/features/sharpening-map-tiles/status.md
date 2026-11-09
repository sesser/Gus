# Sharpening map tiles: implementation status

Owner: swift-macos-engineer. Bug fix (no `prd.md` or `design.md`). Branch
`bug/sharpening-map-tiles`, cut from `develop` at `dfa0d5c`.

**Status: Done.** Ready for review (code-reviewer, then qa-tester). The UI
did not change, so no design review.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

### Steps to reproduce

On a real 20 MP camera raw (`P1040037.RW2`, 5472 × 3648, Panasonic, no camera
crop), with Sharpening Amount 98, Radius 1.4, Detail 52, Masking near 23, no
other edits:

1. Show the Sharpening Map at Fit.
2. Wait for the refinement after the pause.
3. Move Masking and wait for the next one.

Headless, on the unfixed code: `SharpeningMapRawFileTests` below (no other
render of the file earlier in the process; see the order dependence).

### Expected

Every refinement is the map computed directly from the full-resolution master
(R6 of `sharpen-mask-preview`), within the half-float rounding the existing
tests allow.

### Actual

Some cells of a 4 × 2 grid of the map come back wrong and visibly noisier. In
the headless runs the wrong cells are column 2 of 4 (x 0.25–0.5) in the bottom
half and column 4 of 4 (x 0.75–1.0) in either half; the owner saw the bottom
half. Worst difference 255 of 255. A wrong cell can be flipped or misplaced. The first refinement is
often wrong too (below), which differs from the original report.

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
  pulled its source 24 times, a second read 0 more.
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
- Order matters. One direct render of the file earlier in the process hides
  the fault for the rest of it (0 of 7, and 0 of 21 with 6 direct renders
  first), so the test's reference is rendered last.
- A synthetic 24 MP DNG did not trigger it in the earlier report. It was not
  re-run here; laziness is necessary but evidently not sufficient.

**Not known:** why Core Image returns wrong cells when the mask graph reads a
lazy image. Core Image is closed source, and the tile pulls and the 4 × 2 grid
are only suggestive. Nothing here identifies the component at fault (`CIRAWFilter`,
tiling, resource reuse) and no theory of it was tested.

### Test that fails without the fix

- `SharpeningMapSessionTests.keptInputIsRendered` (normal suite).
- `SharpeningMapRawFileTests.refinedMapsMatchTheDirectMap` (needs the file).

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

At 100% (3 runs in one process): unfixed, kept input wrong 1 of 3, first and
other refiner 0 of 3; `deferred: false`, 0 of 3 for all.

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
   mechanism, not the symptom, and its limits are measured, not documented: if
   Core Image stopped deferring at this size it would pass either way.
2. **`SharpeningMapRawFileTests`** (needs `CAMERA_RAW_SAMPLE`, run alone). The
   symptom on the real file: 5 runs of first, kept and other-refiner
   refinements against the direct map rendered last, with the tolerance the
   existing refinement test derives (one more half-float rounding, no
   upstream gain). It reuses `CAMERA_RAW_SAMPLE` rather than adding a variable:
   it accepts any raw, so a cropped sample that `CameraRAWMaskTests` needs works
   too, and the setting is already in `.claude/settings.json`. A file that
   doesn't trigger the fault can only pass. `CameraRAWMaskTests` needs a file
   with a camera crop, which this one lacks (`CameraFrame.rect` is nil), so use
   `--filter`.

**Shown failing without the fix** (only `deferred: false` removed, `internal`
kept; restored afterwards with an identical hash, and only the comment changed
after that):

- `keptInputIsRendered`: 2 issues, `pulled > 0` failed, then
  `provider.calls.withLock { $0 } == pulled` failed.
- `refinedMapsMatchTheDirectMap`, 2 processes: `Expectation failed:
  difference.worst <= allowed`, for example `run 1, kept input: worst 255,
  allowed 4` and `run 1, first: worst 255, allowed 5` (first and other-refiner
  refinements of several runs failed too).

With the fix: `keptInputIsRendered` passes; `refinedMapsMatchTheDirectMap`
passes in 3 of 3 cold processes.

## `LiveRenderSession`

`LiveRenderSession.materialize` and `base(for:)` use the same overload, but no
defect was reproduced, so they are unchanged. Against direct references
rendered last, cold processes, 3 runs each (photo and map frames, plus the
stage path with masks moved):

| Case | Base size | Frames wrong |
| --- | --- | --- |
| Default long edge 2560, plain and masked stacks (3 processes) | long edge 2560 | 0 of 54 |
| Crop to 50%, decoded at 5120 (3 processes) | 5120 long edge; deferred at create, 17.5 MP (between the measured wrap limits) | 0 of 36 |
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
- Latest: `swift build` clean. `swift test`: **637 tests in 109 suites passed**,
  1 known issue (the same). Warnings: only the pre-existing one. No golden
  moved; `UPDATE_GOLDENS` was not run.
- `CAMERA_RAW_SAMPLE=.../P1040037.RW2 swift test --filter SharpeningMapRawFileTests`:
  1 test, passes, 3 of 3 processes.
- No linter or formatter is configured in the repository.

## Bug checks

| # | Item | How checked | State |
| --- | --- | --- | --- |
| 1 | Wrong cells reproduced on the real file | Harness and `SharpeningMapRawFileTests` on unfixed code (39 of 42 cold kept runs) | Done |
| 2 | Fix | `deferred: false` in `materialize`; evidence above | Done |
| 3 | Timing | Table above | Done |
| 4 | Cancellation | One-off mid-fill check; `cancelledRefinementKeepsTheInput` | Done |
| 5 | Regression tests shown failing without the fix | `keptInputIsRendered`, `SharpeningMapRawFileTests` | Done |
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

The order the app uses (live frames first, then the refiner) was not run
headlessly; the owner's report came from it.

## Notes (not fixed here)

- The short `createCGImage` overload is used elsewhere for outputs, for
  example `RenderEngine.makeCGImage`. Those aren't kept and read again, and
  changing the output alone did not change the bug.

## Open questions

None. No design questions; no requirements issues.

## README

No change: requirements, build commands and repository layout are unchanged.
