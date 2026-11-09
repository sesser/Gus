# Sharp live frames at 100%: design

Owner: apple-ui-designer. Date: 2026-11-09. Status: Designed. Nothing is open.

**Inputs.** [`prd.md`](prd.md) (Approved), cited as R1–R14, A1–A9 and D1–D3.
Precedents: [`../sharpen-mask-preview/design.md`](../sharpen-mask-preview/design.md)
("SMP": §4 the hint, §5 the caption spinner, §8) and
[`../ml-denoise/design.md`](../ml-denoise/design.md) ("MLD": §6 the wait, §8,
§15 DQ-3). Code read at `a6b69b0`, nothing seen on screen: `LoupeView.swift`
(zoom, `LoupeImageView`, `LoupeCaption.spinnerLabel`), `AdjustmentEditor.swift`
(map refinement, machine learning wait), `SharpeningMapActions.swift`,
`EffectsControls.swift`, `LensText.swift`, `InspectorView.swift`,
`CurveEditor.swift`, `ScrollZoom.swift`, `LibraryToolbar.swift`,
`LibraryCommands.swift`, the String Catalog and `docs/USER_GUIDE.md`. HIG pages
read 2026-11-09 (markdown versions): Progress indicators, Motion, Writing.

**In short.** No new control, component, color, shortcut or menu item. Two
hints are reworded, the guide gets one paragraph, the existing caption spinner
gets one more condition, and a frame that isn't the photo's own pixels stops
being drawn as if it were. Nothing here comes from another application.

## 1. Hints and wording (D1, A6)

| Hint | Today | Final text |
|---|---|---|
| Sharpening (`SharpeningMapText.hint`, under the Sharpening Map toggle while the map is hidden) | Judge Amount, Radius and Detail at 100% (Z) once the change is saved. Sharpening Map shows Masking's effect at any zoom. | **Judge Amount, Radius and Detail at 100% (Z). Sharpening Map shows Masking's effect at any zoom.** |
| Grain (`EffectsControls`, while Strength is 0) | Raise Strength to add grain. Grain is easiest to judge at 1:1 (Z). | **Raise Strength to add grain. Grain is easiest to judge at 100% (Z).** |

- **Reworded, not removed.** Below 100% sharpening still doesn't look as it
  does at full size (PRD non-goal, `sharpen-masking-scale`), so "at 100%" is
  still the advice. "(Z)" is the exact way to the zoom where the new behavior
  holds (§4). The second sentence stays true (A4).
- **The clause is cut, not replaced with "as you drag".** It warned about a
  surprise that no longer exists. A sentence saying the app does what people
  expect earns no space (HIG Writing: "Check each word to be sure it needs to
  be there").
- **"100%", not "1:1".** The View menu says Zoom to 100% and the toolbar says
  100%. "1:1" is also a crop ratio in this app (`CropSession`), so it is one
  term with two meanings (HIG Writing, "Build language patterns"; same call as
  SMP §4).
- **Nothing else makes the claim.** I searched the Swift source, the String
  Catalog and the guide: no other hint says to judge after a save, and no other
  string uses "1:1" for zoom. The guide's "once you pause" lines are about the
  maps (unchanged, A4), and its machine learning spinner passage stays true.

**`docs/USER_GUIDE.md`.** It says nothing today about editing at 100%, so it
needs an addition, not a correction. Two changes:

1. Add this paragraph before **Sharpening Map**. The engineer may adjust it. At
   review I check the terms: never "sharp frame", "live frame", "draft" or
   "viewport".

   > **Editing at 100%**: at 100% and closer (`Z`, or **View ▸ Zoom to 100%**),
   > the loupe shows the photo's own pixels while you change a value, so you
   > can judge fine detail without letting go. A heavy edit updates less often
   > but keeps its detail. When you start a change, pan or zoom, part of the
   > photo can look soft for a moment. On raw files, White Balance, Profile and
   > Noise Reduction stay soft while the value moves, and the detail arrives
   > once you hold still, even with the control still held. If that takes more
   > than half a second, a small spinner shows in the caption. The histogram
   > always describes the whole photo, and at these zooms it can lag until you
   > pause.

2. In the keys table, change "100 %" to "100%" (the `Z, click` row).

## 2. Marking a soft frame (D2)

**Ruling.** No badge, tint, overlay or announcement marks a soft frame. The
only mark is the existing caption spinner, and only once the person has
stopped and is waiting.

- **No mark while input moves.** The person is watching the photo under their
  hand, and the state changes within a frame or two. Caption badges are for
  states that last (Original, HDR, Offline, Not Applied); one here would flash
  at the start of every drag. SMP §5 has the same rule for the map's estimate.
- **A spinner once they've stopped.** At 100%, a soft picture with nothing
  happening looks like a result. A person can take it for their photo's focus,
  or for Luminance smearing detail, which is the misjudgment this feature
  exists to remove. In this app the spinner already means that the picture on
  screen is not yet the result asked for (MLD §15 DQ-3). The PRD expected no
  new UI, and this adds no component and no string, only a condition.

| Moment | The photo | Caption spinner |
|---|---|---|
| A control outside R4 and R5 moves (R1) | Perhaps a soft first moment (R6), then sharp frames | None |
| A heavy edit moves (R2) | The last sharp frame until the next one lands | None |
| White Balance, Profile or classical Noise Reduction moves (R4) | Soft frames following the hand, drawn per §2.2 | None |
| Same control, input paused, still held (R4) | The soft frame stays, then the sharp frame replaces it in place | §2.1 |
| A pan, a zoom, just after letting go (R6) | The part not ready is soft, never empty, then sharp | §2.1 |
| A machine learning wait (R5) | The last frame stays until the sharp frame replaces it | Unchanged (MLD §6): 0.5 s after the wait began, also during a drag, with its own label. Those frames take over a second, so the wait starts at the change; classical frames keep up with the hand |

### 2.1 The spinner rule

At a covered zoom, the caption shows the spinner when all three hold:

1. Input has stopped for about 0.5 s: a value, a hover, Show Original, the
   overlay, a pan or a zoom. This is the map's timing (SMP §5).
2. The picture on screen is not yet a sharp frame of what was asked for. A
   sharp frame a value behind counts as not yet.
3. One is on its way.

It goes when the sharp frame is on screen, when input resumes, or when the wait
ends some other way (another photo, a failed render).

- **Same slot and look.** The caption's existing slot and mini `ProgressView`,
  with no visible label (HIG Progress indicators: "Display a progress indicator
  in a consistent location", "Avoid labeling a spinning progress indicator").
- **Tooltip and VoiceOver label:** the existing **Refining the photo**. Never a
  word built on "sharpen", which names an adjustment in the same tab.
- **One spinner.** This condition comes last in `spinnerLabel`, so the maps and
  machine learning keep their labels.
- **Where it doesn't apply.** Arriving at a photo at 100%, and `Z` from fit with
  no change under way, load as today with no spinner: they aren't live frames,
  and arriving at a photo is the culling path. An offline master has nothing on
  its way. If the engineer's approach leaves an area soft on a pan after the
  photo has settled, the same rule covers it.

### 2.2 A soft frame must look soft

`LoupeImageView` switches to nearest-neighbor enlargement at magnification 1
and above. As the code stands, a 2560 px frame at 100% is drawn as blocks about
2.3 pixels wide, not softly (read from the code, not seen on screen).
Stair-stepped edges look like detail, and on a sharpening slider they look like
oversharpening.

**Requirement.** Anything less than the photo's own pixels (a soft live frame,
or the cached preview shown while a full render loads) is enlarged smoothly at
every zoom. Nearest-neighbor is only for real pixels above 100%, so blocks on
screen always mean real pixels. The ruling above depends on this: with no
badge, the look of the frame is the cue. The maps stay as shipped (A4).

### 2.3 VoiceOver

Nothing is announced and the canvas value doesn't change. A soft frame changes
nothing a VoiceOver user acts on, and the slider speaks its own value as today
(SMP §8, MLD §8). The spinner has its label for anyone who lands on it.

## 3. The swap from soft to sharp (D3)

**Ruling.** No treatment. The frame replaces the last one in place with no
transition, in both directions (soft to sharp, and sharp to soft when R4 input
resumes), in every mode. So Reduce Motion needs no separate path. The spinner
stays under Reduce Motion: it is a progress indicator, not decoration (MLD §8).

- A crossfade shows a double exposure of two renders, at the zoom and on the
  edges the person is judging.
- It happens on every gesture (HIG Motion: "In apps, generally avoid adding
  motion to UI interactions that occur frequently"), and it would delay the
  frame R7 works to deliver.
- Every frame in the loupe already swaps this way (SMP §5, MLD §6).

Two requirements follow:

- **No implicit animation on anything that draws a frame.** `CALayer.contents`
  crossfades by default. `LoupeImageView` turns that off; any new layer must
  too.
- **The swap changes detail, never position.** Soft and sharp frames line up to
  the pixel. If the sharp image arrives in parts, each part swaps the same way,
  with no feathered edge (R6 accepts the seam for a moment).

## 4. Other consequences

- **Histogram (R9, ruling 6).** The inspector histogram and the curve's
  backdrop read the same value, so both hold during a drag at covered zooms and
  catch up on a pause. The last state stays: never blanked, dimmed or marked. A
  lag alone doesn't start the spinner, which is about the picture. At fit both
  stay live as today.
- **The step at 100% (accepted).** Nothing to design, but "covered" must agree
  with the toolbar:
  - The 100% segment is selected within 1% of 100%
    (`LoupeZoomState.isActualSize`), so a pinch ending at 99.5% shows "100%" and
    gets sharp frames (the PRD's term is "displayed zoom").
  - A photo small enough that Fit is already 100% is covered ("however it was
    reached"), even though the toolbar says Fit.
  - There is no zoom readout and a pinch doesn't stop at 100%, so a pinch ending
    at 97% is soft with neither segment selected. `Z` and the toolbar land
    exactly, which is one reason the hint keeps "(Z)". If DR6 shows this is a
    trap, stopping a pinch at 100% is a separate change.
- **Everything else: nothing to design.** No layout change, no new color,
  nothing on the glass layer. Increase Contrast, Reduce Transparency and
  keyboard paths are unaffected.

## 5. Strings and notes for the engineer

- **No new keys.** Two keys are replaced in
  `Sources/PhotoUI/Resources/Localizable.xcstrings` (§1 text; old keys removed;
  the Sharpening hint's comment stays).
- **"Refining the photo" gets a wider comment:** "Caption spinner while the
  loupe waits for the photo's full detail: replacing a pick zoomed in, or after
  a change, pan or zoom at 100% and above."
- **Debug script.** `print` should report the new spinner state, as the map's
  and machine learning's are reported.

## 6. Checks for the designer review

| # | Check | How |
|---|---|---|
| DR1 | Both hints read as §1, the old keys are gone, the comment is updated | `swift test --filter LocalizationTests`; reading |
| DR2 | §2.2: at 100% and 400%, a White Balance drag and the moment after a pan are smooth, with no blocks. At 400% a sharp frame shows real pixels as blocks | Manual on a 24 MP raw; `snapshot` if the script can hold a soft frame |
| DR3 | §2.1: no spinner during any drag of Amount or White Balance. With White Balance held still, it shows only if the frame takes more than 0.5 s after the last input, and goes when the frame lands or movement resumes. Label "Refining the photo" | Manual on a 24 MP raw; `print` |
| DR4 | R5: one spinner with the machine learning label, the last frame stays, the window responds | Manual on macOS 27 |
| DR5 | §3: no fade and no shift, soft to sharp and back, with Reduce Motion on and off | Manual at 100% |
| DR6 | §4: real pixels at 100% by `Z`, by the toolbar, by ⌘=, and by a pinch that selects the 100% segment. Soft just below. Whether landing just below by pinch is a trap | Manual |
| DR7 | §4: during a drag at 100%, the histogram and curve backdrop hold, never blank or dim, and catch up on a pause. A pan leaves them alone. At fit they stay live | Manual; `print` |
| DR8 | §2.3: nothing announced at the swap, the slider speaks its value, the spinner reads its label, the canvas value is unchanged | Manual; `accessibility image` |
| DR9 | The guide has the paragraph, "100%" in the keys table, and none of the internal terms in §1 | Reading |

## 7. Requirements issues

None. If E3 finds R4 can't reach a sharp frame at acceptable cost, the R4 rows
in §2 change with that ruling.
