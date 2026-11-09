# Chromatic aberration and color fringe removal: design

Owner: apple-ui-designer. Date: 2026-11-07. Status: Designed. The product
manager ruled both requirements issues on 2026-11-07 (§17), each as the
option this design applied. The owner answered §18 Q1 ("It should go into
this feature now"; prd ruling 15, R1a–R1c), and this revision designs the
list of common fringe colors (prd OQ4) in §3, §4, §8, §11, §12, §15 and §16.
The design questions from implementation (DQ-1 to DQ-4) are
ruled in §19 (2026-11-08). The pixel magnifier (prd rulings 16–22, R19–R36,
OQ12, OQ13) is designed in §20, with §1, §3, §4, §8, §11–§16 revised for it
(2026-11-08). Nothing is open.

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
| **Common Fringe Colors** (menu section) | The short list a slot can be filled from without pointing at the photo: Purple and Green (R1a) | Says what the list is and why those colors; not "presets", which already means saved adjustments here |
| **Pick from Photo** (menu item) | The eyedropper's action, as a menu item | Names where the color comes from, beside the listed colors |
| **Tolerance** | How far from the picked color the graying reaches (R3) | The app already uses Tolerance for exactly this in a color range mask (P5: one term per thing). "Range" would collide with the Color Range mask shape, where a range is the set of colors and Tolerance is its width |
| **Fringe Map** / fringe map | The view of where fringe color is removed (R6) | Parallels Sharpening Map, a view the person already knows. Not "mask" (SMP §1: "mask" means a local adjustment here) |
| **Align automatically** (check box) | R7's one control | A check box, because it is a persistent setting that paste and presets carry and re-measure, not a one-shot command like Light's Auto (§7) |
| **Red/cyan**, **Blue/yellow** (row labels) | R10's hand settings | The colors of the outlines the person sees. Row labels are sentence-style (P5) |
| **Pixel Magnifier** (menu), **Pixel magnifier** (row label) | The small round view of the photo's own pixels beside the pointer while picking (R19–R36; §20) | Says what it shows. "Loupe" is the one-photo view here, and a reuse by another tool mustn't read as fringe-specific |

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
Color 1     ● Purple                         [⌖] [⋯]      ← slot row
Tolerance   ──────●──────────────────    [  40 ]           ← only when Color 1 is set
Color 2       None                           [⌖] [⋯]      ← slot row, empty
[ Fringe Map ]                                             ← toggle, 6 pt above
Pixel magnifier  [ 800% ⌄ ]                                ← only while a slot is picking (§20)
Raise Tolerance to include colors further from the picked  ← caption, 4 pt above
one. Colors away from high-contrast edges keep theirs.
Color Alignment                                    [✓]
[✓] Align automatically   ◌                               ← check box, spinner while measuring
    Measured on this photo. Paste and presets measure      ← caption at the check box's title inset
    each photo again.
Red/cyan    ─────●─────────────────      [ +12 ]
Blue/yellow ─────●─────────────────      [  −4 ]
```

`⌖` is the eyedropper toggle, `⋯` the slot's menu (common fringe colors,
Pick from Photo, Clear), `●` the swatch.

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
| Slot menu | `AppKitMenuButton(symbol: "ellipsis.circle")`, trailing after the eyedropper, the same ⋯ pull-down the mask rows and the Adjust header use. Always shown and enabled, empty slot included. Its items are below | The app's existing pattern for a row's commands; a pull-down, because its items are actions (HIG: pop-up buttons are for choosing among mutually exclusive options, pull-downs for commands) |
| Row height | `SliderRow.height` (22 pt); buttons at least 20 pt (UIR §10) | |

No click target on the swatch or name. The slot's color comes from the
eyedropper or the slot menu.

### The slot menu (R1a, prd OQ4)

```
Pick from Photo
─────────────────────
COMMON FRINGE COLORS          ← section header
● Purple
● Green
─────────────────────
Clear                         ← dimmed when the slot is empty
```

| Item | Does | Undo step |
|---|---|---|
| **Pick from Photo** | Arms that slot's eyedropper, exactly as the button does (§4). A second path for keyboard and VoiceOver users who reach the menu first (P2) | None (arming) |
| **Purple**, **Green** under the section header **Common Fringe Colors** | Fills the slot with that color at once and sets its Tolerance to that color's starting value (R1c; values are prd OQ5, the engineer's). Cancels any picking in progress. Each item carries the same `circle.fill` swatch as the row | One: "Choose Fringe Color" (R1b, R12) |
| **Clear** | Empties the slot (§4). Dimmed when it is already empty, so the menu never changes shape | One: "Clear Fringe Color" |

The section header is `NSMenuItem.sectionHeader(title:)` (macOS 14 and
later, inside the app's macOS 15 minimum; the engineer confirms). It tells
people what the two colors are without a sentence in the inspector. The
color items are commands, so they carry no check mark, even when the slot
holds that color's exact value.

The **row's context menu** has the same items in the same order (P2):
right-click or Control-click anywhere on the slot row.

**Why a ⋯ menu per slot, not elsewhere.**

- *Per slot,* because R1a fills "either slot". A single list somewhere
  else would need a second choice of which slot to fill.
- *Not a pop-up showing the slot's value.* A picked color is any color, so
  a pop-up's selected item would have to be invented for it, and Pick from
  Photo and Clear are commands, which don't belong in a pop-up (HIG).
- *Not a split button on the eyedropper* (`NSComboButton`). It has no
  push-on/push-off state, so it couldn't show that picking is on the way
  the inspector's other toggles do (I15). The debug script also drives
  `AppKitButton` and `AppKitMenuButton` already.
- *Not swatch buttons on the row.* Two always-visible color buttons per
  slot would double the row's controls for a secondary path, and would
  look like the Color Mixer's band selector, which means something else.
- *The visible clear button goes.* An eyedropper, a clear button and a ⋯
  menu would make three trailing controls on a 276 pt row. Clear is less
  frequent than filling, it is in both menus, and replacing a color
  doesn't need it.

**How a slot shows a listed color: exactly like a picked one.** The swatch
and the hue name ("Purple") are all the row shows, whatever filled it.
There is no "listed" or "picked" marker. Once in a slot, the two are the
same value with the same behavior (R1b), so a marker would describe
history, not anything the person can act on. It would also go stale the
moment a preset or paste carries the color to another photo (R1b: "arrives
indistinguishable").

### Tolerance rows

A standard `AdjustSlider` under each slot that holds a pick, labeled
"Tolerance", 0–100, `.plain` format. Double-click and the row's context
menu reset it, as every slider. **Every fill sets the starting value**:
a pick sets the pick's starting Tolerance, and a listed color sets its own
(prd OQ5), whether the slot was empty or is being replaced. A new color
generally needs a different width, and undo gives back the old one. Both
starting values are the engineer's to set from the reference, so that a
typical pick or listed color on scene (a) grays the fringe completely with
no slider move (R1c). A value that needs the person to reach for the
slider before anything happens would make the first fill look broken.
Double-click reset follows the stored color alone, never how it got there
(R1b): if the slot holds exactly a listed color's value, it resets to that
color's starting value, otherwise to the pick's. Hidden for an empty
slot: a tolerance without a color means nothing.

### Fringe Map toggle and caption

The toggle is a titled `AppKitButton(.toggle)` "Fringe Map", leading,
6 pt under the last slot row (as Sharpening Map sits under Masking). The
caption under it (11 pt secondary, wraps) has one role at a time, in this
priority:

| State | Caption |
|---|---|
| A slot is picking, and that slot was empty | "Click a colored fringe in the photo to pick Color 1. The magnifier outlines the pixel a click takes. Press Esc to cancel." |
| A slot is picking, and that slot holds a pick (replacing) | "Color 1's effect is hidden while you pick. Click a colored fringe, or press Esc to cancel." |
| The last click landed on a spot with almost no color (§4) | "That spot has almost no color. Click a colored fringe, or press Esc to cancel." |
| Picking ended because the pixels couldn't be read (§19 DQ-4) | "The original could not be read. Make sure it's available, then pick again." |
| Fringe map shown | The legend (§6) |
| No pick | "Pick a fringe's color in the photo with the eyedropper, or choose Purple or Green from the menu beside it. The color turns gray where it lines a high-contrast edge." |
| At least one pick | "Raise Tolerance to include colors further from the picked one. Colors away from high-contrast edges keep theirs." |

The last line answers the first worry people have with a color tool
("will it gray my purple flower?") in the place they look.

While a slot is picking, the **Pixel magnifier** row (a pop-up of the level,
§20) sits between the toggle and the caption, so only the caption moves.

### Color Alignment rows

| Part | Spec |
|---|---|
| Check box | `AppKitCheckbox` titled "Align automatically", sentence-style (P5), at `SliderRow.height`, as "Use machine learning" is built (`machineLearningRow`) |
| Spinner | A mini `ProgressView` right after the check box's title while measuring, with no visible label, a tooltip and VoiceOver label "Measuring color alignment" (HIG Progress indicators, as SMP §5) |
| Caption | 11 pt secondary, wraps, at `InspectorMetrics.checkBoxTitleInset` so it reads as the check box's note. Text by state (§7) |
| Sliders | "Red/cyan" and "Blue/yellow", `AdjustSlider`, signed, default 0 (no shift). The engineer picks the unit and range so that one arrow-key step is a small but visible change in a corner at 100%. Always shown: they show what automatic measured (R10 "fine-tune") |

## 4. Picking a fringe color (OQ3, R1)

### The gesture

1. The person clicks a slot's **eyedropper** (or chooses **Pick from
   Photo** in its menu). It turns on (bezel), and any other picking or
   painting tool turns off: the other slot's eyedropper, a color range
   mask's Pick Colors, and Paint.
2. Over the photo the pointer becomes the system **crosshair**
   (`NSCursor.crosshair`) and the **pixel magnifier** appears beside it
   (§20). Over the surround it stays the arrow, with no magnifier.
3. **One click on the photo picks.** The color is stored in that slot as
   one undo step ("Pick Fringe Color"), the eyedropper turns off, and the
   pointer goes back to the arrow. The loupe then shows the result.
4. Picking again for the same slot (eyedropper or Pick from Photo)
   **replaces** it, as one undo step. Choosing a common fringe color from
   the slot menu replaces it too (§3), and so does picking over a listed
   color (R1b). **Clear** in the slot menu or the row's context menu
   empties the slot as one undo step ("Clear Fringe Color"); its Tolerance
   row goes away and the fringe it grayed comes back. The other slot is
   never touched (R1, AC1).

**Filling from the list never needs the photo**, so it needs none of what
follows: no crosshair, no preview without the slot's effect, and the
fringe map stays on screen and follows. It works wherever the slot menu is
enabled (§4 "Where picking is unavailable" doesn't apply to it, except
that the whole Adjust tab is replaced for videos, offline and unreadable
photos). During a crop session the list stays enabled, as sliders do: it
is a parameter, and the image under the crop frame updates as it does for
any committed change.

**Why one click and done (not a mode that stays on).** A slot holds one
color, so a second click could only replace the first, and in the loupe a
click normally zooms: a mode left on would turn the next "click to zoom
and check" into an unwanted re-pick. The masks' Pick Colors stays on
because each click adds a color to a set; that is a different task.
Trying another spot is one click on the eyedropper away, and each try is
an undo step.

### What a click samples (the user's side; OQ2 is the engineer's)

- **The outlined pixel is what gets picked** (R22). It is the pixel the
  magnifier outlines, and a click never takes any other. The sample comes
  from the photo's data, never from screen pixels, so it does not matter
  whether the loupe shows a stretched live frame or the full-resolution
  render at that moment.
- **Which pixel that is (ruling 18; the 3-point snap is gone).** At the
  view's 100% and closer, exactly the one under the crosshair's center,
  even when a neighbor is more colorful. Zoomed out further, where one
  screen pixel covers several photo pixels, the most colorful of the photo
  pixels under that screen pixel: a thin fringe stays reachable at fit, and
  averaging them would mix the fringe with the sky and give a duller, wrong
  color. The magnifier re-centers on that pixel, so the outline stays in
  its middle (§20). A click made before the magnifier's pixels are ready
  follows the same rule.
- **A spot with almost no color** (gray, white, black, or a monochrome
  photo): nothing is stored, no undo step is made, the eyedropper stays on,
  and the caption and VoiceOver say "That spot has almost no color" (§3).
  Graying a gray color would do nothing, and a silent no-op pick would
  leave the person wondering why the fringe stayed. The test is on the
  outlined pixel alone, and the magnifier says "Almost no color" before
  the click (R26, §20).
- **A click on the surround** (outside the photo) does nothing. The
  eyedropper stays on.

### What the loupe shows while picking

- **Always:** the pixel magnifier beside the pointer, over the photo (§20).
  It draws the image a click samples, before edits, so its pixels can differ
  from the photo around it, and it isn't affected by anything below.
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
| Click on the photo | Picks (above), instead of zooming. A click whose pointer is over the magnifier's drawing also picks (AC27) |
| Drag | Still pans. A press that moves past the loupe's 3 pt drag threshold is a pan, not a pick, so people can move to the next fringe at 100% without leaving the tool |
| Double-click | Picks once and doesn't leave the loupe. The second click of a double-click within the double-click interval after a pick is ignored. A habitual double-click mustn't throw the person back to the grid mid-task |
| Scroll, pinch, ⌥-scroll, `Z`, ⌘= / ⌘−, toolbar Fit \| 100% | Work as always; the eyedropper stays on |
| Esc | Cancels picking: the eyedropper turns off, a replaced slot's effect comes back, nothing is saved. Works wherever the keyboard is in the library window. In a text field, Esc keeps its meaning (hands the keyboard back first). An open menu or pop-up, a sheet and a popover keep their own Esc, and picking stays on |
| Culling keys | Work as always. Moving to another photo (arrows, film strip, auto-advance) cancels picking |
| Right-click / Control-click | The loupe's context menu, as always, with a **Pixel Magnifier** submenu added (§20); picking stays on |
| `-` and `=` | Pixel magnifier level down and up (§20), with the loupe holding the keyboard. New, and only while picking. ⌘- and ⌘= keep their meaning |

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
| Crop session | Dimmed, and Pick from Photo is dimmed in the slot menu; a crop session also cancels picking. The common fringe colors and Clear stay enabled | "Finish cropping to pick a fringe color." |
| Fringe map shown | Enabled. Clicking one suspends the fringe map and brings it back after the pick or Esc (§6) | — |
| Sharpening map shown | Enabled. Clicking one ends the sharpening map, as Paint and Pick Colors do (SMP §6): it serves another task | — |
| Show Original on | Enabled. Clicking one turns Show Original off: the pick is made on the photo being edited | — |
| Review mode | Picking is cancelled on entering review (the inspector hides). With the inspector brought back (⌥⌘I), picking works | — |
| Video, offline, unreadable stack, loading | The Adjust tab shows its existing state (N1); no controls | — |

## 5. Tolerance (R3, R4, R5)

- From here on, "a pick" means a filled slot, whether the eyedropper or
  the list filled it: R2–R5 apply the same way (R1b), and so does
  everything below and in §6–§10.
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
| **Inspector** | The **Fringe Map** toggle (§3) | Same. Dimmed tooltips: "Pick or choose a fringe color to show the fringe map.", "Finish cropping to show the fringe map.", "Exit Review (F) to show the fringe map." Enabled tooltip: "Show where fringe color is removed, in place of the photo" |
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
| **Off** (new photo, nothing set) | Expanded, no check box (nothing modified), reset dimmed | Two empty slots (each with its eyedropper and slot menu, Clear dimmed), no Tolerance rows, Fringe Map dimmed, "No pick" caption | Unchecked, sliders 0, "Off" caption | Unchanged. Renders exactly as before (R11) |
| **No pick yet, picking** | — | Eyedropper on, picking caption, Pixel magnifier row | — | Crosshair and pixel magnifier over the photo (§20) |
| **One pick** | Check box on, reset enabled | Slot row with swatch and name, Clear enabled in its slot menu; its Tolerance row; Fringe Map enabled; "At least one pick" caption | — | Fringes of that color grayed near edges |
| **Two picks** | — | Both rows filled, two Tolerance rows | — | Both grayed |
| **Slot filled from the list** | — | Same as one pick: swatch, "Purple" or "Green", Tolerance at that color's starting value. Nothing marks it as listed (§3) | — | Fringes of that color grayed near edges |
| **Replacing a pick** | — | That slot's eyedropper on, "replacing" caption, Pixel magnifier row | — | Photo without that slot's effect, crosshair and pixel magnifier |
| **Neutral click** | — | Eyedropper still on, "almost no color" caption | — | Unchanged. The magnifier already read "Almost no color" (§20) |
| **Pixels couldn't be read (§19 DQ-4)** | — | Eyedropper off, "could not be read" caption | — | Pointer back to the arrow, no magnifier, a replaced slot's effect back |
| **Fringe map shown** | — | Toggle on, legend | — | Map, "Fringe Map" badge |
| **Color Fringes turned off** | Check box mixed if Color Alignment is on | Values kept, labels secondary (`showsTurnedOff`); eyedroppers, slot menus and Fringe Map stay enabled (as Sharpening Map, SMP §4) | — | Without graying; map shows "Not Applied" |
| **Changing a value with a group off** | — | Picking, choosing from the list, clearing or a Tolerance change turns the group back on, as any control does (`enableModules`) | Same | — |
| **Measuring** | — | — | Checked, spinner, "Measuring…" | Unchanged until the measurement is saved |
| **Automatic, corrected / nothing found / failed** | — | — | §7 captions | Corrected / unchanged / unchanged |
| **Hand-set** | — | — | Unchecked, sliders set, "Set by hand" caption | Corrected |
| **Show Original (`\`)** | — | — | — | Without the feature (and without everything else), Original badge (R12) |
| **Crop session** | — | Eyedroppers, Pick from Photo and Fringe Map dimmed with tooltips; the common fringe colors, Clear and Tolerance usable | Usable (a parameter, like other sliders during crop) | Crop frame |
| **Review mode** | Inspector hidden; with ⌥⌘I, usable | Fringe Map dimmed (as Sharpening Map in review); picking works | Usable | — |
| **Grid** | Not shown (the Adjust tab shows "Open a Photo to Adjust It") | — | — | — |
| **Monochrome or grayscale photo** | Shown (R15: every photo format is offered it) | Every click gives "almost no color". A listed color can still fill a slot; it grays nothing, because nothing in the photo has that color | Measures nothing: "No color edges were found…" | Unchanged |
| **HDR photo on an EDR display** | — | Picking works on what is shown (§14) | — | Map in SDR, HDR badge hidden while it shows. Pixel magnifier in standard range (§20) |
| **Video** | — | — | — | Adjust tab: "No Adjustments for Videos" (N1); not offered (R15) |
| **Offline, unreadable stack, loading** | — | — | — | Existing Adjust tab states (N1) |
| **Stack from a newer build, or damaged** | — | — | — | "Can't Edit This Photo" (N1), unchanged |

## 9. Before/after, undo, reset

- **Before/after** is Show Original (`\`), which shows the photo without
  this feature, as R12 asks. To compare only this feature, people use the
  group check boxes (Color Fringes, Color Alignment) or the Lens heading's
  check box, as for any group.
- **One undo step** per pick, choice from the list, clear, Tolerance gesture, check box change
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
    offline originals, and its sibling for unreadable ones, §19 DQ-2). The
    other photos change as usual. This is the
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
  import report stops listing what was mapped. Whatever their source
  (eyedropper, the list, a preset, a paste or an import), picks look and
  behave the same (R1b).

## 11. Accessibility

### Keyboard

| Who | How |
|---|---|
| Default settings (Tab reaches text fields only) | Tolerance and Red/cyan / Blue/yellow through their value fields: ↑ / ↓ steps, Return or Esc hands the keyboard back (`SliderRow`). Adjust ▸ Show Fringe Map from Control-F2 or Help ▸ Search; Esc in the loupe hides it. Buttons and menus in the inspector are out of Tab's reach with these settings, in this app as in every Mac app |
| Keyboard Navigation (System Settings ▸ Keyboard) or Full Keyboard Access | Tab reaches, in order: Color 1's eyedropper, Color 1's slot menu, Color 1's Tolerance field, Color 2's eyedropper, Color 2's slot menu, Color 2's Tolerance field, Fringe Map, Align automatically, Red/cyan field, Blue/yellow field. Space arms an eyedropper, opens a slot menu, toggles the map or the check box. In an open slot menu, ↑ / ↓ move, Return chooses, Esc closes. Esc also cancels picking |
| The whole fringe task without a pointer (R1a, AC1a) | With Keyboard Navigation on: Tab to Color 1's slot menu, Space, ↓ to Purple, Return. The fringe grays and the Tolerance field appears next in the Tab order; step it with ↑ / ↓. Tab on to Color 2's slot menu for Green. Fringe Map with Space on its button (or Adjust ▸ Show Fringe Map); Esc in the loupe, Space on the button again, or the menu item hides it. Clear from the slot menu. Nothing in this sequence needs the photo or a pointer |
| Picking from the photo | Needs a pointer, because it chooses a pixel. Full Keyboard Access users can move the pointer with the system's pointer-control keys. The list is the way to fill a slot without one (R1a) |
| Pixel magnifier level (R33) | At default settings: `-` and `=` while the loupe has the keyboard, or View ▸ Pixel Magnifier from Control-F2 or Help ▸ Search. With Keyboard Navigation on, its inspector pop-up is in the Tab order after Fringe Map while a slot is picking. The magnifier takes no focus: the keyboard stays where it was before arming |

**"From the keyboard alone" (R1a) is read as "with the system's Keyboard
Navigation or Full Keyboard Access on".** That is how a Mac keyboard user
reaches buttons and pull-downs in every app; with default settings Tab
stops only at text fields, everywhere. The alternative, an Adjust menu
item per slot and per color, would put parameter values in the menu bar,
against N10, for people who already have the system setting. This is
judgment; if QA's M2 or the owner finds it falls short, menu bar items are
an addition, not a redesign.

### VoiceOver

- **Slot row:** a group named "Color 1" whose value is the hue name or
  "None" ("Color 1, Purple"). Eyedropper: label "Pick Color 1", help "Click
  a fringe in the photo to pick its color", spoken as a toggle with its
  state. Slot menu: label "Color 1 commands", help "Choose a common fringe
  color for Color 1, pick one from the photo, or clear it", spoken as a menu
  button. VoiceOver's press opens it (`MenuPopUpButton` already answers
  `accessibilityPerformPress`). The menu reads "Pick from Photo", the
  header "Common Fringe Colors", "Purple", "Green", "Clear" (dimmed when
  empty). The swatch images on the items are decorative, so they carry no
  description.
- **Row context menu:** the same items, reached with VO-Shift-M on the row.
- **Tolerance slider:** label "Color 1 tolerance" (the visible label is
  "Tolerance"; two sliders with the same name would be ambiguous in the
  rotor). Its field: "Color 1 tolerance value".
- **Check box:** "Align automatically", with the caption as its help. The
  spinner's label: "Measuring color alignment".
- **Announcements** (posted when not caused by the control that would speak
  for itself): after a pick or a choice from the list, "Color 1 set to
  purple." (one sentence for both, R1b); after a clear,
  "Color 1 cleared."; on a neutral click, "That spot has almost no color."; when picking ends
  because the pixels couldn't be read, the caption's sentence (§19 DQ-4);
  when measuring ends, the caption's sentence ("Measured on this photo…" or
  "No color edges were found…"). For the map: "Showing the fringe map.",
  "Showing the fringe map. Color Fringes is turned off.", and "Showing the
  photo." (the existing key) when hidden, by any path except its button.
- **Loupe canvas value:** "Fringe map, ‹photo value›" or "Fringe map, not
  applied, ‹photo value›" while the map is shown (as SMP §8). While a slot
  is picking: "Picking a fringe color, ‹photo value›". This is what
  `accessibility image` prints.
- **Canvas actions:** Show / Hide Fringe Map, listed when it can act. While
  picking, **Pixel Magnifier Zoom In** and **Zoom Out**, each listed when it
  can act.
- **Pixel magnifier (R33):** no accessibility element, nothing VoiceOver stops
  on, and nothing announced as the pointer moves. The level's pop-up: label
  "Pixel magnifier zoom", value the percentage. After a change by key, menu or
  canvas action: "Pixel magnifier at 800%."

### Increase Contrast, Reduce Motion, color, touch

- **Increase Contrast:** no new colors. The swatch is the photo's color and
  can be dark on the dark inspector, so the hue name next to it carries
  the meaning. Buttons, badge and spinner are system or `Palette`
  elements. The map runs black to white already. The pixel magnifier's outline
  doubles in weight, its grid strengthens, and its plate drops the secondary
  style (§20).
- **Reduce Motion:** no transitions anywhere. The reveal scroll jumps
  (SMP §8).
- **Color is never the only signal:** slots have names, eyedropper state
  is a bezel, map state is text (HIG Accessibility).
- **Touch-display Macs:** a tap on the photo picks, as a click does. Nothing
  depends on hover (the crosshair is feedback, not information; the pixel
  magnifier needs a pointer and isn't shown for touch alone), and every button
  keeps the 20 pt minimum.

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
| Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta | Slot value: the pick's hue name. Purple and Green are also the slot menu's listed colors | Reuse existing keys; add "fringe color name" (and, for Purple and Green, "common fringe color in the slot menu") to their comments |
| Tolerance | Slider under each pick | Existing key (color range mask); add the new use |
| Color %lld tolerance | VoiceOver label of that slider | |
| Color %lld tolerance value | VoiceOver label of its field | |
| Pick Color %lld | Eyedropper VoiceOver label | |
| Click a fringe in the photo to pick its color | Eyedropper tooltip and VoiceOver help | |
| Finish cropping to pick a fringe color. | Eyedropper tooltip, dimmed in a crop session | |
| Color %lld commands | Slot menu's VoiceOver label | |
| Choose a common fringe color for Color %lld, pick one from the photo, or clear it | Slot menu's tooltip and VoiceOver help | |
| Pick from Photo | Slot menu and row context menu | Arms the slot's eyedropper |
| Common Fringe Colors | Section header in the slot menu and row context menu | Purple and Green follow it |
| Clear | Slot menu and row context menu | Reuse if present; empties the slot |
| Choose Fringe Color | Undo action name, a color from the list | |
| Click a colored fringe in the photo to pick Color %lld. The magnifier outlines the pixel a click takes. Press Esc to cancel. | Inspector caption, picking an empty slot | Replaces the sentence about 100% (Z) |
| Color %lld's effect is hidden while you pick. Click a colored fringe, or press Esc to cancel. | Inspector caption, replacing | |
| That spot has almost no color. Click a colored fringe, or press Esc to cancel. | Inspector caption after a neutral click | |
| The original could not be read. Make sure it's available, then pick again. | Inspector caption and VoiceOver announcement when picking ends because the pixels couldn't be read (§19 DQ-4) | |
| That spot has almost no color. | VoiceOver announcement | |
| Pick a fringe's color in the photo with the eyedropper, or choose Purple or Green from the menu beside it. The color turns gray where it lines a high-contrast edge. | Inspector caption, no pick | |
| Raise Tolerance to include colors further from the picked one. Colors away from high-contrast edges keep theirs. | Inspector caption, at least one pick | |
| Color %lld set to %@. | VoiceOver announcement after a pick or a choice from the list | %lld slot, %@ hue name |
| Color %lld cleared. | VoiceOver announcement after a clear | |
| Pick Fringe Color | Undo action name | |
| Clear Fringe Color | Undo action name | |
| Fringe Map | Inspector toggle; caption badge | One key, both uses |
| Fringe Map · Not Applied | Caption badge, Color Fringes off | |
| Show Fringe Map | Adjust menu; loupe context menu; VoiceOver action | |
| Hide Fringe Map | Same | |
| Show where fringe color is removed, in place of the photo | Toggle tooltip and help, enabled | |
| Pick or choose a fringe color to show the fringe map. | Toggle tooltip, dimmed with no pick | |
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
| Pixel Magnifier | View menu and loupe context submenu title | Shared by every tool that uses it |
| Pixel magnifier | Inspector row label | Sentence-style (P5) |
| Pixel magnifier zoom | The pop-up's VoiceOver label | |
| Zoom of the pixel magnifier. Press - or = while picking to change it. | The pop-up's tooltip and VoiceOver help | |
| 200%, 400%, 800%, 1600% | The levels (100% is an existing key) | No thousands separator |
| Pixel Magnifier Zoom In, Pixel Magnifier Zoom Out | Canvas VoiceOver actions | |
| Pixel magnifier at %@. | VoiceOver announcement after a level change by key, menu or action | %@ is the percentage |
| R, G, B, L | The plate's four letters | Color channels and luminance; not translated without checking |
| Almost no color | The plate, line 2, at a spot a click would refuse | Short state, not a sentence |
| Before edits | The plate, line 2 | The fringe tool's note: what the magnifier draws |
| %lld photos were left unchanged: their originals could not be read. (one: "%lld photo was left unchanged: its original could not be read.") | Activity warning after a measuring paste or preset (§19 DQ-2) | Plural. First line of the row and what VoiceOver hears; one line per file and "And %lld more." follow |

Reused with no new text: "Zoom In", "Zoom Out", "100%", "Showing the photo.", "Reset “%@”", "Turn On %@",
"Turn Off %@", "Reset %@", the offline Activity warning, and (§19 DQ-2)
"%@: the original could not be read." and "And %lld more." (extend their
comments to name the measuring paste or preset), "Paste Adjustments",
"Apply Preset %@" and "%lld of %lld" (§19 DQ-3).

## 13. Custom chrome

One: the pixel magnifier (§20). Every other element is an existing component or pattern: `AppKitButton`
`.toggle` with a symbol (as Original's bezel), `AppKitMenuButton` with
`ellipsis.circle` (the mask rows' ⋯ menu), a system menu section header
(`NSMenuItem.sectionHeader`, which `AppKitMenuButton.Entry` gains along
with an item image), a tinted SF Symbol swatch (the Color Mixer's),
`AppKitCheckbox` with a caption (machine learning's row), `AdjustSlider`,
inspector caption `Text`, `CaptionBadge`, a mini `ProgressView`, menu items,
`NSAccessibilityCustomAction`, and the system crosshair pointer. The map is
content (a rendered frame in the loupe's image layer). Nothing goes on the
glass layer.

**Justification for the pixel magnifier (WORKFLOW Rules).** No system component
shows a photo's own data at a chosen pixel scale beside the pointer. The
system's color sampler reads display pixels after color management, which R25
forbids for the reason §4 rejects the color well. It is built as plain drawing
in the content layer with no interaction of its own, so it forfeits no
accessibility or control behavior: every control for it is a system pop-up,
menu or key.

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

1. **The pixel the magnifier outlines is the pixel a click picks, and its
   color is the color that gets grayed** (R22, §20), at any zoom, whether the
   loupe shows a live frame, the cached preview, the full-resolution render or
   an HDR rendition (§4). At the view's 100% and closer that is the pixel under
   the crosshair's center.
2. **A pick keeps finding the same fringe when other adjustments change
   later.** Raising Saturation, changing White Balance or applying a
   look-up table after picking must not make a picked fringe come back or
   a new color start graying. People pick once and keep editing. A pick
   that silently stops working after an unrelated slider moves would be a
   bug they can't diagnose. If the engineer's choice can't hold this, it
   is a Design question back to me, not a quiet trade-off. (Raised as DQ-1
   and ruled in §19: a raw's own White Balance and Profile come before the
   fringe step and are the accepted exception; every later adjustment is
   held.)
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
- **Sampling** (§4, §14, §20): from the photo's data, by the rule in §4's
  "Which pixel that is", shared by the click and the magnifier's outline. A
  neutrality threshold decides the "almost no color" refusal, for the
  magnifier's reading and the click alike. Tested against scene (a) at fit,
  100% and 800%. What has to change in the built snap is listed at the end
  of §20.
- **Pixel magnifier:** §20. It holds what picking needs within R20, R30 and
  R36 (prd OQ14 is yours), and takes its image, rule, verdict and note from the
  tool (R34).
- **Hue name:** one function from a picked color to the eight Color Mixer
  band names (singular), shared by the row, VoiceOver and the debug script.
  Unit-test each band's center, and that the listed Purple and Green values
  name themselves "Purple" and "Green" (the slot must not read "Magenta"
  after the person chose Purple).
- **Common fringe colors** (R1a–R1c): one table in PhotoCore of the listed
  colors, each a stored color value of exactly the kind a pick stores, plus
  its starting Tolerance (values: prd OQ5, yours). Filling a slot from it
  writes the same fields a pick writes, nothing else: no "source" flag
  (R1b, AC1b). The slot menu, the row's context menu, the debug script and
  `photocli` (if it offers the names) read the same table. Choosing one is
  one `change(…, phase: .committed)` named "Choose Fringe Color", and it
  cancels any picking in progress.
- **Slot menu:** `AppKitMenuButton` gains a section-header entry and an
  optional image per item (the swatch). Pick from Photo is dimmed under the
  same condition as the eyedropper; Clear is dimmed for an empty slot. The
  row's context menu is built from the same entries.
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
| `adjust fringe pick 1\|2 <x> <y>` | Picks for that slot at unit coordinates of the photo on screen, through the same sampling path a click takes (§4's pixel rule, neutral refusal). Waits for the save | Yes (under `adjust`) |
| `adjust fringe fill 1\|2 purple\|green` | Fills that slot from the list, through the same action as the slot menu's item | Yes |
| `adjust fringe clear 1\|2` | Clears that slot | Yes |
| `adjust fringe tolerance 1\|2 <value>` | Sets that slot's Tolerance | Yes |
| `adjust align auto on\|off` | The check box; waits for the measurement | Yes |
| `adjust align redcyan <v>`, `adjust align blueyellow <v>` | The two sliders | Yes |
| `adjust off\|on colorFringes\|colorAlignment`, `adjust reset lens` | Existing verbs, with the new group and section names | Yes |
| `fringearm 1\|2\|off` | Arms or disarms an eyedropper, as its button does (shows the replacing preview) | No |
| `fringemap on\|off\|toggle` | Adjust ▸ Show / Hide Fringe Map's action (reveals Color Fringes, announces), as `sharpenmap` | No |
| `contextmenu fringe 1\|2 [<item>]` | Prints the slot row's context menu (items, header, enabled state), or runs an item, as the existing `contextmenu` targets do | Yes when it runs a fill or Clear; no when it lists or runs Pick from Photo |
| `magnifier level <percent>\|up\|down` | Changes the level by the same action as the pop-up (and, for up and down, the keys) | No |
| `magnifier move <x> <y>` | Puts the pointer's position at unit coordinates of the photo on screen, as a real move would, so a script can read what it would pick | No |
| `print magnifier` | Visible; level; placement (below or above, right or left) and frame in the window; the outlined pixel's coordinates; R, G, B and L; verdict and line 2's text; ready or not; the photo pixels drawn (coordinates and colors, for AC17 and AC24); device pixels per photo pixel; grid shown; memory held | No |
| `print fringe` | Each slot: stored color, hue name, Tolerance, swatch color; the slot menu's items with their enabled state; which slot is picking; the last sample's image point and whether it was refused; the cursor the canvas sets at the photo's center; the inspector caption text; the map: asked for, on screen, badge, legend, refining, can show, what it suspended; Color Alignment: automatic, measuring, stored values, caption text | No |

Existing commands cover the rest: `menuitems "Fringe Map"` and `menupress`
(menu title, enablement), `contextmenu loupe` (the item), `menupick <x>
<y> Purple` on a slot menu's button found with `buttons` (the real
pull-down path), `accessibility <role> <n> press` on the slot menu (the
role AppKit reports for a pull-down `NSPopUpButton`, `AXMenuButton` or
`AXPopUpButton`; `accessibility any` shows which) and `accessibility
AXImage` (the slot menu reached and used with no pointer, AC1a; canvas value
and actions), `buttons` and `hit` (the inspector's
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
| DR2 | Slot rows: both always shown; swatch, hue name, eyedropper toggle bezel, ⋯ slot menu; Tolerance row only under a set slot; the slot menu and the row's context menu hold Pick from Photo, the "Common Fringe Colors" header, Purple, Green and Clear (dimmed when empty), with no check marks | `buttons`, `contextmenu fringe`, `print fringe`; manual |
| DR2a | The list (R1a–R1c): Purple fills a slot in one undo step with no crosshair and no photo click, grays scene (a)'s purple fringe and the disc's rim at its starting Tolerance, and the row then looks exactly as after a pick (swatch, "Purple", Tolerance row, no marker). Green fills the other slot. Choosing a listed color replaces a pick and a pick replaces a listed color; choosing while an eyedropper is armed disarms it; the map stays on and follows; the list stays enabled during a crop session while Pick from Photo dims | `adjust fringe fill`, `menupick` on the slot menu, `contextmenu fringe`, `snapshot`, `print fringe`, `print undo` |
| DR2b | The whole fringe task with no pointer (AC1a, M2): with Keyboard Navigation on, Tab order of §11 reaches each slot menu; Space opens it, Return chooses; Tolerance steps in its field; Fringe Map toggles with Space; Clear from the slot menu. VoiceOver names the slot menu "Color 1 commands", reads the header and items, and announces "Color 1 set to purple." | `accessibility <role> <n> press`, `accessibility any`; manual with VoiceOver (M2) |
| DR3 | Picking: the eyedropper and Pick from Photo both arm it; one click picks and disarms; crosshair over the photo only; drag pans while armed; a double-click picks once and stays in the loupe; a click on the surround does nothing; Esc cancels; one undo step per pick and clear, none for arming | `fringearm`, `click`/`drag`/`doubleclick` with an `open` launch, `print fringe`, `print undo` |
| DR4 | The pixel rule (replaces the snap check): at 100% and 800%, a click on a pixel beside a stronger fringe pixel takes that pixel, and a click one pixel off a fringe on the light ground is refused with the caption and no undo step; at fit, the most colorful photo pixel under the pointer's screen pixel is taken; the outlined pixel equals the stored sample each time | `magnifier move`, `print magnifier`, `adjust fringe pick`, `print fringe` |
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
| DR15 | Magnifier shown beside the crosshair while picking, none over the surround, none for a fill from the list; gone on pick, Esc, another photo, crop, review (AC16); no fade | `fringearm`, `magnifier move`, `print magnifier`, `snapshot` |
| DR16 | Placement: 136 pt ring and plate below right, flipped at the right and bottom edges with no flicker at the threshold; never clipped at all four corners of a photo filling the canvas (AC24); no pixels beyond the photo or crop, hairline shown | `magnifier move`, `print magnifier`, `snapshot` |
| DR17 | Picture: outlined pixel at the exact center at every view zoom and level, zoomed out included; hard squares, level ÷ 100 device pixels (AC22); grid at 800% and 1600% only; outline never covers its pixel, reads over white and black (AC17) | `magnifier level`, `print magnifier`, `snapshot`; manual (M3) |
| DR18 | Plate: four values, level, "Before edits"; on scene (a)'s light ground "Almost no color" with the symbol and dimmed values, before any click (AC21); dashes and a late spinner until ready; nothing changes size | `print magnifier`, `snapshot` |
| DR19 | Level: inspector pop-up only while picking, between Fringe Map and the caption; `-` and `=` step without wrapping; View ▸ Pixel Magnifier and its checked item; context submenu only while picking; picking stays armed through every path; persisted across photos, slots, relaunch (AC22, AC23) | `magnifier level`, `menuitems "Pixel Magnifier"`, `menupress`, `contextmenu loupe`, `key` |
| DR20 | No keyboard focus taken, no accessibility element for the magnifier, no announcement on movement; pop-up label and value; canvas actions; announcement on a level change (AC28) | `accessibility`, `print responder`; manual (M3) |
| DR21 | Increase Contrast: outline, grid and plate as §20 specify. The caption, user guide and strings use §1's and §12's terms | Manual (M3); reading |
| DR22 | The pixels can't be made (§19 DQ-4): picking ends with no undo step, the caption says why and the announcement is posted once; a waiting click is dropped; arming again retries; pixels already held keep working after an eject | Debug script: `magnifier failsample on` before arming (the sampled render fails in memory, and no file is touched; a test never moves or removes an original), `print fringe`, `print magnifier`, `print undo`; code review |

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

None open.

1. **Q1 (answered 2026-11-07).** The owner: "It should go into this
   feature now." The product manager recorded it as prd ruling 15 (R1a,
   R1b, R1c, AC1a, AC1b, M2, a non-goal against a general color chooser,
   and OQ4 for me). The list holds Purple and Green. It is designed in §3
   ("The slot menu"), §4, §8, §11, §12, §15 and §16 (DR2a, DR2b). The
   question as asked:

   **Should there be a way to remove fringes without pointing at the
   photo?** Picking needs a pointer, so a VoiceOver user, or someone who
   can't place the pointer precisely, can't use Color Fringes, though
   Color Alignment works for everyone. A small menu of common fringe colors
   (purple, green) beside each eyedropper would fill a slot without
   pointing, and would also help anyone in a hurry. That is new scope
   beyond your "color picker" rule. **Proposed default:** not in this
   feature. A roadmap Idea row (`fringe-color-presets`) for the product
   manager, considered after M1 shows which colors real fringes have.

## 19. Design questions from implementation (ruled 2026-11-08)

The engineer returned three (status.md "Design questions"), and code review
raised a fourth (DQ-4, code-review.md). None widens
scope or touches a requirement, so none goes to the product manager or the
owner.

| DQ | Ruling | Engineer's change | Where applied |
|---|---|---|---|
| DQ-1 | **Option A**, as built: a raw's own White Balance and Profile are the accepted exception to §14 point 2; the user guide tells the person what to do. Revisit after M1 | One sentence of `USER_GUIDE.md` (below) | §14 point 2 |
| DQ-2 | **One summary row per command**, like the offline warning, that also lists the files, as Export's row does | The Activity report for unreadable originals (below) | §10, §12 |
| DQ-3 | **Confirmed as built**: the command's own title, "‹n› of ‹m›" as the detail, Stop | Fit a long preset name in the toolbar title (below) | §10, §12 |
| DQ-4 | **Picking ends and the caption says why**, when the pixels a tool samples can't be made | End picking, one caption, one announcement (below) | §3, §8, §11, §12, §20, DR22 |

### DQ-1: a raw's white balance comes before the fringe step

**Ruling: A.** For raws, White Balance and Profile are decode settings: the
decoder applies them, and the fringe step can only follow. After picking,
a large change to either can move a fringe's hue out of its slot's range,
and the fringe partly comes back. Every later adjustment (Saturation,
relative white balance on other formats, tone, the mixer, grading, look-up
tables, masks) is held, as §14 point 2 asks.

Why A and not the others:

- **B (von Kries compensation) fails silently**, which is the one outcome
  §14 point 2 exists to prevent. When the estimate is off, the range moves
  to colors the person never picked, and nothing on screen says the stored
  color was moved. Today's failure is visible and fixable: the fringe shows
  again, the Fringe Map shows it black where it was white, and one pick or
  a wider Tolerance fixes it. A visible, explained limit beats an invisible,
  approximate fix (HIG: people stay in control and understand why).
- **C** doubles the decode cost of every render with fringes, against R18.
- **It rarely bites in practice.** White Balance and Profile sit at the top
  of the Adjust tab (Light) and Lens comes after Details, so the usual order
  is to set them first and pick fringes later. A pick's starting Tolerance
  (55) and the soft falloff absorb small changes. The case is a large change
  after picking.

**The user guide sentence.** The engineer replaces the guide's parenthetical
("A raw file's white balance comes from the decoder, before that point:
after a large change to it, pick the fringe again.") with:

> (For a raw file, White Balance and Profile are applied as the file is
> decoded, before that point. After a large White Balance change or a
> different Profile, show the Fringe Map: if the fringe no longer shows
> white, pick or choose its color again.)

It names both decode settings, covers listed colors as well as picks (R1b),
and points to the tool that answers "is it still working?" (R6).

**Revisit after M1.** When M1 runs on real raws, it should also change White
Balance substantially after picking and note whether the fringe returns. If
ordinary edits lose picks, compensation is a follow-up with its own design,
not a change to this one.

### DQ-2: unreadable originals in a measuring paste or preset

**Ruling: one Activity warning row per command, with a summary first line
and the files listed under it.** This is the export's row (`ExportModel.detail`)
applied here, with the offline warning's sentence shape.

The row, titled with the command's undo name (as every report from it), a
warning (the person can fix the file and try again):

```
‹N› photos were left unchanged: their originals could not be read.
‹name›: the original could not be read.
‹name›: the original could not be read.
…
And ‹N› more.
```

- **First line (new key, plural):** one: "%lld photo was left unchanged: its
  original could not be read."; other: "%lld photos were left unchanged:
  their originals could not be read." VoiceOver hears this line only
  (`report(_:action:warning:announcing:)`).
- **One line per file**, the existing "%@: the original could not be read.",
  up to `ExportActivityReport.failureListLimit` (10), in the order measured;
  past that, the existing "And %lld more.".
- Posted once, when measuring ends. Stop writes nothing and posts nothing
  about unreadable files (as built). Offline photos keep their own row,
  posted first (as built). In the loupe the same row is posted, and the
  caption says "This photo could not be measured." (§7, as built).

Why not one row per photo (built): Activity keeps the 20 newest messages,
so a shoot with many unreadable files would push out everything else,
including the offline row from the same command, and VoiceOver would speak
each row. R16a asks to say how many and why; a count in one sentence says
it, and matches the offline row the person may see right beside it. Why not
the summary alone (engineer's recommendation): an offline photo shows its
badge in the grid, but an unreadable one shows nothing, so without the names
the person can't find which files to fix. The export already solved the same
problem with this exact layout and these strings (P5: one way to say one
thing).

"could not be read", not "can't be read": the sentence reports an attempt
that failed, as the export's per-file line and the loupe's "could not be
measured" do. The offline sentence says "are offline" because that is a
state the grid shows.

### DQ-3: the Activity title while measuring

**Ruling: confirmed as built.** The job's title is the command's own undo
name ("Paste Adjustments", "Apply Preset ‹name›"), its detail is "‹n› of
‹m›", and the popover has Stop.

- It is what §10 specified, and it follows Export's job (title names the
  command, the count is the detail), the pattern for a command the person
  started. Auto Exposure's "Measuring exposure ‹n› of ‹m›" names the work
  because measuring is the whole command; here the person asked for a paste,
  and measuring is how it happens (the loupe's caption says so there).
- The job and every row it posts afterwards (offline, unreadable,
  stacks this build can't change) share one title, so the popover reads as
  one command and its results.
- File ▸ Stop (⌘.) doesn't name it, as for batch Auto Exposure: per
  ui-redesign I4, jobs other than export, folder adds and imports keep their
  Stop in the Activity popover. No change.

**One change.** The toolbar shows a job's title on one line, never cut
(`toolbarStatusText`), so "Apply Preset ‹a long preset name›" would widen the
toolbar item. Give the measuring job a `toolbarTitle` fitted by
`ToolbarMetrics.statusLine(name: preset.name) { String(localized: "Apply Preset \($0)") }`
(the same "Apply Preset %@" key), shortening the preset's name in the middle as
Export does with its folder. The popover keeps the full title. "Paste
Adjustments" needs no fitting.

### DQ-4: the held pixels can't be made

Raised by code review, 2026-11-08. The render of the sampled image can fail: the
original was ejected or became unreadable after the photo opened. It only logged,
so the magnifier kept its dashes and spinner forever and a click did nothing, with
no word of why.

**Ruling: picking ends, as if Esc had been pressed, and the caption says why.**

- **When:** the render for the held pixels fails, and it is still the render
  picking is waiting for. That covers arming, and a later re-render while picking
  (Color Alignment or a decode setting changed, R30).
- **What ends:** the eyedropper turns off, the pointer goes back to the arrow, the
  magnifier and its inspector row go, and a replaced slot's effect comes back.
  Nothing is saved and there is no undo step. A suspended fringe map returns.
- **A click waiting for those pixels** is dropped, and the failure is reported once.
- **The caption** (§3), below the picking captions and above the fringe map legend:

  > The original could not be read. Make sure it's available, then pick again.

- **It stays until** the next arming, any change to the adjustments, or another
  photo. VoiceOver hears the same sentence once (§11). No Activity row: the person
  is at this control, and it is one photo (P4; §7's "This photo could not be
  measured." is the precedent).

Why end picking rather than stay armed: an armed tool promises that a click will
work (the crosshair, the magnifier, the caption's "Click a colored fringe"), and
here no click can. That differs from "almost no color", which stays armed because
the next spot may be fine. Trying again is one click on the eyedropper, which starts
a new render, so a disk that has come back just works.

**Not a failure:** pixels already held. They are in memory, so a volume ejected
after they are ready doesn't affect picking, and picks go on working from them.

This is not a requirements change. R20's "a click still picks" covers pixels that
are on their way; once picking has ended no click is waiting (R19). The photo's own
offline state in the Adjust tab (N1) is unchanged.

## 20. Pixel magnifier (R19–R36; OQ12, OQ13)

Designed 2026-11-08 against prd.md rulings 16–22. This section is the
magnifier's whole design; §1, §3, §4, §8, §11–§16 point here.

**HIG read on 2026-11-08:** Pointing devices ("Consider enhancing the pointer
experience by displaying custom annotations that provide useful information";
"Avoid displaying instructional text with a pointer"), Pop-up buttons ("a flat
list of mutually exclusive options"), Materials ("Don't use Liquid Glass in the
content layer"), The menu bar. The HIG has no page on a pointer-following
magnifier. Everything below that isn't quoted is judgment.

### Decisions

**OQ12, the name: Pixel Magnifier** (§1). "Loupe" is the one-photo view, and
"zoom" alone is the view's. It says what the thing shows, and names no fringe,
so it fits other tools (R34).

**OQ12, the look: a round picture beside the pointer, not on it,** with a small
plate of values fixed under the picture and no controls on it. The system
crosshair stays as the pointer (§4).

**OQ13, the level: no control on the magnifier.** The percentage pop-up the
owner asked for sits in the inspector, and three second paths lead to the same
level: keys `-` and `=` while picking, the photo's context menu, and View ▸
Pixel Magnifier (P2).

### Anatomy

```
       + ← the system crosshair, on the photo
          ╭──────────╮
        ╭─┘          └─╮
        │              │     picture, 128 pt across, in a 136 pt ring
        │     [▪]      │     [▪] the outlined pixel, always the center
        │              │
        ╰─┐          ┌─╯
          ╰──────────╯
       ┌────────────────┐    plate, 136 pt wide, 4 pt under the ring
       │R182 G 96 B231 L128│  line 1: the values
       │800%   Before edits│  line 2: the level, and the note or the refusal
       └────────────────┘
```

Fixed size in points on every display, no grip (ruling 22). At the starting
800% on a Retina display the picture is 32 photo pixels across; at 1600%, 16.

### Where it sits (R19, R29)

**Beside the pointer.** The composite (ring and plate, 136 × 176 pt) goes below
and to the right of the pointer, its nearest corner 20 pt from the hot spot on
each axis.

Why not centered on the pointer, as a system color sampler is: a ring covers
about 136 pt of photo and shows far less of it. At fit on a 24 MP photo on a
Retina display, 800% shows about 3 pt of the view to each side of the pointer,
so between 3 and 68 pt from it the person can see neither the photo nor the
magnified pixels. They would steer blind
toward a line that is a screen pixel wide. Centering would also put the
crosshair's arms on the outlined pixel, or force hiding the pointer, which
changes §4 for nothing. Beside it, the person aims on the real photo with the
precise pointer and reads the truth next to it.

- **At an edge it flips,** as a whole and at once: to the left past the right
  edge of the loupe's canvas, above the pointer past the bottom edge (8 pt inset).
  It returns only when the preferred side fits with 24 pt to spare, so it can't
  flicker at the threshold. The plate stays under the ring in every placement.
- **Every corner works (R29, AC24).** The composite is never clipped, because
  it is placed to fit the canvas. If the canvas is too small to fit it on any
  side, it is clamped inside the canvas, and may then lie under the pointer.
- It never crosses the inspector, film strip, caption or toolbar.
- It takes no clicks. A click whose pointer is over its drawing goes to the
  photo and picks (AC27).

### Picture, grid, outline (R20–R22, R29)

- **The outlined pixel is always the picture's exact center.** Zoomed out,
  where the pixel a click takes can differ from the middle of the screen pixel
  (§4), the picture re-centers on the pixel taken. The rule stays one sentence,
  "the middle square is what you get", the outline can't near the rim at any
  level (R22), and the picture is moving several photo pixels per pointer step
  there anyway.
- **Pixels are hard squares,** nearest-neighbor, their edges on device pixels,
  level ÷ 100 device pixels wide (R27, AC22).
- **Grid (R21): at 800% and 1600% only.** One device pixel, mid-gray at 30%
  opacity, 45% with Increase Contrast. A level is device pixels per photo pixel
  on any display, so the rule needs no backing-scale case. At 400% a one-pixel
  line would cover a quarter of each photo pixel. It goes rather than fades,
  since the five levels are discrete. The grid is drawn over the picture and
  isn't part of the "pixels drawn" that AC17 compares.
- **Outline: a two-tone square just outside the pixel.** A 1 pt white line
  around the pixel's exact edge, then a 1 pt black line around that, in points
  at every level (2 pt each with Increase Contrast). One tone always shows, over
  white, black or anything between (R33). It never covers the pixel itself, even
  at 100% where the pixel is one device pixel.
- **Beyond the photo or its crop (R29):** the app's surround color
  (`Palette.loupeBackground`), no pixels, and a one-device-pixel 50% gray
  hairline along the last drawn pixels, so a dark photo's edge can be seen. With
  straightening, a pixel is drawn only if its center is inside the crop; the
  edge is stepped. Quarter turns match the view.
- **Ring:** a 2 pt light line inside a 1 pt dark line, and a soft shadow. Both
  tones again, so it separates from any photo. Not glass: this sits in the
  content layer, and a material would tint what surrounds the pixels being
  judged.

### The plate (R23, R24, R26, R33)

An opaque dark plate, 8 pt corners, 36 pt tall. Opaque, because small numbers
have to read over any photo. Colors are fixed, not dynamic: the library window
is dark in every appearance.

| Line | Content | Type |
|---|---|---|
| 1 | Four columns, R, G, B, L: each a 10 pt letter (secondary) and a right-aligned 3-digit value | 11 pt monospaced digits, so nothing shifts as values change |
| 2 | Left: the level ("800%"). Right: the tool's note ("Before edits") or the refusal | 10 pt |

Both lines are always there, so the plate never changes size under a moving
eye. Line 2 carries data, never instructions (HIG Pointing devices).

| State | Picture | Line 1 | Line 2, right | Other |
|---|---|---|---|---|
| **Normal** | The pixels | Values, primary | "Before edits", secondary | |
| **Would be refused (R26)** | The pixels | Values, dimmed to secondary (primary with Increase Contrast) | `nosign` symbol and "Almost no color", primary | The outline is unchanged: it still marks the pixel tested |
| **Pixels not ready (R20)** | Surround color, mini spinner after 0.5 s (SMP §5) | "–" for each value | Nothing | A click still picks, by the same rule |

**Refusal (the product manager's flag).** With the snap gone, a click one pixel
beside a fringe at 100% is now on gray, and is refused. That is correct, and the
magnifier makes it knowable first: the word, the symbol and the dimmed numbers
change on the pixel that would be refused. There is no delay or smoothing, since
AC21 needs it true of that pixel, and the fixed layout means only text changes.
The click's own refusal (§4: caption, VoiceOver, eyedropper stays on) is
unchanged. The symbol and word carry it, so color is never the signal.

### Why it can differ from the photo (R25, ruling 19)

The picture and values are the pre-edit image; the photo around them and the
slot's swatch (§14 point 3) are as edited. After a strong grade, a fringe can be
pink in the photo, purple in the magnifier, and pink again as a swatch. That is
true and useful, but looks like a bug if unexplained, so the note **"Before
edits"** is always on the plate, for the tool's whole session: no condition to
compute, no flicker, and it sits where the puzzle arises. A raw's White Balance
and Profile are in that image (§19 DQ-1), so the phrase is slightly generous for
them. That is harmless: the case it explains is a difference, and those two
don't cause one.

### The level (R27, R28; OQ13)

Five levels: 100%, 200%, 400%, 800%, 1600%, written without a thousands
separator. One preference on this Mac (`pixelMagnifier.level`, `UserDefaults`,
as the app's other view settings), starting at 800%, any unknown stored value
read as 800%. Never in a stack, a library or an undo step (R31).

| Surface | What | When | Why it's there |
|---|---|---|---|
| **Inspector** | "Pixel magnifier" row with an `AppKitPopUp` of the five levels (§3), in `LabeledPopUp`'s layout | Only while a slot is picking | The owner's drop-down, showing the level. Keyboard Navigation and VoiceOver reach it. It's a pop-up because the levels are mutually exclusive (HIG) |
| **Keys** | `=` steps up, `-` steps down, no wrap. `+` counts as `=` on layouts that need Shift. Text fields keep the keys | Picking, loupe has the keyboard | Changes the level with the pointer still on the fringe, and the result visible. The same keys as the view's zoom, without ⌘. ⌘= / ⌘− are untouched (R32). `[` `]` are the rating |
| **Context menu (loupe)** | **Pixel Magnifier** ▸ the five levels, the current one checked, after Show / Hide Fringe Map | Listed only while picking | Pointer-only people, at the point of use. Picking stays on (§4). The magnifier stays where it was while the menu is open and updates when a level is chosen |
| **Menu bar** | **View ▸ Pixel Magnifier** ▸ Zoom In (`=`), Zoom Out (`-`), a separator, the five levels with the current one checked. After Zoom Out | Dimmed unless picking. Zoom In dims at 1600%, Zoom Out at 100%. The two key items also need the loupe to have the keyboard | P1, Help ▸ Search, Control-F2 at default settings. It's in View because it changes how something is viewed, unlike the fringe map's Adjust step. N10 doesn't apply: that is a mask's parameter, and this is an app-wide view setting |
| **VoiceOver (loupe canvas)** | Custom actions **Pixel Magnifier Zoom In / Out** | Listed when they can act, while picking | R33, AC28 |

Why there's no control on the magnifier: anything riding on it runs from the
pointer, and a magnifier held still to reach one would break R19.

The inspector row appears between the Fringe Map toggle and the caption, so
only the caption moves when it does. A person moving to it leaves the photo, so
the magnifier hides until they return; the row and the plate both show the level.

### When it shows

Shows when a tool is picking, the window is key, and the pointer is over the
photo: the same rect as the crosshair. No fade, in or out: it should feel
attached (R36), and Reduce Motion needs no special case.

| Situation | Behavior |
|---|---|
| Pointer over the surround, inspector, film strip, or leaves the window; window not key | Hidden; picking stays on (AC16) |
| Pick, Esc, moving to another photo, a crop session, entering review | Picking ends, so it goes (R19) |
| Pointer still; the photo pans, zooms, or the sampled image changes (Color Alignment, undo) | Updates to what a click would now take (R30) |
| Drag to pan | Stays and follows |
| Replacing a filled slot, Fringe Map suspended, a live frame on screen | No difference: it draws the sampled image, which never contains the slot's graying (§14 point 4) |
| Filling from the list | Never shown (AC16) |
| The pixels can't be made | Picking ends, so it goes; the caption says why (§19 DQ-4) |
| HDR photo | Standard range; values read 255 at the top (R23; prd Assumptions) |
| Window moves to a display of another scale | Same level, same point size, redrawn for that display (AC22, M3) |
| Touch alone on a touch-display Mac | No hover, so none shown; a tap picks by §4's rule |

### Built to be reused (R34)

The magnifier knows nothing about fringes. A tool gives it:

1. the **image to sample** (pixels, in the orientation the view shows);
2. its **pick rule**: from the pointer's position and the view's scale, which
   pixel a click takes;
3. a **verdict** for that pixel: fine, or refused with a short state string;
4. an optional **note** for line 2 ("Before edits"), or none.

The level preference, the keys, the menu items, the context submenu and the
inspector row are the magnifier's own, and a tool only says it is picking. The
row is one shared view that a tool places in its own inspector section. For the
fringe tool, 2 and 3 are `FringePicker`'s rule and `ColorFringes.neutralChroma`.

### What was left out, and the reference

- **No fade, resize, off switch, value copying or arrow-key nudging** (non-goals).
- **Clean room.** The reference shows function only. Unlike it: no thick dark
  ring (a thin two-tone edge), values on a plate outside the picture so they
  hide no pixels, a two-tone outline rather than a white square, no control on
  the object, and no resize grip. The words are this app's own.

### What has to change in what's built (engineer)

The picking path changes as ruling 18 says. **R1's snap and its test are
replaced, not kept beside this.**

- `FringePicker`: remove `snapRadius` and the search by radius. New rule (§4):
  at the view's 100% or closer, the pixel under the pointer, even if a neighbor
  is more colorful; zoomed out further, the most colorful photo pixel under the
  pointer's device pixel, ties going to the one nearest its middle.
  `sample(…radiusInWidths:…)` follows. The click and the outline call one
  function, so they can't disagree (AC18).
- `ColorFringesTests`: `pick(_:_:in:radius:)`'s default `radius: 3`, and the test
  "A click within 2 pixels of a thin fringe picks the fringe, a neutral spot is
  refused", go. In its place: at 100%, a click one pixel beside the fringe on the
  light ground is refused and a click on a fringe pixel beside a stronger one
  takes that pixel; at fit, the most colorful pixel under the device pixel; the
  neutral refusals stay. Anything else that clicks near a fringe through that
  helper now aims at a fringe pixel.
- `status.md`: the "R1 snap and refusal" row and the "Picking" line of "How it is
  built".
- `USER_GUIDE.md`, line 250. Replace "the pointer is a crosshair over the photo,
  the click takes the most colorful pixel within a few points of it (thin fringes
  are easiest at 100%, Z), and the slot then shows a swatch and the color's name."
  with:

  > the pointer is a crosshair over the photo, and the **pixel magnifier** beside
  > it shows the photo's own pixels, with an outline around the one a click takes
  > and that pixel's R, G, B and L values (0–255, Display P3). At 100% and closer
  > that is the pixel under the pointer; zoomed out further, the most colorful
  > pixel under it. The slot then shows a swatch and the color's name.

  After "the eyedropper stays on.", add:

  > When the magnifier reads **Almost no color**, a click there won't be taken.
  > It shows the photo before your edits, so its colors can differ from the photo
  > around it and from the slot's swatch. Change its zoom with the **Pixel
  > magnifier** pop-up under the slots, **View ▸ Pixel Magnifier**, the photo's
  > context menu, or `-` and `=` while picking; the app remembers it.

  The key table gets a row: `- and =` | (grid: empty) | "while picking a color,
  pixel magnifier zoom out / in".

## Revisions

- 2026-11-07: First version, against prd.md as approved 2026-11-07.
- 2026-11-07: Recorded the product manager's rulings in §17: RI-1 option A
  (prd R16a, AC13a), RI-2 option A (R10, R16, AC7, AC13), the two-group
  reading of R12 confirmed (R12, AC9), scene (a)'s defocused disc (AC1), and
  OQ3 closed. §10 now says "can't be measured (offline or unreadable)" and
  covers the loupe case, as RI-1's ruling words it. Status set to Designed.
  §18 Q1 is still with the owner.
- 2026-11-07: Designed the list of common fringe colors (prd ruling 15,
  R1a–R1c, OQ4) after the owner answered §18 Q1 ("It should go into this
  feature now"). Each slot row gets a ⋯ slot menu (Pick from Photo; the
  section "Common Fringe Colors" with Purple and Green; Clear), and the
  row's context menu holds the same items. The visible clear button is
  removed, and "Pick Again" is renamed Pick from Photo. A listed color shows
  and behaves exactly like a picked one, with no marker. Every fill sets its
  own starting Tolerance. The list works during a crop session and leaves
  the fringe map on. The no-pointer keyboard and VoiceOver path is in §11,
  with "keyboard alone" read as Keyboard Navigation or Full Keyboard Access
  on. New strings, engineer notes and debug hooks (`adjust fringe fill`,
  `contextmenu fringe`), and DR2a and DR2b. §1, §5, §6 (the dimmed tooltip),
  §9, §10 and §13 were touched to match. §18 Q1 is marked answered.
- 2026-11-08: Ruled the engineer's design questions in §19. DQ-1: option
  A (a raw's White Balance and Profile are the accepted exception to §14
  point 2), with the user guide's sentence given. DQ-2: one Activity row per
  command, a new plural summary line followed by the export's per-file lines
  and "And N more.". DQ-3: the command's own title confirmed, with a fitted
  toolbar title for Apply Preset. §10, §12 and §14 point 2 updated to match.
- 2026-11-08: Designed the pixel magnifier (prd rulings 16–22, R19–R36, OQ12,
  OQ13) in the new §20: named Pixel Magnifier; a round picture beside the
  pointer with a values plate under it and no controls on it; the level in a
  pop-up in the inspector while picking, with `-` / `=`, the context menu and
  View ▸ Pixel Magnifier as second paths. The 3-point snap is removed from §4
  (ruling 18), and §15, DR4 and the picking caption follow. §1, §3, §4, §8, §11,
  §12, §13 (the first custom chrome here, justified), §14 point 1, §15 and §16
  (DR15–DR21) are revised.
- 2026-11-08: Ruled DQ-4 (§19, from code review): when the held pixels can't be
  made, picking ends and the caption says why. §3, §8, §11, §12, §20 and DR22
  follow.
- 2026-11-08: §4's Esc row now says what was built and confirmed for review
  finding F2: Esc cancels picking from anywhere in the library window, and text
  fields, open menus, sheets and popovers keep their own Esc.
