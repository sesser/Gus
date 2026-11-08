# Chromatic aberration and color fringe removal: design

Owner: apple-ui-designer. Date: 2026-11-07. Status: Designed. The product
manager ruled both requirements issues on 2026-11-07 (§17), each as the
option this design applied. One owner question (§18) is open and changes
nothing here unless the owner widens the scope.

**Inputs.**

- Requirements: [`prd.md`](prd.md) (Approved, owner rulings 1–14,
  2026-11-07), cited as R1–R18 and AC1–AC15. This document answers its OQ3,
  gives the user's side of OQ1 (§14) and states only what the person must see
  for OQ2 (§14).
- Earlier design records: [`../ui-redesign/design.md`](../ui-redesign/design.md)
  (P1–P5, N1, N7, N10, I7, I15, the §4 command map),
  [`../sharpen-mask-preview/design.md`](../sharpen-mask-preview/design.md)
  (the sharpening map: §2–§11, D-Q1, D-Q2), cited as "SMP §n", and
  `docs/UI_REDESIGN.md` (UIR §1 caption, §4 inspector, §6 menus, §10
  accessibility).
- Code read on `feature/chromatic-aberration`: `Views/AdjustView.swift`
  (sections, `DetailControls`, the Sharpening Map toggle and its caption,
  `machineLearningRow`), `Views/AdjustControls.swift` (`AdjustSection`,
  `GroupLabel`, `GroupToggle`, `SliderRow`, `AppKitCheckbox`, `AdjustText`),
  `Views/AppKitButton.swift` (`.toggle` with a symbol only),
  `Views/MasksSection.swift` (Pick Colors / Done Picking, Tolerance,
  `ShapeButtons`), `Loupe/LoupeView.swift` (`LoupeController` keys, click to
  zoom, double-click to the grid, drag to pan, accessibility, `LoupeCaption`),
  `Loupe/MaskOverlayView.swift` (color sampling and brush hit testing),
  `Model/AdjustmentEditor.swift` (sharpening map state, `measure`,
  `isMeasuring`, previews, `finishSession`), `Model/BatchActions.swift`
  (batch Auto Exposure with progress and Stop), `Model/DebugScript.swift`,
  `Model/DebugAdjustCommands.swift`.
- HIG pages read on 2026-11-07 (markdown versions): Pointing devices (macOS
  pointers, custom pointers), Color wells. The Keyboards, Menus, Progress
  indicators and Accessibility readings in SMP (2026-11-05) are relied on
  where cited.

**Clean-room note.** Nothing here comes from another editor. I avoided the
names other photo apps use for this (their panel names, their "defringe"
and "remove chromatic aberration" wording, and hue/amount slider pairs).
The words below are this app's own and say what the person does: pick a
color, widen its tolerance, align the colors. The interaction (one-shot
eyedroppers per slot, the map) follows this app's existing Pick Colors and
Sharpening Map patterns.

## 1. Names and terms

| Term (title-style where it labels a control) | Meaning | Why this word |
|---|---|---|
| **Lens** (heading) | The new Adjust tab heading for corrections of what the lens did. Distortion and lens vignetting (roadmap lens-corrections) join it later | Short, plain, our own. "Optics" is vaguer; a longer phrase would echo another app's panel name |
| **Color Fringes** (group) | Fringe halos (PRD): picked colors turned gray near high-contrast edges (R1–R6) | What the person sees and calls them |
| **Color Alignment** (group) | Lateral color edges (PRD): the red and blue parts of the image lined up with the green (R7–R10) | Says what the correction does. "Lateral chromatic aberration" is jargon; "color edges" would sit too close to "Color Fringes" |
| **Color 1**, **Color 2** | The two pick slots (R1, ruling 3) | Neutral, stable slot names; a slot is not "the purple one", since either can hold any color |
| **Tolerance** | How far from the picked color the graying reaches (R3) | The app already uses Tolerance for exactly this in a color range mask (P5: one term per thing). "Range" would collide with the Color Range mask shape, where a range is the set of colors and Tolerance is its width |
| **Fringe Map** / fringe map | The view of where fringe color is removed (R6) | Parallels Sharpening Map, a view the person already knows. Not "mask" (SMP §1: "mask" means a local adjustment here) |
| **Align automatically** (check box) | R7's one control | A check box, because it is a persistent setting that paste and presets carry and re-measure, not a one-shot command like Light's Auto (§7) |
| **Red/cyan**, **Blue/yellow** (row labels) | R10's hand settings | The colors of the outlines the person sees. Row labels are sentence-style (P5) |

In sentences, VoiceOver and the user guide: "color fringes", "color
alignment", "fringe map", "tolerance" in lowercase as common nouns (P5).

## 2. Where it lives (OQ3: which group, which heading)

**A new heading, Lens, between Details and Masks,** holding two groups,
Color Fringes then Color Alignment.

```
Presets · Crop & Straighten · Light · Tone Curve · Color Mixer ·
Color Grading · Details · Lens (new) · Masks · Effects
```

Why here:

1. **It sits with Details.** Fringes, like sharpening and noise, are
   judged at 100% on fine detail. People who just set sharpening at 100%
   find fringes next. The Adjust tab is in workflow order, not render
   order (`AdjustView`), so the renderer's order is the engineer's call.
2. **Not inside Details.** Details already holds two groups with a map
   toggle, a check box and a caption. Adding two more groups would make it
   the longest heading by far, and Lens has a future (lens-corrections).
3. **Not above Light.** Putting it first would push every heading people use
   on every photo down a screen, for a correction many photos never need.

**Two groups, not one** (assumption, not a requirements issue). R12 says
the feature "belongs to a group with the group on/off control". Each part
belongs to one: Color Fringes and Color Alignment are separate
`Adjustments.Group`s in the `.lens` section. That gives each its own check
box (compare fringes alone, R12 "before/after"), its own place in a preset's
group list ("presets that apply only some groups"), and the heading's check
box goes mixed when only one is on, as today. If the product manager reads
R12 as one group, only this paragraph and the preset group list change.

Expanded by default, remembered like every heading (`adjust.section.lens`).
The heading's reset resets both groups ("Reset Lens"); its context menu has
Turn Off / On, Reset, Collapse All, Expand All, as every heading.

## 3. Inspector layout

```
Lens                                               [✓] ⟲
Color Fringes                                      [✓]
Color 1     ● Purple                         [⌖] [⊗]      ← slot row
Tolerance   ──────●──────────────────    [  40 ]           ← only when Color 1 is set
Color 2       None                           [⌖]          ← slot row, empty
[ Fringe Map ]                                             ← toggle, 6 pt above
Raise Tolerance to include colors further from the picked  ← caption, 4 pt above
one. Colors away from high-contrast edges keep theirs.
Color Alignment                                    [✓]
[✓] Align automatically   ◌                               ← check box, spinner while measuring
    Measured on this photo. Paste and presets measure      ← caption at the check box's title inset
    each photo again.
Red/cyan    ─────●─────────────────      [ +12 ]
Blue/yellow ─────●─────────────────      [  −4 ]
```

`⌖` is the eyedropper toggle, `⊗` the clear button, `●` the swatch.

### Slot rows (Color 1, Color 2)

Both rows are always shown, in this order, so the second pick is
discoverable (scenario "Two kinds of fringe") and nothing moves when a pick
is made or cleared.

| Part | Spec | Basis |
|---|---|---|
| Label | "Color 1" / "Color 2" in the 80 pt label column, 11 pt secondary, like a slider's label | UIR §4 row grid |
| Swatch | SF Symbol `circle.fill`, tinted with the picked color as it looks in the photo now (§14, OQ2), the size of the Color Mixer's band swatches. Not drawn when the slot is empty | Same pattern as the Color Mixer swatches (`ColorMixerControls`); no custom view |
| Name | The picked color's hue name, 13 pt label color: Red, Orange, Yellow, Green, Aqua, Blue, Purple or Magenta (the Color Mixer's eight bands, singular). Empty slot: "None", secondary | Color is never the only signal (HIG Accessibility). The swatch alone can't be told apart by everyone, and VoiceOver needs a word |
| Eyedropper | `AppKitButton(symbol: "eyedropper", style: .toggle(isOn:))`: the accessory-bar push-on/push-off bezel shows when this slot is picking, as Original and Sharpening Map do. Trailing, before the clear slot | I15 (toggles share one look); the bezel, not a tint, shows the state, so it isn't color alone |
| Clear | `AppKitButton(symbol: "xmark.circle", style: .borderless, tint: .secondaryLabelColor)`, trailing. Shown only when the slot holds a pick; its 20 pt slot stays when empty so the eyedropper never moves | The clear symbol people know from search fields. Mask rows use `minus.circle` for "remove a part", which is a different act |
| Row height | `SliderRow.height` (22 pt); buttons at least 20 pt (UIR §10) | |

No click target on the swatch or name: picking is the eyedropper's job
(one way to do one thing). The row's context menu offers **Pick Again**
(arms the eyedropper) and **Clear** when the slot holds a pick, as a second
path (P2).

### Tolerance rows

A standard `AdjustSlider` under each slot that holds a pick, labeled
"Tolerance", 0–100, `.plain` format. Double-click and the row's context
menu reset it, as every slider. Its default (also the value a new pick
starts with) is the engineer's to set from the reference so that a typical
pick on scene (a) grays the fringe completely on the first click. A value
that needs the person to reach for the slider before anything happens
would make the first pick look broken. Hidden for an empty slot: a
tolerance without a color means nothing.

### Fringe Map toggle and caption

The toggle is a titled `AppKitButton(.toggle)` "Fringe Map", leading,
6 pt under the last slot row (as Sharpening Map sits under Masking). The
caption under it (11 pt secondary, wraps) has one role at a time, in this
priority:

| State | Caption |
|---|---|
| A slot is picking, and that slot was empty | "Click a colored fringe in the photo to pick Color 1. Press Esc to cancel." |
| A slot is picking, and that slot holds a pick (replacing) | "Color 1's effect is hidden while you pick. Click a colored fringe, or press Esc to cancel." |
| The last click landed on a spot with almost no color (§4) | "That spot has almost no color. Click a colored fringe, or press Esc to cancel." |
| Fringe map shown | The legend (§6) |
| No pick | "Pick a fringe's color in the photo to turn it gray where it lines a high-contrast edge. Thin fringes are easiest to pick at 100% (Z)." |
| At least one pick | "Raise Tolerance to include colors further from the picked one. Colors away from high-contrast edges keep theirs." |

The last line answers the first worry people have with a color tool
("will it gray my purple flower?") in the place they look.

### Color Alignment rows

| Part | Spec |
|---|---|
| Check box | `AppKitCheckbox` titled "Align automatically", sentence-style (P5), at `SliderRow.height`, as "Use machine learning" is built (`machineLearningRow`) |
| Spinner | A mini `ProgressView` right after the check box's title while measuring, with no visible label, a tooltip and VoiceOver label "Measuring color alignment" (HIG Progress indicators, as SMP §5) |
| Caption | 11 pt secondary, wraps, at `InspectorMetrics.checkBoxTitleInset` so it reads as the check box's note. Text by state (§7) |
| Sliders | "Red/cyan" and "Blue/yellow", `AdjustSlider`, signed, default 0 (no shift). The engineer picks the unit and range so that one arrow-key step is a small but visible change in a corner at 100%. Always shown: they show what automatic measured (R10 "fine-tune") |

## 4. Picking a fringe color (OQ3, R1)

### The gesture

1. The person clicks a slot's **eyedropper**. It turns on (bezel), and
   any other picking or painting tool turns off: the other slot's
   eyedropper, a color range mask's Pick Colors, and Paint.
2. Over the photo the pointer becomes the system **crosshair**
   (`NSCursor.crosshair`). Over the surround it stays the arrow.
3. **One click on the photo picks.** The color is stored in that slot as
   one undo step ("Pick Fringe Color"), the eyedropper turns off, and the
   pointer goes back to the arrow. The loupe then shows the result.
4. Picking again for the same slot (eyedropper or Pick Again) **replaces**
   it, as one undo step. **Clear** empties the slot as one undo step
   ("Clear Fringe Color"); its Tolerance row goes away and the fringe it
   grayed comes back. The other slot is never touched (R1, AC1).

**Why one click and done (not a mode that stays on).** A slot holds one
color, so a second click could only replace the first, and in the loupe a
click normally zooms: a mode left on would turn the next "click to zoom
and check" into an unwanted re-pick. The masks' Pick Colors stays on
because each click adds a color to a set; that is a different task.
Trying another spot is one click on the eyedropper away, and each try is
an undo step.

### What a click samples (the user's side; OQ2 is the engineer's)

- **The pixel under the crosshair's center, at any zoom, is what gets
  grayed** (prd OQ2: "What the person sees and what gets grayed must
  match"). The sample comes from the photo's data, never from screen
  pixels, so it does not matter whether the loupe shows a stretched live
  frame or the full-resolution render at that moment.
- **Thin fringes snap.** A fringe is often 1–3 pixels wide, and at fit one
  screen point covers several of them, so a click rarely lands exactly on
  one. The pick takes the most colorful pixel within a small radius of
  the click, measured in screen points (the engineer sets it, about 3 pt).
  So at fit it searches a wider area of the photo, and at 100% only a few
  pixels. Averaging the area instead would mix the fringe with the sky
  and the branch and give a duller, wrong color. This is design intent.
  The engineer owns the exact rule and checks it against scene (a): a
  click within 2 pt of the purple fringe at fit picks the fringe color.
- **A spot with almost no color** (gray, white, black, or a monochrome
  photo): nothing is stored, no undo step is made, the eyedropper stays on,
  and the caption and VoiceOver say "That spot has almost no color" (§3).
  Graying a gray color would do nothing, and a silent no-op pick would
  leave the person wondering why the fringe stayed.
- **A click on the surround** (outside the photo) does nothing. The
  eyedropper stays on.

### What the loupe shows while picking

- **Empty slot:** the photo as it is, with every current adjustment,
  including the other slot's graying (after picking purple, the green
  fringe is still there to pick).
- **Slot that holds a pick (replacing):** the photo **without that slot's
  graying**, the other slot still applied. Otherwise the fringe the person
  wants to pick again is already gray on screen and can't be found or
  sampled. The caption says so (§3). Pressing Esc, or the eyedropper again,
  puts the slot's effect back with no change saved. This is a preview: it
  is not saved, not an undo step, and never reaches the cache, grid or
  histogram (like a hover preview).
  - At fit it is the next live frame.
  - Zoomed in, it refines to full resolution once the frame has settled,
    as the sharpening map does (SMP §5: the estimate stays until the exact
    frame replaces it, and the caption spinner appears only after 0.5 s,
    labeled "Refining the photo"). The person is about to click a thin
    fringe at 100%, so a stretched 2560 px frame isn't good enough here.
    That differs from a slider drag, which ruling 13 lets stay stretched.
- **After the pick** the change is saved at once (it is a committed
  change), so at 100% the true result shows as soon as the save lands
  (ruling 13). A Tolerance drag shows the stretched live frame while it
  moves and the true result on release, as every slider does.

### Mouse and keys while picking

| Input | While a slot is picking |
|---|---|
| Click on the photo | Picks (above), instead of zooming |
| Drag | Still pans. A press that moves past the loupe's 3 pt drag threshold is a pan, not a pick, so people can move to the next fringe at 100% without leaving the tool |
| Double-click | Picks once and doesn't leave the loupe. The second click of a double-click within the double-click interval after a pick is ignored. A habitual double-click mustn't throw the person back to the grid mid-task |
| Scroll, pinch, ⌥-scroll, `Z`, ⌘= / ⌘−, toolbar Fit \| 100% | Work as always; the eyedropper stays on |
| Esc | Cancels picking: the eyedropper turns off, a replaced slot's effect comes back, nothing is saved. Works while the loupe or an inspector button has the keyboard; in a text field, Esc keeps its meaning (hands the keyboard back first) |
| Culling keys | Work as always. Moving to another photo (arrows, film strip, auto-advance) cancels picking |
| Right-click / Control-click | The loupe's context menu, as always; picking stays on |

**Why the crosshair.** The HIG lists the crosshair for "precise
rectangular selection". Picking one pixel is not a rectangle, but it is
the same need: the exact point under the pointer matters, and the
crosshair is the only system pointer with an unambiguous center. A custom
eyedropper-shaped pointer would be custom chrome whose hotspot (the tip) is
hard to place on a 1-pixel fringe. The HIG also asks to "keep custom pointer
shapes simple" and to avoid gratuitous ones. This is judgment: the HIG
doesn't name a pointer for sampling.

**Why not a color well.** HIG Color wells: a color well "lets people
adjust the color of… onscreen elements" through a color picker. That picker
offers every color, while the owner's rule is that the color comes from the
photo, and its screen eyedropper samples display pixels (after color
management and drawn over by anything on screen), not the photo's data.
It would let what is grayed differ from what was clicked, which OQ2 forbids.

### Where picking is unavailable

| Situation | Eyedroppers | Tooltip when dimmed |
|---|---|---|
| Crop session | Dimmed; a crop session also cancels picking | "Finish cropping to pick a fringe color." |
| Fringe map shown | Enabled. Clicking one suspends the fringe map and brings it back after the pick or Esc (§6) | — |
| Sharpening map shown | Enabled. Clicking one ends the sharpening map, as Paint and Pick Colors do (SMP §6): it serves another task | — |
| Show Original on | Enabled. Clicking one turns Show Original off: the pick is made on the photo being edited | — |
| Review mode | Picking is cancelled on entering review (the inspector hides). With the inspector brought back (⌥⌘I), picking works | — |
| Video, offline, unreadable stack, loading | The Adjust tab shows its existing state (N1); no controls | — |

## 5. Tolerance (R3, R4, R5)

- One slider per pick. Changing one never changes the other pick's effect
  (AC2).
- Moving right widens the range: never fewer pixels affected (R3). At 0,
  only colors very close to the pick change. The slider has no "off"
  position; Clear is the way to stop a pick.
- The soft falloff (R4) is not a control. The legend and the map show it
  as gray (partial) areas.
- Colors away from high-contrast edges are untouched (R5). The caption
  (§3) and the map (§6) are how the person learns and checks that.

## 6. Seeing what's affected (R6): the fringe map

**Form: a map in place of the photo, exactly like the sharpening map.**
White where a fringe loses all its color, gray where it loses some, black
where nothing changes. One combined map for both picks.

Why this form:

1. **People already know it.** The sharpening map shipped two days ago
   with the same interaction (toggle, badge, legend, Esc, refinement).
   A second "see what's affected" view that worked differently would cost
   learning for no gain (HIG Consistency; P5).
2. **It answers the real question.** On the photo the fringes are thin and
   gray once removed, so a gray fringe and a gray branch look the same.
   On the map, removed color shows as thin white lines along edges. The
   person can see at once that the flower's petals are black (untouched)
   and only its outline is white, and watch white areas grow as Tolerance
   rises.
3. **An overlay tint was rejected.** Any tint color competes with the
   fringe colors themselves and with the red mask overlay, and a
   colored-on-gray "what was removed" picture looks like a color-splash
   effect. Either would also need a color as the only signal.

Per-pick maps (one at a time) were considered and left out: the person's
question is "what does my edit touch", and two picks rarely overlap. While
dragging one pick's Tolerance, the map changes where that pick reaches.

### Where the command lives

Everything follows SMP §3, with these items:

| Surface | What | Enabled when |
|---|---|---|
| **Menu bar** | **Adjust ▸ Show Fringe Map / Hide Fringe Map**, directly after Show / Hide Sharpening Map; the title follows the state | The loupe shows an editable photo (`canEditLoupePhoto`) with **at least one pick**, no crop session, not reviewing. Dimmed otherwise, including in the grid |
| **Inspector** | The **Fringe Map** toggle (§3) | Same. Dimmed tooltips: "Pick a fringe color to show the fringe map.", "Finish cropping to show the fringe map.", "Exit Review (F) to show the fringe map." Enabled tooltip: "Show where fringe color is removed, in place of the photo" |
| **Context menu (loupe)** | **Show / Hide Fringe Map**, after Show / Hide Sharpening Map | Listed only when it can act |
| **VoiceOver (loupe canvas)** | Custom action **Show / Hide Fringe Map**, after the sharpening map's | Same as the context menu |
| **Esc in the loupe** | Hides the map | The loupe has the keyboard and the map is shown |
| **Shortcut, toolbar** | None, for SMP §3's reasons (a step of setting one control, not a frequent whole-photo mode) | — |

Showing it from the menu, the context menu or VoiceOver **reveals Color
Fringes**: shows the inspector, switches to Adjust, expands Lens and
scrolls the Color Fringes group into view (the I7 / SMP §3 pattern; Reduce
Motion jumps). The menu item also makes the feature findable: Help ▸ Search
for "fringe" lands on it.

**Why dimmed with no pick** (where the sharpening map is never dimmed):
with no pick the map would be all black for every photo. The sharpening
map always has something to show, because Masking always selects. The
dimmed tooltip says what to do first.

### What the loupe shows

As SMP §5 in full: same frame, crop, zoom and scroll; neutral grayscale
encoded so mask value *v* displays as gray *v*; standard dynamic range with
the HDR badge hidden; no transition; the photo stays until the first map
frame is ready; the live estimate while a value changes; full-resolution
refinement after about 150 ms without input at any zoom, the estimate
staying until it lands; the mini spinner in the caption after 0.5 s, labeled
"Refining the fringe map". The map follows every change, because what's
grayed depends on everything before the step.

R13 applies to the map too: the fit map and the full-size map cover the
same pixels within the engineer's scale tolerance (AC10). The map must be
computed by the same rule the renderer uses (as SMP §11's "must still equal
the blend mask"), not by a separate approximation.

### Caption badge and legend

The badge goes in **Original's slot** of the caption, as the sharpening
map's does (Filtered, then Original or a map, then HDR, then Offline). Only
one map is on screen at a time (below), so the slot never holds two, and
the caption gets no wider than it is today (loupe-caption-narrow, Next).

| State | Badge | Badge tooltip | Legend (inspector caption) |
|---|---|---|---|
| Shown, Color Fringes on | **Fringe Map** | "Showing where fringe color is removed instead of the photo: white loses its color, black keeps it. Press Esc to see the photo again." | "White areas lose their color, gray areas in part, and black areas keep it." |
| Shown, Color Fringes turned off (picks kept) | **Fringe Map · Not Applied** | "Showing where fringe color would be removed instead of the photo. Color Fringes is turned off. Press Esc to see the photo again." | "Color Fringes is turned off. Turn it on to remove color from the white areas, and the gray areas in part." |

With the group turned off, the map is computed from the stored picks and
tolerances, not from `effective` (which would reset them), as SMP §11 does
for Sharpening.

### How the map interacts with everything else

SMP §6's rule holds, with **one map slot shared by both maps**: at most one
alternate view is on the loupe at a time (Original, a map, the red mask
overlay, a crop session), and the last one asked for wins. Every row of SMP
§6 applies to the fringe map as written for the sharpening map, except:

| Situation | Behavior | Why it differs |
|---|---|---|
| Show Fringe Map while the sharpening map is shown (or the reverse) | The shown map ends, and the other takes its place. What the first one suspended (the overlay, Show Original) stays suspended and comes back when the second is hidden | One slot: switching maps is not "needing the photo" |
| Click an **eyedropper** while the fringe map is shown | The map is **suspended**: the photo shows (for a replaced slot, without that slot's effect, §4). After the pick, or Esc, the map comes back with the new values | Sharpening's Paint and Pick Colors *end* the map (SMP §6). Picking here is a one-click step inside the very task the map serves (map on, re-pick, look again), so ending it would make the person turn it back on after every try |
| **Clear** the last pick while the map is shown | The map ends ("Showing the photo."), and the toggle dims | Nothing is left to map |
| Moving to another photo, review, the grid, a relaunch, offline | The map ends, as SMP §6 | — |
| Zoom, undo / redo, preset and look-up table hover | The map stays and follows, as SMP §6 and D-Q1 | — |
| **Color Alignment** changes while the map is shown | The map follows: fringes move with the alignment | It maps what the renderer grays after alignment, whatever their order |

## 7. Color Alignment (R7–R10)

### Behavior

The model is the one White Balance already uses (Auto measures and fills
Temperature and Tint; moving them makes it Custom), with a check box
because the automatic state persists and is measured again on paste
(R16):

| Action | Result | Undo step |
|---|---|---|
| Check **Align automatically** | The photo is measured from its master (R7). While it measures, the spinner shows and the check box stays checked. When done, the sliders show the measured values and the loupe shows the result. The values are stored (R8) | One: "Turn On Automatic Alignment", recorded when the measured values are saved |
| Uncheck it | The correction is removed: both sliders go back to 0 | One: "Turn Off Automatic Alignment" |
| Move a slider while it is checked (fine-tune, R10) | The slider starts from the measured value. The check box turns off, and the values become hand-set (§17 RI-2) | One per gesture, named for the slider |
| Move a slider while it is unchecked (set by hand, R10) | That shift is applied | One per gesture |
| Check it again after hand-setting | Measures again and replaces the hand-set values | One |
| Uncheck while measuring | Measuring stops, nothing is saved, the sliders stay as they were | None |

Why unchecking removes the correction rather than keeping the measured
values as hand-set ones: the check box is R7's one control that turns the
correction on, so its off state should mean off. Keeping the measured
values is one slider nudge away, and undo restores either way.

**Measuring** is the existing Auto pattern (`AdjustmentEditor.measure`,
`isMeasuring`): off the main thread, dropped if the person moves to another
photo first, and other controls stay usable meanwhile. Turning the group's
check box off keeps the values and the automatic state, as for any group
(R12, AC9).

### Caption under the check box

| State | Caption |
|---|---|
| Off, sliders at 0 | "Removes red/cyan and blue/yellow outlines that widen toward the corners." |
| Measuring | "Measuring this photo…" (with the spinner) |
| Automatic, something corrected | "Measured on this photo. Paste and presets measure each photo again." |
| Automatic, nothing to correct (measured 0, 0) | "No color edges were found to correct in this photo." The check box stays checked, so paste and presets still measure other photos |
| Measuring failed (the master couldn't be read) | "This photo could not be measured." The check box goes back to off, nothing is saved |
| Hand-set (off, a slider not 0) | "Set by hand. Paste and presets copy these values." |

The second and last lines answer R16's difference in the place the person
decides it, before they paste.

### Crop, rotation and straightening (R9)

Nothing to show: the correction stays put when the crop changes, so the
sliders don't move and nothing re-measures. Starting a crop session doesn't
touch Color Alignment.

## 8. Every state

| State | Lens heading | Color Fringes | Color Alignment | Loupe |
|---|---|---|---|---|
| **Off** (new photo, nothing set) | Expanded, no check box (nothing modified), reset dimmed | Two empty slots, no Tolerance rows, Fringe Map dimmed, "No pick" caption | Unchecked, sliders 0, "Off" caption | Unchanged. Renders exactly as before (R11) |
| **No pick yet, picking** | — | Eyedropper on, picking caption | — | Crosshair over the photo |
| **One pick** | Check box on, reset enabled | Slot row with swatch, name and clear; its Tolerance row; Fringe Map enabled; "At least one pick" caption | — | Fringes of that color grayed near edges |
| **Two picks** | — | Both rows filled, two Tolerance rows | — | Both grayed |
| **Replacing a pick** | — | That slot's eyedropper on, "replacing" caption | — | Photo without that slot's effect, crosshair |
| **Neutral click** | — | Eyedropper still on, "almost no color" caption | — | Unchanged |
| **Fringe map shown** | — | Toggle on, legend | — | Map, "Fringe Map" badge |
| **Color Fringes turned off** | Check box mixed if Color Alignment is on | Values kept, labels secondary (`showsTurnedOff`); eyedroppers and Fringe Map stay enabled (as Sharpening Map, SMP §4) | — | Without graying; map shows "Not Applied" |
| **Changing a value with a group off** | — | Picking, clearing or a Tolerance change turns the group back on, as any control does (`enableModules`) | Same | — |
| **Measuring** | — | — | Checked, spinner, "Measuring…" | Unchanged until the measurement is saved |
| **Automatic, corrected / nothing found / failed** | — | — | §7 captions | Corrected / unchanged / unchanged |
| **Hand-set** | — | — | Unchecked, sliders set, "Set by hand" caption | Corrected |
| **Show Original (`\`)** | — | — | — | Without the feature (and without everything else), Original badge (R12) |
| **Crop session** | — | Eyedroppers and Fringe Map dimmed with tooltips | Usable (a parameter, like other sliders during crop) | Crop frame |
| **Review mode** | Inspector hidden; with ⌥⌘I, usable | Fringe Map dimmed (as Sharpening Map in review); picking works | Usable | — |
| **Grid** | Not shown (the Adjust tab shows "Open a Photo to Adjust It") | — | — | — |
| **Monochrome or grayscale photo** | Shown (R15: every photo format is offered it) | Every click gives "almost no color" | Measures nothing: "No color edges were found…" | Unchanged |
| **HDR photo on an EDR display** | — | Picking works on what is shown (§14) | — | Map in SDR, HDR badge hidden while it shows |
| **Video** | — | — | — | Adjust tab: "No Adjustments for Videos" (N1); not offered (R15) |
| **Offline, unreadable stack, loading** | — | — | — | Existing Adjust tab states (N1) |
| **Stack from a newer build, or damaged** | — | — | — | "Can't Edit This Photo" (N1), unchanged |

## 9. Before/after, undo, reset

- **Before/after** is Show Original (`\`), which shows the photo without
  this feature, as R12 asks. To compare only this feature, people use the
  group check boxes (Color Fringes, Color Alignment) or the Lens heading's
  check box, as for any group.
- **One undo step** per pick, clear, Tolerance gesture, check box change
  (saved when measured) or slider gesture (R12, AC9). Arming or cancelling
  an eyedropper and showing or hiding the map are never undo steps.
- **Undo while a slot is picking** keeps it picking; the loupe shows the
  restored values (for a replaced slot, still without that slot's effect).
- **Reset**: the Lens heading's reset ("Reset Lens"), its context menu, and
  Reset All Adjustments give back the identity render (R12, AC9). Double-
  clicking a slider resets that slider only.

## 10. Copy and paste, presets, batch, Lightroom import

- **Copy / Paste Adjustments and presets** carry both groups like any other
  (R16). Picks travel as colors, not positions in the photo (prd
  Dependencies), so they gray the same colors near edges on the other
  photo. The preset save sheet's group list shows "Color Fringes" and
  "Color Alignment" with the other groups.
- **Automatic alignment is measured on each receiving photo** (R16,
  ruling 10), never copied. What the person sees:
  - **In the loupe** (paste or a preset on the open photo): the check box
    shows its spinner and "Measuring this photo…". The whole paste is
    saved as one undo step when the measurement is done.
  - **In the grid** (paste, Apply Preset on a selection): the batch Auto
    Exposure pattern (`BatchActions.autoExposure`). Photos are measured
    one at a time with progress in the toolbar's Activity item under the
    command's own title, and Stop there writes nothing. When all are done,
    everything is saved as one undo step. Only photos that receive
    automatic alignment are measured. A paste without it stays as fast as
    today.
  - **Photos that can't be measured** (original offline or unreadable)
    are left entirely unchanged by that command: none of its groups apply
    to them, and Activity shows the existing "left unchanged" warning
    ("‹N› photos were left unchanged: their originals are offline." for
    offline originals). The other photos change as usual. This is the
    batch Auto Exposure rule (§17 RI-1, ruled; prd R16a, AC13a). In the
    loupe, a paste or preset whose measurement fails leaves the open photo
    unchanged too, and the caption says "This photo could not be
    measured."
- **Hand-set alignment** values are copied as they are (§17 RI-2).
- **Preset and look-up table hover previews** in the loupe show a preset's
  picks at once. A preset with automatic alignment measures in the
  background while hovered and shows the alignment when measured. The
  hover never waits on it, and nothing measured during a hover is saved
  unless the preset is applied.
- **Lightroom preset import** (R17) needs no new UI. Mapped fringe settings
  arrive as picks and show in the slots like any pick, with a swatch and a
  hue name. Automatic correction arrives as "Align automatically" on. The
  import report stops listing what was mapped. Whatever their source, picks
  look and behave the same.

## 11. Accessibility

### Keyboard

| Who | How |
|---|---|
| Default settings (Tab reaches text fields only) | Tolerance and Red/cyan / Blue/yellow through their value fields: ↑ / ↓ steps, Return or Esc hands the keyboard back (`SliderRow`). Adjust ▸ Show Fringe Map from Control-F2 or Help ▸ Search; Esc in the loupe hides it |
| Keyboard Navigation or Full Keyboard Access | Tab reaches, in order: Color 1's eyedropper and clear, Color 1's Tolerance field, Color 2's eyedropper and clear, Color 2's Tolerance field, Fringe Map, Align automatically, Red/cyan field, Blue/yellow field. Space arms an eyedropper, clears, toggles the map or the check box. Esc cancels picking |
| Picking itself | Needs a pointer, because it chooses a pixel. Full Keyboard Access users can move the pointer with the system's pointer-control keys. See §18 Q1 |

### VoiceOver

- **Slot row:** a group named "Color 1" whose value is the hue name or
  "None" ("Color 1, Purple"). Eyedropper: label "Pick Color 1", help "Click
  a fringe in the photo to pick its color", spoken as a toggle with its
  state. Clear: label "Clear Color 1".
- **Tolerance slider:** label "Color 1 tolerance" (the visible label is
  "Tolerance"; two sliders with the same name would be ambiguous in the
  rotor). Its field: "Color 1 tolerance value".
- **Check box:** "Align automatically", with the caption as its help. The
  spinner's label: "Measuring color alignment".
- **Announcements** (posted when not caused by the control that would speak
  for itself): after a pick, "Color 1 set to purple."; after a clear,
  "Color 1 cleared."; on a neutral click, "That spot has almost no color.";
  when measuring ends, the caption's sentence ("Measured on this photo…" or
  "No color edges were found…"). For the map: "Showing the fringe map.",
  "Showing the fringe map. Color Fringes is turned off.", and "Showing the
  photo." (the existing key) when hidden, by any path except its button.
- **Loupe canvas value:** "Fringe map, ‹photo value›" or "Fringe map, not
  applied, ‹photo value›" while the map is shown (as SMP §8). While a slot
  is picking: "Picking a fringe color, ‹photo value›". This is what
  `accessibility image` prints.
- **Canvas actions:** Show / Hide Fringe Map, listed when it can act.

### Increase Contrast, Reduce Motion, color, touch

- **Increase Contrast:** no new colors. The swatch is the photo's color and
  can be dark on the dark inspector, so the hue name next to it carries
  the meaning. Buttons, badge and spinner are system or `Palette`
  elements. The map runs black to white already.
- **Reduce Motion:** no transitions anywhere. The reveal scroll jumps
  (SMP §8).
- **Color is never the only signal:** slots have names, eyedropper state
  is a bezel, map state is text (HIG Accessibility).
- **Touch-display Macs:** a tap on the photo picks, as a click does. Nothing
  depends on hover (the crosshair is feedback, not information), and every
  button keeps the 20 pt minimum.

## 12. Strings

All added by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings`.
None contains the product name, so none needs a `%@` brand argument. Where
a key already exists (for example a color name used by color labels or
tone curve channels), reuse it and extend its catalog comment to name the
new use, as `ui-redesign/design.md` §7 does.

| English (key) | Where | Comment for the catalog |
|---|---|---|
| Lens | Adjust tab heading | Heading for lens corrections: color fringes, color alignment |
| Color Fringes | Adjust tab group; preset group list; undo names through "Turn On %@" | Removes picked fringe colors near high-contrast edges |
| Color Alignment | Adjust tab group; preset group list | Lines up red and blue with green toward the corners |
| Color %lld | Slot row label; VoiceOver group name | %lld is 1 or 2 |
| None | Empty slot's value | Reuse if present |
| Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta | Slot value: the pick's hue name | Reuse existing keys; add "fringe color name" to their comments |
| Tolerance | Slider under each pick | Existing key (color range mask); add the new use |
| Color %lld tolerance | VoiceOver label of that slider | |
| Color %lld tolerance value | VoiceOver label of its field | |
| Pick Color %lld | Eyedropper VoiceOver label | |
| Click a fringe in the photo to pick its color | Eyedropper tooltip and VoiceOver help | |
| Finish cropping to pick a fringe color. | Eyedropper tooltip, dimmed in a crop session | |
| Clear Color %lld | Clear button tooltip and VoiceOver label | |
| Pick Again | Slot row context menu | |
| Clear | Slot row context menu | Reuse if present |
| Click a colored fringe in the photo to pick Color %lld. Press Esc to cancel. | Inspector caption, picking an empty slot | |
| Color %lld's effect is hidden while you pick. Click a colored fringe, or press Esc to cancel. | Inspector caption, replacing | |
| That spot has almost no color. Click a colored fringe, or press Esc to cancel. | Inspector caption after a neutral click | |
| That spot has almost no color. | VoiceOver announcement | |
| Pick a fringe's color in the photo to turn it gray where it lines a high-contrast edge. Thin fringes are easiest to pick at 100% (Z). | Inspector caption, no pick | |
| Raise Tolerance to include colors further from the picked one. Colors away from high-contrast edges keep theirs. | Inspector caption, at least one pick | |
| Color %lld set to %@. | VoiceOver announcement after a pick | %lld slot, %@ hue name |
| Color %lld cleared. | VoiceOver announcement after a clear | |
| Pick Fringe Color | Undo action name | |
| Clear Fringe Color | Undo action name | |
| Fringe Map | Inspector toggle; caption badge | One key, both uses |
| Fringe Map · Not Applied | Caption badge, Color Fringes off | |
| Show Fringe Map | Adjust menu; loupe context menu; VoiceOver action | |
| Hide Fringe Map | Same | |
| Show where fringe color is removed, in place of the photo | Toggle tooltip and help, enabled | |
| Pick a fringe color to show the fringe map. | Toggle tooltip, dimmed with no pick | |
| Finish cropping to show the fringe map. | Toggle tooltip, crop session | |
| Exit Review (F) to show the fringe map. | Toggle tooltip, review mode | |
| White areas lose their color, gray areas in part, and black areas keep it. | Legend, applied | |
| Color Fringes is turned off. Turn it on to remove color from the white areas, and the gray areas in part. | Legend, group off | |
| Showing where fringe color is removed instead of the photo: white loses its color, black keeps it. Press Esc to see the photo again. | Badge tooltip, applied | |
| Showing where fringe color would be removed instead of the photo. Color Fringes is turned off. Press Esc to see the photo again. | Badge tooltip, not applied | |
| Refining the fringe map | Caption spinner tooltip and VoiceOver label | No visible label |
| Refining the photo | Caption spinner while replacing a pick zoomed in (§4) | No visible label |
| Fringe map, %@ | Canvas VoiceOver value | %@ is the photo's usual value |
| Fringe map, not applied, %@ | Same, group off | |
| Picking a fringe color, %@ | Canvas VoiceOver value while picking | |
| Showing the fringe map. | Announcement | |
| Showing the fringe map. Color Fringes is turned off. | Announcement, not applied | |
| Align automatically | Check box | Sentence-style (P5) |
| Measure this photo and line up its red and blue edges with the green | Check box tooltip and help | |
| Red/cyan | Slider | Sentence-style row label |
| Blue/yellow | Slider | Sentence-style row label |
| Removes red/cyan and blue/yellow outlines that widen toward the corners. | Caption, off | |
| Measuring this photo… | Caption, measuring | |
| Measuring color alignment | Spinner tooltip and VoiceOver label | |
| Measured on this photo. Paste and presets measure each photo again. | Caption, automatic | |
| No color edges were found to correct in this photo. | Caption, measured nothing | |
| This photo could not be measured. | Caption, failed | |
| Set by hand. Paste and presets copy these values. | Caption, hand-set | |
| Turn On Automatic Alignment | Undo action name | |
| Turn Off Automatic Alignment | Undo action name | |

Reused with no new text: "Showing the photo.", "Reset “%@”", "Turn On %@",
"Turn Off %@", "Reset %@", the offline Activity warning.

## 13. Custom chrome

None. Every element is an existing component or pattern: `AppKitButton`
`.toggle` with a symbol (as Original's bezel), `AppKitButton` borderless
(the mask row buttons), a tinted SF Symbol swatch (the Color Mixer's),
`AppKitCheckbox` with a caption (machine learning's row), `AdjustSlider`,
inspector caption `Text`, `CaptionBadge`, a mini `ProgressView`, menu items,
`NSAccessibilityCustomAction`, and the system crosshair pointer. The map is
content (a rendered frame in the loupe's image layer). Nothing goes on the
glass layer.

## 14. The designer's side of OQ1 and OQ2

### OQ1: a fixed edge rule, or one people can adjust?

**My view from the user's side: fixed, no control, as the PRD proposes.**

- People think "the purple fringe", not "the contrast threshold of the edge
  detector". A third control whose effect is invisible on the photo would
  make every pick a three-way search (pick, Tolerance, edge) and drag in a
  concept the owner's two-control idea deliberately leaves out.
- The fringe map covers the risk. If the rule misses a fringe, the person
  sees a black gap where they expected white. If it reaches a real
  subject's outline, they see white there. Either way they can narrow
  Tolerance or clear the pick. They are never left guessing.
- **What the fixed rule must cover**, because the PRD's Problem names it:
  halos around **out-of-focus highlights**, whose edges are soft, as well
  as sharp branch-against-sky edges. If the rule only catches sharp edges,
  the bokeh case fails and people will ask for a control. The engineer
  should include a defocused bright disc with a purple rim in scene (a) or
  (b), or as a variant, to check this.
- It must also hold at every size (R13, AC10): the same pixels count as
  "near an edge" at fit and at full size.
- If M1 on real photos shows misses that the map makes plain and Tolerance
  can't fix, that is the evidence for a control, as a follow-up with its
  own design. I would not add it speculatively.

The technical definition is the engineer's.

### OQ2: what the person must see (the choice of image is the engineer's)

1. **The color under the crosshair's center when clicked is the color that
   gets grayed**, at any zoom, whether the loupe shows a live frame, the
   cached preview, the full-resolution render or an HDR rendition (§4).
2. **A pick keeps finding the same fringe when other adjustments change
   later.** Raising Saturation, changing White Balance or applying a
   look-up table after picking must not make a picked fringe come back or
   a new color start graying. People pick once and keep editing. A pick
   that silently stops working after an unrelated slider moves would be a
   bug they can't diagnose. If the engineer's choice can't hold this, it
   is a Design question back to me, not a quiet trade-off.
3. **The swatch looks like the fringe on screen** (the picked color shown
   through the current adjustments, as a pixel of that color would look in
   the photo now), so the person can match swatch to fringe by eye.
4. **When replacing a slot, the person sees the fringe that slot would
   gray** (§4: the loupe without that slot's effect). Whatever the
   sampling image is, it must not contain the slot's own graying.
5. **Monochrome and neutral spots are refused, not stored** (§4).

## 15. Notes for the engineer (behavior, not code)

- **Section and groups.** New `Adjustments.Section.lens` with two
  `Adjustments.Group`s (`colorFringes`, `colorAlignment` or similar
  generic identifiers; no brand values). `AdjustText` gets the three
  titles. The section's position in the Adjust tab is after Details (§2);
  the render order is yours.
- **Picking state** lives on the editor next to `isSamplingColor` and
  `isBrushing`: "which slot is picking" (nil, 1 or 2), mutually exclusive
  with both. It is never persisted, never an undo step, and cleared by
  `finishSession`, a crop session, review, and moving to another photo.
  The loupe's click path (`LoupeScrollView.onClick`) sends a click to the
  picker instead of zooming while a slot is picking. Drags still pan, and
  a double-click right after a pick doesn't close the loupe (§4). Mask
  handles hide and the mask view passes clicks through while a slot is
  picking, as under the sharpening map.
- **Cursor:** the crosshair over the photo's rect only, while picking.
- **Replacing preview** (§4): values with that slot cleared, shown like a
  hover preview (`preview(_:)`), never seeding the cache or histogram.
  Zoomed in, it refines at full resolution, as `scheduleMapRefinement`
  does for the map (the refiner already renders an alternate value set at
  full size).
- **Sampling** (§4, §14): from the photo's data, with the snap radius in
  screen points converted at the current magnification. A neutrality
  threshold decides the "almost no color" refusal. One function, tested
  against scene (a) at fit and at 100% scales.
- **Hue name:** one function from a picked color to the eight Color Mixer
  band names (singular), shared by the row, VoiceOver and the debug script.
  Unit-test each band's center.
- **Fringe map state:** extend the sharpening map's state to one map slot
  with a kind (sharpening, fringe) so that SMP §6's suspend and restore
  logic serves both, and add the eyedropper's suspend (§6). The "can
  show fringe map" condition (editable, at least one pick, not cropping,
  not reviewing) is read by the menu, context menu, VoiceOver action and
  toggle alike (P2). The "not applied" test is one function: Color Fringes
  turned off.
- **Measuring** reuses the Auto pattern: `isMeasuring` (or a separate flag,
  so Auto Exposure and Align automatically don't dim each other), the
  spinner, and dropping results for a photo no longer open. Batch:
  `BatchActions.autoExposure`'s loop, progress and Stop, measuring only
  photos whose pasted or preset values have automatic alignment on.
- **USER_GUIDE.md** is updated in the same change, with the terms of §1 and
  §12 (Lens, Color Fringes, Color 1 / Color 2, Tolerance, Fringe Map, Color
  Alignment, Align automatically, Red/cyan, Blue/yellow). I check its
  wording at review.

### Debug-script hooks (so QA can check it without screen recording)

Commands that change photos open an undo group (CLAUDE.md); the others
must not (roadmap debug-script-undo-groups). Proposed:

| Command | What it does | Undo group |
|---|---|---|
| `adjust fringe pick 1\|2 <x> <y>` | Picks for that slot at unit coordinates of the photo on screen, through the same sampling path a click takes (snap, neutral refusal). Waits for the save | Yes (under `adjust`) |
| `adjust fringe clear 1\|2` | Clears that slot | Yes |
| `adjust fringe tolerance 1\|2 <value>` | Sets that slot's Tolerance | Yes |
| `adjust align auto on\|off` | The check box; waits for the measurement | Yes |
| `adjust align redcyan <v>`, `adjust align blueyellow <v>` | The two sliders | Yes |
| `adjust off\|on colorFringes\|colorAlignment`, `adjust reset lens` | Existing verbs, with the new group and section names | Yes |
| `fringearm 1\|2\|off` | Arms or disarms an eyedropper, as its button does (shows the replacing preview) | No |
| `fringemap on\|off\|toggle` | Adjust ▸ Show / Hide Fringe Map's action (reveals Color Fringes, announces), as `sharpenmap` | No |
| `print fringe` | Each slot: stored color, hue name, Tolerance, swatch color; which slot is picking; the last sample's image point and whether it was refused; the cursor the canvas sets at the photo's center; the inspector caption text; the map: asked for, on screen, badge, legend, refining, can show, what it suspended; Color Alignment: automatic, measuring, stored values, caption text | No |

Existing commands cover the rest: `menuitems "Fringe Map"` and `menupress`
(menu title, enablement), `contextmenu loupe` (the item), `accessibility
AXImage` (canvas value and actions), `buttons` and `hit` (the inspector's
glass pane doesn't snapshot), `snapshot` (the map and the grayed fringes in
the content area), `key escape` (Esc order), `click` / `doubleclick` /
`drag` on the photo with an `open` launch (the real click path while
armed: pick, pan, the ignored double-click), `print loupe <x> <y>`
(magnification and the image point under a click), `undo` / `redo`, and
`pasteadjust`, `preset apply`, `print activity` (batch measuring and the
offline warning).

## 16. Acceptance checks for the designer review

| # | Check | How |
|---|---|---|
| DR1 | The Lens heading sits after Details with Color Fringes, then Color Alignment. The heading's check box goes mixed with one group off, and its reset reads "Reset Lens" | `buttons`, `print`; manual (glass pane) |
| DR2 | Slot rows: both always shown; swatch, hue name, eyedropper toggle bezel, clear only when set (its slot kept); Tolerance row only under a set slot; context menu Pick Again / Clear | `buttons`, `print fringe`; manual |
| DR3 | Picking: one click picks and disarms; crosshair over the photo only; drag pans while armed; a double-click picks once and stays in the loupe; a click on the surround does nothing; Esc cancels; one undo step per pick and clear, none for arming | `fringearm`, `click`/`drag`/`doubleclick` with an `open` launch, `print fringe`, `print undo` |
| DR4 | Snap at fit: a click within 2 pt of scene (a)'s purple fringe picks the fringe color, not a mix; a click on a neutral area is refused with the caption and no undo step | `adjust fringe pick`, `print fringe` |
| DR5 | Replacing: arming a set slot shows the photo without that slot's graying (snapshot of the content area) and the other slot's still applied; Esc restores; zoomed in, the refined frame arrives and the spinner shows only after 0.5 s | `fringearm`, `snapshot`, `print fringe`; manual at 100% on a 24 MP photo |
| DR6 | Fringe Map: menu item after Sharpening Map, dimmed with no pick, in the grid, during crop, in review, for video, offline and unreadable stacks; title flips; context menu and canvas action listed only when it can act; reveal from a hidden inspector on Info | `menuitems`, `menupress`, `contextmenu loupe`, `accessibility AXImage`, `print fringe` |
| DR7 | The map is neutral gray in the photo's frame at fit and 100%; badge and legend match the state, "Not Applied" with the group off | `fringemap on`, `snapshot`, `print fringe` |
| DR8 | One map slot: showing the fringe map replaces the sharpening map and keeps what it suspended; an eyedropper suspends the fringe map and it returns after the pick and after Esc; clearing the last pick ends it | Debug script per row |
| DR9 | Color Alignment: checking measures (spinner, caption), values appear in the sliders; a slider move unchecks it; unchecking zeroes the sliders; each caption of §7 appears in its state (including nothing found on a monochrome photo) | `adjust align …`, `print fringe` |
| DR10 | Paste and presets: the loupe paste waits for measurement and is one undo step; a grid paste shows progress in Activity, Stop writes nothing, offline photos get the warning (per RI-1's ruling); two photos of scene (c) end up with different stored values | `pasteadjust`, `preset apply`, `print activity`, `print fringe` |
| DR11 | Keyboard and VoiceOver: Tab order of §11 with Keyboard Navigation on; the slot group's name and value; slider labels "Color 1 tolerance"; announcements; canvas values while picking and with the map shown | Manual; `accessibility` |
| DR12 | Increase Contrast and Reduce Motion: no new colors, names legible next to dark swatches, no transitions, the reveal jumps | Manual |
| DR13 | Strings: every §12 key present with its comment; `LocalizationTests` pass; `USER_GUIDE.md` uses §1's terms | `swift test --filter LocalizationTests`; reading |
| DR14 | Esc order in the loupe: crop session, picking, map, review, loupe | `key escape` per state |

## 17. Requirements issues (ruled)

The product manager ruled both on 2026-11-07, each as the option this
design had applied (prd.md Revisions). Nothing is open.

| RI | Ruling | PRD | Where this design applies it |
|---|---|---|---|
| RI-1 | Option A. A paste, preset or grid batch that carries automatic lateral correction leaves a photo it can't measure (original offline or unreadable) entirely unchanged: none of the command's groups apply to it, and Activity shows the existing "left unchanged" warning. The other photos change as usual | New R16a, AC13a | §10 (widened from offline only to offline or unreadable, and the loupe case), DR10 |
| RI-2 | Option A. Moving either slider after an automatic measurement starts from the measured values and makes them hand-set; paste and presets copy them as they are (the White Balance pattern) | R10, R16, AC7, AC13 updated | §7, the hand-set caption in §12, DR9 |

Also ruled the same day:

- **Two groups satisfy R12** (my reading in §2 is confirmed): Color Fringes
  and Color Alignment, each with its own on/off and its own preset entry.
  prd.md R12 and AC9 are reworded. §2's assumption stands as the design.
- **Test scene (a) now includes a defocused disc with a soft purple rim**,
  and AC1 checks that it is grayed (the coverage §14 asked for under OQ1).
- **OQ3 is closed** by this design.

The issues as raised:

1. **RI-1. Offline originals receiving automatic Color Alignment** through
   paste, a preset or a grid batch (R8, R16). R8 needs measured values
   stored, and measuring needs the master. The PRD doesn't say what
   happens when a target's original is offline.
   - Option A: as batch Auto Exposure does today, the command leaves those
     photos **unchanged** (none of the pasted groups apply) and Activity
     says "‹N› photos were left unchanged: their originals are offline."
     **Recommended and applied (§10):** one rule the app already uses, and
     a photo never ends up half-pasted.
   - Option B: apply every other group and leave Color Alignment off on
     those photos, with a warning naming the alignment. The look then
     differs from what the person pasted, with no measured values to show
     why.
   - Option C: store "automatic, not measured" and measure the first time
     the original is back online. This needs a new deferred state and
     changes R8's "saved with the edit" guarantee.
   Affects §10 and DR10 only.
2. **RI-2. What fine-tuning an automatic correction means for paste and
   presets** (R10 "fine-tune", R16). The PRD doesn't say whether a
   fine-tuned photo still counts as "automatic" (measured again on each
   receiving photo) or becomes hand-set (copied as is).
   - Option A: **fine-tuning switches to hand-set values.** The check box
     turns off, the slider starts from the measured value, and paste
     copies the values. The White Balance precedent (Auto, then a slider
     move makes it Custom), and one meaning per slider. **Recommended and
     applied (§7).**
   - Option B: keep automatic on and treat the sliders as offsets from the
     measurement. Paste re-measures and adds the same offsets. Slider 0
     then no longer means "no shift", the sliders show offsets rather than
     the correction, and an offset tuned for one photo's measurement may
     be wrong for another's.
   Affects §7, the hand-set caption in §12, and DR9.

## 18. Questions for the owner

1. **Q1. Should there be a way to remove fringes without pointing at the
   photo?** Picking needs a pointer, so a VoiceOver user, or someone who
   can't place the pointer precisely, can't use Color Fringes, though
   Color Alignment works for everyone. A small menu of common fringe colors
   (purple, green) beside each eyedropper would fill a slot without
   pointing, and would also help anyone in a hurry. That is new scope
   beyond your "color picker" rule. **Proposed default:** not in this
   feature. A roadmap Idea row (`fringe-color-presets`) for the product
   manager, considered after M1 shows which colors real fringes have.

## Revisions

- 2026-11-07: First version, against prd.md as approved 2026-11-07.
- 2026-11-07: Recorded the product manager's rulings in §17: RI-1 option A
  (prd R16a, AC13a), RI-2 option A (R10, R16, AC7, AC13), the two-group
  reading of R12 confirmed (R12, AC9), scene (a)'s defocused disc (AC1), and
  OQ3 closed. §10 now says "can't be measured (offline or unreadable)" and
  covers the loupe case, as RI-1's ruling words it. Status set to Designed.
  §18 Q1 is still with the owner.
