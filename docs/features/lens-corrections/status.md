Issue: #87

# Lens corrections (distortion and lens vignetting): status

Owner: swift-macos-engineer. Branch `feature/lens-corrections` (off develop
c97d579). Spec: the PRD (issue #87, revised 2026-11-19) and
[design.md](design.md) (amended 2026-11-19).

**State: In progress (built; waiting on rulings).** Everything the PRD and the
design ask for is built and tested, with Auto reading Fujifilm tables and DNG
opcodes. The open technical questions are answered below from the code and the
owner's files (read through a copy of the catalog; nothing in the library was
opened or changed). Two Requirements issues (RQ-1 which maker tables, RQ-2 DNG
GainMap) and three Design questions (DQ-1 to DQ-3) are open; none blocks review
of what is built, but RQ-1 decides whether more readers belong on this branch,
so the state stays In progress until it is ruled.

## Build and test

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline (develop c97d579 plus the design commits, before any change) | Pass (two existing warnings in `SmartAlbumTests.swift`, `VirtualCopiesTests.swift`) | 1204 tests in 175 suites pass |
| Latest (fdd86c7) | Pass, no new warnings | 1232 tests in 176 suites pass (67.5 s); `Scripts/build-app.sh` passes |

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
  `TestScene.lensGrid`, `LensCorrectionTests` (28 tests, 40 cases with arguments),
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
  pincushion slightly larger. For an off-center or tangential DNG warp, the
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
| AC3 | `rafState`, `dngFile` (tables found), `captions` (no table row 8, row 6), `manualAmountKeptInAuto`; non-raw starts in Manual: `segments` and the scripted check S2 | Pass |
| AC4 | `autoPlan`, `untouched` (Auto on decoder-corrected and built-in raws renders as off; Manual matches the reference on top); real files: `photocli render` of the owner's 12-32 RW2 with Auto: `decoderCorrectsAuto`, not applied (S4) | Pass |
| AC5 | `pickerSeesCorrectedImage` (fringe input and alignment measurement read the corrected image), `vignettingBeforeExposure` (the reference's order; the other order differs) | Pass |
| AC6 | `movesFrame`; scripted S2, S3 (question at commit, Cancel restores and records nothing, Change one step, once per visit, Reset Lens and Reset All and History never, a paste asks once with counts) | Pass (scripted) |
| AC7 | `constrainFills` (no empty pixel with Constrain, empty corner without for pincushion), `cropAfterCorrection` | Pass |
| AC8 | `groupsAndPresets`, `autoPlan` (each file's own tables; no table: nothing, amount kept); render-time lookup, so no photo is refused (Q2) | Pass |
| AC9 | Non-raw state (`otherStates`, `segments`); the JPEG of a pair is a non-raw file with its own stack (edits are per file) | Pass; a pair by eye is P3 |
| AC10 | One renderer: every decode sets `RenderContext.lens`; previews, live frames, the 100% region, export and `photocli` all render through `AdjustmentRenderer` | By construction; no new test of the 100% region against fit (proposed P5) |
| AC11 | `kernelFailure`, `corruptSwitch`, `rafState` (damaged), `dngFile` (damaged), captions rows 3 and 5; `lens force` in the debug script | Pass |
| AC12 | `resetAndRoundTrip` (identity hash); unknown newer stacks are refused by the existing reader (unchanged) | Pass |
| AC13 | Five goldens (fdd86c7), CPU references in `Reference/LensCorrectionReference.swift`; by eye on real files is the owner's (P1) | Goldens pass |

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
- `print inspectorwidth` with the Lens heading open: visible 283, `fits` (the
  widest control is the Tone Curve's segmented control). The narrowest
  inspector can't be set by script (P2).

## Requirements issues

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

## Design questions

**DQ-1. Constrain to image's words for barrel correction.** The scale follows
§15.8 (the camera's framing: fill the frame exactly), which for barrel
correction makes the picture slightly *smaller*, not larger, and for barrel
correction no empty edge appears even with the box off (the corners' content is
pushed out instead). The help "Zoom in slightly so the corrected photo has no
empty edges." is then wrong for the commonest case. Options: (a) keep the
words (cost: none; inaccurate for barrel); (b) new help, for example "Scale the
corrected photo so it fills its frame, with no empty edge." (one string; built
as the design's for now); (c) zoom in only (`max(scale, 1)`), so barrel
correction is not scaled (cost: no longer the camera's framing; the X-E3
comparison would be 1.5% of the radius off). Recommendation: (b). The user
guide already describes the behavior as built.

**DQ-2. The selected segment while the group is off.** Design §3.2 says choosing
a segment turns the group on, and choosing the selected segment records
nothing. With the group off, the stored source (Auto on a new raw) shows
selected; built literally, clicking it does nothing, and the person uses the
check box. Options: (a) as built; (b) clicking the selected segment of an off
group turns it on ("Distortion Source"). Recommendation: (b), small, and it
makes the control do what it looks like it offers. Waiting for the ruling.

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

## README

No change to requirements, build commands or the repository layout. At Ship: one
line in the feature list (Distortion and Lens Vignetting in the Lens heading).

## Open items and limits

- Auto reads Fujifilm and DNG tables only (RQ-1, RQ-2).
- The frame question does not wait behind another sheet (`LibraryModal`); none
  can be up when it is asked from the tab or the menus.
- "Reading the camera's table" (design §4 row 4) is not built: the state is
  known before the tab's controls appear (Q3).
- The whole-sensor copy of an aspect-cropped ORF or RW2 was not tried (Q1).
