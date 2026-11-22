# Copy Adjustments: choose what to copy: design

Owner: apple-ui-designer. Date: 2026-11-22.
Issue: #243. Status: complete. One non-blocking PRD wording note for the
product manager (§14); nothing blocks the engineer.

**Inputs.**

- Requirements: the PRD, the body of issue #243 (approved by the owner
  2026-11-20; Q1 to Q3 as recommended), R1 to R13, AC1 to AC12. Cited as
  "R‹n›", "AC‹n›".
- House designs followed: [`../hdr-merge/design.md`](../hdr-merge/design.md)
  ("HM": the sheet's construction, the height rule, §5.7 and D-H11),
  [`../healing/design.md`](../healing/design.md) (the Spots heading and its
  hint), [`../lens-corrections/design.md`](../lens-corrections/design.md) (the
  frame alert and the "left unchanged" Activity sentences),
  [`../preset-list-view/design.md`](../preset-list-view/design.md) (keyboard
  convention for rows: Full Keyboard Access, a Tab stop each).
- Code read in this worktree: `Model/AdjustmentActions.swift`
  (`copyAdjustments`, `pasteAdjustments`), `Edits/Adjustments.swift`
  (`Section`, `Group`, `isModified`, `pasted(onto:)` in
  `AdjustmentPresets.swift`), `Views/AdjustControls.swift` (`AdjustText`,
  `SectionToggle`, `AppKitCheckbox`), `Views/AdjustView.swift` (tab order,
  `AdjustHeader`), `Views/SpotsSection.swift`, `Views/MasksSection.swift`,
  `Views/LibraryCommands.swift`, `Grid/PhotoContextMenu.swift`,
  `Views/LibraryToolbar.swift`, `Views/MainView.swift`,
  `Model/LibraryModal.swift`, `Views/MergeSheet.swift`,
  `Model/MergeModel.swift` (`canMerge`), `Model/PresetActions.swift`
  (`PresetSaveDialog`), `Views/PresetManagerSheet.swift` (Include menu),
  `Model/DebugScript.swift` (`copyadjust`, `pasteadjust`), `PhotoApplication.swift`
  (window minimum 760 × 480), `docs/USER_GUIDE.md`.
- HIG pages read 2026-11-22 (markdown versions): Sheets, Toggles (checkbox,
  mixed state, hierarchy), Menus (ellipsis). The menu bar, toolbar and
  alert guidance applied here is the reading already recorded in UID, HM and
  LO, which cite those pages.

**Custom chrome.** None. A SwiftUI sheet made of system parts: `Toggle` in
the checkbox style (or the existing `AppKitCheckbox`, which already shows the
mixed state), `Text`, `Button`, `ScrollView` and the standard dividers. The
two menus' items are standard menu items.

## 1. Answers to the PRD's designer questions

| Question | Answer | Section |
|---|---|---|
| Sheet versus panel | **A sheet** on the library window, built like Export and Merge to HDR. A one-shot choice before one action, with Copy and Cancel; a panel is for repeated input with results in view (HIG Sheets). Not an alert (the Save Preset alert's two-column check box grid cannot hold a hierarchy, a mixed state, notes or 22 rows), not a popover (not reachable from a menu item, dismisses on any outside click) | §3 |
| How headings and groups nest | One column in the **Adjust tab's own order** and with its own names. A heading with several groups is a bold row with its own check box (mixed when its groups differ) and its groups indented under it; a heading with one group is a single row. Never collapsed | §3.2 |
| How "No changes" shows | **Secondary text at the row's trailing edge**, on the group's row. The box stays enabled (checking it resets the target's group, R5). When such a row is checked the text becomes "Resets on paste", so the consequence is stated where it is chosen | §3.3 |
| Where the masks note goes | A **fixed footer** under the list, one line, the Masks heading's own sentence verbatim | §3.5 |
| Every entry point named in R1 | One command, one sheet. The Adjust menu, the context menus and the tab's ⋯ menu get the ellipsis; the toolbar button does not | §2 |
| Mixed state when clicked | Mixed or unchecked checks all its groups; checked unchecks them all, as the Adjust tab's heading boxes do | §3.4 |
| Spots and Masks hints | Spots hint rewritten; Masks hint unchanged | §6 |
| Activity for spots left out (R8) | One warning row per paste with the photo count | §5.1 |
| Narrowest window | The list scrolls between a fixed header and a fixed footer and button bar | §3.8 |
| Coexistence with other sheets | A new `LibraryModal` case, `.copyAdjustments`, of kind `.sheet` | §7 |
| Keyboard and VoiceOver | §8 |

## 2. Entry points

One command, **Copy Adjustments…**, with the same behavior everywhere: it
opens the sheet for the **focused photo** (as Copy does today; in the grid the
focused photo of the selection, in the loupe the photo on screen, while
comparing the active photo). Nothing is copied until the sheet's Copy.

| Where | Title | Key | Enabled when |
|---|---|---|---|
| Adjust menu, first item | **Copy Adjustments…** | ⇧⌘C (unchanged) | the focused item is a photo (`focusedIsPhoto`) and no sheet, dialog or alert of the library window is up and the preset manager is not up (`canCopyAdjustments`, §7) |
| Grid, loupe, video-loupe context menu | **Copy Adjustments…** | none | as today: the item is present when the focused item is a photo |
| Adjust tab's ⋯ menu (`AdjustHeader`) | **Copy Adjustments…** | none | the focused photo is ready (as today `focusedItem != nil`) and `canCopyAdjustments` |
| Toolbar, palette only (`copyAdjustments`) | **Copy Adjustments** (no ellipsis), symbol `doc.on.doc` | none | `focusedIsPhoto` and `canCopyAdjustments` |

- **Why the ellipsis (menu items).** HIG Menus: "Append an ellipsis to a menu
  item's label when the action requires more information before it can
  complete." Copy now needs a choice. The ⋯ menu's "Save Adjustments as
  Preset…" is the in-app precedent for the same reason.
- **Why not in the toolbar button.** Toolbar labels have no ellipsis in this
  app: "Export" opens a sheet and has none. The button gets a tooltip,
  **Choose which adjustments to copy** (`.help`).
- **Key and order.** ⇧⌘C stays. Paste Adjustments stays directly under Copy
  Adjustments… with ⇧⌘V. No new item, no "copy without asking" (PRD non-goal).
- **Not a video, not unreadable edits (R1).** A video never opens the sheet
  (the item is dimmed in the menu; the context menu leaves it out, as today).
  A photo whose edits can't be read opens no sheet: the existing Activity
  warning is posted (`AdjustText.unreadableMessage`, action "Copy
  Adjustments"), as today. In the grid that read is asynchronous (after
  pending saves): **the sheet opens when the read has answered**, with no
  spinner (it is a catalog read behind the write chain). A second ⇧⌘C while
  the read is pending does nothing.
- **During a crop session** the Crop row describes the saved crop; the
  unfinished rectangle is not in the stack and is not copied (as today).
- **Where the keyboard goes after the sheet.** Closing returns the keyboard
  to the grid or loupe so ⇧⌘V and the arrow keys work at once. The engineer
  checks this as for Export's sheet, and posts `.browserShouldTakeFocus` if it
  does not.

## 3. The sheet

A sheet on the library window, window-modal, 420 pt wide (§3.8 for height).
It freezes the source's values when it opens (as Export freezes its photos):
the defaults and what Copy stores come from one `Adjustments` value read at
that moment, whatever a background job does meanwhile.

```
┌─ Copy Adjustments ───────────────────────────────────────┐
│ [thumb]  Copy Adjustments                                │
│          From IMG_1234               Check All  Uncheck All│
├──────────────────────────────────────────────────────────┤
│ ☐ Crop & Straighten                                      │
│     Pasted as it is, whatever a photo's size or shape.   │
│ ☐ Spots                                     No changes   │
│     Pasted only onto photos of the same size.            │
│ ▬ Light                                                  │
│     ☐ White Balance                         No changes   │
│     ☑ Tone                                               │
│     ☐ Presence                              No changes   │
│ ☐ Tone Curve                                No changes   │
│ ☐ Color Mixer                               No changes   │
│ ☐ Black & White                             No changes   │
│ ☐ Color Grading                             No changes   │
│ ☐ Details                                                │
│     ☐ Sharpening                            No changes   │
│     ☐ Noise Reduction                       No changes   │
│ ☐ Lens                                                   │
│     ☐ Distortion                            No changes   │
│     ☐ Lens Vignetting                       No changes   │
│     ☐ Color Fringes                         No changes   │
│     ☐ Color Alignment                       No changes   │
│ ☐ Effects                                                │
│     ☐ Look-Up Table                         No changes   │
│     ☐ Vignette                              No changes   │
│     ☐ Grain                                 No changes   │
├──────────────────────────────────────────────────────────┤
│ Presets and Paste Adjustments leave masks out.           │
│ Check something to copy.            [ Cancel ] [ Copy ]  │
└──────────────────────────────────────────────────────────┘
```

(The sketch is AC3's case: Exposure and Tone edited, a crop, nothing else. The
"Check something to copy." text shows only while nothing is checked; the
sketch has Tone checked, so it would be absent. The heading "Light" is mixed,
drawn ▬.)

### 3.1 Header

- The 44 × 44 pt thumbnail of the source photo, as the Export and Merge
  headers (placeholder `Palette.cell` until the image arrives, never blank,
  hidden from VoiceOver), then the title **Copy Adjustments** (13 pt
  semibold, header trait) and a subtitle **From ‹photo name›** (11 pt
  secondary; `PhotoName.display`, so a virtual copy reads "IMG_0412 copy").
  The existing catalog key "From %@" is reused.
- **Why the source is named.** In the grid the selection may hold ten
  photos and Copy takes the focused one. The person has to see which.
- **Check All** and **Uncheck All**: two borderless 11 pt text buttons at the
  header's trailing edge, bottom-aligned with the subtitle. HIG Menus
  suggests "a menu item that makes it easy to remove multiple toggled
  attributes"; the same reason holds here: copying only Color Grading from a
  photo with six checked groups would otherwise take six clicks. They set
  every row, including Crop, Spots and the Lens groups. This is a design
  addition (the PRD is silent); it changes no requirement and can be dropped
  without touching anything else.
- **A source with no changes at all** (every row says "No changes"): a second
  subtitle line with an `info.circle`, 11 pt secondary: **"This photo has no
  adjustments. Checking a group resets it on the photos you paste onto."**
  Without it a person sees 20 unchecked boxes and a dimmed Copy and no
  reason.

### 3.2 The list: rows, order, nesting

A scrolling column of rows, **always fully expanded** (no disclosure
triangles): the purpose of the sheet is to see at once what the photo has,
and 22 rows fit (§3.8). Order is the **Adjust tab's visible order**, the one
`AdjustView` builds, with Presets and Masks left out:

| # | Row | Kind | Children (the tab's group order, `Adjustments.Section.groups`) |
|---|---|---|---|
| 1 | Crop & Straighten | single | none (the crop is not an `Adjustments.Group`) |
| 2 | Spots | single (`.spots`) | none |
| 3 | Light | heading | White Balance, Tone (the `.light` group's UI name), Presence |
| 4 | Tone Curve | single | none |
| 5 | Color Mixer | single | none |
| 6 | Black & White | single | none |
| 7 | Color Grading | single | none |
| 8 | Details | heading | Sharpening, Noise Reduction |
| 9 | Lens | heading | Distortion, Lens Vignetting, Color Fringes, Color Alignment |
| 10 | Effects | heading | Look-Up Table, Vignette, Grain |

- **Names are the tab's** (`AdjustText.title(section)` for a heading and for a
  single-group row, `AdjustText.title(group)` for a child), and Crop's is the
  tab's heading, **Crop & Straighten** (the PRD says "Crop"; the sheet uses the
  name the person sees in the tab). Nothing is invented.
- **A heading with one group is one row**, not a heading with one child. The
  heading's box and the group's box would be the same thing twice.
- **Typography.** Heading rows 13 pt semibold; child rows 13 pt regular,
  indented one checkbox width plus 6 pt (HIG Toggles: "alignment — generally
  along the leading edge of the checkboxes — and indentation, you can show
  dependencies"); single rows 13 pt semibold like headings, so the left edge
  of the list is one level and the indented rows are the only second level.
  Row pitch 20 pt; 4 pt of extra space above every heading and single row
  except the first.
- **Hit target.** The whole row, label to trailing edge, toggles its box
  (also the touch-display Mac's target; the density is tuned for the
  pointer). The trailing text is part of the row, not a separate target.
- **Truncation.** The label truncates at its tail (tooltip: the full name);
  the trailing text never truncates (`fixedSize`), so "No changes" stays
  whole in a longer language.
- **Data-driven.** The row list is one ordered array in PhotoCore, not
  views: #92 will add a Masks row (and then the footer in §3.5 goes), and a
  new Adjust heading adds one entry. A test pins that every
  `Adjustments.Section` and every `Adjustments.Group` appears once, plus Crop
  (AC2).

### 3.3 State and the trailing text

**Initial state (R3), worked out from the source each time, never remembered
(R10):**

| Row | Starts checked when |
|---|---|
| Crop & Straighten, Spots, every Lens group | never |
| any other group | the source has changed it: `isModified(group)`, which counts a group that holds values while turned off |

A heading's box is derived from its groups: on when all are checked, off when
none, **mixed** otherwise. It is never stored.

**The trailing text** (secondary color, 11 pt), first rule that applies:

| Condition | Text |
|---|---|
| unchanged in the source and the row is checked | **Resets on paste** |
| unchanged in the source and the row is unchecked | **No changes** |
| Spots changed | **‹n› spots** (or **‹n› spots, turned off** when the group is off) |
| any other group changed but turned off in the source | **Turned off** |
| otherwise | nothing |

- **A heading row** has no trailing text (its children say it). A single row
  (Spots, Tone Curve, …) is a group row and carries the text.
- **Why "Resets on paste".** PRD R5 and the cost named under Q1: pasting an
  unchanged group resets the target's. That is a legitimate way to clear a
  group on ten photos, and a surprise when it is accidental. The text changes
  the moment the box does, next to the box.
- **Why "Turned off" and the spot count.** R5 pastes a group's on/off state
  with its values, so a group turned off in the source is pasted turned off.
  That is the one outcome a person cannot guess from the Adjust tab's
  collapsed look. The spot count tells a person who sees "Spots" what is
  being carried. Both are judgment, small, and removable.
- **Not by color alone.** Every state is a word or a box state.
- **The box is never dimmed for "No changes."** A dimmed box could not be
  checked, which R5 and AC6 need.

### 3.4 The mixed state and what a click does

- A heading shows a mixed box (a dash, HIG Toggles) when some, not all, of
  its groups are checked.
- **Clicking a heading's box:** checked becomes unchecked for all its groups;
  unchecked or **mixed becomes checked for all its groups**. This is the rule
  of the Adjust tab's own heading boxes (`SectionToggle`:
  `setEnabled(section, !isOn)`), so one control reads one way in both
  places. The AppKit default cycle (on, mixed, off) is not used: the parent's
  state is derived, a person cannot "choose" mixed.
- Checking all includes the children marked "No changes" (they then read
  "Resets on paste"): the click is literal and predictable.
- **Implementation.** SwiftUI's `Toggle(sources:isOn:)` shows the mixed state
  from its children; where it does not render for these rows, the existing
  `AppKitCheckbox` (`allowsMixedState`, `.mixed`) hosts the box. Either is
  fine; the click rule above is a requirement. If the engineer finds the
  checkbox style puts the label's click area short of the full row, add the
  row as the hit shape; do not add a second control.

### 3.5 Footer: the masks note (R11)

One line under the list, fixed (it does not scroll away), above the button
bar, 11 pt secondary: **Presets and Paste Adjustments leave masks out.** This
is the Masks heading's sentence, byte for byte: it is still true of Paste, so
there is no new string and one place to change it when #92 gives masks a row
(delete the footer then; the row list is data-driven, §3.2). It sits in the
footer, not in the list, because masks have no box and a disabled row would
invite the question "why can't I check it" in the middle of the choices.

### 3.6 Button bar

- **Cancel** (Esc) and **Copy** (Return, the default). The default is right:
  Copy only stores values in memory and is replaced by the next Copy (HIG
  Alerts' warning about default buttons is for destructive actions). The label
  is the verb alone.
- **Copy is disabled with nothing checked (R4, AC4).** A dimmed default
  button must say why: **Check something to copy.** (11 pt secondary) appears
  at the bar's leading edge while nothing is checked (the place Merge puts its
  spinner), and is the button's accessibility hint.
- **Cancel changes nothing:** neither the clipboard (an earlier copy stays,
  R4) nor any photo (AC1).
- **Copy** stores the checked rows' values from the frozen source as the new
  clipboard, replacing any earlier one (R10), closes the sheet, posts no
  Activity row (nothing happened to a photo), and announces to VoiceOver
  **Copied ‹list›.** (`AccessibilityText.announce`, medium priority). ‹list› is
  the checked items' names joined as the preset manager lists a preset's
  groups (`PresetText.groups`' comma style), a heading's name standing for all
  of its groups when all are checked; more than five items read "‹n› items".
  The sighted person's confirmation is the sheet closing and Paste becoming
  available.

### 3.7 What Copy stores

The clipboard stays `LibraryModel.copiedAdjustments` (in-app, not the system
pasteboard; PRD non-goal), now with **which items were copied** beside the
values. Paste applies exactly those items (R5): each copied group's values and
on/off state replace the target's, a copied group at its defaults resets the
target's, everything not copied is left as the target has it, the crop
included unless Crop was copied; masks, the stored decode and unknown
operations are never touched. How the selection is keyed (a set of groups plus
a crop flag, or one enum) is the engineer's; the design needs only that the
row list of §3.2 is the single source of the items.

### 3.8 Size, the narrowest window

- **Width 420 pt.** A longest label plus "Resets on paste" fits with room;
  the window's minimum is 760 pt, so width never clamps.
- **Height.** Budget of the default case, in points, an estimate to be
  measured by the engineer (the HM lesson, D-H11: the Form grew 140 pt past its
  estimate): header 68 (44 plus 12 twice), divider 1, list inset 8, 22 rows ×
  20 = 440, two caption lines 28, 9 block gaps of 4 = 36, list inset 8,
  divider 1, footer 28, button bar 52 = **about 670**. The sheet's
  `idealHeight` is the **measured content height, at most 680**, so the default
  case does not scroll. If the measure is over 680, cut in this order and
  record the number in `status.md`: (i) block gaps 4 to 2 (−18), (ii) the two
  caption lines move to row tooltips and VoiceOver help (−28; the Spots fact
  is still said at paste time, §5.1), (iii) the thumbnail goes and the header
  is two text lines (−26). Nothing varies with content (always the same 22
  rows), so unlike Merge the height does not depend on the photo.
- **`minHeight` 380.** The sheet never grows past its ideal.
- **A short window** (the library window's minimum is 760 × 480, or any window
  shorter than the sheet) clamps the sheet to the window. Then **only the list
  scrolls**: the header with Check All and Uncheck All, the footer and the
  button bar stay in place, so Cancel and Copy are always on screen. At 480 pt
  the viewport shows about 12 rows; keyboard focus moving to a row scrolls it
  into view. A `ScrollView` in a sheet is fine: `CLAUDE.md`'s rule against a
  SwiftUI `ScrollView` is about the inspector under the toolbar. Do not use the
  grouped `Form` style for the list: its row padding (about 15 pt a row in
  Merge's measure) would make 22 rows 330 pt taller.

## 4. Defaults, in one place

1. Crop & Straighten, Spots and the four Lens groups: unchecked.
2. Every other group: checked when `isModified`, unchecked and marked "No
   changes" when not.
3. Return accepts the defaults (PRD scenario "accept the defaults with
   Return"). With a source that has no changes, Return does nothing (Copy is
   disabled); §3.1's note says why.
4. The sheet does not remember a previous choice, and nothing is stored in
   preferences (R10).

## 5. What the person sees at paste time

Paste Adjustments is unchanged in place, key (⇧⌘V), enablement (disabled until
something is copied, while comparing, and when the targets hold no photo) and
undo (one step, History label "Paste Adjustments", videos skipped). Two things
can speak:

### 5.1 Spots left out because of the photo's size (R8)

A target whose frame size differs from the source's keeps its own spots and
their on/off state, and its other pasted groups apply normally. **One
Activity row per paste**, a warning (the person asked for something that did
not happen), title "Paste Adjustments" (the action name, as every Activity row
of a command), text:

> **Spots were not pasted onto ‹n› photos: their size differs from the photo
> the spots were copied from.**

with the catalog's plural form for 1 ("…onto 1 photo: its size differs from…").
The count is photos, not spots (R8: "how many were left out"). It is posted
after the change has landed, in the loupe too (one photo). It is
`report(…, warning: true)`, so VoiceOver announces it. It follows the same
sentence style as the neighbors ("‹n› photos were left unchanged: …").

- **Nothing is posted when every target matched**, or when Spots was not
  copied.
- **A source with no spots, Spots checked** (a reset): the same size rule
  applies as written in R8, so a differently sized photo keeps its spots and
  the row is posted. Stated as an assumption, §14.
- **A cancelled lens-frame question** (§5.2) writes nothing and posts nothing.

### 5.2 The lens frame alert (R7)

Unchanged: it asks, in its narrow alert, when a paste moves the frame of a
target that has spots or masks (lens-corrections design §6). Two consequences
for this design:

- A paste that copied no Lens group cannot move the frame, so the alert never
  appears for it (the transform the alert tests is the partial paste).
- The spots' size test uses the frame the target will have **after** the
  paste's Lens groups (R8), so the alert comes first and the Activity row only
  after a confirmed paste.

The copy sheet is closed before any of this (§7), so the two never meet.

## 6. The Adjust tab's hints (R: "Dependencies and impact")

- **Spots heading** (`SpotControls`): "Presets and Paste Adjustments leave spots
  out." is no longer true of Paste. New text, 11 pt secondary as now:
  **"Presets leave spots out. Copy Adjustments can copy them to photos of the
  same size."** The old key is removed from the catalog; healing design §11's
  "in the Masks heading's words" is superseded by this note.
- **Masks heading**: unchanged ("Presets and Paste Adjustments leave masks
  out." is true; it is also the sheet's footer, §3.5).
- **Tooltips and the Spots row caption** say the same fact: the sheet's Spots
  caption "Pasted only onto photos of the same size." is the sentence the
  hint's second half abbreviates.

## 7. Coexisting with the library window's other sheets and alerts

- **A sheet of the library window.** Add `.copyAdjustments` to `LibraryModal`
  with kind `.sheet`, `LibraryModel.showsCopySheet` in `isUp(_:)`, and
  `.sheet(isPresented:onDismiss:)` in `MainView` with `onDismiss:
  { model.modalDidClose() }`, the same as Export and Merge. `LibraryModalTests`
  fails until it is so. This keeps the preset pack import's report waiting
  until the sheet has closed (#203's rule) and keeps "one sheet at a time"
  (HIG Sheets).
- **Not offered over another modal.** `canCopyAdjustments` (the menu, toolbar
  and tab menu enablement) is `focusedIsPhoto && !otherModalIsUp &&
  !showsPresetSheet`, Merge's rule. A window-modal sheet already makes the
  window non-key, which dims `can`-gated menu items; the model checks again so
  the toolbar, the context menu, the debug script and a key held through an
  opening sheet are safe: `openCopySheet()` returns when a modal is up.
- **Over an Activity job.** Allowed: Copy reads, writes nothing. A running
  measuring paste's changes land later; a Copy begun meanwhile reads what is
  saved after pending writes, as Copy does today.
- **Over Export and the others.** Not possible (the items are dimmed).
- **Paste's alerts** (the lens frame question, `WindowModal` alerts) are not
  `LibraryModal`s and run after this sheet has closed.
- **Review mode and comparing.** The sheet opens wherever the menu item is
  enabled today. Comparing copies the active photo; review mode keeps working
  (the sheet is on the library window).

## 8. Keyboard and accessibility (R12, AC12)

**Keyboard.**

- ⇧⌘C opens. **Return** is Copy (the default button) from anywhere in the
  sheet, **Esc** is Cancel.
- Every box is a system checkbox, a Tab stop with Full Keyboard Access on
  (System Settings ▸ Keyboard ▸ Keyboard navigation) and toggled by **Space**.
  This is the house reading of "the keyboard" for a checkbox: the Presets list
  and every inspector control are reached the same way (preset-list-view
  design §8). With the setting off, macOS itself Tabs to text fields and lists
  only, for every app. The sheet adds no roving arrow-key focus (a possible
  later improvement; judgment, not Apple policy). Return and Esc work with the
  setting off. AC12 is read as "with Full Keyboard Access on"; the check is
  M2.
- Check All, Uncheck All are buttons in the Tab order after the list.
- A box taking focus scrolls its row into view.
- The initial focus is the system's: do not set it by code (HM D-H11, a
  focused row would scroll the list on open).

**VoiceOver (covered by CI only; nothing for the owner to check).**

- The sheet's title is a header; the list is one container named **Adjustments
  to copy**; each heading's rows are a container named for the heading.
- A row reads "‹name›, ‹no changes›|‹resets on paste›|‹turned off›|‹n spots›,
  checkbox, checked|unchecked|mixed": the label is the name, the value the
  state, and the trailing text is appended to the label so it is read once
  (not also a separate static text). The captions under Crop and Spots are the
  rows' accessibility hints and hidden as separate elements.
- A heading in the mixed state reads "mixed"; Space sets all as §3.4.
- Copy reads dimmed with the hint "Check something to copy." when nothing is
  checked.
- "Copied ‹list›." is announced when the sheet closes; the Activity row of
  §5.1 is announced as every `report` is.

**Color and contrast.** System checkbox, system text styles, `.secondary` for
the trailing text and captions; no custom color and no glass of our own (the
sheet's material is the system's). Increase Contrast and Reduce Transparency
need nothing. The library window is dark-only; the sheet inherits it. No
motion.

## 9. Requirements covered

| R | Where |
|---|---|
| R1 | §2 (every entry point, video, unreadable) |
| R2 | §3.2 (rows, order, heading box, mixed state) |
| R3 | §3.3, §4 |
| R4 | §3.6 |
| R5 | §3.7 (what Paste applies), §3.3 (the "Resets on paste" text) |
| R6 | §5 (unchanged) |
| R7 | §5.2 |
| R8 | §3.2 and §3.3 (the Spots row), §5.1 |
| R9 | §3.2 (the Crop caption); no remapping |
| R10 | §3.3, §3.6, §4 |
| R11 | §3.5 |
| R12 | §8 |
| R13 | §11 |

## 10. Strings (the String Catalog; `LocalizationTests` fails without them)

Add by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings`, each with a
`comment`. Plural forms as the neighbors do ("‹n› photos were left unchanged").

**New**

| Key | Use |
|---|---|
| `Copy Adjustments…` | Adjust menu, context menus, the tab's ⋯ menu (real ellipsis character) |
| `Choose which adjustments to copy` | tooltip of the toolbar's Copy Adjustments item |
| `Check All` | the sheet's button |
| `Uncheck All` | the sheet's button |
| `No changes` | a row's text: the source has not changed this group |
| `Resets on paste` | a checked row the source has not changed |
| `Turned off` | a row the source has changed but turned off |
| `%lld spots` | the Spots row when it has spots (plural) |
| `%lld spots, turned off` | the same, group off (plural) |
| `Pasted as it is, whatever a photo's size or shape.` | Crop row caption and VoiceOver hint ("shape": aspect and orientation, R9) |
| `Pasted only onto photos of the same size.` | Spots row caption and VoiceOver hint |
| `Check something to copy.` | button bar text and Copy's hint while nothing is checked |
| `This photo has no adjustments. Checking a group resets it on the photos you paste onto.` | the header note for a source with no changes |
| `Adjustments to copy` | VoiceOver name of the list |
| `Copied %@.` | the VoiceOver announcement after Copy; %@ is the list |
| `%lld items` | the list's long form (plural) |
| `Spots were not pasted onto %lld photos: their size differs from the photo the spots were copied from.` | the Activity warning (plural; the 1 form "…photo: its size differs…") |
| `Presets leave spots out. Copy Adjustments can copy them to photos of the same size.` | the Spots heading's note |

**Reused unchanged:** `Copy Adjustments` (sheet title, Activity and undo
names, the toolbar label), `Paste Adjustments`, `Copy`, `Cancel`, `From %@`
(extend its comment: also the Copy Adjustments sheet; the argument is the
photo's display name), `Presets and Paste Adjustments leave masks out.` (also
the sheet's footer; extend its comment), `Crop & Straighten`, every group and
heading name through `AdjustText`.

**Removed:** `Presets and Paste Adjustments leave spots out.`

## 11. Debug script (R13; `CLAUDE.md`: UI checks use `--debug-script`)

The script cannot click a sheet, so the sheet's logic is driven by commands
and the sheet itself is observed. Keep today's `copyadjust` and `pasteadjust`
names:

- `copyadjust` (no argument) copies with the sheet's **defaults** and no sheet
  (what a person gets by pressing ⇧⌘C then Return).
- `copyadjust all`, `copyadjust <name> …` copies exactly those items, named
  as `Adjustments.Group` raw values plus `crop`
  (`copyadjust colorGrade`, `copyadjust crop spots`), also with no sheet.
- `copyadjust sheet` opens the real sheet. Then `copyadjust sheet check <name>…`,
  `uncheck <name>…` (`all` and `none` too), `confirm`, `cancel`.
- `print copysheet` prints every row (name, state on|off|mixed, trailing text,
  enabled), Copy's state, the sheet's size against its ideal (as
  `merge sheet` does) and `canCopyAdjustments`.
- `print clipboard` prints what is on the clipboard: its items by name, and
  `none`.
- `pasteadjust` is unchanged. A test can read the stored stacks (AC5, AC6,
  AC9) and Activity (`activity …`, existing).

## 12. User guide and inventory terms

The engineer updates `docs/USER_GUIDE.md` in the same change (it owns the
file); terms to match the UI exactly: **Copy Adjustments…**, **Paste
Adjustments**, **Check All**, **Uncheck All**, "No changes", "Resets on
paste", "Turned off", **Crop & Straighten**, the heading and group names.
Lines that change: 416 ("Copy and Paste Adjustments carry the crop"), 459
(the spots sentence), 514 (spots left out of Copy and Paste), 684 and 820
(check the wording), the key table at 848 (Copy Adjustments…). The
inventory row "Paste carries crop, not masks" is the product manager's.

## 13. Tests and checks to expect

- **PhotoCore tests** (the engineer's): the row list (AC2: each `Section` and
  `Group` once, Crop once, order); the default selection (AC3, a group off with
  values counts as changed, Lens, Crop and Spots never); a heading's derived
  state and the click rule (§3.4); paste of a selection (AC5 to AC7, AC9,
  AC10); the summary text and "‹n› items"; the spots size rule and its count.
- **Manual checks for a person** (the designer's; none for VoiceOver or macOS
  15 and 26, which CI covers):
  - **M1** The sheet's look beside Export's, with Increase Contrast on: row
    pitch, the indent, the trailing text's contrast, the header and the
    footer, no clipped label.
  - **M2** Keyboard with **Full Keyboard Access on**: Tab through every box,
    Space toggles, Return copies, Esc cancels; Return with nothing checked does
    nothing; focus into a hidden row scrolls it in.
  - **M3** The narrowest window (760 × 480): the list scrolls, the header, the
    footer and the buttons stay, Copy and Cancel stay on screen; the sheet at
    the default window is not scrolled.
  - **M4** A real mouse on a mixed heading: click checks all, click again
    unchecks all; the trailing text changes with each box.
  - **M5** The real flow with keys: ⇧⌘C, Space on a box, Return, ⇧⌘V on a
    series; undo once restores all.
  - **M6** A preset pack import that ends while the sheet is up: the manager
    waits and opens after the sheet closes.

## 14. Requirements issues, assumptions and notes for the PRD

**No requirement is blocked.** Three wording points for the product manager,
none changing scope, so the engineer can start; the design assumes the answer
given.

1. **RI-1 (non-blocking). The PRD's names do not match the tab.** R2 lists
   "White Balance, Light, Presence" as groups; in the UI the heading is
   **Light** and its three groups are **White Balance, Tone, Presence** (the
   `.light` group is titled "Tone", `AdjustText.title`), and R2's list follows
   `Adjustments.Section.allCases`, not the tab's visible order (Crop, Spots,
   Light, Tone Curve, Color Mixer, Black & White, Color Grading, Details, Lens,
   Effects; Presets and Masks have no row). AC2 says "in tab order", so this
   design follows the tab and its names. **AC3** then reads: from a photo with
   only Exposure and Tone edited and a crop, the **Tone** group is checked
   (heading **Light** shows mixed), the other non-Lens groups are unchecked and
   marked, and Crop & Straighten, Lens and Spots are unchecked. Please correct
   R2 and AC3's wording; the design needs no change.
2. **Assumption.** Spots copied from a source **with no spots** (a reset) are
   still subject to R8's same-size rule: a differently sized target keeps its
   spots and the Activity row is posted (§5.1). The alternative (a reset ignores
   size) is simpler to explain but breaks "never pasted onto another size"
   as written. Not material; the engineer follows the PRD's sentence.
3. **Additions the PRD did not ask for**, all removable without touching a
   requirement: Check All and Uncheck All (§3.1), the trailing "Resets on
   paste", "Turned off" and the spot count (§3.3), the VoiceOver announcement
   "Copied …" (§3.6), the note for a source with no changes (§3.1), and the
   toolbar tooltip. If the owner wants the slice smaller, drop them in this
   order: the spot count, "Turned off", the announcement, Check All and
   Uncheck All.

**Not designed, noted.** After copying, nothing shows what is on the
clipboard. A tooltip on the toolbar's Paste item listing the copied items
("Paste Adjustments: Light, Color Grading") would answer it with the same
summary function §3.6 needs; it is a Could and not specified, because the
History label stays "Paste Adjustments" by R6 and Undo is one step.

## 15. Design questions from implementation

None yet. Rulings go here, numbered, for the engineer to cite.
