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

(After the engineer's fixes.)
