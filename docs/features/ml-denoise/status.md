# ML noise reduction for RAW files: implementation status

Owner: swift-macos-engineer. Implements [`prd.md`](prd.md) (Approved, owner
rulings 2026-11-05) against [`design.md`](design.md) (Designed, RI-1 to RI-7
ruled). Branch `feature/ml-denoise-prd`, at `054bf4e` when work started.

**Status: In progress.** Everything is built and tested except AC1, which is
blocked on a requirements issue (RI-E1 below). Open: the owner's items, the
designer review, and the manual checks listed under each criterion.

States: Not started · In progress · Done · Blocked (waiting on a question
below) · Shipped.

## Build and test

- Baseline at `054bf4e` (2026-11-05, Apple M4 Pro, macOS 27.2 build 26B123,
  Xcode SDK 27.2): `swift build` clean; `swift test` 517 tests in 94 suites
  passed, 1 known issue (the `withKnownIssue` in "Live render session",
  pre-existing).
- Latest: `swift build` clean, no warnings in the sources. `swift test`: 548
  tests in 96 suites passed, 1 known issue (the same), 1 test disabled with
  its reason (AC1, RI-E1). Goldens and `EditStackCorpusTests` unchanged.
  `PreviewCacheKey.currentPipelineVersion` is still 6. `UPDATE_GOLDENS` was
  never run.
- A test file not touched here (`SmartAlbumTests.swift:165`) has an
  unused-result warning when the test target compiles; it was there before.
- Debug-script runs use a copy of the bundle with the bundle identifier
  `me.sesser.gus.debugtest` and a scratch library made by `photobench`
  (three 1600 × 1200 DNGs, one 6000 × 4000 DNG, a JPEG and HEICs), so they
  never touch the owner's library or preferences.

## How it is built

- **One state** (R3). `NoiseReduction.machineLearning` (persisted as
  `machineLearning: true` in the `noiseReduction` operation, left out when
  false). A stack without it keeps its bytes and render hash. Profile's
  `decoderVersion` is never a machine learning version:
  - A photo's stack holding `9` or `9.dng` there reads as machine learning
    on, with Profile at the default (`Adjustments(stack:)`). The stored
    bytes stay as they are until the photo is next edited, so the render
    hash and cached previews do not change.
  - A preset's stack keeps the legacy version in Profile
    (`Adjustments(presetStack:)`, `RawDecode.legacyMachineLearningVersion`),
    so it is saved and exported as it was. Applying Profile from it turns
    machine learning on and leaves Noise Reduction's other values
    (`Adjustments.replacing`).
  - `photocli develop --set rawDecode.decoderVersion=9.dng` sets machine
    learning on, as the Decoder pop-up does.
- **Decoder versions.** The machine learning decoder is major version 9:
  `9.dng` for DNG files, `9` for camera raws. The SDK declares both.
- **Availability and outcome** (`MachineLearningNoiseReduction`).
  - One availability rule: `available`, `notOnThisMac` (before macOS 27),
    `cameraNotSupported` (the file's `supportedDecoderVersions` lack version
    9), `notRaw`.
  - One outcome per decode: `notRequested`, `applied`,
    `notApplied(notOnThisMac | cameraNotSupported | failed)`.
  - `Status` turns the values, the group's on/off, the availability and the
    last frame's outcome into the design's states S1–S8, and gives
    *applied*, Color's availability, the badge's reason and the pop-up's
    enabled state. Every surface reads it.
- **Decoding** (`RAWDecodeSettings.apply`). The version is chosen in this
  order:
  1. the machine learning version, when it is asked for and available;
  2. otherwise Profile's choice;
  3. otherwise the decoder's default, pinned below version 9 (RI-7).

  The pin leaves the default alone while it is older than 9, as it is on
  macOS 27. So no existing stack renders differently and no pipeline bump is
  needed. `PreviewGenerator.decode` decodes classically when the request
  cannot apply, or when the machine learning decode gives no image, and
  reports the outcome. Live frames, export renders and the sharpening map's
  input carry that outcome.
- **Previews.** A render that asked for machine learning and did not get it
  is kept in memory for the session (`PreviewDiskCache.storeForSession`,
  64 MB), never on disk. Otherwise a macOS update, a newly supported camera,
  or a one-off failure would leave the fallback cached under the same key.
- **App.**
  - `AdjustmentEditor` holds the inspector's `machineLearning` status and
    the badge's reason, which follows the values on screen, hover previews
    included, and changes with the frame. It also holds the spinner flag
    (`isAwaitingMachineLearningFrame`: waiting more than 0.5 s, and only on
    arrival when the preview was not cached), plus `setMachineLearning`
    ("Turn On/Off Machine Learning") and `chooseDecoder` ("Decoder").
  - `AdjustView`: the check box row, its caption and Color's dimmed state.
    The Decoder pop-up selects the machine learning version while it
    applies, lists it only where it is available, and is dimmed in S5, S6
    and S8.
  - The loupe caption has one spinner slot and the badge after HDR and
    before Offline. The canvas's VoiceOver value gains "Machine learning not
    applied".
  - Batch commands (`changeAdjustments`) leave machine learning off on files
    that are not RAW and post one Activity row. Exports post one row per
    reason before their own.
- **A failed decode is not remembered** for the session (design §3 leaves
  this to the engineer). The next change of values tries again, as the
  design describes, and nothing extra appears on screen.

## Progress

| Step | State | Commit |
|---|---|---|
| 1 PhotoCore: setting, availability, decode, pin, outcome, legacy stacks and presets, export and photocli JSON, session-only fallback previews | Done | `35fa306` |
| 2 photocli and export tests | Done | `f9f492c` |
| 3 photobench `denoise` (R14) | Done | `1482a88` |
| 4 Inspector, Decoder pop-up, loupe caption, VoiceOver, batch and export rows, strings, debug script | Done | `1332380`, `e35c14e` |
| 5 USER_GUIDE.md, this file | Done | this commit |

## Acceptance criteria

Test names are in `Tests/PhotoCoreTests/MachineLearningNoiseReductionTests.swift`
(suites "Machine learning noise reduction" and "…: photocli and export").
Tests that need the decoder's version 9 run only where it exists (macOS 27);
elsewhere they are skipped with the reason "needs the RAW decoder's version
9 (macOS 27 or later)". The fallback and failure paths use per-file
overrides and run on every Mac.

| AC | State | How |
|---|---|---|
| AC1 | **Blocked (RI-E1)** | "Flat areas: … (AC1)" is written as the PRD words it and disabled with the reason. On every synthetic fixture tried, classical at 100 leaves *less* flat-area energy than machine learning (numbers below). |
| AC2 | Tested (macOS 27) | "Edges: … not lower than classical at 100 (AC2)", on a new stripes scene with noise (edge step: machine learning 0.725, classical 0.688). Through the export path's full-resolution render (`PreviewGenerator.rendering`). |
| AC3 | Tested | "A stack without the setting keeps its parameters, render hash and decode settings"; "The pinned default …" (pure rule); "With the decoder's default at 9.dng, a stack that does not ask for it decodes with the pinned version" (the seam: the filter is set to `9.dng` before the settings apply). All goldens and `EditStackCorpusTests` pass unchanged. |
| AC4 | Tested | Legacy stacks with `9.dng` and `9` read as on; one with Profile off stays off; a legacy stack renders as before (pixels equal to a direct `9.dng` decode); Profile's `7.dng` is kept under machine learning and applies again when it is off; Profile-only presets, a paste of Profile and Profile off leave it on; a pre-feature Profile preset turns it on with Luminance and Color unchanged, also after a catalog save and load and a preset file round trip; the Decoder pop-up's choice; `develop` keeps one state. App: `print ml` checked the pop-up and check box agree (see Debug-script checks). |
| AC5 | Tested + debug script | Color kept across on/off; Color unavailable only while applied (`Status`); asked for and not applied, Color changes the render. Debug script: Color dimmed with its tooltip in S2, enabled in S5, S6, S7 and S8. |
| AC6 | Tested + manual pending | "The availability rule …" (unit test of the rule); "This Mac: …" (the synthetic DNG is available on macOS 27). Debug script: a JPEG shows no check box; S3 and S4 dimmed with their captions (with the override). **Manual:** on macOS 15 or 26, any raw shows "not available on this Mac"; a real camera missing from the decoder's list shows "Not available for this camera." |
| AC7 | Tested + manual pending | Override `notOnThisMac`: render equals the classical render and says why; the stack keeps the setting after a reopen and an Exposure change; `photocli develop` on another parameter, `render` and `export` keep it and report `notOnThisMac`. Debug script: badge and caption in S5. **Manual:** the same on a Mac running macOS 15 or 26. |
| AC7a | Tested + debug script | Override `failsDecode`: the classical render, the stack unchanged, live frames say `failed`; `photocli render` and `export` JSON give "could not be applied to this photo"; the export's Activity report has the row. Debug script: S8 caption, badge and its tooltip with `ml override fail`; the export row "3 photos were exported without machine learning noise reduction: it could not be applied to these photos." |
| AC8 | Debug script + **manual pending** | On a 24 MP DNG the spinner was off at 0.3 s and on at 0.8 s, and `key right` moved to the next photo while the frame was rendering. **Manual (owner):** a real 24 MP raw, arrow keys and rating keys during the wait. |
| AC9 | Tested + debug script | "Turning it on and off gives back the stack's bytes" (content and render hash). Debug script: the undo action is "Turn On Machine Learning". **Manual:** ⌘Z in the active app (scripted launches have no key window, so `menuitems Undo` shows it dimmed). |
| AC10 | Tested + debug script | Paste and presets reach raws only, Reset All and the Details reset clear it. Debug script: paste over 3 DNGs, a JPEG and 100 HEICs gave the DNGs `machineLearning: true`, left the others without it, and posted "Machine learning noise reduction was left off for 101 photos that aren't raw files." **Manual:** a RAW+JPEG pair shown as its RAW (the scratch library has no pairs); paste on macOS 15 or 26. |
| AC11 | Tested | `adjustments` lists `noiseReduction.machineLearning` (boolean, default false); `develop --dry-run` prints a stack with it on; `render` and `export` JSON have `machineLearning` with `requested`, `applied` and, when not applied, `reason` and `message`. `develop` refuses it on a file that is not RAW (`invalidEdit`). |
| AC12 | Done | `photobench denoise` runs; the six times are below. |
| AC13 | **Owner** | Open: which cameras and files, and the judgment. |

## Engineer open questions (PRD), measured on this Mac

Apple M4 Pro, macOS 27.2 (26B123), SDK 27.2.

- **Is RAW 9 Apple-silicon-only?** macOS 27 runs only on Apple silicon
  (macOS 26 was the last release for Intel Macs), so an Intel Mac never has
  it. This Mac reports `arm64`. "Needs macOS 27 or later" is therefore the
  right wording, and the design question in §11 does not arise. Not
  measurable here: an Apple silicon Mac whose decoder model is not yet on
  disk (see RI-E2).
- **`extendedDynamicRangeAmount` under RAW 9:** honored. With 1.0 the
  synthetic DNG's largest value is 1.25 under both `8.dng` and `9.dng`, so
  highlight recovery and negative exposure keep their headroom. Not
  measured: floating-point DNGs (HDR merges), since there is no decodable
  one among the fixtures. If their decoder does not list version 9, they
  are `cameraNotSupported` and render as today.
- **Does the synthetic DNG decode through RAW 9?** Yes: it lists `6.dng`,
  `7.dng`, `8.dng` and `9.dng` (default `8.dng`), and `9.dng` renders. But
  the model barely reduces its noise unless the file has a DNG
  `NoiseProfile` tag. With the tag it does, though still less than the
  classical decoder at 100 (RI-E1). The fixture writer now has opt-in
  `writesNoiseProfile`, `iso` and a `stripes` scene; the default bytes are
  unchanged, so no golden changed.
- **Draft and `scaleFactor` under RAW 9:** `scaleFactor` is honored (0.5
  gives half size, and a 512 px thumbnail of a 24 MP raw takes 0.32 s
  against 1.34 s for the 2560 px preview). Draft mode is ignored: draft and
  non-draft decodes are identical pixel for pixel. The loupe's interactive
  frames therefore gain only from the smaller decode size, not from draft.
- **Color under RAW 9:** `isColorNoiseReductionSupported` is false and
  `colorNoiseReductionAmount` has no effect, as WWDC26 session 305 says.
  Luminance does have an effect: on the stripes scene with a noise profile,
  flat-area energy drops 3.3× from Luminance 0 to 100.
- **Setting the decoder version** keeps white balance, boost and extended
  range but resets the noise amounts to that version's defaults. The
  existing order (version, then amounts) is right. An unsupported version is
  ignored: the filter stays on its default and still gives an image.
- **AC7a failure seam:** `MachineLearningNoiseReduction.setOverride(_:for:)`
  with `failsDecode: true`, per file (tests run in parallel, so each uses its
  own file) or for every file (the debug script's `ml override fail`). It
  makes the decode take the same path a real failure does:
  - a requested version that does not take, or
  - a decode that gives no image or an empty one.

  Both fall back to the classical decode with `notApplied(.failed)`. A model
  failure that shows up only while the GPU renders (after the lazy image is
  built) is not caught. Core Image gives no error there, and I have no way
  to cause one.

## Measurements (R14), for the PRD

`swift run -c release photobench denoise --runs 5`: a synthetic 6000 × 4000
DNG (2 % noise, NoiseProfile, ISO 6400), Luminance 50, Color 50. Median of 5
after a first run. Apple M4 Pro, macOS 27.2, release build. Two runs agreed
within 0.04 s.

| Output | ML off | ML on |
|---|---|---|
| Thumbnail (512 px) | 0.06 s | 0.32 s |
| 2560 px preview | 0.07 s | 1.34 s |
| Full-resolution export (JPEG) | 0.11 s | 1.38 s |

The first machine learning decode in a fresh process after a while took
3.05 s (the model loading); a second process right after did not pay it
again. These are synthetic-file times. The owner's own raws can be timed
with `photobench denoise --source <file>`.

## Debug-script checks (design §12)

Run against the scratch library with the bundle copy:

- **DR1:** S1, S2, S3/S4 (override `cameraNotSupported`), S5 (override
  `notOnThisMac`), S6, S7 (`adjust off noiseReduction`) and S8 (override
  `fail`). In each: check box state, enabled state and tooltip, caption
  text and triangle, Color row enabled and tooltip, as in §3. A JPEG shows
  no check box and no caption.
- **DR2:** checking the box selects "9.dng (machine learning)". Choosing
  `7.dng` turns it off and shows `7.dng`; choosing `9.dng` again turns it on.
  In S7 the pop-up shows Profile's `7.dng`. In S5, S6 and S8 the pop-up is
  dimmed with "Turn off Use machine learning to choose another decoder."
  "(default)" is on `8.dng`.
- **DR5:** badge "Machine Learning Not Applied" with each reason's tooltip
  in S5, S6 and S8. None in S2 or S7.
- **DR6:** undo action name "Turn On Machine Learning".
- **DR7, DR8:** the Activity rows above.
- **DR9:** the canvas's value reads "Machine learning not applied, 3 of 105"
  in S5 and "3 of 105" otherwise. The check box's own VoiceOver name could
  not be read this way: `accessibility AXCheckBox` finds none of the
  inspector's check boxes (an existing limit), so it is manual.

Not checked by script: anything drawn (the inspector is a glass pane that
`snapshot` leaves blank), Increase Contrast, Reduce Motion, VoiceOver
speech.

## Requirements issues (for the product manager)

- **RI-E1. AC1 cannot pass on a synthetic fixture.** AC1 says the machine
  learning render has lower high-frequency energy in flat areas than
  classical at Luminance 100 and Color 100. Noise left in flat areas (luma,
  sRGB curve; lower is less noise), DNGs with 2 % Gaussian noise. Pattern
  rows: mean square of the noisy render minus the clean one, 1600 × 1200.
  Stripes row: the high-frequency energy AC1 names, 640 × 480.

  | Fixture | Classical 100 | Machine learning 100 |
  |---|---|---|
  | Pattern, no NoiseProfile | 0.00234 | 0.00398 |
  | Pattern, NoiseProfile | 0.00014 | 0.00134 |
  | Stripes, NoiseProfile | 0.00019 | 0.00044 |

  The classical decoder, given the noise level, smooths uniform Gaussian
  noise on flat synthetic areas away. The model keeps more texture, and
  without a noise profile it barely denoises. AC2 (edges) does hold. AC1's
  comparison rewards smoothing, and synthetic noise is not camera noise.
  Options:
  - **(a)** Replace AC1's fixture with a real high-ISO raw committed to the
    repository. That needs the owner's file and consent (clean-room and
    size), and the test would only run where its camera is supported.
  - **(b)** Change AC1 to what holds on the fixture: machine learning at
    Luminance 100 has less flat-area energy than at Luminance 0 (tested now
    as "Luminance is the machine learning amount"). Leave the comparison
    with classical to the owner's manual check (AC13).
  - **(c)** Measure noise and detail together (for example, flat-area
    energy at equal edge contrast). This needs a definition from you, and I
    can't promise the model wins on synthetic data.

  I recommend (b) now, plus (a) if the owner offers a file. The AC1 test is
  written as worded and disabled until you rule.
- **RI-E2. The decoder's model is an on-demand resource.** The macOS 27 SDK
  adds `CIRAWFilter.downloadResources(timeout:completionHandler:)` and
  `downloadAllResources` (27.2): macOS may fetch the demosaic and denoise
  models on demand. On this Mac `9.dng` decoded without calling them, so the
  model was already present. The app never calls them, since owner ruling 1
  says no downloaded model. If a Mac lacks the model, my guess is the decode
  fails (S8, "could not be applied to this photo") or falls back, but I
  could not cause that. Two questions:
  - Is asking macOS to fetch Apple's own model (with progress) a "downloaded
    model" under ruling 1? If yes, nothing changes.
  - If no, it needs a design: where the progress shows, and what happens
    offline.
- **RI-E3. "9.dng" in the PRD also means "9".** Camera raws (CR3, NEF, ARW
  and so on) list the machine learning decoder as `9`; only DNG files list
  `9.dng`. I treated both as the machine learning version everywhere (R3,
  legacy stacks, `develop`). For camera raws the pop-up item reads "9
  (machine learning)", as the design's `%@ (machine learning)` key allows.
  Please confirm, and update R3 and AC4's wording if you agree.
- **RI-E4. Legacy stacks whose Profile or Noise Reduction group was off.**
  R3 says a stack saved with `9.dng` reads as on with "rendering unchanged".
  Two cases cannot both read as on and render unchanged:
  - **Profile off:** the `9.dng` was not rendering. I read it as off and
    drop the inactive decoder choice, so rendering is unchanged.
  - **Noise Reduction off and Profile on:** it reads as on inside a group
    that is off, so it renders classically where it rendered with `9.dng`
    before.

  Both need a pre-release build on macOS 27 and a group turned off, so I
  expect no real stacks. Please confirm.
- **RI-E5. `photocli develop` on a file that is not RAW.**
  `noiseReduction.machineLearning=true` on a JPEG fails with `invalidEdit`
  ("applies to RAW files only"), the way `develop` already fails a value
  that would have no effect. The app's batch commands leave it off silently
  and count it in Activity. Confirm or rule otherwise.

## Design questions (for the designer)

- **DQ-1. Plural "one" variations I wrote** (§9 gives only the plural forms):
  - "Machine learning noise reduction was left off for 1 photo that isn't a
    raw file."
  - "1 photo was exported without machine learning noise reduction: this
    Mac needs macOS 27 or later."
  - "1 photo was exported without machine learning noise reduction: its
    camera isn't supported."

  The "could not be applied to this photo" one follows §9. Please check the
  wording.
- **DQ-2. The caption's indent** is the small check box's title inset as
  AppKit reports it (18 pt in the current design), measured at run time
  rather than fixed. Please check the alignment on screen in both designs.
- **DQ-3. The spinner on arrival.** The editor renders a first frame for
  the histogram 250 ms after a photo opens. When the photo's preview was
  already cached, that frame is not something the person waits on, so I do
  not show the spinner for it. Without a cache, it shows after 0.5 s.
  Confirm this matches §6's "arriving at a photo … whose preview isn't
  cached yet".

## Owner open items (not answered here)

- Which 2–3 cameras and high-ISO files for AC13, and whether those cameras
  are on the decoder's list. On this Mac `CIRAWFilter.supportedCameraModels(with:
  .version9)` lists 69 camera models (of 941). DNG support is decided per
  file.
- The time ceiling, if any, now that R14's numbers are in.
