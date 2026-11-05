# Sharpening mask preview: design

Owner: apple-ui-designer. Date: 2026-11-05. Status: Designed. The Q4
answers are final (§14). The owner ruled on RI-1 and RI-2 on 2026-11-05
(§13), and prd.md R10, AC11 and the non-goals record the rulings. The
engineer's design questions are ruled in §15. The designer review is in
[`review.md`](review.md). Nothing is open.

**Inputs.**

- Requirements: [`prd.md`](prd.md) (Approved, owner rulings 2026-11-05),
  cited as R1–R13 and AC1–AC14. This document answers its Q4.
- Earlier design records: [`../ui-redesign/design.md`](../ui-redesign/design.md)
  (P1–P5, N7, I7, I15, the §4 command map) and `docs/UI_REDESIGN.md` (UIR
  §1 caption, §4 inspector, §6 menus, §10 accessibility). Masks and the red
  overlay are in `docs/archive/PHASE6_PLAN.md`.
- Code read at `be6be22`: `AdjustView.swift` (DetailControls, AdjustHeader),
  `AdjustControls.swift` (SliderRow, GroupLabel, `showsTurnedOff`),
  `AppKitButton.swift`, `MasksSection.swift`, `LibraryCommands.swift`,
  `LibraryMenuContext.swift`, `Grid/PhotoContextMenu.swift`,
  `Loupe/LoupeView.swift` (LoupeController keys and accessibility,
  LoupeCaption), `Loupe/MaskOverlayView.swift`, `Model/AdjustmentEditor.swift`,
  `Model/SuggestionActions.swift`, `PhotoCore/Edits/AdjustmentRenderer.swift`
  (sharpen, local sharpening), `Adjustments.effective`.
- HIG pages read on 2026-11-05 (markdown versions): Keyboards, Menus,
  Progress indicators, Accessibility.

**Clean-room note.** Nothing here comes from another editor. The owner's
reference shows the mask while a modifier is held during a drag. This design
does not use a modifier or a drag-scoped view at all (§2 says why). The name,
strings, placement and caption treatment are this app's own, and the
grayscale picture follows the owner's stated starting point (R1).

## 1. Name and terms

The view is called the **sharpening map**. It is a map of where sharpening
goes.

- "Sharpening Map" (title-style) is the name of the control, the menu items
  and the caption badge. In sentences and VoiceOver it is "sharpening map"
  (lowercase, a common noun), following P5.
- I did not call it a "mask". In this app "mask" already means a local
  adjustment (the Masks heading, New Mask, Mask Overlay, the red overlay). A
  "sharpening mask" sitting next to the Masks heading and the Mask Overlay
  item would give one word two meanings, which P5 rules out. "Map" is
  distinct, and it describes the picture: white where sharpening goes, black
  where it does not. Masking is still the slider's name, and the map is how
  you see Masking.
- "Preview" was rejected because it suggests the sharpened photo.

## 2. Interaction model (Q4: toggle, automatic, modifier, or a combination)

**Ruling: one persistent toggle. The map does not appear automatically, and
no modifier is involved.** The map stays on until the person hides it or
does something that needs the photo (§6).

Why:

1. **R6 only works with a toggle.** The exact full-resolution map arrives
   *after* input pauses. A view that lasts only during a drag or while a key
   is held goes away at the moment the trustworthy map would appear. Only a
   view that outlasts the gesture shows the refined result.
2. **R2 and R3 cover keyboard steps and typed values.** Each arrow-key step
   and each typed value is a committed change of its own (`SliderRow`). A view
   shown automatically "while Masking changes" would flash between photo and
   map on every key press.
3. **Option-drag is already taken.** AppKit's `NSSlider` uses Option-drag for
   fine stepping (`altIncrementValue`, which `SliderRow` sets). Taking Option
   would break that. Every other modifier-while-dragging choice has no
   convention behind it (HIG Keyboards: "Use modifier keys in ways that people
   expect").
4. **HIG Accessibility asks to minimize time-boxed interface elements.** It
   says: "Prefer dismissing views with an explicit action." A view tied to a
   held key is time-boxed by the hand.
5. **The primary scenario is show, adjust, hide.** The PRD describes it that
   way: show the map, raise Masking until the sky drops out, then go back to
   the photo.

R3 allows a modifier gesture as an extra path. I am not adding one: it would
be a hidden second path to the same toggle, and points 1 and 3 still apply.

The owner reviewed this on 2026-11-05 ("Toggle is fine"): a persistent
toggle named Sharpening Map, an Adjust menu item and a button under Masking,
with no shortcut.

## 3. Where the command lives

| Surface | What | Enabled when | Basis |
|---|---|---|---|
| **Menu bar** | **Adjust ▸ Show Sharpening Map / Hide Sharpening Map**, directly after Show / Hide Mask Overlay (the two "see a mask in the loupe" items sit together). The title follows the state | The loupe shows a photo whose adjustments can be edited (`canEditLoupePhoto`), no crop session, not reviewing. Dimmed in the grid, for videos, offline masters, unreadable stacks and while loading (R11, AC12). It is an ordinary item, not a bare-key item, so it works wherever focus is in the library window, including from a slider's value field | P1; HIG Menus, toggled items ("a changeable label that describes an item's current state"); same pattern as Show / Hide Mask Overlay (N7) and Show Original |
| **Inspector** | The **Sharpening Map** toggle button in Details ▸ Sharpening, on its own row directly under the Masking slider (§4). `AppKitButton` with `.toggle(isOn:)`: the accessory-bar push-on/push-off bezel shows the state, as Original and Crop do (UIR §4, I15) | Same as the menu item. While dimmed, its tooltip says why (§9) | P2; proximity to the slider it serves; precedent of the Original toggle |
| **Context menu (loupe)** | **Show Sharpening Map / Hide Sharpening Map**, after Show Original / Show Adjustments | Listed only when it can act (same conditions as the menu item); left out otherwise (UIR §7) | P2; mirrors Show Original's entry, so the photo itself always offers the way back from a gray picture |
| **VoiceOver (loupe canvas)** | Custom action **Show Sharpening Map / Hide Sharpening Map**, after Show Original / Show Adjustments | Same as the context menu | UIR §10: the canvas's actions match the loupe context menu |
| **Esc in the loupe** | Hides the map | The loupe has the keyboard and the map is shown | Esc already backs out one level at a time in the loupe (crop session, then review, then the loupe). The map becomes one more level. HIG Keyboards: Esc means "Cancel the current action" |
| **Keyboard shortcut** | **None** | — | See below |
| **Toolbar** | **None**, not even in the customization palette | — | The palette holds whole-photo modes (Crop, Original). The map is one step of setting one slider |

**Why no shortcut.** The HIG says: "Define custom keyboard shortcuts for only
the most frequently used app-specific commands." Show Mask Overlay, the
closest precedent, has none (N7). A bare key would not help: bare-key items
are off while the inspector has the keyboard, which is exactly where a
keyboard user changing Masking is. Every free Command combination either has
no mnemonic or adds a modifier to a familiar unrelated shortcut (⌘S, ⌘M, ⌘K,
⌘E…), which the HIG warns against. The keyboard paths in §8 meet R3 without
one. If on-screen use shows that people want a key, that is a separate
change. This is judgment: the HIG does not decide it.

**Showing the map from the menu, the context menu or VoiceOver also reveals
Masking.** It shows the inspector if it is hidden, switches to the Adjust
tab, expands Details, and scrolls the Masking row into view. Reduce Motion
turns that scroll into a jump. The map is only useful while Masking is in
reach, and the app already does this for Suggest Keywords (I7, which reveals
Info ▸ Keywords). Hiding the map leaves the inspector as it is.

## 4. Inspector layout

The Sharpening group in Details changes like this (the rest of Details is
unchanged):

```
Sharpening                                         [✓]
Amount      ──────●───────────────────   [  40 ]
Radius      ───●──────────────────────   [ 1.0 ]
Detail      ─────●────────────────────   [  25 ]
Masking     ───────────●──────────────   [  60 ]
[ Sharpening Map ]                                     ← toggle, 6 pt above
Judge Amount, Radius and Detail at 100% (Z) once the   ← caption, 4 pt above
change is saved. Sharpening Map shows Masking's effect
at any zoom.
Noise Reduction                                    [ ]
…
```

- **Button.** It is leading-aligned, like the inspector's other in-group
  buttons (Paint, Pick Colors). It sits directly under Masking so it reads as
  that slider's companion. Title only, with no symbol: no SF Symbol clearly
  means "map of where sharpening goes" (HIG Menus: "Don't display an icon if
  you can't find one that clearly represents" it), and the title is what
  VoiceOver and Voice Control use. When the Sharpening group is turned off,
  the button stays fully enabled (R10). Turning the group off greys the
  sliders' labels and values (`showsTurnedOff`) but never the button.
- **Caption under the button** (11 pt, secondary, wraps, like the hint it
  replaces). It has one of two roles:
  - **Map hidden: the hint.** It replaces "Sharpening is easiest to judge at
    1:1 (Z), once the change is saved." The new text keeps the advice for the
    other three sliders, which still need 100% and a saved change
    (`viewport-render-1to1`), and points to the map for Masking. It says
    "100%" instead of "1:1" because the View menu says "Zoom to 100%" (P5).
  - **Map shown: the legend** (§5). The hint is about judging the photo, and
    the photo is not on screen.

## 5. What the loupe shows

### The map

- The photo area shows the map **instead of** the photo. The frame is the
  same: the same crop, orientation, size and position, at the current zoom
  and scroll. Switching between photo and map never moves anything.
- **Neutral grayscale.** White means Masking lets full sharpening through,
  black means none, and grays are partial amounts (R1). There is no tint: the
  map must not look like a color cast, and it must never be confused with the
  red overlay of local masks.
- **Display mapping.** Mask value *v* is shown as the display-encoded gray
  *v*, so a mask of 0.5 looks like the interface's middle gray and equal steps
  in the mask look like equal steps in lightness. A mask written as linear
  light would make half-sharpened areas look nearly white, so partial amounts
  would not "read as in between" (R1). The values themselves are not changed
  (R4).
- **Standard dynamic range** (R12). The map is SDR, and the layer stays at
  standard range while the map is shown, so white is the interface's white.
  The HDR caption badge is hidden while the map is shown, because it would
  describe an image that is not on screen.
- The loupe surround (`Palette.loupeBackground`) is unchanged, and there is
  no border. Black regions at the photo's edge will merge with the dark
  surround. I accept that: the photo's shape is known, and an added frame
  would be custom chrome that only the map needs. If the designer review finds
  the edge hard to read on real photos, that is a follow-up change.
- **Value changes while the map is shown.** The map follows every change at
  the cadence of today's live frames: Masking (R2) and any other slider,
  because sharpening's input depends on them. When the Sharpening group is
  turned off, the map is computed from the stored (turned-off) Sharpening
  values, not the effective ones (R10; see §11).

### Showing, refining, hiding (R6)

| Moment | What is on screen |
|---|---|
| The map is turned on | The photo stays until the first map frame is ready, which takes no longer than a live frame. Then the map replaces it. The caption badge and the inspector legend change **with that frame**, so the caption never claims a map that is not on screen. The loupe is never blank |
| A value is changing (drag, key steps, typing) | The live estimate, at the same cadence and draft scale as the photo's live frames today. **No indicator.** The photo's own drafts are not marked either, and the person is watching the map change under their hand |
| Input has paused (about 150 ms, as for photo refinement today) | Refinement to the full-resolution map starts, at any zoom (R6). The estimate stays on screen until the exact map replaces it, with no blank or flash in between |
| Refinement is still running 0.5 s after the last input | A **small system spinner** (`ProgressView`, mini control size) appears in the caption right after the badge, until the exact map is on screen. It has no visible label (HIG Progress indicators: "Avoid labeling a spinning progress indicator"), a tooltip, and a VoiceOver label (§9). The 0.5 s delay keeps it from flickering when refinement is quick. The caption is where the loupe's status already lives (HIG: "Display a progress indicator in a consistent location") |
| The map is turned off | The photo with its current adjustments comes back at once: the last photo frame, or the cached rendition if nothing changed. It then refines as after any change today. The loupe is never blank |

No transition animates between photo and map, with or without Reduce Motion.
Frames swap in place, as live frames do today.

### Caption line

The badges are the existing `CaptionBadge`s on the right of the 28 pt
caption (UIR §1). The map's badge takes **Original's place in the order**
(Filtered, then Original or Sharpening Map, then HDR, then Offline). The two
are never shown together (§6).

| State | Badge | Tooltip |
|---|---|---|
| Map shown, sharpening applied | **Sharpening Map** | "Showing where Masking lets sharpening through instead of the photo: white is sharpened, black is not. Press Esc to see the photo again." |
| Map shown, nothing sharpened (§7) | **Sharpening Map · Not Applied** | "Showing where sharpening would go instead of the photo. No sharpening is applied now. Press Esc to see the photo again." |
| Exact map pending > 0.5 s | the badge above, then the spinner | spinner: "Refining the sharpening map" |

Why there is a badge and not only the gray picture: a black-and-white
conversion looks much like the map. The badge tells them apart, the same way
the Original badge separates the original from a photo with light edits.

### Legend

There is no legend drawn on the photo. The legend is the inspector caption
under the button, next to the slider being moved. The badge's tooltip and
VoiceOver also carry it.

| State | Legend (inspector caption) |
|---|---|
| Applied | "White areas are sharpened, gray areas in part, and black areas not at all." |
| Sharpening group turned off | "Sharpening is turned off. Turn it on to sharpen the white areas, and the gray areas in part." |
| Amount 0 (group on) | "Amount is 0. Raise it to sharpen the white areas, and the gray areas in part." |

The off state takes priority over Amount 0. These sentences describe the
controls, so they stay true when local masks sharpen too. When local masks
do still sharpen, §7 adds one sentence after them.

## 6. How the map interacts with everything else (R8, R9; Q4)

**One rule:** at most one alternate view is on the loupe at a time:
Original, the sharpening map, the red mask overlay, or a crop session. The
last one asked for wins. The map *suspends* the overlay and Show Original,
and hiding the map brings back whichever was showing (R8). Anything that
needs the photo or the mask handles on screen *ends* the map. Controls
always show what is on screen.

| Situation | Behavior | Basis |
|---|---|---|
| Show the map while the **red overlay** is on | The overlay is suspended. The eye button shows off and the menu reads "Show Mask Overlay", because the overlay is not on screen. The overlay preference is kept | R8, AC9 |
| Hide the map after that | The overlay returns, and the eye and menu show on | R8 |
| **Show Mask Overlay** (eye, menu) while the map is shown | The map ends and the overlay shows | Last asked wins |
| Show the map while **Show Original** is on | Original is suspended. The Original toggle, the `\` item and the caption show the map state | R8 |
| Hide the map after that | Original returns, **unless a value changed while the map was shown**. Any change ends Show Original, as it does today (`AdjustmentEditor.change`) | R8; existing rule |
| **Show Original** (`\`, toggle, menu, context menu, VoiceOver) while the map is shown | The map ends and the original shows. Pressing `\` again shows the adjustments, with the overlay if its preference is on | Last asked wins; AC9 |
| **Crop** (`C`, menu, toolbar, inspector) while the map is shown | The map ends and the crop session starts. It does not come back after Done | As Show Original today (`beginCrop`) |
| During a **crop session** | Show Sharpening Map is dimmed in the menu and inspector (tooltip says why) and left out of the context menu and VoiceOver actions | AC9 option "unavailable"; same as Show Original during crop |
| **Mask handles, brush cursor** | Hidden while the map is shown. Clicks and drags on the photo do not paint, sample colors or move handles (R8). Click-to-zoom, double-click to the grid, drag-to-pan and ⌥-scroll zoom keep working | R8, AC9; R5 (zoom works on the map) |
| **Paint** or **Pick Colors** on when the map is shown | Showing the map turns them off; the buttons go back to "Paint" and "Pick Colors". Pressing Paint or Pick Colors while the map is shown ends the map | Tools that work on the photo need the photo |
| **New Mask** / **Add to Mask** while the map is shown | The map ends, so the new shape's handles can be placed | Same reason |
| Selecting a mask row | No change: the map stays and handles stay hidden | Navigating the list does not need the photo |
| **Zoom** (Z, ⌘= / ⌘−, pinch, ⌥-scroll, toolbar Fit \| 100%) | The map stays. A new zoom gets the exact map for that zoom, with the estimate scaled until it arrives | R5, R6 |
| **Moving to another photo** (arrows, Home and End, film strip click, auto-advance after rating) | The map ends. The next photo shows as a photo, and the inspector button goes back to off | Like Show Original (`finishSession`). A map tells you nothing about the next photo's values, and culling a gray picture would be wrong (Q4) |
| **Film strip** | Unchanged. It always shows photos, never maps | PRD non-goal |
| **Review mode** | Entering review ends the map. In review Show Sharpening Map is dimmed, even with the inspector brought back with ⌥⌘I (tooltip says why) | R9, PRD non-goal |
| **Leaving the loupe** (grid) | The map ends | R9 |
| **Relaunch** | Off. The state is never stored | R9, R7 |
| **Volume goes offline / photo becomes uneditable** while shown | The map ends with the editing state | R11 |
| **Undo / Redo** while shown | The map follows the restored values. The toggle is not an undo step (R7) | R7, AC8 |
| **Hovering a preset or look-up table** while shown | The map shows the hovered values, as the photo would. When the hover ends, it goes back to the applied values. The map stays on (D-Q1, §15) | The loupe always shows the values under consideration, in whichever view is on |
| Culling keys while shown | They rate, flag and label the photo as usual. If Advance After Rating moves on, the map ends as for any move | — |
| Inspector hidden or Info tab chosen while shown | The map stays. The badge, context menu and Esc remain as ways back | The map is a view of the loupe, not of the inspector |
| **Esc** order in the loupe | Crop session, then map, then review, then loupe. The map can't coexist with crop or review, so in practice Esc hides the map first | Extends the existing one-level rule |

## 7. Amount 0 or Sharpening turned off (R10)

- The map **still shows Masking's selection**: where sharpening would go at
  these Masking, Radius and Detail values. Showing the map is never dimmed
  for these states.
- **"Not applied" state** (owner ruling RI-1, "Only when nothing sharpens";
  R10): shown only when nothing at all is sharpened. That means the global
  Amount is 0 or the Sharpening group is off, *and* no local mask in effect
  (turned on) has Sharpness above 0. Then:
  - The badge reads **Sharpening Map · Not Applied** with its tooltip (§5).
  - The legend gives the reason and the next step (§5).
  - VoiceOver's value and its announcement say so (§8).
- **When local masks still sharpen** (Amount 0 or the group off, plus at
  least one mask in effect with Sharpness above 0), saying "not applied"
  would be false. The view stays in its **normal state**: the badge is plain
  **Sharpening Map**, the tooltip, VoiceOver value and announcement are the
  applied ones, and the legend adds one sentence after the reason:
  "Masks with Sharpness still sharpen the areas they cover."
  - The sentence says only that local masks sharpen. It does not say they
    follow the map. With the group off they don't: local sharpening then
    ignores the user's Masking. That behavior is a PRD non-goal and roadmap
    Idea `local-sharpen-group-off` (owner ruling RI-2), and nothing in this
    UI may promise otherwise. The same sentence serves the Amount-0 case,
    where local masks do follow the map, so there is one string and no
    claim that depends on which case applies.
- Turning the last sharpening mask off, or setting its Sharpness to 0,
  switches to the not-applied state with the next frame, and turning one back
  on switches back.
- Raising Amount, or changing any Sharpening slider while the group is off
  (which turns the group back on, as today), switches the badge and legend to
  the applied state with the next frame.

## 8. Accessibility

### Turning it on and off without a pointer (R3, AC5)

| Who | Show | Hide |
|---|---|---|
| Keyboard, default settings (Tab reaches text fields only) | Adjust ▸ Show Sharpening Map through Control-F2 (menu bar focus) or Help search (⌘?, type "sharpening", Return). Then step Masking in its value field with ↑ / ↓ (⇧ for ×10), which `SliderRow` already supports | Esc in the value field hands the keyboard to the loupe, then Esc hides the map. Or use the menu item again |
| Keyboard Navigation or Full Keyboard Access on | Tab to the **Sharpening Map** button, which comes after Masking's value field, and press Space | Space on the button, Esc in the loupe, or the menu |
| VoiceOver | The button, the menu item (VO-M), or the loupe canvas's action **Show Sharpening Map** | The same, titled **Hide Sharpening Map** |
| Voice Control | "Click Sharpening Map" (the button's title is its name) | Same |

### VoiceOver

- **Button.** Its name is "Sharpening Map", and its on/off state comes from
  the push-on/push-off button (AppKit reports it as a toggle). Its help is
  the tooltip. The engineer confirms the spoken state on screen (AC5).
- **Loupe canvas.** While the map is shown, its value starts with the map
  ("Sharpening map, Picked, 13 of 87"), or "Sharpening map, no sharpening
  applied, …" in the §7 state. The label (file name and kind) is unchanged.
  This is what `accessibility image` prints (AC10).
- **Announcements**, posted on the canvas when the map shows or hides by any
  path except the button (the button speaks its own new state):
  "Showing the sharpening map." or "Showing the sharpening map. No sharpening
  is applied." when showing, and "Showing the photo." when hiding. When the
  map ends because of something else (moving to another photo, review, crop,
  Show Original), the existing announcement for that action is enough. The
  canvas value change covers the rest.
- **Refinement** is not announced: it changes no value a VoiceOver user acts
  on. The spinner has a label for anyone who lands on it.
- Masking's value is spoken as today (formatted value).

### Increase Contrast, Reduce Motion, color

- **Increase Contrast.** The map does not change: it already runs from pure
  black to pure white, and R4 forbids reshaping its values. The badge,
  legend, button and spinner are existing system or `Palette`-dynamic
  elements and follow the setting as they do now. No new colors.
- **Reduce Motion.** There is no photo-to-map transition in any mode. The
  scroll that reveals Masking (§3) jumps instead of animating. The system
  spinner is unchanged (it is a progress indicator, not decoration).
- **Color.** The map is achromatic and its state is carried by text (badge,
  legend, button state, VoiceOver), never by color (HIG Accessibility:
  "Convey information with more than color alone").
- **Hit target.** The small push button is at least the 20 pt minimum
  height (UIR §10, HIG Accessibility).

## 9. Strings

All new, added by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings`.
None contains the product name, so none needs `%@` for a brand value.

| English (key) | Where | Comment for the catalog |
|---|---|---|
| Show Sharpening Map | Adjust menu; loupe context menu; loupe VoiceOver action | Shows where Masking lets sharpening through, in place of the photo |
| Hide Sharpening Map | Same three places | Returns the loupe to the photo |
| Sharpening Map | Inspector toggle button (Details ▸ Sharpening); loupe caption badge | Name of the view; one key, both uses |
| Sharpening Map · Not Applied | Loupe caption badge | Map shown while nothing is sharpened (Amount 0 or Sharpening off, and no mask in effect with Sharpness) |
| Show where Masking lets sharpening through, in place of the photo | Button tooltip and VoiceOver help, enabled | |
| Finish cropping to show the sharpening map. | Button tooltip, dimmed during a crop session | |
| Exit Review (F) to show the sharpening map. | Button tooltip, dimmed in review mode | "Exit Review" is the View menu item |
| Judge Amount, Radius and Detail at 100% (Z) once the change is saved. Sharpening Map shows Masking's effect at any zoom. | Inspector caption under the button, map hidden | Replaces the old Sharpening hint |
| White areas are sharpened, gray areas in part, and black areas not at all. | Inspector legend, map shown, sharpening applied | |
| Sharpening is turned off. Turn it on to sharpen the white areas, and the gray areas in part. | Inspector legend, group off | |
| Amount is 0. Raise it to sharpen the white areas, and the gray areas in part. | Inspector legend, Amount 0 | |
| Masks with Sharpness still sharpen the areas they cover. | Legend, added after the Amount-0 or group-off sentence when a local mask in effect has Sharpness above 0 | Owner ruling RI-1. Must not claim the masks follow the map (RI-2, `local-sharpen-group-off`) |
| Showing where Masking lets sharpening through instead of the photo: white is sharpened, black is not. Press Esc to see the photo again. | Badge tooltip, applied | |
| Showing where sharpening would go instead of the photo. No sharpening is applied now. Press Esc to see the photo again. | Badge tooltip, not applied | |
| Refining the sharpening map | Spinner tooltip and VoiceOver label | No visible label (HIG Progress indicators) |
| Sharpening map, %@ | Loupe canvas VoiceOver value | %@ is the photo's usual value, e.g. "Picked, 13 of 87" |
| Sharpening map, no sharpening applied, %@ | Loupe canvas VoiceOver value, not applied | Same argument |
| Showing the sharpening map. | VoiceOver announcement | |
| Showing the sharpening map. No sharpening is applied. | VoiceOver announcement, not applied | |
| Showing the photo. | VoiceOver announcement on hide | |

**Removed:** "Sharpening is easiest to judge at 1:1 (Z), once the change is
saved."

**Reused, with no new uses:** "Show Original", "Show Adjustments", "Show Mask
Overlay", "Hide Mask Overlay", "Paint", "Pick Colors", "Masking", "Amount".

## 10. Custom chrome

None. Every element is an existing component or pattern: `AppKitButton`
`.toggle` (the Original toggle), an inspector caption `Text` (the hint it
replaces), `CaptionBadge` (Original, HDR), a system mini `ProgressView`,
menu items, `ActionMenuItem`, and `NSAccessibilityCustomAction`. The map
itself is content (a rendered frame in the loupe's image layer), not chrome.
Nothing goes on the glass layer.

## 11. Notes for the engineer (behavior, not code)

- **State.** The map is a loupe view state next to `showsOriginal` and
  `showsMaskOverlay`, with "suspended" memory for those two (§6). It is never
  persisted, never in the edit stack, never an undo step, and never fed to
  the histogram, the preview cache or the grid (R7; the same rules as
  `frameHasOverlay`). Hiding it must not seed a cached preview from a map
  frame.
- **Values.** The map uses Masking, Radius and Detail from the stored values
  even when the Sharpening group is turned off. `effective` would reset them
  (R10). It must still equal the blend mask the renderer uses for those
  values (R4, AC2). With the group off, local sharpening ignores these
  values today (roadmap Idea `local-sharpen-group-off`, a PRD non-goal).
  Don't change that here, and don't word anything as if it were otherwise.
- **Not-applied test** (§7): global Amount is 0 or the group is off, and no
  turned-on mask has Sharpness above 0. One function, read by the badge, the
  legend, the VoiceOver value and the announcement.
- **Display.** Encode mask *v* as gray *v* in the display's transfer
  function (§5). Unit-test the conversion: 0, 0.5 and 1 give encoded 0,
  0.5 ± 1/255 and 1. Show it in standard dynamic range.
- **Menu state.** `LibraryMenuState` gains "map shown", "map not applied"
  and "can show map" (`canEditLoupePhoto && !isCropping && !isReviewing`).
  The menu, context menu, VoiceOver actions and the inspector button all
  read the same condition (P2).
- **Reveal** (§3): the I7 pattern (`showsInspector`, `inspectorTab = .adjust`,
  `InspectorExpansion` for Details), plus scrolling the Masking row into view,
  animated unless Reduce Motion is on.
- **Debug script.** One command to show, hide and toggle the map (for
  example `sharpenmap on|off|toggle`). `print` reports its state, and the
  badge text is reachable for AC8–AC10. Debug-script commands that change
  photos open an undo group (CLAUDE.md); this one does not change photos.
- **USER_GUIDE.md**: describe the map in the same change, using the terms in
  §1 and §9 (Sharpening Map, sharpening map, Masking, Esc to return). I will
  check its wording at review.

## 12. Acceptance checks for the designer review

| # | Check | How |
|---|---|---|
| DR1 | Menu item placement, titles and enablement: after Show / Hide Mask Overlay. In the grid it reads "Show Sharpening Map", dimmed. It is enabled on an editable loupe photo, and the title flips after `menupress`. It is dimmed for a video, an offline master and an unreadable stack (AC12), during a crop session and in review | `menuitems "Sharpening Map"` in each state |
| DR2 | Inspector: the "Sharpening Map" toggle is directly under Masking, its state follows the menu, it is enabled with Sharpening off or Amount 0, and when dimmed its tooltip gives the §9 reason | `buttons`, `print`; manual on screen (glass pane) |
| DR3 | Keyboard only with default settings: show from Help search, step Masking in its value field with ↑ / ↓, then Esc twice returns to the photo. With Keyboard Navigation on, Tab from Masking's value field reaches the button and Space toggles it (AC5) | Manual |
| DR4 | VoiceOver: the button speaks its name and state; the canvas actions include Show / Hide Sharpening Map; the announcements in §8 are spoken; `accessibility image` output starts its value with "Sharpening map" (AC5, AC10) | Manual; debug script `accessibility` |
| DR5 | The map is neutral gray, and in the same frame as the photo (snapshots of photo and map line up at fit and at 100%). The badge and legend match the state | `snapshot` (the content area renders) and `print` |
| DR6 | Partial amounts read as in between: mask 0.5 is the interface's middle gray | Engineer's unit test (§11) |
| DR7 | Refine on pause: no indicator during a drag; the spinner appears only when the exact map takes more than 0.5 s after input stops, and goes away when it arrives (AC7 covers the pixels) | Manual on a 24 MP raw at fit and at 400% |
| DR8 | §6 rules: overlay suspended and restored (AC9); Show Original suspended and restored when nothing changed, ended when Masking changed; `\` while shown ends the map; Crop ends it and dims it; Paint, Pick Colors and New Mask end it; handles hidden and a drag with a brush mask selected leaves the stack unchanged (AC9); zoom keeps it; an arrow key, a film strip click, review, the grid and a relaunch all end it (AC10) | Debug script per row; manual for the film strip |
| DR9 | §7, AC11's four cases, with the map shown. (a) Amount 0, no mask with Sharpness: badge "Sharpening Map · Not Applied", legend "Amount is 0…". (b) Group off, no mask with Sharpness: the same badge, legend "Sharpening is turned off…". (c) Amount 0, and separately group off, each with one mask in effect at Sharpness 50: badge "Sharpening Map", no "Not Applied" anywhere (badge, VoiceOver value, announcement), and the legend's reason followed by "Masks with Sharpness still sharpen the areas they cover." (d) Case (c) with that mask turned off: the not-applied state returns. In every case no wording says local masks follow the map | `print` (badge, legend), `accessibility image`; debug-script `mask add`, mask checkbox; manual |
| DR10 | Showing from the menu with the inspector hidden on the Info tab: the inspector appears on Adjust with Details expanded and Masking visible; hiding leaves the inspector alone | `menupress`, then `print` |
| DR11 | HDR photo on an EDR display: the map's white matches the interface's white, and the HDR badge is hidden while the map is shown (AC13) | Manual |
| DR12 | Increase Contrast: no new color and the badge still legible. Reduce Motion: no transition, and the reveal scroll jumps | Manual |
| DR13 | Strings: every §9 key present with its comment, the old hint removed, `LocalizationTests` pass, and `USER_GUIDE.md` uses §1's terms | `swift test --filter LocalizationTests`; reading |
| DR14 | Esc order in the loupe: map before review and loupe; Esc in a value field first hands the keyboard back | Manual; `key` in the debug script |

## 13. Requirements issues (ruled)

Both were ruled by the owner on 2026-11-05. prd.md records them (Rulings,
R10, AC11, non-goals). Nothing is open.

| RI | Ruling | Where this design applies it |
|---|---|---|
| RI-1 | "Only when nothing sharpens" (Option A). The not-applied state shows only when nothing at all is sharpened. When local masks still sharpen, the normal state stays and the legend adds one sentence | §7, §9 (the sentence), §11, DR9 (AC11's four cases) |
| RI-2 | "Roadmap item to decide" (Option A). Roadmap Idea `local-sharpen-group-off`; this feature does not change it (R13), and the PRD lists it as a non-goal | §7 and §11 point to it; the UI says nothing that promises local masks follow the map while the group is off |

The issues as raised:

1. **RI-1. R10 with local sharpening.** R10 says that with Amount 0 or the
   Sharpening group off, "it is clear that no sharpening is applied right
   now". The renderer still sharpens inside any turned-on mask whose
   Sharpness is above 0. At Amount 0 it does so through the global Masking,
   so the map applies to those masks
   (`AdjustmentRenderer`, "The global radius, detail and masking at the local
   amount"). Saying "no sharpening is applied" would be false then.
   - Option A: "Not applied" means nothing is sharpened at all (global and
     local). With local sharpening the badge stays "Sharpening Map" and the
     legend adds a sentence (§7). **Recommended**: it never says something
     untrue, and it costs one condition.
   - Option B: apply R10 literally, showing "Not Applied" whenever Amount is 0
     or the group is off, even when masks sharpen. Not recommended: the
     screen would contradict the photo.
   - Option C: say "global sharpening" in the UI. Not recommended: the app
     has no "global" term (P5), and it adds a concept to explain one edge.
2. **RI-2. A rendering finding: turning Sharpening off changes how local
   sharpening is masked.** `Adjustments.effective` resets a turned-off group
   to its defaults, so with Sharpening off, local Sharpness uses Masking 0,
   Radius 1 and Detail 25 instead of the person's values. Turning the group
   off "to compare" therefore makes masks with Sharpness sharpen noise they
   did not sharpen before. It is out of scope here (R13: no rendering change).
   - Option A: a roadmap item to decide whether local sharpening should keep
     the stored Radius, Detail and Masking when the group is off. That is a
     rendering change with a pipeline bump. **Recommended**.
   - Option B: accept it as intended (off means defaults everywhere) and
     explain it in the legend.

## 14. Answers to Q4 (final)

Final as of 2026-11-05. The owner confirmed the interaction ("Toggle is
fine"), and the RI rulings are applied above.

| Q4 item | Answer | Section |
|---|---|---|
| The interaction | One persistent toggle. Not automatic, no modifier gesture | §2 |
| Where the control lives | Adjust menu (after Mask Overlay); an inspector toggle under Masking; the loupe context menu and VoiceOver actions; Esc hides it. No shortcut, no toolbar item | §3, §4 |
| How the screen shows the map is on, and Amount 0 | The gray map, the caption badge "Sharpening Map" or "Sharpening Map · Not Applied", the inspector legend, and the VoiceOver value and announcements | §5, §7, §8 |
| Which state wins | The last one asked for. The map suspends the overlay and Original and gives them back when hidden; Crop, Paint, Pick Colors and new shapes end it; it is unavailable during crop and review | §6 |
| Whether it stays on when moving to the next photo | No: it ends, like Show Original | §6 |
| The Adjust tab hint | Reworded, with "100%" in place of "1:1" and a pointer to the map; replaced by the legend while the map is shown | §4, §9 |

## 15. Design questions from implementation (2026-11-05)

Raised by the engineer on `feature/sharpen-mask-preview` (fe33e97..cd08f25).
Both are ruled here. Owner rulings from the same day are recorded for
context and change nothing in this design: the histogram may go stale while
the map is shown (accepted), and the difference in where Masking cuts at fit
versus full size is its own roadmap Idea, outside this feature.

| # | Question | Ruling | Basis |
|---|---|---|---|
| D-Q1 | Look-up table and preset hover previews while the map is shown. (a) As built: the map follows the previewed values. (b) Hovering ends the map. (c) The map ignores hover and keeps the applied values | **(a), as built.** The map shows the hovered values, its badge and legend follow them (a preset with Amount 0 can show "Not Applied" while hovered), and it refines on pause like any change. When the hover ends, it returns to the applied values. (b) is rejected: a passive hover would end a view the person turned on, the kind of side effect HIG Accessibility warns about ("Prefer dismissing views with an explicit action"). (c) is rejected: hovering would do nothing visible, so the preview would look broken, and the map would disagree with the values the loupe is previewing. This keeps one rule: the map follows every value the loupe would show. A preset that sets Masking is exactly where the map helps. I read the PRD non-goal ("the mask in … preset or look-up table hover previews") as covering the preview *surfaces* (the preset tiles, the look-up table browser's pictures), which keep showing photos. The loupe is the map's own surface. If the product manager reads it otherwise, it is theirs to rule | §6 row "Hovering a preset or look-up table"; P5 (one rule); HIG Accessibility |
| D-Q2 | The Sharpening Map toggle's frame measured 20 pt high in one inspector layout and 24 pt in another | **Acceptable**, provided the drawn bezel matches the Original toggle's in the same window. Both heights meet the macOS minimum control size of 20 pt (HIG Accessibility). The concern is only consistency: if the 24 pt case is the bezel itself stretching rather than its hit area, pin the button to its intrinsic height. That is a manual check at review (review.md) | HIG Accessibility (20 × 20 pt minimum); UIR §4, I15 (inspector toggles share one look) |
