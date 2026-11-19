# Lens corrections: geometric distortion and lens vignetting: design

Owner: apple-ui-designer. Date: 2026-11-19. Issue: #87 (slug `lens-corrections`).
Status: Designed. The owner ruled all five requirements issues on 2026-11-19
(§18, recorded in §21); §3.2, §4, §5, §6, §11, §14 to §17 and §19 are amended for
RI-1 (Manual works on a raw that is already corrected; only Auto is inert there).

**Inputs.**

- Requirements: the issue body (the PRD, status Approved 2026-11-18), cited as
  R1 to R14 and AC1 to AC13. This document answers its designer open questions:
  where the two groups, Source, Amount, Constrain to Image and the captions sit
  in the Lens heading, how the warning (R6) looks, how "applied by the camera
  decoder" reads, and whether R13's map is needed (it is not, §12).
- Earlier records followed: [`../chromatic-aberration/design.md`](../chromatic-aberration/design.md)
  (CA §2 the Lens heading, §3 layout, §7 the automatic check box and its
  captions, §8 states, §10 paste and batch, §11 accessibility; the closest
  precedent, and its Color Alignment is what this feature's Auto resembles),
  [`../healing/design.md`](../healing/design.md) (the mask and spot frame, the
  state caption, history labels, §20 rulings),
  [`../bw-module/design.md`](../bw-module/design.md) (a group whose check box is
  always shown because "on" is itself an edit, the segmented control and
  `fillsWidth`, the debug hooks), [`../ui-redesign/design.md`](../ui-redesign/design.md)
  (P1 to P5, N1 states, N10 "parameters are not commands"),
  [`../edit-history/design.md`](../edit-history/design.md), and
  `docs/UI_REDESIGN.md` (UIR §4 inspector rows, §10 accessibility).
- Code read on `feature/lens-corrections` (develop c97d579):
  `Views/LensControls.swift` (the Lens heading's body), `Views/AdjustControls.swift`
  (`AdjustSection`, `SectionToggle`, `GroupToggle`, `GroupLabel`, `LabeledPopUp`,
  `SectionHeader`), `Views/BlackAndWhiteSection.swift`, `Views/CurveEditor.swift`
  (`AppKitSegmented`, `fillsWidth`), `Model/LensText.swift`,
  `Edits/LensCorrections.swift` (`ColorFringes`, `ColorAlignment`),
  `Edits/Adjustments.swift` (`Section.lens`, `Group`, `setEnabled`,
  `presetGroups`), `Preview/EmbeddedLensCorrection.swift`,
  `Model/PresetActions.swift` (the Save Preset group list),
  `Model/LibraryOpsActions.swift` and `Model/ComparisonActions.swift` (how alerts
  are put up), `Model/DebugScript.swift` (`inspectorwidth`, `alert`).
- HIG pages read on 2026-11-19 (markdown version): Alerts. The Segmented
  controls, Sliders, Menus, Inspectors and Accessibility readings in the earlier
  records are relied on where cited. Where the HIG is silent I say "judgment".

**Clean-room note.** "Distortion", "vignetting", "Source", "Auto", "Manual" and
"Amount" are common words for the task. I did not use the names other editors
give this panel (their "Profile" corrections and "Upright" and "Transform"
wording), and I avoid "profile" altogether: in this app a profile already means
a camera color profile (the PRD says "table", and so do the strings below). The
layout (a group with a check box, a two-way source control, one amount slider, a
caption) is this app's own Color Alignment, Color Grading and Spots pattern.

## Summary of rulings

| # | Ruling |
|---|---|
| L1 | Two new groups, **Distortion** and **Lens Vignetting**, at the top of the Lens heading, in that order, before Color Fringes and Color Alignment (§2) |
| L2 | Both groups' check boxes are **always shown** (unchecked on a new photo), because "on, with Auto and nothing else set" is itself an edit. The module carries an explicit on value, as Black & White does (§3.1) |
| L3 | **Source** is a two-segment control, **Auto | Manual**, in a row with the label "Source". Turning a group on starts in Auto, except on a file where Auto cannot apply, where it starts in Manual (§3.2) |
| L4 | **Auto shows no sliders; Manual shows one Amount.** Both are kept when the person switches. Manual starts from its own stored value (0 the first time), never from the camera's table (§3.3) |
| L5 | Amount is signed, **-100 to +100, default 0**. For Distortion positive straightens lines that bow outward (barrel), negative lines that bow inward (pincushion). For Lens Vignetting positive lightens the corners, negative darkens them (§3.3) |
| L6 | **Constrain to image**, a check box under Distortion only, on by default, for both sources (§3.4) |
| L7 | One caption under each Source row, one role at a time, always naming the source in use or why nothing is applied (§4) |
| L8 | On a raw that the camera decoder, or Fujifilm's built-in correction, already corrects, **Auto is inert and Manual works on top** (owner ruling RI-1, 2026-11-19). The group is not dimmed: its Auto segment is, its caption says Auto does nothing and Manual still works, and Auto never corrects a second time (§5) |
| L9 | Auto cannot apply on three kinds of file: a non-raw file, a decoder-corrected raw, a Fujifilm built-in raw. There the Auto segment is dimmed with a tooltip naming the reason, a stored Auto shows no segment selected, and turning the group on starts in Manual (§3.2, §5) |
| L10 | The mask and spot warning is an **alert sheet on the library window**, for Distortion only, asked only when the corrected frame would really change on a photo that has masks or spots, **once per visit to the photo**, once for a whole paste or preset, never for undo, redo or History (§6; see RI-3) |
| L11 | A table that cannot be read, or kernels that cannot run, are told **on the group** with a warning symbol and words, never silently skipped (§4) |
| L12 | No map, overlay or preview of where the correction samples from (R13, §12) |
| L13 | **No menu item, shortcut or toolbar item.** Parameters are not commands (N10); batch is Paste Adjustments or a preset (§8) |
| L14 | Presets and paste carry both groups; each receiving photo reads its own table; the Save Preset list reads Distortion, Lens Vignetting in that order, before Color Fringes (§9) |
| L15 | Distortion never moves red and blue against green; that is Color Alignment's job, and a camera table's per-color part is not applied (§10, judgment) |

## 1. Terms

| Term | Meaning | Why this word |
|---|---|---|
| **Distortion** (group) | Straight lines the lens bends: barrel (they bow outward) or pincushion (inward) | The PRD's word and the photographer's |
| **Lens Vignetting** (group) | Corners the lens makes darker (or, set the other way, lighter) | "Vignetting" alone would sit one letter from **Vignette** (Effects: the creative darkening, its own group in the Save Preset list and its own undo names). People would pick the wrong box. "Lens" says whose fault it is and pairs with the heading (RI-2) |
| **Source** | Where the correction comes from | One word, answers "from what?". The two values name the two answers |
| **Auto** | Use the correction table the camera stored in this file | The PRD's word. The row label and the caption say what it uses, so "Auto" is never a bare promise |
| **Manual** | Set the correction by hand | The PRD's word |
| **Amount** | The hand-set strength, signed | The Masks heading's Amount is a different control; the row label stays short and the VoiceOver names are distinct (§11) |
| **Constrain to image** | Zoom in just enough that the corrected photo has no empty edge | The PRD's phrase (R7), in the check box's sentence style (P5) |
| **table** | The numbers a camera stores in the file to describe its lens | The PRD's word. Never "profile" (above) |

In sentences, VoiceOver and the user guide: "distortion", "vignetting",
"source", "table" in lowercase as common nouns (P5).

## 2. Where it lives

**Under the existing Lens heading, Distortion and Lens Vignetting first.**

```
Presets · Crop & Straighten · Spots · Light · Tone Curve · Color Mixer ·
Black & White · Color Grading · Details · Lens · Masks · Effects

Lens
  Distortion          (new)
  Lens Vignetting     (new)
  Color Fringes
  Color Alignment
```

Why here and in this order:

1. **The heading exists and its name was chosen for this** (CA §2: "Distortion
   and lens vignetting join it later"). A second heading would split lens
   things across the tab.
2. **Geometry first.** The tab is in workflow order, not render order, but here
   the two agree and the person's order agrees with both: fix the shape, then
   the light at the corners, then the colored edges, which are judged on the
   corrected image (AC5: the fringe picker and Color Alignment work on it). The
   renderer's order is R5's; vignetting's gain actually runs before Exposure,
   which the tab does not show and needs not.
3. **Auto is what most people do with a wide raw, so it is the first thing they
   see.** The two groups sit above the fringe tools, which need picking and
   judging at 100%.
4. **No new heading state.** `Adjustments.Section.lens` gains the two groups
   (`.distortion`, `.vignetting`, in front of `.colorFringes`, `.colorAlignment`);
   the heading keeps its expansion key (`adjust.section.lens`), expanded by
   default, its check box (mixed when only some groups are on), its reset ("Reset
   Lens") and its context menu (Turn Off / On, Reset, Collapse All, Expand All).
   The tab gets about 190 pt longer with all four groups open. I did not fold the
   Lens heading by default (Black & White's choice, B1), because that would
   change the tab for people who have it open; judgment, and a one-key change if
   the tab proves too long.

## 3. Inspector layout

```
Lens                                               [✓] ⟲
Distortion                                         [✓]
Source      [    Auto    |   Manual   ]
Using the camera's correction table from this file.        ← caption, 4 pt under the row
[✓] Constrain to image                                     ← check box, both sources
Lens Vignetting                                    [ ]
Source      [    Auto    |   Manual   ]
No vignetting table was found in this file. Choose
Manual to set the amount by hand.
Color Fringes                                      [ ]
 …
```

With **Manual** chosen the Amount row appears under the caption, before the
check box:

```
Distortion                                         [✓]
Source      [    Auto    |  Manual   ]
Set by hand. Positive values straighten lines that bow
outward, negative values lines that bow inward.
Amount      ──────────●─────────────────    [  +12 ]
[✓] Constrain to image
```

Every row is a standard control through the wrappers the tab already has. No new
component, no custom view.

### 3.1 The group check boxes: always shown (L2)

Every other group's check box is shown only once the group has an edit, because
moving a control is what creates the edit. These two groups differ in the way
Black & White differs (BW §3.1): **switching on with Auto, with nothing else
moved, is itself an edit**, so there is no control to touch first. So:

- The check box (`GroupToggle`'s slot, 16 pt, in the group label's row) is shown
  at all times. Unchecked on a photo that never had the group; checked while the
  group is on and not turned off; unchecked while the group keeps values but is
  turned off (the existing kept-but-off state).
- **Checking it** on a photo that never had the group switches the group on in
  **Auto** (§3.2 for the one exception). One undo step: "Turn On Distortion" /
  "Turn On Lens Vignetting". It checks itself when a control of the group changes,
  as every group does (`enableModules`), in the same undo step as that change.
- **Unchecking it** keeps the source, the amount and Constrain to image and shows
  the photo without the correction ("Turn Off Distortion"). Checking it again
  brings them back.
- **The module therefore needs an explicit on value** (default false, left out of
  the stack while false). "On with Auto and no other value" has no other
  representation, since Auto is the default and defaults are left out (R14). `isModified`
  is true while it is on or any other value is away from its default, and the
  stack of a photo that never had the group is byte for byte what it was (AC1,
  AC12). This is the same device as Black & White's `isOn`; it is a model
  requirement and not a UI choice (RI-4).
- **The heading's check box** is unchanged: checked while all modified groups
  apply, mixed while some do, and its Turn Off / On and Reset reach the new
  groups like the others. Those paths change Distortion too, so they take the
  warning of §6.
- **A reset of one group** has no button (none of the Lens groups has one). The
  way back to "off, nothing stored" is **Reset Lens** (the heading's reset),
  which resets all four groups, or uncheck the group to keep its values.
  Double-clicking Amount resets that slider to 0.

### 3.2 Source (L3)

A row in the 80 pt label column: the label **Source** (11 pt secondary, as every
row label) and a small two-segment control, **Auto | Manual** (`AppKitSegmented`,
`.selectOne`, `.fillEqually`, `fillsWidth: true`; BW §3.2's component). Two
segments in about 176 pt (the label column, the gap, then the rest of a 256 to
396 pt content width) fit with room: each segment is at least about 65 pt in the
current design, so the row asks for about 218 pt at the narrowest. The engineer
confirms with `print inspectorwidth` (§15) that the Lens heading reports `fits`
at 256 pt in both designs.

- **Why a segmented control and not a pop-up.** Two mutually exclusive values
  whose state the person wants to see and flip in one click (compare the
  camera's correction with their own). A pop-up hides the state behind a click
  (HIG Segmented controls; the Heal / Clone precedent, healing §3). The labels are
  not nouns ("Auto", "Manual"), a small departure from the HIG's noun rule that
  Heal / Clone also take; they are the standard names of the two modes, and the
  row label "Source" gives the control its noun. The HIG says a labeled segmented
  control does not need introductory text; I keep the label because "Auto"
  alone does not say auto *what*, and the tab's other rows all have one. Judgment.
- **Choosing a segment** is one undo step ("Distortion Source" / "Lens Vignetting
  Source"), turns the group on if it was off (B10's rule), and keeps both modes'
  values. Choosing the selected segment changes nothing and records no step.
- **Starting in Manual.** On a file where Auto cannot apply (a non-raw file, a
  raw the camera decoder already corrects, a Fujifilm raw with its built-in
  correction; §5), checking the box starts the group in **Manual** in the same
  step, since Auto would be a dead end there (R9; owner ruling RI-1). Everywhere
  else the first source is Auto (R3).
- **Tooltips** (HIG: one per segment): Auto "Use the correction table the camera
  stored in this file."; Manual "Set the correction by hand."
- **Dimming.** The Auto segment alone is dimmed on a file where Auto cannot apply
  (§5), with a tooltip that names the reason. A dimmed segment cannot be chosen.
  If the stack holds Auto there (the default of a photo never touched, or it came
  by paste or preset), no segment is selected (as Black & White's segmented
  control shows none while the sliders are a mix) and the caption says what to do
  (§4). Manual is never dimmed, and the control is never dimmed as a whole (the
  owner ruled that Manual works on a corrected raw). `AppKitSegmented` needs a
  per-segment enabled flag and a selection of -1 (the latter it already passes
  through).

### 3.3 Amount (L4, L5)

- **Shown only in Manual.** In Auto there is nothing meaningful to show: a
  camera's table is a curve, not a number, and a slider fixed at some made-up
  value would suggest it can be moved. This differs from Color Alignment, whose
  automatic result *is* two numbers and so shows them for fine-tuning (CA R10).
  The cost is the switch: a person who likes the camera's correction and wants a
  little less must go to Manual, which starts from its own value, not the
  camera's. The caption in Auto says so in one clause (§4). A "Strength" slider
  for Auto is a possible follow-up, not asked for here (R2 and R3 name only the
  manual Amount); I did not add scope.
- **One slider per group**, `AdjustSlider`, label **Amount**, `.signed`, range
  -100 to +100, default 0, step 1 (↑ / ↓ in the field, ×10 with Shift, as every
  slider), double-click resets to 0, the row's context menu offers Reset "Amount".
  A typed value outside the range is clamped by the field and refused by the model.
- **Units are the engineer's, with this intent**: ±100 is the most a real lens
  needs, and one step is a change you can just see in a corner at 100%. For
  Distortion, +100 corrects roughly the barrel of a very wide zoom at its widest
  (corner displacement of the order of 10% of the half-diagonal; the engineer
  fixes the number from the owner's files and records it in `status.md`). For Lens
  Vignetting, ±100 is about ±2 EV at the corner, which is what a fast prime wide
  open loses. The fall-off shape is fixed; there is no Midpoint or Feather
  control (not asked for; PRD non-goals).
- **Sign convention: the slider is a correction.** Positive undoes what wide
  lenses do (straightens barrel, lightens dark corners), because that is the
  case nearly every photo needs, so the common move is to the right. Negative
  does the opposite, which also serves the creative uses (darker corners). The
  sentence is the Manual caption and the row's tooltip and VoiceOver help (§4,
  §11), because a slider cannot print end labels.
- **Turned-off look.** While the group is unchecked its row shows as turned off
  (secondary label and value, no fill) and stays usable; changing it checks the
  group and applies in one step (the `showsTurnedOff` pattern).
- **Undo label**: "Distortion Amount", "Lens Vignetting Amount" for a drag, a
  typed value, an arrow step, a double-click reset (not the slider's own name, so
  Undo and History read the same whichever way the value was set).

### 3.4 Constrain to image (L6, R7)

A check box under Distortion's other rows, `AppKitCheckbox` at `SliderRow.height`,
title **Constrain to image**, **on by default**, in both sources (the camera's
table can leave a blank edge as well as a hand value). Its help: "Zoom in
slightly so the corrected photo has no empty edges." What it means for the person:

- **On:** the corrected photo keeps its frame's size and shape and fills it, a
  little larger than before for barrel correction. The edges are never blank (AC7).
- **Off:** the lines are straightened at the scale the lens recorded at the
  center, and the edges may show a blank border. The border is not filled with
  invented content (judgment: the PRD asks for no fill), and loupe, previews and
  export agree on what it is (R10); the engineer says which fill (black, or
  transparent in PNG-like exports) in `status.md`.
- The existing crop is unchanged and still applies after correction (R7). It
  stays usable while Distortion changes. Its rectangle is a share of the corrected
  frame, so the picture under it changes with the correction, as it does for any
  other geometry change; nothing is rewritten.

It is stored as a value left out while it is on (`constrain`: false is the
stored case), so it adds nothing to the stack for an unchanged group (R14).
Vignetting has no such control: it never changes the frame.

An undo label is "Turn On Constrain to Image" / "Turn Off Constrain to Image".
A change here moves the frame and takes the warning (§6).

## 4. Captions: one role at a time (L7, L11, R12)

One caption per group, 11 pt secondary (`.caption`), wrapping, 4 pt under the
Source row and left-aligned with the row labels (it describes the source, not the
check box below it). Its text is the **first row that applies** in the order
below, so the person always reads the most important true thing.

| # | State (the group's source status) | Distortion | Lens Vignetting |
|---|---|---|---|
| 1a | The photo is already corrected by the system decoder; Auto is stored or nothing is stored (no segment selected) | Applied by the camera decoder, so Auto does nothing here. Choose Manual to add your own correction. | (same) |
| 1b | The same, Manual selected | Applied by the camera decoder. Auto does nothing here; your amount is added on top of it. | (same) |
| 2a | A Fujifilm raw LibRaw decodes, with its built-in correction; Auto is stored or nothing is stored | Applied by the camera's own table, so Auto does nothing here. Choose Manual to add your own correction. | (same) |
| 2b | The same, Manual selected | Applied by the camera's own table. Auto does nothing here; your amount is added on top of it. | (same) |
| 3 | Kernels cannot run and this group would need them (Manual with an Amount other than 0, or Auto with a table) | (warning symbol) Lens correction could not be set up on this Mac, so this group changes nothing. | (same) |
| 4 | Auto, the file's table is being read, and it takes longer than 0.5 s | Reading the camera's table… (mini spinner) | (same) |
| 5 | Auto, a table exists but is damaged or not understood | (warning symbol) The camera's table in this file could not be read, so nothing is corrected. Choose Manual to set the amount by hand. | (same) |
| 6 | Auto, table found, group on | Using the camera's correction table from this file. | Using the camera's vignetting table from this file. |
| 7 | Auto, table found, group off | This file has a camera correction table. Turn on Distortion to use it. | This file has a camera vignetting table. Turn on Lens Vignetting to use it. |
| 8 | Auto, a raw with no table | No distortion table was found in this file. Choose Manual to set the amount by hand. | No vignetting table was found in this file. Choose Manual to set the amount by hand. |
| 9 | Auto stored on a non-raw file (which cannot have Auto), no segment selected | This file has no camera correction table, so Auto isn't available. Choose Manual to set the amount by hand. | (same) |
| 10 | Manual | Set by hand. Positive values straighten lines that bow outward, negative values lines that bow inward. | Set by hand. Positive values lighten the corners, negative values darken them. |

Notes:

- **The source is always named** (R12): "the camera's correction table from this
  file" (a table), "the camera decoder", "the camera's own table" (Fujifilm's
  built-in), "by hand" (Manual). Rows 8 and 9 say how to get to Manual where the person
  needs it. A person who wants the camera's result a little weaker finds the way
  in the user guide (§19), not in a caption that would be wrong on most photos.
- **"Applied by the camera decoder"** (R4, AC4) is the first sentence of rows 1
  and 2, in the PRD's words, followed by the consequence for Auto and what Manual
  does (owner ruling RI-1: Auto never applies on these photos, Manual works on
  top). It reads the same for both groups. Rows 1b and 2b replace the Manual
  caption (row 10) on these photos, because the person must know their amount is
  *added* to the camera's correction; the sign sentence of row 10 is then only
  in the Amount row's tooltip and help (§3.3, §14).
- **Row 3 beats rows 1b and 2b** (a Manual amount that cannot run must say so),
  but rows 1 and 2 beat every row below them, so the Auto-inert fact is never
  hidden by a table that the file also carries (a decoder-corrected raw may still
  hold a table; Auto must not apply it). Row 3's "Auto with a table" never occurs
  on those photos, since Auto does not run there.
- **Rows 3 and 5 carry `exclamationmark.triangle`** next to the text, in the
  Spots limit caption's pattern (healing §7), so the problem is never conveyed by
  color or position alone. They are the only warnings in the group. R11 and AC11:
  with the kernel forced to fail, or a corrupt table, the group says so.
- **Row 7 needs the table's presence to be known while the group is off.** That
  is a metadata read on every photo that shows the Adjust tab. If it is not cheap,
  the engineer drops row 7 and shows row 8's cousin only after the group is on:
  an off group then reads "Straightens lines a lens bends. Auto uses the camera's
  table stored in the file." (judgment; the design works without row 7).
- **Row 4 (reading)** exists only if the read can take noticeable time. The
  spinner is a mini `ProgressView` with no visible label, tooltip and VoiceOver
  label "Reading the camera's table", after 0.5 s (SMP §5, CA §3). If the read is
  instant the row is never seen.
- **The strings of rows 7 and 8 use the group's own noun** (distortion table,
  vignetting table) because a Panasonic raw can carry one and not the other; the
  two groups then show different rows.
- The caption never changes while a slider moves, so the layout does not jump
  during a drag.

## 5. Every state

What is true of the photo decides the group's body. The one new idea is that
**Auto can be unavailable** (dimmed segment, no effect) while Manual always works.

| Photo or state | Source control | Amount | Constrain | Check box | Caption row | Render |
|---|---|---|---|---|---|---|
| **New raw, nothing stored** | Auto selected, enabled | Hidden | Shown (Distortion) | Shown, unchecked | 7 if a table exists, 8 or the fallback otherwise | Unchanged: renders exactly as before (R1, AC1) |
| **Raw with a table, group on, Auto** | Auto selected | Hidden | Shown | Checked | 6 | Corrected from the table |
| **Raw, no table, Auto** | Auto selected | Hidden | Shown | Checked | 8 | Unchanged, and says why (AC3) |
| **Manual** | Manual selected | Shown | Shown | Checked | 10 | Corrected by the amount |
| **Group turned off (unchecked)** | Whatever was chosen | As that source | As is | Unchecked | 7 or 10, secondary | Without the group |
| **A raw the decoder corrects (rows 1a, 1b), or Fujifilm's built-in correction (rows 2a, 2b)** | Auto segment dimmed, tooltip below; Manual enabled; no segment selected while Auto is stored, nothing stored included | Shown in Manual | Shown, enabled (it applies to the amount added on top) | Enabled | 1a or 2a; 1b or 2b with Manual | Auto never applies, so with Auto the render equals the render with the group off (R4, AC4); Manual adds the person's amount on top of the camera's correction (owner ruling RI-1) |
| **Non-raw file (JPEG, HEIC, TIFF, the JPEG of a pair)** | Auto segment dimmed, tooltip below; Manual enabled | Shown in Manual | Shown | Enabled | 10, or 9 if Auto is stored | Manual only (R9, AC9) |
| **Table unreadable (row 5)** | Auto selected, enabled | Hidden | Shown | Checked | 5 | Unchanged (R11, AC11) |
| **Kernels cannot run (row 3)** | As stored | As stored | As stored | As stored | 3 | Unchanged (R11) |
| **Show Original (`\`)** | As is | As is | As is | As is | As is | Without the correction, as without every edit |
| **Crop session** | Usable | Usable | Usable | Usable | As is | Corrected; the crop frame is shown over the corrected photo |
| **Comparing, video, offline, unreadable stack, loading, grid, review** | The tab's existing states (N1, comparison §11); no controls | | | | | The stack is never written over when unreadable (R14) |
| **A virtual copy, one file of a RAW+JPEG pair** | As its own file | | | | | Each has its own stack and its own lookup (R9, AC9) |
| **A monochrome or HDR photo** | Nothing special | | | | | |

- **Auto being unavailable does not stop the group.** The check box, Manual, its
  Amount and Constrain to image all work; the stored values travel with Paste and
  presets to photos where Auto *can* apply (R8). With Auto stored on such a photo
  (no segment selected), the render equals the render with the group off, which
  is AC4's wording; the person is told by the caption (rows 1a, 2a) and can choose
  Manual to add their own correction.
- **No double correction.** Auto, the only source that applies the camera's table,
  never runs on these photos, so the camera's correction is never applied twice by
  the app. Manual is the person's deliberate amount, visible in the picture and
  named as "added on top" in the caption, the same as Manual on a JPEG.
- **The dimmed Auto segment stays in its place**, so the control looks the same
  from photo to photo of a folder and the person can see which of their photos
  Auto reaches.
- **The Auto segment's tooltip when dimmed**, by reason: non-raw: "Auto isn't
  available: this file has no camera correction table."; the camera decoder:
  "Auto isn't available: the camera decoder already corrects this photo."; Fujifilm's
  built-in table: "Auto isn't available: this photo is already corrected by the
  camera's own table."
- **How the app knows** which row applies (the decoder case, the table, the
  non-raw case) is the PRD's engineer questions. If the engineer cannot tell per
  file whether the system decoder corrected it, they raise a Design question and
  I rule; I do not design around "unknown" in advance, because the only safe
  default (treat as corrected) turns the group off for every system-decoded raw.
- **Ruled (RI-1, 2026-11-19).** The owner decided that Manual works on a raw the
  camera decoder or Fujifilm's built-in table already corrects, with Auto inert
  there. This design follows it. For the engineer: Manual applies to the image as
  it comes from the decoder (already corrected), about the sensor's center like
  every other lens step, in the same place in the render as on any other photo;
  nothing in the decoder or the Fujifilm step changes (non-goal).

## 6. The warning when the frame changes (R6, AC6)

### What triggers it (L10)

The mask and spot frame is the frame **after lens correction** (R6). A change to
Distortion therefore moves the picture under every stored mask object and spot
(Option A: nothing is remapped). Before the change commits, the app asks, when
**all** of these are true:

1. The change would **really move the corrected frame**: the net distortion
   transform before and after differ (turning on Auto where there is no table or
   where Auto is inert, or Amount from 0 to 0, move nothing, so they never ask;
   Manual on a decoder-corrected raw does move it, and asks). The model
   says "frames differ", the UI does not guess from the control.
2. The photo has **at least one mask object or spot** (counted whether the group
   is turned off or not).
3. It is a **deliberate edit of the open photo or selection**: a check box, the
   heading's check box or Turn Off / On, Source, Amount, Constrain to image, Reset
   Lens, Paste Adjustments or Apply Preset.

It **never** asks for: Undo, Redo, reverting to a History entry (each restores a
state the person already had, and undo is itself the way back), Reset All
Adjustments (it clears masks and spots with the rest; the engineer confirms it
clears both), Lens Vignetting or any non-geometric group, a hover preview, or
anything while comparing (editing is off there).

**Once per visit.** After the person answers Change for a photo, further
Distortion changes on that photo ask no more **until they leave it** (another
photo, the grid, review) or a mask or spot has been added since. Asking on every
step of a drag, an arrow-key sequence or a try-three-amounts session would turn a
warning into a toll, and the HIG advises against alerts for "common, undoable
actions". R6 says each change warns; this is the version that keeps the warning
useful (RI-3, which also offers the alternative of no alert).

### Where in a gesture

- **A check box, a segment, a menu or paste:** asked before the change is made.
- **An Amount drag, a typed value or an arrow step in the field:** the live frames
  render as the person drags, so they *see* the correction and the masks moving;
  the question is asked **when the gesture commits** (mouse up, Return, the first
  arrow step of the visit). While it is up the slider shows the new value and the
  photo the new frame. **Cancel puts both back** (the slider knob, the field, the
  frame) and records nothing; Change saves one undo step. An alert cannot be put
  up in the middle of a slider's tracking loop, so asking at commit is the only
  place that does not break the drag.
- **Typing in the field:** asked when Return or Tab commits the value; Esc
  cancels typing as always.

### The alert

An alert sheet attached to the library window (`WindowModal`, the way the
comparison refusals and the removal question are put up), the app icon (no caution
symbol: nothing is lost and the change is undoable, HIG Alerts "use a caution
symbol sparingly").

| Part | Single photo | A selection (paste, preset) |
|---|---|---|
| Title | Change distortion on a photo with masks or spots? | Change distortion on photos with masks or spots? |
| Message | Masks and spots are placed in the corrected frame, so this photo's can move away from what they cover now. You can undo the change. | %lld of the %lld photos have masks or spots. They are placed in the corrected frame, so they can move away from what they cover now. You can undo the change. |
| Buttons | **Change** (default, trailing), **Cancel** (Esc and ⌘.) | same |

- **The default button is Change**, because the person chose the change on
  purpose and it is undoable; making Cancel the default would be wrong (HIG:
  "you don't want to make a Cancel button the default button"), and no button is
  destructive-styled for the same reason (HIG: not for an action people
  deliberately chose). "Change" is the verb of what the button does (HIG: prefer a
  verb that "relates directly to the alert text"); "OK" and "Continue" are not.
- **A selection** gets **one** alert for the whole command, with the counts, when
  at least one receiving photo has masks or spots and the change moves its frame.
  Cancel cancels the whole command (nothing is written to any photo). Change
  applies to all as one undo step with History entries per photo, as Paste does
  today. The counts are photos whose frame would move and that hold masks or
  spots, over the photos receiving the group.
- **Sheets that are already up:** the question waits behind them (`LibraryModal`),
  as the preset report does.
- **A confirmation does not remember a suppression choice.** The HIG allows a
  "don't ask again" checkbox on repeating alerts; I did not add one, because there
  is no setting to undo it and a person who suppressed it once would never learn
  why their spots moved. Once per visit is the relief.

**HIG disagreement, said once.** The HIG's advice is not to alert for common,
undoable actions; the better pattern is to apply the change and say, in the group,
"Masks and spots may have moved. Undo to put them back." The PRD asks for a
warning *before* the commit that can be cancelled (R6, AC6) and the owner accepted
that default, so this design provides it, as narrowly as it can. RI-3 asks the
product manager to confirm or choose the inline notice.

## 7. What a masks-and-spots photo shows afterwards

Nothing special in the inspector. After the change the mask and spot overlays,
rings and previews all follow the corrected frame (they use the mask frame as
ever), so the rings and the picture stay in step; they may no longer sit on what
they were put on. Undo restores the earlier frame and the masks and spots as they
were. The healing record's rule holds: say in `status.md` which frame a stored
position is in and show a ring landing on the same pixels after a correction
(healing §15).

## 8. Menu bar, keys, context menus, toolbar (L13)

**No menu item, no shortcut, no toolbar item.** Reasons:

1. **Parameters are not commands (N10).** The group check boxes and sliders of
   every other heading have no menu items; the two new groups are the same kind
   of thing. The B&W submenu was justified by "one deliberate whole-photo change"
   whose quick-set had no other keyboard route; a pair of check boxes does not
   meet that bar, and a person with the system's Keyboard Navigation on reaches
   every control here by Tab (CA §11 reading: with default settings Tab stops at
   text fields only, in this app as in every Mac app).
2. **Menu-bar reachability is already met where it matters.** Copy / Paste
   Adjustments, Apply Preset and Reset All Adjustments carry the groups (§9), and
   the heading's context menu has Turn Off / On and Reset.
3. **A shortcut is wrong for it.** Every bare key is taken by culling and tools;
   this is a once-per-photo-set correction, not a frequent action.
4. **Batch.** "Correct every selected photo from its camera table" is a real
   wish after an import of wide-angle shots. It is served by a preset of the two
   groups set to Auto (§9), which asks for no new surface. A direct **Adjust ▸
   Auto Lens Correction** on a grid selection is proposed as a follow-up (§18).

**Context menus.** The Lens heading's standard one. The group labels have none
(CA's neither). The loupe's and grid's photo menus get nothing (UIR §7).

## 9. Paste, presets, copies, pairs, Lightroom (L14, R8, R9)

- **Copy and Paste Adjustments** and **presets** carry both groups with all their
  values: on, Source, Amount, Constrain to image. Paste replaces the target's two
  groups with the source's; a source that never had them turns the target's off.
  The **Save Preset** group list and **Manage Presets** show **Distortion** and
  **Lens Vignetting** in that order, in the Lens group of the list, before
  **Color Fringes** (`Group` declared in that order). "Include" defaults: checked
  when the photo has the group on or any value away from its default. A preset of
  only these two groups applies to any number of photos as one undo step.
- **Each receiving photo reads its own table** when the source is Auto (R8): the
  stack stores Auto, not the sender's numbers. A photo with a table gets its own
  correction; a photo with no table is **unchanged and its caption says no table
  was found** (row 8), and the manual Amount the stack carried is **kept, not
  applied** while Source is Auto (R8: "keeps the sliders' values"; RI-5 confirms
  this reading). On a file where Auto cannot apply (a non-raw, a decoder-corrected
  raw, a Fujifilm built-in raw), the pasted Auto is stored with no segment
  selected and the caption of row 9, 1a or 2a; the pasted Manual Amount, if
  Manual was pasted, applies (owner ruling RI-1).
- **A photo that cannot be corrected** (its original is offline or cannot be read,
  so its table cannot be looked up) is **left unchanged by that command**, none of
  the command's groups apply to it, and Activity says so with the existing
  sentences ("‹N› photos were left unchanged: their originals are offline." and its
  unreadable sibling, CA §10, §19 DQ-2; extend their catalog comments, add no new
  text). This applies only to a paste or preset that carries these groups with
  Auto on, as Color Alignment's rule does. The engineer says in `status.md`
  whether the lookup needs the file at paste time; if the table is read when the
  photo renders, no photo is refused and this rule never fires (AC8's "reported"
  then reads as the caption alone; the engineer reports which case it is).
- **An "All settings" preset** (one saved before this feature, or with every box
  checked) replaces every group, so applying it to a photo whose Distortion is on
  turns it off, and takes §6's warning when that moves a frame with masks or
  spots. Manage Presets can take the groups out of it. The user guide says so,
  next to the same note for Black & White and Color Fringes.
- **Preset and look-up table hover previews** show the groups at once; they never
  ask the §6 question (a preview commits nothing).
- **Virtual copies and RAW+JPEG pairs.** A copy starts with the original's groups
  (Auto included; it reads the same master's table) and changes independently. The
  two files of a pair are separate; the JPEG's group has no Auto (R9, AC9). No UI.
- **Lightroom and other imports:** no change. Lens-profile settings still import
  as "lens corrections" in the report's left-out list; mapping them to Auto is a
  product decision, not part of this feature (PRD non-goals).
- **Sidecars and originals** are never written for these groups, as for every edit.

## 10. Order and what the groups do not do

User-visible consequences of R5, which the guide says once:

- **Distortion renders first among the adjustments**, before Color Fringes and
  Color Alignment and before the crop. The fringe picker, the Fringe Map, Color
  Alignment's measurement and the Pixel Magnifier's pixels are all of the
  corrected image (AC5). One consequence for a string that already exists: the
  magnifier plate says **"Before edits"** (CA §20). With Distortion applying, the
  pixels shown are the corrected ones, so I rule the plate then reads **"After
  lens correction"** (one new string, §14), and "Before edits" otherwise. The
  engineer says if the picker samples before it.
- **Vignetting's gain renders before Exposure and the tone sliders**, not after
  Effects' Vignette: lens falloff is part of the recorded light, the creative
  vignette is a look that comes last. The two never fight; the user guide says so.
- **Distortion does not move red against green** (L15, judgment): a camera
  table may describe each color separately, and applying that part would stack on
  Color Alignment's automatic measurement and double-correct the fringes. The
  group straightens lines with the table's green (reference) part only; fringes are
  Color Alignment's job, which exists. The engineer confirms this is possible
  with the tables the owner's cameras store; if a maker's table cannot be
  separated, they raise it as a Design question.
- **The optical center is the center of the whole sensor, before the crop**, as
  Color Alignment's (CA R9), so a crop never changes how a scene point is
  corrected.

## 11. Accessibility and VoiceOver

- **Order**, per group: the check box, the Source control, the Amount slider and
  its field (Manual), Constrain to image (Distortion), then the caption as plain
  text. The group's heading label is read with the check box.
- **Check boxes:** named "Distortion" and "Lens vignetting" ("Distortion,
  checkbox, unchecked"), help "Turn on Distortion" / "Turn off Distortion to
  compare" (the `GroupToggle` strings). The always-shown unchecked state reads
  naturally.
- **Source control:** label "Distortion source" / "Lens vignetting source"; each
  segment speaks its name, selected state and tooltip as help. Dimmed segments
  speak "dimmed" with the tooltip that says why. "No segment selected" is spoken
  as the system control speaks it.
- **Amount:** slider "Distortion amount", field "Distortion amount value"; "Lens
  vignetting amount" and its value. Help: row 10's sentence. The visible label is
  "Amount" twice on the tab (and once in the Masks heading); the longer names keep
  them apart in the rotor.
- **Constrain to image:** the check box with its help. 
- **The caption** is plain text read in order; rows 3 and 5's symbol is
  decorative (the words carry it).
- **Announcements** (posted when the control that caused them would not speak
  for itself): when a status becomes known after the person acts, the caption's
  sentence, once: after checking a group ("No distortion table was found in this
  file."), after a paste or preset on the open photo (the open photo's caption),
  and after a table fails to read (row 5). Not on every redraw.
- **The alert** is a standard `NSAlert`: VoiceOver reads the title, message and
  buttons; Return = Change, Esc and ⌘. = Cancel.
- **Keyboard.** Default settings (Tab reaches text fields only): the Amount fields
  (↑ / ↓ steps, Return or Esc hands the keyboard back, `SliderRow`); the groups
  themselves are not reachable without the system setting, as no other group's
  check boxes are. Keyboard Navigation or Full Keyboard Access: Tab reaches, in
  order, per group, the check box, the Source control (←/→ moves between its
  segments, Space chooses), the Amount field, Constrain to image. Nothing here
  needs a pointer. (Judgment, as CA §11: not adding menu items for the group state
  keeps N10; if QA finds the keyboard route falls short, menu items are an
  addition, not a redesign.)
- **Increase Contrast:** no new colors. Every control is a system control; the
  warning symbol is the system's. Nothing relies on a hairline.
- **Reduce Transparency, Liquid Glass:** nothing here draws glass. The
  inspector is the system's pane, the controls are content-layer controls in it,
  the alert is the system's sheet. Nothing new is stacked on glass.
- **Reduce Motion:** no animation of our own; the photo re-renders as for any
  slider.
- **Color is never the only signal:** the source is named in words, the warnings
  have a symbol and words, the on state is a check mark.
- **Touch-display Macs:** the inspector's small controls, tuned for a pointer; the
  two-segment control is as small as Color Grading's. Nothing depends on hover.

## 12. No map or overlay (L12, R13)

R13 asks whether a preview of where the correction samples from is needed. **No.**

- The Fringe Map and Sharpening Map exist because their effect is a *selection*
  the eye cannot see on the photo (a gray fringe looks like a gray branch). Lens
  correction's effect is plainly visible: lines straighten, corners lighten, and
  Show Original (`\`) and the check boxes compare it at once. There is nothing
  hidden to reveal.
- A grid overlay or a displacement map would be a third on-photo view competing
  for the one map slot (CA §6) and the red mask overlay, for no decision the
  person makes with it.
- Where a person does need to know whether a table was found, the caption says it
  (§4); that is the information a map would have been a roundabout way to give.

## 13. Custom chrome

None. Every element is an existing component: `AppKitSegmented` (with a
per-segment enabled flag, which sets a property of the same `NSSegmentedControl`),
`AdjustSlider`, `AppKitCheckbox`, `GroupLabel`, inspector caption `Text`, a mini
`ProgressView`, a system `NSAlert` sheet. The one wrapper change, the per-segment
flag, is the whole justification this document owes.

## 14. Strings

All by hand in `Sources/PhotoUI/Resources/Localizable.xcstrings`
(`LocalizationTests` fails on a literal with no entry). None contains the product
name. Reuse an existing key and extend its comment where one exists ("Amount",
"Auto", "Source" may exist; "Distortion" and "Lens Vignetting" are new).

| English | Where | Comment for translators |
|---|---|---|
| Distortion | Group label, preset group list, undo names through "Turn On %@" | Lens group: straightens lines a lens bends |
| Lens Vignetting | Same | Lens group: corrects dark or light corners a lens causes. Not the creative Vignette |
| Source | Row label | Where a lens correction comes from: Auto or Manual |
| Auto, Manual | Segments | Source choices: the camera's table in the file, or set by hand |
| Use the correction table the camera stored in this file. | Auto tooltip and help | |
| Set the correction by hand. | Manual tooltip and help | |
| Auto isn't available: this file has no camera correction table. | Auto tooltip when dimmed | |
| Amount | Row label | Reuse; add the lens use |
| Distortion amount, Distortion amount value, Lens vignetting amount, Lens vignetting amount value | VoiceOver | |
| Distortion source, Lens vignetting source | VoiceOver, the control | |
| Positive values straighten lines that bow outward; negative values straighten lines that bow inward. | Amount tooltip and help, Distortion | |
| Positive values lighten the corners; negative values darken them. | Amount tooltip and help, Lens Vignetting | |
| Constrain to image | Check box | Zoom in so there is no empty edge |
| Zoom in slightly so the corrected photo has no empty edges. | Check box tooltip and help | |
| The captions of §4 (distortion and vignetting forms of rows 6, 7, 8 and 10; the shared forms of rows 1a, 1b, 2a, 2b, 3, 4, 5, 9) | Group caption | Source status of a lens correction group |
| Auto isn't available: the camera decoder already corrects this photo. | Auto tooltip when dimmed, decoder-corrected raw | |
| Auto isn't available: this photo is already corrected by the camera's own table. | Auto tooltip when dimmed, Fujifilm built-in | |
| Reading the camera's table | Spinner tooltip and VoiceOver label | No visible label |
| Turn On Distortion, Turn Off Distortion, Turn On Lens Vignetting, Turn Off Lens Vignetting | Undo and History | Existing "Turn On %@" with the group's title |
| Distortion Source, Distortion Amount, Lens Vignetting Source, Lens Vignetting Amount | Undo and History | |
| Turn On Constrain to Image, Turn Off Constrain to Image | Undo and History | |
| Reset Lens | Existing "Reset %@" | |
| Change distortion on a photo with masks or spots? | Alert title | Shown before a lens correction that moves the frame of a photo with masks or spots |
| Change distortion on photos with masks or spots? | Alert title, a selection | |
| Masks and spots are placed in the corrected frame, so this photo's can move away from what they cover now. You can undo the change. | Alert message | |
| %lld of the %lld photos have masks or spots. They are placed in the corrected frame, so they can move away from what they cover now. You can undo the change. | Alert message, plural forms | %lld counts photos |
| Change | Alert button | Confirms a lens correction change |
| After lens correction | Pixel magnifier plate, line 2, when Distortion applies | The magnifier shows the photo after lens correction |
| No distortion table was found in this file. | VoiceOver announcement (the caption's first sentence) | |

Reused with no new text: "Cancel", "Turn On %@", "Turn Off %@", "Reset %@",
"Collapse All", "Expand All", and the Activity "left unchanged" sentences (their
comments extended, §9). Captions, tooltips and the alert message are sentence
style, group labels and undo names title style (P5).

## 15. Notes for the engineer (behavior, not code)

1. **What the UI needs from PhotoCore** for each group: the stored on value, the
   Source (Auto or Manual), the manual Amount, Constrain to image (Distortion);
   and, from the photo and its file, a **source status** that is one of: table
   found, decoder corrects, Fujifilm built-in, no table, non-raw (no Auto),
   table unreadable, reading, kernels cannot run; plus **whether the net frame
   differs** between two stacks (for §6), and the count of masks and spots.
   One function gives the caption row, the segment states and the check marks
   (as `FringeMapStatus` does for the badge and the legend).
2. **Explicit on** (§3.1) as `BlackAndWhite.isOn`, left out while false;
   `enableModules(changedFrom:)` treats a change of Source, Amount or Constrain as
   turning the group on; `Section.lens`, `Group` and the preset list in the order
   of §9; `Group.presetGroups` includes both.
3. **Defaults** left out: on false, Source Auto, Amount 0, Constrain true. A reset
   gives the identity hash (AC12). Unknown newer-schema stacks are refused as
   before (R14).
4. **The warning** (§6) is a gate on the commit paths of `setEnabled`, the
   Distortion setters, Reset Lens and the batch paste and preset, asking via
   `WindowModal`; Cancel restores the control and the frame. The once-per-visit
   flag clears on a change of photo and on adding a mask or spot. Undo, redo and
   History never go through it.
5. **Where the model must say "Auto not available"**: for a non-raw, the decoder
   case and Fujifilm's built-in correction, Auto never applies; Manual does, on
   the image as decoded (§5, owner ruling RI-1). The UI needs this per photo to
   dim the Auto segment, pick the tooltip and caption row (1a, 1b, 2a, 2b, 9) and
   start a newly checked group in Manual. If the engineer cannot tell the decoder
   case per file, raise it (§5).
6. **Table lookup per photo** at render time or at paste; say which in `status.md`
   (§9), and whether a read can take long enough for row 4.
7. **Frames.** Crop, the mask and spot overlays, `CameraFrame`'s whole-sensor
   decode for raws with a crop, and Color Alignment's measurement all take the
   corrected frame; check the crop overlay and Straighten against it, and show a
   spot ring landing on the same pixels (healing §15).
8. **Edges.** Constrain to image's scale policy (§3.4) must match each camera's own
   JPEG framing where Auto is used (the Fujifilm embedded step scales about the
   center to fill, and agrees with the X-E3's JPEG to a third of a pixel; an X-A5's
   JPEG keeps the recorded scale, `EmbeddedLensCorrection` code review Q12). Where
   a maker differs, "off" is the recorded scale.
9. **Live frames**, fit, 100%, a drag, export and `photocli render` use one
   renderer (R10). A pipeline bump only for photos that turn the groups on (R14).
10. **Kernel and table failures** are messages on the group (§4 rows 3 and 5), not
    a log line. The Lens kernels' existing silent skip (RI-CR1 for Color Fringes and
    Color Alignment) is **not** part of this feature; the same status could be shown
    on their groups as a follow-up (§18).
11. **Strings** (§14) by hand before `LocalizationTests`; `AdjustText.title` for
    the two groups; the catalog comments as listed.
12. **`AppKitSegmented`** needs a per-segment enabled flag; selection -1 already
    works.
13. **A new SwiftUI `ScrollView` is not to be introduced** (CLAUDE.md "No SwiftUI
    ScrollView under the toolbar"); the groups go in the existing `LensControls`.
14. **Whether a photo is a raw, a JPEG or the like** is known to the editor; say how
    in `status.md`.

## 16. Debug-script hooks (so review and QA can check without screen recording)

The existing `buttons`, `hit`, `print` and `menuitems` cover the panes; the glass
pane note in `CLAUDE.md` applies (snapshots leave the inspector blank; the content
area renders). Please make these checkable, named by the existing pattern:

- `lens print`: for the loupe photo, per group: on, applies, Source, the status
  row of §4 by name, Amount, Constrain, the caption text, the selected segment
  index, which segments are enabled, which controls are dimmed, whether the
  confirmation is up, and whether once-per-visit has been answered.
- `lens distortion on|off|auto|manual|amount <n>|constrain on|off` and
  `lens vignetting on|off|auto|manual|amount <n>`: drive the **same path as the
  controls**, so the §6 gate fires for a photo with masks or spots. Answer it with
  the existing `alert press Change` / `alert press Cancel` (and `alert` to read its
  texts).
- `lens force kernelfail|tablecorrupt|off`: a debug-only switch (never a setting;
  like `--demosaic libraw`) so AC11 can be checked.
- `print inspectorwidth` with the Lens heading open: must report `fits` at 256 pt
  for the Source rows (the `fillsWidth` note).
- `buttons` should list the Source control's segments with their tooltips and
  dimmed state; the Amount rows and the check boxes appear as ordinary controls.
- A `snapshot` of the loupe shows the corrected render; the rows are checked with
  `lens print` and `print`.
- `photocli render` prints, per group, the source status name and whether it was
  applied, beside `decoder`.

## 17. Acceptance checks for the designer's review

1. The Lens heading holds, in order, Distortion, Lens Vignetting, Color Fringes,
   Color Alignment; its check box, "Reset Lens" and context menu reach all four.
2. Both new check boxes are always visible; unchecked on a new photo; checking
   switches Auto on in one undo step named "Turn On Distortion" / "Turn On Lens
   Vignetting"; unchecking keeps the values.
3. Source is a two-segment control with the label "Source" that fits at 256 pt
   (`print inspectorwidth`); tooltips on both segments; choosing records
   "Distortion Source"; choosing the selected one records nothing.
4. Auto shows no slider; Manual shows one Amount, -100 to +100, signed, default
   0, clamping typed values, double-click resets, labels and values per §3.3.
5. Constrain to image is shown under Distortion only, on by default, and has the
   undo labels of §14.
6. Every caption row of §4 appears in the state that §5 says, reads as written,
   names the source, and warnings (rows 3 and 5) carry the symbol and the words.
7. A raw the system decoder corrects, and a Fujifilm raw LibRaw decodes, show the
   Auto segment dimmed with the tooltip for its reason; the group is not dimmed;
   turning it on starts in Manual (caption 1b or 2b); with Auto stored (a paste, or
   nothing stored) no segment is selected, the caption is 1a or 2a, and the render
   with the group on equals the render with it off (AC4); choosing Manual and an
   Amount adds a correction on top of the decoder's (owner ruling RI-1).
8. A JPEG, and the JPEG of a pair, show the Auto segment dimmed with its tooltip;
   turning the group on starts in Manual; a pasted Auto shows no selection and row
   9 (AC9).
9. With a mask or spot present, a check box, Source, Amount (at commit),
   Constrain, Reset Lens, Paste and Apply Preset that move the frame show the §6
   alert with the right title and buttons; Cancel leaves the stack, the slider and
   the frame as they were; Change saves one undo step (AC6). It does not appear
   for Vignetting, Auto where it is inert, a change that moves nothing, Undo, Redo,
   History, Reset All, or a second change on the same visit.
10. A selection paste shows one alert with the counts; Cancel changes no photo.
11. Paste and a preset give each receiving photo its own Auto result; a photo with
    no table is unchanged with row 8; an offline photo is left unchanged with the
    existing Activity sentence (AC8).
12. The Save Preset list and Manage Presets list the two groups in the order of §9;
    an old all-settings preset turns them off.
13. Strings, undo and History names read as §14; no hard-coded color; no new
    custom view; Increase Contrast, Reduce Transparency and Reduce Motion on.
14. The Pixel Magnifier plate reads "After lens correction" when Distortion
    applies.
15. Show Original removes the correction; Reset returns the identity stack
    (AC12).

Manual checks for a person (M1 and on) go into `review.md` after the build; they
will be, at least: the Lens heading at the narrowest and widest inspector, light,
dark and Increase Contrast; the alert's look and keys with a real keyboard, a
drag released with masks present and Cancel; each of the owner's five cameras'
files beside its own JPEG (Auto within about 1 px in the outer quarter, by eye);
Constrain to image on and off on a wide raw; a preset applied to a selection that
mixes a table, no table and a JPEG; the owner's X-E3 (Fujifilm built-in) and a
system-decoded raw with Auto stored, then Manual on top, reading the dimmed Auto
segment, its tooltip and the 1a, 1b, 2a, 2b captions at 256 pt; the slider's
step at 100%. None asks for
VoiceOver or macOS 15 and 26 (the owner's standing rule).

## 18. Requirements issues (all ruled by the owner, 2026-11-19)

All five were ruled as designed, RI-1 in the option this section recommended;
the rulings are in §21. The text below is kept as the question that was asked,
and the design above is amended to the answers. The product manager amends R1,
R3, R4, R6, R7, R14 and AC4 and AC6 in the issue body to match.

1. **RI-1. R4 against R9: can Manual work on a photo that is already corrected?**
   **Ruled: yes.** Manual works on a decoder- or Fujifilm-corrected raw; Auto is
   inert there (§5).
   R4 says where the system decoder or Fujifilm's built-in table already corrects,
   "our step does not apply", and AC4 says the render with the group on equals
   the render with it off. R9 says a file the camera already corrected has no Auto
   but "manual still works". I applied R4 and AC4 as written to **raws** (the
   group is inert in both sources, §5) and R9 to **non-raw** files (JPEGs), the
   only reading in which all three hold. The consequence matters to the owner:
   most of his files (a system-decoded Panasonic RW2 and OM System ORF, X-T3 and
   X100S if the system decoder corrects them, and every X-E3 raw through
   Fujifilm's built-in table) may be inert, so on them this feature does nothing
   and Manual cannot be used. If the owner would rather let Manual work **on top**
   of a decoder-corrected raw (Auto still inert, so nothing is corrected twice
   unless the person chooses to), the design change is small: Source stays enabled
   with Auto inert and a caption that says Manual adds to the camera's correction
   (§5 rows 1 and 2, §4). Recommended: rule it, preferably yes for the decoder
   case; it needs no pipeline change. For Fujifilm's built-in table AC4 as
   written holds only for Auto. Please rule and amend R4 and AC4 either way.
2. **RI-2. Wording. Ruled: accepted.** (a) The second group is titled **Lens Vignetting**, not
   "Vignetting": the Effects heading's **Vignette** is a group of its own and the
   two would sit side by side in the Save Preset list and in undo names (§1). (b)
   The check box reads **Constrain to image** (sentence style, P5; the PRD
   capitalizes it as a feature name). Please amend R1 and R7.
3. **RI-3. R6 and AC6: an alert for an undoable change. Ruled: the narrow alert
   of §6 is accepted.** The HIG advises against
   alerts for common, undoable actions, and its better pattern is to apply the
   change and tell the person, with undo as the way back. The PRD asks for a
   warning before the commit with Cancel, and I built it (§6), narrowly: only when
   the corrected frame really moves on a photo with masks or spots, **once per visit
   to the photo** rather than on every change (a drag, a typed value or a session of
   tries would otherwise ask every time), once for a whole paste, never for undo,
   redo, History or Reset All. Please amend R6 and AC6 to "warns before the first
   change that moves the frame on a visit" with those exceptions, or rule that an
   inline notice after the fact ("Masks and spots may have moved. Undo to put them
   back.") replaces the alert. The owner's warn-versus-lock question (PRD open
   questions) is answered: warn.
4. **RI-4. R1 and R14: the check box is always shown and the module needs an
   explicit on value. Ruled: accepted.** Auto is the default and defaults are left out, so "on with
   Auto" has no other representation; the check box cannot wait for an edit to
   appear (§3.1). It is Black & White's RI-3 over again. Please say so in R1 and
   R14 ("defaults left out" holds: on false is left out).
5. **RI-5. R3 and R8: "keeps the sliders' values", and the first source on a
   non-raw. Ruled: accepted** (and, with RI-1, the same start in Manual applies
   to every file where Auto cannot apply). I read R8's "a photo with no table keeps the sliders' values" as
   *the manual Amount a stack carries is kept and travels but is not applied while
   Source is Auto* (R3: Auto with no table does nothing), not as a fallback that
   applies it. Please confirm. And on a file where Auto cannot apply (R9), checking
   the box starts the group in Manual, not Auto, so it is never a dead end (§3.2);
   please add this exception to R3's "Auto is the default".

Proposed follow-ups (new issues, not this branch):

- **Auto Lens Correction on a grid selection** (Adjust menu, one undo step, the
  Activity "left unchanged" rule), the direct form of the preset in §8.
- **A Strength slider for Auto** (percent of the camera's correction), for the
  person who wants the camera's result a little weaker without losing it (§3.3).
- **Show a source status on Color Fringes and Color Alignment** when the Lens
  kernels cannot run (they skip silently today: RI-CR1).
- **Lightroom lens settings into Auto** in the preset import (PRD non-goal today).

## 19. User guide points (`docs/USER_GUIDE.md`, by the engineer in the same change)

Under **Lens**, ahead of Color Fringes, a **Distortion** and **Lens
Vignetting** paragraph; and the Lens opening sentence, which now says the heading
has four groups:

1. **What and where.** The Lens heading now has **Distortion** and **Lens
   Vignetting** first, each with its own check box (always shown) and Source,
   then Color Fringes and Color Alignment. Photos you never touch render as before.
2. **Source.** **Auto** reads the correction table your camera stored in the raw
   file. **Manual** is one **Amount**, -100 to +100: for Distortion positive
   straightens lines that bow outward (barrel), negative lines that bow inward; for
   Lens Vignetting positive lightens the corners, negative darkens them. Auto has
   no slider; to take the camera's correction a little weaker, switch to Manual and
   set your own. Manual starts from its own value, not from the table's. On a raw
   the camera decoder already corrects, and on a Fujifilm raw with its built-in
   correction, Auto does nothing (the Auto segment is dimmed and the caption says
   so), but Manual still works: your amount is added on top of the camera's
   correction. A new group on such a photo, or on a file that is not a raw, starts
   in Manual.
3. **Constrain to image** (Distortion): on by default, it zooms in just enough
   that the corrected photo has no empty edge; off keeps the lens's own scale and may
   leave a blank edge. Crop applies after correction.
4. **What the caption tells you.** Which source is in use ("Using the camera's
   correction table from this file", "Set by hand"), and why nothing happens when
   it doesn't: no table in the file; already corrected by the camera decoder or by
   Fujifilm's built-in table (Auto does nothing there; Manual still works and
   adds to the camera's correction); a file that is not a raw has no Auto (JPEGs
   are corrected in the camera; set the amount by hand); a table that could not be
   read, or a Mac that could not run the correction.
5. **Masks and spots.** Their frame is the **corrected** frame. Changing Distortion
   on a photo that has masks or spots asks first, since they can move away from
   what they cover; Cancel leaves everything as it was, Change is one undo step.
   It asks once per visit to the photo, once for a whole paste or preset, and never
   for Undo, Redo, History or Reset All Adjustments. Lens Vignetting never asks.
6. **Order.** Distortion is applied first, before Color Fringes and Color
   Alignment and before the crop, which they all work on; Lens Vignetting lifts the
   corners before Exposure and the tone sliders, so it is not Effects' Vignette,
   which comes last. Distortion does not move red against green: that is Color
   Alignment.
7. **Presets, paste and a whole shoot.** Both groups copy and paste and go into
   presets; each photo reads its own table for Auto. To correct a whole shoot, save
   a preset of the two groups on Auto and apply it to the selection. A preset with
   all settings replaces the two groups too (and can turn Distortion off).
8. **Undo and History.** "Turn On / Off Distortion", "Distortion Source",
   "Distortion Amount", the Lens Vignetting forms, "Turn On / Off Constrain to
   Image", and "Reset Lens".
9. **Lightroom presets.** Unchanged: lens settings are still listed as left out.
10. **No change** to anything else: photos with these groups off render as before.

README at Ship (product manager): one line in the feature list.

## 20. Assumptions (stated, not blocking)

- The ranges' units and the engineer's numbers (§3.3) give a usable result at the
  ends; if not, the engineer changes the numbers, not the ±100.
- A table's presence is cheap to know for a photo shown in the Adjust tab (§4 row
  7); otherwise the fallback of §4 applies.
- The system decoder case can be told per file (PRD question to the engineer); if
  not, a Design question comes back.
- The magnifier's "After lens correction" (§10) is right if the picker samples
  after Distortion; the engineer confirms.
- Expanded by default is kept for the Lens heading (§2).
- The one-visit rule's "visit" is the loupe's photo being the current one; moving to
  another photo and back asks again.

## 21. Rulings

Owner rulings of 2026-11-19 on the requirements issues of §18:

- **RI-1.** Manual **works** on a raw that the system decoder or Fujifilm's
  built-in table already corrects; **Auto is inert** there. The group is not
  dimmed: only the Auto segment is (tooltip by reason), a stored Auto shows no
  segment selected, a newly checked group starts in Manual, and the captions are
  rows 1a, 1b, 2a, 2b of §4. AC4 holds for Auto: the render with Auto equals the
  render with the group off. Manual adds on top of the camera's correction and
  takes the §6 warning like any frame change. Built into §3.2, §4, §5, §6, §9,
  §11, §14 to §17 and §19.
- **RI-2.** The group is **Lens Vignetting**; the check box is **Constrain to
  image**.
- **RI-3.** The narrow alert of §6 stands (only when the frame really moves on a
  photo with masks or spots, once per visit, once for a whole paste or preset,
  never for undo, redo, History or Reset All).
- **RI-4.** The check box is always shown; the module carries an explicit on value.
- **RI-5.** A stored Manual Amount is kept and not applied while Source is Auto;
  a group checked on a file where Auto cannot apply starts in Manual.

Design questions from implementation are recorded below as numbered rulings
(DQ-1, ...) with their date.

## Revisions

- **2026-11-19.** First design, from the approved PRD of 2026-11-18.
- **2026-11-19 (later).** Owner rulings on RI-1 to RI-5 recorded (§21, §18 marked
  ruled). RI-1 changes the design: the whole-group "inert" state is gone. On a
  decoder- or Fujifilm-corrected raw only Auto is inert (dimmed segment, stored
  Auto shows no selection, new groups start in Manual) and Manual works on top.
  Amended: summary L8 and L9, §3.2 (starting in Manual, dimming), §4 (rows 1 and 2
  split into 1a, 1b, 2a, 2b and the notes), §5 (states and notes), §6 (trigger),
  §9 (paste), §14 (two tooltips), §15 item 5, §17 checks 7 and 9 and the manual
  checks, §19 items 2 and 4, §21. §11 and §16 need no change (a dimmed Auto
  segment and the status rows were already covered).
