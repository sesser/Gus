# Spot healing and cloning: design

Owner: apple-ui-designer. Date: 2026-11-18. Issue: #86 (slug `healing`).
Status: Designed and built. The owner ruled the three requirements issues on
2026-11-18 (§18, recorded as R-1 to R-3 in §20); the engineer's two design
questions are ruled in §20 (DQ-1, DQ-2). Review: [`review.md`](review.md).

**Inputs.**

- Requirements: the issue body (the PRD, status Draft when read), cited as
  R1–R16 and AC1–AC13. This document answers its designer open questions:
  where the tool sits, how size, feather, opacity and mode are set, the
  overlay and source handles, the keys, and the wording about paste and
  presets.
- Earlier records followed: `docs/UI_REDESIGN.md` (UIR §4 inspector, §6 menus,
  §10 accessibility), [`../ui-redesign/design.md`](../ui-redesign/design.md)
  (P1–P5, the §4 command map, N7, N8, D-Q5),
  [`../chromatic-aberration/design.md`](../chromatic-aberration/design.md)
  (CA §4 picking gesture, §8 states, §11 accessibility: the closest
  precedent for a tool that works on the photo),
  [`../side-by-side-comparison/design.md`](../side-by-side-comparison/design.md)
  (no editing while comparing), [`../edit-history/design.md`](../edit-history/design.md),
  `docs/archive/PHASE6_PLAN.md` (the mask overlay and the Masks heading).
- Code read on `feature/healing`: `Views/MasksSection.swift`,
  `Views/AdjustView.swift`, `Views/AdjustControls.swift` (`AdjustSection`,
  `SectionHeader`), `Views/LibraryCommands.swift` (the Adjust menu),
  `Views/LibraryMenuContext.swift`, `Loupe/MaskOverlayView.swift`,
  `Loupe/LoupeView.swift` (`LoupeController.handle`, the click route),
  `Model/MaskEditing.swift`, `Model/AdjustmentEditor.swift`,
  `Model/CullingAction.swift` (every bare key in use).
- HIG pages read on 2026-11-18 (markdown versions): Segmented controls,
  Pointing devices (custom pointers, touch on Mac, added October 2026),
  Keyboards. The Menus, Inspectors and Accessibility readings in the earlier
  design records are relied on where cited. Where the HIG is silent I say
  "judgment".

**Clean-room note.** The words below (Spots, Edit Spots, Heal, Clone, source,
Size, Feather, Opacity) say what the person does and are common nouns for
the task. The layout (one heading, a mode switch, three sliders, rings and a
connecting arrow on the photo) follows this app's own Masks, Crop and Fringe
patterns. The keys are chosen from what this app leaves free, not from any
other editor's.

## Summary of rulings

| # | Ruling |
|---|---|
| S1 | A new **Spots** heading in the Adjust tab, directly after Crop & Straighten, collapsed by default (§2) |
| S2 | One set of controls (Heal / Clone, Size, Feather, Opacity). They show the selected spot, or the next spot's values when none is selected. New spots start with the values last set (§3) |
| S3 | **Edit Spots** is one tool state of the loupe: click empty photo to add a spot, click a spot to select it, drag it to move, drag its ring to resize, drag its source to move the source (§4) |
| S4 | The source follows the spot when it moves; it is chosen automatically only when a spot is added or when **Choose Source Automatically** is used (§4, §5) |
| S5 | Every command is in **Adjust ▸ Spots ▸**. Bare keys: `H` Edit Spots, `V` Show / Hide Spot Overlay, ⌫ deletes the selected spot (§6) |
| S6 | The limit is told in the inspector (icon and text), the loupe caption, a beep and VoiceOver; the tool stays usable for selecting and deleting (§7) |
| S7 | Comparing: the whole Adjust tab is already replaced; the menu items dim and `H` does nothing (§8) |
| S8 | Spots are named in the Spots heading's own note as left out of paste and presets, in the Masks heading's wording (§11) |
| S9 | Overlay: white rings with a dark hairline, solid for Heal and dashed for Clone, the selected spot's source drawn as a ring with a cross and an arrow to the spot (§4) |

## 1. Terms

| Term | Meaning | Why this word |
|---|---|---|
| **Spots** (heading) | The retouching tool | The PRD's word; plain. "Retouch" or "Heal" would name one of the two modes |
| **spot** | One circular fix: a place, a size, a source, a mode | A dust spot is the common case; "patch" would collide with the source |
| **Heal**, **Clone** (modes) | Heal blends the copied texture into the surrounding tone and color; Clone copies it as it is | The PRD's names (R2). Segment labels are read as names of the two kinds of spot ("a Heal spot"); see §3 on the HIG's noun rule |
| **source** | The circle the spot copies from | The PRD's word; "sample" is used elsewhere in the app for picking a color |
| **Edit Spots** | The toggle and menu item that turns the tool on | Parallel to **Crop** / **Finish Cropping** (title follows state in the menu, bezel shows state on the button) |
| **Size**, **Feather**, **Opacity** | The spot's radius, edge softness and strength | Size and Feather are Paint's words for the same ideas (P5, one term for one thing) |

In sentences, VoiceOver and the user guide: "spot", "source", "heal",
"clone" in lowercase as common nouns (P5).

## 2. Where it lives

**A new heading, Spots, between Crop & Straighten and Light.**

```
Presets · Crop & Straighten · Spots (new) · Light · Tone Curve · Color Mixer ·
Color Grading · Details · Lens · Masks · Effects
```

Collapsed by default, remembered like every heading (`adjust.section.spots`).

Why here:

1. **It is a picture fix, not a look.** Dust and blemishes belong to the
   photo, not to the tone and color choices after them. The Adjust tab is in
   workflow order, not render order (`AdjustView`), and people clean the
   frame before they grade it. Crop & Straighten and Spots are the two
   headings that change what is in the frame, so they sit together at the top.
   The renderer happens to agree (R5), which is a coincidence, not the reason.
2. **Not inside Masks.** A mask is a region that gets a *local adjustment*;
   a spot copies pixels. Putting spots in the Masks list would give them
   rows, names and per-mask sliders (Exposure, Contrast…) that mean nothing
   for them, and up to 100 rows. They are objects on the photo, not rows.
3. **Not a toolbar item or a sheet.** The Mac toolbar is for navigation and
   the commands used on every photo; tools with parameters live in the
   inspector beside the photo (HIG Inspectors: show controls for the
   selected item next to the content), the way Crop does. A palette-only
   toolbar item for the toggle is added as a second path (§6).
4. **Collapsed by default** because most photos never need it, and the
   heading is one 28 pt line. It expands itself when the tool is started
   from a menu, a key or the loupe's context menu (§6), which also shows the
   inspector and the Adjust tab, as Show Sharpening Map does.

The heading header uses the existing `SectionHeader`: a **check box** (turn
the spots off and on to compare; the operation's `isEnabled`, ruling R-2), the
overlay **eye** and the heading's **reset** in the trailing slot. The reset's
tooltip and menu title are "Delete All Spots" (the thing being reset is a
set of objects, so the title says what happens). Its context menu is the
standard one (Turn Off / On, Delete All Spots, Collapse All, Expand All).

## 3. Inspector layout

```
Spots                                      [✓]  👁  ⟲      ← 28 pt header
[ ◉ Edit Spots ]                                            ← toggle, bezel on while the tool is on
Spot 3 of 12                                   [🗑] [⋯]     ← or "New spot"
[            Heal            |           Clone           ]   ← full-width segmented control
Size      ─────●────────────────────────   [ 0.6 ]
Feather   ─────────●────────────────────   [  50 ]
Opacity   ───────────────────────────●──   [ 100 ]
(state caption, 11 pt secondary, wraps)
Presets and Paste Adjustments leave spots out.
```

| Part | Spec | Basis |
|---|---|---|
| Toggle | `AppKitButton(title: "Edit Spots", symbol: "bandage", style: .toggle(isOn:))`, leading, the push-on / push-off bezel Original, Sharpening Map and the fringe eyedroppers use. Tooltip "Click spots in the photo to heal or clone them (H)". Dimmed in a crop session ("Finish cropping to edit spots.") | I15: toggles share one look; the bezel, not a tint, shows the state. `bandage` is an SF Symbol (SF Symbols 3 and later); the engineer confirms it in the SF Symbols app and otherwise uses `circle.dashed` |
| Context row | 11 pt secondary, left: **"New spot"** with nothing selected, **"Spot 3 of 12"** with one selected (placement order). Right: `trash` (borderless `AppKitButton`, 22 pt, dimmed with nothing selected, tooltip "Delete Spot") and a ⋯ `AppKitMenuButton` ("Spot commands") | Says what the controls below act on (S2). The mask rows' ⋯ and the Remove-from-Mask button are the precedents |
| ⋯ menu | Choose Source Automatically · Select Next Spot · Select Previous Spot · separator · Delete Spot · Delete All Spots. Items that need a selection dim without one | P2: a second path to each menu-bar command, same titles |
| Mode | `AppKitSegmented`, two segments, **Heal** and **Clone**, no row label (HIG Segmented controls: "A segmented control that displays text labels doesn't need introductory text") | See the note below |
| Sliders | `AdjustSlider` at `SliderRow.height`, labels in the 80 pt column. **Size**: percent of the photo's longer side, one decimal, the radius, exactly Paint's Size unit and meaning so the same number draws the same ring. **Feather** 0–100, default 50. **Opacity** 0–100, default 100, `.plain`. Double-click and the row's context menu reset to the default | UIR §4 row grid. Resolution-independent units, because the same dust is twice as many pixels on a 54 MP file and the stored value is a fraction of the long edge |
| Notes | The state caption (below), then the paste note, both 11 pt secondary | |

**Why a segmented control for Heal / Clone, and the noun rule.** The two
modes are mutually exclusive, there are two of them, and the person needs to
see the current one and flip it in one click: a segmented control, not a
pop-up (the pop-up hides the state behind a click) and not a check box (a
mode is not a yes/no for a feature). The HIG also says "Use nouns or noun
phrases for segment labels"; Heal and Clone are verbs. This is a deliberate,
small departure: they are the names of the two kinds of spot (a Heal spot,
a Clone spot), the row label would only repeat them, and there is no better
noun for either that a person would recognize ("Blend" and "Copy" are
vaguer). It is judgment, not Apple policy. Tooltips on both segments
(HIG macOS: "provide one for each segment"): "Blend the copied texture into
the surrounding tone and color" and "Copy the source exactly as it is".

**One set of controls, two meanings, said out loud (S2).** The controls act
on the selected spot. With none selected they set the next spot. The context
row names which ("New spot" or "Spot 3 of 12"), so a slider never silently
changes meaning. **New spots start with the values last set** (by the
controls, or by dragging a ring's size): the dust task is "set the size
once, click twenty times", and a spot you just resized to fit a blob is the
best guess for the next one. Selecting an older spot does not change what
the next one gets; only editing does. The values are kept as app preferences
(`spots.mode`, `spots.size`, `spots.feather`, `spots.opacity`, generic keys),
not in the photo, like the pixel magnifier's level. The first-run values are
Heal, Feather 50, Opacity 100, and a Size the engineer sets so that a plain
click on a typical dust speck at 24 MP heals it with no slider move (the
fringe precedent, CA R1c).

The Size range must reach a few pixels of dust at 24 MP (about 0.1 percent)
and a large blemish (about 10 percent), with one arrow-key step in the
field of 0.1. The engineer proposes the numbers.

### The state caption (one role at a time, in this priority)

| State | Caption |
|---|---|
| A click found no source (§5) | "There's no clean area nearby to copy from. Try a smaller size, or click somewhere else." |
| At the limit (§7) | "This photo has 100 spots, the most it can have. Delete one to add another." (with `exclamationmark.triangle`) |
| Selected spot's source is outside the crop | "This spot's source is outside the crop. Drag the spot, or choose a source automatically." |
| Editing, overlay hidden | "The overlay is hidden, so a click adds a spot. Show the overlay to select one." |
| Editing, a spot selected | "Drag the spot to move it, or drag the circle it copies from. Press Delete to remove it." |
| Editing, none selected, no spots | "Click a dust spot or blemish in the photo. Press Esc when you are done." |
| Editing, none selected, spots exist | "Click the photo to add a spot, or click a spot to change it. Press Esc when you are done." |
| Not editing, no spots | "Choose Edit Spots, then click a dust spot or blemish in the photo. It is filled from a clean area nearby." |
| Not editing, spots exist | "12 spots." (plural forms; "12 spots, 2 outside the crop." when some are) "Choose Edit Spots to change them." |

The count is spelled out in the last row because spots are invisible while
the tool is off, and a photo that has been retouched should say so.

## 4. The tool on the photo

### Starting and stopping

- **Edit Spots** (button, `H`, Adjust ▸ Spots ▸ Edit Spots, the loupe's
  context menu, the palette toolbar item) turns the tool on. The title
  becomes **Finish Editing Spots** in menus (Crop's pattern).
- It is **loupe only**: dimmed in the grid and in review (the inspector is
  hidden there, and editing is out of scope for culling). Entering review,
  starting a crop session, starting a comparison, moving to another photo
  and closing the loupe all turn it off. It is never an undo step and never
  stored.
- It is **one on-photo tool at a time** (the app's rule for Paint, Pick
  Colors, the fringe eyedropper and crop): turning it on ends the sharpening
  and fringe maps, a fringe pick, mask painting and color picking, clears the
  selected mask (its handles go away) and turns Show Original off. Choosing
  one of those, or selecting a mask, turns Edit Spots off. The last asked for
  wins, because each needs the photo on screen without another tool's
  overlay. Collapsing the Spots heading does not end it.
- **Esc backs out one level**, as the rest of the loupe does: crop session,
  fringe pick, maps, then **a selected spot (deselects)**, then **Edit Spots
  (turns off)**, then review, then the loupe.

### The pointer

Over the photo the pointer is the system **crosshair** (`NSCursor.crosshair`)
with a **ring** at its center showing the next spot's size, and an inner ring
at the end of the solid core when Feather is above 0 (the mask brush draws
the same two rings; `drawCursor`). The ring is solid for Heal and dashed for
Clone. Over an existing spot or one of the selected spot's handles the
pointer is the arrow, which says "a click selects here, not adds". Over the
surround (outside the photo) it is the arrow and a click does nothing. No
custom pointer image and no text with the pointer (HIG Pointing devices:
"Keep custom pointer shapes simple", "Avoid displaying instructional text
with a pointer").

### Mouse

| Input | Result |
|---|---|
| Click on empty photo | Adds a spot there (mouse up, so a drag can pan; the loupe's 3 pt drag threshold) with the current mode, Size, Feather and Opacity, picks its source (§5), and **selects it**. One undo step, "Add Spot" |
| Click inside a spot's ring | Selects it (the topmost, the newest) |
| Drag inside the selected spot's ring (or inside any spot's ring, which selects it first) | Moves the spot. Its source moves with it, keeping the same offset; frames render while dragging, one undo step on release, "Move Spot" |
| Drag the small handle on the selected spot's ring (at 3 o'clock) | Resizes it, symmetric about its center. "Resize Spot". The source ring follows the size |
| Drag inside the source ring, or the cross at its center | Moves the source. "Move Spot Source" |
| Drag on empty photo | Pans, as in the loupe at any other time |
| Double-click | Adds one spot and does nothing more: a second click of a double-click is ignored, so a habit never leaves for the grid mid-task (CA §4) |
| Scroll, pinch, ⌥-scroll, `Z`, ⌘= / ⌘−, Fit | Work as always; the tool stays on |
| Right-click, Control-click | The loupe's context menu (§6); a right-click on a spot selects it first, as the grid does |
| Esc | §4 "Starting and stopping" |

Click priority: (1) the selected spot's source and resize handles, (2) the
inside of any spot's ring, newest first, (3) empty photo, which adds. So a
new spot cannot be added by clicking inside an existing ring; delete or move
the old one, or click just outside it. While the overlay is hidden nothing
is selectable and every click adds (§4 overlay), which is why hiding it is a
choice the caption names.

**Moving, resizing and the source (S4).** A spot's source keeps its offset
when the spot moves, so a source that was right stays right and nothing
jumps while the person drags. Where keeping it would put the source outside
the photo, it stops at the edge. When the spot grows until the source would
overlap it, the source is pushed outward along the same line until the two
rings touch. A dragged source is held to the same two rules the automatic
one follows: it cannot overlap its own spot and cannot leave the photo (the
handle stops at the limit while the pointer carries on; this is what the PRD's
edge scenario asks of "the source"). After moving a spot onto different
content, **Choose Source Automatically** (§6) gives it a fresh automatic
source, as one undo step.

**Resizing is not only a drag.** Size also has the inspector slider and
field, and the field takes typed values, which is the path without a pointer
(§12).

### The overlay (R4, S9)

Drawn only while the tool is on and the overlay is shown, in the content
layer over the photo (a view inside the image view, like `MaskOverlayView`),
so it zooms and scrolls with the photo and nothing goes on the glass layer.

| Element | Look |
|---|---|
| Spot ring | A circle at the spot's radius on screen, **1.5 pt white** over a **3 pt black at 35%** hairline, so it reads on a white sky (where dust is found) as well as on a dark one. Heal solid, **Clone dashed (4 pt on, 3 pt off)**. Never filled: the healed result stays visible inside it. Drawn no smaller than an 8 pt radius at fit, so a speck stays selectable (the heal itself keeps its true size) |
| Selected spot | Ring 2.5 pt, the feather's core as a thin inner ring (as the brush cursor), and a 6 pt-radius **resize handle** (white fill, black 60% stroke: the mask handle) on the ring at 3 o'clock |
| Source of the selected spot | A ring of the same size, solid 1 pt, with a **small cross at its center** (the thing to grab), and a 1 pt line from the source's center to the spot's ring ending in a **filled arrowhead** (8 pt) on the spot's ring, so "from here, to there" is shown by shape and direction. Only the selected spot's source is drawn (100 sources would bury the photo) |
| Other spots | Their ring only, no source |
| Hidden | Nothing is drawn or hit-tested; clicks add. Its state is the eye's (`eye` / `eye.fill`, accent tint when on, the Masks heading's eye), **Adjust ▸ Spots ▸ Show / Hide Spot Overlay** (`V`; DQ-1: not under View) and the loupe's menu. It starts shown each time the tool is turned on and is not saved |

**Increase Contrast:** the hairline goes to 60% and every stroke gains
0.5 pt. **Reduce Motion:** nothing animates. **Color is never the only
signal:** mode is solid or dashed, selection is weight plus a handle, the
source is a ring with a cross and an arrow. The overlay's white and black are
fixed drawing colors, not chrome, as the existing mask overlay's are.

**Touch-display Macs (HIG Pointing devices, touch):** a tap adds, selects or
grabs exactly as a click does; the handles' visible size is unchanged and
their grab distance is 10 pt for every kind of event (DQ-2: the app does not
tell touch from pointer; an earlier draft grew it to 22 pt on touch). Nothing depends on hover: the source
shows on selection, not on hover. Touch-and-hold opens the context menu.

### What a placed spot looks like in the render

The heal happens before color and tone (R5), so the healed pixels take every
later adjustment with the rest of the photo. A heal does not show a seam
when Exposure or a look-up table is changed afterwards. A spot is a circle in
every crop and rotation (uniform scale and rotation keep a circle a circle),
so the ring on screen is always round.

## 5. Automatic source: what the person sees (R3, R16)

The choice of patch is the engineer's. The visible behavior:

1. **A click adds, selects and shows the source.** With the overlay shown the
   source ring, its cross and the arrow appear with the spot at once, so the
   person sees where the patch came from without asking, and can drag it if
   the result looks wrong (the scenario in the PRD). That is the feedback;
   nothing is animated.
2. **With the overlay hidden** the click still adds and heals, and no ring is
   drawn. Showing the overlay shows the selected spot's source. Hiding the
   overlay is a person's choice to judge the result, not a reason to guess.
3. **VoiceOver** says where the source is: "Spot 12 added. Copied from the
   left." (eight directions, from the offset), after the Heal or Clone mode.
4. **No source can be found** (the spot is too big for the photo, or every
   clean candidate is taken or too close to the edge): **nothing is added**,
   no undo step, the system alert sound plays (`NSSound.beep()`, the Mac's
   refusal), the caption says "There's no clean area nearby to copy from. Try
   a smaller size, or click somewhere else." and VoiceOver reads the same.
   A beep alone would not say why; text alone is easy to miss while looking at
   the photo. The engineer confirms that this case can occur and what makes it
   (§15).
5. **The automatic choice prefers the part of the photo inside the current
   crop**, so a source the person can see is the default. A source outside
   the crop is allowed (it is the same picture content, and later crops don't
   change the heal, AC4), and the caption says when the selected one is.

## 6. Menu bar, keys, context menus, toolbar

All spot commands are in **Adjust ▸ Spots ▸**, a submenu placed after Rotate
Right and before New Mask ▸ (the heading's order), so the long Adjust menu
grows by one line (HIG Menus: use a submenu for a group of related items).
The submenu's title is always enabled (D-Q5). Items stay listed and dim when
they can't act (P1).

| Item | Key | Enabled when | Notes |
|---|---|---|---|
| **Edit Spots** / **Finish Editing Spots** | `H` (bare) | loupe, editable photo, not cropping, not comparing, not reviewing | Starts the tool, shows the inspector and the Spots heading expanded (as Show Sharpening Map shows Masking). Title follows state |
| **Show Spot Overlay** / **Hide Spot Overlay** | `V` (bare) | the tool is on | Judgment: `V` is free and, unlike `O`, can't be misread as Original (`\`) |
| separator | | | |
| **Spot Mode ▸ Heal, Clone** | none | the tool is on, or a spot is selected | Checkmarks show the selected spot's mode, or the next spot's. Same effect as the segmented control. One undo step when a spot is selected |
| **Choose Source Automatically** | none | a spot is selected | §4. One undo step, "Choose Spot Source" |
| separator | | | |
| **Select Next Spot**, **Select Previous Spot** | none | the tool is on, more than one spot is visible | Cycles the spots visible in the current crop, in placement order. No key: Tab must stay free to move keyboard focus out of the loupe |
| **Move Spot ▸ Left, Right, Up, Down** | ⌥← ⌥→ ⌥↑ ⌥↓ | a spot is selected | 1 screen point at the current zoom; ⇧ held makes it 10. A held key is one undo step ("Move Spot") when it is released |
| **Move Source ▸ Left, Right, Up, Down** | ⌥⌘← ⌥⌘→ ⌥⌘↑ ⌥⌘↓ | a spot is selected | The same, for the source; the same limits as a drag (§4). "Move Spot Source" |
| separator | | | |
| **Delete Spot** | ⌫ handled by the loupe, **no key shown** | a spot is selected | See below |
| **Delete All Spots** | none | the photo has spots | One undo step, no dialog (it can be undone; Reset All's precedent). Also the heading's reset |

**The option-arrow keys** are enabled only while the loupe has the keyboard
(the bare-key rule, UIR §6), because ⌥← and ⌥→ mean "word left, word right"
in every text field and a menu key would steal them. Arrows themselves keep
moving between photos and are **not** repurposed: a person who selects a
spot and then presses → to go on must not move a spot by accident (the HIG
says a held arrow moves the selected object by the smallest unit; here that
is the option-arrow, and the reason is that the loupe's arrows already mean
"next photo"). Judgment.

**Delete (⌫).** Bare ⌫ is already Remove from Album in the loupe, and the
shortcut rule (P3, one key one item: AppKit matches the first item with a key
equivalent even when it is disabled) allows only one menu item to carry it.
So: while the tool is on and a spot is selected, the loupe handles ⌫ before
the menu and deletes the spot; **Remove from Album is dimmed in that state**
so the menu never offers what the key won't do; the Delete Spot item shows no
key equivalent; the user guide names ⌫. This is the one key that has no menu
item showing it. It is a second path to a command that is in the menu, which
is what the HIG asks of shortcuts. ⌘⌫ stays Remove from Library and is not
used.

**Keys not added.** There is no key to change the mode, the size or to add a
spot: the HIG says to define shortcuts "for only the most frequently used"
commands, and these have the segmented control and the slider. If sizing by
the inspector proves slow in real dust work, `-` and `=` (free while the tool
is on, as the pixel magnifier uses them while picking) are an addition, not a
redesign.

### Context menus (P2: leave out what can't act)

| Where | Items |
|---|---|
| Loupe, tool off | The existing loupe menu, plus **Edit Spots** after Crop |
| Loupe, tool on, pointer not on a spot | **Finish Editing Spots**, **Show / Hide Spot Overlay**, and the rest of the loupe's menu |
| Loupe, tool on, on a spot (selects it first) | **Heal**, **Clone** (checkmarks) · **Choose Source Automatically** · **Delete Spot**, then separator, then the items above |
| Spots heading | Standard: Turn Off / On, Delete All Spots, Collapse All, Expand All |
| Context row, ⋯ | Above (§3) |

### Toolbar

**Palette only, off by default**: **Edit Spots** (`bandage`, the toggle's
on-state like Crop's), in Customize Toolbar. Not a default item: a tool used
on some photos does not earn a place in the default bar (UIR §5, Crop's
precedent).

## 7. The limit (R10, S6)

At 100 spots:

- The tool **stays usable**: selecting, moving, resizing and deleting
  existing spots are what the person needs to get out of the limit.
- A click on empty photo **adds nothing**, plays the alert sound, and the
  inspector's caption becomes the limit text with a warning symbol and the
  words (never color alone). The context row reads "100 spots" with the same
  symbol instead of "New spot".
- The loupe's caption line shows a badge **"Spot Limit"** (`CaptionBadge`,
  tooltip "This photo has 100 spots, the most it can have. Delete one to add
  another.") while the tool is on and the limit is reached, because the
  person's eyes are on the photo, not the inspector.
- VoiceOver announces the sentence once per refused click.
- A stack **over** the limit (101 or more, from a newer build or a hand edit),
  an unreadable one, or one from a newer version is never written over;
  the Adjust tab shows the existing **Can't Edit This Photo** state. The
  existing wording for exceeding limits is extended: "These edits hold more
  masks, brush points or spots than this version of %@ allows. Editing is
  off so they are not lost."

## 8. Other states and tools

| Situation | Behavior |
|---|---|
| **Comparing side by side** (R13, AC11) | The Adjust tab is replaced as a whole by the existing **Not Available While Comparing** state with its Stop Comparing button, so there is no Spots heading to dim. All Spots menu items are dimmed (`!isComparing`, as Paste and Apply Preset are); `H` and `V` do nothing in a comparison (its key handler doesn't know them); spots still **render** in each pane. Starting a comparison turns the tool off |
| **Crop session** | The toggle is dimmed with its tooltip, the tool is off (the crop shows the whole photo and its own handles), the sliders still set the next spot's values as other sliders do in a crop session. Menu items dim |
| **Show Original** (`\`) | Turning the tool on turns Show Original off, so the person edits the photo being edited. Spots don't render in the original |
| **Sharpening map, fringe map, fringe pick, Paint, Pick Colors, a selected mask** | One on-photo tool at a time (§4) |
| **Review mode** | Tool off, items dimmed; the inspector is hidden there |
| **Video, offline, unreadable stack, loading** | The Adjust tab's existing states (UI redesign N1): no controls |
| **Spots outside the crop** | Not drawn and not selectable; counted in the caption ("12 spots, 2 outside the crop.") and deleted by Delete All Spots. Reached again by Reset Crop or a crop session |
| **Monochrome, HDR, RAW+JPEG pair** | Nothing special. A pair's two files have their own spots (R12); the inspector says nothing about it, as it doesn't for other edits |

## 9. Every state of the Spots heading

| State | Header | Tool toggle | Context row | Caption | Loupe |
|---|---|---|---|---|---|
| **No spots, tool off** | Check box hidden, reset dimmed, eye dimmed | Off | "New spot" | "Choose Edit Spots, then click…" | Unchanged; renders exactly as before (R6) |
| **Spots, tool off** | Check box on, reset enabled, eye dimmed | Off | "New spot" | "12 spots. Choose Edit Spots to change them." | Healed photo, no overlay |
| **Tool on, none selected, none placed** | Eye on | On | "New spot" | "Click a dust spot or blemish…" | Crosshair and size ring |
| **Tool on, spots, none selected** | | On | "New spot" | "Click the photo to add a spot, or click a spot to change it…" | Rings on every spot |
| **A spot selected** | | On | "Spot 3 of 12", trash enabled | "Drag the spot to move it…" | Selected ring with handle, source ring, cross, arrow |
| **Overlay hidden, tool on** | Eye off | On | | "The overlay is hidden…" | Crosshair and ring; no spot rings |
| **Source outside the crop** | | On | | The source caption | Arrow runs to the photo's edge, no source ring |
| **No source found** | | On | | The refusal caption until the next action | Nothing added, alert sound |
| **At the limit** | | On | "100 spots" + warning symbol | The limit caption | "Spot Limit" badge |
| **Spots turned off (check box)** | Check box off | Off or on | | As above; values keep and show secondary (`showsTurnedOff`); placing turns it back on | Photo without the spots; overlay still draws if the tool is on |
| **Crop session** | | Dimmed, tooltip | | | Crop frame |
| **Comparing** | The whole tab is replaced | | | | Two panes |
| **Review, grid** | Not shown | | | | |

## 10. Undo, History, reset (R7, AC6)

Each is one undo step and one History entry; the label is the undo action
name, stored as text (edit-history design):

| Action | Label |
|---|---|
| Click to add | Add Spot |
| Drag a spot; ⌥-arrow keys (a held key is one step) | Move Spot |
| Drag a source; ⌥⌘-arrow keys | Move Spot Source |
| Drag the ring handle | Resize Spot |
| Size, Feather, Opacity (a slider gesture, or a typed value) | Spot Size, Spot Feather, Spot Opacity |
| Heal / Clone (segment, menu, context menu) | Change Spot Mode |
| Choose Source Automatically | Choose Spot Source |
| Delete Spot, Delete All Spots (button, menu, ⌫) | Delete Spot, Delete All Spots |
| The heading's check box | Turn Off Spots, Turn On Spots |
| Reset All Adjustments | Reset All Adjustments (also clears spots) |

Not undo steps: turning the tool on or off, selecting, showing or hiding the
overlay, and the stored next-spot values. **Undo while the tool is on** keeps
it on and restores the spots; a selected spot that the undo removes is
deselected. **Reverting to a History entry** restores that entry's spots,
and the selection is cleared.

## 11. Paste, presets, copies and sidecars (R11, R12, R14, AC10)

- **The wording (S8).** The heading's note, always shown when it is expanded,
  in the Masks heading's words: **"Presets and Paste Adjustments leave spots
  out."** It is the last line of the heading's body, after the state caption,
  because the state caption is the one that needs reading while working;
  that is the only difference from the Masks heading, which puts it first.
- **Copy Adjustments** does not copy spots; **Paste Adjustments** and
  **Apply Preset** leave the target's spots as they are, on one photo or a
  selection. There is no new message in Activity: the rule is stated where
  spots are edited, as for masks. The preset save sheet's group list does not
  offer Spots (it is not a preset group); the heading's check box is not part
  of Copy or presets either.
- **Duplicate** gives the copy the original's spots, then the two are
  independent (R12); nothing in the UI marks it.
- **Sidecars and originals** are never written for spots (R14); no UI.

## 12. Accessibility and VoiceOver

### Keyboard

| Who | How |
|---|---|
| Default settings (Tab reaches text fields only) | Size, Feather and Opacity through their value fields (↑ / ↓ step, Return or Esc hands the keyboard back, `SliderRow`). The tool: `H`, or Adjust ▸ Spots from Control-F2 or Help ▸ Search. Select Next / Previous Spot, Spot Mode, Choose Source Automatically, Delete Spot and Delete All Spots from the menu. Move the selected spot or its source with the option-arrow keys |
| Keyboard Navigation or Full Keyboard Access | Tab reaches, in order: the heading's check box, Edit Spots, the trash button, the ⋯ menu, the Heal / Clone control (←/→ change it), Size, Feather and Opacity fields. Space activates buttons and opens the ⋯ menu |
| A whole fix without a pointer | Needs a place, which only a click or touch gives, the same limit as the fringe eyedropper (CA §11). **Adding** a spot needs a pointer. Everything after is possible from the keyboard: select with the Spots menu, move with ⌥-arrows, resize in the Size field, change mode, move the source, delete |

**Honest gap.** Adding a spot by keyboard alone is not designed here, because
a spot's place is the one value that has no number to type. If VoiceOver's
press on the canvas does not click at the VoiceOver cursor, a person who
cannot point cannot add spots at all. Ruled (R-3, 2026-11-18): accepted for
the first version, as picking a fringe color is; **Add Spot at Center of View**
is a possible follow-up, not part of this feature.

### VoiceOver

- **Canvas.** While the tool is on and the overlay shown, each spot visible in
  the crop is an accessibility element of the overlay (a button), in
  placement order. Label: "Spot 3, Heal, upper left" (the position in thirds
  of the visible photo); value: "Selected" or none; help "Press to select".
  Custom actions: **Select**, **Switch to Clone** / **Switch to Heal**,
  **Move Spot Left / Right / Up / Down**, **Move Source Left / Right / Up /
  Down**, **Choose Source Automatically**, **Delete Spot**; each action lists
  only when it can act. A press on empty canvas is a click at the VoiceOver
  cursor and adds a spot if the loupe's element does that (§15).
- **Canvas value** (`accessibility image`): "Editing spots, 12 spots, ‹photo
  value›" while the tool is on.
- **Inspector.** Toggle: label "Edit Spots", spoken as a toggle with its
  state, help "Click spots in the photo to heal or clone them". Context row:
  "Spot 3 of 12" or "New spot" as static text, read with the controls. Mode:
  "Spot mode", "Heal, selected". Sliders: "Spot size", "Spot feather", "Spot
  opacity" (the visible labels are shorter; Paint's Size and the masks'
  Feather exist, so the accessible names stay distinct in the rotor), and the
  fields "Spot size value" and so on. Trash: "Delete Spot". ⋯: "Spot
  commands", spoken as a menu button.
- **Announcements** (posted when the control that caused them wouldn't speak
  for itself): after an add, "Spot 12 added. Heal. Copied from the left.";
  after a delete, "Spot deleted. 11 spots."; after Delete All, "All spots
  deleted."; the refusal sentences of §5 and §7; after Choose Source
  Automatically, "Source chosen. Copied from the right."; after Select Next
  Spot, the spot's label.
- **Spot moves by action or key** announce nothing extra (the next read of
  the label gives the position).

### Contrast, motion, color, touch

See §4 (overlay: Increase Contrast, Reduce Motion, shape and weight rather
than color, touch hit areas). The caption's warning symbols come with text.

## 13. Strings

Added by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings`; none
contains the product name except the extended unreadable-edits sentence,
which already takes it as `%@`. Reuse an existing key and extend its catalog
comment where one exists (Size, Feather, Opacity, Delete Spot-like words).

| English | Where |
|---|---|
| Spots | Heading; Adjust ▸ Spots submenu; undo names through "Turn On %@" |
| Edit Spots, Finish Editing Spots | Toggle and menu titles; loupe context menu; palette item |
| Click spots in the photo to heal or clone them | Toggle tooltip and VoiceOver help |
| Finish cropping to edit spots. | Toggle tooltip in a crop session |
| New spot; Spot %lld of %lld; %lld spots | Context row; plural forms of the last |
| Heal, Clone | Segments; Spot Mode items; context menu; VoiceOver actions |
| Blend the copied texture into the surrounding tone and color; Copy the source exactly as it is | Segment tooltips |
| Size, Feather, Opacity | Slider labels (reuse "Size", "Feather") |
| Spot size, Spot feather, Spot opacity (+ " value") | VoiceOver names |
| Spot commands; Delete Spot; Delete All Spots | ⋯ menu, trash tooltip, heading reset tooltip, menu |
| Choose Source Automatically; Select Next Spot; Select Previous Spot | Menus |
| Spot Mode; Move Spot; Move Source; Left, Right, Up, Down | Submenu titles and items |
| Show Spot Overlay, Hide Spot Overlay | Menu, loupe context menu; eye tooltip "Show the spots and their sources" |
| Spot Limit | Loupe caption badge |
| The seven captions of §3 and the limit, no-source and source-outside-crop sentences | Inspector captions; VoiceOver for the refusals |
| %lld spots, %lld outside the crop. | Caption, plural forms |
| Presets and Paste Adjustments leave spots out. | The heading's note |
| Add Spot, Move Spot, Move Spot Source, Resize Spot, Spot Size, Spot Feather, Spot Opacity, Change Spot Mode, Choose Spot Source, Delete Spot, Delete All Spots, Turn On Spots, Turn Off Spots | Undo action names and History labels |
| Editing spots, %lld spots, %@ | Canvas value |
| Spot %lld, %@, %@ ; Selected | Spot element label (number, mode, position) and value |
| upper left, top, upper right, left, center, right, lower left, bottom, lower right | Position words |
| Spot %lld added. %@. Copied from the %@. | Announcement (number, mode, direction; the direction words left, right, above, below, upper left… ) |
| Spot deleted. %lld spots. ; All spots deleted. ; Source chosen. Copied from the %@. | Announcements |
| These edits hold more masks, brush points or spots than this version of %@ allows. Editing is off so they are not lost. | Replaces the existing `.exceedsLimits` text |

## 14. Custom chrome

One: the **spot overlay** (rings, handles, source cross and arrow, §4). No
system component draws editable handles on a photo; the app already has two
(`CropOverlayView`, `MaskOverlayView`) and this one is built the same way, as
plain drawing in the content layer, with the accessibility elements (§12)
standing in for the interaction a system control would give. Everything else
is an existing component: `AppKitButton` (toggle, trash, eye), `AppKitSegmented`,
`AdjustSlider`, `AppKitMenuButton`, `SectionHeader`, inspector caption text,
`CaptionBadge`, menu items, the system crosshair and arrow. Nothing goes on
the glass layer, and Liquid Glass is unchanged (it is for the controls
floating over content, not for annotations on the content).

## 15. Notes for the engineer (behavior, not code)

- **Editor state**: `isEditingSpots`, `selectedSpotID`, `showsSpotOverlay`
  and the next-spot template live next to `isBrushing` and `isSamplingColor`,
  mutually exclusive with them, the maps, `pickingFringeSlot` and a selected
  mask (§4); cleared by photo change, crop session, review, comparison and
  `finishSession`. Never persisted, never an undo step.
- **Group**: spots are one operation with `isEnabled`; a group `spots` in
  `Adjustments` so the check box, "Turn On %@" and `showsTurnedOff` work;
  excluded from copy, paste and the preset group list (R11); `isModified`
  drives the check box and reset; Reset All clears it.
- **The click route**: `LoupeScrollView.onClick` toggles zoom today. While the
  tool is on, a click goes to the spots overlay instead (the picker's closure
  at `LoupeView` line 230 is the model), drags pan, a second click of a
  double-click is ignored, placement is on mouse up. The overlay passes a click
  through only where nothing is hit and the overlay is hidden.
- **Keys** go in `LoupeController.handle` before `CullingKeymap`: `H`, `V`, ⌫
  (when a spot is selected), ⌥ and ⌥⌘ arrows, and the Esc ladder of §4. Key
  repeats of a held nudge coalesce into one undo step. Menu items that carry
  bare or option keys use the existing `canByKey` pattern; the menu state
  (`LibraryMenuState`) gains the editing flag, whether a spot is selected,
  the mode, the count, whether the overlay is shown and whether the limit is
  reached. Remove from Album's enablement gains `&& !spotSelected`.
- **Geometry**: spots are in the mask frame, so the overlay reuses
  `outputPoint(fromMask:)` and `maskPoint(fromOutput:)`. A circle in the mask
  frame is a circle on screen at every crop and straighten. Spots outside the
  crop are skipped by the overlay but counted.
- **Order and position.** The ring the person sees and the heal must agree.
  Where a decoder applies its own geometry first (the Fujifilm embedded lens
  correction, the Lens heading's alignment), say in `status.md` which frame
  the stored position is in and show that the ring lands on the same pixels.
- **Source rules** (§4, §5): keeps its offset when the spot moves; stops at the
  photo's edge; pushed out when the spot grows; a dragged source cannot
  overlap its own spot or leave the photo; the automatic choice prefers the
  visible crop; no source means no spot and a message. Confirm which cases
  produce "no source".
- **Live drag**: moving, resizing and a source drag render live frames; at
  100% they use the sharp-live path as masks do. Report the cost of a drag
  against a brush mask (the PRD's only performance wording).
- **Touch**: one 10 pt grab distance for every event (DQ-2); no touch detection.
- **Strings** `AdjustText.unreadableMessage(.exceedsLimits)` changes (§7), and
  its catalog comment says so.
- **photocli** names (spots, source, heal, clone) should follow this UI's words.

## 16. Debug-script hooks (so review and QA can check without screen recording)

The tab and canvas are checked with `buttons`, `hit`, `print` and
`accessibility image` as in CLAUDE.md. Proposed commands, named by the
existing pattern (`mask add`, `activity open`):

- `spots on | off`, `spots overlay on | off`
- `spot add <x> <y>` (unit coordinates of the photo as shown) and the
  refusal case, `spot select <n>`, `spot delete`, `spot clear`,
  `spot mode heal | clone`, `spot set size|feather|opacity <value>`
- `spot drag spot|source|size <x> <y>`, `spot source auto`, `spot nudge …`
- `spots print` (the spots, their frames, the selected one) and a
  `snapshot` that includes the overlay (the content layer renders; the glass
  panes stay blank, as CLAUDE.md says).

## 17. Acceptance checks for the designer's review

1. The heading is after Crop & Straighten, collapsed on a new photo, remembered, with check box, eye and reset.
2. Edit Spots shows the Adjust tab with the heading open; turning it off clears the selection; moving to another photo turns it off.
3. A click adds a spot with the last-set values, selects it, shows its source ring, cross and arrow; the heal shows inside the ring.
4. Heal draws a solid ring, Clone a dashed one; the selected spot's weight and handle differ.
5. Drag inside a ring moves the spot with its source; the ring handle resizes; a source drag stops at its own spot and the photo's edge.
6. Esc: deselect, then tool off, then the existing order.
7. ⌫ deletes the selected spot and Remove from Album is dimmed; with no spot selected ⌫ is Remove from Album as before.
8. The 101st click is refused with the alert sound, the caption, the "Spot Limit" badge and a VoiceOver sentence; selecting and deleting still work.
9. Every command of §6 is in Adjust ▸ Spots with the stated enablement and none dims wrongly in the grid, review, crop and comparing.
10. Comparing: the Adjust tab says so; `H` does nothing; spots still render.
11. The paste note is present and worded as the Masks heading's; paste and presets don't change the target's spots.
12. History labels read as §10; undo and revert restore spots and clear the selection.
13. Overlay legibility on a white sky and a dark foreground; Increase Contrast; Reduce Motion; the 10 pt grab distance (DQ-2).
14. VoiceOver elements, actions and announcements of §12 as far as `accessibility` shows them.

Manual checks for a person (M1…) are written into `review.md` after the build.

## 18. Requirements issues (ruled 2026-11-18)

Raised for the product manager; the owner ruled all three on 2026-11-18 (§20
R-1 to R-3). The text below is kept as the question that was asked.

**RI-1. A command to choose the source again (R3).** The PRD says the app
chooses the source on placing and the person can drag it. Moving a spot onto
different content leaves its source where it was (§4), so a way back to a
fresh automatic choice is needed: **Choose Source Automatically**, one undo
step, reusing the placement logic. It also gives keyboard and VoiceOver users
the only way to improve a source without dragging. Please confirm it is in
scope (it costs the engineer almost nothing) or tell me to take it out.
A "try another source" that cycles candidates would be a further follow-up,
not asked for here.

**RI-2. An on/off check box for the Spots heading (R6, R7).** Every other
heading has one, and it is the way to compare the photo with and without the
retouching (Show Original also hides every other edit). It is the operation's
`isEnabled` and adds a `spots` group that copy, paste and presets leave out.
Please confirm. If it is declined, §2, §3, §9 and §10 lose the check box and
"Turn On / Off Spots".

**RI-3. Adding a spot without a pointer (R1, R4).** R1 is a click, and the
HIG asks for keyboard access to what an app does. A spot's place has no
number to type, so a person who cannot point cannot add one unless VoiceOver's
press clicks at its cursor (to be shown by the engineer, §15). Recommended:
accept for this feature, as the fringe eyedropper does, and add **Add Spot at
Center of View** (then move it by the option-arrows) as a follow-up if the
owner wants it. Please rule.

## 19. Assumptions (stated, not blocking)

- The next-spot values are app preferences, not part of the photo (R11 says
  nothing stored in the photo beyond the operation).
- Placing on mouse up and dragging to pan with the tool on follow the fringe
  eyedropper (CA §4).
- A dragged source is held to the automatic choice's two rules (inside the
  photo, clear of its own spot); AC2 says "no source" overlaps or leaves, and
  the PRD's edge scenario says the same of "the source".
- Spot numbers "3 of 12" follow placement order and change when a spot
  before it is deleted; they are labels, not identities.
- `V` and `H` are free of any existing key (checked against `CullingKeymap`,
  `NavigationKey`, the comparison and magnifier keys and the menus).
- No new setting in Settings, no alert, no sheet; Activity is not used.

## 20. Rulings

### Owner rulings on the requirements issues (2026-11-18)

| # | Ruling | Where it is built into this design |
|---|---|---|
| R-1 | **Choose Source Automatically is in scope** (RI-1). One undo step, "Choose Spot Source", reusing the placement logic. A "try another source" command is not part of this feature | §3 ⋯ menu, §4 (moving and the source), §6 menu, context menus, §10 label, §12 action and announcement |
| R-2 | **The Spots heading has an on/off check box** (RI-2): the operation's `isEnabled`, with a `spots` group that Copy, Paste Adjustments and presets leave out (it is not offered in the preset save sheet's group list). Turning it off keeps the spots and their values, and shows them secondary; placing, moving or changing a spot turns it back on. The check box is hidden while the photo has no spots, as other headings' are when nothing is modified. Undo and History names: Turn Off Spots, Turn On Spots | §2 header, §9 states, §10 labels, §11, §15 group note |
| R-3 | **No pointer-free add in v1** (RI-3). Adding a spot needs a click or touch. Everything after is keyboard- and VoiceOver-reachable. **Add Spot at Center of View** is a possible follow-up, to be filed by the main session if the owner wants it; no menu item, command or text for it is in this design | §12 "Honest gap" |

Because R-2 makes the check box part of the design, the PRD should list the
`spots` group beside R11 (left out of copy, paste and presets), and AC10
should include "turning the check box off keeps the spots and the photo
renders without them". That is the product manager's edit, not mine.

### Design questions from implementation

Ruled 2026-11-18, on the engineer's report after step 6.

**DQ-1. Where Show / Hide Spot Overlay lives (`V`).** §4's overlay table said
View; §6's command map said Adjust ▸ Spots ▸. The engineer followed §6.

*Ruling: Adjust ▸ Spots ▸ Show Spot Overlay / Hide Spot Overlay, bare `V`.
§6 governs and §4 is corrected above.* Reasons:

1. **The overlay belongs to a tool, not to the photo's display.** It exists
   only while Edit Spots is on and shows that tool's own handles. The app
   already puts every such overlay with its tool in Adjust: Show / Hide Mask
   Overlay, Show / Hide Sharpening Map and Show / Hide Fringe Map are all in
   Adjust. View holds the things that change how any photo is shown (Show
   Original, zoom, the film strip, the inspector, Pixel Magnifier while a
   picker is on). One rule per kind of thing is the consistency principle (P5).
2. **Discoverability.** The item sits one line under Edit Spots, which is
   where a person looks for it, and its enablement (on only while the tool is
   on) reads the same as its neighbours.
3. **HIG.** The HIG describes View as the menu for how content is displayed
   and Apple's apps follow it; this is a judgment call, not an Apple rule, and
   the app's own precedent (1) decides it. Nothing else changes: the key, the
   titles, the eye and the loupe's context menu are as in §4 and §6.

**DQ-2. Touch hit areas (§4 said 22 pt on touch, built as 10 pt always).** The
engineer found no public AppKit way to tell a finger from the pointer.

*Ruling: keep one 10 pt grab distance (a 20 pt target around the 6 pt handle)
for every event, add no touch detection, and §4 and §15 are corrected above.*
Reasons:

1. **I can't verify a way to do it.** `NSEvent.subtype` has a `.touch` case,
   documented only as "A touch event occurred"; nothing I could read says a
   touch-display Mac reports it for a finger on a window. Branching on a signal
   that may never fire, in a build nobody here can try on a touch Mac, would be
   dead code that claims a feature. The HIG's own advice is to distinguish
   pointer and finger "only if it provides value" (Pointing devices), and its
   touch-on-Mac section (added October 2026) gives guidance on revealing
   hidden controls, not on hit-area sizes. So §4's 22 pt was my judgment, not
   Apple's number.
2. **The spot's other parts are already big.** The ring's whole inside moves
   the spot (never drawn under a 16 pt diameter, and larger as you zoom in),
   the source's whole ring grabs the source, and a tap on empty photo adds.
   Only the resize handle is small, and Size has a slider and a typed field
   and a spot can be nudged by menu, so nothing is reachable only through that
   handle.
3. **Touch-and-hold opens the context menu** and tap-to-select is the same
   code as a click, both from the system.

If the owner has a touch Mac and finds the handle hard to hit, the remedy is a
larger uniform grab distance (about 14 pt), not input detection (judgment).
If the PRD states a touch target size I did not see it (I could not read the
issue; see `review.md`): the product manager should say so.
