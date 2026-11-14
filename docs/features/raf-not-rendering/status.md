# RAF not rendering: implementation status

Issue: #161. Bug fix, branch `bug/raf-not-rendering`, cut from `develop` at `ef592d9`.

**Status: Done** (2026-11-13). A raw the system's RAW decoder gives no image
for is decoded by the vendored LibRaw and renders everywhere; it is adjusted
like any rendered image. The code review's findings C1 to C15 and question Q6,
and the design review's fixes F1 to F5 and ruling D5, are answered below. Added
on the owner's ruling of 2026-11-13: a Fujifilm RAF that LibRaw decodes gets
the camera's own frame and the lens corrections the camera stored in the file
(**Lens corrections and the frame**, below). Next: code review of that
addition, then qa-tester again (with the reviewer's Q7), then the owner's
sign-off. The fourth code review's findings C16 to C22 and Q11 are answered
under **Code review, fourth pass**.

## Bug

**Steps to reproduce** (macOS 27.2.1). `swift run photocli render
/Volumes/photos/2019/2019-01/2019-01-12/DSCF5159.RAF --out o.png`, or open any
RAF of that folder (Fujifilm X-E3) in the loupe.

**Expected:** it renders. **Actual:** `undecodable`; a black loupe, grey film
strip tiles.

**Root cause.** Not the network volume or #160: all 16 X-E3 RAFs tried fail on
a local copy too. On this macOS `CIRAWFilter` is made for the file but has
`nativeSize` 0x0, decoder versions `["None"]` and no output image, and ImageIO
cannot decode it either, so `PreviewGenerator.decode` had nothing left and threw.
It is the X-E3's lossless compressed files the system decoder gives nothing
for (all of the owner's folder by their headers: sensor 6048x4038), not every
X-E3 file: the code reviewer found that it reads an uncompressed one (sensor
6160x4032), and an X-T3's lossless compressed file (`DSCF4583.RAF`).

**The fix.** `PreviewGenerator.decode` falls back to LibRaw
(`Preview/LibRawDecoder.swift`) when, and only when, the system decoder gives
no image.

**The test that fails without the fix:**
`LibRawFallbackPipelineTests.rawWithoutSystemImageRenders` ("A raw the system
decoder gives no image for is decoded by LibRaw and renders",
`Tests/PhotoCoreTests/LibRawDecoderTests.swift`). It runs in every `swift test`
on a synthetic 256 x 192 DNG, for which the system decoder gives no image on
this Mac exactly as for the X-E3 file. Checked: with the fallback's line
switched off it fails with `undecodable` (and five more of the suite with it).
Where a macOS does read that DNG the test still passes, through the system
decoder, and prints that its premise does not hold there; `LibRawDecoderTests`
calls LibRaw directly and runs its code on every macOS. On a real file:
`RAF_SAMPLE=path/to/X-E3.RAF swift test --filter LibRawFallbackTests` (7 tests).

## Owner's rulings

2026-11-13, before the review: no embedded preview in place of a render (a
grid placeholder is its own feature, #168). LibRaw, vendored, only where the
system decoder gives no image, so nothing gets slower.

2026-11-13, on the code review's questions:

- **Q1, license.** LibRaw is taken under the LGPL 2.1, not the CDDL.
- **Q2, `CLAUDE.md`.** The Dependencies edit stands, with LGPL 2.1 in place of
  CDDL; the other "GRDB only" statements follow. Applied by the main session
  in `4ff5d30` (`CLAUDE.md` line 158 and Dependencies,
  `.claude/agents/code-reviewer.md`); see **Not done** for Layout and Commands.
- **Q3, adjusting.** A photo LibRaw decoded must still be adjustable. Controls
  are not hidden unless an adjustment is impossible; what is impossible is
  reported as a Design question.
- **Q4, the cache.** LibRaw previews stay on disk under the same keys as any
  preview; two looks after a macOS change are accepted. No cache change was
  made.
- **Q5, the frame.** Stayed LibRaw's first inset crop at first; decided for
  Fujifilm files with the lens corrections (the camera's own frame).
- **Lens corrections (new scope, 2026-11-13).** LibRaw photos came out without
  the camera's lens corrections (straight lines bowed). To be fixed on this
  branch: read Fujifilm's tables from the RAF and apply them on the LibRaw
  path only, automatically, with no control for now.

## What a LibRaw photo is

One test, `SystemRAWDecoder.reads(url)` (`Preview/SystemRAWDecoder.swift`):
the system decoder gives an image of the file with its default settings. It is
the test `PreviewGenerator.decode` makes of a decode, and what `RawDefaults`,
Auto White Balance, the live session, the 100% renderer, the sharpening map,
the fringe picker, Color Alignment's measurement and the editor ask instead of
the file's extension. A raw that fails it is a rendered image everywhere, as a
JPEG is (`RenderContext.isRaw` false):

| | Raw the system decodes (X-T3) | Raw LibRaw decodes (X-E3) |
|---|---|---|
| White Balance modes | As Shot, Auto, Daylight … Flash, Custom | As Shot, Auto, Custom |
| Temperature, Tint | Kelvin and tint, in the decoder | relative (−100 … 100), in the renderer |
| Auto White Balance | Kelvin (5886 K, tint 7) | relative (16, −22) |
| Tone, Presence, Tone Curve, Color Mixer, Color Grading, masks, Lens, Effects, Sharpening, crop | renderer | renderer, the same |
| Highlights or Exposure below 0 | decoder keeps values above white | what the decode holds (as a JPEG) |
| Luminance noise reduction | decoder | renderer's denoiser |
| Color noise reduction | decoder | not offered |
| Profile, Decoder | offered | a note in the group's place |
| Use machine learning | offered | dimmed: "Not available for this camera." (on every macOS, F3) |
| Lens corrections (distortion, lateral color, corner shading) | by the decoder | from the camera's tables in a Fujifilm RAF; none for other files |
| Frame | the decoder's (6240x4160, X-T3) | the camera's, from a Fujifilm RAF (6000x4000, X-E3); else LibRaw's inset crop |
| Mode shown after a paste of Daylight or a Kelvin Custom | the pasted mode | As Shot: what renders (F2, D5) |
| Mode shown after choosing Custom with both sliders at 0 | Custom | Custom (D5) |

`photocli render --long-edge 600` with one `--set` at a time, SHA-256 of the
PNG against the unedited render (debug build):

| Setting | X-E3 (LibRaw) | X-T3 (system) |
|---|---|---|
| `whiteBalance.relativeTemperature=60`, `relativeTint=30` | changes | same (a raw's is Kelvin) |
| `whiteBalance.temperature=2500`, `tint=60` | same | changes |
| `whiteBalance.preset=daylight` (5500 K) | same | changes |
| `exposure.ev=1`, `exposure.ev=-1` | changes | changes |
| `tone.highlights=-80`, `tone.shadows=60`, `tone.contrast=50` | changes | changes |
| `noiseReduction.luminance=80` | changes | changes |
| `noiseReduction.color=90` | same | changes |
| `rawDecode.look=flat` | same | changes |
| `sharpen.amount=120` | changes | same (under a fifth of full size: no sharpening shows) |
| `presence.saturation=40` | changes | changes |

So the two kinds of raw mirror each other in white balance: Kelvin values do
nothing to a LibRaw photo, relative values do nothing to a system raw. That is
how a JPEG has always behaved, and the Adjust tab offers each photo only the
kind that works. Kelvin values reach a LibRaw photo only by paste, a preset or
`photocli`, and then change nothing; they stay in the stack, and the Mode
pop-up shows the mode that renders (design review D2, F2).

## Code review findings

| # | Outcome |
|---|---|
| C1 | Fixed in `7957ed1` (no `LIBRAW_NOTHREADS`). Now tested: `concurrentDecodesMatchSoloDecodes` (12 decodes of 6 files at once, four rounds, against each alone) and `buildIsThreadSafe` (the define is not in `Package.swift`). With the define put back, the first fails here (8 of 48 decodes differed) and so do the orientation and inset crop tests running beside it. |
| C2 | Fixed: the one test above. The editor's `isRaw` is "the system decoder reads this file"; the Adjust tab, Auto White Balance and the renderer agree. `photocli` table above. |
| C3 | Fixed. Decode settings reach only a raw the system decodes (`SystemRAWDecoder.Memo`, told by the editor from `RawDefaults`, else read from the file once), so they no longer key a LibRaw decode in `LiveRenderSession`, `LiveRegionRenderer`, `SharpeningMapRefiner`, the fringe picker or Color Alignment. `LiveRenderSession` also keeps LibRaw's decodes by what they differ by, half the frame or all of it, so a draft request, a final one and a small crop share one. On the X-E3 file: one decode through an interactive frame, a final frame, Kelvin and noise reduction changes and a 0.9 crop; a second, full one for a 0.3 crop. Test: `decodeSettingsDoNotDecodeAgain`. |
| C4 | Fixed. `LibRawDecoder.frameSize` reads the frame from the header (`libraw_open_file` only, about 1 ms) and `PreviewGenerator.nativeSize` answers with it. The reviewer's command now gives 1799x1199 for the X-E3 (was 900x600; X-T3 1872x1248). Tests: `cropDecodesLargeEnough`, and `aCropDecodesLargeEnough` on a real file. |
| C5 | Ruled (Q4): no change. |
| C6 | Fixed. `LibRawDecoderTests` (8 tests) and `LibRawFallbackPipelineTests` (9) run by default on synthetic DNGs: linear and neutral levels derived from the mosaic's values, orientations 2 to 8 pixel for pixel, the half-size rule, the frame math and a real inset crop (`SyntheticDNG` can write a default crop), failing files, concurrent decodes, the fallback, the shared test, crop size, decode keys, the machine learning reason, Auto White Balance. The Bug section names the failing test. |
| C7 | Fixed: the reason is the availability's (`cameraNotSupported` on macOS 27, `notOnThisMac` before), not `failed`. Such a preview is still kept for the session only, as every not-applied render is. |
| C8 | Fixed: LibRaw's reason is logged (category `decode`) when it cannot decode a file the system decoder gave no image for. |
| C9 | Fixed: `src/Makefile` excluded (the build has no warning now), zlib no longer linked. |
| C10 | Fixed in `THIRD_PARTY_NOTICES.md`, `LibRawDecoder`'s comments, this file and the user guide. `README.md`, `CLAUDE.md` and `.claude/agents/code-reviewer.md`: see **Not done**. |
| C11 | Fixed: the real-file test compares long edges. |
| C12 | Fixed: `rawcompare` prints the first run and the best of N, is in the usage text and in `docs/PROFILING.md`, which says what the figures do not show. |

## Code review, second pass (`code-review.md` Follow-up, 2026-11-13)

C1 to C12 closed by the reviewer. New:

| # | Outcome |
|---|---|
| C13 | Fixed. `LibRawDecoder.Frame.isTurned` is `flip & 4 != 0`: the mirrored quarter turns (LibRaw's flips 4 and 7, orientations 5 and 7) swap width and height as 5 and 6 do, so `frameSize` and `PreviewGenerator.nativeSize` give the size as shown. Tests: `decodeIsOriented` now covers orientations 2 to 8 pixel for pixel, with `frameSize` against the decode; `frameFromSizes` covers every flip. |
| C14 | Fixed by the designer's ruling D5 (the reviewer's Q8), exactly: see the design review below. |
| C15 | Fixed here: `CLAUDE.md` (line 158, Dependencies) and `.claude/agents/code-reviewer.md` were updated in `4ff5d30` by the main session, and this file no longer says otherwise. Layout and Commands: see **Not done**. |
| Q6 | Answered in code. (a) `SystemRAWDecoder.reads`, `RawDefaults` and Auto White Balance test the filter set up as an untouched photo decodes (`givesImageUntouched`: `RAWDecodeSettings.none`, which pins the decoder version as every decode does), and `PreviewGenerator.decode` decides by the same test: when the stack's own choices (the whole-sensor copy, a decoder version) leave the system decoder without an image, it decodes without them, and logs it, before it would turn to LibRaw. A raw `reads` says the system decodes never gets LibRaw's image. No file takes that retry here, so it has no test of its own; `oneTestOfWhatIsDecodedAsRaw` checks that such choices never move a file to the other decoder. (b) `PreviewGenerator.Decoded.decoder` says which decoder made an image, and `LiveRenderSession` keeps a decode by LibRaw's two sizes only when LibRaw made it: it expects LibRaw of a raw the system does not read whose header LibRaw reads, and takes what the decode returned over that (`learn`). Test: a session told the system does not decode a 1024 x 768 DNG that it does decode: the draft's 250 pixel base no longer serves the 400 pixel frame (with `learn` switched off the test fails with exactly the reviewer's 250). |
| Q7 | For qa-tester (several LibRaw photos at 100%: memory, time to sharp). Not measured here. |

## Lens corrections and the frame (new scope, 2026-11-13)

**The problem.** The system decoder applies a camera's lens corrections;
LibRaw does not. An X-E3 photo with the XF 35mm f/2 showed its barrel
distortion (7.6% at the corner), color fringing and corner shading (52% of the
light at the corner).

**Where the tables are.** A RAF's big-endian header gives three sections at
offset 84: the embedded JPEG, the "CFA header" (records: `RawImageFullSize`
0x100, `RawImageCropTopLeft` 0x110, `RawImageCroppedSize` 0x111) and the raw
data. In X-Trans files the raw data section starts with a little-endian TIFF
header whose one entry, 0xF000, points at Fujifilm's IFD; there
`GeometricDistortionParams` (0xF00B), `ChromaticAberrationParams` (0xF00F) and
`VignettingParams` (0xF010) are signed rationals: a leading value (the frame's
half diagonal in pixels over the number of knots: 3605 / 11), then the knots
(radii, 1 at the corner) and the values. Two layouts: 23, 31 and 23 values
(11 knots, the X-E3) and 19, 29 and 19 (9 knots, later cameras).
`Preview/FujifilmRAF.swift` reads the header, the records and at most 64 KiB
of the raw section; it never uses ExifTool. Files without the tables, with
tables that correct nothing (a lens without contacts writes zeros) or with
values no lens has are left uncorrected.

**The math** follows darktable's embedded-metadata lens correction
(`src/iop/lens.cc`, GPL 3 or later, recorded in `THIRD_PARTY_NOTICES.md`),
written again in Swift and Metal (`Preview/EmbeddedLensCorrection.swift`):
tables linear between knots that are radii of the recorded image; a recorded
radius r belongs at r / (1 + distortion / 100); red and blue come from their
own radii; each sample is divided by vignetting / 100; and the picture is
scaled by the largest multiplier between the frame's short side and its corner
(0.985 for this lens), so nothing is taken from outside the recorded frame.
The recorded radius for each output radius is solved for exactly and kept in a
1024-entry lookup table (the kernel reads between entries).

**Where it runs.** In `LibRawDecoder.decode` only, on LibRaw's linear image,
before anything else sees it (so before the crop, the masks' frame and the
Lens heading, as the system decoder's corrections are). One stitchable kernel,
`embeddedLens`, in a Metal library of its own (`Kernels/LensKernels.swift`);
samples at pixel centers, interpolated by hand. If the kernel cannot compile,
the photo is cut to its frame uncorrected and a line is logged (the same
limitation as the Lens heading's, RI-CR1).

**The frame (Q5).** For a Fujifilm RAF the frame is the camera's own
(`RawImageCropTopLeft`, `RawImageCroppedSize`): 6000x4000 for the X-E3, the
size of its JPEG and of the system decoder's image where it reads such files,
and the frame the tables are centered on. LibRaw's crop must start on the
sensor's color pattern (that is why its inset was 5998x3997), so LibRaw now
decodes its whole visible area (6032x4028) and the frame is cut from it in the
same resampling. A half-size decode's frame starts between two pixels and is
resampled too, so every size shows the same frame. Files that are not RAFs
keep LibRaw's inset crop (a DNG's default crop) or its visible area. A RAF
shot at 16:9 or 1:1: no sample here; the frame is whatever those two tags say.

**Checked against the camera's JPEG.** The JPEG the camera embeds in the RAF
(1920x1280) has the camera's own corrections. `LibRawFallbackTests`
(`theCorrectedRenderLinesUpWithTheCamerasJPEG`) looks up 48-pixel blocks of it
in the half-size render (zero-mean normalized cross-correlation, sub-pixel by a
parabola) and reports how far each has moved, in JPEG pixels (one is 3.1
pixels of the full-size photo), and how bright the render is beside the JPEG
far from the center against near it:

| File | Blocks | Corrected: median, 90th percentile | Beyond 0.75 of the radius | Uncorrected: median (largest) | Light far / near |
|---|---|---|---|---|---|
| DSCF5123, XF 35mm f/2 | 474 | 0.35, 0.85 | 0.79 | 5.7 (80) | too dark to tell |
| DSCF5124, XF 35mm f/2 | 536 | 0.36, 1.07 | 0.89 | 3.8 (90) | too dark to tell |
| DSCF5139, XF 35mm f/2, camera upright | 866 | 0.43, 1.43 | 0.95 | 5.1 (20 within the search) | 1.001 (lens: 0.66) |
| DSCF5170, XF 14mm f/2.8 (no distortion in its table) | 858 | 0.27, 0.73 | 0.43 | (nothing to move) | 1.003 (lens: 0.56) |
| DSCF5162, lens without contacts (tables correct nothing) | 502 | 0.30, 1.59 | 0.34 | (nothing to move) | 0.97 (lens: 1.0) |

(The uncorrected figures of DSCF5124 and DSCF5139 are from a run before an
uncorrected half-size decode's frame was resampled; DSCF5123's moved from 4.1
to 5.7 with that.)

So the window frame and other details are where the camera's JPEG has them to
about a third of a JPEG pixel (one pixel of the 24-megapixel photo) in the
middle of the distribution, and the corner shading is undone (1.00 where the
lens passes 56% to 66% of the light). What does not match: with the 35mm the
outer quarter of the radius is off by 0.8 to 0.95 JPEG pixels (about 3 pixels
at full size) in the median, against 0.4 where there is nothing to correct;
by radius the residual is +0.2 to +0.3 JPEG pixels around the middle and −1
(16 blocks) to −3.5 (3 blocks) in the outermost tenth: the camera takes the
far corners from slightly further in than the table's linear reading gives.
The scale rule also leaves a residual of 0.03% of the radius. Neither was
tuned away: the formulas are darktable's as documented.

**System-decoded raws are untouched.** The X-T3's `photocli render
--long-edge 600` PNGs (unedited, a Kelvin white balance, +1 EV) have the same
SHA-256 as before the change; every golden and reference passes; the code is
only reached from `LibRawDecoder`.

**Pipeline version: no bump** (8 stays). On `develop` these files do not
render at all, so no cached preview of a shipped build changes. One caveat for
whoever ran an earlier build of this branch on a library with such photos (the
owner did): their cached thumbnails and previews were made without the
corrections and at 5998x3997, under keys that have not changed, and stay until
the photo is edited or the preview cache folder is deleted. Crops and masks
made on such photos with an earlier build of this branch sit a few pixels off
(the frame moved by 2 and 3 pixels and the geometry changed).

**Tests** (all in the default run unless noted): `FujifilmRAFTests` (8: both
layouts, an X-T3's real nine-knot values, the crop mode and tables for another frame, files without usable tables, frames, every truncation and 4,000
random damages of a synthetic RAF, which found a crash on a short read while
it was written; reading from disk), `EmbeddedLensTests` (16: the tables'
functions and their inverse, the scale rule, the lookup tables' reading error
against the slope jumps at knots, the kernel against its CPU reference
`Reference/EmbeddedLensReference.swift` in a float context with a bound from
single precision, the app's half-float context with its derived bound, a
picture recorded through the lens restored to within bilinear reading error
and off by more than 0.1 without the correction, tables that correct nothing,
the frame in LibRaw's image for all eight orientations). On a real file
(`RAF_SAMPLE`): `theFrameIsTheCameras` and
`theCorrectedRenderLinesUpWithTheCamerasJPEG` (median at most 0.5 JPEG pixels,
90th percentile at most 1.5, uncorrected at least four times worse, light far
from the center within half of what the lens's falloff would show).

## Code review, fourth pass (`code-review.md`, 2026-11-13)

| # | Outcome |
|---|---|
| C16 | Fixed. The order of decoders is a function of its own, `PreviewGenerator.rawImage` (the system decoder with the stack's settings, then without the stack's decoder choices, then LibRaw), which `decode` calls and `decoderOrder` tests with stand-ins for the decoders. |
| C17 | Fixed. `LibRawDecoder.maximumSensorPixels` is 150,000,000 (raw width times raw height): above every camera's single frame, and about 3.3 GB for a full decode at 22 bytes a pixel. A larger file is refused after `libraw_open_file` (`Failure.tooLarge`, logged, then `undecodable`) and has no `frameSize`. **The number is the owner's to change.** Test: `sensorSizeLimit`. |
| C18 | Fixed. A Super CCD's file (LibRaw's `fuji_width` set) gets no crop of either kind: its frame is LibRaw's own picture, whose size comes from `libraw_adjust_sizes_info_only` on a separate instance. A RAF's camera frame is used only when the file's records give the sensor size LibRaw reads (`LibRawDecoder.cameraFrame`). The public FinePix F700 sample now renders whole, 2035x1533 (was a 3511x755 strip). Tests on synthetic bytes: `cameraFrameAndSensorLayout`. |
| C19 | Fixed. The corrected value ends at the decode's white (1): `min(sample × gain, 1)` in the kernel and in the reference. LibRaw's image ends at white, so a clipped area is white wherever it lies, and the camera and the system decoder clip after the gain as well; values the gain lifts past white are clipped, as in the camera's picture. Tests: `gainEndsAtWhite` (a white image stays exactly 1 everywhere; a flat 0.7 is lifted by the gain up to 1; a picture with clipped parts against the reference). |
| C20 | Fixed. Tables whose knots start away from the center (the nine-knot layout: 0.35) get a knot at 0 with no distortion, no shift and all the light, as darktable's `_init_coeffs_md_v2` adds it. Test: `readsARealNineKnotLayout`, with an X-T3's own values (`DSCF4583.RAF`) in synthetic bytes. |
| C21 | Fixed. What `decode` does with LibRaw's image is `LibRawDecoder.framed` (the cut, the tables, the half-pixel resample, `fullSize`) and `LibRawDecoder.lensTables` (which tables); `decodeFramesAndCorrects` and `whichTablesADecodeUses` run them by default on synthetic images and synthetic RAF bytes. |
| C22 | Fixed: 7 tests with a sample; the scale rule's comment names the X-A5 exception; "the first one 0" is true since C20; the Bug section and the user guide say lossless compressed X-E3 files; a file whose tables are not used (its frame refused, a crop mode, tables for another frame) says so in the log. |
| Q11 | `FujifilmRAF.cropMode` reads `CropMode` (0x104D) from the maker note of the embedded JPEG's Exif, and `LensTables.frameRadius` is the tags' leading value times the knots. Tables are used only when the mode is not 2 or 4 **and** that radius is the camera frame's half diagonal within 2 pixels (`FujifilmRAF.lensTables(for:)`); otherwise the file is shown uncorrected, in its frame, with a log line. **No file in a 1.25x crop mode was at hand**, so what darktable does for them (knots times 1.25) is not applied and not checked. Tests: `tablesForAnotherFrame`. The Exif parser is covered by the same truncation and damage tests as the rest. |
| Q12, Q13, Q14 | The owner's. Q12 (the scale rule against an X-A5's JPEG) is noted in the correction's comment; Q14 (bilinear resampling, and the half-size frame read between two rows) is a choice made here. |

## Design review (`review.md`, 2026-11-13)

Rulings on the engineer's Design questions: **D1** keep the note under the
Profile heading, no dimmed pop-ups. **D2** no Kelvin scale and no Daylight to
Flash for these photos. **D3** their machine learning caption, check box help
and badge tooltip name Luminance only. **D4** no decoder badge in the grid or
the loupe.

| # | Outcome |
|---|---|
| F1 | Fixed. For a photo the system decoder doesn't read (`AdjustmentEditor.usesFallbackDecoder`), the caption and check box help are "Not applied: this camera isn't supported. Luminance applies instead." and the badge tooltip ends "It's shown with Luminance instead." (`MachineLearningText.caption`, `checkBoxHelp` and `badgeHelp` take `fallbackDecoder`; no new `Reason`, so export rows keep one reason per camera). Both keys are in the catalog with the review's comments. `print ml` prints them. |
| F2, D5 | Fixed, then changed by the second pass's ruling **D5** (code review C14: with F2 as first written, choosing Custom at 0/0 on any JPEG snapped back to As Shot). `WhiteBalance.relativeDisplayPreset` (PhotoCore) is D5's rule: the stored mode when it is As Shot, Auto or Custom and the balance holds no Kelvin values; otherwise As Shot when both relative values are 0, else Custom. The Mode pop-up of every file that is not decoded as a raw (JPEGs too) selects it; the stack is not rewritten, and choosing Custom at 0/0 still saves one undo step, as ruled. Test: `LibRawFallbackPipelineTests.relativeModeShown` (D5's four cases and both rules). Scripted on the X-E3: `adjust wb custom` shows `wb mode 'Custom'` with `"preset":"custom"` stored and one undo step, undo shows `'As Shot'`; Daylight pasted from the X-T3 shows `'As Shot'` with `"preset":"daylight","temperature":5500` kept; after Temperature +25, `'Custom'`. `print ml` prints the pop-up's selected mode. |
| F3 | Fixed. The reason for these photos is the camera on every macOS: `MachineLearningNoiseReduction.reasonWithoutSystemDecoder` (`cameraNotSupported`) is what a decode reports (so the badge, `photocli` and the export's Activity row), and the editor gives the check box and caption `cameraNotSupported` without asking the macOS version. Test: `machineLearningReasonIsTheCamera`. Not run before macOS 27: no such Mac here; the code no longer has a branch on the version for these photos. |
| F4 | Fixed: the note reads "macOS can't decode this raw file, so it's shown without a profile. Temperature and Tint are relative to the camera's white balance, and Color noise reduction isn't available." (catalog key and value; place, style and the combined accessibility element kept). |
| F5 | Fixed in `docs/USER_GUIDE.md`: "not the macOS decoder's profile and contrast"; the groups by their names (Tone, Presence, Tone Curve, Color Mixer, Color Grading, …); Use machine learning "dimmed unless a paste or preset turned it on; it then says it isn't applied, and Luminance applies instead". |

The review's improvement (the tab laying out as for a JPEG while a photo
loads): the Adjust tab shows its spinner while the editor is loading
(`loupeAdjustState` `.loading`) and lays the controls out only once the file's
kind is known, so no layout of the wrong kind is drawn. M5 stays a manual check.

## Build and tests

- Baseline before this pass (`7957ed1`): `swift build` complete with one
  warning (C9); `swift test` 859 tests in 129 suites passed, 1 known issue.
- Now: `swift build` complete, no warning. `swift test`: 906 tests in 133
  suites passed, the same 1 known issue (`LiveSessionTests`, values above
  white in the cached stages). `RAF_SAMPLE=… swift test --filter
  LibRawFallbackTests`: 7 tests passed. `Scripts/build-app.sh all`: both
  bundles built (SDK 27.2, minimum 15.0).
- Two existing tests changed, neither loosened: `RAWDecodeGraphTests`' tripwire
  lists `SystemRAWDecoder.swift` as a place a RAW filter is made and never
  rendered; `LiveRegionRendererTests.decodeWhileMoving` uses a file that does
  not exist and now tells the renderer the system decodes it, as the editor does.
- No golden moved, no pipeline bump, no migration. Renders of files the system
  decoder reads are unchanged; the live session's decode size for a crop keeps
  its old arithmetic for them.

## Debug-script check

A copy of the release bundle with its own bundle identifier, a new library
root in a scratch folder, the X-E3 and X-T3 files added with `addfolder`.
`print ml` now starts with the decoder and what the Adjust tab offers.

- X-E3: `decoder fallback wb modes [As Shot, Auto, Custom] temperature enabled
  true value 0`; `ml checkbox off enabled false tip 'Not available for this
  camera.'`; Color and Decoder not shown. `adjust warmth 60`, `adjust auto wb`
  (relative 16, −22), exposure, highlights and `luminance-nr` each saved a
  stack and an undo step, and the loupe's picture changed (snapshots).
- X-T3: `decoder system wb modes [As Shot, Auto, Daylight, Cloudy, Shade,
  Tungsten, Fluorescent, Flash, Custom] temperature enabled true value 6,246 K`,
  the check box enabled, Color and Decoder shown; Auto gave 5886 K, tint 7.
- Not checked by script: the note's look (the snapshot leaves the inspector
  blank in this design, and SwiftUI text is not found through AppKit).

- After the design review's fixes, a paste from the X-T3 (Daylight, Use
  machine learning on) onto the X-E3: `wb mode 'As Shot'`; `ml caption 'Not
  applied: this camera isn't supported. Luminance applies instead.' triangle
  true`, the check box on and enabled with the same tip; the badge's help ends
  "It's shown with Luminance instead."; turning it off gives the dimmed "Not
  available for this camera." again.

**For a person:** the design review's manual checks M1 to M6 (`review.md`):
the note's look, White Balance, the dimmed check box, a paste from a raw macOS
decodes, switching between the two photos, and Custom staying Custom.

## Timings

Release build, local copies, `photobench rawcompare --runs 3` (first run /
best of three; `docs/PROFILING.md` says how to read the system's column):

| File | System | LibRaw full | LibRaw half |
| --- | --- | --- | --- |
| Sony ARW 24 MP | 0.19 / 0.06 s | 1.18 / 1.15 s | 0.13 / 0.12 s |
| Fujifilm X-T3 RAF (26 MP, compressed) | 0.05 / 0.05 s | 9.62 / 9.55 s | 0.64 / 0.62 s |
| Fujifilm X-E3 RAF (24 MP) | no image | 8.79 / 8.71 s | 0.60 / 0.59 s |
| Canon CR2 | 0.05 / 0.05 s | 1.29 / 1.26 s | 0.30 / 0.30 s |
| Olympus ORF | 0.09 / 0.08 s | 1.32 / 1.30 s | 0.42 / 0.41 s |
| Panasonic RW2 | 0.05 / 0.02 s | 1.09 / 1.09 s | 0.16 / 0.16 s |
| Panasonic HDR DNG | 0.04 / 0.03 s | unsupported | n/a |

The half-size decode serves thumbnails and fitted previews (a 2560 pixel
preview of the X-E3 takes about 0.6 s to decode). The full decode, about 9 s
for an X-E3 file, is needed at 100%, for an export over half the frame's size,
and for a crop that keeps less than 85% of the frame's long edge at preview
size. LibRaw is single-threaded here.

## Open (the owner's call)

- **Q5, the frame.** Decided for Fujifilm RAFs: the camera's own frame
  (6000x4000 for the X-E3). Other files LibRaw decodes keep its first inset
  crop, or its visible area. A 16:9 or 1:1 picture: no sample here.
- **Lens corrections: what does not match the camera** (above): about 3
  pixels of the full-size photo in the outer quarter of the radius with the
  35mm, more in the far corners. Accept, or look for the camera's exact rule.
- **Lens corrections for other makers.** Only Fujifilm's tables are read. A
  raw of another maker that the system decoder gives no image for is shown
  uncorrected (darktable reads Sony's, Olympus's and Panasonic's and a DNG's
  opcodes the same way). No such file here.
- **No control** for the camera's corrections (as ruled). Design question in
  the engineer's report: whether one is wanted.
- **Stale previews** from earlier builds of this branch (above): delete the
  preview cache once.
- **Edits when a later macOS decodes the camera.** The photo then goes to the
  system decoder: its look changes (Q4 accepted that for the cache), and a
  relative Temperature or Tint set meanwhile stops applying, because a system
  raw takes Kelvin values only. The stack keeps the values. Requirements issue R1.
- **The level of a LibRaw decode depends on its content.** LibRaw's default
  takes the brightest value in the frame as white when it is over 75% of the
  file's white level (`adjust_maximum_thr`, against color casts in clipped
  highlights). Two frames of one scene can differ by up to 0.4 EV. Kept as
  LibRaw's default; found by the inset crop test. Requirements issue R2.
- **LGPL in a distributed binary.** The bundles carry no notices; the LGPL asks
  for a notice and a copy of the license with a binary, and for a note of the
  change and its date in each modified file (the two headers carry none: the
  vendored tree was not to be touched; the notices file has it). Not legal
  advice. Requirements issue R3.
- **Choosing Custom on a photo that holds pasted Kelvin values.** By D5's
  rule 2 the pop-up then still shows As Shot (the Kelvin values stay in the
  stack and both relative values are 0) until a slider moves. Built as ruled;
  a Design question in the engineer's report.
- **White balance across decoders.** Ruled for this fix (D2: not offered). A
  Kelvin white balance pasted onto a LibRaw photo, or a relative one onto a
  raw macOS decodes, is kept and does nothing; the designer proposes an
  enhancement for the product manager (slug `white-balance-across-decoders`),
  which also covers R1.

## Not done, and why

- **`CLAUDE.md`** and **`.claude/agents/code-reviewer.md`**: not edited by
  the engineer, whose rules do not let another agent's message authorize a
  change to `CLAUDE.md` or `.claude/`, whatever it relays. The main session
  made the edits (`4ff5d30`: line 158, Dependencies, the reviewer's rule;
  `b162839`: Layout and Commands). Proposed for the lens corrections: a line
  in the Rendering rule, in the engineer's report.
- **`README.md`**: the product manager's (`docs/WORKFLOW.md`); see **README**.
- **`Sources/CLibRaw`**: untouched except for `LICENSE.LGPL`.
- No decoder badge in the grid or loupe, no `decoder` field in `photocli`'s
  JSON, no multithreaded LibRaw, no zlib or JPEG support in it: proposed as
  follow-ups in the report.

## README

For the product manager at Ship:

- Line 161: GRDB is no longer the only third-party code. Proposed: "GRDB is
  the only package dependency. LibRaw 0.22.3 is vendored in `Sources/CLibRaw`
  under the LGPL 2.1 (see `THIRD_PARTY_NOTICES.md`) and decodes raw files the
  macOS raw decoder cannot."
- The layout table has no row for `Sources/CLibRaw` (LibRaw's source, built by
  `Package.swift`; never edited).
- Requirements: raws macOS does not decode (the Fujifilm X-E3 on macOS 27.2)
  now render, flatter, with the differences the user guide lists; Fujifilm
  files with the camera's frame and lens corrections.
- `THIRD_PARTY_NOTICES.md` now also names darktable (GPL 3 or later: the lens
  correction math, written again).
- The License section may want a line that LibRaw is included under the LGPL 2.1.
- `CLAUDE.md`'s "Scope so far" needs an entry for this fix; its Commands could
  list `RAF_SAMPLE=path/to/file.RAF swift test --filter LibRawFallbackTests`.
