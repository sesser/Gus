# GPU demosaic for raws LibRaw decodes: QA

Owner: qa-tester. Date: 2026-11-16. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/gpu-demosaic` at `2397983`, on an Apple M4 Pro (14 cores, 24 GB), macOS 27.2.1, Swift 6.4.2, MacOSX 27.2 SDK (`vtool`: minos 15.0, sdk 27.2). Against the PRD (issue #196) as revised on 2026-11-16 (rev 2: AC3 accepted as measured, AC4 only at ISO 800 or lower, AC6 detail recorded for 5 files), `status.md` and `code-review.md` (first and second pass).

Safety: every `photocli`, `photobench` and app launch used `--library-root` on a scratch folder made by `photobench`, or opened no library (`photobench demosaic`, `swift test`). The real samples were only read (28 staged copies in the session scratch folder; the Bayer samples in the owner's samples folder). After the run no `Gus`, `photobench` or `photocli` process is running, and nothing under `~/Library/Application Support/Gus` or `~/Library/Caches/me.sesser.gus` is newer than when I started (checked with `find -newer` against a marker file made first; the owner's catalog's newest file dates from 15:11 that day, before the run). Nothing in `Sources/`, `Tests/`, `Scripts/` or `Package.swift` was edited; `git status` is clean.

## Verdict

Passes, with one criterion not met as written and awaiting the owner: AC2's edge chroma bound on the E-M5 III (2.04 against LibRaw AHD's 1.97, 1.04x; Q2 below). AC3, AC4 and AC6 are met as the owner accepted them in rev 2, and I reproduced the engineer's numbers for them on five real files. Speed, memory and fallback hold (X-E3 full size 0.62 s against 7.7 s). One test-power finding (Q1, not blocking). What only a person can look at is four items (P1 to P4).

## Acceptance criteria

How is Test, Script (a `photobench`/`photocli` measurement or a debug-script run, below) or Person. All test names are Swift Testing suites under `Tests/PhotoCoreTests`. The full `swift test` at this commit passed: **1072 tests in 161 suites** (65 s), none skipped on this Mac.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 (`reads` decides; unsupported CFA keeps LibRaw's own) | Test | `GPUDemosaicDecodeTests.whichDemosaic` (Bayer and X-Trans take the GPU; a linear DNG takes LibRaw's, pixels byte for byte equal to the debug switch); `.systemDecoderStillDecides` (a file the system reads gets `decoder == .systemRAW` and no demosaic); `LibRawDecoderTests` (a raw goes to LibRaw only when the system has no image). Reads: `PreviewGenerator.rawImage` changed only by a `try` on the LibRaw branch, so system-read raws and JPEGs are untouched | Pass |
| AC2 (Bayer vs AHD on a known truth: CPSNR >= AHD - 0.1 dB, edge chroma p95 <= 1.0x) | Script | S1 (`photobench demosaic --mode truth --nr off`). GX85: 33.83 against 33.23 dB, edge chroma 16.73 against 17.94. 5D II: 41.95 against 41.96, 8.28 against 8.34. E-M5 III: CPSNR 47.99 against 47.92 but edge chroma **2.04 against 1.97 (1.04x)**. `DemosaicTruthTests` (`BAYER_SAMPLES`) expects AC2 as written, so it reports the E-M5 III | **Fail** for the E-M5 III's edge chroma only (the PRD gives no spike figure for it); Pass for the two files it names. Awaits the owner (Q2) |
| AC3 (X-Trans kernel quality), accepted as measured (rev 2) | Script | S1 and S2 (`--mode real --nr off`). Synthetic: X-Trans kernel alone 0.26 (GX85), 1.09 (5D II) and 0.33 (E-M5 III) dB under LibRaw's three passes, edge chroma 1.03x, 1.11x, 1.25x: reproduced exactly. Real (five files, kernel alone): false color 0.53x to 0.86x, detail 0.82x (X-E3 ISO 200 `DSCF3141`) and 0.90x (X-T3 `DSCF4583`), 0.97x to 1.04x on the other three: the same gap the PRD records | Pass as ruled (not met as first written; #199 closes the gap) |
| AC4 (ours vs LibRaw's own, ISO <= 800: blocks median <= 1 and p95 <= 2, edge median <= 5) | Script, Test | S2 on four files at ISO <= 800 with the noise step: X-E3 `DSCF5123` ISO 400 blocks 0.27 / 1.43, edges 3.42; X-E3 `DSCF3141` ISO 200 0.15 / 0.37, edges 1.41; X-T3 `DSCF0664` ISO 160 0.17 / 0.64, 2.30; X100S `X1000304` ISO 800 0.29 / 1.76, 3.10. All meet it. `DemosaicXTransSampleTests.quality` (`XTRANS_SAMPLES`, S4) expects it for every file at ISO <= 800 except the three the PRD accepts, and passed on three files. X-T3 `DSCF4583` (ISO 6400) gives 0.95 / 2.33, edges 8.42: outside AC4's scope by RI-2. I did not rerun all 28 files | Pass as ruled |
| AC5 (X-T3 vs the system decoder at 5500 K: < 20 and <= LibRaw's + 1) | Test | S3: `LibRawAgainstSystemTests` with `RAW_BOTH_SAMPLES` on `DSCF4583`: ours **10.4**, LibRaw's own 10.0 (`RAW_DEMOSAIC=libraw`), +0.4 | Pass |
| AC6 (false color <= 1.0x LibRaw's with detail >= 0.95x; flat patches <= 1.0x), accepted as measured (rev 2) | Script, Test | S2 with the noise step: false color 0.75x, 0.29x, 0.17x, 0.59x, 0.73x on the five files (all <= 1.0), detail 1.02x, 0.95x, 1.02x, 0.99x, 1.03x (none under 0.95 by the suite's own count: it printed "none" for three of them). Both named files meet the Must (`DSCF5123` 0.75x at 1.02x; `DSCF4583` 0.17x at 1.02x). Flat patches: `ColorNoiseReductionTests.flatColorNoise` ours 0.20x (X-Trans) and 0.25x (Bayer) LibRaw's. See Q1: that test does not fail with the noise step off | Pass as ruled; test power see Q1 |
| AC7 (thin colored lines and edges survive the noise step) | Test | `ColorNoiseReductionTests.keepsLinesAndEdges` ("Thin colored lines keep their color and edges stay put", RGGB and X-Trans): line contrast 100% to 101% of the input (>= 85%), edge ΔE median 1.24 / 1.29 (<= 3), p95 without noise 1.02 / 0.94 | Pass |
| AC8a (each kernel against its plain-Swift reference; half-float 2^-10) | Test | `DemosaicKernelTests.matchesReference` (5 patterns, derived per-value bound, the bound's derivation is in the test's comment), `.halfOutput`, `.halfSize` bins (3 ULP); `ColorNoiseReductionTests` one level (1, 2, 4), bands against one pass, half output. Mutation M1 (X-Trans green weight 1/e instead of 1/e²) in a scratch copy fails `matchesReference` for all three X-Trans patterns | Pass |
| AC8 (clean room; sources named) | Person (review) | `code-review.md` "Clean room (AC8)": no copied code found; `status.md` "Published sources" names them; `THIRD_PARTY_NOTICES.md` unchanged. I did not judge provenance myself | Pass (by code review) |
| AC9 (X-E3: 6000x4000 and the lens corrections) | Test | S5: `LibRawFallbackTests` with `RAF_SAMPLE` on `DSCF5123`: 9 tests pass, `theFrameIsTheCameras` (6000 x 4000), corrections applied, alignment with the camera's JPEG median 0.299 px, p90 0.758 (LibRaw's own demosaic, same file: 0.308 / 0.830). `DemosaicXTransSampleTests.frameAndFallback` passed. Also S7: `photocli render` gives 6000 x 4000. The test's "far from the center ... nan" line prints `nan` with either demosaic (it is guarded and unchanged by this branch) | Pass |
| AC10 (white balance change runs no new unpack or demosaic) | Test | `GPUDemosaicDecodeTests.whiteBalanceRunsNoDemosaic`: a run counter unchanged across Kelvin, Tint and Mode changes at fit and at full size, `decodeCount == 1`, and the frame equals a fresh session's. S6 (live): a white balance frame at fit 8.2 to 9.0 ms with our demosaic, 9.9 ms with LibRaw's | Pass |
| AC11 (Adjust tab, stack unchanged) | Script, Test | S8 (X-E3 in the bundle copy, Adjust tab): note "macOS can't decode this raw file ... Color noise reduction isn't available.", `ml` state `unavailable(cameraNotSupported)`, caption "Not available for this camera.", Use machine learning check box present, off and disabled, Color slider not shown. Unedited stack is `{"operations":[],"schemaVersion":1}`; after setting Kelvin and Luminance only a `whiteBalance` and a `noiseReduction {luminance}` operation exist: no new keys. Tests: `EditStackCorpusTests` (bytes and hashes unchanged), `LibRawDecoderTests.machineLearningReasonIsTheCamera` | Pass |
| AC12 (GPU fails or no device: LibRaw's pixels, logged, next file uses the GPU) | Test | `GPUDemosaicDecodeTests.fallbackOnFailure` (execution failure and no device, Bayer and X-Trans: `pixels.data` equal to `--demosaic libraw`, the `OSLogStore` line read back, the next decode ours), `.scratchAllocationFallsBack` (the noise step's scratch fails after the demosaic is encoded: the process lives); `DemosaicXTransSampleTests.frameAndFallback` on the real X-E3. Mutation M5 (log line removed) fails `fallbackOnFailure` | Pass |
| AC13 (cancellable, <= 400 MB, no new warnings) | Test, Script | `GPUDemosaicDecodeTests.cancellation` (a decode cancelled after the unpack throws `CancellationError`, runs no demosaic), `.stoppedExportIsNotAFailure` and `.stoppedPhotoTally` (code review C2); mutation M4 (both `Task.checkCancellation()` removed) fails both. S9 (`--mode memory`, fresh process): X-E3 peak 296 MB above, X-T3 315 MB (LibRaw's own 550 and 595 per `status.md`). Warnings: the code reviewer's clean build into a separate path showed none, and my builds show none; I did not force a clean rebuild myself | Pass (the bound is measured in `photobench`'s process, not in the app) |
| AC14 (pipeline version 12, nothing found from 11; guide says previews regenerate) | Test | `GPUDemosaicDecodeTests.pipelineVersion`; mutation M2 (version back to 11) fails it three ways. `docs/USER_GUIDE.md` diff has the paragraph "every preview and thumbnail in the library is made again once" | Pass |
| AC15 (timings against R14 to R18 in `status.md`) | Script | S6, release build, files in the cache, first run then median of the other five. X-E3 full **0.616 s** (R14 <= 1.0; LibRaw 7.72 s), half 0.553 s (LibRaw 0.581); X-T3 0.650 s (8.25), half 0.583 s (0.614); GX85 0.096 s (0.398), half 0.075 (0.108); 5D II 0.314 s (0.615), half 0.284 (0.288); E-M5 III 0.343 s (0.621; min 0.312, one 0.599 outlier in six), half 0.298 (0.303). Every full and half size is at or under LibRaw's own and R14 to R16 hold. GPU time (R17): X-E3 75.5 ms, X-T3 80.8, GX85 22.8, 5D II 30.2, E-M5 III 29.2. 100% region: decode 746 to 755 ms (LibRaw 7944), first region 4 ms (5), white balance region 2.5 ms (2.5) | Pass |
| AC16 (small tests run everywhere; 24 MP only opt-in) | Test | The three new suites run on 96 x 96 and 516 x 516 synthetic mosaics in every `swift test`; each GPU suite is `.enabled(if: hasMetalDevice, "reason")`; the tests that need a raw only LibRaw decodes are `.enabled(if: !systemReadsSmallXTrans, "reason")` (no `Test.cancel`, code review C10); real files only behind `XTRANS_SAMPLES`, `BAYER_SAMPLES`, `RAF_SAMPLE`, `RAW_BOTH_SAMPLES`. I could not run the CI runners' paravirtual GPU or the Swift 6.2.4 toolchain of the macOS 15 job here: the pull request's CI is that check | Pass here; CI is step 7 |

Counts: 17 rows. Passed by test 10 (AC1, AC5, AC7, AC8a, AC9, AC10, AC12, AC13, AC14, AC16), by script or measurement 2 (AC11 with tests, AC15) plus 3 met as the owner accepted them in rev 2 (AC3, AC4, AC6), by review 1 (AC8). Failed 1 (AC2, E-M5 III only, Q2). Open for a person 0 (the look checks are P1 to P4).

Mutation checks (scratch copy of the branch under the session scratch folder, never the checkout; each mutation restored): M1 X-Trans weight 1/e: caught. M2 pipeline version 11: caught. M3 baseline noise step off by default (`decodeNoiseReduction = nil`): **not caught**, see Q1. M4 no cancellation checks: caught. M5 fallback log line removed: caught.

## Findings

For the engineer.

- **Q1 (Should add, test power). Nothing in the always-run suites fails if the baseline color noise step is switched off in the decode.** Mutation M3 (`GPUDemosaic.decodeNoiseReduction` defaulting to `nil`) leaves all of `ColorNoiseReductionTests` green: `flatColorNoise` only asks for "ours at most LibRaw's" (the PRD's 1.0x), and the kernel alone already measures 0.85x (RGGB) and 0.69x (X-Trans); with the step on, 0.25x and 0.20x. The other noise tests call the step explicitly, and the kernel-level tests check its math, not that a decode uses it. So R9 ("a baseline step runs in the new path") is covered by the opt-in sample suite only, and there on some files. Steps: in a scratch copy set the default to `nil`, run `swift test --filter ColorNoiseReductionTests`. Expected: a failure. Actual: 5 tests pass. Suggestion, inside the PRD's bound: have `flatColorNoise` also expect the measured margin (for example at most 0.5x LibRaw's, between 0.25x and 0.69x), or compare a default decode with one under `$decodeNoiseReduction.withValue(nil)` and expect it strictly quieter. Not a failure of the feature, which behaves correctly (S8, S7 and the real-file measures use the step).
- **Q2 (owner or product manager, with code review Q3). AC2 on the E-M5 III.** Edge chroma error p95 is 2.04 against AHD's 1.97 (1.04x) on that truth; CPSNR passes. The PRD's spike figures leave this file out. `DemosaicTruthTests` stays red on it when `BAYER_SAMPLES` includes the E-M5 III. Options as in `status.md`: accept as measured, or limit AC2's edge bound to the files with spike figures. Nothing loosened. The three AC4 files (code review Q3) want the same kind of answer.

No Design questions. No Requirements issues beyond Q2. The PRD's R21 wording ("above the app's baseline") is measured against the benchmark process's footprint before the decode (88 MB), not the app's; it is met by a wide margin (296 and 315 against 400) either way.

## Scripts

Placeholders: `$Q` is the session scratch folder's `qa` directory; `$S` the staged sample copies; `$B` the Bayer samples folder; `$R` the checkout (all scratch).

**S1** (AC2, AC3 synthetic; reproduced the engineer's table exactly)
```
.build/release/photobench demosaic --mode truth --nr off --files "$B/GX85.RW2:$B/Canon5DMkII.CR2:$B/EM5MarkIII.ORF"
```
Shows the CPSNR and edge chroma table of AC2 and AC3 (23 s).

**S2** (AC3, AC4, AC6, real files; five files: X-E3 ISO 400 `DSCF5123`, X-E3 ISO 200 `DSCF3141`, X-T3 ISO 6400 `DSCF4583`, X-T3 ISO 160 `DSCF0664`, X100S ISO 800 `X1000304`)
```
.build/release/photobench demosaic --mode real --files "$S/XE3-DSCF5123.RAF:$S/X-E3-ISO200-2018-11-10-DSCF3141.RAF:$S/XT3-DSCF4583.RAF:$S/X-T3-ISO160-2019-11-25-DSCF0664.RAF:$S/X100S-ISO800-2016-04-16-X1000304.RAF"
.build/release/photobench demosaic --mode real --nr off --files <the same>
```
With the step: ratios and blocks as in the AC rows. Kernel alone: false color 0.83x, 0.53x, 0.66x, 0.86x, 0.85x; detail 1.02x, 0.82x, 0.90x, 0.97x, 1.04x.

**S3** (AC5)
```
RAW_BOTH_SAMPLES="$S/XT3-DSCF4583.RAF" swift test --filter LibRawAgainstSystemTests
RAW_DEMOSAIC=libraw RAW_BOTH_SAMPLES="$S/XT3-DSCF4583.RAF" swift test --filter LibRawAgainstSystemTests
```
Block ΔE at 5500 K: 10.4 (ours), 10.0 (LibRaw's).

**S4** (AC4, AC6, AC9, AC12 on real files)
```
XTRANS_SAMPLES="$S/XE3-DSCF5123.RAF:$S/XT3-DSCF4583.RAF:$S/X100S-ISO800-2016-04-16-X1000304.RAF" swift test --filter DemosaicXTransSampleTests
```
Both tests passed (298 s in a debug build); the suite printed no file under AC6's detail bound among the three, and none of the three AC4 exceptions.

**S5** (AC9)
```
RAF_SAMPLE="$S/XE3-DSCF5123.RAF" swift test --filter LibRawFallbackTests
RAW_DEMOSAIC=libraw RAF_SAMPLE="$S/XE3-DSCF5123.RAF" swift test --filter "LibRawFallbackTests/theCorrectedRenderLinesUpWithTheCamerasJPEG"
```
Nine tests pass; alignment median 0.299 px, p90 0.758 (LibRaw's: 0.308, 0.830).

**S6** (AC15, AC10 live, R14 to R18)
```
.build/release/photobench demosaic --mode timing --runs 6 --libraw --files "$S/XE3-DSCF5123.RAF:$S/XT3-DSCF4583.RAF:$B/GX85.RW2:$B/Canon5DMkII.CR2:$B/EM5MarkIII.ORF"
.build/release/photobench demosaic --mode live --frames 30 --files "$S/XE3-DSCF5123.RAF"
RAW_DEMOSAIC=libraw .build/release/photobench demosaic --mode live --frames 30 --files "$S/XE3-DSCF5123.RAF"
```
Timing table as in AC15. Live, three runs with ours: fit first frame 758 to 772 ms, white balance 8.2 to 9.0 ms, exposure 8.2 to 9.0 ms, 100% decode 746 to 755 ms, first region 4 ms, white balance region 2.5 ms; LibRaw's: fit first frame 793, white balance 9.9, exposure 8.2, 100% decode 7944, first region 5, white balance region 2.5.

**S7** (R20, AC9): a scratch library from `photobench generate --output $Q/bench-photos --jpeg 6 --dng 2 --per-folder 8` and `photobench import --library-root $Q/cli-lib --source $Q/bench-photos`, then
```
.build/release/photocli render $Q/smoke-photos/XE3-DSCF5123.RAF --out $Q/out/xe3-gpu.jpg --library-root $Q/cli-lib
.build/release/photocli render $Q/smoke-photos/XE3-DSCF5123.RAF --out $Q/out/xe3-libraw.jpg --library-root $Q/cli-lib --demosaic libraw
```
First: `decoder libRaw`, `demosaic {method gpu, pattern xTrans}`, 6000 x 4000, empty edit stack, render 0.80 s (0.92 s wall). Second: `demosaic {method libraw, reason chosen}`, 12.5 s wall. I looked at 1000 x 700 crops at 100% of both from the same spot (a stained glass panel with a dark lead edge on a grey pane): same edges, no zipper or colored fringe in ours, less color grain in the grey than LibRaw's.

**S8** (AC11, smoke check: an X-E3 RAF opens, renders, takes the 100% path, edits). A bundle copy: `Scripts/build-app.sh`, `cp -R build/Gus.app $Q/app/`, `plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $Q/app/Gus.app/Contents/Info.plist`, `codesign --force --deep --sign - $Q/app/Gus.app`; the scratch library `$Q/app-lib` is a copy of S7's. The first run imported the folder (`addfolder $Q/smoke-photos; waitimport`). Then, launched as the executable directly:
```
$Q/app/Gus.app/Contents/MacOS/Gus --library-root $Q/app-lib --debug-script "wait 2; project; search DSCF5123; wait 2; focus 0; loupe; inspector on; tab adjust; wait 6; zoomstep in; wait 3; zoomstep in; wait 3; zoomstep in; wait 3; print loupe; zoomstep in; wait 3; print loupe; zoomstep in; wait 3; print loupe; wait 6; print viewport; snapshot $Q/out/smoke6-zoom.png; adjust temperature 7500; wait 5; print viewport; print frames; adjust scrub temperature 4000 9000 8 60; wait 4; print frames; print viewport; adjust luminance-nr 30; wait 4; print frames; snapshot $Q/out/smoke6-after.png; quit"
```
and, for the Adjust tab and the stack, the same start with `print ml; print loupe` after `wait 6`, then `adjust temperature 6500; wait 3; print adjustments; adjust luminance-nr 40; wait 3; print adjustments; print frames`. Showed: the photo imports and renders (cache hash `6c76a50e5dc3`, the same render hash `photocli` printed in S7); the Adjust tab states of AC11 above; the loupe steps 0.368, 0.5, 1.0 (the Fit / 100% zoom steps); at 1.000 a region frame 6000x4000 "applied" and the first frame 612 ms, sharp frames 52 to 56 ms while a Kelvin scrub ran, 77 to 113 ms still frames; the stack as in AC11. I looked at `smoke6-zoom.png`: the X-E3 photo drawn correctly (the glass panel, candles, dark window frame), the glass panes (sidebar, inspector) blank as `CLAUDE.md` says. Limits: the process was not the key app (`print responder` says `key nil`; the `zoom` key did nothing, `zoomstep` worked), so the 100% check is the region path and frame timings, not a look. Launched with `open -W -n --stdout … --args …` instead, this session twice saw an empty grid or the photo marked offline (a state of the scratch library that the direct launches did not show; the diff touches no volume or library code; not investigated further).

**S9** (R21, AC13)
```
.build/release/photobench demosaic --mode memory --file "$S/XE3-DSCF5123.RAF"
.build/release/photobench demosaic --mode memory --file "$S/XT3-DSCF4583.RAF"
```
Footprint before 88 MB; peak 384 MB (296 above) and 403 MB (315 above).

**S10** (the whole suite and the new ones): `swift test` (1072 tests in 161 suites passed); `swift test --filter "GPUDemosaicDecodeTests|DemosaicKernelTests|ColorNoiseReductionTests|LibRawDecoderTests|EditStackCorpusTests|PreviewCacheKey"` (47 tests in 7 suites passed, none skipped).

**S11** (mutations, in a copy of the tree under `$Q/mut`, restored after each; the script is `$Q/mutate.sh`, with M1 and M3 redone by hand because BSD `sed` rejects `0,/re/`): M1 `float weight = 1.0f / e;` in `xtransGreen`, M2 `currentPipelineVersion = 11`, M3 `decodeNoiseReduction … = nil`, M4 the two `try Task.checkCancellation()` lines of `decodeOnGPU` removed, M5 the `log.notice` of a GPU failure removed. Results in the table above.

## For a person

None of these needs the owner's real library. Use a scratch library from `photobench` and a copy of the bundle, `--library-root` on every launch (the command goes with the sign-off request). There is no `review.md` (no UI change), so no M-numbers; these four cover what the scripts and measures cannot say.

- **P1. How an X-E3 and an X-T3 photo look at 100% against LibRaw's own demosaic.** Add a folder with an X-E3 RAF (and, to compare another sensor class, an X-T3 or X100S RAF) to the scratch library with Add Folder Without Copying. Open it in the loupe, press Z for 100%, look at a dark edge on a light ground, fine texture (foliage, fabric) and a thin bright line. Then quit, relaunch the same copy with `--demosaic libraw` added and look at the same spot. Look for: a colored fringe or a zipper along edges at a slant (the known gap, #199) and whether it distracts at 100%; texture that is softer than before; color of small details kept. The numbers say ours is a little softer than LibRaw's three passes on 11 of 28 files and cleaner in color; whether that is a better picture is the owner's eye.
- **P2. A high-ISO X-E3 or X-T3 photo (ISO 3200 or more).** Same steps. Look for: color blotches gone in flat areas (sky, walls), and no gray-washed small colored details or desaturated edges (the noise step's cost). Compare with `--demosaic libraw` again.
- **P3. Stopping an export.** Select about 10 X-E3 raws, File ▸ Export, start, then File ▸ Stop (⌘.) while two are rendering. Look in Activity for "Export stopped after N photos" and no "could not be written" lines naming raws (code review C2; the tests cover the mapping, not the Activity text or the timing).
- **P4. The first launch after the update on a library with photos.** On a scratch copy of a real library (migrations are not touched, but the previews are), the grid and loupe fill in again from an empty cache (pipeline version 12, R23, the user guide says so). Look for: how it feels; that nothing blocks. Optional.

macOS 15 and 26 are covered by the pull request's CI (the macOS 15 job builds with Swift 6.2.4, code review C10), not by a person here.

## Follow-up

Findings (relayed by the main session; I did not rerun anything for these):

- **Q1: Fixed** in `5dd946e`, confirmed by code review's fourth pass with the mutation re-run (the baseline noise step switched off in the decode now fails a test).
- **Q2: Closed.** The owner accepted AC2's E-M5 III edge chroma (2.04 against 1.97, 1.04x) as measured, in `ccc71fa`. AC2 therefore stands as accepted, like AC3, AC4 and AC6.

Person checks: the owner did P1 to P4 on 2026-11-17 in the bundled app at `f211d34`, on a scratch library with five RAFs (X-E3 at ISO 200, 3200 and 8000, X-T3 at ISO 12800, X100S at ISO 3200). Their words: "no noticeable difference in rendering at 100% against the old look; previews for X-E3 files generate a lot faster, no lag." P1 to P4 are done.

**Sign-off: 2026-11-17, owner, commit `f211d34`.** Checks left open: none, except those left to the pull request's CI (macOS 15 and 26, the Swift 6.2.4 test compile of the macOS 15 job, and the CI runners' GPU). The main session commits this file.
