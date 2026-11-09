# Chromatic aberration and color fringe removal: code review

Owner: code-reviewer. Date: 2026-11-08. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/chromatic-aberration`, fafdec6..7bbdfe5. Build and tests: `swift build` clean; `swift test` 627 tests in 107 suites passed, 1 known issue (the pre-existing "Live render session"), run here on Swift 6.4.2 from a scratch build. CI on 7bbdfe5 passed on both runners (Swift 6.2.4 on macos-15, 6.3.3 on macos-26).

## Verdict

Not ready to merge: five Should fix findings, no Blockers. The renderer, the stored data and the project's rules on goldens, the pipeline version, originals and undo all hold. The findings are in the paths around them: a batch measurement that can lose its progress and Stop, a silent skip, a pick that can differ from the outline, a missing refinement, and AC29, which is code review's own check and doesn't pass.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoApp/Model/AdjustmentActions.swift:74`, `:95` | A photo whose edit stack this build can't read is dropped from a measuring paste or preset with no message. Line 74's comment says the catalog reports it, but line 95 filters that photo's id out, so the catalog never sees it. | Grid selection of ten photos, one with a stack over `MaskLimits` or from a newer build; paste a copy with Align automatically on. Nine change and Activity says nothing about the tenth. The same paste without automatic alignment reports "1 photo was left unchanged: its edits can't be changed in this version." If every photo is unreadable, the command does nothing and says nothing. Fix: keep those ids in the list passed to `changeAdjustments`, which skips and reports them. | R16a (the person is told); the app's existing batch behavior |
| C2 | Should fix | `Sources/PhotoApp/Model/AdjustmentActions.swift:59-68` (the same pattern in `BatchActions.swift:86-92`) | A cancelled batch measurement clears the state of the batch that replaced it. The new command cancels the old task and starts its own, but the old task's `defer` runs later and sets `batchAutoTask = nil`, progress to nil and `setMeasuringAlignment(false)` unconditionally. | Paste with Align automatically onto several raws, then apply a measuring preset (or paste again) before it ends. The first task finishes its current photo and returns: the Activity row disappears, the inspector's spinner stops, and `batchAutoTask` is nil, so Activity's Stop does nothing (`stop: { model.batchAutoTask?.cancel() }`) although the second batch runs on and saves. Fix: each task clears only state it still owns (a generation number). | Correctness; design §10's Stop |
| C3 | Should fix | `Sources/PhotoApp/Loupe/LoupeView.swift:1102`, `:1126` | Within the 3-point drag threshold the outline follows the pointer, but the click picks where the mouse went down. `mouseDragged` updates the magnifier before the threshold check; `mouseUp` picks at `downLocation`. | At the view's 100% on a Retina display, press on pixel X and let the pointer slip 1 point before releasing. The outline shows X + 2 at release and the stored color is X's. On a fringe 2 pixels wide that is a different color, or a refusal the plate didn't show. Fix: pick where the magnifier last outlined, or hold the outline until the press becomes a drag. | R22 (Must): "A click never picks any other pixel" |
| C4 | Should fix | `Sources/PhotoApp/Model/AdjustmentEditor.swift:218` | A zoom change schedules refinement only when a map is shown (`sharpeningMap.isShown`), which is the old condition. Re-picking a filled slot, added in this branch, needs it too. | (a) Arm a filled slot at fit, then press `Z`. The loupe keeps the stretched 2560 px frame without the slot, with no refinement until another render happens to run, and that frame is what the person aims at. (b) Fringe map shown, filled slot armed (map suspended), zoom from 100% to fit: the refinement runs with `adjustments`, including the slot being replaced, so the fringe being picked turns gray on screen. Fix: test `currentContent` and `fringeSlotIsReplaced(pickingFringeSlot)` here, as `scheduleMapRefinement` does. | design.md §4 "Zoomed in, it refines to full resolution" |
| C5 | Should fix | `Sources/PhotoCore/Edits/PixelMagnifier.swift:104`; `Sources/PhotoApp/Loupe/LoupeView.swift:616-628` | AC29 asks code review to confirm the magnifier refers to no fringe type, and it does in two places. `PixelMagnifierValues` calls `FringeColorMath.inverse`. The loupe's `updateMagnifier` is written against the concrete `FringeMagnifierTool`: `outputPixelWidth` and `position(forOutput:)` are not on `PixelMagnifierTool`, so the test tool (AC29) proves only the core. | A second tool, Pick Colors being the planned one, can't reach the loupe's magnifier without changing `updateMagnifier` and the protocol. Fix: move the matrix inverse to a neutral home, and put the output-to-position mapping and the scale on the protocol (`maskPoint` is only for the debug script). | R34, AC29 |
| C6 | Nit | `Sources/PhotoCore/Commands/LibraryCommands.swift:206-231` | The doc comment says "as the app sets it", but `colorAlignment.automatic=false` leaves the measured red and blue in the stack. The app's check box zeroes them (`setAutomaticAlignment(false)`). | `photocli develop --set colorAlignment.automatic=false` after a measurement: the correction still renders, now as hand-set values. | R14 |
| C7 | Nit | `Sources/PhotoApp/Model/AdjustmentEditor.swift:1412-1416` | Unchecking Align automatically while a paste or preset is measuring only hides the spinner. `alignmentTask` is nil on that path, and the doc comment says unchecking "stops it and saves nothing". | In the loupe, paste with automatic alignment and uncheck during the measuring: the check box clears, then the paste saves automatic alignment. | Correctness |
| C8 | Nit | `Sources/PhotoApp/Loupe/PixelMagnifierView.swift:98`, `:173` | The picture reaches the layer as RGBA Display P3, not BGRA in the window's color space, so Core Animation converts it on the main thread at commit on every pointer move. It is 256 × 256, so the cost is small. | On an sRGB external display, each update adds a color conversion at commit. | CLAUDE.md, Concurrency |
| C9 | Nit | `Sources/PhotoApp/Loupe/LoupeView.swift:425` | Cursor rects are invalidated only when the armed slot changes, and the rect is the photo's frame in the scroll view at that moment. Read from the code; it takes a person with a pointer to see it. | A portrait photo armed at fit, then zoomed to 100%: outside the old rect the pointer can stay an arrow over the photo while the magnifier shows. | design.md §4 step 2 |
| C10 | Nit | `Sources/PhotoBench/EditBenchmark.swift:109` | AC31's "update per pointer move" is measured only at the default 800%, with no crop. A 256-device-pixel picture holds 35² cells at 800% and 259² at 100%, about 55 times as many, so the recorded 0.15 ms would be roughly 8 ms at 100% (an estimate from the cell counts), on the main thread. | The recorded number doesn't cover the slowest level. Record 100% too. | R36, AC31 |
| C11 | Nit | `Sources/PhotoApp/Model/DebugAdjustCommands.swift:33` | The help text still says "snap", which ruling 18 removed. | Misleads whoever writes a debug script. | Ruling 18 |

## Questions

For the designer:

- **What should the magnifier and a click do when the held pixels can't be made** (the original was ejected or became unreadable while picking)? Today `syncSamplePixels` only logs: the magnifier keeps its dashes and spinner, a click does nothing, and no caption says why. design.md §20 covers pixels that are not ready yet, not pixels that never arrive.

For the product manager (low priority):

- **If the Lens kernels fail to compile,** `align` and `fringeStep` return the input image (`try?` in `LensRenderer.swift`), so the edit renders uncorrected with no message and those previews are cached under the edit's hash. They compiled on macOS 15, 26 and 27, so this needs an OS-level failure. Should the app say so?

## Checked and fine

- **Pipeline and goldens (R11, AC8):** no golden, no fixture golden and no `currentPipelineVersion` changed. Identity stacks skip the lens step (`lens` returns its input object). `decodeSettings` is built from the effective values, so a group turned off decodes as before.
- **Render paths:** the lens step is in `upstream`, so previews, export, the live session (its stage key includes the lens operations through the render hash), masks (`maskAlpha`) and the sharpening map all get it. A camera-cropped raw decoded whole for alignment keeps its camera frame (`Self.crop`), and `maskSourceSize` follows.
- **Kernels against the CPU reference:** order, signs, ROIs and extents; the Swift and Metal hue weights match; each kernel has its own library.
- **Preview cache safety:** a frame without the re-picked slot is never seeded (`frame.adjustments == committed`), and map frames are excluded (`showsPhoto`).
- **Magnifier core:** quarter-turn mapping both ways, half-float decoding, P3 conversion against CoreGraphics (AC19), hard cells, crop edges, one rule for click and outline, held pixels released when picking ends (the task's retained result is cleared too).
- **Concurrency:** decoding and measuring are off the main actor; no new `@unchecked Sendable` or `nonisolated(unsafe)`. A pick racing a change of the sampled image waits for the newest render.
- **Rules:** no migration, no new dependency, no brand value, no SwiftUI `ScrollView`, menus on focused values, every photo-changing debug command inside `changing`, stacks this build can't read are never written over (C1 is only about the message), originals untouched.
- **Edit data:** `AdjustmentParameters`, group and section tables, and all four per-kind switches in `Adjustments` are updated. Tolerance left out at its starting value behaves as R1b says.
- **Tests:** every testable AC has a test or a debug-script row; no sleeps, no loosened tolerance. AC19's look-up table and other-slot cases exist and each edit is shown to change the render. status.md's test count and its "no golden changed" claim are confirmed.
- **Compile time on older Swift:** the expressions CI rejected (`ColorAlignmentTests.swift:67` and `:154` before 92d7156) were closures over a range with index arithmetic chained into `.reduce` or `.max`. Nothing added since 92d7156 has that shape: the new tests use loops. Timing on 6.4.2 can't predict this (those two expressions take 3 and 32 ms here), so the evidence is the shape and CI on 7bbdfe5 passing on 6.2.4 and 6.3.3.
- **Outside input:** `CameraRawMapping.lens` and `ParameterValues.color` are bounded: non-finite values are rejected or can't pass `width > 0`, and everything is clamped. The Metal source is built from constants only. No `Process` or network code in the diff.

## Follow-up

### Second pass: 10c4013 (local, not yet pushed)

Reviewed `git diff 7bbdfe5 10c4013`, including the new code it adds (DQ-4, the Esc monitor, F3–F5, the debug-script commands). `swift test` from a separate worktree and scratch build: 633 tests in 108 suites passed, 1 known issue. No golden or pipeline version changed. CI has not seen this commit.

**Verdict after the second pass: not ready to merge.** One new Blocker (C12) and one new Should fix (C13), both small. Everything else is fixed or may stand.

| # | Outcome | Evidence |
|---|---|---|
| C1 | Fixed | `AlignmentMeasurements.versionsToChange` drops only failed originals; an unreadable stack reaches the catalog, which reports it. Unit test fails when the old filter is put back (trial revert). |
| C2 | Fixed | `LatestRun`: the `defer` and the loop's progress line touch only state the run still owns, in paste, presets and Auto. Unit test fails when `owns` is always true. The race itself is untested because `LibraryModel` has no test target; I traced the replace path by reading and it holds. Accepted. |
| C3 | Fixed | The outline is set at mouse-down and moves again only once the press is a drag, so it stays on the pixel the click takes. No test target reaches `LoupeScrollView`; by reading. A person confirms it in M3. |
| C4 | Fixed | `didSet` uses `refinementWanted` for both cases. Table test fails when the zoom condition is dropped (trial revert). The test covers the rule; the call site is by reading. |
| C5 | Fixed | The core has no fringe type, `updateMagnifier` uses only `any PixelMagnifierTool`, and the output mapping is on the protocol. AC29 passes. The click stays fringe-specific, which is the tool's own part. |
| C6 | Fixed | `automatic=false` alone clears the correction. The test line fails without the branch (trial revert). |
| C7 | Fixed, with a regression | Unchecking now stops a paste's measuring. The same line can also stop an unrelated batch: see C13. By reading. |
| C8 | Stands | Accepted. The picture is built on the main thread for each pointer move, so there is no off-main step to move the conversion into, and at 65,536 pixels the commit cost is small. The Display P3 bitmap also matches R23's values and what AC17 checks. The 4 ms figure covers building the picture, not the commit, but the size alone makes the case. |
| C9 | Fixed | Cursor rects are invalidated on every bounds change while picking, and the rect is now in the document view's coordinates. By reading; a person confirms it in M3. |
| C10 | Fixed | 100% and a straightened crop are recorded (3.6 and 4.0 ms, under my estimate). One label is wrong: C14. |
| C11 | Fixed | Help text corrected. |
| Question: held pixels fail | Closed by DQ-4 | Built as ruled, checked against design §19: only the render picking waits for counts, a waiting click is dropped, the failure is reported once, arming retries, the caption clears on arming, on any change and on another photo, and pixels already held keep working. |
| Question: kernels fail to compile | Closed by RI-CR1 | Known limitation; no change. |

**New findings**

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C12 | Blocker | `Sources/PhotoApp/Model/DebugLensCommands.swift:76-85` | `magnifier hideoriginal` renames the focused photo's original with `FileManager.moveItem`. The comment says "scratch libraries only", but nothing enforces that, and the debug script ships in the release bundle. A scratch library can also reference real files, since folders import in place. | A script run with `--library-root` on a library that references real originals renames the master to `<name>.hidden`. If the script stops before `restoreoriginal`, the file stays renamed and the photo reads as missing. Fix: remove the command and make DR22's failure another way, for example a debug-only switch that makes the sampled render fail, or an ejected disk image as R16a's run used. | CLAUDE.md: "Originals are never moved, copied or modified." |
| C13 | Should fix | `Sources/PhotoApp/Model/AdjustmentEditor.swift:1436` | `setAutomaticAlignment(false)` cancels `library?.batchAutoTask` even when `isMeasuringAlignment` comes from the editor's own task. | Start a measuring paste on many grid photos, open one in the loupe, check Align automatically and uncheck it while it measures. The whole paste stops and writes nothing, with no message. Fix: cancel the batch only when `alignmentTask` is nil. | Correctness; design §7 |
| C14 | Nit | `docs/PROFILING.md:323` and status.md's speed table | The row labelled "400%" comes from `level: .standard`, which is 800% (`PixelMagnifier.swift:21`). | The record names the wrong level. | AC31 |

**New code with no finding:** the Esc monitor (installed and removed with picking, and in `tearDown`; only this window, text fields keep Esc, one level per press), DQ-4, the grid limited to drawn cells (F3, whose test fails when the limit is removed), F4, the context menu's section header (F5), `contextmenu at` and `resignkeyboard`.

**Older compilers:** the new expressions are short, and the new tests use loops, not chained closures. The longest new `#expect`, three `abs(...) < 1e-12` terms (`LensReviewFixesTests.swift:44`), has a precedent that passes CI (`PresetTests.swift:52`). Only CI on this commit can settle it.

### Third pass: 03a5af5 (local, not yet pushed)

Reviewed `git diff 10c4013 03a5af5` only. `swift test` from a separate worktree and scratch build: 634 tests in 108 suites passed, 1 known issue. No golden or pipeline version changed. CI has not seen this commit.

**Verdict after the third pass: code review has no open findings.** C1–C7 and C9–C14 are fixed and C8 stands by agreement. Merging still needs CI green on the final commit and the other reviews.

| # | Outcome | Evidence |
|---|---|---|
| C12 | Fixed | Both commands are gone, and no file operation remains in any debug-script source (`Sources/PhotoApp/Model/Debug*`, `Sources/PhotoUI/Import/ImportDebugCommands.swift`). DR22 now fails the sampled render in memory, through the same failure branch as a real read error. |
| C13 | Fixed | The batch is cancelled only when `alignmentTask` is nil, and the editor's own measurement always has a task while it runs, so a batch for other photos goes on. The paste-measuring case (C7) still stops. By reading; the engineer also ran `pasteadjust loupeuncheck` and `pasteadjust uncheck`. |
| C14 | Fixed | Both rows now say 800%, which is `PixelMagnifierLevel.standard`. |

**`debugFailsSamplePixels`:** it can't affect a normal run. Its only writer is `DebugLensCommands.swift:78`, reached only from `DebugScript.run` (`DebugScript.swift:224`). The script starts only when `--debug-script` is on the command line (`LaunchOptions` reads `CommandLine.arguments` only, no preference or environment value). The flag is in memory, starts false and is never saved. When false, the only change on the normal path is one Boolean check before the same render.

**The file-operation scan test (`LensReviewFixesTests.swift:39`):** keep it. It fails when a `moveItem` call is put back (trial revert), its `paths.count >= 3` check stops it passing by scanning nothing, and it follows the source scans in `BrandingTests` and `LocalizationTests`. It is a tripwire, not proof: it lists five `FileManager` calls, so a write through `Data.write` or a helper in another file gets past it, and it skips `ImportDebugCommands.swift` in PhotoUI. It is unlikely to fail for an unrelated change. Not worth a finding.

**New findings:** none. The new script modes wait with a bound and change a photo only inside `pasteadjust`'s undo group.

**Older compilers:** the only new expressions are a typed closure returning `Result` and simple loops in the test and script code, with no chained arithmetic closures.
