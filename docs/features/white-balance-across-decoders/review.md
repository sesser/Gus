# White balance and baseline look across decoders: design review

Owner: apple-ui-designer. Date: 2026-11-14. Issue #170. Branch
`feature/libraw-color-pipeline` at `67b58b2`. Against `design.md` (§2 to §14,
ruling §17.1 added with this review) and the PRD's acceptance criteria.

Read: `Sources/PhotoApp/Views/AdjustView.swift` (`DevelopControls`:
`fallbackDecoderNote`, `whiteBalance`, `modePopUp`, `whiteBalanceCaption`,
`pick`), `Model/AdjustmentEditor.swift` (the load: `whiteBalanceControls`
set with `isRaw` and `rawDefaults` in one apply), `Model/FallbackDecoderText.swift`,
`PhotoCore/Edits/AutoAdjust.swift` (`WhiteBalanceControls`),
`Edits/Adjustments.swift` (`kelvinDisplayPreset`), the String Catalog,
`Model/DebugMachineLearningCommands.swift` (`print ml`),
`Tests/PhotoCoreTests/WhiteBalanceAcrossDecodersTests.swift`,
`docs/USER_GUIDE.md` 344 to 403, and `status.md`. Not built or run.

## Verdict

**Approved with one required fix.** The White Balance group is the system
raw's group on a LibRaw photo, control for control; the note, both captions
and the §5 display rule are as designed, and nothing names the decoder. The
one required change is the DQ-1 ruling (F1): Custom on a raw stores the
numbers it shows. Two small fixes (F2 spacing, F3 guide wording) can land in
the same commit.

## Design requirements

| # | Requirement | Result | Evidence |
|---|---|---|---|
| DR1 | LibRaw photo: nine modes, Kelvin Temperature, Tint −150 to 150; Tungsten 2,850 K / 0 | Pass | `.kelvin` → `Preset.allCases`, the same `AdjustSlider`s (`.kelvin`, `.reciprocal`, `temperatureRange`, `tintRange`) as a system raw; `.raw(.tungsten)`; AC1 script |
| DR2 | As-shot values shown unedited, believable; double-click resets to them | Pass in code; believability needs M2 | `defaultValue: asShot.kelvin` / `asShot.tint`, value `balance.temperature ?? asShot.kelvin`; as-shot from the header before layout (`LibRawDecoder.cameraColor`), the same function the decode uses |
| DR3 | Auto stores and shows Kelvin and tint | Pass; the wait needs M3 | `pick(.auto)` → `autoWhiteBalance()` while not unavailable; AC3 script stores 5332 / −12 |
| DR4 | §5 rule on both raws; Custom sticks; relative values show As Shot | **Fail until F1** (pass after F1, see Second pass) | `kelvinDisplayPreset` matches §5 exactly and serves both decoders; Custom does not stick on a photo with leftover relative values (DQ-1) |
| DR5 | Rendered images unchanged | Pass | `.relative` keeps `relativePresets`, −100 to 100 sliders, `relativeDisplayPreset` (D5) |
| DR6 | Note copy exactly §3; old key gone | Pass | Catalog key and `FallbackDecoderText.note` match §3 to the character; "shown without a profile" and "relative to the camera" no longer in `Sources/` |
| DR7 | W1 and W2 as drawn; no sliders; captions and help exact | Pass, one spacing fix (F2) | W1: one item, dimmed, help = caption, no triangle, no sliders. W2: `[As Shot, stored]`, enabled, triangle `accessibilityHidden`, help = caption; re-picking the stored mode returns nil; Auto and Custom refused for `.unavailable`. Both strings match §10 |
| DR8 | No decoder badge or wording naming the decoder | Pass | Nothing in the group, caption or loupe; "fallback" appears only in the debug script's output |
| DR9 | User guide terms match the UI | Pass, two wording fixes (F3) | **White Balance**, **Mode**, **As Shot**, **Temperature**, **Tint**, **Profile** used as in the UI |

Layout was set in one apply with the stack (`whiteBalanceControls`,
`isRaw`, `usesFallbackDecoder`), so no wrong group is drawn first (§6's
condition met; no Design question needed).

## Findings for the engineer

**F1. Custom on a raw stores the numbers it shows (required; DQ-1).**
Implement ruling `design.md` §17.1 in `WhiteBalanceControls.picking(.custom,
from:)` for `.kelvin(asShot:)`:

1. `preset = .custom`, starting from the stored value.
2. A nil `temperature` becomes `asShot.kelvin`; a nil `tint` becomes
   `asShot.tint`; stored values are kept.
3. The as-shot values unrounded, so each slider stays on its default.
4. `relativeTemperature` / `relativeTint` untouched (R10, RI-W1(a)).
5. One undo step "White Balance"; nothing recorded when the result equals
   the stored value.

`.relative` keeps storing `WhiteBalance(preset: .custom)`; `.unavailable`
keeps returning nil. Tests to change and add are listed in §17.1 (the
`leftover` expectation at `WhiteBalanceAcrossDecodersTests.swift:342-344`
becomes "shows Custom"). This applies to system raws too: a Custom picked
there now carries its as-shot numbers into a paste, which §17.1 accepts.
Update the comment on `picking` ("Custom stores Custom") and the script
check for AC10 in `status.md`.

**F2. Caption spacing (small).** `whiteBalanceCaption` adds `.padding(.top,
2)` inside a `VStack(spacing: 2)`, so the caption sits 4 pt under the pop-up;
§6 asks for 2 pt, as the machine learning caption has (which uses the stack
spacing alone). Remove the top padding so the two captions sit alike.

**F3. User guide wording (small), `docs/USER_GUIDE.md`.**
- Line 374 to 375: "a note stands in place of **Profile**". The **Profile**
  heading stays; the note replaces its pop-ups. Say "under **Profile**, a
  note stands in place of its pop-ups (the built-in profile can't be
  changed)".
- Line 379: "(**As Shot**, Auto, Daylight to Flash, Custom)" bolds one of
  four mode names. Bold all the named items the reader looks for, or none:
  "(**As Shot**, **Auto**, **Daylight** to **Flash**, **Custom**)".
- Optional after F1, line 392 to 394: "Mode shows **As Shot**, and you pick
  the white balance again" stays true; no change needed.

## Improvements (judgment, not required)

- `print ml` prints the caption from `WhiteBalanceText`, chosen by the same
  model call as the view, so it proves the state, not that the caption is
  drawn. The pop-up's tip is read from the real control, which is the
  stronger check; QA should rely on that plus M7 for the caption itself.
  SwiftUI text isn't an `NSView`, so I don't ask for more.
- After F1, consider a one-line note in the guide that Custom keeps the
  numbers shown and a paste carries them. Not needed for correctness.

## What's working (keep it)

- One display rule (`kelvinDisplayPreset`) for both decoders, display only,
  with the six §5 cases tested.
- The W2 pop-up offering exactly As Shot and the stored mode, with re-picking
  a no-op: the setting is visible and removable without pretending to work.
- Availability decided from the header before layout; the decode asks the
  same function, so the tab and the render can't disagree.
- No custom chrome: system pop-ups, the existing slider rows and the machine
  learning caption's style and triangle.

## Manual checks (for a person at the bundled app)

Scratch library: one X-E3 RAF (LibRaw), one X-T3 RAF (macOS), one JPEG; for
M7 the `photobench generate --dng-without-color` file. Inspector open, Adjust
tab, in the loupe.

- **M1. The note.** X-E3: under "Profile" the §3 text wraps cleanly at the
  inspector's narrowest width, with clear space before White Balance; no
  pop-ups under Profile.
- **M2. White Balance on the X-E3.** Nine modes. Unedited, Temperature shows
  a plausible Kelvin (near the X-T3's for a similar scene). Tungsten turns the
  photo clearly blue and shows 2,850 K, tint 0; Shade warms it.
  Double-clicking Temperature returns to the as-shot value.
- **M3. Auto on the X-E3.** The pop-up dims briefly, then shows Auto with a
  Kelvin and tint, and the photo looks neutral. Note whether the wait reads as
  "working" or as a hang.
- **M4. Paste both ways.** Daylight from the X-T3 onto the X-E3: Mode shows
  Daylight, the photo changes. 4,000 K from the X-E3 onto the X-T3: it changes.
  ⌘Z undoes each paste in one step.
- **M5. Switching photos.** X-T3 → X-E3 → JPEG → X-E3 with the arrows: the raws
  show the same group, only the JPEG shows three modes and −100 to 100, no
  value carries over, no visible jump while the X-E3 loads.
- **M6. A photo edited with a #161 build** (relative values on an X-E3): Mode
  shows As Shot, sliders at as-shot values, the photo as shot. Choose Custom:
  it stays Custom, Temperature and Tint keep the same numbers with no fill,
  the photo does not visibly change; ⌘Z returns to As Shot in one step. Repeat
  on the X-T3 with no earlier edit: the same. (After F1.)
- **M7. Unavailable state.** On the colorless DNG: the dimmed pop-up on As
  Shot, the caption under it starting at the pop-up's left edge, its wrap and
  legibility in the dark window with Increase Contrast on and off; hovering the
  pop-up shows the same text. Paste a Daylight onto it: the orange triangle
  caption and the two-item pop-up; choosing As Shot removes it and brings back
  the dimmed state; ⌘Z brings Daylight back.
- **M8. Live drag.** Drag Temperature on the X-E3 at fit and at 100%: the loupe
  follows the slider while it moves, not only on release.
- **M9. Caption spacing (after F2).** In M7's two states and beside a LibRaw
  photo's machine learning caption: both captions sit the same distance under
  their control.

## Second pass (2026-11-14): F1 to F3 confirmed

Read at `f94d5db`, `3aa74ce` and `2263fdd`: `PhotoCore/Edits/AutoAdjust.swift`
(`WhiteBalanceControls`), `CameraColor/CameraColorStep.swift` (`rendered`),
`PhotoApp/Views/AdjustView.swift` (`whiteBalanceCaption`),
`docs/USER_GUIDE.md` 344 to 408.

**Verdict: approved. No open findings.** DR4 now passes; every other row
stands.

| Finding | Result | Evidence |
|---|---|---|
| F1 | Fixed | `picking(.custom)` for `.kelvin(asShot:)`: `preset = .custom`, `temperature ?? asShot.kelvin`, `tint ?? asShot.tint`, unrounded, relative values untouched; `.relative` stores Custom beside the stored values; `.unavailable` and Auto return nil. Matches §17.1 steps 1 to 5 (step 5 relies on `change` skipping equal values, unchanged) |
| F2 | Fixed | `.padding(.top, 2)` removed: the caption sits at the stack's 2 pt, as the machine learning caption does |
| F3 | Fixed | "under **Profile**, a note stands in place of its pop-ups"; the mode names bolded alike; new sentences on Custom carrying its numbers and on the Kelvin reading differently between decoders are accurate and use the UI's terms |

**The as-shot clamp (asked by the coordinator): acceptable.** For a LibRaw
photo the as-shot Kelvin and tint go through `CameraColorStep.rendered`,
which clamps them to 2,000 to 50,000 K and ±150. As Shot still renders the
camera's own neutral. Custom, a slider move or a double-click reset then
renders the clamped number, so on such a photo the picture shifts the first
time White Balance is touched. That contradicts §17.1's "nothing visible"
only for light beyond the sliders' ends (candle light under 2,000 K, a tint
past ±150), and the alternatives are worse:
- storing an out-of-range value gives a slider that can't show its own
  number, or a range that differs per photo (HIG, Sliders: the range is a
  property of the control, not the photo);
- a separate "as shot" value the sliders can't reach hides what Custom
  stores.

Showing, storing and rendering one number keeps the pop-up, the sliders, the
render and a paste in agreement, which is the point of §17.1, and As Shot
remains the way back to the camera's own white. I record this as an
amendment to §17.1: on a LibRaw photo "as-shot" in step 2 means
`CameraColorStep.rendered(asShot)`.

The guide's wording is right in substance. Two optional polish points, not
blocking:
- Line 384 to 385 "choosing **Custom** or moving a slider then renders that
  number": "renders" is engineer's language. Suggest "…then changes the photo
  to that end's color; **As Shot** brings back the camera's own."
- The clamp sentence now sits before "Two things to know about the numbers",
  so the paragraph reads as three. Move it after the second thing (the
  daylight-only color data), or drop "Two".

### Manual checks after the second pass

M6 and M9 now apply as written (F1 and F2 are in). One check added:

- **M10. Light beyond the sliders' ends** (only if such a file is at hand:
  a LibRaw raw shot under candle light or similar, below 2,000 K). Unedited,
  Temperature reads 2,000 K and the photo looks as the camera saw it. Choose
  Custom: the photo shifts to 2,000 K once and stays; choose As Shot: the
  camera's look returns. The shift should read as the slider's limit, not as
  a fault. Skip if no such file exists; the unit tests cover the numbers.

## Summary for the issue

Design review, second pass: **approved, no open findings.** F1 (Custom on a
raw stores the Kelvin and tint shown, §17.1), F2 (caption spacing) and F3
(user guide wording) are confirmed in code and docs. The clamp of a LibRaw
photo's as-shot values to the sliders' ranges is accepted: As Shot keeps the
camera's white, and Custom or a slider renders the number shown (recorded as
an amendment to §17.1). Two optional guide polish points. Manual checks M1 to
M10 for the owner (M10 only if a file shot below 2,000 K is at hand).
Full review: docs/features/white-balance-across-decoders/review.md

## Summary for the issue (first pass)

Design review: **approved with one required fix.** The LibRaw photo's White
Balance group is the system raw's (nine modes, Kelvin, Tint); the Profile note,
the unavailable and not-applied captions and the As Shot rule for leftover
relative values match the design; nothing names the decoder.
- F1 (required, DQ-1 ruled): choosing Custom on any raw stores the Kelvin and
  tint it shows (as-shot when unset, unrounded), so Custom sticks; ruling in
  design.md §17.1.
- F2: caption 2 pt under the Mode pop-up, as the machine learning caption.
- F3: two user guide wording fixes.
Manual checks M1 to M9 for the owner (M6 updated for the ruling).
Full review: docs/features/white-balance-across-decoders/review.md
