# Halves that don't line up at 100% (Core Image split render): code review

Owner: code-reviewer. Date: 2026-11-21. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/core-image-split-render`, `9bcac27..47e4065` (merge base with
`origin/develop`; two commits, `390cb83` and `47e4065`). Bug fix: reviewed
against the **Bug** section of `status.md` and issue #253.
Build and tests: `swift build --build-tests` clean, no new warnings;
`swift test` 1282 tests in 184 suites passed (90.4 s); the affected suites
(`ImageIOFullDecodeTests`, `LensAlignStaleAreaTests`, `LiveRegionRendererTests`,
`SpotTests`) 47 tests passed, and `ImageIOFullDecodeTests` with
`LensAlignStaleAreaTests` passed 4 runs of 4 in a row (about 18 s a run).

## Verdict

The fix is correct and the tests prove it: with the copy turned off, every
regression test the Bug section names fails, in every run. It is not ready for
the pull request until C1 is settled, because the 20 MP render test is very
likely to fail on CI's GPU. The rest (C2 to C4) are worth fixing but do not
block QA.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C1 | Should fix | `Tests/PhotoCoreTests/ImageIOFullDecodeTests.swift:259` (`largeRenderKeepsItsParts`) | The 20 MP render test always runs. The project gates renders this large behind `LARGE_RENDER_TESTS=1` because CI's runners can't do them: `DeferredRenderTests.swift:220-223` says "the CI runners' paravirtual GPU fails the 24 MP render below ('command buffer exited with error status')"; `LiveRegionRendererTests` uses 3000 × 2000 by default and 6000 × 4000 only with the variable; `RuntimeKernelTests` and `LargeSharpeningMapTests` do the same. This test makes a 320 MB float texture and 20 more full 5472 × 3648 renders with local tone (Highlights −45), on four fresh engines. | On the macOS 26 and 15 runners (step 7), a failed command buffer makes `makeSurfaceImage` return nil, so `cgImage` throws `renderFailed` and the test fails. The PR goes red on a test, not a fault in the code. CI is also where the Core Image fault may not exist at all (status "Not verified"). Fix: gate it like its neighbors (`.enabled(if: … ["LARGE_RENDER_TESTS"] == "1", …)`), and add `ImageIOFullDecodeTests` to the `LARGE_RENDER_TESTS` command in `CLAUDE.md` (the owner's file: propose it in the report). The ungated guards still fail without the fix (checked, see Checked and fine): `fullDecodeIsResident`, `renderUnchanged`'s `decoded.url == nil` and `tileSeesTheInputArea`'s JPEG case. | Tests deterministic and fit for CI; `CLAUDE.md` `LARGE_RENDER_TESTS` convention |
| C2 | Should fix | `Sources/PhotoCore/Preview/ResidentDecode.swift:69` | The only size limit is 16384 pixels on a side, so a full-size decode can hold up to 16384 × 16384 × 16 B = 4 GiB of GPU memory. Before the fix the same decode was read lazily and held nothing. Exports run two renders at once (`ExportJob.maxConcurrentRenders` = 2), and `LiveRegionRenderer.decode` (`LiveRegionRenderer.swift:170`) holds the float copy and its own half-float base together while it materializes (24 B/px at the peak). | A 16000 × 10000 TIFF or PNG (a stitched panorama, or a PNG of that size a few MB long, since deflate compresses flat areas very far) makes a 2.56 GB private texture for each full-size decode. Exporting two at once asks for 5.1 GB, over the recommended Metal working set of an 8 GB Mac (about 5.3 to 5.7 GB) before Core Image's intermediates and the 16-bit output bitmaps are counted. The copy may succeed and the render after it then fail (`renderFailed`, export fails), or the system swaps hard. An upload that fails falls back to the lazy read, but one that succeeds and starves the next render does not. Fix: add a pixel or byte limit as well as the side limit (for example a share of `device.recommendedMaxWorkingSetSize`, or a fixed megapixel cap), above which the decode stays lazy and is logged, as it already is beyond 16384. Where the limit goes is a trade-off the owner should rule on (see Q1). | Concurrency and memory: work that holds the decode longer or larger than needed |
| C3 | Nit | `Sources/PhotoCore/Preview/ResidentDecode.swift:73`, `:94` | The doc comment says "Nil, logged", and `status.md` says the fallback is "logged". Two of the nil returns log nothing: no Metal device (`:73`), and `CIImage(mtlTexture:)` returning nil (`:94`). | On a machine or run with no Metal device, or if Core Image refuses the texture, the photo silently stays exposed to the seam, and `log stream` shows nothing to say why. Fix: log on both lines, as the other three paths do. | Correctness: a fallback the code says it logs |
| C4 | Nit | `status.md` "The fix" and "The one render change"; `ResidentDecode.swift:49` | `status.md` names the cost as "16 bytes a pixel… while the decode is in use". It doesn't say that the 100% base doubles up while it is made: `LiveRegionRenderer` copies the float copy again into its own half-float texture, so it costs one more full pass and a 24 B/px peak for ImageIO photos. Separately, `bandPixels`' comment ("a 32 MB copy of 16-bit pixels") describes the source; each band writes 64 MB into the float destination. | Readers judging memory (QA, the owner, the #150 merge) under-count the 100% path's peak by a third. Fix: one line each in `status.md` "Cost" and the comment. | Record keeping |

## Questions

- **Q1 (owner, through the main session; goes with C2).** Where should the
  resident copy stop? Above a limit the decode stays lazy, so those photos can
  still show the seam on macOS 27.2, as photos over 16384 pixels already can.
  Below it, a full-size view or export holds 16 B/px of GPU memory. A limit
  near 100 to 150 MP (1.6 to 2.4 GB, matching LibRaw's 150 MP cap for raws)
  covers every camera frame and keeps two at once inside an 8 GB Mac's
  working set.
- **Q2 (engineer, `status.md` accuracy; not a finding, not measured by me).**
  "The one render change" names straightened or rotated full-size renders
  only. Any step that resamples the decode before Core Image's first
  intermediate may move the same way: Manual Distortion, Color Alignment and
  the export resize, as well as a heal or clone whose source sits at a
  fractional offset. The heal and the 2048 px resize were measured (at most
  one step). If Distortion and Color Alignment on a JPEG at full size are
  measured, or the sentence says "resampling of the decode (Straighten,
  Distortion, Color Alignment…)", QA and Ship will describe the change
  correctly. The pipeline version holds either way (see below).

## Checked and fine

- **The fix works, and the tests fail without it.** I turned the copy off
  (`let image = lazy` in `decodeWithImageIO`), rebuilt, and ran twice, then
  three more times for `largeRenderKeepsItsParts` alone. Every run failed
  `fullDecodeIsResident` (url not nil), `renderUnchanged` (both cases),
  `tileSeesTheInputArea` (JPEG) and `largeRenderKeepsItsParts` ("1 of 16
  renders showed the right half on the left", "15 of 15 renders differed
  from the first", the same in all five runs). Then I restored the file
  byte for byte, and `git status` was clean. With the fix, 4 of 4 runs
  passed.
- **The unflipped `LiveRegionRenderer.materialize` is needed and guarded.**
  I put back `develop`'s flipped version with the fix in place, and
  `LiveRegionRendererTests` "A region is the same area of the
  full-resolution render" failed (center, crop and straighten). Then I
  restored it and the tree was clean. Nothing else reads `base.texture`'s
  rows directly; `baseByteCount` (8 B/px) still matches the half-float base.
- **Bands.** `bands(of:)` covers the extent top first with no gaps or
  overlaps, and destination origins are bottom-up, matching an unflipped
  destination. `residentCopyIsTheFile` (3000 × 2000, several bands) is exact
  in float. Each band is at most 4 MP (64 MB in float), far under the 256 MB
  limit at which Core Image splits a render, and each one is
  `waitUntilCompleted` before the next starts, so no band copy can race a
  read. With the side capped at 16384, a band is at least 256 rows.
- **Color space and orientation.** The copy renders to and reads from the
  working space (extended linear Rec. 2020) as unclamped `rgba32Float`, and
  the alpha modes are the defaults on both sides, so the copy is
  premultiplied in and out. An unedited render is the same bit for bit
  (`renderUnchanged`, `residentCopyIsTheFile`). The orientation is applied
  by `CIImage(contentsOf:, applyOrientationProperty:)` before the copy
  (`fullDecodeIsOriented`, EXIF 6, bytes equal).
- **Lifetime.** The texture lives only as long as the `CIImage` that reads
  it: the graph in `cgImage`, export, `photocli render`,
  `FringePicker.samplePixels` and the sharpening map's `renderWhole` drops it
  when the call returns. `LiveRegionRenderer` keeps only its own half-float
  base, and `SharpeningMapRefiner` only its materialized `CGImage`. Nothing
  caches the decode. The lazy `CIImage` is released after the copy. The
  contexts keep no intermediates (`cacheIntermediates: false`).
- **Swift 6 concurrency.** `ResidentDecode` is a non-isolated enum. Its
  `static let`s (a `RenderEngine`, `@unchecked Sendable` with a written
  reason that holds, and a `Logger`) are Sendable. Every full-size caller
  runs off the main actor: the `fullLane` task, `Task.detached` in
  `LiveRegionRenderer.prepare` and the fringe sample, the
  `SharpeningMapRefiner` actor, export and `photocli`. `outputSize`, which
  runs detached and is asked for neighbors that may be cancelled, keeps the
  header read through `forSizeOnly`. The blocking `waitUntilCompleted`
  follows `makeSurfaceImage` and `materialize`. No cancellation check
  between bands: the copy costs about 10 to 50 ms at 20 MP and callers check
  before it, so that is acceptable.
- **No `PreviewCacheKey.currentPipelineVersion` bump: the claim holds.**
  Only `encodedRendering` writes to disk (`PreviewService.swift:207-216`).
  It passes the tier's long edge (512 or 2560, times the crop's
  `sourceZoom`, `decodeLongEdge`), which always takes ImageIO's thumbnail
  path (a `CGImage`), never `ResidentDecode`. That includes tight crops,
  where the thumbnail is capped at the native size. Callers with
  `longEdge: nil` are all memory-only or outputs: the 100% rendition (memory
  `#full`; side by side and review mode use it), export, `photocli render`,
  `LiveRegionRenderer`, the sharpening map refiner (never seeded:
  `frame.showsPhoto`), the fringe picker's samples and `MaskBenchmark`.
  Color Alignment's measurement (2048), Auto (`measureSize`) and the live
  session (`decodeSize`, an `Int`) decode smaller. `seedPreviewIfRendered`
  fills the memory cache only. The HDR rendition (`decodeHDR`) is
  unchanged. This matches the precedent in
  `docs/features/deferred-render-flake/` and
  `docs/features/sharpening-map-tiles/` (no bump when nothing cached
  changes). No golden moved, no tolerance loosened: `renderUnchanged` uses
  the 100% renderer's existing derived tolerance.
- **#228's guard (`LensAlignStaleAreaTests`).** The blurred-scene case still
  pins that its input can show a stale area (`sees: true`), so
  `dragInOneContext` is still a real guard for `lensAlign`'s area callback.
  The JPEG case now pins that the pipeline's full-size JPEG can't
  (`sees: false`), which also fails if the decode goes lazy again (checked
  above). `jpegDragInOneContext` is now only a regression check of the
  user's case, as the new comment says.
- **SDK compatibility.** `CIRenderDestination(mtlTexture:commandBuffer:)`,
  `CIImage(mtlTexture:options:)`, `startTask(toRender:from:to:at:)`,
  `CIImage.url` and the `CIFilterBuiltins` generators the test uses are all
  in the macOS 26.5 SDK's headers here, and are macOS 10.12 to 10.15 APIs.
  None is a macOS 27 symbol. I did not run a Swift 6.2 compiler; the
  engineer's native-build-system build against 26.5 is in `status.md`.
- **Scope.** No catalog, migration, stack, sidecar, UI string, branding or
  dependency change. `photocli render --software` is refused on Apple
  silicon, so the Metal-only copy doesn't reach a CPU context there.
- **`/security-review` not needed.** No new parser, subprocess, file writing
  or network code: files are still read by ImageIO and Core Image as
  before. The resource side of untrusted sizes is C2.

## Follow-up

### Second pass, 2026-11-21

Reviewed: `47e4065..34a614c` (one commit, `34a614c`). It touches
`ResidentDecode.swift`, `ImageIOFullDecodeTests.swift`, `status.md` and this
file (committed by the engineer as written; no finding above was changed).
Nothing else changed.
Build and tests: `swift build --build-tests` clean. `swift test` 1283 tests
in 184 suites passed (74.7 s). Under load, two full `swift test` runs at once
while `fullDecodeIsOriented` ran 8 times in a third process: all passed, no
failure in either log. `ImageIOFullDecodeTests` with `LensAlignStaleAreaTests`
passed 5 runs of 5 in a row. `LARGE_RENDER_TESTS=1 swift test --filter
ImageIOFullDecodeTests`: 7 of 7 passed (the soak 9.3 s).

| # | Result | Notes |
|---|--------|-------|
| C1 | Fixed, `34a614c` | `largeRenderKeepsItsParts` is gated by `.enabled(if: LARGE_RENDER_TESTS == "1")`, the same form as `DeferredRenderTests`' large case, and the suite's doc comment and `status.md` name the command. The engineer's case that no smaller ungated variant can guard this holds up: they report 0 of 24 swaps at 3000 × 2000 (forced into 4 to 20 parts by a small `memoryTarget`) and at 4400 × 1100 in 8 parts, against 12 of 24 at 15.8 MP (4592 × 3448) and at 20 MP. That agrees with what I saw in the first pass (the 20 MP soak failed in every run without the fix) and with the fault needing large inputs, not just a split render. The largest renders known to pass on CI are about 6 MP (`LiveRegionRendererTests`' 3000 × 2000, `DeferredRenderTests`' ungated 4400 × 1100), so a CI-sized variant would pass without the fix. I did not run their probe again. The ungated guards still fail without the fix (see below). `CLAUDE.md`'s `LARGE_RENDER_TESTS` command still names only `LargeRenderTests|LargeBrushTests`. Adding `ImageIOFullDecodeTests` there is the owner's call, and the main session should propose it. |
| C2 | Fixed, `34a614c` (owner's ruling on Q1) | `lazyReason(width:height:)` checks the side first (so `width * height` can't overflow, and it couldn't on 64-bit anyway), then `> 100_000_000`. That is inclusive, so 10000 × 10000 is copied. `resident` returns nil with a notice for each reason before it asks for a device or makes a texture. `residencyLimit` pins both limits, the edges on both sides, the order of the two reasons, and that `resident` keeps a 10000 × 10001 generator image lazy (nothing allocated). The log says the size, which limit was hit and that the photo may show the seam. Its arguments are integers, so they are public in `os_log`. The doc comment and `status.md` ("Photos over either limit stay exposed", README notes) say what the limit leaves open. |
| C3 | Fixed, `34a614c` | Both paths now log an error (no device; `CIImage(mtlTexture:)` nil), with the size and that the decode is read lazily. Neither can be reached in a test here, as `status.md` says. |
| C4 | Fixed, `34a614c` | `status.md` "Cost" and the `ResidentDecode` doc comment give the 100% path's extra pass and 24 B/px peak (480 MB at 20 MP, 1.6 GB of copy at the 100 MP limit). The `bandPixels` comment says 64 MB into the float texture. Q2 is answered in the wording: Distortion and Color Alignment "may change the same way… not measured", listed under Not verified. |
| F (flaky `fullDecodeIsOriented`) | Fixed, `34a614c` | The diagnosis holds. The old test compared two different graphs in 8-bit Display P3: Core Image converting the file's encoded values against Core Image converting the copy's linear floats. A one-level rounding difference near a level boundary is what you'd expect from two programs, and it fits "passed alone, failed once in a full run" with no sleep or shared state involved. The new comparison is in float in the working space, which is the space the copy is rendered in, so equality is the claim itself (the same comparison as `residentCopyIsTheFile`). It is exact, with no tolerance, so nothing was loosened. It still checks orientation: the extent (480 × 640) and every value against Core Image's own oriented read. It passed in every run above, about 18 in all, 8 of them while two full suites ran at once. |

**The tests still fail without the fix.** I turned the copy off
(`let image = lazy` in `PreviewGenerator.swift:414`), rebuilt, and ran
`ImageIOFullDecodeTests` and `LensAlignStaleAreaTests` twice with
`LARGE_RENDER_TESTS=1`. Both runs failed the same 7 issues: `fullDecodeIsResident`
(2), `renderUnchanged` (JPEG and TIFF, `decoded.url == nil`),
`tileSeesTheInputArea` (JPEG) and the soak (`swapped == 0`, `unlike == 0`). So
without the variable, as on CI, three ungated tests still fail without the
fix. Then I restored the file with `git checkout`, checked it against its
SHA-1 from before, rebuilt and retested (10 of 10 passed). `git status` is
clean. As before, `fullDecodeIsOriented` and `residentCopyIsTheFile` pass
without the fix. That is by design: they check the copy's values, not that the
copy is used.

**Verdict, second pass.** C1 to C4 and the flaky test are closed, and no new
findings. The branch is ready for qa-tester. `/security-review` is still not
needed (no parser, subprocess, file writing or network code).

### Third pass (CI fix), 2026-11-22

Reviewed: `74a5256..42657d3` (one commit, `42657d3`, tests and `status.md`
only: `Support/BlockingWork.swift` and `BlockingWorkTests.swift` new,
`ImageIOFullDecodeTests.swift` and `LensAlignStaleAreaTests.swift` changed).
Nothing in `Sources/`, `Scripts/` or `Package.swift`. The merge `74a5256` was
not reviewed (a merge of `develop` with no hand-resolved code). `42657d3` is
not pushed yet (`origin` is at `74a5256`), so CI has not run on it.
Build and tests: `swift build --build-tests` clean, with no warning from the
four changed test files (rebuilt from scratch). `swift test`: 1337 tests in 191
suites passed (95.0 s). `LARGE_RENDER_TESTS=1 swift test --filter
ImageIOFullDecodeTests`: 8 of 8 passed (the soak 9.3 s). Local toolchain:
Swift 6.4.2. CI builds with 6.2.4 (macOS 15) and 6.3.3 (macOS 26), and neither
is installed here, so CI is the only check of those compilers.

**Nothing weakened.** In `git show -w 42657d3` the test bodies change only
by being wrapped in `offCooperativePool { … }`, plus three comparison lines
and one tolerance line. Every `#expect` and `#require`, every image size
(640 × 480, 3000 × 2000, 1200 × 800, 1500 × 1000, 480 × 640, the 20 MP soak),
the `.serialized` traits and the `LARGE_RENDER_TESTS` gate are as before.
`WorkLane`, `WorkLaneTests` and `ResidentDecode` are untouched.

- **`differingCount` is the old `!=`.** It is the same per-element Float `!=`
  as `zip(a, b).filter { $0 != $1 }.count`, so 0 and −0 are equal, NaN differs
  from NaN, and every index is counted. `differingCountCountsEveryDifference`
  pins this (`[0, .nan]` against `[-0, .nan]` gives 1). An empty array gives 0
  through the `baseAddress` guard. The one difference is a length mismatch,
  which the old `zip` cut to the shorter array and this traps on (C5).
- **The tolerance table is `allowedSteps` exactly.** `compare` calls
  `allowed(wholeValue)` with a `UInt8`. `allowedSteps(gain:encoded:)` is a
  pure function of `gain` and that byte. The table is built for all 256 bytes,
  inside the loop, so each stack gets its own `gain`. `allowed[Int($0)]` is
  always in range. The same value for every input, computed once per byte.
- **`offCooperativePool` is correct.**
  - *APIs.* `withTaskExecutorPreference`, `TaskExecutor`,
    `UnownedJob.runSynchronously(on: UnownedTaskExecutor)` and
    `asUnownedTaskExecutor()` are macOS 15 / Swift 6.0 (SE-0417), the
    package's minimum. There is no `#available` and no `Test.cancel`.
  - *Sendable.* `BlockingWorkExecutor` is a `final class` with only `let`
    Sendable state (a `DispatchQueue`, a `String`), so it needs no
    `@unchecked`. The `queue.async` closure captures only `UnownedJob` and
    `UnownedTaskExecutor`, which are both Sendable. No `nonisolated(unsafe)`.
  - *Isolation.* Every caller is a nonisolated test method, so `#isolation` is
    nil and the body runs on the preferred executor. An actor-isolated caller
    would keep its actor. The doc comment says as much ("its nonisolated
    code").
  - *Reporting and saturation.* I checked both in a scratch package outside
    the repository, with `BlockingWork.swift` copied in unchanged:
    - A failing `#expect` and a failing `#require` inside `offCooperativePool`
      are recorded against their own test, at their own line.
    - 200 child tasks of a group in the body, each blocking for 0.2 s, all ran
      on `tests.blocking-work`. So child tasks inherit the preference. They
      finished in 1.04 s: Dispatch adds threads as its threads block, and no
      deadlock occurs.
    - While 28 blocking bodies ran, 50 tasks on the cooperative pool finished
      in 0.1 ms.

    No body waits synchronously on work that needs this queue: the bodies
    wait on the GPU, on files or on their own awaits.
  - *What `BlockingWorkTests` covers.* It checks the queue label (also after
    an await), that `Test.current` is the same test, and that errors pass
    through. The engineer also reports that the guards still fail with the
    copy turned off. I did not repeat that, because it needs a source edit.
    The scratch check above covers the same reporting path.
- **The causal claim is supported and stated with fair hedging. It is
  correlational, not proven.**
  - What holds:
    - In this branch's four CI jobs (run 44992559236, both attempts, both
      systems) the test failed every time.
    - Every `develop`-era job I checked passed: runs 44934276425 (221 s and
      242 s), 44919066660 (156 s, 188 s), 44926001368 (221 s, 218 s) and
      44556278405 (190 s). Each time the test, which needs about 0.1 s
      alone, spent minutes waiting.
    - The new `Full-size ImageIO decodes` suite starts beside
      `LensAlignStaleAreaTests` in every failing job.
    - The pool is starved locally too. In my full run the trivial
      `BlockingWorkTests` took 64 s and the WorkLane test 80 s, which matches
      the follow-up's point that other suites still block the pool.
  - Where the evidence is weaker than it reads:
    - GitHub's log timestamps are batched. For example, "One context renders…
      started" and its "passed after 1.901 seconds" are stamped 10 ms apart.
      So "finished within 0.1 s to 3 s of the end of `LensAlignStaleAreaTests`"
      shows ordering at most, not timing.
    - The narrowed-pool reproduction slowed the cancellation from 1.2 s to
      7.9 s and 6.1 s but never went past 10 s. It shows the mechanism, not
      the failure.
    - The fix takes this branch's suites off the pool. It does not remove the
      starvation that `develop` already has, so the 10 s margin stays
      load-dependent. `status.md`'s "CI is the real check" is right; the
      Review findings row's **Fixed** gets ahead of it (C6).
- **The proposed follow-up is sound.** The title, the `bug` label, "tests
  only", and the named suites agree with the samples, and both remedies are
  given. I'd put the wall-time-independent WorkLane test first: it removes the
  failure whatever the load. Moving suites off the pool only lowers the odds.
  One more data point for its body: in a local full run on 14 cores, trivial
  tests waited 64 to 80 s.

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C5 | Nit | `Tests/PhotoCoreTests/ImageIOFullDecodeTests.swift:92` | `differingCount` checks the lengths with `precondition`. In `renderUnchanged` (`:226`) the two arrays are sized from each image's own extent, so a regression where the decode's extent differs from the file's is a trap, not a recorded issue. The old `zip` compared the shorter prefix and still counted differences. | A decode whose extent no longer matches the file (an orientation or frame regression) gives `differingCount` arrays of different lengths. The `precondition` stops the test process, so `swift test` ends there: the issue is not attributed to the test and the other suites' results are lost. Fix: `#expect(a.count == b.count)` at the call sites (or `try #require` in the helper), then count over `min(a.count, b.count)`. | Tests: a failure reports as a failure |
| C6 | Nit | `docs/features/core-image-split-render/status.md:297`, `:316`, `:433` | The CI record has three small slips. (1) "on macOS 26 only `:373`" is true of the rerun only: attempt 1 on macOS 26 (job 137116586292) recorded `:371` and `:373`. (2) The CI times quoted (`residentCopyIsTheFile` 12.6 s and 9.8 s, `renderUnchanged` 22.4 s and 12.2 s) are the rerun's; attempt 1's were 20.1 s and 19.9 s, and 24.9 s and 26.7 s. That understates the case rather than overstating it. (3) The Review findings row says **Fixed** for a commit CI has not run on, while the CI section says CI is the real check. | A reader (QA, the owner, the PR description) takes the CI failure as fixed before any CI run of `42657d3`. If it fails again, the record says otherwise. Fix: "macOS 26's rerun only `:373`", give both attempts' times, and "Fixed in tests, pending CI on `42657d3`" until the PR's CI is green. | Record keeping |

**Verdict, third pass.** The CI fix is correct and weakens nothing. Every
assertion, tolerance and image size is unchanged, `differingCount` and the
tolerance table are the same comparisons, and the executor is sound on
macOS 15 and under strict concurrency. C5 and C6 are nits and don't block. The
branch can be pushed for CI. That run is the real test of the fix: if the
WorkLane test fails again, the remedy is the follow-up's wall-time-independent
WorkLane test, not more suites moved off the pool. The change has no behavior,
so qa-tester and the owner need nothing new, unless the fix for a renewed CI
failure touches `Sources/`. `/security-review` is not needed: no parser,
subprocess, file writing or network code.
