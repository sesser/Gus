# GPU demosaic for raws LibRaw decodes: code review

Owner: code-reviewer. Date: 2026-11-16. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/gpu-demosaic`, `34738c2..fb6b7f5` (6 commits). Build and
tests: `swift build` green, and a clean build into a separate build path shows
no warnings; `swift test` passed 1067 tests in 161 suites (66 s). The opt-in
suites (`XTRANS_SAMPLES`, `BAYER_SAMPLES`, `RAF_SAMPLE`, `RAW_BOTH_SAMPLES`)
were not run: there are no samples on this side.

Checked against the PRD as revised on 2026-11-16 (issue #196: AC3 accepted as
measured, RI-1; AC4 only at ISO 800 or lower, RI-2; AC6 accepted as measured).

## Verdict

Not ready yet. The design is sound and the rules this review was asked to
watch hold: `SystemRAWDecoder.reads` still decides, system-decoded raws and
JPEGs are untouched, the pipeline bump is plain, there is no brand leak, and
nothing points to another project's code. There are four Should-fix findings.
One fallback path the PRD promises (R19, allocation failure) aborts the
process. Stopping an export now lists the raws in flight as failed. The opt-in
sample suite still checks the criteria as first written. `status.md` still
says Blocked. All four are small fixes.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoCore/Demosaic/GPUDemosaic.swift:276` (also `:479` in `denoise`) | `encodeDenoise` can throw (its scratch textures fail to allocate, `.allocation("noise reduction scratch")`) after `run` has made its compute encoder. Nothing ends that encoder on the way out. The other throws after the encoder exists (green plane, X-Trans tables) do call `endEncoding()` first; this one doesn't. | Metal aborts the process when an encoder is released without `endEncoding`, without the validation layer too. I checked this with a 20-line program in the scratchpad (make a command buffer and a compute encoder, throw, drain the autorelease pool): `-[_MTLCommandEncoder dealloc]:134: failed assertion 'Command encoder released without endEncoding'`, exit 134. So when memory is tight, a full-size decode (4 × 27 MB of `rgba32Float` scratch at 6000 px wide) takes the app down. R19 says such a decode falls back to LibRaw's demosaic. Fix: make the scratch textures before the encoder, or end the encoder on every throw (a `defer` or a `do`/`catch` around the encoding). | R19; correctness |
| C2 | Should fix | `Sources/PhotoCore/Preview/LibRawDecoder+GPU.swift:115,124` with `PreviewGenerator.swift:308` and `Export/ExportJob.swift:273` | A LibRaw decode now throws `CancellationError` once its task is cancelled (R21), and `PreviewGenerator` passes it on. `ExportJob.export` doesn't tell that apart from a real failure: its last `catch` makes it `.writeFailed(error.localizedDescription)`. | Export 24 X-E3 raws and choose File ▸ Stop while two are rendering. The two in flight (the unpack is 0.5 s of their 0.6 s) come back as failures. Activity lists "`DSCF0001.RAF`: The operation couldn't be completed. (Swift.CancellationError error 1.)" and the row is a warning. If those two were the last items, `summary.cancelled` (`Task.isCancelled && done < total`, line 248) is false, because failures count toward `done`, and the row reads "Exported 22 of 24 photos. 2 could not be written." Before this branch those two finished and were written. Fix: treat `CancellationError` in `ExportJob.export` as not done (or skipped), not failed. The other callers are fine: the preview lanes, the live session (`AdjustmentEditor` catches it), and the measuring paste (detached task). | Correctness; R21 |
| C3 | Should fix | `Tests/PhotoCoreTests/DemosaicSampleTests.swift:82-89` | The opt-in X-Trans suite still checks AC3 as first written (`alone.falseColorRatio <= 1.0`, `alone.detailRatio >= 0.95`) and AC4 on every file at every ISO. The PRD revised both on 2026-11-16: AC3 is accepted as measured, and AC4 applies only at ISO 800 or lower. | `XTRANS_SAMPLES=<the 28 files> swift test --filter DemosaicXTransSampleTests` is red on the accepted state, by `status.md`'s own numbers: AC3 detail fails on 11 files, AC4 on the high-ISO ones (`DSCF4583`: blocks p95 2.33, edges 8.42), AC6 detail on 5. `status.md` proposes that command for `CLAUDE.md`, so whoever runs it next meets a red suite for a known, accepted result. Fix: AC4 expectations only for files at ISO 800 or lower (LibRaw's `other.iso_speed`, say), and AC3 printed as a measurement, not expected. For AC6's detail bound, see Q1. This aligns the test with the PRD as revised; it does not loosen a tolerance to make a test pass. | PRD rev 2; tests match the spec |
| C4 | Should fix | `docs/features/gpu-demosaic/status.md:15-21, 314, 332-333, 348-378` | `status.md` still says **Status: Blocked** on RI-1 and RI-2, with R8, AC3 and AC4 marked Blocked or Not met. The owner ruled on both on 2026-11-16 (PRD Revisions, rev 2). It also gives the latest full run "at `5003d8a`", a commit that is not on any branch (one rewritten before `6d54d5a`). | Review and QA read `status.md` as the record. `docs/WORKFLOW.md` step 3 wants the engineer's last state to be **Done**, and the rulings recorded. Update the status line, the RI section (ruled: accepted as measured; AC4 at ISO 800 or lower), the AC rows, and the commit of the last full run. | `docs/WORKFLOW.md` step 3 |
| C5 | Nit | `Tests/PhotoCoreTests/GPUDemosaicDecodeTests.swift:30,36,136`; `DemosaicKernelTests.swift:71-78`; `ColorNoiseReductionTests.swift:62,87,114,150,219` | Without a Metal device the new GPU tests `return` and pass instead of being skipped. `GPUDemosaicDecodeTests.gpuAvailable` is `(try? shared()) != nil`, so a kernel compile failure also turns `whichDemosaic` and `fallbackOnFailure` into silent passes. (`DemosaicKernelTests` would still fail on a compile failure: it catches only `.noDevice`.) `whiteBalanceRunsNoDemosaic` also returns early on any macOS whose system decoder reads the small DNG, which may be the CI runners, so AC10 is checked only here. | On a runner with no device, or a broken kernel source, the run shows these tests passed when nothing ran. AC16 asks for "skip with the reason, as the existing GPU tests do" (`RuntimeKernelTests`, `StitchableKernelTests` use `.enabled(if:, "reason")`). | AC16 |
| C6 | Nit | `Sources/PhotoCore/Commands/RenderCommands.swift:134-140, 233-253` | `photocli render`'s new `decoder` and `demosaic` keys, and the refusal of a bad `--demosaic` value, have no automated test (`status.md` R20: "checked by hand"). | A change to the JSON contract or the parsing goes unnoticed. A test like `whichDemosaic`'s on the small synthetic X-Trans DNG would cover it. | R20; tests |
| C7 | Nit | `Sources/PhotoCore/Demosaic/SensorMosaic.swift:195-197` | `cblack` is read at `offset(of: \.black) − 4104 × 4`. That is correct for the vendored 0.22.3 header (`curve[0x10000]`, then `cblack[LIBRAW_CBLACK_SIZE]`, then `black`, all 4-byte aligned), but nothing checks it. | A future LibRaw update that reorders `libraw_colordata_t` would read the wrong blacks without any error. A one-line test (`offset(of: \.black) == 0x10000 * 2 + Int(LIBRAW_CBLACK_SIZE) * 4`) would catch it. | Robustness |
| C8 | Nit | `GPUDemosaic.swift:188-189`, `LibRawDecoderTests.swift:362-366` | The output's rows are padded to `minimumLinearTextureAlignment` (16 bytes here, more on some GPUs). The padding comes from `posix_memalign` and is never written. `Pixels.data` includes it, and the concurrency test compares `pixels.data` of GPU decodes byte for byte. | With an odd decode width (8 bytes of padding a row here), the same file decoded twice can compare unequal from leftover heap bytes. That's a flaky test, not a rendering fault. Compare `samples()`, or zero the padding. | Test determinism |
| C9 | Nit | `Sources/PhotoCore/Preview/LibRawDecoder+GPU.swift:49` | `Pixels: @unchecked Sendable`, but every member (`Int`, `Bool`, `Data`) is `Sendable`. | No failure. The `@unchecked` is unneeded and would hide a future non-`Sendable` member. | Swift 6 concurrency |

## Questions

- **Q1 (product manager).** The owner accepted AC6 "as a whole" with 5 of 28
  files under the detail bound (0.92x to 0.94x). Should the opt-in suite keep
  `reduced.detailRatio >= 0.95` as an expectation, so it is red on those five
  of the owner's own samples, or record the result as a measurement, as C3
  proposes for AC3? Either is defensible; the suite should say which.

## Checked and fine

- **The one decider.** `SystemRAWDecoder.reads` is untouched, and
  `PreviewGenerator.decode` still tries the system decoder first
  (`rawImage`). The only change there is `try` on the LibRaw branch, so raws
  the system reads and JPEGs render as before. No golden moved, and no file
  under `Goldens/` is in the diff.
- **Pipeline version.** 11 to 12 in `PreviewCacheKey`, a plain bump with no
  carry-over. `GPUDemosaicDecodeTests.pipelineVersion` pins it, and
  `EstimateEdgeTests` now checks `>= 11`, as `LocalSharpenGroupOffTests`
  already did for its own bump. The user guide says previews are made again.
- **Memory lifetime.** The mosaic and output storage are page-aligned
  (`posix_memalign` at `getpagesize()`, length rounded to pages) and wrapped
  with `makeBuffer(bytesNoCopy:…, deallocator: nil)`. `run` holds the storage,
  the buffers, the green plane and the scratch until `waitUntilCompleted`.
  `Image.data` keeps the storage alive through its deallocator, and the
  `CIImage` and live session keep the `Data`. LibRaw's buffers are freed
  (`libraw_recycle`) before the GPU's are made.
- **Bounds.** `SensorMosaic.unpacked` checks `left + width <= raw_pitch/2` and
  `top + height <= raw_height` before copying, and the 150 MP cap is checked
  at open. The black pattern must divide the CFA period before it is indexed,
  so `rows × columns ≤ 36`. In the kernels, every raw read is in the image
  (`valueAt` on mirrored or in-border coordinates). The X-Trans border is
  worked out from the tables' reach (6), and neighbours stay within ±2. The
  banded noise reduction reads scratch rows clamped to what the previous
  level wrote. I traced the in-place band order: a band's last level writes
  only after the next band's first level has read the rows they share, and a
  scratch set is reused only two bands later. `DemosaicTables` refuses
  patterns whose lists exceed the kernels' fixed arrays.
- **Fallbacks.** Every one is logged with the file private and the reason
  public: unsupported pattern, no color data, no sensor data, no device,
  compile, allocation, encoding and execution failures. The debug switch
  isn't logged, which is intended. The failure path decides per decode; only
  a missing device is cached, as R19 allows. The `fallbackOnFailure` test
  reads the log line back.
- **Cancellation.** It is checked after the unpack and after the copy, before
  any GPU allocation. `WorkLane` cancels a job only when no waiter is left,
  so a cancelled decode can't reach a waiting caller. C2 is the one caller
  that mishandles it.
- **Concurrency.** The new `@unchecked Sendable` types (`GPUDemosaic`,
  `PageAlignedStorage`, `TableBuffers`) have written reasons that hold.
  `Mutex` guards the engine and the tables cache. Decodes run off the main
  actor. `MTLCompileOptions.mathMode`, `Mutex` and `OSLogStore` are all on
  macOS 15 (R22).
- **Matching LibRaw's scale.** The multipliers, per-site black (common, per
  color with the second green as 3, and the repeating pattern), the white
  span, the crop box (cut after the demosaic), the orientation (whole-pixel
  moves in LibRaw's flip order), the Fujifilm frame and lens corrections, and
  `channelScale`/`whiteMargin` all match `decodeWithLibRawDemosaic`. The
  existing orientation, inset-crop and white-level tests now run through the
  GPU path and pass.
- **Hermetic tests and tools.** The new tests write only to
  `RepositoryFiles.withTemporaryDirectory`. Real samples are opt-in through
  `XTRANS_SAMPLES` and `BAYER_SAMPLES`, with `.enabled(if:, reason)`.
  `photobench demosaic` opens no library and removes its temporary folder.
  No sample path is committed; the docs give file names only.
- **Branding and localization.** There are no brand values. The new persisted
  or JSON names (`decoder`, `demosaic`, `method`, `pattern`, `reason`) are
  generic. No UI string was added. The launch option `--demosaic` takes a
  value.
- **Clean room (AC8).** `THIRD_PARTY_NOTICES.md` is unchanged. The kernels and
  tables say which papers they follow. I found none of the hallmarks of the
  known X-Trans or Bayer implementations (no hexagon tables, no
  homogeneity-map tiles, no copied constant tables): the X-Trans taps are
  derived at run time from the pattern. `status.md` lists the published
  sources.
- **Other rules.** No migration, no change to the edit stack or presets (R13),
  no new package, and `Package.swift` is untouched.

## Follow-up

### Second pass (2026-11-16)

Reviewed: `fb6b7f5..dda56da` (`522f41f` code and tests, `dda56da`
`status.md`). Build and tests at `dda56da` on this Mac (Xcode 27.2, Swift
6.4.2): `swift build` green; `swift test` passed 1071 tests in 161 suites
(67 s); `swift test --filter
"GPUDemosaicDecodeTests|DemosaicKernelTests|ColorNoiseReductionTests"` passed
21 tests in 3 suites, the new ones included. The sample suites were not run
(no samples here).

**Verdict: not ready yet.** C1 to C9 are fixed, and the fixes are correct. One
of them (C5) brought in `Test.cancel`, which the Swift 6.2.4 toolchain of the
macOS 15 CI job does not have, so the pull request's required check would fail
to compile the tests (C10, Blocker). It is a small change to three tests.

| # | Verdict | Commit | Notes |
|---|---|---|---|
| C1 | Fixed | `522f41f` | `run` wraps everything from the first `common(...)` to `encodeDenoise` in `do throws(Failure)`, and the `catch` ends the encoder before it rethrows. Nothing between `makeComputeCommandEncoder` and that `do` can throw (`tableBuffers` and every other throw come before the encoder). `denoise` does the same around `encodeDenoise`, its only throw after the encoder is made. `InjectedFault.scratchAllocation` throws at the top of the scratch loop, inside both `do`s. `scratchAllocationFallsBack` covers Bayer and X-Trans decodes (LibRaw's pixels byte for byte, the next decode ours) and `denoise`. Passes here. |
| C2 | Fixed | `522f41f` | `ExportJob.outcome(of:name:)` maps `CancellationError` to `.cancelled`; `tally` counts it neither done nor failed. A `CancellationError` reaches `export` only from `Task.checkCancellation` in `decodeOnGPU`, on the child task of a cancelled group, so `Task.isCancelled` is true whenever an item is `.cancelled`, and `done < total` then holds: `summary.cancelled` is set, and Activity reads "Export stopped after N photos." (`ExportModel.finishedMessage`). Both checks come before any file is opened, so a stopped item writes nothing and replaces nothing. Other errors still log and fail as before; `photocli export` runs uncancelled and is unchanged. `stoppedExportIsNotAFailure` checks the mapping, the tally and a real render in a stopped task, with no file written. It checks `run`'s end-of-export arithmetic by reasoning, not end to end; that is enough here. |
| C3 | Fixed | `522f41f` | AC4 is expected only when LibRaw's `other.iso_speed` is 1 to 800; AC3 is printed, not expected; AC6 expects false color, prints detail, and lists the files under 0.95x (Q1 answered that way). The truth suite expects AC2 for Bayer only and prints X-Trans. No threshold changed. Two known-red cases remain by the engineer's choice and are documented in `status.md`: see Q2 (already with the owner) and Q3 below. |
| C4 | Fixed | `dda56da` | **Status: Done** with the rev 2 rulings, the RI section rewritten as ruled, the AC rows updated, the last full run at `522f41f` (on the branch; 1071 tests, which matches my run). |
| C5 | Fixed, but see C10 | `522f41f` | The three GPU suites and the GPU tests of `GPUDemosaicDecodeTests` are `.enabled(if: hasMetalDevice, "…")` and call `GPUDemosaic.shared()` directly, so a kernel compile failure now fails them. The tests that need a raw only LibRaw decodes skip with a reason, but through `Test.cancel`, which C10 is about. |
| C6 | Fixed | `522f41f` | `renderReportsTheDemosaic` checks `decoder`, `demosaic.method`/`pattern`/`reason`, `--demosaic libraw`, `Automatic`, the refusal of `ahd` (`invalidValue`) and a JPEG with no `demosaic`. Passes. |
| C7 | Fixed | `522f41f` | `blackLayoutHolds` checks `black`'s offset against `curve[0x10000]` plus `cblack[LIBRAW_CBLACK_SIZE]` and that `data_maximum` follows it, which matches the vendored header (`libraw_types.h:782-785`). A changed size of `cblack` moves both the check and the read together; anything inserted around them fails the check, and the decode then falls back to LibRaw's demosaic with a logged reason (`Unsupported.blackLayout`). `DemosaicKernelTests.blackLayout` pins it. (The check runs after the unpack, so in that case each decode unpacks twice; it can only happen after a LibRaw update, which the test catches first. Not a finding.) |
| C8 | Fixed | `522f41f` | `PageAlignedStorage.zeroPadding` clears each row's padding after allocation, in `run` and `denoise`, before the storage reaches Metal. `Image.data` covers `bytesPerRow × height`, so the page-rounding tail past it is never in the data. The `@unchecked Sendable` reason (written once by the filling thread before hand-off) still holds. |
| C9 | Fixed | `522f41f` | `Pixels: Sendable`; it compiles, so every member is `Sendable`. |

New in this pass:

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C10 | Blocker | `Tests/PhotoCoreTests/GPUDemosaicDecodeTests.swift:87, 118, 270` | The C5 fix skips three tests with `try Test.cancel("…")`. `Test.cancel` is public in Swift Testing from Swift 6.3 (`Sources/Testing/Test+Cancellation.swift`, first in tag `swift-6.3-RELEASE`). In `swift-6.2.4-RELEASE` that file doesn't exist and no `func cancel` is in `Sources/Testing` (I checked a clone of the tag). The macOS 15 CI job selects Xcode 26.3, and its latest green run on `develop` (run 43984746539) logs `Apple Swift version 6.2.4`. The macOS 26 job (Xcode 26.6, Swift 6.3.3) and this Mac (Swift 6.4.2) have it, so nothing before the pull request shows the problem. | When the pull request opens, the `Build and test (macos-15)` required check fails to compile `PhotoCoreTests` ("type 'Test' has no member 'cancel'"), so no test runs on macOS 15 and the merge is blocked (WORKFLOW step 7). Fix without `Test.cancel`: decide each test's condition before it runs (for example a `static let` that writes the small X-Trans DNG to a temporary folder and asks `SystemRAWDecoder.reads`, used in `.enabled(if:, "reason")`), or put the `Test.cancel` behind `#if compiler(>=6.3)` with a printed reason and `return` otherwise. Whichever is used, the macOS 15 job is the check: a build with Xcode 26.3 if it can be had here, otherwise the pull request's CI. | CI on macOS 15 (WORKFLOW step 7); R22 |

New question:

- **Q3 (product manager, with Q2).** The X-Trans sample suite now expects AC4
  on every file at ISO 800 or lower. Rev 2 records three such files (an X-E3 at
  ISO 200 with block p95 2.08, two X100S files) as outside AC4 and accepted as
  part of the whole. So `XTRANS_SAMPLES` over all 28 of the owner's files is
  still red on those three, and only on them. For AC6's five files under the
  detail bound the suite records rather than expects (Q1). Should AC4's three
  be treated the same way, or stay expected so they keep showing? Q2 asks the
  same of AC2's E-M5 III in `DemosaicTruthTests`. It is not a code fault either
  way: the engineer chose this on purpose and `status.md` says so (AC2 and AC4
  rows). The two should get one answer.

Checked and fine in this pass, beyond the table: `LibRawDecoder.Output.iso`
is read while the processor is open on both paths (before `libraw_unpack` and
`libraw_recycle` on the GPU path, before `libraw_close` on LibRaw's), and it
has a default, so other initializers are unaffected. It is used only by the
sample suite. `hasMetalDevice` is a module-level `let Bool`, fine under strict
concurrency. `whiteBalanceRunsNoDemosaic` stays enabled without a device and
expects zero runs there. `stoppedExportIsNotAFailure` needs no device: the
cancellation check comes before `GPUDemosaic.shared()`. The gate in that test
(`AsyncStream` iteration ends when its task is cancelled) is deterministic,
with no sleep. Nothing under `Sources/CLibRaw`, `Goldens/` or `Package.swift`
changed, and no UI string, brand value or tolerance changed.
