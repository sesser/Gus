Issue: #87

# Lens corrections (distortion and lens vignetting): status

Owner: swift-macos-engineer. Branch `feature/lens-corrections` (off develop
c97d579). Spec: the PRD (issue #87, revised 2026-11-19) and
[design.md](design.md) (amended 2026-11-19).

**State: Done** (2026-11-19). Everything the PRD and the design ask for is built
and tested, as the owner ruled on 2026-11-19 (see Rulings): Auto reads Fujifilm
RAF tables and DNG opcodes; the other makers' readers and DNG `GainMap` are
follow-ups. The open technical questions are answered below from the code and the
owner's files (read through a copy of the catalog; nothing in the library was
opened or changed). Next: code review and the designer's review, then QA;
`/security-review` applies (a DNG opcode list parser and RAF tag reads).

## Build and test

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline (develop c97d579 plus the design commits, before any change) | Pass (two existing warnings in `SmartAlbumTests.swift`, `VirtualCopiesTests.swift`) | 1204 tests in 175 suites pass |
| After the 2026-11-19 rulings (ad9b419) | Pass, no new warnings | 1234 tests in 176 suites pass (71.9 s); `dngSample` passes opt-in on Adobe's sample; `Scripts/build-app.sh` passes |
| After the first reviews (f0ccf8e) | Pass, no new warnings | 1239 tests in 176 suites pass (70.3 s); `Scripts/build-app.sh` passes |
| Latest (after the second passes) | Pass, no new warnings | 1239 tests in 176 suites pass (73.1 s); `Scripts/build-app.sh` passes |

`PreviewCacheKey.currentPipelineVersion` stays 13: a stack without the new
operations renders byte for byte as before (the lens step returns its input
object untouched, `untouched` test), and a stack that turns a group on has a new
render hash, so new previews by itself. No migration. No existing golden moved:
`GoldenTests` failed only on the five new cases until they were recorded with
`UPDATE_GOLDENS=1` in their own commit (fdd86c7); that run rewrote the six RAW
golden fingerprints on this macOS build (#214), and those rewrites were reverted.

## Answers to the open technical questions

Measured on macOS 27.2.1 with the system RAW decoder as the app sets it up for
an untouched photo (`RAWDecodeSettings.none`, which pins the decoder version),
and on one file per camera and lens in the owner's library (45 combinations).

### Q1. Can we tell per file whether the system decoder already corrected it?

**Yes.** `CIRAWFilter` has `isLensCorrectionSupported` (read-only) and
`isLensCorrectionEnabled` (read-write, "the default value can vary based on the
image", CIRAWFilter.h). The app has never set either, so the decoder applies its
correction exactly when both are true. One read of the filter the editor already
opens (`RawDefaults`, 20 to 85 ms, part of the load before the tab is ready) and
the one every decode opens gives the answer, so the editor's status and every
render agree.

On the owner's files:

| Files | Supported, enabled | The file carries a table |
|---|---|---|
| Panasonic GX7 II with Lumix 12-32, 15, 20; ZS100 | yes | yes (`DistortionCorrection` 1) |
| GX7 II with Olympus 40-150 | no | no (`DistortionCorrection` 0) |
| E-M5 III with Olympus 12-45, 25, 45, Lumix 20 | yes | yes |
| E-M5 III with manual and adapted lenses (Rokinon 12, OM Zuiko, Canon FD) | no | no |
| X-E3 with XF18-55, XF27, XF35 (uncompressed, system-decoded) | yes | yes |
| **X-E3 with XF14 (134 files) and XF23 f/1.4 (14 files)** | **no** | **yes** (Fujifilm tables: distortion all 0, vignetting down to about 77% at the corner for the 14) |
| Sony A7 III with Tamron 28-75 | yes | (not checked) |
| **Sony A7 III with FE 35mm F2.8 ZA** | **no** | **yes** (Sony `DistortionCorrParams`, `VignettingCorrParams`) |
| Canon 5D II and 6D, every lens | no | no table we know of |
| HDR merges (`-HDR.dng`) | no | no opcodes |

A DNG with a `WarpRectilinear` opcode (a sample from Adobe's published DNG
sample files, used only as input, never committed) reports **supported, not
enabled**: the system decoder does not apply DNG lens opcodes by default. So for
a DNG "decoder corrects" is false and Auto reads the opcodes itself.

All 218 X-E3 raws in the library are decoded by the system decoder (uncompressed);
none goes through LibRaw. Fujifilm's built-in correction (LibRaw path) is
therefore known from code (`LibRawDecoder.Output.hasLensCorrections`), not from
these files.

Not verified: whether the whole-sensor copy of an aspect-cropped ORF or RW2
(`CameraFrame.fullFrameFilter`) keeps the decoder's correction. The owner has no
such file (every ORF and RW2 in the library is shot at the sensor's own aspect).
Each render reads the flag from the filter it actually decodes with, so a render
never applies Auto on top of a correction the decoder made; the editor reads it
from the file as opened, which is the same filter for every file the owner has.

### Q2. Is the table read at render time or at paste time? Is any photo refused?

**At render time.** The stack stores Auto, never numbers from a table, so paste
and presets copy the setting and each photo's renders read its own file's table
during the decode (the same place the Fujifilm built-in tables are read for
LibRaw). Nothing needs the file at paste time, so **no photo is ever refused**
by a paste or preset and the Activity "left unchanged" sentence never fires for
these groups; AC8's "reported" is the caption on the photo (design §9 names this
case). An offline photo renders nothing new until its volume is back, as for any
edit.

### Q3. Is a table read slow enough to need a "Reading…" row?

**No.** Reading a RAF's tables takes 0.6 ms (`FujifilmRAF`), a DNG's opcode
list one ImageIO property read, and the decoder's flag comes from the filter the
editor already opens before the tab is ready. The status is known when the
tab's controls appear, so row 4 of design §4 never shows and is not built. Row 7
("This file has a camera correction table", known while the group is off) is
built: the read is cheap.

### Q4. Can a maker's table be applied without its red/blue part (green only)?

**Yes, for every table format seen:**

- Fujifilm: distortion (green reference) and the red and blue shifts are three
  separate tag arrays (`GeometricDistortionParams`, `ChromaticAberrationParams`).
- DNG `WarpRectilinear`: one coefficient set per plane; with three planes the
  green plane's (plane 1) is applied to all three, with one plane that set.
- Panasonic RW2: one set of distortion parameters, no per-color part.
- Olympus ORF and Sony ARW: distortion and chromatic aberration are separate tags.

So L15 holds: Distortion never moves red against green.

### Q5. Does Reset All clear both masks and spots?

**Yes.** `Adjustments.resettingAll()` rebuilds the values from the operations
this build does not understand only; masks (`local`), spots and the crop go with
everything else. Reset All never asks the frame question (design §6).

### Q6. `AppKitSegmented` per-segment enabled flag

Not there today; added (`enabledSegments`, `NSSegmentedControl.setEnabled(_:forSegment:)`).
A selection of -1 already shows no segment selected.

### Other engineering answers (PRD open questions)

- **Schema and pipeline.** Two new operations, `lensDistortion` and
  `lensVignetting` (kind version 1, schema 1, defaults left out, `on` false not
  stored). No migration. A stack without them renders byte for byte as before,
  so no `PreviewCacheKey.currentPipelineVersion` bump: a stack that turns them on
  has a new render hash and so new previews by itself.
- **Mask and spot frame.** Distortion is applied to the decoded image before the
  spots and masks, keeping the image's size, so a stored position (a unit point
  of the mask frame) keeps its numbers and lands on whatever the corrected
  picture shows there (Option A: nothing is remapped).
- **Raw or not.** The editor knows from `SupportedFormats.isRaw` (the extension)
  and `SystemRAWDecoder.reads` (`RawDefaults`); a LibRaw-decoded raw is a raw.

## What was built

- **PhotoCore**
  - `Edits/LensProfileCorrections.swift`: `LensDistortion` (kind
    `lensDistortion`: `on`, `source` auto|manual, `amount` −100…100, `constrain`
    default true) and `LensVignetting` (kind `lensVignetting`: `on`, `source`,
    `amount`), defaults left out; parameter descriptions
    (`AdjustmentParameterTests` covers them). `Adjustments.distortion`,
    `.lensVignetting`, groups `.distortion`, `.lensVignetting` (first under
    `Section.lens`, in the preset list before Color Fringes),
    `setEnabled`/`enableModules` switch them on as Black & White's.
  - `Edits/LensWarp.swift`: the models (`LensRadialModel` manual, DNG
    polynomial, Fujifilm table; `LensGainModel` the same three), their frame
    geometry (center offset, unit radius, orientation), `LensWarp.scale`
    (Constrain to image) and `LensCorrectionPlan` (what applies to one photo,
    and whether a change moves the frame).
  - `Preview/CameraLensState.swift`: per file, read at decode and by the
    editor with one rule: not a raw, the system decoder corrects
    (`isLensCorrectionSupported && isLensCorrectionEnabled` on the filter that
    decodes), Fujifilm's built-in correction (LibRaw), the tables Auto uses
    (RAF green distortion and vignetting; DNG `OpcodeList3` `WarpRectilinear`,
    green plane, and `FixVignetteRadial`), or unreadable. `RenderContext.lens`
    carries it; every decode sets it.
  - `Edits/LensCorrectionRenderer.swift` and two kernels (`lensGain`,
    `lensWarp` in `Kernels/LensKernels.swift`): the gain, then the warp, first
    in `AdjustmentRenderer.lens`, before alignment, fringes, spots, masks and
    the crop. The fringe picker (`fringeInput`) and Color Alignment's
    measurement (`ColorAlignmentMeasurement.measuredImage`) read the corrected
    image.
  - `Edits/LensCorrectionStatus.swift`: the caption row, the dimmed Auto
    segment, the selected segment, for the tab, VoiceOver, `lens print` and
    `photocli`.
  - `Edits/LensCorrectionDebug.swift`: `kernelfail` and `tablecorrupt` switches.
  - `RawDefaults.lensCorrectedByDecoder`; `FujifilmRAF.lensTablesDamaged`;
    `photocli render` prints `lensCorrections` (per group `status`, `applied`);
    `photocli develop` treats the groups' `on` as Black & White's.
- **PhotoApp**: `Views/LensCorrectionGroupView.swift` (the two groups in
  `LensControls`), `Model/LensCorrectionText.swift` (every word),
  `Model/LensCorrectionActions.swift` (the changes, the frame question in the
  loupe and for paste and presets), the gate in `AdjustmentEditor.commit`,
  `AppKitSegmented.enabledSegments`, the magnifier plate ("After lens
  correction"), `Model/DebugLensCorrectionCommands.swift`.
- **Fixtures and tests**: `DNGOpcodes` and `SyntheticDNG.Options.opcodeList3`,
  `TestScene.lensGrid`, `LensCorrectionTests` (30 tests, 42 cases with arguments; `dngSample` opt-in),
  `Reference/LensCorrectionReference.swift`, five goldens.
- **Docs**: `docs/USER_GUIDE.md` (the Lens paragraph, Distortion and Lens
  Vignetting, the magnifier note, the All settings preset note).

## Engineering decisions recorded (design asked the engineer to say)

- **Manual Amount units.** Distortion: `1 − cρ²`, c = 0.08 × Amount / 100
  (ρ in half diagonals): +100 takes the corner from 8% nearer the center.
  Measured on the owner's Lumix 12-32 at 12 mm (`P1180211.RW2`), the system
  decoder's own correction takes points from 0.928 of their radius at ρ 0.93
  (about 7%), so that lens is about +90. Lens Vignetting: `(1 + ρ²)^(2a/100)`,
  the cos⁴ fall-off of a lens whose corner is 45° off axis; ±100 is ±2 EV at
  the corner, 0 at the center.
- **Constrain to image's scale.** For a warp about the frame's middle (manual,
  Fujifilm), the largest source-over-corrected ratio between the short side's
  middle and the corner: the rule of the Fujifilm built-in step, which matched
  the X-E3's own JPEG to a third of a pixel (`EmbeddedLensCorrection.outputScale`;
  equal to it to 10⁻⁹ in `fujifilmWarp`). It fills the frame exactly: for barrel
  correction the picture comes out slightly smaller (more of it kept), for
  pincushion slightly larger (help: "Scale the corrected photo to fill its frame,
  with no empty edge."). For an off-center or tangential DNG warp, the
  smallest scale at which 256 edge points read from inside. See DQ-1.
- **The empty edge (Constrain off).** Opaque black, the same in the loupe,
  previews, export and `photocli` (one kernel). A sample within half a pixel
  of the recorded image repeats its edge pixel.
- **Lens vignetting and white.** A gain above 1 lifts a value at most to white
  (1) and leaves one above white as it is, as the Fujifilm step and the camera
  do, so a clipped sky stays even to the corners; below 1 it scales.
- **Order.** Gain, then warp: the tables give the light where it was recorded.
  A DNG list that puts `FixVignetteRadial` after the warp is read the same way
  (the radius differs by the distortion, a few percent, in a smooth gain).
- **An identity table is no table.** A Fujifilm distortion table of zeros (the
  XF14 and XF23 write zeros), or a vignetting table of 100s, reads as none, so
  the caption says "No distortion table was found" rather than "Using the
  camera's table" for a table that does nothing.
- **Fujifilm built-in** is known from the file the way `LibRawDecoder` decides
  (non-identity tables, a camera frame, tables for that frame); damaged tables
  or a 1.25x crop mode read as unreadable.
- **A Core Image fault, worked around.** A context reused the input area an
  earlier render of the same image with another warp had needed, and repeated
  its edge (seen in `LensCorrectionTests`: a 1 pixel shift at the corner after a
  constrained render). The warp's area callback is not in the graph's digest,
  as `RAWDecodeGraph` found for the RAW decoder. The warp's input goes through
  `RAWDecodeGraph.keyed` with a key from the warp, frame and scale, so each warp
  has a digest of its own and the same warp shares one. Proposed follow-up: the
  existing `lensAlign` kernel's area callback depends on the alignment the same
  way.
- **The frame question** is a gate in `AdjustmentEditor.commit`: the change is on
  screen (a drag's frames included), the save waits; Cancel puts the saved
  values back. Once per visit: the answer is kept with the photo's count of masks
  and spots and cleared when the photo closes; adding one asks again. Reset All
  sets a skip flag; undo, redo and History write through `apply`, never `commit`.
  Paste and presets read their targets' saved stacks first (the file only where
  Auto is involved), then ask once with counts; on the loupe's photo an answer
  given on this visit counts. The question does not wait behind other sheets
  (`LibraryModal`): it is asked from the tab or the menus, which a sheet blocks.

## Acceptance criteria

| AC | How it is checked | Result |
|---|---|---|
| AC1 | `explicitOn` (identity stack; on stored explicitly), `untouched` (no lens step without the groups), every existing golden unchanged, no pipeline bump | Pass |
| AC2 | `distortionMatchesReference` (five amounts on `lensGrid`, CPU reference, bound derived from float), `vignettingMatchesReference`, `vignettingScale`; goldens `lensDistortion-barrel-lensGrid`, `lensVignetting-lighten-grayRamp` | Pass |
| AC3 | `rafState`, `dngFile`, `dngSample` (opt-in) (tables found or not), `otherStates` (a Panasonic or Olympus raw: no table), `captions` (row 8 "No distortion table was found…", row 6), `manualAmountKeptInAuto`; non-raw starts in Manual: `segments` and the scripted check S2 | Pass |
| AC4 | `autoPlan`, `untouched` (Auto on decoder-corrected and built-in raws renders as off; Manual matches the reference on top); real files: `photocli render` of the owner's 12-32 RW2 with Auto: `decoderCorrectsAuto`, not applied (S4) | Pass |
| AC5 | `pickerSeesCorrectedImage` (fringe input and alignment measurement read the corrected image), `vignettingBeforeExposure` (the reference's order; the other order differs) | Pass |
| AC6 | `movesFrame`; scripted S2, S3 (question at commit, Cancel restores and records nothing, Change one step, once per visit, Reset Lens and Reset All and History never, a paste asks once with counts) | Pass (scripted) |
| AC7 | `constrainFills` (no empty pixel with Constrain, empty corner without for pincushion), `cropAfterCorrection` | Pass |
| AC8 | `groupsAndPresets`, `autoPlan` (each file's own tables; no table: nothing, amount kept); render-time lookup, so no photo is refused (Q2) | Pass |
| AC9 | Non-raw state (`otherStates`, `segments`); the JPEG of a pair is a non-raw file with its own stack (edits are per file) | Pass; a pair by eye is P3 |
| AC10 | One renderer: every decode sets `RenderContext.lens`; previews, live frames, the 100% region, export and `photocli` all render through `AdjustmentRenderer` | By construction; no new test of the 100% region against fit (proposed P5) |
| AC11 | `kernelFailure`, `corruptSwitch`, `rafState` (damaged), `dngFile` (damaged), captions rows 3 and 5; `lens force` in the debug script | Pass |
| AC12 | `resetAndRoundTrip` (identity hash); unknown newer stacks are refused by the existing reader (unchanged) | Pass |
| AC13 | Five goldens (fdd86c7), CPU references in `Reference/LensCorrectionReference.swift`, `dngSample` (see the note under Rulings); by eye: Lens Vignetting with Auto on the XF14 and XF23 files against the camera's JPEG is the owner's (P1) | Goldens pass |
| AC14 | `choosingSource` (off, never on or unchecked: a segment turns the group on with that source in one change; the values before are what one Undo writes back; on with that source: nothing); the editor uses the same rule (`setLensSource`); scripted S5 | Pass |

## Scripted checks (debug script)

Bundle copy `me.sesser.gus.debugtest.lens87`, ad hoc signed, scratch library from
`photobench generate --jpeg 3 --dng 2` plus copies of two of the owner's raws
(`DSCF7407.RAF`, X-E3 + XF14; `P1180211.RW2`, GX7 II + 12-32), each run on a
fresh copy, every launch with `--library-root`.

- **S1** XF14 raw: `lens print` gives state `tables(fujifilm distortion false
  vignetting true)`, Distortion row `noTable`, Lens Vignetting `tableAvailable`;
  `lens vignetting on` gives `usingTable`, applies, undo "Turn On Lens
  Vignetting". `photocli render` with `lensVignetting.on=true`: corners about
  18% brighter, center unchanged.
- **S2** JPEG with one spot: Auto dimmed (`autoUnavailable notRaw`, no segment
  selected), checking starts in Manual ("Turn On Distortion", no question: Amount
  0 moves nothing). `lens distortion amount 40` asks (title and message as
  design §6; Change is the default button, Cancel takes Esc); Cancel leaves
  amount 0 and the undo top "Turn On Distortion"; again with Return: "Distortion
  Amount"; a second change on the visit asks no more; Constrain off: "Turn Off
  Constrain to Image", no question; Lens Vignetting never asks.
- **S3** Reset Lens after an answer: no question (once per visit); Reset All:
  no question; History lists the entries; grid, select all, Paste from a photo
  without Distortion: "Change distortion on photos with masks or spots?", "1 of
  the 107 photos has masks or spots…", Change: undo "Paste Adjustments".
- **S4** `photocli render` of the 12-32 RW2 with `lensDistortion.on=true`:
  `decoderCorrectsAuto` for both groups, nothing applied.
- **S6** (after the reviews) JPEG, never touched: `lens distortion constrain off`
  turns Distortion on in Manual ("Turn Off Constrain to Image"). With a spot and
  the question up for Distortion, a Lens Vignetting change does nothing; Cancel
  restores, Return saves "Distortion Amount".
- **S7** Grid, all 107 selected, Paste of Manual Distortion 30 onto a selection
  where one photo has a spot: "1 of the 107 photos has masks or spots…"; Cancel
  writes nothing; again with Return: "Paste Adjustments"; one `undo` leaves redo
  "Paste Adjustments". A scripted `pasteadjust` answered Cancel leaves its own
  command's group empty, which the script's undo stack shows as an empty step
  (a scripting artifact: ⌘V in the app has no group of its own).
- **S8** (C10, C11) Grid, all 107 selected, IMG_00001 with a spot; `lens
  pastethenfocus IMG_00017` pastes Manual Distortion 30 and at once selects one
  other photo: the question still says "1 of the 107 photos…"; after Change,
  "Paste Adjustments", the selection is the one photo, and IMG_00003 (selected
  when the paste started, not after) has Distortion Manual 30, as does IMG_00017.
- **S5** (AC14) XF14 raw, Lens Vignetting never on: `lens vignetting manual`
  turns it on in Manual, undo "Lens Vignetting Source"; one `undo` puts it back
  off with Source Auto; `lens vignetting auto` twice: the first turns it on (one
  step), the second records nothing. `buttons` shows Constrain to image's tooltip
  "Scale the corrected photo to fill its frame, with no empty edge."
- `print inspectorwidth` with the Lens heading open: visible 283, `fits` (the
  widest control is the Tone Curve's segmented control). The narrowest
  inspector can't be set by script (P2).

## Review findings (code-review.md C1 to C9, Q1 to Q3; review.md F1 to F5)

| # | What was done | Test or check |
|---|---|---|
| C1 | Fixed. The tab never compiles the kernels: `LensKernels` records when its compile ends (an atomic), and the editor asks `lensCorrectionKernelsKnownUnavailable`, false until a compile has finished (a failed one shows row 3 then). The editor starts the compile off the main actor when a photo opens, as before, and bumps `lensKernelsRevision` when it ends, so the groups redraw. Renders (off the main actor) still compile on first use | `kernelFailure` (the known flag); scripted `lens print` |
| C2 | Fixed (its task changed again by C10). A selection's read now runs as the batch task (`batchAutoTask`, `batchAutoRun`): the saved stacks, then only for photos with masks or spots whose Distortion uses Auto, their files, four at a time, through `CameraLensState.read(url)` (one `CIRAWFilter`, not `RawDefaults`), with progress in Activity under the command's title. Stop there or a newer paste or preset ends it (the run token keeps a second command from clearing the first's state); a paste or preset while the question is up does nothing | `standaloneRead`; scripted S7 |
| C3 | Fixed in the script, mostly fixed in the app. The debug script's loop now waits after every grouped command (key, menu, context menu, paste, preset) while a batch task reads or measures, unless the frame question is up; `alert press` and `alert key` wait in their own group after the answer. In the app, the loupe's photo alone (⌘V in the loupe, the common case) is decided at once from the editor, which holds its saved values and file state, so the paste registers its undo step before the command returns and ⌘Z right after ⌘V undoes it. **Not fixed for a selection in the grid**: there the stacks are read first, so ⌘Z pressed before that read returns (normally a few milliseconds behind pending saves, longer when files are read, with Activity showing it) undoes the step before the paste. The same is true today of a paste or preset that measures Color Alignment. Holding Undo during the read needs the window's own undo manager or the Edit menu, which the app does not own; noted as a limit | scripted S6, S7 |
| C4 / F1 | Fixed: `commit` reads and clears the skip flag before any return, and `resetAll` clears it in a `defer` | by reading (the path needs an operation this build does not know); scripted Reset All earlier (S3) |
| C5 | Fixed: stored amounts are clamped to −100 … +100 on read, as Color Alignment's values | `storedAmountClamped` |
| C6 | Fixed: an `OpcodeList3` of 4 bytes or fewer is read from the entry's own field | `emptyOpcodeList` |
| C7 | Fixed: a LibRaw decode's state is built in exactly when `Output.hasLensCorrections` says LibRaw applied the tables (`PreviewGenerator.libRawLensState`); the editor keeps the file rule for its first read, as suggested | `libRawBuiltIn` |
| C8 | Fixed: `readingLabel` and its catalog entry removed | `LocalizationTests` |
| C9 | Fixed: tests set `LensCorrectionDebug.$taskFault` (task-local), which parallel suites never see; the process-wide switch stays for the debug script | `kernelFailure`, `corruptSwitch` |
| F2 (DQ-4) | Fixed: Constrain to image on a group never switched on starts it in Manual where Auto can't apply, in the same step; the Amount (a typed value or a script) does the same. The debug script's prediction follows | scripted S6 |
| F3 | Fixed: `constrainTitle`'s comment and the catalog comment read "scale the corrected photo to fill its frame" | — |
| F4 | Fixed: the magnifier plate reads "After lens correction" while the plan has a warp or a gain; user guide updated | by reading (`fringeMagnifierTool`) |
| F5 | Fixed: the user guide lists Turn Off Distortion, Turn Off Constrain to Image, the four Lens Vignetting forms and Reset Lens | — |
| Q1 | Answered: no disagreement on the owner's files. On an E-M5 III ORF, a GX7 II RW2 and X-E3 RAFs (XF35, XF14), the flags are the same under `RAWDecodeSettings.none`, under the stack's settings (Kelvin, the whole-sensor request, machine learning asked) and under the older decoder version (7 or 6). None of these cameras is offered the machine learning decoder (versions 7 and 8 only), so version 9 could not be tried; renders read the flag from the filter that decodes, so a render never applies Auto over the decoder's correction | probe, 2026-11-19 |
| Q2 | Fixed rather than assumed: `lensFrame` places the camera's frame where it lies (`CropRect.x`/`y`, y from the top), so the center and radius are the camera frame's with or without a whole-sensor decode | `lensFrameOffCenter` |
| Q3 | Guarded: while the question is up, `change` does nothing (a menu key equivalent included) and a paste or preset does nothing, so the answer decides one change under its own name. Whether AppKit delivers a menu key equivalent with the sheet up stays a check with a real keyboard (P4) | scripted S6 (a Lens Vignetting change while asking is ignored) |

### Second passes (code-review.md C10 to C12, review.md F6 to F8)

| # | What was done | Test or check |
|---|---|---|
| C10 / F7 | Fixed. The read and the question run on a task of their own again (`lensQuestionTask`, with its own run token `lensQuestionRun`); they never cancel or claim `batchAutoTask`, so a paste or preset never ends a running Auto Exposure or measuring paste. While files are read the read has its own Activity row, with the same title, "N of M" and Stop as a measuring paste's (design DQ-5), and Stop cancels only it. A newer paste or preset replaces an older one's read. The debug script waits for this task as for the batch task | by construction (no path of the read touches `batchAutoTask`); scripted S8 |
| C11 | Fixed. The command's targets are taken when it starts and passed to the change: `batchSelection(action:targets:)`, `changeAdjustmentsMeasuringAlignment(…, targets:)` and `applyingAdjustmentPreset(_:targets:)`. The question and the change are about the same photos whatever is selected or open when the answer comes | scripted S8 (`lens pastethenfocus`) |
| C12 | Fixed. A `CancellationError` from reading the stacks ends the command with nothing written; only a real read failure goes on to the change (which reads and reports again), and only if no newer command took over | by reading; Stop writes nothing |
| F6 | Fixed. A preset's name is fitted to the toolbar (`ToolbarMetrics.statusLine`) and passed as the read row's toolbar title | by reading |
| F8 | Fixed. The `afterLensCorrection` comment (Swift and catalog) says Distortion or Lens Vignetting; `setConstrainToImage`'s doc comment is one paragraph; `setLensAmount`'s doc comment rewritten | — |

C11's check is a debug-script run, since the targets are captured in PhotoApp,
which no test target imports.

## Rulings (owner, 2026-11-19)

- **RQ-1:** ship Fujifilm RAF and DNG opcodes now. Panasonic, Olympus and Sony
  readers are follow-ups, with no code on this branch (follow-ups F2, F3).
- **RQ-2:** DNG `GainMap` is deferred (follow-up F4).
- **DQ-1:** the Constrain to image help reads "Scale the corrected photo so it
  fills its frame, with no empty edge." (the designer may tighten it). Changed
  in `LensCorrectionText.constrainHelp`, the String Catalog (the old key replaced)
  and the user guide.
- **DQ-2:** keep as built: choosing a Source segment while the group is off turns
  it on, one step ("Distortion Source"); with the group on, the selected segment
  records nothing. The user guide says so.
- **DQ-3:** keep caption row 8 ("No distortion table was found…") on raws whose
  tables this build does not read.

The PRD's rev2 (issue body, 2026-11-19) records these: R3 and AC3 name the
tables read (Fujifilm RAF, DNG `WarpRectilinear` and `FixVignetteRadial`), the
other makers' readers and `GainMap` are non-goals, AC13's by-eye check is Lens
Vignetting on the XF14 and XF23 files, and R15/AC14 is DQ-2's rule (tested by
`choosingSource`, with the rule moved into PhotoCore as
`Adjustments.choosingLensSource`). The designer tightened DQ-1's help to "Scale
the corrected photo to fill its frame, with no empty edge.", which is in the code,
the catalog and the user guide. Re-read against the code: nothing else in the PRD
or design.md disagrees with what is built. One note for AC13's "the DNG-opcode
sample": the real DNG on this Mac with a `WarpRectilinear` (Adobe's sample
`03_jxl_bayer_raw_integer.dng`) has a green plane that moves nothing (only red and
blue are scaled), so Auto rightly finds no distortion table there (`dngSample`,
opt-in, `DNG_OPCODE_SAMPLE=path`). Distortion read from a table is covered by the
synthetic opcode lists (`dngOpcodeParsing`, `dngFile`), the Fujifilm table render
(`fujifilmWarp`) and the CPU references.

The questions as they were asked are kept below.

## Requirements issues (ruled, see Rulings)

**RQ-1. Which maker tables Auto reads in this pass.** The PRD names Panasonic,
Olympus and Fujifilm first. On the owner's files:

- Every Panasonic RW2 and Olympus ORF that carries a table is already corrected
  by the system decoder (table present exactly when the decoder corrects), so
  Auto is inert on all of them (RI-1). A reader would only serve raws the system
  decoder can't read (a body newer than macOS), and could only be checked
  against the system decoder's own output on the same files.
- Olympus's tables are undocumented (ExifTool lists them as unknown tags
  `0x150a` and `0x150c`); reading them without another project's code means
  fitting their meaning to the system decoder's output.
- Fujifilm's tables are already read (`FujifilmRAF`), and 148 of the owner's
  X-E3 files (XF14, XF23) are system-decoded, not corrected by the decoder, and
  carry them. Auto applies there (in practice only Lens Vignetting: those two
  lenses' distortion tables are all zero). This pass builds it.
- Sony A7 III files with the FE 35mm F2.8 ZA carry distortion and vignetting
  tables the system decoder does not apply; Sony is not in the PRD's list.

So AC13's "within about 1 px of the camera's JPEG where the file has a table"
can be checked by eye only for Lens Vignetting on the XF14 and XF23 files.
Asked: is Fujifilm plus DNG opcodes the first slice, with Panasonic, Olympus and
Sony readers as follow-ups, or should Panasonic (and Olympus) be built now
although no owner file would use them? Recommendation: the first, with Sony as
the first follow-up (it is the only one that would change the owner's photos).

**RQ-2. DNG `GainMap`.** The PRD names gain-map opcodes. A `GainMap` sits in
`OpcodeList2`, before demosaicing, per color plane, and is usually a phone's
lens shading that every DNG reader applies as part of the raw. No file with one
is on this Mac, and applying it after the decode would only approximate it.
Built: `FixVignetteRadial` for vignetting. Proposed: `GainMap` as a follow-up if
a real file needs it.

## Design questions (ruled, see Rulings)

**DQ-1. Constrain to image's words for barrel correction.** The scale follows
§15.8 (the camera's framing: fill the frame exactly), which for barrel
correction makes the picture slightly *smaller*, not larger, and for barrel
correction no empty edge appears even with the box off (the corners' content is
pushed out instead). The help "Zoom in slightly so the corrected photo has no
empty edges." is then wrong for the commonest case. Options: (a) keep the
words (cost: none; inaccurate for barrel); (b) new help, for example "Scale the
corrected photo so it fills its frame, with no empty edge." (one string, now in the code: see Rulings);
(c) zoom in only (`max(scale, 1)`), so barrel
correction is not scaled (cost: no longer the camera's framing; the X-E3
comparison would be 1.5% of the radius off). Recommendation: (b). The user
guide already describes the behavior as built.

**DQ-2. The selected segment while the group is off.** Design §3.2 says choosing
a segment turns the group on, and choosing the selected segment records
nothing. With the group off, the stored source (Auto on a new raw) shows
selected. Options: (a) clicking it does nothing, and the person uses the check
box (the literal reading); (b) clicking the selected segment of an off group
turns it on, one step "Distortion Source" (built: the control does what it looks
like it offers; with the group on, the selected segment records nothing).
Recommendation: (b), as built; a one-line change to (a) if the designer rules so.

**DQ-3. The caption on a raw whose table this build does not read.** Sony A7 III
files with the FE 35mm F2.8 ZA carry tables, but no reader exists (RQ-1), so
row 8 says "No distortion table was found in this file." Options: (a) keep until
the reader exists; (b) detect the presence of known-but-unread tables and say
"This camera's table can't be read yet. Choose Manual…" (a new string and a
presence check per maker). Recommendation: (a), revisit with RQ-1's follow-ups.

## For a person (manual checks proposed for qa.md)

- **P1** The owner's XF14 or XF23 raw beside the camera's JPEG with Lens
  Vignetting on Auto (corners within about 1 px of the JPEG's light, by eye).
- **P2** The Lens heading at the narrowest and widest inspector, light, dark,
  Increase Contrast: the two Source controls, the dimmed Auto segment and its
  tooltip, captions 1a, 1b, 2a (no LibRaw RAF on this Mac), 6 to 10.
- **P3** A RAW+JPEG pair: the JPEG's Auto dimmed, editing one leaves the other.
- **P4** The alert with a real keyboard (Return, Esc, ⌘.) and a real slider drag
  released with a mask present, then Cancel.
- **P5** At 100% and fit, a live drag of Amount and an export of the same setting
  agree (AC10), on a wide raw.

## Proposed follow-ups (new issues, not this branch)

- **F1 (bug).** "Color Alignment's lensAlign kernel can read a stale input area."
  Its area callback depends on the alignment values, which are not in Core
  Image's graph digest: a context can reuse the area an earlier render of the
  same image with other values needed and repeat its edge pixels (the fault this
  branch works around for the warp, see Engineering decisions). A live drag of
  Red/cyan or Blue/yellow on a JPEG is where it would show.
- **F2 (enhancement).** "Auto lens corrections from Sony ARW tables"
  (`DistortionCorrParams`, `VignettingCorrParams`): the owner's A7 III files with
  the FE 35mm F2.8 ZA carry them and the system decoder does not apply them; the
  only reader that would change the owner's photos today (RQ-1).
- **F3 (enhancement).** "Panasonic and Olympus lens tables for raws the system
  decoder can't read": inert on every owner file today; Olympus's tables are
  undocumented (RQ-1).
- **F4 (enhancement).** "DNG GainMap for Lens Vignetting", if a real file needs
  it (RQ-2).
- **F5 to F8 (enhancement), from design §18:** Auto Lens Correction on a grid
  selection (Adjust menu); a Strength slider for Auto; the kernel-failure status
  on Color Fringes and Color Alignment (they skip silently, RI-CR1); Lightroom
  lens settings imported as Auto.

## README

No change to requirements, build commands or the repository layout. At Ship: one
line in the feature list (Distortion and Lens Vignetting in the Lens heading).

## Open items and limits

- Auto reads Fujifilm and DNG tables only (ruled: RQ-1, RQ-2; follow-ups F2 to F4).
- ⌘Z pressed while a paste or preset on a grid selection is still reading its
  targets undoes the step before it (code review C3, the part not fixed; the
  loupe's paste is decided at once).
- The frame question does not wait behind another sheet (`LibraryModal`); none
  can be up when it is asked from the tab or the menus.
- "Reading the camera's table" (design §4 row 4) is not built: the state is
  known before the tab's controls appear (Q3).
- The whole-sensor copy of an aspect-cropped ORF or RW2 was not tried (Q1).
