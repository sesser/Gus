# Chromatic aberration and color fringe removal: implementation status

Owner: swift-macos-engineer. Implements [`prd.md`](prd.md) (Approved, owner
2026-11-07, rulings 1–15, R1a–R1c) against [`design.md`](design.md)
(Designed). Branch `feature/chromatic-aberration`, which carries the
stitchable-kernels spike (`1b537e0`).

**Status: Done.** Every requirement and acceptance criterion is built and
has a test or a debug-script check below; M1 and M2 are the manual checks
the PRD names. Design questions DQ-1 to DQ-3 and requirements issue RI-E1
are open for their owners; none blocks a criterion (each describes what is
built meanwhile). Next: code-reviewer and the designer review, then qa-tester.

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
- **Picking** (`Edits/FringePicker.swift`): from the full-resolution decode
  (whole sensor for raws) aligned as the photo renders, before any graying;
  the most colorful pixel within 3 screen points (converted at the loupe's
  zoom); refused below OkLab chroma 0.025.
- **App**: `LensControls` (inspector), `LensText` (every string),
  `AdjustmentEditor` (picking state, the shared map slot with `mapKind`,
  measuring), `FringeMapActions` in `SharpeningMapActions.swift`, the loupe's
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
| R1, AC1 | `ColorFringesTests` "AC1": picks (through `FringePicker`'s snap) of scene (a)'s purple gray both bars' purples and the disc's rim, a second pick grays the greens, clearing either restores only it; debug script: `adjust fringe pick 1 0.1185 0.3` on the scene file picks, one undo step "Pick Fringe Color" | Done |
| R1 snap and refusal (design §4) | `ColorFringesTests` "A click within 2 pixels…"; debug script: a click on the light ground is refused ("That spot has almost no color…" caption, eyedropper stays on, no undo step) | Done |
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
| R17, AC14 | `LensCommandTests` "AC14" | Done |
| R18, AC15 | `photobench edits`, below | Done |
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

## Design questions

**DQ-1 (§14 OQ2 point 2): a raw's own white balance comes before the fringe
step.** For raws the decoder applies white balance (and Profile's look);
the fringe step can only follow it. A large white balance change shifts a
fringe's hue, and a pick can then stop matching. Every later adjustment is
held as §14 asks.
- A: accept; the user guide says to pick again after a large change to a
  raw's white balance. **Built.** No cost.
- B: compensate: estimate the decoder's per-channel change between the
  white balance at pick time and now (von Kries) and move the stored color
  with it. Store the pick's white balance with the slot. Approximate; a few
  days with tests; a mismatch there would silently move the range.
- C: sample and gray on a second decode at as-shot white balance. Doubles
  the decode cost of every render with fringes; ruled out by R18.
Recommendation: A, revisited after M1.

**DQ-2 (§10): unreadable originals in a measuring paste or preset.** R16a
leaves them unchanged and says so; §10 gives the offline string only. Built:
one Activity warning per photo with the export's existing "‹name›: the
original could not be read.", and in the loupe "This photo could not be
measured." Options: keep it, or a summary string like the offline one
("‹N› photos were left unchanged: their originals can't be read.", new).
Recommendation: the summary string, for parity with offline.

**DQ-3 (§10): Activity's title while a paste or preset measures.** Built:
the command's own title ("Paste Adjustments", "Apply Preset ‹name›") with the
existing "‹n› of ‹m›" detail, and Stop. Confirm, or name a title.

## Requirements issues

**RI-E1: soft rims beyond the fixed rule.** The fixed edge rule (OQ1)
catches rims whose brightness falls over up to about 60 full-size pixels.
Very defocused highlights can be softer. PRD OQ1 already makes an adjustable
rule a follow-up after M1; noting it so M1 checks soft bokeh specifically.

**RI-E2: presets saved with every group now include the Lens groups.** A
preset that stored "every group" (no group list) reads as all groups, which
now includes Color Fringes and Color Alignment at their defaults, so applying
an older such preset clears a photo's fringe slots and alignment. Options: A
accept (every group means every group; built); B record the groups a preset
had when saved before this feature (a migration of the `groups` column).
Recommendation: A.

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

## Latest run

Filled at the end of the work.
