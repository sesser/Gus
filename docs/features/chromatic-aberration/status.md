# Chromatic aberration and color fringe removal: implementation status

Owner: swift-macos-engineer. Implements [`prd.md`](prd.md) (Approved, owner
2026-11-07, rulings 1–15, R1a–R1c) against [`design.md`](design.md)
(Designed). Branch `feature/chromatic-aberration`, which carries the
stitchable-kernels spike (`1b537e0`).

**Status: Done.** Every requirement and acceptance criterion is built and
has a test or a debug-script check below; M1 and M2 are the manual checks
the PRD names. The design questions and requirements issues are ruled
(design.md §19, prd.md revisions of 2026-11-08) and their changes are built.
Next: code-reviewer and the designer review, then qa-tester.

States: Not started · In progress · Done · Blocked · Deferred.

## Build and test

- Baseline at `82c4df2` (2026-11-07): `swift build` clean; `swift test` 578
  tests in 100 suites passed, 1 known issue (the `withKnownIssue` in "Live
  render session", pre-existing).
- Latest: see the end of this file ("Latest run").
- Every existing golden passes unchanged; `UPDATE_GOLDENS` was never run;
  `PreviewCacheKey.currentPipelineVersion` is unchanged (R11, AC8). No new
  goldens: the new scenes are checked against CPU references instead.
- Debug-script runs use a copy of the bundle with the bundle identifier
  `me.sesser.gus.debugtest` and a scratch library of the scene files from
  `photobench scenes` (one of them on a disk image that was then ejected, for
  an offline original), always with `--library-root`.

## How it is built

- **Model** (`Edits/LensCorrections.swift`). Two modules in a new section
  `lens`: `ColorFringes` (`colorFringes`: `color1`/`color2` as OkLab lists,
  `tolerance1`/`tolerance2`) and `ColorAlignment` (`colorAlignment`:
  `automatic`, `red`, `blue` in ten-thousandths of magnification). Groups
  `colorFringes` and `colorAlignment`. A slot's Tolerance is left out while it
  is its color's starting Tolerance, so a listed color and a pick of the same
  value store the same bytes (R1b). `CommonFringeColor` is the list (Purple,
  Green); `FringeHueName` names a color by the nearest Color Mixer band.
- **Renderer** (`Edits/LensRenderer.swift`, `Kernels/LensKernels.swift`). The
  lens step runs on the decoded image before the crop: alignment (red and blue
  resampled about the image center by hand-written bilinear interpolation),
  then graying (`mix(c, Y, w)`, Y the Rec. 2020 luminance, so brightness is
  kept, R6 ruling). `w` = edge weight × the larger slot weight. Stitchable
  kernels compiled at run time, **each in a library of its own** (finding 1).
  Stacks without the groups never reach a kernel (`lens` returns its input
  object), and raws decode exactly as before unless alignment is on, which
  decodes the whole sensor so the center is the lens axis (R9).
- **Measuring** (`Edits/ColorAlignmentMeasurement.swift`): the master decoded
  whole at up to 2048 px; per channel, a coarse search in half-pixel corner
  steps then Gauss–Newton on the magnification that lines the channel up with
  the green over edge pixels, the green fitted per tile (gain and offset).
- **Picking** (`Edits/FringePicker.swift`): the pixel a click takes is the
  pixel the magnifier outlines, by one function for both
  (`FringePicker.pickedPixel`, ruling 18; the snap is gone): at the view's
  100% and closer the pixel under the pointer, zoomed out further the most
  colorful photo pixel under the pointer's device pixel. It samples the full-
  resolution decode (whole sensor for raws) aligned as the photo renders, before
  any graying, held while picking (OQ14, below); refused below OkLab chroma 0.025.
- **Pixel magnifier** (`Edits/PixelMagnifier.swift`,
  `Loupe/PixelMagnifierView.swift`, `Model/PixelMagnifierActions.swift`): the
  generic core knows nothing of fringes. A tool (`PixelMagnifierTool`) gives
  the image, the pick rule, a verdict and a note; `FringeMagnifierTool` is the
  fringe tool, and a test uses one of its own (AC29). The level is the
  `pixelMagnifier.level` preference on `LibraryModel`.
- **App**: `LensControls` (inspector), `LensText` (every string),
  `AdjustmentEditor` (picking state, the held pixels, the shared map slot
  with `mapKind`, measuring), `FringeMapActions` in `SharpeningMapActions.swift`, the loupe's
  pick path (`LoupeScrollView.onPick`, crosshair cursor rects, the ignored
  double-click), `changeAdjustmentsMeasuringAlignment` (paste and presets),
  `DebugLensCommands`.

## Decisions on the engineer's open questions

**OQ1, the edge rule.** A pixel is near a high-contrast edge when the
perceptual luminance (sRGB curve of the Rec. 2020 luminance) within a square
window of 24 full-resolution pixels around it spans 0.2 … 0.4 of the range
(smoothstep: none below 0.2, full above 0.4; a dark branch at 0.25 against
a sky at 0.85 spans 0.6). The result is softened by a Gaussian of a quarter
of the window, so the rule has no hard border. The window is scaled with the
render (`RenderContext.scale`, whole pixels, at least one), so every size
counts the same pixels (R13, AC10). 24 rather than 12: with 12, scene (a)
drawn six times larger (a rim whose brightness falls over 60 pixels) kept
its purple at the rim's middle (weight 0.07); with 24 it is 1.0. Rims softer
than about 60 pixels at full size are not fully caught: see RI-E1.

**OQ2, the image the picker samples.** The decoded master, aligned as the
photo renders, before every slot's graying and every other adjustment — the
image the fringe step itself works on — at full resolution. So the clicked
color is the one grayed, at any zoom (§14 point 1); later adjustments
(Saturation, relative white balance, tone, the mixer, grading, look-up
tables, masks) never change what matches (point 2); the slot's own graying
is never in it (point 4); neutral spots are refused (point 5). The swatch is
the stored color through the adjustments after the fringe step (point 3).
The exception is a raw's own decode settings (white balance, Profile's
look), which come before the step: DQ-1.

**OQ5, the listed colors and starting Tolerances** (derived in
`FringeToleranceDerivationTests`, which fails if a constant is changed by
hand). Scene (a) has two purples on its bars (bluer and redder), a purple
disc rim, and two greens (yellower and bluer). A listed color is the OkLab
color at the middle of its kind's hues, at their mean lightness and chroma:
Purple (0.684, 0.1255, −0.1287), Green (0.7917, −0.1264, 0.0662); they name
themselves Purple and Green. Its starting Tolerance is the smallest multiple
of 5 whose full-gray core (half the hue reach, reach = 6° + 0.84° ×
Tolerance) covers every fringe of its kind: Purple 25 (core 13.5° for a
spread of 12.2°), Green 20 (core 11.4° for 10.3°). A pick's starting
Tolerance is 55: a pick may land on either end of a kind, so its core must
cover the widest spread within one kind (24.4°). Neither reach touches the
scene's sky.

## Requirements and acceptance criteria

| Item | Check | State |
|---|---|---|
| R1, AC1 | `ColorFringesTests` "AC1": picks (through `FringePicker`'s rule) of scene (a)'s purple gray both bars' purples and the disc's rim, a second pick grays the greens, clearing either restores only it; debug script: `adjust fringe pick 1 0.1185 0.3` on the scene file picks, one undo step "Pick Fringe Color" | Done |
| R1 pixel rule and refusal (design §4, §20; ruling 18) | `ColorFringesTests` "The pixel rule": at 100% a click on a fringe pixel beside a stronger one takes that pixel, one pixel beside the fringe on the light ground is refused, at fit the most colorful under the device pixel; neutral refusals stay; debug script: a click on the light ground is refused ("That spot has almost no color…" caption, eyedropper stays on, no undo step) | Done |
| R1a, AC1a | `ColorFringesTests` "AC1a" (listed colors at their starting Tolerances gray every fringe); debug script: `menupick` on Color 1's and Color 2's ⋯ buttons fills them (the real pull-down path); `contextmenu fringe 1` lists Pick from Photo, the Common Fringe Colors header, Purple, Green, Clear (dimmed when empty); `buttons` names them "Pick Color 1", "Color 1 commands" with the design's help | Done (keyboard and VoiceOver by a person: M2) |
| R1b, AC1b | `ColorFringesTests` "AC1b": same stored parameters, render hash and pixels as a pick of the same value; Tolerance widens and narrows; `LensCommandTests`, `AdjustmentsTests` (presets and paste copy the group as any other); debug script: Clear and its undo, a pick replacing a listed color | Done |
| R1c | Derivation above; AC1a | Done |
| R2 | AC1; `LensRenderingTests` (the kernels against `LensReference`, luminance kept) | Done |
| R3, AC2 | `ColorFringesTests` "AC2": a fringe a known hue away untouched at 0 and gray when wider; the changed set never shrinks over 0 … 100; Color 1's Tolerance never changes Color 2's pixels | Done |
| R4, AC3 | `ColorFringesTests` "AC3": removed color falls from 1 to 0 with no step larger than smoothstep's slope allows | Done |
| R5, AC4 | `ColorFringesTests` "AC4" ×2: scene (b)'s patches keep their color where no edge is within reach while inside a range; the sky beside the ridge stays blue; every pixel outside every range matches the render without the feature | Done |
| R6 | Fringe Map: debug script `fringemap on` (badge, legend, caption, canvas value "Fringe map, 3 of 5", "Hide Fringe Map" action), Esc hides it; `LensRenderingTests` (the map is the removal's weight) | Done |
| R7, AC5 | `ColorAlignmentTests` "AC5" ×2: scene (c) at three pairs of magnifications measured to under 0.1 px at the corner; stored values applied identically at full and preview size; debug script: Align automatically on scene (c) measures 39.91 / −30.0 (truth 40 / −30) | Done |
| R8 | Values stored and never measured per render (AC5); `photocli develop` measures once | Done |
| R9, AC6 | `ColorAlignmentTests` "AC6": two crops agree on the overlap as the plain crops do; measuring ignores the crop; raws with alignment decode the whole sensor | Done |
| R10, AC7 | `ColorAlignmentTests` "AC7"; `LensRenderingTests` (channels against the reference); debug script: a Red/cyan move after measuring makes it hand-set ("Set by hand…"); unchecking zeroes both | Done |
| R11, AC8 | Full `swift test`: every golden and the edit-stack corpus unchanged; `ColorFringesTests` "R11" (the lens step returns its input; decode settings unchanged; groups off render as absent) | Done |
| R12, AC9 | `AdjustmentsTests` (reset of every section gives the identity hash), R11 test (group off keeps values), debug script: undo names "Pick Fringe Color", "Choose Fringe Color", "Clear Fringe Color", "Turn On Automatic Alignment", slider titles; undo restores; `adjust off colorAlignment` keeps the values | Done |
| R13, AC10 | `ColorFringesTests` "AC10": a fit render at scale ¼ and a full render disagree only within 8 master pixels of a boundary | Done |
| R14, AC11 | `LensCommandTests` "AC11"; `AdjustmentParameterTests` (every parameter described) | Done |
| R15, AC12 | `ColorFringesTests` "AC12" (DNG, JPEG, HEIC, TIFF of scene (a): under 20% of the fringes' chroma stays); videos: the Adjust tab shows "No Adjustments for Videos", unchanged | Done |
| R16, AC13 | `ColorAlignmentTests` "AC13" (two scalings measured to their own values; hand-set values copied); debug script: a grid paste measured each online photo (fringes.dng, fringes.tif, fringe-subjects.tif got their own values) | Done |
| R16a, AC13a | Debug script: grid paste of automatic alignment onto a selection with an offline original: its render hash stayed `6c76a50e…` (identity), Activity "1 photo was left unchanged: its original is offline.", one undo step "Paste Adjustments" | Done |
| R16a, unreadable originals (design §19 DQ-2) | Debug script: the same paste with two originals overwritten by junk: after the offline row, one warning row "Paste Adjustments": "2 photos were left unchanged: their originals could not be read." then one line per file; one undo step | Done |
| R16, AC13b (RI-E2) | `LensPresetTests` ×3: a stored preset with no group list, and a preset file with no `groups` key, clear the slots and alignment; a group list without the Lens groups keeps them. Debug script: an imported pre-feature file ("All settings") applied to a scene (a) photo with both slots and automatic alignment cleared them as one undo step, "Apply Preset Older", and one undo restored them | Done |
| R17, AC14 | `LensCommandTests` "AC14" | Done |
| R18, AC15 | `photobench edits`, below | Done |
| R19, AC16 | Debug script: arming shows it over the photo (`print magnifier`), none over the surround (`magnifier move 1.05 0.5`), filling from the list leaves it off, Esc, another photo, a crop session and review remove it | Done |
| R20, R21, AC17 | `PixelMagnifierTests` "AC17, AC22" (hard squares, each cell exactly its photo pixel, at every level and backing 1 and 2; `bitmap`); grid at 800% and 1600% only (`showsGrid`, `print magnifier`). The not-ready state (dashes, no pixels, a click waits and stores the same color) follows one path; at these sizes the pixels arrive before a script can read it, so it is listed for a person on a large raw | Done |
| R22, AC18 | `PixelMagnifierTests` "AC18" ×2 (outline = pick at 100%, 800% and fit); debug script: `magnifier move` then `adjust fringe pick` at the same point: outlined maskPoint 0.118381,0.300203 and `print fringe`'s last sample 0.1184,0.3002 | Done |
| R23–R25, AC19, AC20 | `PixelMagnifierTests` "AC19" (values against a CPU reference, CoreGraphics' Rec. 2020 to Display P3, within 1, on scenes (d) and (a)), "AC20" ×2, "AC19: Exposure, Saturation, a look-up table and the other slot leave the sampled pixels unchanged" (every pixel of scene (a) compared, each edit shown to change the render at the purple fringe; the filled other slot is R25's "before any graying"), "Color Alignment changes the sampled image"; debug script: Exposure leaves the values unchanged; a neutral reads R = G = B = L | Done |
| R26, AC21 | `PixelMagnifierTests` "AC21"; debug script: the light ground reads "Almost no color" and the click is refused | Done |
| R27, R28, AC22, AC23 | `PixelMagnifierTests` (cell size level ÷ 100 at backing 1 and 2, levels, no wrap); debug script: `magnifier level`, keys `=` and `-` (no wrap), inspector pop-up (`buttons`), `menuitems Pixel`, the checked context submenu; level 400 persisted across relaunch and another `--library-root` | Done |
| R29, AC24 | `PixelMagnifierTests` corners, crop and quarter turn; placement test (flips, no flicker, never clipped at all four corners); debug script: corner pixels stay in the window, drawn cells beyond the photo are none | Done |
| R30, AC25 | Editor reloads the held pixels when alignment or a decode setting changes, and the magnifier re-reads on every pan and zoom (`print magnifier` follows); `PixelMagnifierTests` "Color Alignment changes the sampled image" | Done |
| R31, AC26 | Not in the stack: no new parameter; goldens and corpus unchanged (full `swift test`); debug script: arming and level changes add no undo step (`print undo` names only the pick) | Done |
| R32, AC27 | Scriptable: the view's `hitTest` returns nil, and the debug script's `hit` over its drawing reaches the photo (`LoupeImageView`); design §4's input rows stay DR3's checks (an `open` launch for the real click, drag and double-click paths, which QA runs). The real click while the magnifier is clamped under the pointer is part of M3 (prd.md AC27) | Done |
| R33, AC28 | No accessibility element (`accessibility any` lists none), level from `-`/`=`, menu, pop-up and canvas actions; the first responder stayed `LoupeHostView` before and after arming (`print responder`); legibility by a person (M3) | Done (M3) |
| R34, AC29 | `PixelMagnifierTests` "AC29": a test tool's own image and rule | Done |
| R35, AC30 | Only the fringe slots arm it; `adjust mask add colorRange` leaves it off | Done |
| R36, AC31 | `photobench edits`, below; memory held is released when picking ends (`print magnifier` heldBytes 0) | Done |
| M1 | Real photos: for a person, later (not blocking) | Pending (owner) |
| M2 | VoiceOver with no pointer: for a person (QA lists it) | Pending (person) |

## Speed (R18, AC15)

`photobench edits --limit 3 --frames 20` on 6000 × 4000 synthetic files,
live frames at 2560 px, median (p50) ms; Apple M4 Pro, macOS 27.2,
2026-11-08, with the final edge window (24):

| | DNG | HEIC | JPEG |
|---|---|---|---|
| live next frame (exposure) | 64.9 | 24.5 | 23.8 |
| live saturation (the color slider) | 64.7 | 26.2 | 26.1 |
| live fringe tolerance (two slots) | 78.0 | 27.1 | 27.2 |
| live fringe map | 17.2 | 10.1 | 10.5 |
| live color alignment | 13.9 | 30.5 | 33.2 |

Fringe Tolerance runs within a few milliseconds of Saturation on HEIC and
JPEG and 13 ms slower on DNG; alignment on a raw decodes the whole sensor
once (its first frame, 89 ms at p95) and then drafts. Recorded in
`docs/PROFILING.md` ("Lens heading").

The first frame that needs the Lens kernels waited 2.2 s for them to compile
once after a build (seven libraries); the editor now compiles them in the
background when the first photo opens.

The pixel magnifier, `photobench edits` on the same files (AC31), median ms:

| | DNG | HEIC | JPEG |
|---|---|---|---|
| arming to first pixels | 142 | 33 | 48 |
| update per pointer move, 400% | 0.15 | 0.14 | 0.15 |
| update per pointer move, 100% (largest picture) | 3.6 | 3.5 | 3.6 |
| same, straightened crop (costliest cells) | 3.9 | 3.9 | 4.0 |
| memory held while picking | 183 MB | 183 MB | 183 MB |
| live saturation, magnifier held | 66.2 | 25.8 | 26.0 |
| live saturation (for comparison) | 66.3 | 25.3 | 25.6 |

Live frames don't get worse with the magnifier showing. The held pixels are
released when picking ends. Recorded in `docs/PROFILING.md` ("Lens heading").

## Findings

1. **Core Image ran one run-time compiled kernel for another of the same
   library.** With `fringeGray` and the fringe map's kernel in one Metal
   source, whichever ran first in a context was then run for the other (the
   map came back as the photo); renaming did not help, a library of its own
   did. The same risk applies to `StitchableKernels` (its two kernels have
   different signatures, and its tests pass). Every Lens kernel now has its
   own library; `LensRenderingTests` "never stand in for each other" guards
   it. Proposed for CLAUDE.md below.
2. **Concurrent renders through one float context gave zeros** in tests; the
   suite serializes its float-context renders. The app's `RenderEngine`
   already serializes per context.
3. **Core Image's half-float intermediates round toward zero** in places, so
   the reference is checked through a float context, and the app's
   half-float pipeline against a bound derived from its roundings.
4. **The alignment estimator reads softer channels as slightly smaller**
   (about 0.1 px at a 640 px corner after one interpolation). A photo whose
   red and blue are softer than its green may be measured a little low; M1
   will show whether it matters.
5. **Debug script and measuring commands.** A paste or preset that measures
   saves after the command's undo group closed, and `registerUndo` outside a
   group (the script turns `groupsByEvent` off) raised and crashed the
   release app later. `pasteadjust` and `preset apply` now wait for the
   measuring inside their group. The app itself is unaffected.
6. The synthetic DNG of scene (a) measures a small blue magnification
   (−4.47): its demosaic offsets channels, which the scene files show but
   real raw decoders do not.

**OQ14, holding the pixels while picking.** When a slot starts picking, the
editor renders the sampled image once, at full resolution, into memory as half
float (the working format): 183 MB for a 24 MP photo, on a Core Image context
of its own so it neither queues behind previews nor slows a live frame. Every
later read is a memory read, so the magnifier follows the pointer in about 0.2 ms.
It renders again only when something changes that image (R30: Color Alignment
or a decode setting, by the key `(source, decode settings, alignment)`). It
is released as soon as picking ends (R36). A click before it is ready
waits for it and applies the same rule, so the click and the outline can never
differ (R20, R22). Tiles or a lazy render per move would cost a raw decode per
new region. The conversions for R23 and R24 are checked against a CPU reference
(`PixelMagnifierTests`, CoreGraphics' conversion; L on the same curve).

## Design questions (ruled, design.md §19, 2026-11-08)

- **DQ-1, a raw's White Balance and Profile come before the fringe step:**
  option A, as built. The user guide's sentence is now the one §19 gives.
- **DQ-2, unreadable originals in a measuring paste or preset:** one warning
  row per command, titled with its undo name: the new plural line ("%lld
  photo(s) was/were left unchanged: its/their original(s) could not be
  read.", what VoiceOver hears), then the export's per-file line up to
  `ExportActivityReport.failureListLimit` and "And %lld more.". Posted once
  when measuring ends, nothing on Stop, after the offline row
  (`changeAdjustmentsMeasuringAlignment`, `unreadableDetail`). Built and
  checked (table above).
- **DQ-3, the Activity title while measuring:** confirmed as built. Apply
  Preset's job now has a toolbar title fitted with
  `ToolbarMetrics.statusLine` (the preset's name shortened in the middle);
  the popover keeps the full title. Not checked by the debug script: the
  script's `preset apply` waits for the measuring to end inside its undo
  group, so the job is never on screen when it prints. A person can see it
  by applying a preset with a long name and Align automatically to several
  photos.

## Requirements issues (ruled, prd.md revisions of 2026-11-08)

- **RI-E1, soft rims beyond the fixed edge rule:** accepted as built; M1 now
  checks soft bokeh rims. No change.
- **RI-E2, presets saved with every group:** option A, as built; new AC13b
  (tested above), and the user guide's Presets paragraph says that a preset
  with all settings, older ones included, replaces Color Fringes and Color
  Alignment, and that Manage Presets… can take them out.

## README

- New: the Lens heading (Color Fringes, Color Alignment) in the Adjust tab;
  Adjust ▸ Show / Hide Fringe Map.
- New command: `swift run -c release photobench scenes --output DIR [--size WxH]`
  writes the chromatic aberration test scenes as TIFFs and a DNG.
- `photocli develop` accepts `colorFringes.*` and `colorAlignment.*`
  (`colorAlignment.automatic=true` measures the original).

## Proposed CLAUDE.md changes (owner's part)

- Architecture, Edit stack: replace "Custom kernels are possible without a
  Metal build step: `RuntimeKernels` (a spike, not used by the renderer) …"
  with: "Custom kernels are stitchable Core Image kernels compiled from Metal
  source at run time (`Kernels/LensKernels.swift`; `StitchableKernels` is the
  spike), each in a Metal library of its own: Core Image ran one kernel of a
  library for another. `RuntimeKernels` stays a spike."
- Architecture, Edit stack: "`AdjustmentRenderer` renders in a fixed order"
  could add "the Lens heading's alignment and fringe removal first, on the
  decoded image before the crop".
- Debug script paragraph: "A command whose change is saved after an await
  (a measuring paste) must wait inside its undo group (`waitForBatchMeasuring`)."
- Commands: add `swift run -c release photobench scenes --output DIR`.

## Review round (PR #48)

Outcome of each finding in code-review.md and review.md, on the commit below.
"Unit" is a test that fails without the fix; "script" is a debug-script run on
a bundle copy against a scratch library.

| Finding | Outcome | How it was checked |
|---|---|---|
| C1 | A measuring paste or preset leaves out only versions whose originals failed. A stack this build can't read stays in the list, and the catalog skips and reports it (`BatchEdit.AlignmentMeasurements`). | Unit `LensReviewFixesTests`; script: paste over 8 photos with one stack at schema 99: 7 changed, that one untouched, Activity "1 photo was left unchanged" |
| C2 | A cancelled batch no longer clears the state of the run that replaced it (`BatchEdit.LatestRun`, in paste, presets and Auto). | Unit for the rule; the replacement race is app-only, by reading |
| C3 | The outline holds still inside the drag threshold and shows the press point, so it is the pixel a click takes. | App-only (`LoupeScrollView` has no test target); person check M3 |
| C4 | Refinement follows what is on screen, not the suspended map (`LoupeRefinement.wanted`). | Unit table |
| C5 | `PixelMagnifierTool` now carries the output mapping, the loupe uses only the protocol, and the matrix inverse moved to `Matrix3`. | Unit: AC29's tool through `reading(tool:atOutput:devicePixelsAcross:)`; `Matrix3` round trip |
| C6 | `colorAlignment.automatic=false` alone removes the correction. | Unit in `LensCommandTests` |
| C7 | Unchecking Align Automatically during a paste or preset measurement cancels that batch too. | App-only, by reading |
| C8 | **Stands.** The picture is 256 × 256 and the conversion happens on the main thread at commit either way; drawing into the window's color space would only move it, and would add a window dependency to the bitmap. Worst update measured is 4 ms. | Benchmark below |
| C9, F1 | The crosshair area follows zoom and scroll; `photoRect` is in the scroll view's document coordinates. | App-only; person check M3 |
| C10 | `photobench edits` now also times 100% and a straightened crop. | Speed table above |
| C11 | Help text corrected. | n/a |
| F2 | Esc cancels picking from anywhere in the window except a text field, by a key monitor that exists only while picking. | Script: first responder off the loupe, Esc posted through the app, picking ended |
| F3 | The grid covers only cells that hold a photo pixel (`Picture.gridLines`). | Unit at corners at 800% and 1600%; script snapshot at the top left corner at 1600%: no lines over the empty area, right way up |
| F4 | Switching to the Sharpening Map while the fringe map is suspended cancels picking. | Script: `fringemap on; fringearm 1; sharpenmap on`: picking none |
| F5 | The context menu has a real section header, and Purple and Green keep their swatches. | Script: `contextmenu at`: `[section]` header, `[image]` on both, single separators |
| DQ-4, DR22 | If the held pixels can't be made while picking waits for them, picking ends and the caption says why, once. | Script: file removed before arming: picking none, caption shown, magnifier gone, held 0 bytes, no undo step; restored and armed again: retried and ready; file removed after ready: magnifier keeps working |

RI-CR1 (Lens kernels fail to compile) is a known limitation per the ruling; the
`try?` paths in `LensRenderer.swift` are unchanged. The designer's optional
"keep the grid out of the outlined pixel" was not taken (not required).

## Latest run

2026-11-08, after the review round above: `swift build` clean, no warnings;
`swift test` **633 tests in 108 suites passed, 1 known issue** (the
pre-existing one in "Live render session"). No golden changed, no pipeline
version bump, `UPDATE_GOLDENS` never run. No new `Gus-*.ips` crash report from
these runs.
