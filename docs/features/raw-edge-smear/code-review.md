# RAW edge smear: code review

Owner: code-reviewer. Date: 2026-11-10. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/raw-edge-smear`, the uncommitted working tree on `13b1f90`
(nothing is committed yet, so base and head are both `13b1f90`). Build and
tests, run here on macOS 27.2: `swift build` complete; `swift test` 688 tests
in 114 suites passed, 1 known issue (the existing one in `LiveSessionTests`);
`RAW_EDGE_SAMPLES=<Kayaking>/P1040027.RW2:<Kayaking>/P1040058.RW2 swift test --filter RAWEdgeSmearTests`
6 tests (7 cases) passed. The source tree was not changed: mutations and
experiments ran in a copy outside the repository.

## Verdict

The fix does what the Bug section asks, and every place a RAW decode is
rendered uses the decode's own engine. Not ready for qa-tester yet: a context
made and dropped per RAW decode leaves memory behind that is never given back
(C1), which `status.md` says does not happen. C1 needs a fix, or the owner's
decision to accept it as a known cost.

Second pass, 2026-11-10: the fix was reworked and is ready for qa-tester. See
Follow-up, which replaces this verdict.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Should fix | `Sources/PhotoCore/Preview/PreviewGenerator.swift:228` (`engine.isolated()`), `Sources/PhotoCore/Preview/RenderEngine.swift:98`, `Sources/PhotoCore/Edits/AutoAdjust.swift:117`; `status.md` lines 190 to 193 ("No memory growth") | Every RAW decode that is rendered makes a `CIContext` and drops it, and each one leaves memory behind for the life of the process. The growth is linear with no plateau. See "C1 measurements" below. | 24,000 RAW previews in one process (a 1200 × 800 synthetic DNG, `jpegData(source:stack:tiers:)` for preview and thumbnail, 7 at a time): the footprint goes 421 MB at 2,000, 847 MB at 10,000, 1,589 MB at 24,000, about 53 KB per decode. With the shared pool it stays between 417 and 433 MB from 500 to 6,000. An import of 10,000 raws ends about 530 MB higher, and it is never released until quit; a White Balance drag adds one context per frame. | Correctness (engine and context lifetime); `status.md` states the opposite |
| C2 | Nit | `Sources/PhotoCore/Preview/PreviewGenerator.swift:117` (`hdrImage`); `Tests/PhotoCoreTests/RAWRenderIsolationTests.swift` | No test fails without this part of the change. | With `decoded.engine.makeHDRCGImage(image)` changed back to `engine.makeHDRCGImage(image)`, `RAWRenderIsolationTests` still passes (run). The HDR tests use a gain-map JPEG and an integer DNG that returns nil before rendering, so none can tell. A floating-point DNG would then render through the shared interactive engine again unnoticed. Eleven of the other twelve call sites are each caught by a test, and the twelfth cannot go wrong (see "Checked and fine"). | Tests: a test that fails without the change |
| C3 | Nit | `docs/features/raw-edge-smear/status.md` lines 112 to 116 | "At `13b1f90` plus the test file alone, 5 of its 7 cases fail" cannot be run as written. | `RAWRenderIsolationTests.swift` also holds the `RAWRenderIsolationTests` suite, which uses `RenderEngine.isolated()`, `renderCount`, `Decoded.engine` and `decode(…engine:)`: none exist at `13b1f90`, so the file does not compile there. The claim itself holds (I got the same 5 of 7 with `decodeRAW` handing back the caller's engine); the Bug section should say how to reproduce it, since QA checks against it. | `docs/WORKFLOW.md`, Bug fixes: the test that fails without the fix |

### C1 measurements

All on this Mac, macOS 27.2, debug build.

- **Soak, branch.** One 1200 × 800 `SyntheticDNG`, a generator on
  `RenderEngine(contextCount: 7)`, a task group keeping 7
  `generator.jpegData(source:stack:tiers: [.preview, .thumbnail])` calls
  running, `phys_footprint` (`task_info`, `TASK_VM_INFO`) every 2,000:
  421, 491, 629, 745, 847, 911, 1,026, 1,121, 1,279, 1,328, 1,486, 1,589 MB
  at 2,000 to 24,000. Throughput also falls, from 159 a second over the first
  6,000 to 126 a second over all 24,000.
- **Soak, shared pool** (the same code with `decodeRAW` returning the caller's
  engine): 417, 427, 423, 425, 433, 429, 433, 429, 428, 431, 432, 433 MB at
  500 to 6,000.
- **`photobench previews --tier preview --format dng --fresh`** on 900
  synthetic DNGs, peak memory footprint (`/usr/bin/time -l`) at `--limit`
  300, 600, 900: branch 467, 480, 543 to 555 MB; shared pool 462, 467, 473 MB.
- **It is Core Image's, not this code's.** A standalone program with no
  project code (`CIContext(mtlDevice:options:)` with the engine's options, one
  `jpegRepresentation` of a 256 px image, the context dropped, each turn in an
  `autoreleasepool`, 3,000 turns): one shared context leaves 0 KB a turn; a
  new context per render about 21 KB a turn; `clearCaches()` before dropping
  it 22 KB; without a `.name` 20 KB; a context that renders nothing leaves
  nothing. So the cost comes with a context's first render, and neither
  `clearCaches()` nor an autorelease pool gives it back. The RAW graph leaves
  more (53 KB) than the trivial one.
- The GPU driver prints `AGX: exceeded compiled variants footprint limit` once
  within 3,000 RAW previews on the branch, and not with the shared pool.
- `status.md` measured 270 renders, where the branch is indeed lower than the
  pool (here too: 307 MB against 417 MB at 500). The growth shows only past
  that.

Not measured: macOS 26 and 15, a release build, real 20 MP raws over
thousands of renders.

## Questions

For the owner (relayed from `status.md`, not findings):

1. **Pipeline version 8.** `status.md` says the owner allowed the bump, and
   also lists it as an open question. It needs one answer on record before
   sign-off. The bump is right for what it is for: the smeared previews sit
   under the identity stack's hash, so nothing else replaces them.
2. **C1's trade-off**, if the engineer finds no way to bound it: accept a
   known cost of about 53 KB per RAW decode rendered, or choose one of the
   candidates `status.md` rejected. This is the owner's call, not mine.
3. **`CLAUDE.md`.** The engineer proposes changes to the owner's part
   (Architecture rules, Rendering: "one Metal-backed `CIContext`" is no longer
   the whole rule; a `RAW_EDGE_SAMPLES` command and its allow entry in
   `.claude/settings.json`). I agree the Rendering rule should name
   `Decoded.engine`: nothing else stops a new caller from rendering a decode
   through the shared engine.

For the product manager (Requirements issue):

4. Photos whose Color Alignment was measured automatically before this fix
   can hold slightly wrong stored values (`status.md`, open question 2: red
   5.19 for 5.13, blue −2.55 for −2.43 in the one case measured). The fix
   does not touch stored edits. Whether that needs anything (a note, a way
   to measure again) is a requirements decision.
5. The fix changes what `CLAUDE.md` says about rendering, so step 6 (Ship)
   applies by `docs/WORKFLOW.md`'s rule, although the bug has no roadmap row.

## Checked and fine

- **The Bug section's test fails without the fix.** With `decodeRAW` handing
  back the caller's engine, `RAWEdgeSmearTests` on the Kayaking pair fails 5
  of its 7 cases (previews, export at 2048 px, live frames, the 100% region,
  Color Alignment) and passes the two `status.md` says pass either way; with
  the fix all 7 pass. `RAWRenderIsolationTests` fails 4 of its 6 tests with
  that change, as `status.md` says.
- **Every call site is pinned**, one mutation at a time (each changed back to
  the shared engine, `RAWRenderIsolationTests` run): `encodedRendering`,
  `cgImage`, `ExportRenderer.export`, Auto Exposure, Auto White Balance's
  `isolated()`, `ColorAlignmentMeasurement`, `FringePicker.samplePixels`,
  `LiveRegionRenderer`'s texture, `LiveRenderSession.base`,
  `SharpeningMapRefiner`'s kept input and its whole renders each fail a test.
  Two do not: `hdrImage` (C2) and `photocli render`, which makes a new engine
  per call, so nothing can go wrong there.
- **No RAW render path is left on a shared context.** `CIRAWFilter` is built
  in three places: `decodeRAW` (and `CameraFrame.fullFrameFilter`, only ever
  called from it), `AutoAdjuster.whiteBalance` (its own isolated engine, one
  file), and `RawDefaults`, `nativeSize` and
  `MachineLearningNoiseReduction` (properties only, nothing rendered). `PreviewGenerator.decode` is internal and has no default for
  `engine`. The renders still on `generator.engine` all start from pixels:
  `LiveRenderSession`'s frames and stages (a `CGImage` base),
  `LiveRegionRenderer.render` (the texture), the sharpening map from its kept
  input (`deferred: false`), `FringePicker.swatch` (no photo). PhotoApp renders
  nothing from a decode itself. `PreviewGenerator.image(source:)` drops the
  engine; only tests call it.
- **One isolated context renders several times, always the same file**
  (preview then thumbnail in `encode`, Auto White Balance's solve, a deferred
  image's tiles), which is not the fault's condition.
- **Deferred renders** (a side over 4096 px: the 1:1 rendition, full-size
  exports, large live bases). With `CI_PRINT_TREE=1`, two full-size renditions
  made before either was read each rendered when read in a context of its
  own (`metal context 11:shared-raw-0` and `15:shared-raw-0`), so the claim
  that a deferred render runs in the context that made it holds. With the fix,
  `cgImage(source:)` of the second raw at full size, 5000 px and 4200 px
  equals the render made alone exactly. This pair does not show the fault at
  those sizes without the fix either, so no test could fail there.
- **`RenderEngine.isolated()`**: same device, same options, software renderer
  kept; `@unchecked Sendable` still holds (immutable contexts and name, counts
  under one mutex). `renderCount` is internal and read only by tests.
- **`LiveRegionRenderer`**: the texture is made on the isolated engine's
  device, which is the shared engine's, and is read only after
  `waitUntilCompleted`.
- **Swift 6 concurrency**: no new main-actor work, no new `@unchecked` or
  `nonisolated(unsafe)`; `Rendering` and `Decoded` carry a `Sendable` engine.
- **Pipeline version** 7 to 8, with the reason in the constant's comment, as
  7 has. No rendering changed: the real-file renders equal those made alone.
  No golden, tolerance or reference changed (nothing under
  `Tests/PhotoCoreTests/Goldens` or `Reference` is in the diff), and no test
  names a version number.
- **Tests**: Swift Testing, no sleeps, no timing. The real-file suite compares
  against a render made alone instead of an absolute score, and only reads
  the originals (exports go to a temporary folder). The four changed test
  files only pass an engine.
- **Other rules the diff touches**: no migration, edit operation, sidecar,
  undo, UI string, brand value or dependency changed; originals are only read.
- **Security**: no parser, subprocess, file writing outside the library or
  network code was added or changed. `/security-review` is not needed.

Not checked: macOS 26 and 15 (the pull request's CI is the first run there,
and it has no camera raws); the app was not launched.

## Follow-up

### Second pass, 2026-11-10

Reviewed: the reworked fix, still the uncommitted working tree on `13b1f90`.
The owner chose a render graph of its own for every decode (`status.md`,
"C1", choice 2), and the engine isolation the first pass reviewed is gone:
the diff against `develop` is now `Sources/PhotoCore/Preview/RAWDecodeGraph.swift`
(new), one line each in `PreviewGenerator.decodeRAW` and
`AutoAdjuster.whiteBalance`, the pipeline version, and
`Tests/PhotoCoreTests/RAWDecodeGraphTests.swift` (new). The sections above
describe the first version and are left as they were.

Build and tests, run here on macOS 27.2: `swift build` complete, no warning in
a changed file; `swift test` 689 tests in 115 suites passed, 1 known issue
(the existing one); `RAWEdgeSmearTests` on the Kayaking pair 6 tests (7 cases)
passed; `RAW_CONTEXT_SOAK=12000` with the pair, both tests passed. Mutations
and experiments ran in a copy outside the repository.

**Second-pass verdict: ready for qa-tester.** One Nit (C4). The fix stops the
fault on this Mac, leaves no memory behind, and costs no speed.

| # | Status | Notes |
| --- | --- | --- |
| C1 | Fixed (uncommitted) | By replacing the approach: no context is made per decode any more. Soak, 12,000 RAW previews of the synthetic DNG, 7 at a time: 428, 432, 430, 434, 427, 432, 433, 434, 432, 435, 431, 428 MB, 0 KB a preview, 223 previews a second (the shared pool on `develop`'s code gave 222 in the first pass). No `AGX` message. `status.md` no longer claims what C1 disputed, and its "C1" section records my figures correctly. |
| C2 | Withdrawn | `hdrImage` is as on `develop` and renders on the shared engine by design. It reaches the decoder through `decodeHDR`, `decode` and `decodeRAW`, where the key is applied, like every other path. |
| C3 | Fixed (uncommitted) | The Bug section now gives a reproduction that runs. Followed as written (`decodeRAW` taking `raw.outputImage`): 5 of the 7 `RAWEdgeSmearTests` cases fail (previews, export at 2048 px, live frames, the 100% region, Color Alignment), the two guards pass, and `rawFiltersAreMadeInKnownPlaces` fails. |

New finding:

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C4 | Nit | `Tests/PhotoCoreTests/RAWDecodeGraphTests.swift:415` and `:461` to `:465` (`RAWContextSoakTests.previews`) | The soak's limit is a fixed 100 MB between the first quarter and the end, whatever the count, and the count may be as low as 1,200. The per-preview figure is printed but not checked. | At the 50 KB a preview the test exists to catch, growth over the last three quarters is 45 MB at 1,200 previews, 75 MB at 2,000 and 100 MB only at about 2,700: below that the test passes with the leak present. The first version's own curve (312 MB at 500, 433 MB at 3,000) sits on the limit at 3,000. It needs 12,000 or more to be a guard, or a limit on the per-preview figure. | Tests: a test that fails without the change |

What was asked, and what I found:

- **Every `CIRAWFilter` render path is covered.** A RAW filter is made in six
  places in four files. Two render its image, and both take it from
  `RAWDecodeGraph.output(of:)`: `decodeRAW` (which also receives
  `CameraFrame.fullFrameFilter`'s whole-sensor filter, its only caller) and
  Auto White Balance. The other four read values only (`nativeSize`,
  `RawDefaults`, `MachineLearningNoiseReduction`, and `CameraFrame` handing
  its filter on). `FringePicker.samplePixels`, `ColorAlignmentMeasurement`,
  `LiveRenderSession.base`, `LiveRegionRenderer`, both `SharpeningMapRefiner`
  decodes, `hdrImage`, export and `photocli render` all go through
  `PreviewGenerator.decode`, unchanged from `develop`.
- **The key is unique across concurrent decodes.** One atomic counter for the
  process; 2⁴⁴ serials before a repeat. It is the uniqueness that does the
  work, not the clamp: with every decode given the same key, the four real-file
  tests run (previews, exports, live frames, the 100% region) fail again. Keys that differ only in the second digit (what
  happens after 4,194,303 decodes) pass on the real files. Core Image's own
  printed digest (`recipe=` in `debugDescription`) differs for keys one
  `Float` step apart, is equal for equal keys, and was distinct for 200,000
  neighbouring keys: direct support for the second assumption in
  `RAWDecodeGraph`'s comment.
- **The clamp is safe for HDR and extended range.** The bounds are finite
  (below 1.4 × 10³⁰) and far above any pixel; negative values and values
  above white pass. `CIColorClamp` is a color kernel, so it adds no render
  pass and changes no extent or region of interest. The image stays opaque:
  `alphaInfo` of 8-bit, 16-bit, BGRA and HDR renders is the same keyed and
  not, and an exported TIFF still has no alpha channel.
- **The tests fail when the key is removed**, one mutation at a time:
  `decodeRAW` or Auto White Balance taking `raw.outputImage` fails the source
  check; `keyed` without the clamp fails two tests; one key for every decode
  fails `keysAreNotSharedAcrossThreads`; `output(of:)` ignoring its key fails
  `decoderOutputIsKeyed`. One limit, which the test's own comment admits: the
  source check is text. A call site that passes one fixed key passes every CI
  test while the smear is back (tried); only the real-file suites see that.
- **"No memory growth" now holds** (C1 above). With real 20 MP raws the 7
  contexts hold about 3.5 GB while they work; that is the same without the
  key (3.3 to 3.5 GB measured on `develop`'s decode line), so it is not from
  this change.
- **The output difference is honestly described, and I get the same.** The 54
  Kayaking raws, preview and thumbnail, each rendered alone, with the key
  against without: 76 of 108 files pixel for pixel the same, 32 differ, by at
  most 1 level in 14 files, 2 in 13, 3 in 3, 4 in 2; a median of 0.0017% of
  their values and at most 0.033%. `status.md` says 29 of 102 healthy files,
  1 to 4 levels, median 0.002%, at most 0.03%. By this file's rules it is
  acceptable: the pipeline version is bumped, no golden or tolerance changed,
  and the RAW goldens were compared on this Mac (their fingerprint is 27.2,
  26B123) and pass. Whether byte-for-byte output matters is the owner's
  question (`status.md`, open question 1).
- **Pipeline version 8**: the constant's comment gives the reason and says
  nothing else looks different, which is accurate.
- **Swift 6 concurrency**: one `Atomic<UInt64>`; nothing else shared. No new
  `@unchecked` or `nonisolated(unsafe)`.
- **Security**: nothing that calls for `/security-review`.

Still open, none of it a finding:

- **macOS 26 and 15.** The fix rests on two things observed on 27.2 only, and
  CI has no camera raws. The real-file suites are the only guard, so the
  owner's part of `CLAUDE.md` should carry the rule and the two commands the
  engineer proposes (`status.md`, README), with allow entries for
  `RAW_EDGE_SAMPLES` and `RAW_CONTEXT_SOAK` in `.claude/settings.json`.
- **For the product manager**, unchanged from the first pass: stored Color
  Alignment values measured before the fix, and that step 6 (Ship) applies if
  `CLAUDE.md` changes.
- Not checked: RAW files the RAW decoder gives no image for, which ImageIO
  decodes outside the app's contexts; the app was not launched.
