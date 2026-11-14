Issue: #170

# White balance and baseline look across decoders: implementation status

Feature, branch `feature/libraw-color-pipeline`, cut from `develop` at `868f8f6`.
Covers #171 (closed). PRD: the body of #170. Design: `design.md` (§12 is the
engineer's list).

**Status: Done** (2026-11-14). Every acceptance criterion is built and has its
test or scripted check. The design review's findings F1 to F3 and the code
review's C2 to C7 are fixed (**Review findings**, below). Open, and not the
engineer's to close:

- **C1 (owner's ruling, through the main session):** how the Adobe DNG SDK is
  acknowledged. Not touched, as told: `THIRD_PARTY_NOTICES.md` and the
  disclosure comments in `ColorTemperature.swift`, `CameraColor.swift` and
  `CameraProfile.swift` are as the reviewer read them.
- **RI-E1 (owner, through the product manager):** AC5's closeness numbers. The
  PRD's A2 leaves them to a first measurement and the owner's confirmation.
  Measured: they hold for the X-E3's Kelvin and its picture at 5500 K, not for
  tint (off by up to 13 on every camera tried, against A2's 5), and not for
  the X-T3's Kelvin (14% to 30% under the system decoder's). QA records AC5
  as measured, not as passed.

DQ-1 is ruled (design §17.1) and built.

Next: the second pass of code-reviewer and the designer (the fixes change
source and the UI), then qa-tester, then the owner's sign-off (AC6's visual
check is the owner's).

## Review findings

Design review (`review.md`, 2026-11-14):

| # | Outcome |
|---|---|
| F1, DQ-1 | Fixed as design §17.1 reads. `WhiteBalanceControls.picking(.custom, from:)` for a raw by either decoder: `preset` custom, a missing `temperature` or `tint` becomes the as-shot value (unrounded), stored values are kept, relative values are untouched; `.relative` stores Custom beside what is stored; `.unavailable` returns nil. Tests: `customStoresTheNumbersShown` (from As Shot; from Tungsten, 2850 / 0 kept; a Kelvin without a tint gets the as-shot tint; `.relative`; `.unavailable`; the render moves by at most one level of 255 on both decoders; a paste carries the numbers), `relativeValuesOnARaw` (Custom on 60 / 30 stores the numbers beside them and shows Custom), `libRawPhotoHasARawsWhiteBalance`. Script below |
| The step's ranges (the reviewer's question on §17.1, ruled by the main session: keep the clamp, show and store the clamped values) | The color step keeps a Kelvin within 2000 to 50000 and a tint within ±150, the sliders' ranges. A LibRaw photo's as-shot values are now shown and stored through the same function (`CameraColorStep.rendered`), so for a camera white beyond a range the slider, Custom's stored number and the render are one number. As Shot itself still renders the camera's own neutral, so on such a photo choosing Custom (or moving a slider) changes the picture to the range's end. System raws are as before: the system decoder takes the number as stored. Test: `asShotBeyondTheRanges` (1750 K; tint 190). In the user guide |
| F2 | Fixed: `whiteBalanceCaption` has no top padding; the stack's 2 points are the gap, as under the machine learning check box. M9 is the check |
| F3 | Fixed in `docs/USER_GUIDE.md`: "under **Profile**, a note stands in place of its pop-ups"; every mode name in bold. Added (the review's optional line): Custom keeps the numbers shown and a paste carries them; and the ranges |

Code review (`code-review.md`, 2026-11-14):

| # | Outcome |
|---|---|
| C1 | Not touched: waits for the owner's ruling |
| C2 | Fixed. The fixture, not the decoder: `SyntheticDNG.mosaic(options:)` draws a picture's mosaic once and `write(to:options:mosaic:)` writes a file from it; `decodeIsOriented`, `insetCropIsDecoded` and `whiteLevelIsTheFiles` write both of their files from one mosaic, and the new tests that compare two files do the same. Soak: `swift test --skip-build --filter "LibRawDecoderTests\|LibRawFallbackPipelineTests"` 80 times in each of two processes at once: 160 runs, 0 failed (the reviewer had 7 of 80) |
| C3 | Fixed. `SyntheticDNG.Color` writes `CameraCalibration1` and `2`; two camera kinds (`calibrated`, `calibratedForward`: two lights with daylight named first in the file, a calibration for each, an analog balance) run through `CameraColorTests` (math against the reference, which is now AB × CC × CM with the reference neutral for forward matrices), `calibrationAndAnalogBalance`, and `CameraColorStepTests.stepMatchesReference` (a LibRaw decode of the file). Checked by mutation: with `calibration(at:)` returning the identity, 4 tests fail; without the `swapAt`, `stepMatchesReference` fails for both kinds |
| C4 | Fixed. `LibRawFallbackTests.theExposureTheCameraHeldBackIsAdded` reads the file's `RawExposureBias` from LibRaw apart from the decoder's use of it and requires that exposure of the camera color, the step and the transform (1 stop for `DSCF5123.RAF` and `DSCF5139.RAF`, both at −1.72). With the wiring removed it fails on those files. A file shot at 100% holds nothing back and cannot tell; the test prints that |
| C5 | Fixed. `CameraColorStep.fileExposure` (`LibRawDecoder.fileExposure(of:)`: the Fujifilm held-back exposure, else a DNG's baseline exposure) is used when there is no camera color. Test: `exposureWithoutColorData` |
| C6 | Fixed. `LibRawDecoder.dngExposure(baselineExposure:)`: finite and within 4 stops either way, else not used. Test: `dngBaselineExposure` (5000, 200 and −50 stops render as the file without the tag, every value a number) |
| C7 | Fixed. When a rendition written since the cutoff cannot be removed, the folder is not renamed; the older renditions are moved under version 9 one by one, copied where a move is refused, and the one left behind stays under version 8 for `removeObsoletePipelineVersions`. Nothing written since the cutoff comes under version 9. Test: `carryOverSurvivesAFailedRemoval` (a folder made read-only) |

## What was built

A raw the system decoder gives no image for is still decoded by LibRaw, but
to **camera RGB** now (balanced for the camera's own white, not clipped at
it, no color matrix), and a **color step** after the decode turns that into
the working space for the stack's Kelvin and tint. The stack's white balance
reaches the decode as it reaches the system decoder's
(`RAWDecodeSettings.temperature` and `tint`), so nothing in the stack says
which decoder reads the file (R1, R9).

| Piece | Where |
|---|---|
| Kelvin and tint against chromaticity (Robertson's isotherms, tint scale 3000) | `Sources/PhotoCore/CameraColor/ColorTemperature.swift` |
| The DNG specification's mapping: neutral to white point and back, matrices read between two lights, forward matrices, Bradford to D50, then to Rec. 2020 | `CameraColor/CameraColor.swift`, `Matrix3x3.swift` |
| The profile value (R8): calibrations with their lights, forward matrices, hue/saturation and look tables (carried, not applied), tone curve, baseline exposure | `CameraColor/CameraProfile.swift` |
| What one decode and one white balance come to (gains, clip at white, matrix, exposure, curve) and its Core Image graph: `CIColorMatrix`, `CIColorClamp`, `CIColorMatrix`, `CIColorCurves`; no custom kernel | `CameraColor/CameraColorTransform.swift` |
| The step kept with a decode; the built-in look and its measurement record | `CameraColor/CameraColorStep.swift` (`CameraColorStep`, `BaselineLook`) |
| LibRaw: camera-space decode, the camera's color data from the header, the file's white level, Fujifilm's held-back exposure | `Preview/LibRawDecoder.swift` |
| The step applied in `PreviewGenerator.decode`; `Decoded.camera` keeps the decode before it | `Preview/PreviewGenerator.swift` |
| Which settings reach which decoder, and which key a decode | `Preview/SystemRAWDecoder.swift` (`settings(_:reaching:systemReads:)`, `Memo.decodeKey`) |
| Live frames at fit and at 100% keep the camera-space decode and apply the step per frame | `Edits/LiveRenderSession.swift`, `LiveRegionRenderer.swift` |
| Relative values never render on a raw | `RenderContext.balancedByDecoder`, `AdjustmentRenderer.globalSteps` |
| Auto White Balance: Kelvin and tint for LibRaw's photos | `Edits/AutoAdjust.swift` |
| What the Mode pop-up shows and offers (§5, §6) | `WhiteBalance.kelvinDisplayPreset` (`Edits/Adjustments.swift`), `WhiteBalanceControls` (`Edits/AutoAdjust.swift`) |
| The stack's profile reference | `CameraProfileReference` (`Edits/Adjustments.swift`) |
| Pipeline version 9, with version 8 carried over | `Preview/PreviewCacheKey.swift`, `PreviewDiskCache.carryOver` |
| The Adjust tab, the note, the captions, the strings | `PhotoApp/Views/AdjustView.swift`, `Model/FallbackDecoderText.swift`, `AdjustmentEditor.whiteBalanceControls`, the String Catalog |
| Debug script | `Model/DebugMachineLearningCommands.swift` (`print ml`), `DebugAdjustCommands.swift` (`adjust wb pick`) |
| `photobench generate --dng-without-color N` (a file for AC14) | `Sources/PhotoBench/Generate.swift` |

`Sources/CLibRaw` is untouched. No new dependency. No migration.

### How the color step works

1. LibRaw decodes with `output_color` 0 (camera RGB), `highlight` 1 and the
   app's own multipliers (the reciprocal of the as-shot neutral, the largest
   1), so no channel is clipped below its saturation.
2. The step multiplies each channel by its gain for the chosen white
   (camera neutral from the white point's XYZ through the color matrix),
   clips at white, applies the camera-to-working matrix times the baseline
   exposure, then the baseline tone curve. A blown highlight is white at any
   white balance: every saturated channel is at or over 1 before the clip.
3. As Shot uses the camera's neutral itself. A Kelvin or tint alone takes the
   other from as shot, as the system decoder does.

A white balance change is a new graph over the kept decode: never a new
decode (design §4, M8). Measured in the bundle on an X-E3 file at 100%: a
Temperature scrub's frames are full-resolution region frames with the
values applied (`print viewport`: `region frame 1761x1368 … of 6000x4000
applied`), with no decode between them.

### Accuracy with one matrix (R3)

A file that is not a DNG has one matrix, LibRaw's for the camera under D65.
It is used at every temperature: a neutral comes out neutral at any Kelvin,
but colors away from neutral drift the further the light is from daylight,
where a second (tungsten) matrix would correct them. A DNG read through
LibRaw uses both of its matrices and its forward matrices. Documented in
`CameraColor`'s comment and in the user guide.

### The profile value (R8) and what it does not do yet

`CameraProfile` holds everything a `.dcp` has. The color step applies the
matrices, illuminant interpolation, forward matrices, tone curve and baseline
exposure. **It does not apply hue/saturation maps or the look table**: the
value carries them (so #89 loses nothing reading a file), no profile this
build can make has one, and applying them is #89's (the PRD's non-goal
"applying Adobe `.dcp` profiles"). The seam for #89 is one line in
`PreviewGenerator.decodeWithLibRaw` (`CameraColor.with(profile:)`).

The stack's reference is the operation kind `cameraProfile` with a string
parameter `identifier`. This build reads it into `Adjustments.cameraProfile`,
keeps every parameter as stored (also ones it has no name for), writes it
back unchanged, and renders with the built-in profile. A build from before
keeps it as an operation of an unknown kind. No build writes one.

## Decisions the PRD left to the engineer

**O7, the cache (R12).** A cache key is made from the content hash and the
stack, where nothing is read; which decoder a file gets takes reading the
file, which may be offline. A LibRaw-only key would need that answer stored
per photo (a migration). So `currentPipelineVersion` is 9 for everything,
**and version 8 is carried over**: at launch, previews written before LibRaw
decoding existed in any build (2026-11-13, midnight UTC; #161's first commit
is from that afternoon) are moved under version 9 with one folder rename; the
ones written since are deleted and made again on demand. So the library's
previews survive, those of offline masters included (R11's "their cached
previews stay valid"), and no preview of a LibRaw photo's old look is shown.
Checked in the bundle on the scratch library: 10 renditions dated before the
day were found under `v9`, 11 dated after were gone and made again, `v8` was
gone.

**R7, the white level.** LibRaw's `adjust_maximum_thr` is 0: white is the
file's white level whatever the frame holds. No trade-off to return: the
sensors measured saturate within 0.4% of that level (54 X-E3 files: clipped
areas peak at 16322 to 16383 of 16383 over a black of about 1022; an X-T3, a
Sony, an Olympus and a Panasonic at 0.999 and up), and the color step counts
a channel as saturated at 0.99 of the level (`LibRawDecoder.whiteMargin`), so
blown highlights are exactly white, for 0.015 EV of highlight range. A sensor
that saturates more than 1% under its file's white level would keep a cast in
blown highlights; none was found.

**O4, one baseline for every camera.** Not close enough across makers. The
system decoder's boost curve is the same for every camera tried, but its
exposure is per camera, and no file states it:

| Camera | System = gain × LibRaw − offset | The system decoder's `baselineExposure` |
|---|---|---|
| Fujifilm X-E3 (public file) | 1.050 (0.070 EV), 0.0027 | 0.02 |
| Fujifilm X-T3 (4 files) | 0.98 to 1.10 (0.063 EV in the mean), 0.0028 to 0.0032 | 0.12 |
| Panasonic DMC-ZS100 | 1.046 (0.065 EV), 0.0025 | 0.10 |
| Sony ILCE-7M3 | 1.255 (0.328 EV), 0.0034 | 0.35 |
| Olympus E-M5 Mark III | 1.334 (0.416 EV), 0.0040 | 0.40 |
| Canon EOS 5D Mark II | 1.434 (0.520 EV), 0.0046 | 0.55 |

The look is the X-E3's: 0.07 EV, the offset folded into the tone curve. A
LibRaw photo from a Sony, Olympus or Canon would open a quarter to half a
stop darker than the system decoder shows it (proposed follow-up below).

**Fujifilm's dynamic range setting (found while measuring).** A RAF records
how far below nominal its raw data was exposed (`RawExposureBias`: −0.72
normally, −1.72 at 200%, −2.72 at 400%). The system decoder brightens by the
difference (its `baselineExposure` is 0.12 and 1.12 on X-T3 files at −0.72 and
−1.72), and so does the color step now (`LibRawDecoder.fujifilmExposure`).
Without it the owner's X-E3 files shot at 200% (both sample files are) opened
a stop too dark. The stop above white is past white in the default render and
comes back with Exposure or Highlights.

**Auto on a photo without color data (design §6).** Stores nothing:
`AutoAdjuster.whiteBalance` throws `whiteBalanceUnavailable`, and the group
does not offer Auto there.

**When availability is known (design §6).** From the header, before the tab
lays out (`LibRawDecoder.cameraColor`, about 1 ms, with the as-shot values).
The decode asks the same function, so the two cannot disagree. No Design
question.

**Auto's wait (design §4).** A half-size LibRaw decode (about 0.6 s for an
X-E3) and the search on a reduced copy; the pop-up is dimmed meanwhile. For
the owner at M3.

**Commit trailer.** The task asked for `Claude Sonnet 5.5`; the commits carry
`Claude Fable 5.2`, the model that made them (as `1804e7c` on `develop` does).

## The baseline look, measured (R6, O1: match the system decoder)

`BaselineLookMeasurementTests` (`RAW_LOOK_SAMPLES`), macOS 27.2.1, decoder
version 8, nine files both decoders read. The X-E3 file is a public
uncompressed one (raw.pixls.us `DSCF2175.RAF`): the system decoder reads it,
so the look's exposure and black offset are the X-E3's own, not a stand-in's.

- **Tone curve.** The system decoder's default render against its own render
  with `boostAmount` 0, pixel for pixel, per channel of the working space in
  the sRGB encoding. One curve fits every camera between 0.25 and 0.62 of the
  encoded range to ±0.002. The Olympus has less shadow contrast, and two
  files differ in their highlights; the look is the middle of the nine. 33
  knots, `BaselineLook.encodedKnots`.
- **Exposure and black.** The table above. The offset (the system decoder's
  shadows are deeper by about 0.003 of white) is folded into the curve.

The test asserts the built-in look against a fresh measurement (0.01 of the
encoded range, 0.05 EV), so a later macOS that changes the system decoder's
look is noticed when it is run.

## LibRaw against the system decoder (R5, AC5, AC6)

`LibRawAgainstSystemTests` (`RAW_BOTH_SAMPLES`), each file decoded by both:

| Camera (files) | As shot, Kelvin | Tint | Unedited: EV, tone spread, ΔE | At 5500 K, tint 0: ΔE |
|---|---|---|---|---|
| X-E3 (1, public) | 3864 against 3923: −1.5% | −13 | +0.04, +0.3%, 2.7 | 4.3 |
| X-T3 (6) | −14% to −30% | +7 to +13 | −0.03 to +0.16, ±2%, 0.8 to 3.0 | 9.2 to 17.5 |
| Sony ILCE-7M3 (1) | +0.1% | +7 | −0.26, −7%, 3.6 | 3.6 |
| Canon EOS 5D Mark II (1) | −7% | −13 | −0.45, −12%, 7.4 | 8.5 |
| Olympus E-M5 Mark III (1) | −4% | −5 | −0.23, +3%, 9.5 | 6.7 |
| Panasonic DMC-ZS100 (1) | −2% | +5 | +0.01, +1%, 1.1 | 3.3 |

ΔE is the median CIELAB difference of 16-pixel blocks of a 320-pixel render,
both clipped to 0 … 1; tone spread is the standard deviation of the encoded
luminance.

- **The scale is the same.** For one chromaticity, `CIRAWFilter` and
  `ColorTemperature` give the same Kelvin and tint to single precision
  (`ColorTemperatureTests`). With one matrix for both decoders (a synthetic
  DNG) their as-shot values agree to 0.01% and 0.01 of tint.
- **The matrices are not.** LibRaw's matrix for a camera is Adobe's; the
  system decoder has its own. For the X-T3 the two read one neutral about a
  fifth apart. The camera's own table of white balances by Kelvin (in the
  file) agrees with LibRaw's matrix to 5% from 3400 K to 7100 K, so it is
  the system decoder that stands alone there. For the X-E3 the one file that
  could be compared (shot near 3900 K) agrees to 1.5%; the X-E3's own table
  and LibRaw's matrix agree to 4% up to 5300 K and drift to 13% at 6300 K.
- **Away from as shot the methods differ too.** With the same matrix, a grey
  at 4000 K (as shot D65) is 12% bluer and 4% less red from the system
  decoder than from the DNG specification's Bradford adaptation. Balancing in
  camera space instead (as a forward matrix does) was tried against six real
  files at five temperatures and is no closer to the system decoder overall,
  so the specification's method stays (R3).

## Acceptance criteria

Default-run tests are on synthetic DNGs: the 256 x 192 one is decoded by
LibRaw on macOS 27.2.1 and the 1536 x 1152 one by the system decoder. Tests
that need LibRaw whatever the macOS call `LibRawDecoder` directly.

| # | State | Test or check |
|---|---|---|
| AC1 | Done | `WhiteBalanceAcrossDecodersTests.libRawPhotoHasARawsWhiteBalance` (the group's model, `WhiteBalanceControls`: nine modes, Tungsten is 2850 K / 0, the render changes and is bluer; `PhotoApp` has no test target, so the model is in PhotoCore). Script on an X-E3 file: `wb state kelvin asShot 5318 K tint 2`, nine modes; `adjust wb pick tungsten` gives `wb mode 'Tungsten'`, `2,850 K`, tint `0`; undo gives As Shot |
| AC2 | Done | `kelvinAppliesOnBothDecoders` (Daylight and 2500 K change both, in the same direction). `photocli render --long-edge 600 --set whiteBalance.preset=custom --set whiteBalance.temperature=2500`: the PNG's SHA-256 differs from the unedited one on the X-E3 file (`1d892cbe…` to `319a7815…`; on `develop` it does not) and on the X-T3. See RI-E3 for the command without `preset` |
| AC3 | Done | `LibRawFallbackPipelineTests.autoWhiteBalanceFollowsTheDecoder` (Kelvin and tint, whole numbers, no relative values; a grey picture with a cast comes back to D65 within 2% and 3 of tint). Script: Auto on an X-E3 file stores `"preset":"auto","temperature":5332,"tint":-12` and shows them |
| AC4 | Done | `CameraColorStepTests.stepMatchesReference` (one matrix, two, forward matrices; five white balances; with and without the look) against `Reference/CameraColorReference.swift`, tolerance derived from half-float roundings put through the reference. `CameraColorTests` checks the math alone to 10⁻⁶ |
| AC5 | Built and measured; tolerances for the owner (RI-E1) | `LibRawAgainstSystemTests.compare` prints every number and asserts the measured limits per camera |
| AC6 | Done for Fujifilm; owner's visual check open | The same test: X-E3 +0.04 EV, tone spread +0.3%; X-T3 within 0.16 EV and 2%. Other makers: O4 above |
| AC7 | Done | `LibRawDecoderTests.whiteLevelIsTheFiles`: a crop without the picture's brightest values decodes pixel for pixel as the whole |
| AC8 | Done (tables carried, not applied) | `standInProfile` (other matrices, forward matrices, a tone curve, an exposure: the render is the reference's for them); `unknownProfileReference` (loads, written back as stored, renders as without it, kept through an edit) |
| AC9 | Done | `decoderSwap`: one file as LibRaw and as the system decoder; same as-shot values, the white balance applies in both, the stack's bytes are unchanged. JPEG: Kelvin inert, relative applies |
| AC10 | Done | `relativeValuesOnARaw`, `kelvinModeShown` (§5's six cases). Script: relative 60 / 30 on an X-E3 file keeps `"relativeTemperature":60,"relativeTint":30`, shows `'As Shot'` with as-shot sliders. Choosing Custom there (§17.1) stores `"preset":"custom","relativeTemperature":60,"relativeTint":30,"temperature":5318.442815396026,"tint":1.740704475662509`, shows `'Custom'` with `5,318 K` and `+2`; one undo (`White Balance`) returns to As Shot and the relative values alone. `photocli`: the PNG with relative values is the unedited one's |
| AC11 | Done | Full `swift test`, no golden updated. `photocli render` of the X-T3 file (unedited, 2500 K, +1 EV, full size) and of a JPEG (unedited, relative, Kelvin): the same SHA-256 as a build of `868f8f6` (`6c07dff3…`, `fc877d6d…`, `745b18a2…`, `66de99f7…`) |
| AC12 | Done | `cachedPreviewsAreRegenerated` (version 9; a version 8 preview written since 2026-11-13 is not found; an older one is carried over) |
| AC13 | Done | `pasteBetweenDecoders` (the stack and the render, both ways, and a preset). Script: Daylight copied from the X-T3 and pasted onto the X-E3 shows `'Daylight'`, `5,500 K`; one undo (`Paste Adjustments`) restores the empty stack; 4000 K from the X-E3 onto the X-T3 likewise |
| AC14 | Done | `unusableColorData` (no matrix; no neutral): renders as shot at the baseline, Kelvin and relative values change nothing, Auto throws, the model is W1 or W2. Script on a `--dng-without-color` file: `wb state unavailable`, Mode `'As Shot'` disabled with the caption as its tip, no sliders; after a stored Daylight `wb state unapplied`, modes `[As Shot, Daylight]`; As Shot removes it |

Also: `ColorTemperatureTests` (known illuminants, round trip, the system
decoder's own mapping), `fujifilmExposure`, `dngBaselineExposure`,
`exposureWithoutColorData`, `customStoresTheNumbersShown`,
`asShotBeyondTheRanges`, `carryOverSurvivesAFailedRemoval`,
`calibrationAndAnalogBalance`,
`LibRawFallbackPipelineTests.rendererAdjustsTheLibRawImage`,
`decodeSettingsDoNotDecodeAgain` (a white balance changes the frame, not the
decode count; the 100% renderer stays ready).

Tests changed, none loosened: the `LibRawDecoderTests` and
`LibRawFallbackPipelineTests` cases that said a LibRaw photo takes relative
values and ignores Kelvin now say the reverse, which is the requirement.

## Build and tests

| | Before (`26843e4`) | Now |
|---|---|---|
| `swift build` | complete, no warning | complete, no warning |
| `swift test` | 952 tests in 138 suites passed, 1 known issue (`LiveSessionTests`) | 988 tests in 144 suites passed, the same known issue (982 before the review fixes) |
| `Scripts/build-app.sh all` | | both bundles built |

The test target has two warnings from before (`SmartAlbumTests`,
`VirtualCopiesTests`).

With samples, all passing after the review fixes: `RAF_SAMPLE` on two X-E3
files (9 tests each), `RAW_LOOK_SAMPLES` (9 files), `RAW_BOTH_SAMPLES` (11
files).

**The failure seen once before the reviews** (`insetCropIsDecoded`) was the
fixture, as the code review found (C2): two drawings of one picture are not
always the same bytes when other drawings run at once. Fixed; 160 runs under
load, none failed.

## Debug-script checks

A copy of the release bundle with the identifier
`me.sesser.gus.debugtest.wb170` (the usual test domain holds a toolbar
configuration that crashes at launch, a known issue), a scratch library from
`photobench import`: three X-E3 files, one X-T3, a JPEG, a synthetic DNG
without color data and one with. `inspector on` first: a new preference
domain starts with the inspector hidden.

- `print ml` now prints `wb state kelvin|relative|unavailable|unapplied`,
  the as-shot values and the caption, then the Mode pop-up (selected, enabled,
  tip, items), Temperature and Tint rows and the note.
- X-E3: `kelvin asShot 5318 K tint 2` (5215 K / 3 and 5358 K / −2 for the
  other two); the Temperature field at 4000 stores Custom with
  the as-shot tint, undo name `Temperature`; Shade is `7,500 K`, `+5`; turning
  the group off renders the as-shot hash.
- Custom (§17.1, after the review fixes): on the X-E3 `adjust wb pick custom`
  stores `"preset":"custom","temperature":5318.442815396026,"tint":1.740704475662509`
  and shows `'Custom'`, `5,318 K`, `+2`; picking it again changes nothing;
  from Tungsten it keeps `2850` / `0`. On the X-T3, from Daylight, it keeps
  `5500` / `0`. On the JPEG it stores `"preset":"custom"` alone.
- X-T3: `decoder system wb state kelvin asShot 6246 K tint 24`, unchanged.
- JPEG: `wb state relative`, modes `[As Shot, Auto, Custom]`, sliders at 0.
- AC1, AC3, AC10, AC13, AC14 as in the table.

**For a person:** `review.md`'s M1 to M9. M1, M7 and M9 (the note's and the
captions' look and spacing) cannot be scripted: snapshots leave the inspector
blank.

## Requirements issues (for the product manager)

- **RI-E1. AC5's tolerances (A2).** Proposed from the measurement, by what a
  person would see:
  - As-shot Kelvin: within 5% holds for the X-E3 and the Sony, Olympus and
    Panasonic files, 7% for the Canon, not for the X-T3 (14% to 30%).
  - Tint: within 15, not 5.
  - The picture at 5500 K: median ΔE up to 6 for the X-E3, up to 10 for the
    other makers, 9 to 18 for the X-T3.
  - Unedited: within 0.3 EV and ΔE 5 for Fujifilm files.

  For the owner's primary scenario (an X-T3 white balance pasted onto an
  X-E3 photo): the paste applies and changes the photo, but 5500 K means a
  cooler picture than as shot on the X-T3 (which the system decoder reads as
  6246 K) and a slightly warmer one on the X-E3 (5318 K). Options: (a) accept,
  with the user guide's sentence; (b) a per-camera correction of LibRaw's
  Kelvin toward the system decoder's, which needs a file of each camera that
  the system decoder reads and is only possible for cameras it knows.
  Recommendation: (a).
- **RI-E2. R8's wording.** "The colour step takes its inputs (… hue/saturation
  and look tables …) from a profile value": the value carries the tables, the
  step does not apply them. Applying them is a 3D table in HSV per the DNG
  specification, and belongs with reading `.dcp` files (#89). Say so in R8,
  or ask for it here.
- **RI-E3. AC2's command.** `--set whiteBalance.temperature=2500` alone
  changes nothing on either decoder, on `develop` too: the preset stays As
  Shot, which ignores stored Kelvin values. It takes
  `--set whiteBalance.preset=custom` as well. Either AC2's text, or `--set`
  could imply Custom when a Kelvin value is set (an enhancement).
- **RI-E4. A3 and the stand-in.** The system decoder reads uncompressed X-E3
  files, so the X-E3 itself can be measured (one public file here). The X-T3
  is a poor stand-in for Kelvin (above) and a fair one for the look. An
  uncompressed raw from the owner's own X-E3, in daylight, would make the
  X-E3 row more than one file at 3900 K.
- **RI-E5. One exposure for all cameras (A6, O4).** Measured above: not
  close for other makers.

## Design questions (for the designer)

- **DQ-1. Custom on a raw with leftover relative values.** Ruled: design
  §17.1 (option (b), on every raw). Built; see **Review findings**, F1.
- None open.
- **For the designer's review, not a question:** the user guide now says the
  Kelvin shown can differ from what macOS reads for the same camera (§7 puts
  accuracy notes in the guide).

## README

For the product manager at Ship:

- Raws macOS can't decode: the same White Balance as any raw (nine modes,
  Kelvin, Tint, Auto), a built-in profile and a baseline look close to a raw
  macOS decodes; no longer "flatter and darker" or "relative Temperature and
  Tint".
- `Sources/PhotoCore/CameraColor/` is new (the color step). `CLAUDE.md`'s
  Layout line for `PhotoCore` could name it; its Rendering rule could say:
  "A raw LibRaw decodes is decoded to camera RGB and gets a color step
  (`CameraColorStep`: the stack's Kelvin and tint by the DNG specification's
  method, the built-in profile's matrix, a baseline look measured against
  the system decoder); `RenderContext.balancedByDecoder` is true for a raw by
  either decoder, and relative white balance renders only where it is false."
- Commands: `RAW_LOOK_SAMPLES=a.RAF:b.ARW swift test --filter
  BaselineLookMeasurementTests` and `RAW_BOTH_SAMPLES=a.RAF:b.RAF swift test
  --filter LibRawAgainstSystemTests`; `photobench generate
  --dng-without-color N`. Run the first on every new macOS (the look is
  measured against the system decoder).
- `PreviewCacheKey.currentPipelineVersion` is 9; version 8's previews from
  before 2026-11-13 are carried over at launch.
- `THIRD_PARTY_NOTICES.md` opens with a paragraph on published
  specifications and methods (the Adobe DNG Specification, Robertson's
  method, the DNG SDK's tint scale, EXIF). They are not projects, so they
  have no section and no About entry (`AcknowledgementConsistencyTests` ties
  sections to the About window's record). If the owner wants the DNG SDK
  named in the About window, that is a record entry, a string and a README
  Credits line.
- `docs/PROFILING.md` has the new LibRaw-against-system look figures.

## Not done, and why

- Hue/saturation maps and look tables are not applied (RI-E2).
- No per-camera or per-maker baseline exposure (RI-E5).
- No `.dcp` reading, Profile pop-up or profile storage (#89, non-goal).
- No conversion of stored relative values (R10, ruled).
- `CLAUDE.md` and `README.md` are not edited (the owner's and the product
  manager's).
- The colorless-file path keeps LibRaw's own fallback for a file without
  white balance coefficients, which measures the picture (its default since
  0.20), as on `develop`.

## Proposed issues (for the main session to file)

- **enhancement: "Baseline exposure by maker for raws LibRaw decodes".** The
  built-in look's exposure is the Fujifilm X-E3's. The system decoder's is
  per camera (0.07 to 0.52 EV on the files measured); a LibRaw photo from a
  Sony, Olympus or Canon opens 0.25 to 0.45 EV darker than the system decoder
  would show it. A small table by maker, measured with
  `BaselineLookMeasurementTests`.
- (Withdrawn: "LibRaw inset crop test failed once under load". It was the
  fixture, fixed on this branch as C2. The code review proposes a bug of its
  own, on `develop`: a render of one HDR DNG that is not the same from run to
  run.)
- **enhancement: "`photocli --set whiteBalance.temperature` implies Custom"**
  (RI-E3).
