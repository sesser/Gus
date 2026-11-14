# White balance and baseline look across decoders: code review

Owner: code-reviewer. Date: 2026-11-14. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/libraw-color-pipeline`, `868f8f6`..`43f159f` (the code is
that of `67b58b2`; `43f159f` adds the design review and ruling §17.1 only,
which is not built yet). Build and tests, on macOS 27.2.1 (26B131), Swift
6.4.2: `swift build` complete; `swift test` 982 tests in 144 suites passed,
1 known issue (`LiveSessionTests`); `Scripts/build-app.sh all` built both
bundles. With samples, all passing: `RAF_SAMPLE` on two X-E3 files (8 tests
each), `RAW_LOOK_SAMPLES` (9 files), `RAW_BOTH_SAMPLES` (11 files), with the
numbers `status.md` gives. Repeated 80 times in two processes at once, the
LibRaw suites failed 7 times (C2).

## Verdict

Ready for QA: no blocker, and the color math, the kept camera-space decode,
the cache carry-over and the "nothing else renders differently" claim all
hold up under an independent check. Three things should be fixed before the
pull request: the DNG SDK's code is recorded as if it were a specification
(C1, the owner's ruling), the LibRaw tests are flaky because of the fixture,
not the decoder (C2), and the DNG calibration path has no test (C3).

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix (owner's ruling, before the pull request) | `THIRD_PARTY_NOTICES.md:3-31`; `Sources/PhotoCore/CameraColor/ColorTemperature.swift:109-154`; `CameraColor.swift:8-10, 95-106`; `CameraProfile.swift:134-149` | The notices file puts Adobe's DNG SDK in a paragraph on "published specifications and methods" that are "no project's code", with no section, license or copyright. Compared with the SDK's public source (version 1.4, the one at hand; the notice names 1.7.1): `ColorTemperature.init(_:)` and `.chromaticity` are `dng_temperature::Set_xy_coord` and `Get_xy_coord` statement for statement (the same loop from index 1, `index == 1` giving weight 0, the last line taken unconditionally, a negative distance set to 0, the interpolated direction, the same order of operations); `CameraProfile.kelvin(ofLightSource:)` is `dng_camera_profile::IlluminantToTemperature` case for case. Both are disclosed as "written again in Swift with nothing copied". Not disclosed: `CameraColor.white(ofNeutral:)` is `dng_color_spec::NeutralToXY` (start at D50, 30 passes, stop under 0.0000001, the mean of the last two on the last pass), while the notice and the file's comment say `CameraColor.swift` is "written from the specification's text". The specification says only "iterate until the xy values converge" | The record of where code came from is wrong for one function and incomplete for the rest: the SDK's files say "Adobe permits you to use, modify, and distribute this file in accordance with the terms of the Adobe license agreement accompanying it", and nothing in the repository carries that agreement or its copyright line. Every other source followed this way has a section with its license, copyright, files and functions (LightCraft, darktable), which `AcknowledgementConsistencyTests` ties to the About window and the README's Credits | `CLAUDE.md` Layout (`THIRD_PARTY_NOTICES.md`: math ported from other projects, with notices); clean-room constraint; new third-party sources need the owner |
| C2 | Should fix | `Tests/PhotoCoreTests/LibRawDecoderTests.swift:96, 143, 239`; `Sources/PhotoFixtures/SyntheticImages.swift:53` | The failure `status.md` names (`insetCropIsDecoded`, seen once) is the fixture, not a decode. `SyntheticImages.makeImage` draws with Core Graphics, and its pixels are not the same every time when several drawings run at once: 15 to 20 of 720 concurrent drawings differed, 0 of 2,000 one at a time; up to 2 of 720 DNGs written at once differed, in 36 to 246 bytes. The decoder is steady: 0 of 2,160 concurrent decodes of two fixed files differed from their first decode. Three tests write "the same picture" twice and compare the two decodes pixel for pixel: `decodeIsOriented` (7 cases), `insetCropIsDecoded`, and this branch's new `whiteLevelIsTheFiles` | `swift test --filter "LibRawDecoderTests\|LibRawFallbackPipelineTests"` run 40 times while another test process ran: 6 runs failed (`decodeIsOriented` orientation 2, 4, 5, 8 and `insetCropIsDecoded` twice, each `differing == 0`); with four suites in the filter, 1 of 40 (`decodeIsOriented` 6). CI will fail at some such rate, and each failure reads as a decoder race | Tests are deterministic |
| C3 | Should fix | `CameraColor.swift:68-73, 121-126`; `Preview/LibRawDecoder.swift:312-330` | No test reaches a DNG's `AnalogBalance` or `CameraCalibration`: `SyntheticDNG.Color.analogBalance` exists and nothing uses it, and the fixture cannot write the `CameraCalibration` tags | In a scratch copy, making `CameraColor.calibration(at:)` return the identity, and removing the `swapAt` that keeps each camera calibration with its own light, both pass the whole of the color suites. (The code is right for what I could check: a diagonal `AnalogBalance` of 1.25, 1, 0.8 gives the as-shot Kelvin and the matrix of the same camera with the balance folded into its `ColorMatrix`, to rounding; the calibration illuminants written in either order give equal values; a neutral stays neutral with forward matrices.) DNGs from Adobe's converter carry `CameraCalibration` and `AnalogBalance` tags (per-unit values for some cameras), so this path will run on real files | Every behavior has a test that fails without it |
| C4 | Nit | `Tests/PhotoCoreTests/LibRawFallbackTests.swift:95`; `LibRawDecoder.swift:336-338` | The one assertion on a real RAF's held-back exposure accepts anything from 0 to 3 | With the three lines that pass `fujifilmExposureBias` into the color removed, `RAF_SAMPLE=…/DSCF5123.RAF` (a file at −1.72) still passes all 8 tests. Only `RAW_BOTH_SAMPLES` with a file shot at 200% catches it (−1.24 EV against the system decoder), and that depends on which files are given. Assert the value the file states (1 stop for −1.72) | Tests |
| C5 | Nit | `CameraColor/CameraColorStep.swift:28`; `LibRawDecoder.swift:302-349, 411` | A file whose color data cannot be used loses its own exposure: `cameraColor(of:)` returns nil before the DNG's `BaselineExposure` or the Fujifilm bias has anywhere to go, and the step falls back to `.baseline(of: .builtIn(calibrations: []))` with a file exposure of 0 | A Fujifilm RAF shot at 200% dynamic range from a camera LibRaw has no matrix for (state W1) opens a stop darker than the camera's JPEG; the same file with a matrix opens a stop brighter. Rare; no regression (`develop` had no such exposure at all) | Correctness |
| C6 | Nit | `LibRawDecoder.swift:332-334` | A DNG's `BaselineExposure` is taken as the file gives it, bounded only below (−100, LibRaw's "not in the file") | A DNG stating 5000 stops gives a factor of infinity and a frame of which every sample is not a number (196,608 of 196,608 in the 256 x 192 fixture); 200 stops renders everything at the curve's ceiling. No crash, and a thumbnail is written. Keep it within a few stops, as `fujifilmExposure` does for its own value | Values from outside files are bounded before use |
| C7 | Nit | `Preview/PreviewDiskCache.swift:163-170`; `PhotoApp/Model/LibraryModel.swift:752-753` | When one rendition written since the cutoff cannot be removed, `carryOver` returns without renaming, and `removeObsoletePipelineVersions`, which runs next, deletes the rest of `v8`, the renditions from before the cutoff among them | Scratch check with one read-only folder under `v8`: `carryOver` gives (0, 0), and afterwards the old rendition is under neither `v8` nor `v9`. For an offline master that preview cannot be made again until its volume is back. This is what a plain bump does to everything, and it never shows a stale preview, so it is the safe side; moving the kept renditions one by one in that case would keep them | Data safety of the carry-over (asked for in this review) |

## Questions

- **For the owner, through the product manager (C1).** Which of two: (a)
  acknowledge the DNG SDK as a project whose code was followed (a section
  with Adobe's license agreement and copyright, the three functions named,
  the About record and the README credit that `AcknowledgementConsistencyTests`
  then asks for), or (b) have the three functions written from Robertson's
  paper and the DNG specification alone, so the paragraph is true. With (a)
  the owner also decides whether Adobe's agreement sits with this project's
  own license. Note for (b): the table's 325 mired entry must stay 0.24702
  (the misprint in Wyszecki and Stiles, corrected elsewhere to 0.24792),
  because the system decoder uses it: with 0.24792
  `ColorTemperatureTests.matchesTheSystemDecoder` fails by 0.0013 in x or y.
- **For the product manager (RI-E1, R5 and AC5).** As the PRD's A2 states
  them, R5 and AC5 are not met for the X-T3 (as-shot Kelvin 14% to 30% under
  the system decoder's, ΔE 9 to 17.5 at 5500 K), and the sample test passes
  because its limits were set from the measurement (0.32 and ΔE 20 for
  "other Fujifilm"). The engineer says so; it needs the owner's ruling before
  sign-off, and QA should record AC5 as measured, not as passed. One more
  number for that ruling, from the cameras' own files (`WB_GRBLevelsStandard`,
  the camera's white balance for D65) through LibRaw's matrix by a
  calculation of my own: X-E3 6573 K, tint +2.5 (1% from D65); X-T3 5694 K,
  tint +24 (12% under). So for the X-T3 part of the gap is LibRaw's matrix
  against the camera itself, not only the system decoder "standing alone";
  for the X-E3, the camera that matters here, the matrix agrees with the
  camera. The same calculation gives the as-shot values the app shows (5318 K,
  tint +1.7 for `DSCF5123.RAF`).
- **For the designer (ruling §17.1, before it is built).** Custom stores the
  as-shot numbers unrounded. On a LibRaw photo those then render through the
  Kelvin and tint round trip instead of the camera's own neutral: the same
  to within 0.2% in Kelvin and 0.5 of tint (`ColorTemperatureTests.roundTrip`),
  so not the same bytes as As Shot, and the color step keeps Kelvin within
  2000 to 50000 and tint within ±150, so a photo whose as-shot values lie
  outside (candle light, some LED light) would change when Custom is picked.
  Accepted, or should the step leave as-shot numbers unclamped?
- **For the product manager (R7).** The PRD asks for the trade-off to be
  returned if a fixed white level leaves casts in blown highlights. The
  engineer measured five makers' files, found none within the 1% margin and
  returned none; a sensor that saturates more than 1% under its file's white
  level would show one. Recorded as a known limit in `status.md`; nothing to
  rule unless the owner wants it.

## Checked and fine

- **Color math**, read against the DNG specification and checked by a
  calculation of my own (Python, Robertson's method from the formula): the
  neutral from `cam_mul`, XYZ to camera as calibration times color matrix,
  the weight linear in reciprocal temperature and held outside the two
  lights, the forward-matrix path with the reference neutral, linear Bradford
  to D50 and D50 to Rec. 2020, the Y = 1 scaling, the clip at white after the
  gain (every saturated channel is at or over 1, so blown highlights are
  white at any white balance), LibRaw's matrix orientations (`colormatrix`
  rows are camera channels, `forwardmatrix` rows are XYZ), the multipliers
  with the largest at 1 so LibRaw's own clip never bites, and the tint's sign.
  Extreme and non-finite Kelvin and tint render finite pixels (0, negative,
  NaN and infinite values fall back to as shot or the range's ends).
- **Mutations in a scratch copy** (22, each run against the color and LibRaw
  suites): 19 caught by the default tests: relative white balance on a raw,
  the live session and the 100% region skipping the color step, the decode
  keyed by white balance, the weight linear in Kelvin, no Bradford, the tint's
  sign, LibRaw's content-dependent white level, the margin, the clip at
  white, forward matrices, the carry-over keeping everything, version 8, Auto
  without its LibRaw branch, the profile reference not written back, the
  measurements' settings, a DNG's baseline exposure, the unusable-color path,
  the display rule. Not caught: C3 (two) and C4.
- **No decode on a white balance change.** `LiveRenderSession` and
  `LiveRegionRenderer` keep `Decoded.camera.linear` and apply the step per
  frame; `Memo.decodeKey` is `.none` for a LibRaw raw; the stage cache's key
  holds the stack's hash without masks and effects, so it changes with the
  white balance; drafts are reduced before the step. `SharpeningMapRefiner`,
  `FringePicker`, `ColorAlignmentMeasurement` and the editor's sample pixels
  now pass the white balance to the LibRaw decode.
- **`RenderContext.balancedByDecoder`**: true for both decoders at the two
  places a raw's context is made, `isRaw` by default elsewhere; local
  adjustments keep relative white balance on raws (`applyLocal`).
- **Nothing else renders differently.** `photocli render` from a build of
  `868f8f6` and from this branch, SHA-256 of the PNGs: the X-T3 file
  unedited, +1 EV and Custom 2500 K at 600 pixels and at full size (7 of 7
  equal; `6c07dff3…`, `745b18a2…`, `66de99f7…` as `status.md` has them); a
  Sony, Canon, Olympus, Panasonic raw and an HDR DNG unedited, at 3200 K,
  with relative values and with Tungsten, exposure and sharpening; a JPEG and
  a TIFF unedited, relative, Kelvin and +1 EV. All equal, except one render
  that varies from run to run on `develop` as well (see Follow-up issues
  below). The X-E3 file differs from `develop` unedited and at 2500 K, and
  its relative values now render as shot, as required. No golden, tolerance,
  `Package.swift`, `Sources/CLibRaw` or script changed.
- **Pipeline version 9** is bumped in the commit that changes the rendering
  (`745f295`). The carry-over: the cutoff is 2026-11-13 00:00 UTC, before
  #161's first commit (13:30 PST that day), and before #161 these files had
  no preview at all (`undecodable`), so nothing dated earlier can be a
  LibRaw photo's; renditions are never touched after they are written, so
  the date is the writing's; it runs in `LibraryModel.open` before the model
  exists, so nothing in the process reads or writes the cache meanwhile;
  `photocli` and the importer do not use the disk cache; a launch
  interrupted mid-way resumes at the next; a `v8` that turns up once `v9`
  exists is not merged. It walks the folder on the main actor once: 0.87 s
  for 99,840 renditions here. Renditions written since 2026-11-13 are
  dropped whatever their file is, offline masters' included, which R12 allows.
- **Stack.** `cameraProfile` is written only when it holds parameters, so
  every earlier stack keeps its bytes and its hash; its parameters, known or
  not, survive a read and an edit; a newer `kindVersion` is kept as an
  unknown operation; no group carries it; a build from before keeps it as an
  unknown kind. No migration. Relative values on a raw are kept and never
  rewritten.
- **Concurrency.** New types are value types; `CameraDecode`'s
  `@unchecked Sendable` gives its reason (an immutable `CIImage`); the
  header read for the Adjust tab is off the main actor.
- **Strings**: three keys in the catalog, the old note's key gone, no product
  name; `LocalizationTests` and `BrandingTests` pass. **Debug script**:
  `adjust wb pick` runs inside `adjust`'s undo group and waits for Auto
  inside it. No `ScrollView`, menu, launch option or dependency added.
- **The baseline look** is the system decoder's own output measured, not
  taken from an application; the measurement reproduces (curve within 0.0000
  at its knots, 0.070 EV).
- **Security.** No new parser, subprocess, network code or path taken from a
  file. Values read from LibRaw's header are checked before use except C6.

## Follow-up

Second pass: not yet. The engineer's fixes and ruling §17.1 (Custom stores
its numbers), once built, come back here.

Issues for the main session to file or reword:

- **bug (on `develop`, not from this branch): "A render of one HDR DNG is not
  the same from run to run".** `photocli render --input P1180234-HDR.dng
  --long-edge 800 --set whiteBalance.preset=tungsten --set
  whiteBalance.temperature=2850 --set whiteBalance.tint=0 --set
  exposure.ev=0.5 --set sharpen.amount=60` gives one of two PNGs (`d285ec89…`
  13 times and `7c4166d1…` 3 times of 16 from a build of `868f8f6`; 10 and 6
  from this branch), differing in 19% of the samples by up to 4953 of 65535.
- **The engineer's proposed bug "LibRaw inset crop test failed once under
  load"** should not be filed as written: it is C2, a fixture that is not
  the same under concurrent drawing, with no decode race behind it. Fix it
  on this branch or file it with that cause.
