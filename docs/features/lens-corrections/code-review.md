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

Second pass, 2026-11-19: f0ccf8e (the fixes for C1 to C9, Q1 to Q3 and the
designer's F1 to F5; `status.md` "Review findings"). `swift build` passes; the
full `swift test` passes, 1239 tests in 176 suites (71.0 s). No golden,
fingerprint, migration or `currentPipelineVersion` change in the commit.

**Verdict of the second pass: not ready for QA yet.** Every first-pass finding
is closed. The batch read that fixes C2, though, brought two new Should-fix
findings, C10 and C11. Both are small fixes in `confirmingLensFrameChange`.

### First-pass findings

| # | Result | Commit | Note |
|---|---|---|---|
| C1 | Fixed | f0ccf8e | The main actor now reads only `lensCorrectionKernelsKnownUnavailable` (an `Atomic` the `compiled` initializer sets, plus the debug fault), which never touches `compiled`. The only other reader of `lensCorrectionKernelsAvailable` is `photocli` (`RenderCommands`), which is not on the main actor. `prepareLensKernelsOnce` still starts the detached utility compile, and a main-actor `Task` bumps the observed `lensKernelsRevision` when it ends, so the groups redraw (row 3 if it failed). Until then the groups count the kernels as available, which is right for every machine where they compile. |
| C2 | Fixed, with the new findings C10 and C11 below | f0ccf8e | Stacks are read, then `frameCandidates` runs detached. Files are read only for candidates with Auto, four at a time in a task group, through `CameraLensState.read(url)` (one `CIRAWFilter`). Progress is under the command's title, and Stop cancels it. `readLensState` is `nonisolated async` in a Swift 6.0 tools package (no `NonisolatedNonsendingByDefault`), so the reads run off the main actor. |
| C3 | Fixed in the debug script. The app limit is accepted (see Known limit) | f0ccf8e | `waitForBatchWork` now runs after every grouped command and after a grouped `alert press`/`alert key`. Its loop ends because each run's `defer` clears `batchAutoTask` when it still owns the run, and the measuring paste the body may start takes the handle over. The loupe's photo alone is decided from `committed` and the editor's `lensState`, and `changeAdjustments` registers its undo synchronously, so ⌘V then ⌘Z in the loupe is right. |
| C4 | Fixed | f0ccf8e | `commit` reads and clears the flag before its guard, and `resetAll` clears it in a `defer`. |
| C5 | Fixed | f0ccf8e | Both `init(_ values:)` clamp to −100…100 (`storedAmountClamped`). A round trip writes the clamped value back the next time the photo is saved: the stored hash changes once and the render does not, as with Color Alignment. `Adjustments` equality compares clamped values, so the clamp never causes a write by itself. JSON cannot carry NaN, so `min`/`max` passing NaN through cannot happen. |
| C6 | Fixed | f0ccf8e | A count of 4 or less reads `list.field` (`emptyOpcodeList`). The guard above it means the count is exactly 4 there. |
| C7 | Fixed | f0ccf8e | `libRawLensState` uses `Output.hasLensCorrections` (`libRawBuiltIn`). The editor's first read keeps the file rule, as suggested. If LibRaw's correction failed, its caption can say "the camera's own table" while the render has `.tables(.none)`. Auto applies nothing in either case, so nothing renders twice. |
| C8 | Fixed | f0ccf8e | The string and its catalog entry are gone. `LocalizationTests` passes. |
| C9 | Fixed | f0ccf8e | `@TaskLocal taskFault` is read first by `fault`. No test sets the process-wide switch any more (grep), and both tests read it synchronously in the same task. The debug script's switch is unchanged. |
| Q1 | Answered | — | Checked on the owner's files: the flags agree under the stack's settings. Version 9 could not be tried because no camera on hand is offered it. Renders read the flag from the filter that decodes, so they can never double-correct. Nothing more is needed here. |
| Q2 | Fixed | f0ccf8e | See "lensFrame" below. |
| Q3 | Guarded | f0ccf8e | `change` and `confirmingLensFrameChange` do nothing while the question is up. Whether a menu key equivalent reaches the window with the sheet up stays QA's P4. |

### New findings (second pass)

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C10 | Should fix | `Model/LensCorrectionActions.swift:172-173` | Every Paste Adjustments on the grid, and every preset with Distortion, now cancels `batchAutoTask` and starts a new `batchAutoRun` before it has read anything. It does so whether or not the paste involves the lens, or will read a file or ask. On `develop` a paste that does not measure was synchronous and never touched a running batch, and before f0ccf8e this branch's read had its own `lensQuestionTask`. | Select 300 photos and run Auto Exposure (about a minute, with progress in Activity). Then select other photos and paste only an Exposure change. Auto Exposure's task sees `Task.isCancelled` and writes nothing, its `defer` no longer owns the run, and its Activity line is replaced and then cleared. Nothing tells the person their Auto Exposure was dropped. A running measuring paste or preset on other photos is dropped the same way. Fix: keep the read on a handle of its own, as the question task was, and have `waitForBatchWork` wait for it too. Alternatively, take over `batchAutoTask` only once there are files to read, though even then it ends someone else's measuring. | CLAUDE.md Undo: each step records what it changed. A command the person started must not vanish without a message. |
| C11 | Should fix | `Model/LensCorrectionActions.swift:183, 212, 227` with `AdjustmentActions.swift:41`, `PresetActions.swift:53` and `AdjustmentActions.swift:56` | The question is asked about `targets`, captured when the command starts. `body()` then runs `pasteAdjustments`' or `applyingAdjustmentPreset`'s own `batchSelection(action:)` (or `changeAdjustmentsMeasuringAlignment`'s), which reads `actionTargets` again after the awaits. So the change lands on whatever is selected when the read ends or the answer comes. This was already on the branch at ad9b419, and I missed it in the first pass. C2's fix makes it easy to reach, because the read now takes seconds and shows in Activity while the grid stays usable. | Select 200 raws with spots and Distortion on Auto, and paste a preset with Distortion Manual. While Activity shows the read, click one other photo (no spots). The alert then says "N of 200", and Change applies the preset to the one clicked photo only, as one undo step. The 200 are unchanged. If the person instead presses Return to open the loupe and pastes there, the loupe's photo is pasted twice: once at once by the loupe path, and again when the grid read ends. Fix: take the version IDs (`batchSelection`) when the command starts and pass them to the body. `applyAdjustments(toVersions:)` already takes them, and `changeAdjustmentsMeasuringAlignment` needs an `ids` parameter. | PRD R6/AC6 (the question covers the photos changed); correctness |
| C12 | Nit | `Model/LensCorrectionActions.swift:182-184` | `try? await writes.savedEditStacks` turns `CancellationError` into "could not read", and that branch runs `body()` without asking or checking `batchAutoRun.owns(run)`. `WriteChain.read` throws `CancellationError` when the task is cancelled (`try Task.checkCancellation()` before and after the fetch). | Paste A onto a selection with masks and Auto Distortion while saves are queued. Before A's read returns, apply preset B (or Auto Exposure). B cancels A, so A's read throws, and A's paste is applied anyway, unasked. Fix: `catch is CancellationError { return }`, and run `body()` only on a real read failure, as before. | AC6; the doc comment ("Stop … or a newer paste or preset ends it") |

### The points asked about

- **Batch task, run token, Stop.** The token logic is right: each `defer` clears
  only its own run, and a measuring body started from inside the task takes the
  handle over without being cancelled (it is a new unstructured `Task`). Stop
  cancels the task, the chunk loop and the guard after it return, and the
  `defer` clears the progress. At most four synchronous reads are still in
  flight when Stop comes. Stop is not offered before the reads begin (no
  progress yet) or while the alert is up (progress cleared), which is fine. The
  problems are C10 (what it cancels), C11 (what the body applies to) and C12
  (cancellation treated as a read failure).
- **Activity progress.** It is shown only when files are read, under the
  command's title, and counts reads. `lenses` is seeded with the open photo, so
  the count would be one ahead whenever the open photo is among several
  targets. That cannot happen: the loupe's targets are its one photo, which
  takes the immediate path, and the editor is `idle` in the grid (`follow(nil)`).
  Not a finding.
- **Question state machine.** `markAskingLensFrame` brackets `WindowModal.run`.
  `change` refuses while asking, so a spot nudge's timer or a menu change can't
  raise a second alert. `finishLensFrameQuestion` clears the flag before it
  restores or applies. Cancel restores through direct assignments, not
  `change`, so the new guard doesn't block it. The loupe path's question
  `Task` is not tracked. A second ⌘V before that `Task` first runs would ask
  twice, but key events are delivered after the main queue drains, so I could
  not make that happen.
- **Loupe paste decided at once.** It is decided from `committed` and the
  editor's `lensState`, with the same `lensFrameAnswer` rule as the batch path.
  With no question, `body()` registers undo synchronously. With a question,
  undo registers on Change, and the script groups that through `alert press`.
  Correct.
- **`lensCorrectionKernelsKnownUnavailable`.** It never compiles. The `Atomic` is
  written with `.releasing` and read with `.acquiring`. The redraw comes from the
  first editor's main-actor `Task`. The debug fault is honored. See C1.
- **`CameraLensState.read(url)`.** It makes the same decision as
  `SystemRAWDecoder.reads` (`givesImageUntouched` sets the filter up as
  `RAWDecodeSettings.none`) and reads the same flags `RawDefaults` reads after
  it. It builds a graph and never renders, and `RAWDecodeGraphTests` lists it
  so. Non-raws are `.notRaw`, and raws the system can't decode get the file rule
  (as C7 for the editor). It is used only off the main actor.
- **`lensFrame` offset.** No existing render or golden changes. `lensFrame` is
  called only by the Lens step, which returns its input for an identity plan, and
  Distortion and Lens Vignetting are new on this branch. `cameraFrame` is set
  only for a system decode of the whole sensor (`PreviewGenerator.swift:370`;
  Olympus `AspectFrame`, Panasonic crop). It is nil for LibRaw (Fujifilm RAFs
  already come out in the camera's frame, and their built-in correction does
  not use `lensFrame`), for ImageIO and in every golden (no `cameraFrame` in the
  golden tests). For a centered camera frame the new rectangle equals the old
  one. `CameraFrame.rect` is oriented and y-from-top. The conversion
  `minY + (1 − y − h)·H` matches how `Crop` places the same `CropRect`
  (`Crop.swift:179-181`). `lensFrameOffCenter` pins it.
- **`$taskFault`.** See C9. Renders that read it from another task (detached work
  inside a render) see only the process switch. No test relies on that.
- **Clamping on read.** See C5. Stack round-trip and hash are as for Color
  Alignment. `setAmount` still refuses out-of-range values rather than clamping,
  as before.
- **Known limit: a grid paste's ⌘Z during the read undoes the previous step.**
  Acceptable. It is the same as a measuring paste or preset (undo registers after
  the per-photo awaits) and as `copyAdjustments`' chain read. The window is
  normally the write chain's settle plus one catalog read (milliseconds). When
  files are read, Activity shows it, as it does for measuring. It needs no
  change, but it should stay in the user guide or `status.md` as a known limit.
  Fixing C11 does not widen it.

### For the main session

- `/security-review`: nothing new beyond the first pass. The commit changes no
  parser bounds except C6's (which only narrows the read), adds no subprocess,
  no file writing and no network code. The opcode reader and the RAF check are the
  branch's parsers, already in scope from the first pass.
- No Design questions or Requirements issues.

## Follow-up, third pass

Third pass, 2026-11-19: dc89c81 (C10 to C12, the designer's F6 to F8, the
debug command `lens pastethenfocus`) and 6dfb005 (user guide). a0df578 (the
designer's `review.md`) is docs only. `swift build` passes. Full `swift test`:
the first run had 1 failing test out of 1239. Only the tail of that log was
kept, so I can't name it. Four more full runs passed, each 1239 tests in 176
suites in 68.6 to 71.3 s. None of the reviewed commits touches a test, a
golden, a migration or `currentPipelineVersion`. The failure is most likely an
existing intermittent test unrelated to this change, but that is unconfirmed.
QA's full run should keep its whole log.

**Verdict of the third pass: ready for QA.** C10, C11 and C12 are fixed, and so
are F6 and F8 from the code side. No new Should-fix finding. There are two new
Nits (C13, C14), both narrow timing cases. I confirm the designer's F9 from the
code. It is the only thing I would fix before QA, because the result is an
Activity row that never ends and a Stop that does nothing.

### Second-pass findings

| # | Result | Commit | Note |
|---|---|---|---|
| C10 | Fixed | dc89c81 | The read and the question run on `lensQuestionTask` with their own token, `lensQuestionRun`. No code path in `confirmingLensFrameChange` touches `batchAutoTask`, `batchAutoRun` or `setBatchAutoProgress` (grep: the only claimants are `BatchActions` Auto Exposure and `changeAdjustmentsMeasuringAlignment`, as on `develop`). The measuring body still takes `batchAutoTask` when it measures, which is `develop`'s rule. Activity's "lensread" job Stop cancels only `lensQuestionTask`. `waitForBatchWork` waits for either task unless the question is up. The second command takes over the first: the grid path cancels the older task and begins a new run, and each guard (217, 226, 248) and the `defer` check `owns(run)`. The exceptions are C13 and F9. |
| C11 | Fixed | dc89c81 | `commandTargets` is read once, before any await, and handed to `body`. Videos stay in it so `batchSelection` still counts skipped videos. `batchSelection(action:targets:)`, `applyingAdjustmentPreset(_:targets:)` and `changeAdjustmentsMeasuringAlignment(…, targets:)` use it. After that, everything looks photos up by id (`item(versionID:)`, the catalog's `editStacks`). The loupe path: one target, the open one, decided synchronously from `editor.savedAdjustments`. With no question, `body` and its undo registration run before the call returns. With a question, the alert is a sheet on the window, so the open photo can't change while it is up. A loupe paste no longer applies twice when the grid read it supersedes asked a question (that path cancels the older task). It can still apply twice when it takes the no-question path: see C13. The one remaining live read between question and change is `mode == .loupe` in the measuring path: see C14. |
| C12 | Fixed | dc89c81 | `catch is CancellationError { return }` writes nothing, and the `defer` clears the row only for its own run. `WriteChain.read` throws `CancellationError` before and after its fetch, so a cancelled task can't get stacks back. A genuine error runs `body` only while `lensQuestionRun.owns(run)`. Stop can't come between the cancel and that check, because the read's Activity row (and so its Stop) appears only after the stacks are read (214). |
| F6 | Fixed (code side) | dc89c81 | `ToolbarMetrics.statusLine(name:)` with the same "Apply Preset %@" key as the measuring path. It reaches `setLensReadProgress` at both sites and the job's `toolbarTitle`. |
| F7 | Fixed | dc89c81 | Same change as C10. |
| F8 | Fixed | dc89c81 | Comments and the catalog comment agree. The catalog's key is unchanged, so `LocalizationTests` is unaffected (it passes). |

### Checked in this pass

- **Two commands in flight.** Grid then grid: the newer one cancels the older.
  The older one returns from the stack read (`CancellationError`), from the
  chunk guard or from 226, and writes nothing. While the question is up, a newer
  paste or preset does nothing (162). Each measuring body that starts takes
  `batchAutoTask` over from an earlier measuring body, as on `develop`.
- **Undo registration.** `changeAdjustments` registers synchronously inside
  `body`. On the grid path that happens on the main actor after an await
  (outside an event), the same as `develop`'s measuring paste. The step's
  `before` and `after` come from the write itself, so a version that was gone by
  then simply isn't in the step.
- **Photos removed or going offline during the read.** The `CatalogItem`s are
  snapshots, but only `versionID`, `isVideo` and `volumeID` are used. A removed
  version is absent from `Catalog.editStacks(forVersions:)` (a filtered fetch), so
  `changeEditStacks` and its undo step skip it. The measuring path drops it at
  `item(versionID:)`. `isOffline` and `sourceURL` are evaluated in `body`, so a
  volume unmounted during the read gets the measuring path's offline warning. A
  non-measuring paste still changes offline photos, as on `develop`. The
  question's count can include a photo removed during the read, which is
  harmless.
- **`lens pastethenfocus`.** `changesPhoto` returns true, so the command gets
  its own undo group, which is the same rule as `pasteadjust`. The command
  awaits `waitForBatchWork`, and so does the loop. When the paste asks, the wait
  ends on `isAskingLensFrame` and `alert press` registers the step in its own
  group. That is the same as `pasteadjust` (the group closes with nothing in it).
  `setFocus` runs synchronously after `pasteAdjustments`, before the task's first
  await, so the command really does change the selection before the read ends,
  even with no file to read.
- **F9 (designer), confirmed by reading the code.** `setLensReadProgress` at 214
  and 223 has no `owns(run)` check. A superseded task that is between its
  detached `frameCandidates` and 214, or inside a chunk, writes the row after the
  newer run cleared it. It then returns at 217 or 226, and its `defer` no longer
  owns the run. The row stays, and its Stop cancels the nil or finished
  `lensQuestionTask`. The designer's fix is right: guard both writes with
  `lensQuestionRun.owns(run)`.

### New findings (third pass)

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C13 | Nit | `Model/LensCorrectionActions.swift:165, 169`; `PresetActions.swift:35` | The doc comment (157) and `status.md` C10 say a newer paste or preset ends a pending read. Only the grid path and the loupe path that asks actually cancel `lensQuestionTask`. These paths return without cancelling it: the loupe paste or preset that needs no question (169), a selection of videos only (165), and every preset without Distortion (`PresetActions.swift:35`). In those cases the pending read later applies the older command after the newer one. | Select 40 RAFs with a spot and Distortion Auto, and apply preset X (with Distortion). While Activity shows "N of 40", open one of the 40 in the loupe and apply preset Y (no Distortion, or no frame change). Y is saved. Then X's read ends and X is saved over all 40, the loupe's photo included, so for the groups both presets set, that photo shows X, the older command. ⌘Z undoes X first. With the same copied adjustments pasted twice, the second write records no history entry (`hasSameContent`), but it adds a second undo step. `develop` already does this with a measuring paste followed by a plain preset, so this is not a regression of kind. | Correctness; the doc comment. Fix: either cancel the pending read (`lensQuestionTask?.cancel()`, `lensQuestionRun.begin()`) at the top of `confirmingLensFrameChange` after the 162 guard and in `applyAdjustmentPreset`'s direct path, or reword 157 and `status.md` to "a newer paste or preset that reads". |
| C14 | Nit | `Model/AdjustmentActions.swift:67, 71, 107` | `changeAdjustmentsMeasuringAlignment` decides `inLoupe = mode == .loupe` when `body` runs, which is now after the read (and the question). It then marks the editor's current photo as measuring, and as failed if any target's original can't be read, without checking that this photo is a target. | Select 20 raws with spots and Distortion Auto in the grid, and paste a copy with Align automatically on. During the read, press Return on another photo, Q, to open it. When the read ends, Q's Color Alignment caption says it is measuring for the whole batch. Unchecking Align automatically on Q then cancels the 20-photo paste (`AdjustmentEditor.swift:1995`, `batchAutoTask?.cancel()` when the editor has no task of its own). If one of the 20 originals is unreadable, Q says "This photo could not be measured" although nothing touched it. `develop` has a narrower form of this: `inLoupe` was taken at the command, and the open photo can change while measuring. The read widens the window. | C11 (live state read between question and change). Fix: set measuring and failed only while `editor.item?.versionID` is a target (or the single target), checked when they are set. |

### For the main session

- `/security-review`: nothing new. These commits add no parser, subprocess, file
  writing or network code.
- No Design questions or Requirements issues. C13's choice (end the pending
  read, or let it land after) is small enough for the engineer. If the owner
  wants a rule, it is a Design question for DQ-5.
- Next: F9 to the engineer (a two-line guard), with C13 and C14 optional, then
  qa-tester. If they are fixed, a fourth pass needs only the new commit.
