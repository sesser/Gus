# Full render main thread stall: code review

Owner: code-reviewer. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/pre-hdr-merge-fixes`, commit `23c71f4` (#65) on top of `476d6a9`
(#73, reviewed in `docs/features/dehaze-above-white/code-review.md`), base
`1ef945a`. Build and tests: `swift build` clean. I ran the full `swift test`
(1040 tests, 155 suites) five times: three passed, and two failed in
`DeferredRenderTests.matchesCoreAnimationsRender` ("484 rows differ"). The
suite passed alone (`--filter DeferredRenderTests`).

## Verdict

Not ready yet. The fix is correct: the render moves off the main thread,
the surface is owned and released properly, there is a failure path, and
HDR, exports and goldens are left alone. But one of its new tests is flaky
(C1): it compares two separate Core Image renders byte for byte, and Core
Image itself varies by one level from one render to the next. Two of my
five full runs failed on it, so CI would likely go red. Fix C1, then QA.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Blocker | `Tests/PhotoCoreTests/DeferredRenderTests.swift:183` | `matchesCoreAnimationsRender` requires Core Animation's render of the deferred image and its draw of the new rendition to be byte-identical (`rows == 0`). These are two separate renders of the same stack, and Core Image's 8-bit output varies by one level between renders whichever route draws them. | Full `swift test` failed 2 of 5 times on this Mac: "kCGColorSpaceDisplayP3: 484 rows differ from Core Animation's render of the deferred image". In a scratch clone I rendered the test's stack twice per route, six rounds with a new engine each, with and without the vignette. The old deferred route against itself differed in 486 rows (1727 bytes) in one round and 106 rows (138 bytes) in another, surface against surface the same, always at most 1 level; other rounds were identical. So the test's premise is too strict; the fix itself is fine. A tolerance of ≤ 1 level per byte (with a count bound if wanted) would still catch the bitmap route, which differs by up to 52 levels. The status's "equal byte for byte" needs the same qualification. | Tests are deterministic (agent rules; `CLAUDE.md`, Checking image code) |
| C2 | Nit | `Sources/PhotoCore/Preview/RenderEngine.swift:133`, `PreviewService.swift:229`, `WorkLane.swift:93` | The full rendition's render now runs inside the full lane (one slot), and once `waitUntilCompleted()` has started it can't be cancelled. When the loupe moves on, `cancelWaiter` cancels the task, but the job keeps its slot until the render finishes. | At 100%, press → twice quickly (or hold it) with machine learning noise reduction on. The photo you stop on starts rendering only after the previous photo's 1.3–2 s render ends, so it can stay soft up to that much longer than a single arrival (status: 1327–2095 ms). Before this fix each arrival froze the main thread for as long, so overall this is better, not a regression. No change asked. Worth a line in the status's "Not fixed here" and a look in QA's arrow-key check. | Concurrency: cancellation honored |

## Questions

- **Memory per full frame (engineer, measurement only).** The rendition
  keeps its own 96 MB IOSurface for the CGImage's life (memory cache plus
  layer). Core Animation then copies it (the status measures 10–15 ms per
  draw against about 5 ms from ordinary memory). Before, Core Animation's
  deferred render went straight into a surface of its own. So at 100% there
  may now be two 96 MB copies where there was one, and four in Compare.
  I could not measure the window server's side headless, so this is a
  question, not a finding. A `footprint`/`vmmap` reading of the app at 100%
  before and after would settle it. If it doubles, the follow-up would be
  handing the layer the IOSurface itself.
- **Design review.** The spinner after letting go of a raw setting at 100%
  is the one design §2.1 specifies (viewport-render-1to1 `design.md`). That
  file's `review.md` names its absence as known limitation L1 (DR3, M13).
  The spinner logic is unchanged; only the timing changed. I don't think it
  needs a full design review; a one-line confirmation from the designer
  that L1 is resolved would do, and QA's M13-style check covers what it
  looks like. The main session decides.

## Checked and fine

- **Main thread.** `PreviewGenerator.cgImage` is called only from
  `PreviewService.fullResolutionImage`, inside `fullLane.run`. That lane
  runs work in `Task.detached`, so the decode and the render no longer
  reach the main thread, and the loupe gets a CGImage that is already
  rendered. `renderedWhereMade` shows Core Image's provider is not asked
  again on read or draw, with a control proving the short call still
  defers.
- **Blocking wait off the main thread.** `waitUntilCompleted()` blocks a
  thread of the Swift cooperative pool for 0.4–2 s. That is not new in kind:
  the generate lane (`encodedRendering`) and the HDR lane (`makeHDRCGImage`
  reads pixels) already render synchronously in the same detached lane
  tasks. The full lane has concurrency 1, so at most one more thread is
  held.
- **IOSurface lifetime and ownership.** A new surface for each call, never
  pooled or reused, so nothing can overwrite a surface that is still shown.
  It is locked read-only after the GPU is done. The data provider holds one
  `passRetained` reference, and its release callback unlocks and drops it.
  The CGImage retains the provider, and so do crops of it. If
  `CGDataProvider` fails, the reference is balanced by hand. If `CGImage(…)`
  returns nil, ARC frees the provider and the callback balances it. Rows use
  `surface.bytesPerRow` for both the size and the image.
- **Pixel format.** BGRA, premultiplied first, 32-bit little-endian. It
  matches `CIRenderDestination`'s default premultiplied output, and the
  orientation is checked by the test's own-pixels comparison (line 198,
  which passed in every run).
- **Large images.** In a scratch program, `IOSurfaceGetPropertyMaximum`
  reports 16384, yet surfaces of 16385 × 3000, 20000 × 4000 and
  30000 × 3000 were created and rendered correctly through
  `CIRenderDestination`. A wide panorama still gets its rendition.
- **Failure path.** If the surface can't be made, the render throws, or the
  lock fails, the result is nil → `Failure.renderFailed` →
  `fullResolutionImage` throws → `LoupeView.loadFullResolution` clears
  `loupeAwaitsFullRendition` and keeps the preview-tier image. That is the
  same as a failed `makeCGImage` before.
- **Stale results.** `LoupeView` (and `ComparisonView`) check `shownKey`
  before they display a result, unchanged. Only the newest full rendition
  stays in the memory cache (`insertFullResolution`).
- **Untouched paths.** `makeCGImage(_:colorSpace:)` (live frames, maps,
  thumbnails), `makeCGImage(_:colorSpace:bitsPerComponent:)` (exports,
  goldens, `photocli render`) and `makeHDRCGImage` are unchanged in the
  diff. `coreAnimationRendersDeferredImages` shows that the HDR rendition
  is not rendered again by Core Animation, which is why it keeps its call.
  No pipeline bump, no golden touched, `GoldenTests` passed in every run.
- **Sendable.** `CGImage` crosses back in `DecodedImage`, as before.
  `RenderEngine` stays `@unchecked Sendable` for its existing reason; the
  new method adds no shared state.
- **Docs and scope.** The `USER_GUIDE.md` paragraph matches the behavior.
  The comments in `AdjustmentEditor` and `ViewportBenchmark` are updated.
  The issue's lazy 2560 px base is explained and left in "Not fixed here",
  along with the refined sharpening map at 100% (which may stall the same
  way) as a candidate follow-up.

## Follow-up

| # | Result | Commit |
|---|---|---|
| C1 | Fixed | `072518d` |
| C2 | Not fixed, as asked: noted in `status.md` ("Not fixed here") and in its checks for a person | `072518d` |
| Question: memory | Answered: measured, no second copy in the app process | `072518d` |

## Second pass

Date: 2026-11-15. Reviewed: commit `072518d` only (`Sources/PhotoCore/Preview/RenderEngine.swift`,
a comment; `Tests/PhotoCoreTests/DeferredRenderTests.swift`; `status.md`).
Build and tests: `swift build` clean. Full `swift test` three
times in a row at `072518d`: 1040 tests in 155 suites passed, 3 of 3
(64.5, 67.2, 66.9 s); `matchesCoreAnimationsRender` passed in each
(21.1 to 21.8 s). Earlier, two of five full runs failed on it.

**C1, closed.** `matchesCoreAnimationsRender` now allows one level per byte
between Core Animation's render of the deferred image and its draw of the
rendition, and reports the row count and the worst difference. The exact
check that Core Animation passes the rendition's own pixels through stays
exact (`rows == 0`), which is right: that comparison is of one render with
itself, not two renders.

- **The control still makes the bitmap route fail.** It renders the same
  `image` with the same context, extent, format and color space, with
  `deferred: false`, draws it through the same `drawnByCoreAnimation`, and
  requires it to differ from `before` by more than one level. It does not
  depend on the product code, so if Core Image ever made the two routes
  agree within one level, the control fails and says the test needs
  revisiting, instead of the test passing without telling anything apart.
  If the product code went back to a bitmap render, `after` would be that
  render, and its difference from `before` is the control's (the engineer
  shows it: 3146 rows, up to 24 levels, against the tolerance of 1). The
  `stopAbove: 1` early exit only shortens the scan; it can't make the
  control pass wrongly, since it stops only once `worst` is already over 1.
  Strictly, a control of "more than 1" leaves room for a bitmap render at
  exactly 2 levels to slip under the tolerance through one level of noise;
  with differences of 24 to 52 levels observed this is theoretical, so no
  finding.
- **No "byte for byte" claim about the on-screen render remains.**
  `git grep` over `Sources/`, `Tests/`, `status.md` and `docs/USER_GUIDE.md`:
  `makeSurfaceImage`'s comment, the suite and test comments, the test's
  name and `status.md` (Fix, Tests) now say "within one level". What is left
  is correct: `status.md` line 84 says the rendition's own pixels and their
  draw are equal byte for byte (they are, and the test checks it exactly),
  line 229 quotes the finding, and the user guide never made the claim (its
  one "byte for byte", line 589, is about export and masters). Other
  "byte for byte" tests in the suite are unrelated to this change.
- One small inconsistency, not a finding: the test comment says a bitmap
  render differs "by up to 52 levels on this stack" (my scratch measurement
  for C1), `status.md` "up to 24 levels" (the engineer's, with the bitmap
  route in `PreviewGenerator.cgImage`). Both are measurements; the claim
  that matters, far more than one level, holds for either.

**C2, closed as Not fixed by agreement.** `status.md` names it under
"Not fixed here" with the before/after trade, and adds an arrow-key check
with machine learning on to the checks for a person, which is what was
asked.

**Memory question, answered.** The numbers in `status.md` hang together
with the commit message and with the image: a 6000 × 4000 BGRA surface is
96,000,000 bytes, 91.6 MiB, which `footprint` shows as 92 MB of dirty
IOSurface in both builds (the "96 MB" elsewhere in the file is the same
surface in decimal megabytes). Physical footprint before 619, 694, 716 MB
(a spread of about 97 MB, "about 100 MB" as written) and after 628, 629 MB,
inside that spread. One surface in each build, so the app holds no second
copy. The window server's side is not measured, as the file says; that was
also the part I could not reach, so I don't ask for more.

**Verdict, second pass.** Ready for the next step (qa-tester, after the
designer's confirmation on L1 if the main session asks for it). No new
findings. `/security-review` still not needed.

## Second pass (d29424f)

Date: 2026-11-15. Reviewed: commit `d29424f` only (the owner's finding at
sign-off: at 100% the photo jumps when the full rendition lands).
Files: `PreviewGenerator.outputSize`, `PreviewService.outputSize(for:)`,
`memoryCachedOutputSize(for:)` and their cache, `LoupeArrivalSize`,
`LoupeView` (arrival, `resizeImageView(toPixels:)`, the `matchFrame(to:exact:)`
change, neighbor prefetch), `ComparisonPane.show`, `OutputSizeTests`,
`status.md`. Build and tests: `swift build` clean. Full `swift test` at
`d29424f`, three logged runs in a row: 1044 tests in 156 suites passed, 3 of
3 (70.0, 67.3, 66.5 s). `OutputSizeTests` passed in each, and its real-raw
case was skipped (no `CAMERA_RAW_SAMPLE` set). Two earlier full runs exited 0
as well, but I didn't capture their summaries. I didn't launch the app.

**Verdict, second pass.** Ready for the next step. The arrival size is
computed from the same graph that renders, keyed so that an edit can't
serve an old size, and nothing new reaches the main thread. Two small
findings about the neighbor prefetch's extra work (C3, C4); neither is a
correctness problem and neither blocks QA.

### Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C3 | Should fix | `Sources/PhotoApp/Loupe/LoupeView.swift:623-626`, `Sources/PhotoCore/Preview/PreviewService.swift:270` | A neighbor task that has been cancelled still starts `outputSize`. `WorkLane.run` throws `CancellationError` at once for a cancelled task, `try?` swallows it, and the next line calls `previews.outputSize(for:)` without checking `Task.isCancelled`. Its `Task.detached` doesn't inherit the cancellation, so the work always runs to the end. Cancelling `sizeTask` doesn't stop its inner detached task either. | Hold → at 100% (the owner's check) or at fit. Each step cancels up to three neighbor tasks, and each cancelled one starts a header read for a photo the person is already past: two `CIRAWFilter(imageURL:)`, two `DNGLayout` reads, and, for a cropped Olympus or Panasonic raw, `CameraFrame.fullFrameData` reading the whole file. Each is 20–100 ms by `status.md`, they run at `.userInitiated` alongside the full lane's render, and nothing limits how many run at once. Before this commit a cancelled neighbor did nothing more. Fix: `guard !Task.isCancelled else { return }` before the `outputSize` call. | Concurrency: cancellation honored |
| C4 | Nit | `Sources/PhotoCore/Preview/PreviewService.swift:262-276` | `outputSize(for:)` doesn't share work with a request already in flight for the same key, and always runs at `.userInitiated`, even when a prefetch asks. | Arrow from n to n+1 before n+2's size is known: the new step asks for n+2's size again (now index+1) while the first request is still running, so the same work runs twice. A prefetch read competes with the visible full render at the same priority. The lanes avoid both through their key and priority. Fix: run it in a lane, or pass a priority and keep a map of in-flight requests. | Concurrency (efficiency); no rule broken |

### Checked and fine

- **Main thread.** On the main actor, `show` only calls
  `memoryCachedOutputSize` (a `Mutex` dictionary lookup) and
  `previewRequest` (as before). Loading the stack (the catalog read), the
  `SystemRAWDecoder.reads` probe, `DNGLayout`, the decode graph and any
  `CameraFrame` copy all run inside `outputSize`'s `Task.detached`. `remember`
  is a lock. `PreviewService` stays `Sendable` with `Mutex` state, and the
  detached closure captures only `Sendable` values (`PreviewGenerator`, the
  `@Sendable` loader, `PreviewCacheKey`, `URL`).
- **Same graph as the render.** `outputSize` takes
  `image(source:stack:longEdge: nil)`'s `extent.integral`, the call
  `cgImage(source:stack:colorSpace:)` makes before `makeSurfaceImage`, which
  sizes its surface by the same `extent.integral`. It uses the same
  `interactiveGenerator`, no draft, scale 1. So the frame
  (`RAWDecodeGraph`, `CameraFrame` when the stack asks for the whole sensor,
  and the fallback without decoder choices), orientation, lens corrections,
  straightening, turns and crop all come from the code that renders. The
  color space doesn't change the size. The graph is lazy (the renderer's
  local estimates are filters, not renders), so nothing is decoded. The
  cases left out are left out correctly: videos; raws
  `SystemRAWDecoder.reads` refuses (LibRaw would decode in full, about 9 s);
  linear DNGs (`LinearRawDecode.rendered` renders the whole image). Raws the
  system reads never reach LibRaw (`rawImage`'s order), so a size from the
  system graph can't disagree with a LibRaw rendition. HDR full renditions
  are not recorded, and floating-point DNGs are linear and so return nil
  anyway.
- **Stale sizes.** The key is content hash, render hash and pipeline
  version. Crop, rotate, straighten, undo, redo and a history revert each
  change the render hash, so each gets its own entry, and returning to an
  earlier stack gets that stack's own size, which is still right. A stack not
  saved yet fails `Self.stack`'s hash check and gives nil, not a wrong size.
  At the same version (an edit), `show` sizes nothing on arrival and starts
  no size task, as before. `rendition < .full` keeps a late size from
  touching a full rendition or a live frame (`.live` sorts above `.full`).
  `shownKey` is checked as for the other tasks.
- **Memory.** At most 4096 entries of about 150 bytes (key plus `CGSize`),
  about 0.6 MB, emptied all at once at the limit. Fine.
- **The `matchFrame(to:exact:)` change.** At 100%, a full rendition whose
  size differs now keeps the same relative center instead of re-centering.
  Magnification is the same either way (`applyZoom` sets 1 at
  `.actualSize`). After a crop or turn at 100%, the preview step
  (`exact: false`) still re-centers when the aspect changes, so in practice
  this only applies to an arrival whose size was wrong. That is the case it
  was made for.
- **Compare (#63).** `ComparisonPane.show` uses the same rule, and its
  late correction goes through `resizeDocument`, which runs under
  `performWithoutFollowing` and keeps the unit center, so a linked pane
  doesn't move with it. Compare doesn't prefetch, so a pane uses a size the
  loupe learned or corrects once.
- **Film strip (#25), videos, offline.** The film strip still uses the
  catalog's proportions (unchanged and named in `status.md`). Videos: nil
  from `outputSize`, and `fullResolutionImage` doesn't record a poster's
  size. Offline: no task (`sourceURL` nil), and a size already learned is
  still used.
- **Rendering unchanged.** No change to the renderer, `PreviewCacheKey`,
  pipeline version or goldens. `cgImage` and `fullResolutionImage` render
  exactly as before; the only addition is `remember`, after the render.
- **Tests.** `OutputSizeTests` checks the predicted size against the
  rendered one, the cache, the rendition recording its own size, and the
  arrival rule. Cases: a cropped and turned DNG where the catalog's size is
  wrong (asserted, so the case can't pass trivially), an orientation-6 JPEG,
  a plain DNG, and a real raw behind `CAMERA_RAW_SAMPLE`. Swift Testing,
  deterministic, no sleeps. The video case only exercises the early return.
  No straightened case, but straightening goes through the same `extent` by
  construction.
- No new UI strings, brand values, dependencies, migrations or persisted
  names.

### Follow-up (second pass)

| # | Result | Commit |
|---|---|---|
| C3 | Open | |
| C4 | Open (Nit; the engineer may leave it with a line in `status.md`) | |

## Third pass (bb27fda)

Date: 2026-11-15. Reviewed: commit `bb27fda` only (`LoupeView.preloadNeighbors`,
`PreviewService.outputSize(for:)`, `OutputSizeTests.cancelledCallerStartsNoRead`,
`status.md`). Build and tests: `swift build` clean. Full `swift test` at
`bb27fda` twice in a row: 1045 tests in 156 suites passed, 2 of 2 (67.1 and
65.5 s), the new test passing in each.

**C3, closed.**
- **The prefetch.** `guard !Task.isCancelled` comes after the swallowed
  `try?` of the preview prefetch and before `outputSize`, and again after
  `outputSize` and before the HDR prefetch. A cancelled neighbor now does no
  more work than it did before `d29424f`.
- **`outputSize(for:)`.** A cancelled caller still gets a size the cache
  already has, which needs no read. Otherwise it returns nil before it makes
  the detached task. The detached read now checks `Task.isCancelled` after
  loading the stack and before `generator.outputSize`, and
  `withTaskCancellationHandler` passes the caller's cancellation on to it. If
  the caller is cancelled between the guard and the handler, `onCancel` runs
  at once, so that race is covered too. The catalog read for the stack still
  runs to the end; it is small and was never the cost.
- **Nothing cached for a cancelled caller.** A cancelled read returns nil, so
  `remember` is skipped. If cancellation arrives after the recheck, the read
  finishes and its size is cached. That size is right for its key, so it
  does no harm.
- **Non-cancelled calls.** The size, the cache and the priority are as
  before; the test's second half checks one read and the right size. The
  other two callers (`LoupeView:362`, `ComparisonView:812`) already ignored a
  result once cancelled, so a nil there changes nothing.
- **The test catches it.** In a scratch clone (the repository was not
  touched), removing only the entry guard makes `cancelledCallerStartsNoRead`
  fail on `loads == 0` (the stack loader runs). Removing the recheck as well
  makes it fail on `cancelled == nil` and on the cache being empty too. So the
  test covers the guard directly and the handler plus recheck indirectly.
  Swift Testing, deterministic, no sleeps.

**C4, closed as Not fixed by agreement.** `status.md` names it under "Not
fixed here" (no coalescing, always `.userInitiated`), which is what was asked.

No new findings. `/security-review` still not needed.

### Follow-up (third pass)

| # | Result | Commit |
|---|---|---|
| C3 | Fixed | `bb27fda` |
| C4 | Not fixed, as agreed: noted in `status.md` ("Not fixed here") | `bb27fda` |

## Security review

Not needed. The change adds no parser, subprocess, file writing outside the
library, or network code. `d29424f` reads only headers of masters the app
already reads, so it doesn't change that.

## Summary for the issue

**Code review (#65): not ready, one Blocker in a test. The fix itself is sound.**
- The full-resolution rendition is rendered into a new IOSurface in the full
  lane, off the main thread. Ownership (retained by the provider, unlocked
  on release), the failure path and stale-result guards are right. HDR,
  exports and goldens are untouched.
- C1 (Blocker): `matchesCoreAnimationsRender` failed 2 of 5 full test runs
  (484 rows). Core Image's own output varies by 1 level between renders on
  both routes, so a byte-exact comparison is flaky. Allow 1 level.
- C2 (Nit): a running render can't be cancelled, so quick arrowing at 100%
  with ML on can delay the last photo by one render. Overall better than
  before; note it.
- Questions: possible doubled memory (our surface plus Core Animation's
  copy), to measure. The spinner after letting go is design §2.1's (L1);
  I suggest a designer confirmation, not a full review. No
  `/security-review`.
- Full file: `docs/features/full-render-main-thread-stall/code-review.md`
