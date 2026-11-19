Issue: #87

# Lens corrections (distortion and lens vignetting): status

Owner: swift-macos-engineer. Branch `feature/lens-corrections` (off develop
c97d579). Spec: the PRD (issue #87, revised 2026-11-19) and
[design.md](design.md) (amended 2026-11-19).

**State: In progress.** The design's and the PRD's open technical questions are
answered below from the code and from the owner's files (read through a copy of
the catalog; nothing in the library was opened or changed). One answer changes
scope (RQ-1, maker tables) and goes to the product manager; the rest of the
feature is unblocked and being built.

## Build and test

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline (develop c97d579 plus the design commits, before any change) | Pass | 1204 tests in 175 suites pass |

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
  lenses' distortion tables are all zero).
- Sony A7 III files with the FE 35mm F2.8 ZA carry distortion and vignetting
  tables the system decoder does not apply; Sony is not in the PRD's list.

This pass builds Auto from Fujifilm tables and DNG opcodes (`WarpRectilinear`,
`FixVignetteRadial`; published specification), and treats other raws as having
no table. Asked: is that the first slice, with Panasonic, Olympus and Sony
readers as follow-ups, or should Panasonic (and Olympus) be built now although
no owner file would use them?

**RQ-2. DNG `GainMap`.** The PRD names gain-map opcodes. A `GainMap` sits in
`OpcodeList2`, before demosaicing, per color plane, and is usually a phone's
lens shading that every DNG reader applies as part of the raw. There is no file
with one on this Mac, and applying it after the decode would only approximate
it. Proposed: not in this pass (Auto reads `FixVignetteRadial` for vignetting),
a follow-up if a real file needs it.

## Design questions

(Collected as the build goes; see the report.)
