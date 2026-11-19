# Black & White module (film filters): design

Owner: apple-ui-designer. Date: 2026-11-18. Issue: #218 (slug `bw-module`).
Status: Designed. Three PRD wording points need the product manager (§18); none
blocks the engineer.

**Inputs.**

- Requirements: the issue body (the PRD, status Approved 2026-11-18), cited as
  R1 to R15 and AC1 to AC14. This document answers its designer open questions:
  where the heading sits, the check box, the five sliders, the quick-set
  control and its value, what a photo with no color shows, captions, menu
  commands, history labels and the strings.
- Earlier records followed: `docs/UI_REDESIGN.md` (UIR §4 inspector rows, §6
  menus, §10 accessibility), [`../ui-redesign/design.md`](../ui-redesign/design.md)
  (P1 to P5, N1 states, N10 "parameters are not commands", the §4 command map),
  [`../healing/design.md`](../healing/design.md) (the closest precedent for a
  new heading with a check box, a mode control, sliders and a state caption;
  its menu and history sections), [`../side-by-side-comparison/design.md`](../side-by-side-comparison/design.md)
  (no editing while comparing), [`../edit-history/design.md`](../edit-history/design.md).
- Code read on `feature/bw-module` (develop): `Views/AdjustView.swift`,
  `Views/AdjustControls.swift` (`AdjustSection`, `SectionHeader`,
  `GroupToggle`, `GroupLabel`, `SliderRow`, `AdjustText`), `Views/CurveEditor.swift`
  (`AppKitSegmented`), `Views/LibraryCommands.swift` (the Adjust menu),
  `Views/LibraryMenuContext.swift`, `Views/SpotsSection.swift`,
  `Model/AdjustmentEditor.swift` (`setEnabled`, `reset`), `Model/PresetActions.swift`
  (the Save Preset group list), `Edits/Adjustments.swift` (`Section`, `Group`,
  `isModified`, `isEnabled`, `effective`), `Presets/CameraRawMapping.swift`
  (what a Lightroom B&W preset does today).
- HIG pages read on 2026-11-18 (markdown versions): Segmented controls, Sliders,
  Menus. Earlier records' readings of Inspectors, Accessibility and The menu bar
  are relied on where cited. Where the HIG is silent I say "judgment".

**Clean-room note.** "Black & White", the five filter names and "filter" are
common photographic terms. The layout (one heading, a segmented control, five
slider rows, a caption) is this app's own Color Grading and Spots pattern. The
direction of each filter is film practice that R5 already states; the captions
below say it in plain words and are not taken from any other application.

## Summary of rulings

| # | Ruling |
|---|---|
| B1 | A new **Black & White** heading in the Adjust tab, directly after Color Mixer and before Color Grading, **folded by default** (§2) |
| B2 | The heading uses the standard `SectionHeader`: disclosure, title, check box, reset. Its check box is **always shown** and is the group's on/off switch. Checking it on a photo that never had the group switches the conversion on with all five sliders at 0 (§3.1) |
| B3 | Under the heading: a full-width **segmented control** (Yellow, Orange, Red, Green, Blue) for the quick-sets, then five slider rows, then one caption (§3) |
| B4 | The segmented control **shows** a filter only while exactly that quick-set is in effect; no segment is selected when the group is off or the sliders are a mix. It is derived from the sliders, never stored (§3.2) |
| B5 | The quick-set value is **100**: "the filter itself", the slider's end. If 100 looks too heavy, the engineer scales the filter's numbers, not the quick-set (§4) |
| B6 | The slider tracks are filled in the filter's **system color** (`systemYellow`, `systemOrange`, `systemRed`, `systemGreen`, `systemBlue`). It is the system slider's own track tint, not custom drawing; a *Should* with a plain fallback (§5) |
| B7 | A photo that already has no color: nothing is hidden or dimmed; the caption says the filters change nothing, **only** when the file is known to be monochrome (§6) |
| B8 | One new submenu, **Adjust ▸ Black & White ▸**: Turn On / Off Black & White, the five filters with check marks, No Filter. Loupe photo only; dimmed in the grid. No keyboard shortcut (§8) |
| B9 | History: the switch is **Turn On / Off Black & White** (the label every group's switch already has); every slider and quick-set change is **Black & White Filter**; the heading's reset is **Reset Black & White** (§9) |
| B10 | Moving any control of the group, or choosing a quick-set, while the group is off turns it on, in the same undo step (§3.1) |
| B11 | No Lightroom wording changes: the import report still says "Black and white (approximated)" (§10) |

## 1. Terms

| Term | Meaning | Why this word |
|---|---|---|
| **Black & White** (heading, group, submenu) | Turning the photo to gray by a steerable mix of its colors | The PRD's name. "Monochrome" is the technical word; photographers say black and white. The ampersand keeps the heading short in a 28 pt row |
| **filter** | A colored filter put on a lens: it lets its own color through and holds back the opposite one | What film photographers call it (the PRD's word). Defined once, in the caption, in plain words |
| **Yellow, Orange, Red, Green, Blue** | The five filters, in that order (warm to cool) | The PRD's set. The order is the one photographers lay them out in |
| **quick-set** | Choosing one filter alone at full strength | Used in this document and the user guide only; the UI says nothing but the filter's name |
| **gray** (in UI strings) | The result | The app's spelling is American ("gray", "color"); the PRD's "grey" is prose |

In sentences, VoiceOver and the user guide, "filter" is lowercase and "Black &
White" is the heading's name (P5: one term for one thing).

## 2. Where it lives

**A new heading, Black & White, between Color Mixer and Color Grading.**

```
Presets · Crop & Straighten · Spots · Light · Tone Curve · Color Mixer ·
Black & White (new) · Color Grading · Details · Lens · Masks · Effects
```

Why here:

1. **It is the middle step of a sequence people already read top to bottom.**
   Color Mixer sets how colors look; Black & White then turns them to gray;
   Color Grading, which is after it in the render, tints the gray (the PRD's
   own non-goal: "Color Grading, after it, tints the grey"). The three headings
   in this order are also the three steps' render order (R7).
2. **The tab is in workflow order, not render order** (`AdjustView`'s own
   comment), so the PRD's wish that the UI order "can differ" is free. The
   workflow order is *not* "just before Tone Curve": Tone Curve sits above the
   color headings because people set light first. Moving Black & White above
   Tone Curve to match the renderer would split it from the Color Mixer whose
   result it consumes and from the Color Grading that follows it.
3. **Not inside the Color Mixer heading.** Color Mixer is open by default, holds
   eight swatches and three sliders, and its hue and saturation do nothing once
   the photo is gray (only its luminance still matters: R7, AC7). A second group
   in that heading would make one 28 pt heading carry two check boxes and two
   unrelated sets of controls, and "Turn Off Color Mixer" would be ambiguous.
   A heading of its own has one check box, one reset and one fold state.
4. **Not a Profile or Presence control.** Presence's Saturation (-100) is a
   desaturation; it fixes one mix for every photo, which is the problem the PRD
   starts from. Black & White is a conversion, not a strength.
5. **Not a toolbar item or a sheet.** The toolbar is for navigation and
   commands used on every photo; a conversion with parameters belongs beside the
   photo in the inspector (HIG Inspectors, as Crop and Spots).

**Folded by default**, remembered like every heading
(`adjust.section.blackAndWhite`, default `false`, folded and expanded with
Collapse All / Expand All). Most photos are never converted, and an open heading
adds about 190 pt to an already long tab. The folded heading is still a full
28 pt row with its check box and reset, so the conversion can be turned on and
off without opening it, and it is found by scanning the tab. When a person
chooses a filter from the **Adjust** menu (§8) the heading does *not* open by
itself: the photo changes, and that is the feedback (unlike Spots, whose tool
needs its controls).

## 3. Inspector layout

```
Black & White                              [☐]  ⟲     ← 28 pt SectionHeader
[ Yellow | Orange |  Red  | Green | Blue ]            ← AppKitSegmented, small, full width
Yellow   ────────────────────────   [   0]            ← five AdjustSlider rows, 0...100
Orange   ────────────────────────   [   0]
Red      ────────────────────────   [   0]
Green    ────────────────────────   [   0]
Blue     ────────────────────────   [   0]
Each filter lightens colors like itself and darkens the opposite ones.   ← caption
Color Grading can tint the result.
```

The stack spacing is the Color Grading content's: 8 pt between the segmented
control, the slider block and the caption; 2 pt between slider rows. Under the
heading the content has the usual 4 pt bottom padding.

### 3.1 The check box and the group's two off states

Every other group shows its check box only once the group has edits, because
moving one of its controls is what creates the edit. Black & White is different
in one way that matters: **a conversion with every slider at 0 is itself an
edit** (R3: the photo's luminance as gray), so there is no "touch a control"
that starts it. So:

- **The check box is always shown** on this heading (the other check boxes'
  slot, 16 pt, and its place in the header do not change; only its "hidden
  until edited" rule does). Unchecked on a photo that never had the group;
  checked while the conversion applies; unchecked while the group keeps values
  but is turned off (the same kept-but-off state every group has, `disabled`).
- **Checking it on a photo that never had the group** switches the conversion
  on with all sliders at 0: the photo goes to its luminance as gray. One undo
  step, "Turn On Black & White".
- **Unchecking it** keeps the five values and shows the colored photo, as every
  group does; checking it again brings the values back. "Turn Off Black &
  White".
- **Moving a slider, choosing a quick-set or typing a value while the group is
  off** turns the group on in the same step (B10), as for every group ("it
  checks itself when a control of the group changes"). One undo step, "Black &
  White Filter"; History shows one entry, not two.
- **The heading's context menu** (right-click or two-finger click on the
  heading) is the standard one: **Turn On** / **Turn Off** (always available
  here, for the reason above), **Reset** (only when the group has anything away
  from its defaults), then Collapse All and Expand All.
- **The reset** (the trailing `arrow.counterclockwise`, tooltip "Reset Black &
  White") returns the group to *off with all sliders 0* (R12): the stack goes
  back to one that never had the group, so the check box is unchecked and the
  segmented control has no selection. It is enabled when the group is on or any
  slider is away from 0, whether or not the group is turned off.

What the engineer needs from the model (the shapes are the engineer's): the
module carries an explicit *on* value, default false and left out of the stack
when false, because "on with every slider at 0" must be told apart from "never
had the group" (R3, R12, AC12); `isModified` is true while it is on or any
slider is away from 0; turning the group on from the check box when it is not
modified sets *on*; and the sliders' "turned off" look (§3.3) follows whether the
group *applies*, not only whether it is in `disabled`.

### 3.2 The quick-set control

A full-width small **segmented control** with five text segments, in the order
Yellow, Orange, Red, Green, Blue (`AppKitSegmented`, `.selectOne`,
`.fillEqually`: the Color Grading and Tone Curve pattern, no new component).

- **Choosing a segment** sets that filter's slider to 100 (§4) and the other
  four to 0, turns the group on (B10), and is **one undo step**, "Black & White
  Filter" (R6, AC6). One undo restores all five values and the group's earlier
  on/off state.
- **The selected segment is derived**, never stored: a segment shows as selected
  only while the group applies *and* that filter's value is the quick-set value
  and the other four are 0 (compare the values as the sliders round them,
  `format.keyIncrement / 2`). With the group off (never on, or turned off), or
  with any other mix, **no segment is selected** (`selectedSegment = -1`;
  `AppKitSegmented` already passes the index straight through). Moving a slider
  after a quick-set therefore deselects the segment, and moving it back selects
  it again.
- **Choosing the selected segment again** changes nothing and records no undo
  step (the values already are the quick-set).
- **Why a segmented control and not five buttons or a pop-up.** The PRD says
  "buttons". The HIG allows a segmented control to "function as a set of buttons
  that perform actions without showing a selection state" or to show a single
  choice, and asks only that the two not be mixed in one control ("don't show a
  selection state for segments in a control that otherwise performs actions").
  This one is a selection control throughout: its state is the filter in effect.
  It is better than five push buttons because people try the filters one after
  another to compare (one click each, with the current one visible), and it
  keeps the five names in one grouped row that does not wrap at the inspector's
  width (five push buttons at 11 pt need about 50 pt each with their bezels;
  "Orange" and longer translated names would clip). A pop-up would cost two
  clicks per try and hide the other filters. The HIG's limit of "about five to
  seven segments" is met. Labels are nouns in title style and need no
  introductory text (HIG, Segmented controls).
- **Equal widths and long names.** The row is about 276 pt wide, about 55 pt a
  segment. "Yellow", "Orange", "Naranja" and "Amarillo" fit at 11 pt; a longer
  translation truncates in its segment and keeps its tooltip and VoiceOver
  name. The engineer checks the longest English and German names at the
  inspector's narrowest width.
- **Tooltips**: one per segment (HIG: "provide one for each"), the filter's
  sentence from §7.

### 3.3 The five sliders

Five `AdjustSlider` rows, labels **Yellow**, **Orange**, **Red**, **Green**,
**Blue**, range 0 to 100, default 0, format `.plain` ("0" to "100", no sign:
a strength, as Detail, Masking and Blending), step 1 (arrow keys and ↑/↓ in the
field, ×10 with Shift, as every slider). Nothing about the row changes: label
80 pt, a small slider, a bezeled value field; double-clicking the label or the
knob resets that slider to 0; the row's context menu offers Reset "Yellow"; a
typed value outside 0 to 100 is clamped by the field (AC5; the model also
refuses it).

- **Turned-off look.** When the group does not apply (never on, or unchecked),
  the rows show as turned off: labels and values secondary and the fill hidden
  (the `adjustGroupIsOn` environment `showsTurnedOff` already sets), while the
  rows stay usable (changing one turns the group on, B10). For this group the
  environment value is false whenever the group is not on, including before it
  was ever switched on, so a fresh photo's five sliders read as "not applied".
  This is what tells a person that sliders alone are not on; the check box is
  checked the moment they move one.
- **A change label.** Every slider commits as "Black & White Filter" (not the
  slider's own name), so the History panel and Undo read the same for a drag,
  a typed value and a quick-set (R12). The `editor.change` title is that string.
- **Tooltip and VoiceOver help** on the row (the `help` parameter): the filter's
  sentence from §7.
- **VoiceOver names** (the `accessibilityLabel` parameters): "Yellow filter",
  and for the field "Yellow filter value", because "Red", "Green" and "Blue" are
  also the Tone Curve's channels and the Color Mixer has "Reds".

### 3.4 The caption

One caption under the slider block, 11 pt (`.caption`), secondary, wrapping, with
the 4 pt top and 2 pt bottom spacing of the other captions, from the heading's
left edge. It is static: it teaches the idea once and does not change with
state, so the layout never jumps while a slider moves. The exception is a
monochrome file (§6), which replaces it.

> Each filter lightens colors like itself and darkens the opposite ones. Color
> Grading can tint the result.

Why static and not per-state: a per-state caption (as Spots has) earns its
place when the next action depends on the state. Here every state offers the
same controls, and the filter-specific effects live in the tooltips and
VoiceOver help of §7, where the person is pointing at the filter. The sentence
is non-technical on purpose: no "transmittance", no "channel mix".

## 4. The quick-set value: 100

R6 leaves it to the designer and engineer. **100.** Reasons:

1. **It is what the control says.** A Red quick-set is "a red filter on the
   lens"; the slider's 0 to 100 is "how much of that filter". The quick-set is
   the whole filter, so people lower it "to taste" (the PRD's scenario), the way
   they would reach for a weaker filter. Any number below 100 would be an
   arbitrary, unexplained choice that nobody could predict.
2. **It makes the segmented control's state exact.** One value, one definition
   of "this quick-set is in effect" (§3.2).
3. **It keeps the filter's full range reachable from one click.** With 70, the
   dramatic end needs a second action.

Dependency on the engineer: the quick-set value is one constant in PhotoCore
(`BlackAndWhite.quickSetAmount`, not typed in the UI). If at 100 the Red filter
renders a result the owner finds too extreme on the PRD's blue-sky scene, the
engineer scales the filters' numbers (the transmittance curves, recorded in
`status.md`), **not** this constant, so the slider's end keeps meaning "the
filter itself". If that turns out to be wrong in use, the constant is the one
thing to change, and the user guide's wording ("at full strength") then needs
the same edit.

## 5. Slider look: tinted tracks

**Yes: fill each slider's track in its filter's system color.**

| Slider | Fill |
|---|---|
| Yellow | `NSColor.systemYellow` |
| Orange | `NSColor.systemOrange` |
| Red | `NSColor.systemRed` |
| Green | `NSColor.systemGreen` |
| Blue | `NSColor.systemBlue` |

- **Why.** The HIG says "customize a slider's appearance if it adds value ...
  including track color ... to communicate intent". Here it does: the five rows
  are five *colors*, and the tint is how a photographer matches a row to the
  filter in their hand. It is also the Color Mixer's own device (its swatch row
  is tinted in the band's hue), so it is not a new idea in this inspector.
- **It is not custom chrome.** `SliderRow` already sets `NSSlider.trackFillColor`
  (clear when the group is off). The only change is an optional tint value on
  `AdjustSlider` passed through to that property. No drawing, no new view.
  System colors adapt to Light, Dark and **Increase Contrast** (the system
  supplies the higher-contrast variants), and they follow no accent color, which
  is right here: the fill is data, not emphasis.
- **Color is never the only signal.** The row's label names the filter, the
  field shows the number, and the knob position shows the amount. The fill is
  redundant decoration, so a person who cannot tell the tints apart loses
  nothing (WCAG: the tint does not carry information that is not also in text).
- **Turned off:** the fill is hidden (clear), as for every slider. On macOS 26
  the neutral-value fill (from 0, which here is the left end) draws as it does
  for other 0-to-100 sliders; before 26 the fill is the filter color from the
  minimum, which looks the same because the default equals the minimum.
- **Fallback.** This is a *Should*. If the tinted fill misbehaves in either
  design (macOS 15 or 26) or hurts legibility with Increase Contrast, drop the
  tint and leave the sliders in the standard look; nothing else in this design
  depends on it.
- Not done on purpose: no colored label text, no swatch dots in the label
  column (that changes the 80 pt label layout for every row), no gradient track
  of the whole spectrum (custom drawing; the sliders' value is amount, not hue).

## 6. A photo that has no color; other states

**What the tab shows for a photo that already is gray: the same controls,
nothing hidden or dimmed.** The conversion still applies (R3: gray in, the same
gray out, so the photo does not change), the sliders still work, and the group's
values are still copied, pasted and saved in presets for other photos. Dimming
would be wrong: the values may be exactly what the person wants to paste onto a
color photo next.

One small honest note, as a *Should*: when the file is **known to be monochrome**
(its color model is gray: a gray JPEG or TIFF), the caption in §3.4 is replaced
by

> This photo has no color, so the filters change nothing.

secondary caption style, no warning triangle (it is not a problem). It is shown
only for that cheap, certain test of the source file's color model; the app does
**not** inspect pixels to guess that an RGB photo is neutral, and shows nothing
special for such a photo (a gray RGB scan looks exactly like a color photo with
no color; saying nothing there is better than a wrong claim). A raw is never
called colorless. The engineer says whether the source's color model is already
known to the editor; if reading it is costly, drop the note and ship the static
caption (the design works without it, B7).

| State | Adjust tab | Menu items (§8) |
|---|---|---|
| Ready, color or gray RGB photo | The heading as §3 | Enabled |
| Ready, monochrome file | The heading as §3 with the §6 caption | Enabled |
| Cropping | The heading as every heading is while cropping (controls follow the other sliders' rule; the photo shown is the crop session's) | Dimmed (`!isCropping`) |
| Comparing | The tab is already replaced by "Not Available While Comparing" (side-by-side design §11) | Dimmed |
| Video | "No Adjustments for Videos" (N1); batch commands skip videos and count them in Activity, as the other batch edits | Dimmed |
| Offline original, unreadable stack (newer version, damaged, over the limits), loading | The existing `ContentUnavailableView`s (N1); the stack is never written over (R15) | Dimmed |
| Grid mode | The tab's "Open a Photo to Adjust It" with Presets (existing) | Dimmed (the loupe photo only; see §8) |
| A stack that has masks | The heading is the same; the Masks heading's shape list has no Black & White (R10, AC10) | Enabled |
| Show Original (`\`) held | As every heading: the original shows, the values are untouched | As every item |

A stack that already has a conversion shows the heading's check box checked, the
five values, and the matching segment selected when it is a quick-set.

Things Black & White makes moot, which the UI does not warn about and the user
guide says once: a local **White Balance** or **Saturation / Vibrance** on a
photo that is converted has nothing to work on; Color Mixer hue and saturation
do nothing on it, its luminance still does (R7).

## 7. Wording of the filters

One sentence per filter, as plain words about skies, skin and leaves. It is the
tooltip of its segment, the tooltip and VoiceOver help of its slider row. The
engineer's numbers must make each sentence true (R5, AC4); if a number
contradicts a sentence, the sentence is wrong until the designer rules.

| Filter | Sentence |
|---|---|
| Yellow | Yellow filter: slightly darker skies, lighter yellows and skin. |
| Orange | Orange filter: darker skies, lighter skin and warm tones. |
| Red | Red filter: much darker skies, lighter reds and skin, darker leaves. |
| Green | Green filter: lighter leaves and grass, darker reds and skin. |
| Blue | Blue filter: lighter skies and haze, darker reds and skin. |

Sentence style, a full stop at the end (tooltips are sentences). They are five
complete strings rather than "%@ filter: %@" fragments so a translator can reorder
them.

## 8. Menu bar, keys, context menus, toolbar

P1: every command that starts from the library window is in the menu bar,
listed and dimmed when it cannot act. The group check boxes and the other
groups' sliders have no menu items (N10: parameters are not commands). The
Black & White quick-sets differ in two ways: each is **one deliberate
whole-photo change** (a conversion, like applying a preset, which has a menu
item), and the keyboard and VoiceOver path to them otherwise runs only through
the tab's controls. Help ▸ Search also finds menu items by title (N13), and
"Red Filter" is a thing a person searches for. So there is one submenu.

**Adjust ▸ Black & White ▸**, in the Adjust menu's second group, between
**Auto Exposure** and **Reset All Adjustments** (the group of photo-wide
adjustments; Crop, Spots and the masks follow after their separator):

```
Auto Exposure
Black & White           ▸   Turn On Black & White      (title follows state: Turn Off Black & White)
Reset All Adjustments       ─────────────
                            ✓ Yellow Filter
                              Orange Filter
                              Red Filter
                              Green Filter
                              Blue Filter
                            ─────────────
                              No Filter
```

- **Turn On Black & White / Turn Off Black & White**: one item whose title
  follows the state (HIG toggled items: "include a verb if a changeable label
  isn't clear enough": a bare "Black & White" could be a state or an action).
  It is the heading's check box. Off, with the group never used, it switches the
  conversion on (all 0); on, it turns it off keeping the values.
- **Yellow, Orange, Red, Green, Blue Filter**: the five quick-sets, with a check
  mark on the one in effect (HIG: "a checkmark to show that an attribute is
  currently in effect"; the same state the segmented control shows, §3.2). They
  turn the group on. Choosing the checked one does nothing.
- **No Filter**: all five values to 0, the group stays on, so the photo is its
  luminance as gray (R3). It is the HIG's "Plain"-style item that "removes
  multiple toggled attributes at one time" and is the only keyboard path back
  to a plain conversion without resetting the group. Checked while the group
  applies and every value is 0.
- All six value items record "Black & White Filter" (§9). Reset is not in the
  submenu: it is the heading's reset and **Reset All Adjustments** already holds
  the menu-bar path (N10's precedent for every other heading's reset). Judgment:
  the HIG suggests a new menu "if a submenu contains more than about five
  items"; seven items in two groups, all about one feature, is under the cost of
  splitting it.
- **Enablement:** `canEditLoupePhoto && !isCropping && !isComparing`; dimmed in
  the grid, for video, offline, unreadable stacks and while loading. The
  submenu's title stays enabled (HIG: "make sure a submenu remains available
  even when its nested menu items are unavailable"; D-Q5). Check marks show only
  while the group applies and the loupe photo is editable.
- **Grid.** In this feature these items act on the loupe's photo only; with the
  grid showing they are dimmed. Converting a whole selection is done today with
  a preset or Paste Adjustments (R11); a grid batch version of the same items is
  proposed as a follow-up (§18).
- **Keyboard shortcut: none.** The bare keys are all taken by culling and the
  tools, and ⌘-chords with the letters left are the system's and other menus'
  territory. The items are standard menu items with stable titles, so a person
  can assign their own in System Settings ▸ Keyboard ▸ App Shortcuts. (Judgment:
  the HIG asks for shortcuts for *frequent* actions; converting is occasional,
  and `\` already compares with the original.)
- **Menu state the model needs** (the shapes are the engineer's): whether the
  group applies, which quick-set (if any) is in effect, whether the values are
  all 0, published through `LibraryMenuContext` like the other Adjust items,
  never a model passed into `Commands`.
- **Context menus.** The heading's (§3.1) holds Turn On / Off and Reset. The
  loupe's and grid's photo context menus get nothing (they hold no adjustment
  items, UIR §7).
- **Toolbar.** Nothing. A palette-only item for a rarely used conversion would
  spend toolbar room that navigation items need.

## 9. Undo, History and reset (R12, AC6, AC11, AC12)

| Action | One undo step, named | History panel entry |
|---|---|---|
| Check the check box, Adjust ▸ Turn On Black & White | Turn On Black & White | Turn On Black & White |
| Uncheck it, Adjust ▸ Turn Off Black & White | Turn Off Black & White | Turn Off Black & White |
| A slider drag, a typed value, a double-click reset of one slider, ↑/↓ in a field | Black & White Filter | Black & White Filter |
| A quick-set (segment or menu item) | Black & White Filter | Black & White Filter |
| No Filter | Black & White Filter | Black & White Filter |
| The heading's reset, its context menu's Reset | Reset Black & White | Reset Black & White |
| Paste, Apply Preset, Reset All Adjustments | Their own existing names | Their own |

- A drag is one step, committed at the end (`.changing` frames carry no name),
  as every slider.
- A change that also turns the group on (B10) is one step with the change's name.
- The two labels the PRD names are kept as the *group* labels: "Black & White
  Filter" exactly; the switch's entry is "Turn On / Off Black & White", the
  verb form every group's switch already uses ("Turn Off Color Mixer"). See §18,
  point 1.
- A selection-wide batch (paste, preset, Reset All) is one step with History
  entries per photo, as today.
- Reverting to an earlier History entry restores all five values and the on/off
  state, since it writes the stack's snapshot (edit-history design).

## 10. Paste, presets, copies, pairs and import (R11, AC11)

- **Copy and Paste Adjustments** carry the group (values and on/off) like the
  Color Mixer's. Paste replaces the target's Black & White with the source's;
  a source that never had it turns the target's off.
- **Presets.** `Group.presetGroups` already feeds the Save Preset dialog, Manage
  Presets and the preset's group list from `AdjustText.title(group)`, so a
  **Black & White** check box appears with no further UI work. Put the new group
  **after Color Mixer and before Color Grading** in `Adjustments.Group` and
  `Adjustments.Section` so those lists read in the tab's order. "Include"
  defaults: checked when the photo has the group on or any value away from 0.
  A preset of only this group applies the conversion to any number of photos
  as one undo step.
- **An "All settings" preset** (one saved before this feature, or with every box
  checked) replaces *every* group, so applying it to a converted photo switches
  the conversion off, exactly as an all-settings preset already clears Color
  Fringes and Color Alignment and a Color Mixer (the user guide's existing note
  about presets saved before Color Fringes existed). That is the preset's
  documented meaning; **Manage Presets…** can take the group out of it. The user
  guide says so under Presets.
- **Virtual copies and pairs** (R11): a copy starts with the original's group
  (values and on/off) as a snapshot and changes independently; the two files of
  a RAW+JPEG pair are separate. No UI of its own.
- **Lightroom and other imports** (B11): the PRD's non-goal stands, so there is
  **no new wording**. A Lightroom preset that converts to gray still imports as
  Presence's Saturation at -100 and the Color Mixer's luminances, and the import
  report still lists "Black and white (approximated)". The user guide must not
  say Lightroom B&W settings map to the new heading. (A true mapping into this
  group is a follow-up, §18.)
- **Masks (R10).** The shape and component lists offer no Black & White; masks'
  local controls are unchanged. The user guide says the conversion is global.
- **Effects.** Grain and Vignette are after the group (R14); grain stays gray.
  The Look-Up Table is after it too, so a table that adds color to gray (a tone)
  still does. No UI.

## 11. Accessibility and VoiceOver

- **Order**: the heading's disclosure ("Collapse"/"Expand"), the heading button,
  the check box, the reset, then the segmented control, the five sliders and
  their fields, the caption.
- **The check box** is named "Black & White" ("Black & White, checkbox, checked"),
  help "Turn off Black & White to compare" / "Turn on Black & White" (the
  `GroupToggle` strings), so the always-shown unchecked state reads "unchecked"
  and "Turn on Black & White".
- **The segmented control**: name "Filter" (`accessibilityLabel`), each segment
  speaks its name, its selected state and its tooltip as help. VoiceOver says
  "none selected" for the off and mixed states, as the system control does.
- **The sliders**: "Yellow filter, slider, 0" with the help sentence; the field
  "Yellow filter value". Values read as plain numbers.
- **The caption** is plain text read in order; it states the rule and nothing
  that changes.
- **Menu items** are standard menu items: VoiceOver reads the check marks.
- **Full Keyboard Access**: the check box, segmented control, sliders and fields
  are reachable with Tab and the arrow keys as every other control; the whole
  feature is also reachable from the menu bar without a pointer.
- **Voice Control** (judgment, not tested here): "Red" also names the Tone
  Curve's Red segment when that is visible; the sliders' longer accessibility
  names ("Red filter") keep the two apart, and Voice Control's number overlay
  covers the rest.
- **Touch (touch-display Macs).** The controls are the inspector's existing
  small ones, tuned for a pointer, as the HIG asks; the heading row is 28 pt and
  the segmented control is small like Color Grading's. Nothing here depends on
  hover.

## 12. Contrast, transparency, motion

- **Increase Contrast:** every control is a system control; the fill tints are
  system colors, which have high-contrast variants. Nothing in the design
  relies on a thin hairline.
- **Reduce Transparency, Liquid Glass:** nothing here draws glass. The inspector
  is the system's pane; the controls are content-layer controls inside it.
  Nothing new is stacked on glass.
- **Reduce Motion:** no animation of our own. The photo re-renders as for any
  slider.
- **Color is never the only signal** (§5): label, number and position carry it.
- **Light and Dark:** semantic colors only; no hard-coded values.

## 13. Strings

All through `Sources/PhotoUI/Resources/Localizable.xcstrings`, added by hand
(`LocalizationTests` fails on a literal with no entry). "Black & White" is not
the product name, so it is a plain string. The ampersand is literal. Keys are
the engineer's; every entry needs the comment shown.

| English | Where | Comment for translators |
|---|---|---|
| Black & White | Heading, group name in Save Preset / Manage Presets, the submenu, undo names | Adjust tab heading and group: turns the photo to gray by a mix of colored filters |
| Yellow, Orange, Red, Green, Blue | Segment titles and slider labels | Black & White filter names, as colored filters on a camera lens. Yellow and Orange are new; Red, Green and Blue already exist as Tone Curve channel names, so give these their own keys with this comment |
| Yellow filter, Orange filter, Red filter, Green filter, Blue filter | VoiceOver names of the slider rows | Same, lowercase "filter" |
| Yellow filter value, … | VoiceOver names of the fields | Same |
| Filter | VoiceOver name of the segmented control | Black & White: the five quick filters |
| Yellow filter: slightly darker skies, lighter yellows and skin. | Tooltip of the segment, tooltip and help of the row (five strings, §7) | What a yellow filter does to a black and white photo |
| (the four others of §7) | | |
| Each filter lightens colors like itself and darkens the opposite ones. Color Grading can tint the result. | The caption | Black & White heading caption; "Color Grading" is the heading's name below |
| This photo has no color, so the filters change nothing. | The caption for a monochrome file | Black & White caption when the photo's file is already monochrome |
| Turn On Black & White, Turn Off Black & White | Adjust ▸ Black & White menu item (one, title follows state); undo and History names | Menu item and undo name; verb form because the label changes |
| Yellow Filter, Orange Filter, Red Filter, Green Filter, Blue Filter | Menu items, with a check mark | Adjust ▸ Black & White menu items; choose one filter alone |
| No Filter | Menu item | Adjust ▸ Black & White menu item: all five filters at 0 |
| Black & White Filter | Undo and History name of every filter change | Undo action name |
| Reset Black & White | Undo and History name; tooltip of the reset | Existing "Reset %@" with the heading's name |

The existing generic strings are reused for the check box help ("Turn off %@ to
compare", "Turn on %@"), the heading's Turn On / Turn Off, Reset, Collapse All
and Expand All. Menu items and the heading are title style; the caption and
tooltips are sentence style (P5).

## 14. Custom chrome

None. Every control is the system's (`NSSegmentedControl`, `NSSlider`,
`NSButton` check box, disclosure) through the wrappers the Adjust tab already
has. The one change to an existing wrapper is an optional track tint on
`AdjustSlider` (§5), which sets a property the row already sets. That is the
whole justification this document owes.

## 15. Notes for the engineer (behavior, not code)

1. **The UI needs, from PhotoCore**: the five filters in order (Yellow, Orange,
   Red, Green, Blue); one *on* value besides the five 0 to 100 values; the
   quick-set constant (§4); a way to say "which quick-set is in effect" (the
   rule of §3.2); and, if cheap, whether the source file is monochrome (§6).
2. **Not the UI's business**: the transmittance values, how combined sliders are
   multiplied and normalized (R4), and the render position. The UI shows only
   the five numbers. The §7 sentences are claims about direction (R5); the
   engineer's values and `AdjustmentParameterTests` / the CPU reference (AC4)
   keep them true, with Orange between Yellow and Red.
3. **Section and group.** A new `Adjustments.Section.blackAndWhite` (one group,
   `.blackAndWhite`), both placed after the Color Mixer's and before Color
   Grading's in their enums. Its heading is built like Color Mixer's
   `AdjustSection` with the check box always shown and Turn On / Off always
   offered (the only difference from `AdjustSection`'s rules, §3.1), so either
   a flag on `AdjustSection`/`GroupToggle` or a small section view of its own,
   as `SpotsSection` is. The disclosure's default is folded.
4. **Check box and "off".** §3.1: *on* explicit; checking on a never-used group
   sets *on*; unchecking uses `disabled` as every group does; any change in the
   group while it does not apply turns it on in the same step
   (`enableModules(changedFrom:)` must treat *on* as it treats the others).
5. **Undo/History names** as §9; the section reset uses the existing "Reset
   \(title)" so it needs only `AdjustText.title`.
6. **Menu**: new items in `LibraryCommands.adjustCommands` and state in
   `LibraryMenuState`/`LibraryMenuContext`; the submenu uses `Toggle` for the
   check-marked filters like Spot Mode.
7. **No pipeline bump, no migration, no golden moved** (R13); presets, paste,
   batch and copies use the module like any other (R11).
8. **Strings**: §13, by hand, before `LocalizationTests`.
9. **User guide**: §19, in the same change as the behavior (WORKFLOW ownership).

## 16. Debug-script hooks (so review and QA can check without screen recording)

The existing `buttons`, `hit`, `print` and `menuitems` commands cover the
panes; the glass-pane note in `CLAUDE.md` applies (snapshots leave the
inspector blank). Please make these checkable:

- `blackwhite` (or the engineer's name): print the group's state (on, applies,
  the five values, the selected quick-set or none) for the loupe photo; set the
  group on or off; set a quick-set; set a slider; and print the segmented
  control's selected index and the check box state.
- `menuitems Black` lists the submenu with its check marks and enablement.
- `accessibility` is not needed for AppKit controls beyond the existing roles.
- A snapshot of the loupe (content area) shows the gray render; the five rows are
  checked with `print`.

## 17. Acceptance checks for the designer's review

1. The heading sits between Color Mixer and Color Grading, folded on first use,
   its fold state remembered, and its check box is always visible (unchecked on
   a new photo).
2. Checking it on a new photo grays the photo (all 0) in one undo step named
   "Turn On Black & White"; unchecking brings color back with the values kept.
3. Moving a slider while the group is off turns it on in one step named "Black &
   White Filter"; History shows one entry.
4. The segmented control selects exactly the quick-set in effect, none when off
   or mixed; choosing the selected one adds no undo step.
5. Each quick-set sets its filter to 100 and zeroes the others in one step; one
   undo restores all five and the on/off state.
6. The five rows read 0 to 100, plain numbers, clamp typed values, reset on
   double-click, and look turned off while the group is not applying.
7. Track tints are the filter system colors, hidden when turned off, legible with
   Increase Contrast, with a clean fallback if dropped.
8. Captions and tooltips read as §3.4 and §7 and are true of the render.
9. A monochrome file shows the §6 caption; an RGB photo with no color shows the
   static caption.
10. Adjust ▸ Black & White ▸ has the seven items, with state-following title,
    check marks, dimmed in the grid, comparing, cropping, video, offline and
    unreadable; the submenu title stays enabled.
11. The Save Preset dialog and Manage Presets list "Black & White" in tab order;
    a preset of only this group applies as one step across a selection.
12. Reset returns an identical stack to one that never had the group; the
    heading's reset and Reset All Adjustments both reach it.
13. VoiceOver reads the names, states and help of §11; Full Keyboard Access
    reaches every control; Increase Contrast, Reduce Transparency and Reduce
    Motion on.
14. Strings all in the catalog; no hard-coded colors; no new custom view.

Manual checks for a person (M1 and on) go into `review.md` after the build.

## 18. Requirements issues (for the product manager; none blocks the engineer)

1. **R12 / AC12 wording of the switch's history label.** The PRD says the
   switch's History label is "Black & White". Every group's switch is recorded
   as "Turn On / Turn Off <group>" (`AdjustmentEditor.setEnabled`), and a bare
   "Black & White" in the Undo menu does not say what happened or distinguish
   on from off. Ruling here: the switch is "Turn On Black & White" / "Turn Off
   Black & White" (§9); "Black & White Filter" is unchanged. Please amend R12 and
   AC12 ("the History panel shows the two labels") to "the History panel shows
   Turn On / Off Black & White and Black & White Filter".
2. **R6: "five quick-set buttons".** The design makes them one segmented control
   (§3.2), HIG-supported, state-showing, one click per try. Please amend R6 and
   AC6 to say "quick-set control" so the criteria are not read as five push
   buttons; the behavior R6 and AC6 test (sets one, zeroes the rest, one undo
   step) is unchanged.
3. **R1: "the same per-group check box the other groups have".** It is the same
   control in the same place, but it is **always shown**, not only once the group
   has edits (§3.1), and the module therefore needs an explicit *on* state
   (R3's "on with all sliders at 0" has no other representation). Please state
   this in R1 and R12 ("defaults left out" holds: *on* false is left out).

Proposed follow-ups (new issues, not this branch's scope):

- **Black & White on a grid selection**: the Adjust ▸ Black & White items acting
  on every selected photo, one undo step, videos skipped and counted
  (`BatchEdit`). Today converting a selection is a preset or a paste.
- **Lightroom black and white into this group**: the import still approximates
  with Saturation -100 and Color Mixer luminances (B11); with a real conversion
  available a mapping from Lightroom's gray mixer to the five filters is a
  product decision (the mix is not one-to-one with an eight-band gray mixer).

## 19. User guide points (`docs/USER_GUIDE.md`, by the engineer in the same change)

In the Adjust section, after Color Mixer and Color Grading's text, a **Black &
White** paragraph:

1. **What and where.** A heading between Color Mixer and Color Grading, folded
   until first used, with its own check box (always shown) and reset. It turns
   the photo to gray the way a colored filter on a camera lens would for black
   and white film.
2. **Starting.** Check the box (the photo becomes gray by each color's
   brightness), or move a slider, or choose a filter in the row of five. Uncheck
   to compare with color; your values are kept.
3. **The five filters.** Yellow, Orange, Red, Green, Blue, each 0 to 100: a
   filter lightens colors like itself and darkens the opposite ones, so Red makes
   a blue sky much darker and lightens skin, Green lightens leaves, Blue lightens
   skies and darkens skin. They combine, and the photo's overall brightness stays
   about where it was. The filter row sets one filter to 100 (its full strength)
   and the others to 0; it shows which filter is on only while the sliders are
   exactly that.
4. **Adjust ▸ Black & White ▸**: the on/off item, the five filters with check
   marks, No Filter; the loupe photo only. No keyboard shortcut (assign one in
   System Settings if you like).
5. **Order.** It applies after White Balance, Color Mixer and the other color
   edits (so the Color Mixer's luminance still lightens or darkens the gray and
   its hue and saturation do nothing), and before Tone Curve and Light's tone
   sliders; Color Grading can tint the gray, and Grain, Vignette and the
   Look-Up Table come after.
6. **Scope.** Global: it is not a mask's control and masks' local White Balance
   and Saturation do nothing on a gray photo. Photos only (videos are left out of
   batches and say so in Activity).
7. **Undo and History.** Entries "Turn On / Off Black & White" and "Black &
   White Filter"; Reset is "Reset Black & White" and returns the heading to off
   with every slider at 0.
8. **Presets, paste, copies.** The group is in Save Adjustments as Preset…'s
   list, copy and paste carry it, a virtual copy starts with the original's,
   each file of a RAW+JPEG pair has its own. An "All settings" preset replaces
   it too: applying one to a converted photo turns the conversion off.
9. **Lightroom presets.** Unchanged: gray Lightroom presets still import as
   Saturation -100 and Color Mixer luminances, reported as "Black and white
   (approximated)".
10. **A photo with no color** (a monochrome file) says the filters change nothing;
    the controls still work.
11. **No change** to anything else: photos with no Black & White render as before
    (R13).

README at Ship (product manager): one line in the feature list.

## 20. Assumptions (stated, not blocking)

- The quick-set value, 100, depends on the engineer's filter numbers giving a
  usable Red at full strength (§4).
- The source's color model is known or cheap to read for the §6 caption; if not,
  the caption is dropped.
- The tinted slider fill draws as intended on macOS 15 and 26 (§5); else the
  fallback.
- Folded by default (B1) is a judgment, not a rule; if usage shows people look
  for the heading and miss it, unfolding it by default is a one-key change.

## 21. Rulings

Design questions from implementation are recorded here as numbered rulings
(DQ-1, ...) with their date. None yet.
