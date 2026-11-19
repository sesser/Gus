# Lens corrections (distortion and lens vignetting): code review

Owner: code-reviewer. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/lens-corrections`, c97d579..ad9b419 (13 commits). Build and
tests: `swift build` passes; the full `swift test` passes, 1234 tests in 176
suites (68.2 s; the opt-in suites skipped as usual).

## Verdict

Not ready for QA yet, but close: the stack, the renderer, the parsers and the
frame question are sound, and nothing that existing photos render changed. Three
Should-fix findings are left: a main-thread stall the first time the Lens heading
shows after a build (C1), a slow paste or preset with no feedback before the frame
question (C2), and debug-script pastes that can now register undo outside their
group (C3). The six Nits can be fixed at the same time or recorded.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Model/LensCorrectionActions.swift:13-16`, `Views/LensCorrectionGroupView.swift:13`, `Edits/Kernels/LensKernels.swift:43-45` | The group view's `body` calls `editor.lensStatus`, which reads `AdjustmentRenderer.lensCorrectionKernelsAvailable`, so `LensKernels.isAvailable`, so `compiled.get()`. `compiled` is a lazily initialized `static let` (swift_once), so the first read on the main actor compiles every Lens kernel there, or waits for the `.utility` task `prepareLensKernelsOnce` started. Before this branch nothing on the main actor touched `compiled`: renders skip it for an identity plan, and Color Fringes' UI never reads it. | First launch after a build or an update (the kernels' Metal cache is cold: "about 2 s", `prepareLensKernels`'s doc), open a photo in the loupe with the Adjust tab's Lens heading open: the main thread blocks until the compile finishes, about 2 s less the load's own awaits. The beach ball shows and input stops. Later launches take a few ms. | CLAUDE.md Concurrency (no heavy work on the main thread) |
| C2 | Should fix | `Model/LensCorrectionActions.swift:143-160, 173-176` | Before it asks, `confirmingLensFrameChange` reads the file of every target that has masks or spots and uses Auto before or after. It does this one target after another in one detached task, through the full `RawDefaults(source:)` (status.md Q1: 20 to 85 ms each). Nothing shows while it reads, and the command stays available. `lensQuestionTask` is also overwritten by a second command, whose handle the first task's `defer` then clears. | A shoot with dust spots on 200 raws, all selected, then Apply Preset with Distortion on Auto: 200 × 20 to 85 ms = 4 to 17 s with no alert, no Activity line and no change. A second Apply or Paste in that time starts a second read, and later a second alert. Only `isLensCorrectionSupported`/`Enabled` and the tables are needed (one `CIRAWFilter(imageURL:)` and `CameraLensState.read`). Read them concurrently, or show the batch status line the measuring paste uses. | CLAUDE.md Concurrency (async and cancellable work) |
| C3 | Should fix | `Model/AdjustmentActions.swift:32-43`, `Model/PresetActions.swift:33-37`, `Model/DebugScript.swift:247-251, 472-475, 739-744` | Every paste is now asynchronous: it waits for `savedEditStacks` of all targets before `applyAdjustments` registers its undo step, even when no lens group is involved. Before this branch a paste without color-alignment measuring was synchronous. Only the debug script's `pasteadjust` and `preset apply` wait for it (`waitForBatchMeasuring`, now including `lensQuestionTask`). `key`, `menupress`, `menupick` and `contextmenu` are in `changing` but close their group after 80 or 300 ms without waiting. | `menupress Paste Adjustments` (or `key` with ⌘V, or the grid's context menu Paste) on a library whose write chain is busy, or a large selection: the read returns after the command's group has ended. `registerUndo` then runs outside a group with `groupsByEvent` off, NSUndoManager raises, and the script crashes later (CLAUDE.md, debug script). In the app, ⌘V followed quickly by ⌘Z undoes the step before the paste. Fix: have the script loop wait for `lensQuestionTask` after every grouped command, not only in `waitForBatchMeasuring`. | CLAUDE.md debug script: a change saved after an await waits inside its undo group |
| C4 | Nit | `Model/AdjustmentEditor.swift:718-724, 893-897` | `resetAll()` sets `commitSkipsLensQuestion` before `change`. `commit` clears it only after `guard let item, adjustments != committed`. A Reset All that changes nothing therefore leaves the flag set for the next commit. | A photo with a spot, Manual Distortion 30 and an operation this build does not know (so `isDefault` stays false and Reset All stays enabled). Reset All (the spot goes, and the flag is used), Reset All again (no change, flag left set), ⌘Z (spot and Distortion back, through `apply`), then drag Distortion's Amount: no question. AC6 wants one. Fix: clear the flag in `resetAll` after `change` (`defer`). | PRD R6, AC6 |
| C5 | Nit | `Edits/LensProfileCorrections.swift:44-49, 94-98`; `Edits/LensWarp.swift:28-30, 306-330` | A stored `amount` is read without the −100…100 range. The plan uses it as it is. `ColorAlignment`, the other geometric step, clamps on read (`LensCorrections.swift:258-266`). | A stack with `lensDistortion.amount` 2000 (a `.guspreset` written by hand, or a later build with a wider range) gives c = 1.6, so `ratio` is negative beyond ρ 0.79. The picture folds onto itself at the corners, Constrain's scale comes out of `max` as 0.42, and the slider shows a value beyond its ends. No crash (checked: every value stays finite). | Stored values from outside (CLAUDE.md, security: parsers of preset files) |
| C6 | Nit | `Preview/CameraLensState.swift:182-183` | `reader.read(Int(list.count), at: reader.valueOffset(list))` treats the entry's field as an offset whatever the count. A TIFF entry of 4 bytes or fewer holds its value in the field itself. | A DNG with an empty `OpcodeList3` (4 bytes, count 0) reads 4 bytes at offset 0 (`II*\0`, a count of 0x49492A00), so `parse` throws and the file reads as `.unreadable`. Auto then shows the warning row 5 ("could not be read") for a valid file. Fix: use `list.field` when `count <= 4`. | Parser correctness |
| C7 | Nit | `Preview/PreviewGenerator.swift:306-308`, `Preview/CameraLensState.swift:83-86` | For a LibRaw decode, `.builtInCorrection` is decided again from the file. `LibRawDecoder` also needs `frame.window != nil` (the camera's frame within LibRaw's image) and a successful `EmbeddedLensCorrection.apply`, and it reports the result in `Output.hasLensCorrections`, which is ignored here. | A RAF whose camera frame is not within LibRaw's visible area, or any LibRaw RAF when the Lens kernels fail. LibRaw applies no correction, but the state is `.builtInCorrection`, so Auto is inert and the caption says "Applied by the camera's own table". Use `output.hasLensCorrections` in `decodeWithLibRaw`; the editor can keep the file rule for its first read. | PRD R4, R12 |
| C8 | Nit | `Model/LensCorrectionText.swift:24-25`; String Catalog | `readingLabel` ("Reading the camera's table") is never used, because row 4 of design §4 is not built (status.md Q3). The catalog entry is dead too. | — | Dead code |
| C9 | Nit | `Edits/LensCorrectionDebug.swift`; `Tests/PhotoCoreTests/LensCorrectionTests.swift:446-453, 534-541` | `LensCorrectionDebug.fault` is process-global. `kernelFailure` and `corruptSwitch` set it in a `.serialized` suite, which serializes only within that suite. `GoldenTests` (five lens cases), `LensRenderingTests` and the other suites run in parallel. | While the switch is set (a short window), a parallel golden render of `lensDistortion-barrel-lensGrid` builds its graph with `isAvailable` false and renders uncorrected, so the golden fails as a flake. Use a `@TaskLocal` or pass the fault in. | Tests deterministic |

## Questions

For the engineer, recorded rather than reported as findings because I could not
make them fail:

- **Q1. The decoder's flag under the stack's own settings.** Renders read
  `isLensCorrectionEnabled` from the filter after `settings.apply(to:)`. With the
  machine learning noise reduction that filter has decoder version 9, and for a
  crop of an aspect-cropped ORF or RW2 it is the whole-sensor copy. The editor
  reads the flag with `RAWDecodeSettings.none`. If version 9 enables the
  correction differently ("the default value can vary based on the image",
  CIRAWFilter.h), the caption and the render disagree. Can one owner file with
  ML noise reduction on be checked (`lens print` against `photocli render`'s
  `lensCorrections`)?
- **Q2. An off-center camera frame.** `lensFrame` centers the camera's frame on
  the middle of a whole-sensor decode and ignores `CropRect.x`/`y`. If an Olympus
  `AspectFrame` or a Panasonic crop is ever off the sensor's middle, the manual
  correction's center moves when a crop or a first mask switches the decode to
  the whole sensor. Is that known never to happen? Using `x`/`y` costs one line.
- **Q3. Menus while the frame question is up (for QA's P4).** The question is a
  gate in `commit` while the change is on screen. If a menu key equivalent
  (SwiftUI `Commands`) still fires with the alert sheet up, a second commit asks
  again, and Change saves both changes under the first name. The guards in
  `finishLensFrameQuestion` keep the stack consistent; only the undo name and a
  second alert are at stake. Worth one check with a real keyboard.

No Design questions or Requirements issues: what is built matches the PRD (rev 2)
and design.md as ruled.

## Checked and fine

- **No pipeline bump, no migration, no existing golden or fingerprint moved.**
  `currentPipelineVersion` stays 13. The diff has no migration and no
  `*.fingerprint.json`. Golden commit fdd86c7 adds five new PNGs and their cases
  only (no source change), so it is not an update of an existing golden.
  `AdjustmentRenderer.lens` returns its input object when the plan is identity
  (`untouched` asserts `===`), so stacks without the groups render byte for byte
  as before. The new operations are added only when their parameters are
  non-empty, so the hash of every existing stack is unchanged.
- **Stack model.** Defaults are left out, `on` false is not stored, and the
  explicit `on` works as Black & White's (generalized through
  `EditStack.switchedKinds`). Turning a group off keeps its values in `disabled`;
  `effective` and `LensCorrectionPlan` use the effective values. Reset of the
  heading and Reset All give the identity hash. Unknown operations are kept as
  before. `AdjustmentParameters.swift` describes both modules
  (`AdjustmentParameterTests`). `choosingLensSource` is one step and returns nil
  when nothing changes (AC14). `photocli develop` handles `on` and value-switches-on.
- **Renderer.** Gain, then warp, first in the Lens step, before alignment,
  fringes, spots, masks and the crop. It is one path for previews, live frames,
  the 100% region (whole decode, output cropped), export, `photocli`, the spot
  source finder, the fringe picker and Color Alignment's measurement. Every
  `PreviewGenerator.decode` path sets `RenderContext.lens` (system RAW, LibRaw,
  ImageIO, HDR). Videos and swatches have none, so Auto applies nothing there.
  The frame (`lensFrame`, the camera frame on a whole-sensor decode) is
  scale-invariant, so fit, drafts and 100% agree. The fringe picker and the
  measurement read the corrected image only when a group is on, so no existing
  photo or golden changes (AC5).
- **Kernels.** Both are stitchable, each in its own Metal library (`source(of:)`
  per key). The math was checked line by line against `LensWarp.source` and
  `LensGain.apply`: the transposed matrix, the tangential terms (DNG
  specification), the table index and the white limit. The ROI bounds the edge's
  sources with a 2 px margin; the bulge between the 9 samples per side is under
  0.05 px for these models. All eight orientation matrices were derived by hand
  and agree with `toSensor`. The digest workaround keys the warp's input on the
  warp, scale and frame, so a context cannot reuse another warp's input area; the
  44-bit hash shares the key space with decode serials only in different graph
  positions. The gain kernel's ROI is the identity, so it needs no key.
- **References and tolerances.** `LensCorrectionReference` is plain Swift in
  double precision. The bounds are derived from single-precision coordinates and
  the table step, not tuned, and no tolerance was loosened. The reference shares
  `LensWarp.source` and `scale` with the renderer, so the model itself is checked
  apart from it: `vignettingScale`, `fujifilmWarp` against
  `EmbeddedLensCorrection.outputScale` to 1e-9, `constrainFills`, and my
  derivation of the orientation matrices.
- **Parsers (untrusted bytes).** The DNG list is capped at 1 MiB and 256 opcodes.
  Every read is bounds-checked (`BigEndianReader.bytes`, no overflow on 64-bit),
  the parameter lengths are exact, values must be finite, centers lie in 0…1 and
  coefficients are bounded. IFDs come from the existing `TIFFReader` (at most
  1024 entries and 64 sub-IFDs). Rationals with a zero denominator read as 0.
  Degenerate crops or areas give finite but odd geometry and never trap. The RAF
  check (`hasLensTags`) reads within the existing capped raw-section buffer.
  Nothing is written, and no path comes from a file.
- **Frame question.** One gate in `commit`; Change saves one step on the
  `persist` chain; Cancel restores the saved values and records nothing. Undo,
  redo and History go through `apply` and never ask. Reset All skips it (C4
  aside). Once per visit, by the count of masks and spots, cleared in
  `finishSession`. Paste and presets ask once with counts and don't ask twice on
  the loupe's photo (`noteLensFrameAnswered`). The file reads for it run off the
  main actor.
- **Debug script.** `lens …` opens a group only when the change records at once
  (`changesPhoto`); `alert press Change` and `alert key return` group the answer,
  and Cancel and Esc do not. `lens force` is debug only. The default-button change
  to `alert key return` leaves alerts without a default button as they were.
- **UI rules.** `AppKitSegmented.enabledSegments` keeps every other use as it was
  (empty means all enabled), and the check boxes are `AppKitCheckbox`. No SwiftUI
  `ScrollView`, and no model passed into `Commands`.
- **Strings, branding, dependencies, clean room.** `LocalizationTests` and
  `BrandingTests` pass; the plural variation of the count message is in the
  catalog. Persisted names (`lensDistortion`, `lensVignetting`, `source`,
  `amount`, `constrain`, groups `distortion`, `lensVignetting`) carry no product
  name. `Package.swift` is unchanged and nothing is vendored. The DNG opcodes
  follow the published specification; the Adobe sample was used only as input
  and is not committed.

## Follow-up

(For the second pass: each finding Fixed, Not fixed (and why) or Withdrawn, with
the commit.)
