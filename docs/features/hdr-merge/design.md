# HDR merge: design

Owner: apple-ui-designer. Date: 2026-11-20. Revised 2026-11-21.
Issue: #150. Status: complete (second pass 2026-11-20: §6.1 cases 6a and 6b,
§7.3 reasons, §13 strings, D-H5, RI-H4; revision 2026-11-21: the reference
choice and the Auto-align and De-ghost check boxes, see the note below and
§20). Four requirements issues are open for the
product manager (§17). §1–§16 already assume the default given for each, so the
engineer can start; a different ruling changes only the lines §17 names.

**Revision 2026-11-21 (owner rulings of that date, revised PRD of the same
date).** The PRD now lets the person choose any listed frame as the
**reference** (R3), and adds two check boxes, **Auto-align** and **De-ghost**
(R9, R10), both checked every time the sheet opens, not remembered. `photocli`
takes the same three choices (R17); with Auto-align off no frame is refused for
failing to line up (A14); an extreme reference is not warned about (A13). What
changed in this file: the term "naming photo" is gone (one concept, the
reference); §1 (two rows added); §5 (the diagram, §5.2 made selectable, §5.3's
Name, Folder and caption, and new §5.5 to §5.8: how the reference is chosen,
the two boxes, the height, what updates when the reference changes); §6
(cases 6 and 9 follow the reference, new §6.4); §7.1 and §7.3 (phases, one
failure text); §10, §11 (accessibility), §13 (strings), §14 (script),
§15 (guide), §16 (H17 to H21, manual checks M8 to M14), §17 (the PRD's open questions 6 to 9 answered)
and the rulings in §20 (D-H6 to D-H10). The rest stands as
written. Where a line below still says what the first revision said and §20
disagrees, §20 holds.

**Inputs.**

- Requirements: the PRD, the body of issue #150 (approved by the owner
  2026-11-20), R1–R18, AC1–AC14, A1–A9. Cited as "R‹n›", "AC‹n›", "A‹n›".
- Current design: [`../ui-redesign/design.md`](../ui-redesign/design.md) (cited
  as "UID"; placement rules P1–P5), [`../library-ops/design.md`](../library-ops/design.md)
  ("LO": File menu groups, removal blocked by running jobs, §8) and
  [`../virtual-copies/design.md`](../virtual-copies/design.md) ("VC": File menu
  placement of a command that makes new items, §2.1).
- Code read in this worktree: `Views/LibraryCommands.swift` (File menu),
  `Views/LibraryMenuContext.swift` (`canExport`, `canDuplicate`),
  `Grid/PhotoContextMenu.swift`, `Views/ExportSheet.swift` (the sheet this
  one follows), `Views/ActivityToolbarItem.swift` (`ActivityJob`, popover),
  `PhotoCore/Browser/ActivityLog.swift`, `StoppableJob.swift`,
  `Import/QuitConfirmation.swift`, `PhotoUI/QuitGuard.swift`,
  `Model/LibraryModal.swift`, `Model/DuplicateActions.swift`,
  `Model/LibraryOpsActions.swift` (`canRemoveFromLibrary`),
  `Model/DebugScript.swift` (command list), `docs/USER_GUIDE.md` (key table).
- HIG page read 2026-11-20 (markdown version): Keyboards (standard shortcuts,
  custom shortcuts, modifier order). The rest of the guidance applied here
  (File menu, ellipsis, dimming, sheets, alerts) is the HIG reading already
  recorded in UID, LO and VC, which cite those pages; I did not fetch them
  again for this design.

**Custom chrome.** None. Every surface is a system component: a File menu item,
`NSMenu` context-menu items (as the grid builds them), one SwiftUI sheet made
of `Form`, `Table`, `Picker` (segmented) and buttons (the Export sheet's
form), the toolbar's Activity item and popover, and a system alert for the
quit question. The one optional addition is an action button on an Activity
message (§8.3, R18, a Could); it is built from a standard `Button` in the
existing popover row.

## 1. Answers to the PRD's designer questions

| Question | Answer | Section |
|---|---|---|
| Where the command lives | **File ▸ Merge to HDR…**, ⇧⌘L, second item of the photo-file group, right after Duplicate. Also in the grid's context menu, after Duplicate. Not in the toolbar, the loupe, the sidebar or the Photo menu | §2, §3 |
| When it is off, and when it refuses | Dimmed only when the reason is plain from the selection: fewer than two photos selected, a merge already running, a sheet up. Everything else (mixed raw and non-raw, offline, read-only folder, more than 9, a video among several, a copy beside its own original, frames of different sizes) is answered **in the sheet**, which names the frames at fault and keeps Merge off. Nothing is written until the person presses Merge | §4, §6 |
| Format choice | In the sheet, a segmented **TIFF / DNG** control, TIFF first and the default. When the DNG writer is not built (the engineer's spike, Open question 1), the control is absent and the sheet says what the file is | §5 |
| Choosing the reference (Open question 9, 2026-11-21) | **Click the frame's row in the Photos table** (a single-selection table: the selected row is the reference, always exactly one). The row keeps a "Reference" mark in words. Arrow keys move it, VoiceOver selects the row. No pop-up, no separate control | §5.5, D-H6 |
| Auto-align and De-ghost (Open question 9) | Two system check boxes, **Auto-align** and **De-ghost**, in the Photos section under the table's caption (not in Result), each with a one-sentence caption that says what unchecking does. Both checked on every open | §5.6, D-H7 |
| Progress and cancel | A job in the toolbar's Activity item, determinate, phase named in the popover; Stop in the popover and **File ▸ Stop Merge** (⌘.). A cancel or a failure leaves the library unchanged and posts one Activity row | §7 |
| The new master afterward | An ordinary photo of the reference's project and folder, in capture-date order beside its frames, named `IMG_1234_HDR`, with a TIFF or DNG type badge. It is **selected and scrolled into view only if the person has not changed the selection or the source** while it ran; otherwise Activity says where it is | §8 |
| Marking it | By name and type badge only. No "merged" mark, because no provenance is stored (A6) and no migration is planned | §8.2, RI-H3 |
| Undo | One step, "Merge to HDR": the photo leaves the library, the file stays, Activity names its path | §9 |
| Empty states | None needed: the item is dimmed with nothing to act on, and the sheet always has frames to show | §4 |
| Accessibility | System controls throughout; the refusal text sits first in the sheet's reading order; flagged rows carry a symbol and text, never color alone; the result and failures are announced | §11 |
| macOS 15 | No conditional UI: every component exists on 15 and gets the earlier look there | §12 |

**The words.** The command is **Merge to HDR…**, and what it makes is a **merged
photo**. A frame is one of the selected photos. The **reference** is the one
frame the person chooses (by default the 0 EV one): it names the result, says
where it is saved, supplies its metadata, is what the others are lined up to
when Auto-align is on and is where moving things are taken from when De-ghost
is on (PRD R3, A9). There is no separate "naming photo". Words
not used in the UI, the guide or strings: "bracket" as a noun in menus (the
guide may say a "bracketed series" once, since photographers do), "ghost"
except inside the control's name **De-ghost** (the PRD's and the owner's word,
which photographers know; its caption says in plain words what it does;
D-H7) and "registration" (the app says what happens: "doesn't line up"), "stack" (that is
#90), and "version". A merged TIFF is **tone-mapped**, which the sheet and the
guide say once in plain words, because the app's other "HDR" words (the loupe's
HDR badge, View ▸ Show HDR Highlights) are about how a screen shows light, not
about a merge.

## 2. Placement

### 2.1 File menu

The new item is in **bold**. Everything else is as built.

```
Import from Card or Folder…          ⌘I
Add Folder Without Copying…          ⇧⌘I
─────────────
New Album…                           ⌘N
New Smart Album…                     ⌥⌘N
Edit Smart Album…
Rename “‹name›”…  /  Rename “‹project›”
Delete “‹name›”…
Remove Project from Library…
─────────────
Duplicate                            ⌘D
**Merge to HDR…**                    ⇧⌘L
Show in Finder                       ⇧⌘R
Export…                              ⇧⌘E
Remove from Library…                 ⌘⌫
─────────────
Check for Changes on Disk
Stop ‹job›                           ⌘.
─────────────
Close                                ⌘W
```

- **Why File.** The HIG's File menu is where a command that makes a new item
  from existing ones lives (VC §2.1 made the same argument for Duplicate). The
  group already holds the commands that act on the photo targets as library
  items. Merge makes a new photo and a new file, so it sits beside Duplicate,
  which also makes new photos. The Photo menu changes values on photos; this
  adds one.
- **Why the ellipsis.** The command opens a sheet that asks for a choice
  (HIG Menus: the ellipsis signals that more choices follow), and the sheet is
  where the refusals appear.
- **Title** stays "Merge to HDR…" for any number of photos; the sheet title
  carries the count.

### 2.2 Context menu

- **Grid:** **Merge to HDR…** is the second item of the group that holds
  Duplicate, Export… and Show in Finder, giving the order Duplicate, Merge to
  HDR…, Export…, Show in Finder, RAW+JPEG Pair ▸. The existing order is kept.
  Left out (not dimmed) when it can't act (UID P2), so a right-click on one
  photo doesn't list it.
- **Loupe and video loupe:** left out. The loupe acts on one photo, so §4's
  rule never holds there. (A person who wants to merge the photos around the
  one in the loupe goes back to the grid, selects them and chooses the item.)
- **Comparison panes:** left out, same reason (they act on the active photo).
- **Film strip, sidebar:** nothing, as for Duplicate.

### 2.3 Not placed

- **Toolbar:** nothing, not even as a palette item. Merging is occasional
  (a few times a session at the most), ⇧⌘L and the context menu are close at
  hand, and the toolbar holds the frequent commands (HIG Toolbars). Judgment.
- **Inspector:** no button.
- **VoiceOver custom actions on the grid:** none. The grid's action list stays
  the frequent culling commands (UIR §10); VO-Shift-M reaches the context menu.
- **A drop target** (dragging photos onto something): no. Selection is the
  series, and the menu is the one way in.

## 3. Key

| Command | Key | Why | Conflicts checked |
|---|---|---|---|
| Merge to HDR… | **⇧⌘L** | R1 asks for a key. The letters that suggest the command all have a standard Command key: H (Hide), M (Minimize), and the HIG says "avoid creating a new shortcut by adding a modifier to an existing shortcut for an unrelated command", so ⇧⌘H or ⇧⌘M would break that rule. L has no entry in the HIG's standard table. The key is memorable only as "the one in the File menu"; the menu shows it | Not in the HIG standard table (Keyboards, read 2026-11-20). No `keyboardShortcut("l", …)` anywhere in `Sources/`; nothing in `ImportCommands`. Not used by the text system. Modifier order and use follow the HIG (Shift as the secondary modifier, Command primary, no Control) |

**Enablement follows Export, not Duplicate.** Merge uses `can`, not
`canByKey`: it is enabled whichever pane has the keyboard (grid, search field,
inspector). The reasons ⌘D and ⌘⌫ are limited to the grid (a key a text field
also wants; acting on something the person isn't working in) don't apply:
⇧⌘L isn't a text-editing key, and the command opens a sheet that shows the
frames it will act on before anything happens. This is judgment.

No bare key is added: a single letter that starts a one-minute job is too easy
to press by mistake.

## 4. Enablement

**The targets** are what the other photo commands act on: the grid's
selection, counted as the grid shows them (a grouped RAW+JPEG pair is one).

**File ▸ Merge to HDR… and the context item are enabled when all hold:**

1. there are **at least two targets** (AC1);
2. no merge is running (§10);
3. no other sheet, dialog or alert of the library window is up (as every
   library item).

That is all. The check is on catalog state already in memory and never touches
the disk (as Show in Finder's, LO §5.1). Anything else that stops a merge is
found when the sheet opens (§6), because a dimmed menu item can't say why, and
"why" is exactly what a person with eight photos selected and a video among
them needs to be told. This is the HIG's rule that an item stays listed and is
dimmed only when it plainly can't act (UID P1), applied with the exception
that explanation matters more than the dim.

**One video selected, none, one photo:** dimmed (AC1). Two or more targets with
a video among them: enabled, and the sheet refuses naming the video (R14,
AC12). This reconciles AC1 and R14; see RI-H1.

**While comparing or cropping:** the loupe has one target, so the item is
dimmed without a rule of its own.

## 5. The Merge to HDR sheet

A sheet on the library window (window-modal), built like the Export sheet (a
fixed header, one `Form` column, Cancel and the action), because it is the
same kind of task: a command with a few choices about a file that gets
written, over a selection that must not change under the person's hands. The
sheet **freezes its frames** when it opens, as Export does; it is added to
`LibraryModal` (§16, N1).

```
┌─ Merge 3 Photos to HDR ──────────────────────────────────┐
│ [thumb]  Merge 3 Photos to HDR                           │
│          From All Photos                                 │
│          ⚠ <the refusal, when there is one>              │
├──────────────────────────────────────────────────────────┤
│ Photos                                                   │
│  Photo               Type   Shutter   Compensation       │
│  IMG_1233            RAW    1/250 s   −2 EV              │
│ ▌IMG_1234  Reference RAW    1/60 s    0 EV   (selected)  │
│  IMG_1235            RAW    1/15 s    +2 EV              │
│  “IMG_1234” names the result and where it is saved.      │
│  Click another photo to change it.                       │
│  ☑ Auto-align                                            │
│    Lines the other photos up to the reference. Off:      │
│    merged as they are.                                   │
│  ☑ De-ghost                                              │
│    Moving things, such as people, come from the          │
│    reference only. Off: plain blend.                     │
│ Result                                                   │
│  Format        [ TIFF | DNG ]                            │
│  16-bit, Display P3, tone-mapped. Looks right in any app.│
│  Name          IMG_1234_HDR.tif                          │
│  Folder        …/Trip/Day 2                              │
│  The originals are not changed, and your adjustments are │
│  not used: the photos are merged as they were shot.      │
├──────────────────────────────────────────────────────────┤
│                                    [ Cancel ]  [ Merge ] │
└──────────────────────────────────────────────────────────┘
```

The reference is the selected row (the bar and "(selected)" in the sketch stand
for the system's selection highlight, which this design does not draw by hand).
The sheet is 560 pt wide and at most 600 pt tall (§5.7).

### 5.1 Header

- A 44 × 44 pt thumbnail of the reference frame (the Export header's form),
  then the title **Merge ‹N› Photos to HDR** (13 pt semibold, plural rule) and
  a subtitle **From ‹source›** (11 pt secondary: the sidebar source the
  Export sheet names).
- **The refusal or note** goes under the subtitle, where Export puts its
  general issue (`IssueText`: `exclamationmark.triangle` and text). One message
  at a time, the first that applies in §6's order. Putting it in the header
  makes it the first thing read, by eye and by VoiceOver.
- ‹N› counts **frames** (a pair is one), which can be fewer than the targets.

### 5.2 Photos section

- A `Table` of the frames in **capture order** (earliest first; the order
  that decides "first" in R3), **with single selection: the selected row is
  the reference** (§5.5; it was "no selection" in the first revision), no
  sorting, and the rows never reorder when the reference changes, 24 pt rows, as many
  rows as frames (2 to 9; above 9 the first nine plus the refusal), with a
  height that fits them and scrolls past 250 pt.
- **Columns:** **Photo** (the display name, `PhotoName.display`, so a copy
  reads "IMG_0412 copy"; the reference's name is followed by a secondary
  "Reference" that is never truncated: the name gives way first, cut in the
  middle with its full text as a tooltip, and the mark is `fixedSize`; the
  owner's screenshot showed it cut to "Referen…"), **Type** (RAW, JPEG, HEIC, TIFF: the grid's badge words, so a
  pair reads RAW), **Shutter** (the frame's exposure time, "1/250 s"), and
  **Compensation** ("−2 EV", "0 EV", "+2 EV", from the metadata; "—" when the
  file has none). Aperture and ISO are not columns: a bracket varies shutter
  or compensation, and four columns fit the sheet without a horizontal
  scroller. Numbers use `monospacedDigit`.
- **A flagged row** (the frame a refusal is about) starts with
  `exclamationmark.triangle`, and its accessibility value says "Problem". The
  message in the header says what the problem is. Never color alone.
- **Caption under the table:** "“‹reference›” names the result and where it
  is saved. Click another photo to change it." 11 pt secondary, like the Export
  sheet's captions, one line at 560 pt for a name of ordinary length. It
  replaces "names the result and is the photo the others are lined up to": the
  lining up is now the Auto-align caption's (§5.6), since it can be turned
  off. It also tells a person that the rows can be clicked, which a table
  doesn't show by itself; the role "Reference" is the row's own mark, so the
  caption doesn't repeat it. The metadata the result takes is said by the
  guide (§15), not the sheet (height, §5.7).
- **A non-blocking note** (information, `info.circle`, 11 pt secondary, in the
  same place as the caption) when every frame has the same shutter, aperture,
  ISO and compensation and none of them is missing: "These photos have the
  same exposure settings. Merging them won't widen the range of light." It
  doesn't stop the merge; a person may have a bracket whose metadata lies (a
  manual flash series). Judgment, not in the PRD: it prevents the commonest
  wasted minute. Left out if the engineer finds the metadata unreliable.

### 5.3 Result section

- **Format.** A segmented `Picker`, **TIFF** and **DNG**, in that order, TIFF
  selected the first time. The choice is kept as a preference (Export keeps its
  settings), so a person who always wants DNG sets it once. R5's "default
  TIFF" is the first-run value. Under it, a caption that follows the choice:
  - TIFF: "16-bit, Display P3, tone-mapped. Looks right in any app."
  - DNG: "16-bit floating point, not tone-mapped. Tone it in the Adjust tab."
    (Written as 32-bit in the first draft; the system's RAW decoder reads no
    32-bit float DNG, so the file is 16-bit: ruling D-H4, §19.)
  The color space is **Display P3**, tagged with its profile (A7: my
  proposal). It is the working space's output space, it keeps a wide-gamut
  raw's colors that sRGB would clip, and every color-managed viewer reads the
  tag. Using the reference's own space would mean a raw (which has none)
  and a JPEG (sRGB) get different files from the same command. No control: the
  sheet carries no color-space choice in v1.
- **If the DNG writer is not built** (the spike's answer, PRD Open question 1),
  the Format row and the DNG caption are **absent**, not a one-item picker and
  not a disabled "DNG": a control that offers a thing that isn't there only
  invites the question. The sheet then shows a plain row "Format: TIFF
  (16-bit, Display P3, tone-mapped)". Every other section is unchanged.
- **Name.** A read-only line: the name the file will get now, for the chosen
  format (`IMG_1234_HDR.tif`, or `IMG_1234_HDR-2.tif` when that exists, by
  `MergeNaming`'s numbering, which counts a file or master of the same stem
  in any format as taken, and `MasterFiles`'s rule: D-H5). It changes with the
  format and with the reference (§5.8). The name is decided again when the merge starts (the folder may
  change in a minute); the caption says nothing about that, because the
  difference is rare and the Activity row names the real file.
- **Folder.** The reference's folder (it follows the chosen reference, §5.8), as a path truncated at its head, with
  the full path as its tooltip (the Export sheet's folder row, without the
  Choose button). There is **no folder chooser**: R2 puts the result beside the
  reference. A series from several folders gets one more caption sentence: "The
  photos are in several folders. The result goes in the reference's."
- **Caption under the section:** "The originals are not changed, and your
  adjustments are not used: the photos are merged as they were shot." This is
  the first time the app writes a new file into a source folder; the Folder row
  and the Photos caption now say where ("saved beside it"), so the first
  half of the first revision's caption ("Saved next to “‹reference›”.") is
  dropped as a repeat, which also saves a line of height (§5.7). The sentence
  states A2, which people will otherwise discover by surprise (a white balance
  fixed on one frame is not carried). The "several folders" sentence stays,
  and follows the chosen reference.

### 5.4 Buttons

- **Cancel** (Esc) and **Merge** (Return, the default). The default is right:
  the action writes one new file and changes nothing existing, so a Return
  pressed without reading is harmless (HIG Alerts' concern about default
  buttons is for destructive actions). The label is the verb alone; the
  frames are listed above it.
- **Merge is off** while a refusal shows or while the pre-flight check
  (§6.2) runs. A small `ProgressView` (`.controlSize(.small)`) sits left of the
  buttons only when that check takes longer than about half a second (a slow
  network volume).
- Choosing Merge closes the sheet at once and starts the job (§7). The sheet
  does not stay open with progress: the person can go on working, as after
  Export.

### 5.5 Choosing the reference (revision 2026-11-21, D-H6)

**The control is the Photos table itself: click a frame's row and it is the
reference.** The table is a single-selection `Table` (`selection:` bound to
the model's reference), and the selected row is the reference, always exactly
one.

- **Why this one.** The person chooses by comparing: which frame is the 0 EV
  one, in which has the walker stepped out of the way. Everything they compare
  by is in this table (name, type, shutter, compensation) and the thumbnail in
  the header already follows the reference. Choosing in the place where the
  evidence is is direct manipulation (HIG's principle that people act on the
  thing they see), costs no second control, and keeps the row's "Reference"
  mark and the choice one and the same thing, so they can never disagree.
  Selecting an item from a list to make it the chosen one is also the
  standard Mac meaning of table selection. The effect shows at once just
  below it, in the Name and Folder rows (§5.8).
- **Rejected.** (a) A **Reference pop-up** in the Result section: a correct,
  standard control, but it lists names alone (IMG_1233, IMG_1234,
  IMG_1235), so the person must match a name to a row to know what they are
  choosing, and the table's mark plus a pop-up would be two controls for one fact for
  VoiceOver to read. It is the fallback if the table's selection proves
  unworkable (see the engineer note). (b) A **radio column** in the table: a
  radio is a control, and a table cell that looks like one but is not one
  (or a hand-built one) is custom chrome that forfeits system behavior.
  (c) A **context-menu or Photo-menu action** ("Use as Reference"): hidden
  and one more step; a context menu must not be the only route to a
  setting (HIG Context menus). Not added even as a second route: one way is
  enough for a nine-row list. (d) A **button** "Use as Reference" beside the
  table: a control whose only job is to give the selection a meaning.
- **The cost of selection, and the answer.** A table's selection usually
  means "act on this". The caption under the table (§5.2) says what the click
  does, and the mark "Reference" stays on the row in words, so the state is
  readable when the selection highlight is gray (the table isn't first
  responder, or the window isn't key), with Increase Contrast and
  without color.
- **Rules.**
  - Initial value: the default of R3 (the 0 EV frame, else the first by
    capture time), every time the sheet opens, whatever was chosen before
    (AC3c). Nothing is stored; there is no preference.
  - **Never empty.** ⌘-clicking the selected row, clicking the empty space
    under the rows, or any other way to deselect leaves the reference where it
    was (the selection binding ignores `nil`).
  - **Every listed row can be chosen**, including a row a refusal flags and
    the darkest or brightest frame (A13: no warning, ruling 2026-11-21).
    Choosing a flagged frame doesn't clear the refusal about it; it shows the
    refusal that now applies (§6.4).
  - The rows keep their capture order; the chosen row doesn't move to the top.
  - A video in the series (a refusal, case 3) can still be the selected
    row; the sheet refuses and Merge is off either way.
- **Keyboard.** The table is a Tab stop. Up and Down arrows (and type-select,
  Home and End) move the selection, so move the reference, **immediately**:
  there is no separate commit and no "reference not yet chosen" state. Esc still
  closes the sheet, and the sheet then forgets the choice (AC3c). Return
  still presses Merge, the default button, also with the table focused (a
  table does not take Return when nothing is being edited; manual check M10).
  Initial focus stays on **Merge** when it is enabled, else **Cancel**
  (§11), so the sheet opens with the default reference and a person who
  doesn't touch it is not asked to decide anything.
- **VoiceOver.** Rows are selectable table rows: VO-Space selects one. A row
  is read as name, "Reference" for the chosen one, type, shutter,
  compensation, and "selected" by the system. After a change the sheet posts
  one announcement (§11).
- **Pointer.** One click selects (no double-click, no drag, no hover
  affordance; hover-dependent affordances are not used). Touch-display Macs:
  a row is 24 pt high like every Mac table row and the system gives the
  table its touch behavior; no custom hit area.
- **Engineer note (a risk, not a requirement).** SwiftUI's `Table` lets
  ⌘-click deselect and may show no selection while the binding refuses it.
  If the binding cannot hold "always one" on macOS 15 and 26, restore the
  previous value in `onChange` (a visible flicker of one frame is
  acceptable). If a reliable always-one table selection can't be had, return
  a design question: the fallback is the Reference pop-up of (a), with the
  mark kept on the row.

### 5.6 Auto-align and De-ghost (revision 2026-11-21, D-H7)

Two **system check boxes** (`Toggle` with the checkbox style), **Auto-align**
and **De-ghost**, in that order (the order the work happens: lining up, then
combining), in the **Photos section, under the table's caption**, not in the
Result section.

- **Why there and not in Result.** Result is about the file that gets written
  (Format, Name, Folder), and the owner's two choices are about what is done
  to the photos relative to the reference. Under the table they read in the
  order of the task: which photos, which is the reference, how they are
  combined; then what is written. Putting them in Result above Format would
  separate Format from its own caption; below Format they would sit between
  the file's name and the file's folder choices, as if they were about the
  file. A third section would add a header (about 20 pt) for two lines.
  Judgment, not Apple policy.
- **Labels:** "Auto-align" and "De-ghost" (the PRD's proposal; D-H7 on the
  word "ghost"). Sentence-style, no verbs needed for a check box
  (HIG Toggles: label a check box with what it turns on).
- **Captions** (11 pt secondary, one line each at 560 pt, indented to the
  label's text under the box; they say what the box does and what
  unchecking does):
  - Auto-align: "Lines the other photos up to the reference. Off: merged as
    they are."
  - De-ghost: "Moving things, such as people, come from the reference only.
    Off: plain blend."
  Reasons: A14 (off means as they are, with no check that the scene matches,
  said by "merged as they are") and R10 (off means no region takes its pixels
  from the reference alone, said by "plain blend"). The captions do not say
  "tripod": the box's own effect is the information, and a person with a
  tripod knows. If a caption wraps in another language the form scrolls
  (§5.7).
- **State:** both checked every time the sheet opens, as the model is made
  for the sheet and nothing is persisted (R9, R10, AC9a). Unlike Format,
  which is a remembered preference (§5.3): the owner ruled these two reset.
  They are independent; any of the four combinations can be merged. Never
  dimmed: not by a refusal, not by the format, not by the other box.
- **Nothing else on the sheet changes with them.** No refusal depends on
  either (the different-scene refusal is found by doing the work, §6.3; the
  size and offline refusals apply with Auto-align off too, AC7b), the Name
  and Folder rows don't change, and with both off the reference still names
  the result, gives its folder and metadata (A9). No warning when either is
  off. Both off gives no extra text.
- **Activity follows them** (§7.1): with Auto-align off the job has no
  "Aligning" phase and says "Merging" after reading; with De-ghost off the
  phases are unchanged.
- **VoiceOver.** The box is read as "Auto-align, checked, checkbox"; its
  caption is its accessibility hint (`accessibilityHint` with the caption
  text, the separate caption text hidden from VoiceOver so it is not read
  twice). Space toggles it; both are Tab stops after the table.

### 5.7 Height at the default size (revision 2026-11-21, D-H8)

The sheet stays **560 pt wide** and its **ideal height goes from 560 to 600 pt**
(`minHeight` stays 420). It never grows past that, for any content: more
frames, a two-line refusal in the header, or longer captions only make the
**Form scroll**, between the header and the buttons, which stay in place (the
header's refusal is the first thing read and must stay on screen, §5.1). 600 pt
is about two thirds of the roughly 900 pt a current 13-inch laptop's screen
offers below the menu bar at its default scaling, and still fits on the
smallest scaled laptop display (about 770 pt) with the library window's title
bar above it. A library window shorter than the sheet clamps it to the window
and the Form scrolls (manual check M14).

Budget at the default (3 frames, nothing flagged), in points, estimated from
the Export sheet's construction and the current `MergeSheet` metrics, to be
measured by the engineer (`print` of the form's content height, §14):

| Part | pt |
|---|---|
| Header (44 pt thumbnail + 14 pt padding twice) | 72 |
| Photos section: inset and title 36, table 100 (3 rows × 24 + 28), reference caption 14 | 150 |
| Two check boxes, each 20 + a one-line caption 14 | 68 |
| Row spacing in the Photos section | 30 |
| Result section: inset and title 36, Format 24, its caption 14, Name 20, Folder 20, the shared caption (two lines) 28 | 142 |
| Row spacing in the Result section | 30 |
| Gap between sections, bottom inset | 30 |
| Divider, buttons (control 28 + padding) | 58 |
| **Total** | **580** |

So the common case (three frames) needs no scrolling, with about 20 pt of
slack for metric differences. The first revision's sheet needed about 520
(its ideal height was 560). With nine frames the table grows to its 250 pt
cap and the Form scrolls (about 150 pt). The "same exposure" note (+16 pt) and
a two-line refusal (+14 pt) use the slack or scroll. To keep it so, two lines
were cut from the first revision: the Photos caption was two lines and is
now one, and "Saved next to “‹reference›”." is dropped from the Result
caption (the Folder row says it); and the check boxes' captions are one line
each. If the engineer's measure
shows the default case scrolling, the order to cut is: the Result caption's
second sentence is kept, the checkbox captions are shortened further, and only
then is the ideal height raised, in steps of 20 and never past 640 (a
design question before that).

### 5.8 What updates when the reference changes (revision 2026-11-21, D-H9)

One choice, so everything that came from the old reference follows the new
one **at once**, in the same update, with nothing to confirm:

| Where | What changes |
|---|---|
| Table | the selection and the "Reference" mark move to the row; nothing reorders |
| Header | the thumbnail becomes the new reference's (the old one stays until the new one is ready, never a blank); the title, count and "From …" don't change |
| Table caption | names the new reference |
| Name row | the new reference's stem plus `_HDR` and the format's extension, numbered by `MergeNaming` in the **new** reference's folder (so `IMG_1235_HDR.tif` may read `IMG_1235_HDR-2.tif` where the other folder differs) |
| Folder row, tooltip, and the "several folders" sentence | the new reference's folder |
| Refusal in the header and flagged rows | decided again (§6.4): the folder-writability refusal (case 9) and the size refusal's wording (case 6) follow the reference; the others stay |
| Merge | stays off until the new reference's folder check (§6.2) has finished, then follows the refusals |
| Auto-align, De-ghost, Format | unchanged |
| What gets written | the metadata, project, folder and name of the new reference (R3; AC3a); the sheet doesn't list them beyond the Name and Folder rows |

- **Speed.** The disk check of a folder runs once per folder for the life of
  the sheet and its answer is kept, so moving the reference among frames of
  one folder (the usual series) is instant; a frame in another folder checks
  that folder off the main thread. The Name's number comes from the same
  directory read. An answer that arrives after the reference has changed again
  is discarded (it carries the reference it was for). While the check for a new
  folder runs, Name shows the unnumbered candidate in secondary color, and
  Merge is off; the small spinner by the buttons appears only after about half
  a second (§5.4). This is the same rule as the first open, applied again.
- **Pressing Merge** repeats the check for the reference as it is then (§6.2,
  unchanged).

## 6. Refusals

A refusal is shown in the sheet (§5.1) and nothing is written. The first
that applies, in this order, is the one shown; the rows it is about are
flagged. Two kinds: **from the selection** (known when the sheet opens, in
memory) and **from the disk** (known after the pre-flight, §6.2). Text is
sentence-style, names the frame in curly quotes, and says what to do.

### 6.1 From the selection

| # | Case | Message (title-less; ‹ › filled in) | Flagged rows |
|---|---|---|---|
| 1 | Fewer than two frames (the targets were two files of one RAW+JPEG pair, ungrouped; R14) | "Select at least two different photos. A RAW+JPEG pair counts as one." | all |
| 2 | More than 9 frames (R14, A5) | "At most 9 photos can be merged at once. Select fewer." (plural on 9; the limit is `MergeLimits.maxFrames`) | the tenth onward |
| 3 | A video among the targets (R14) | "“‹name›” is a video. Only photos can be merged." | the video(s) |
| 4 | A copy beside its own original, or two copies of one photo (they are one file; merging reads the master, A2) | "“‹copy›” is a copy of “‹original›”, the same file. Select each photo once." | the copy |
| 5 | A mix of raw and non-raw frames (R8, A4) | "These photos are a mix of raw and non-raw files. Select only raws, or only JPEG, HEIC or TIFF files." | the non-raw frames when raws are the majority or tie, else the raws |
| 6 | Frames of different sizes (see RI-H2) | "“‹name›” is a different size from “‹reference›”. Merged photos must be the same size." Measured **from the chosen reference** (revision 2026-11-21): the message names the first frame (capture order) whose size differs from the reference's. Whether this refusal applies does not depend on the reference (some frame differs from any choice); who is named and flagged does | every frame whose size differs from the reference's |
| 6a | A frame over the pixel limit (`MergeLimits.maximumPixels`, 150 MP; security review M1; ruling D-H5) | "“‹name›” is too large to merge. A photo can have at most ‹150› megapixels." | the frames over the limit |
| 6b | The frames' pixels together would take more than the memory budget (`MergeLimits.frameMemoryBudget`: half this Mac's memory; D-H5) | "These photos are too large to merge together on this Mac. Select fewer." | all frames |
| 7 | An offline photo (R14) | one: "“‹name›” is offline. Connect its drive and try again." Several: "‹N› of these photos are offline. Connect their drives and try again." (plural; the first is named in the table) | the offline frames |

- **A RAW+JPEG pair is one frame, and its file is the RAW** (R8), whichever
  cell was selected and whichever file Photo ▸ RAW+JPEG Pair shows. The Type
  column says RAW, so the choice is visible. The cost: a pair's JPEG selected
  with two stand-alone JPEGs is a mix (case 5). That is rare, and the table
  shows why.
- A copy as the **only** link to its master is fine (case 4 is only about two
  items of one master); the copy's file stem and metadata come from its master
  and from the copy's own rating, flag and label (R7 reads "the reference", and
  when the copy is chosen as the reference that is the item the person selected).
- **Order matters.** Count and kind (1–3) come before content (4–6b) and
  availability (7), so one message answers the most basic problem first. 6a
  and 6b follow 6 (a frame of another size is the more useful thing to say
  first) and 6a precedes 6b (one frame to drop is a clearer instruction than
  "select fewer"). After
  the person fixes it, the sheet is opened again, and the next one shows.

### 6.2 From the disk

Checked once, asynchronously, when the sheet opens, off the main thread (a
network volume can be slow), and again when Merge is pressed (the state may
have changed while the sheet was up). The sheet shows the result of the first
check; the second, if it fails, closes the sheet and posts an Activity warning
(§7.3) rather than a second alert.

| # | Case | Message | Flagged rows |
|---|---|---|---|
| 8 | A master can't be read (missing, no permission; R14) | "“‹name›” can't be read. Check that the file is still there." | that frame |
| 9 | The **reference's** folder can't be written (read-only volume, no permission; R14, AC12). Decided again whenever the reference changes (§6.4) | "The merged photo would be saved next to “‹reference›”, in “‹folder›”, which can't be written to. It may be on a read-only disk, or you may not have permission." | the reference |

- A write check is made by what the file system says about the folder
  (writable, not read-only volume), not by creating a file: a refused merge
  leaves nothing behind (R14).
- **Free space** is not a refusal: the size isn't known until the merge is
  planned. It is a failure (§7.3).
- **Merge already running:** not a refusal; the item is dimmed (§4).

### 6.3 What is not a refusal at open

- **Frames that can't be aligned** (a different scene, R9) are found only by
  doing the work. They fail the job and Activity names the frame (§7.3).
  Offering a "check alignment" step before the merge would cost most of its
  time for the rare case. **With Auto-align off this never happens**: no
  step measures a shift, so no frame is refused for failing to line up and a
  merge of unrelated scenes goes ahead as given (R9, A14, ruling 2026-11-21;
  the box's caption says "merged as they are", and no warning is added). The
  other refusals still apply (AC7b).
- **A corrupt file** that opens but fails to decode: the same, named in
  Activity.

### 6.4 When the reference changes (revision 2026-11-21, D-H9)

Refusals are decided from the frames and the reference together. Only two
depend on the reference (R14); the rest are fixed for the life of the sheet:

| Refusal | Depends on the reference? | When it changes |
|---|---|---|
| 1 to 5, 6a, 6b, 7 (count, kind, video, copy, raw mix, size limit, memory, offline) | No | never while the sheet is open |
| 6 (different size) | The frame named and flagged, and the wording | at once, from memory |
| 8 (a master can't be read) | No | never |
| 9 (the folder can't be written) | Yes: the reference's folder | after that folder's check (§5.8) |

- **A refusal that no longer applies goes away** when the reference changes:
  the header text is replaced (by the next refusal in §6's order, or by
  nothing), the flagged rows update, and Merge is on once the folder check is
  done (AC12: choosing a frame in a writable folder when the first reference's
  folder is read-only lifts case 9; the reverse brings it on). The text names
  the **chosen** reference ("The merged photo would be saved next to
  “IMG_1235”, in …").
- **Case 9 flags the reference's row**, so choosing another row moves the
  flag with the reference; the old reference's row is unflagged unless another
  refusal is about it.
- **A frame in a read-only folder is a legitimate non-reference.** Only the
  reference's folder is written to (R2), so a series with one frame on a card
  mounted read-only merges when the reference isn't that frame.
- **Order is unchanged** (§6.1, §6.2): the first applicable refusal is the one
  shown. A selection refusal that is not about the reference (a video, an
  offline frame) stays on screen whichever frame is chosen, which is right:
  changing the reference can't fix it.
- **Messages and their words are re-read** by VoiceOver when they change
  (§11).

## 7. Running the merge: Activity

The job lives in the toolbar's Activity item and popover and nowhere else:
the sheet has closed, so no alert is attached to a window the person may have
left (UID P4: a background task reports in Activity). No Dock progress and no
notification in v1 (judgment: Export has neither).

### 7.1 While it runs

- **A job in the Activity item** (`ActivityJob`, id `merge`), **determinate**:
  the bar is the fraction of the pipeline's phases, weighted by cost (the
  engineer sets the weights from the spike: read and decode, align, merge and
  de-ghost, tone map, write; the bar never moves backward). **With Auto-align
  off there is no align phase** (revision 2026-11-21): its weight is left
  out when the job starts, so the bar still runs from 0 to 1 and the detail
  goes from "Reading" to "Merging". De-ghost off changes no phase (it is part
  of "Merging").
- **Title** in the popover: `Merge to “‹IMG_1234_HDR.tif›”`. In the toolbar the
  name is fitted by `ToolbarMetrics.statusLine(name:)` (middle-truncated), as
  `Export to “…”` is.
- **Detail** under the title, one of: "Reading 2 of 3", "Aligning 2 of 3",
  "Merging", "Tone mapping", "Saving", "Adding to the library". Two numbers
  and no plural on the second, as the other jobs do ("12 of 24"): the strings
  can't inflect it.
- **Stop** in the popover (`stop:` closure) and **File ▸ Stop Merge** (⌘.).
  `StoppableJob` gains `case merge`. One item serves ⌘. (UID P3), titled for
  the newest job.
- **One merge at a time.** The File item and the context item are dimmed while
  one runs (as Export is, UID I1). A second would double the memory the
  engineer budgets (A5).
- **Not stoppable at the last step.** Once the file is in place, the
  catalog write is a single quick transaction; Stop during "Adding to the
  library" is accepted but takes effect after it (the merged photo is then
  in the library, and Activity says so). This is the one point where Stop
  can't promise "nothing added"; it is a fraction of a second.

### 7.2 Stopped

Stop (the button, ⌘., or quitting through the quit question) ends the work and
leaves **no new file, no catalog row and no partial file** (R11, AC9). The
temporary file is removed. Activity posts one **information** row titled
"Merge to HDR": "The merge was stopped. Nothing was added to the library." The
person asked for it, but the popover otherwise shows nothing happened, and the
row is the record.

### 7.3 Done and failed

- **Success** (R15's Activity requirement, AC13): one **information** row
  titled "Merge to HDR": "Merged ‹N› photos into ‹full path›." The path is
  selectable text (the popover already uses `.textSelection(.enabled)`), and
  the new photo can be shown in the Finder with File ▸ Show in Finder.
  VoiceOver hears "Merged to “‹file name›”." (§11).
- **Failure:** nothing changes in the library, and no file is left except in
  the one case below. One **warning** row titled "Merge to HDR": "The photos
  couldn't be merged. Nothing was added to the library." followed by the
  reason as a second sentence:
  - **Alignment (R9; only with Auto-align on):** "“‹name›” doesn't line up
    with “‹reference›”. Merge photos of the same scene, or turn off
    Auto-align." (revision 2026-11-21: the second clause is the new remedy,
    since the sheet now has the switch; the person can open the sheet again
    with it off.)
  - **Read:** "“‹name›” couldn't be read."
  - **Space:** "There isn't enough space on “‹volume›”."
  - **Write:** "The file couldn't be saved: ‹system reason›."
  - **Too large** (a decoder reports more pixels than the catalog did): the
    6a text, in the same row.
  - **Memory:** "There wasn't enough memory to merge these photos."
  - **Unusable name** (the reference's file name or place in the catalog is
    not one a file can be written beside; a damaged library; D-H5): "A merged
    photo can't be saved beside “‹reference›”. The library's record of its
    file name or location isn't valid."
  - **Same content** (the catalog already holds a photo with the result's
    content; the file is removed again; practically unreachable; D-H5): "The
    library already has a photo with the same content."
  - **Pre-flight changed** (§6.2's second check): the §6.2 message for that
    case, in the same row, nothing started.
  - **Anything else:** the underlying error as the detail, as library-ops does.
- **The one exception: the file is complete but the catalog write failed.**
  Then the file stays (the app never deletes files) and the row is a warning:
  "The merged photo was saved at ‹full path› but couldn't be added to the
  library. Add the folder again to import it." Nothing else is left behind.
- No alert for any of these (UID P4: the person can't act on it beyond trying
  again).

### 7.4 Library window events during the run

- **Closing the window or quitting** asks first, like Export: `QuitConfirmation`
  gains `case merging` (PhotoCore), alert **Quit While Merging?**, message "The
  merge is stopped and nothing is added.", buttons **Keep Merging** (default,
  Return and Esc) and **Stop and Quit**, as every other quit alert has them
  (ruling D-H1, §19). Same host rules as the others (the front-most sheet,
  never an About window).
- **Removing photos or a project** is dimmed while a merge runs (§10): a
  removal that takes the reference's project out from under the merge could
  not leave "library unchanged" and the file both true. This is LO §8's
  mechanism (`RemovalAvailability`).

## 8. The new master in the grid

### 8.1 Where it appears

- A new master is catalogued in the reference's project (R6, whichever frame
  the person chose), so it
  appears in All Photos, that project, the Dates tree and any smart album
  whose rule it meets, like any import. It carries the reference's capture
  date (R7), so with the default capture-date sort it lands **beside its
  frames**; with a file-name sort it lands after `IMG_1234` (the suffix sorts
  after the stem). No special placement.
- **Not** in the albums or keyword sources the frames were in, unless the
  result's own keywords (R7) put it in a keyword source. Albums are not in
  R7's list of what is carried, and a merged photo that appeared in an album
  without being asked would be a surprise. Said in the guide.
- It is shown at once in the grid's sources that can show it, as an import's
  photos are, with the type badge **TIFF** or **DNG** like any such file.

### 8.2 How it is marked

By its **name** (`IMG_1234_HDR`, `IMG_1234_HDR-2`) and its **type badge**. No
glyph on the cell, no caption badge, no smart-album rule. The reason is that the
PRD stores no link from the result to its sources (A6) and plans no migration,
so the app can't tell a merged TIFF from any other; a mark would need a stored
fact. That is judgment, not a rule, and it is raised as RI-H3 in case the owner
wants "find my merges". The name does the work for now, and the search field
finds "_HDR".

### 8.3 What happens when it lands

The aim is to put the result under the person's hand without taking anything
from them.

- **Selected and scrolled into view** when **all** hold when the merge ends:
  the library window is showing the grid or the loupe with a source that
  contains the new photo (All Photos, the reference's project, its date), no
  filter hides it, and **the selection is still exactly the frames** the merge
  was started from (the person hasn't clicked elsewhere). The new photo
  replaces the selection and takes the focus. **In the loupe (and in review
  and comparison) the new photo does not take the selection and the loupe stays
  on the photo it was on**: the person is looking at something. The first
  sentence's "grid or the loupe" is narrowed to "the grid" (ruling D-H2, §19).
- **Otherwise** the selection and focus are not touched. A person who moved on
  to rate other photos doesn't have the selection yanked 40 seconds later (HIG:
  keep people in control, don't move what they didn't act on).
- **R18 (Could): "Show in Library"** — an action button on the Activity row of
  the success message that selects the new photo in a source that holds it
  (All Photos when the current one doesn't) and scrolls to it. It needs one
  addition to the shared Activity popover: an optional action on a message
  (`ActivityLog.Message.action`, a title and a closure id, shown as a standard
  borderless `Button` at the row's trailing edge). If the engineer doesn't
  build it, the row's path and the search field are the way; nothing else
  depends on it.
- A filter that hides the new photo (a rating filter, a flag filter) isn't
  changed: the new photo has the reference's rating, flag and label (R7),
  so it matches whatever made that photo visible, as a copy does (VC §4.2).
  The "stays visible until the filter changes" rule covers it like any photo.
- **Sidecar:** with sidecars on, the new master gets its `.xmp` as any new
  master does (R6, AC4); nothing in the UI shows it.

### 8.4 Empty states

None are needed. With nothing or one photo selected the item is dimmed (§4),
and with two or more the sheet always has frames to show. The sidebar's and
the grid's empty states are unchanged by this feature. A library with no
photos shows no item enabled.

## 9. Undo (R15, AC13)

- **One undo step**, named **Merge to HDR** (Edit ▸ Undo Merge to HDR / Redo
  Merge to HDR). It is registered when the merge **completes** (the catalog
  row exists), as Duplicate registers its own after its write; nothing is on
  the stack while it runs, and Stop is how a running merge is undone.
- **Undo** removes the photo from the library: the catalog row and its
  sidecar-queue entries and its edit history go, **the merged file and its
  sidecar stay on disk**. The selection goes back to the frames. Activity
  posts one **information** row titled "Merge to HDR": "“‹file name›” was
  removed from the library. The file is still at ‹full path›." (AC13).
- **Redo** puts the same photo back (the same row) when its file is still
  there and unchanged; if it is gone or changed, nothing is added and Activity
  posts a warning: "“‹file name›” couldn't be added back because the file has
  changed or is missing."
- **Merging again after Undo** gives `_HDR-2`: the file from the first merge is
  still there, and R4 never replaces a file. The guide says so; the sheet's
  Name line shows it before the person presses Merge, so it is not a surprise.
- **Removing the photo later** with Remove from Library… is the ordinary
  removal (files stay), and clears the undo stack as removals do (LO §6.3).
  The file stays on disk and is the person's to delete in the Finder; the
  guide says that.

## 10. Interactions with other commands

| Situation | Behavior |
|---|---|
| Another merge is running | Item dimmed; context item left out (§4) |
| An import (folder add or card copy) is running | Merge allowed. Both write catalog rows through the model's ordered chain; the engineer confirms (a design question if not) |
| An export is running | Allowed; both are background jobs, ⌘. names the newest |
| Remove from Library…, Remove Project from Library… | Dimmed while a merge runs (§7.4); `RemovalAvailability.canStart` gains `isMerging` |
| Duplicate | Not blocked: a copy makes another version of a master; the merge reads files, not versions |
| Quit, window close | Asks (§7.4) |
| A source photo's file changes or goes missing mid-merge | The job fails naming the frame (§7.3 "Read"); nothing is written |
| The volume of the reference's folder unmounts mid-merge | Write fails; §7.3 "Write"; no partial file (the temporary file is removed or, if the volume went, its absence is the result) |
| Sidecar sync | The result is a normal photo for it (A8) |
| The reference's folder becomes unwritable, or its volume unmounts, while the sheet is up | Found when Merge is pressed (the second check, §6.2): the sheet closes and Activity warns; a frame chosen as reference in the meantime is checked, not the one from the first check |
| The sheet is up and the person changes the sidebar source or the selection | Not possible: the sheet is window-modal and its frames are frozen (§5), the reference with them |

## 11. Accessibility

- **Menu item and context item:** standard system items, so VoiceOver reads
  them with their key. Reachable by VO-M and, for the grid, VO-Shift-M.
- **Sheet reading order:** title, subtitle, the refusal or note (header, so it
  is read before the controls), the table and its caption, Auto-align,
  De-ghost, the Result section, the buttons. Initial focus is on **Merge**
  when it is enabled, else on **Cancel**. Tab order: table, Auto-align,
  De-ghost, Format, Cancel, Merge.
- **The table** is a system `Table` with single selection (§5.5): VoiceOver
  reads each row as name, type, shutter, compensation, the reference's
  "Reference" and the system's "selected"; VO-Space on another row chooses it.
  A flagged row's accessibility value is "Problem" (the symbol is decoration
  and hidden). Column headers are real headers. The table's accessibility
  label is "Photos"; its hint, "Choose the reference".
- **When the reference changes** (§5.8; by click, arrow or VO-Space), one
  announcement after the folder check has finished and the answer is known,
  debounced about 0.3 s so arrowing through several rows says only the last:
  "Reference ‹name›. Result ‹file name›." and, when a refusal now shows or
  has just gone, its text or "Merge is available." The announcement is not
  posted for the first selection when the sheet opens (the sheet's own
  reading covers it).
- **Check boxes** (§5.6): system toggles labelled "Auto-align" and
  "De-ghost", the caption as the hint; VoiceOver says "checked" or
  "unchecked" on a change, and nothing else on the sheet moves.
- **Segmented Format control:** a system `Picker` with the label "Format";
  VoiceOver reads the selected segment and the caption below it.
- **Merge is dimmed with a reason on screen:** the reason is the header text
  right before it in reading order, so a dimmed button is never unexplained.
- **Announcements** (`NSAccessibility` announcement, as culling and removal
  use): on success "Merged to “‹file name›”." (the new photo isn't necessarily
  on screen, so the announcement is the only signal for a VoiceOver user who
  isn't looking at Activity), on failure "The photos couldn't be merged.", on
  stop "The merge was stopped."
- **Full Keyboard Access:** every route works without a pointer: ⇧⌘L, the
  File item, Return and Esc in the sheet, ⌘. to stop, Tab to the table and
  Up and Down to choose the reference, Space on a check box, Tab through
  Format, Cancel and Merge.
- **Color is never the signal:** flagged rows carry a symbol and text; the
  note and refusal carry a symbol and words.
- **Increase Contrast, Reduce Transparency, Reduce Motion:** the sheet,
  table, segmented control and popover are system components, so they follow
  the settings. The Activity bar's motion is the system's. There is no custom
  motion.
- **Text size:** the Mac has no Dynamic Type; the sheet uses the Export
  sheet's 13 pt and 11 pt text styles, no smaller.
- **Touch (touch-display Macs):** system controls only, no custom hit areas.

## 12. macOS 15 behavior

The app's minimum is macOS 15 and the SDK decides the look (CLAUDE.md).
Nothing here is conditional on the OS:

- The sheet is the Export sheet's construction (`Form` grouped, `Table`,
  `presentationSizing(.fitted)`, segmented `Picker`), which Export already
  ships on 15 and 26.
- Menu items, context menus, the Activity item and popover, the alert for the
  quit question: unchanged on both.
- On macOS 15 (linked with the macOS 26 SDK it runs the earlier design) there
  is no Liquid Glass; the system gives the sheet and toolbar item the earlier
  look. There is nothing to recolor or fit by hand.
- What differs between OS versions is the **result**, not the UI: the system RAW
  decoder differs between 15, 26 and 27, so a merged TIFF is not byte for byte
  the same across them (the merge decodes at the OS's own decode, A2). No
  golden depends on it. The merged DNG shows in the loupe's HDR render only on
  an EDR display, as any floating-point DNG already does.
- Vision's registration requests and Core Image's kernels the PRD names exist
  on both; if the engineer's spike finds a difference, it goes to `status.md`.
- These are covered by CI only: the owner's standing rule is not to ask for
  macOS 15 or 26 checks by hand, and none is added to `review.md`'s list.

## 13. Strings (catalog keys)

Added by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings`, each with a
comment naming its use. None mentions the product name. Plurals use the
catalog's plural variations, and no string has two plural numbers.

- **Menu and undo:** "Merge to HDR…" (File menu, grid context menu); "Merge to
  HDR" (undo action name, Activity row title; one key if the comment names
  both). "Stop Merge" (File ▸ Stop).
- **Sheet header:** "Merge %lld Photos to HDR" (plural); "From %@" (reuse
  the Export sheet's key if its comment allows, else a new key).
- **Sheet body:** "Photos" (section); "Result" (section); "Photo", "Type",
  "Shutter", "Compensation" (column titles); "Reference" (a row's role);
  "“%@” names the result and where it is saved. Click another photo to change
  it." (caption; replaces "“%@” names the result and is the photo the others
  are lined up to."; the old key is removed); "Auto-align"; "Lines the other
  photos up to the reference. Off: merged as they are." (its caption and
  accessibility hint); "De-ghost"; "Moving things, such as people, come from
  the reference only. Off: plain blend." (its caption and hint); "Choose the
  reference" (the table's accessibility hint);
  "These photos have the same exposure settings. Merging them won't widen the
  range of light." (note); "Format"; "TIFF"; "DNG"; "16-bit, Display P3,
  tone-mapped. Looks right in any app."; "16-bit floating point, not
  tone-mapped. Tone it in the Adjust tab."; "TIFF (16-bit, Display P3,
  tone-mapped)" (the row when DNG isn't built); "Name"; "Folder"; "The
  originals are not changed, and your adjustments are not used: the photos are
  merged as they were shot." (replaces the key that began "Saved next to
  “%@”."); "The photos are in several
  folders. The result goes in the reference's."; "Merge" (button); reuse
  "Cancel".
- **Refusals** (§6): "Select at least two different photos. A RAW+JPEG pair
  counts as one."; "At most %lld photos can be merged at once. Select fewer."
  (plural); "“%@” is a video. Only photos can be merged."; "“%1$@” is a copy of
  “%2$@”, the same file. Select each photo once."; "These photos are a mix of
  raw and non-raw files. Select only raws, or only JPEG, HEIC or TIFF files.";
  "“%1$@” is a different size from “%2$@”. Merged photos must be the same
  size."; "“%@” is offline. Connect its drive and try again."; "%lld of these
  photos are offline. Connect their drives and try again." (plural); "“%@”
  can't be read. Check that the file is still there."; "The merged photo would
  be saved next to “%1$@”, in “%2$@”, which can't be written to. It may be on a
  read-only disk, or you may not have permission."; "“%@” is too large to
  merge. A photo can have at most %lld megapixels." (6a; also Activity; one
  number, always 150 today, so no plural variation); "These photos are too
  large to merge together on this Mac. Select fewer." (6b).
- **Activity (job):** "Merge to “%@”" (popover title); "Reading %lld of %lld",
  "Aligning %lld of %lld" (no plural on either number), "Merging", "Tone
  mapping", "Saving", "Adding to the library" (details).
- **Activity (results):** "Merged %lld photos into %@." (plural; the path);
  "The merge was stopped. Nothing was added to the library."; "The photos
  couldn't be merged. Nothing was added to the library."; "“%1$@” doesn't line
  up with “%2$@”. Merge photos of the same scene, or turn off Auto-align."
  (replaces the key without the last clause); "“%@” couldn't be read.";
  "There isn't enough space on “%@”."; "The file couldn't be saved: %@.";
  "There wasn't enough memory to merge these photos."; "The merged photo was
  saved at %@ but couldn't be added to the library. Add the folder again to
  import it."; "“%1$@” was removed from the library. The file is still at
  %2$@."; "“%@” couldn't be added back because the file has changed or is
  missing."; "A merged photo can't be saved beside “%@”. The library's record
  of its file name or location isn't valid." (replaces the first draft,
  D-H5); "The library already has a photo with the same content."
- **Optional (R18):** "Show in Library" (the row's button). Not built (D-H3).
- **Quit:** "Quit While Merging?"; "The merge is stopped and nothing is
  added."; "Keep Merging" (button; the second button is the shared "Stop and
  Quit", D-H1).
- **VoiceOver:** "Merged to “%@”."; "The photos couldn't be merged."; "The merge
  was stopped."; "Reference %1$@. Result %2$@." and "Merge is available."
  (the announcements after a change of reference, §11; a refusal's own text
  follows when one shows).
- **Types:** the type column reuses the grid's words (RAW, JPEG, HEIC, TIFF);
  no new keys.
- **Dates and exposure formatting:** shutter as "1/250 s", compensation as
  "−2 EV" with the Unicode minus, both formatted for the locale.

## 14. Debug script needs (CLAUDE.md: UI checks with `--debug-script`)

The sheet is SwiftUI, and SwiftUI builds its accessibility tree only for an
attached assistive app, so the script reads **model state**, not the view.
Glass panes don't snapshot, and a sheet may not either, so the checks are
text. Additions, all in a new `DebugMergeCommands.swift`:

| Command | Does | Prints |
|---|---|---|
| `merge sheet` | opens the sheet for the current selection (what the menu item does) | frames in order with type, shutter, compensation and role (the reference marked); the refusal text and its flagged frames, or "none"; the pre-flight status; the result's name, folder and format choices offered; whether DNG is offered; `align` and `deghost` (both `on` when the sheet opens, always); the form's content height against the sheet's ideal height (§5.7) |
| `merge format tiff\|dng` | sets the sheet's format | the Name line and caption |
| `merge reference <name or 1-based row>` | chooses the reference the way a click on the row does (revision 2026-11-21) | the new reference, the Name and Folder lines, the refusal text and flagged frames (or "none"), whether Merge is enabled once the folder check is done; the answer that arrives for a superseded reference is shown as discarded |
| `merge align on\|off`, `merge deghost on\|off` | sets a check box | the box's state and the other's |
| `merge start` | presses Merge | the job's id, title and the first detail (with `align off` the details skip "Aligning") |
| `merge wait` | waits for the job to end (with a timeout) | the result path, or the Activity warning, or "stopped" |
| `merge stop` | the Stop path (the same closure as the popover's) | the Activity row |
| `merge cancelsheet` | presses Cancel | confirms no job and no file |
| `print merge` | state | running or not, phase and detail, fraction, canMerge, `canMergeReason` (the dim reason: fewer than two, running, sheet up), selection after |
| `menuitems "Merge to HDR…"` | exists | enabled or dimmed, key ⇧⌘L |
| `contextmenu` (grid) | exists | lists the item after Duplicate with 2+ selected; absent with 1 |
| `activity` | exists | shows the merge's rows (extend `activity` output with the job's detail) |

- **A bracket fixture.** `photobench` already writes a scratch library; it
  needs a `--brackets <n>` option that adds synthetic series (3 raws with
  known shifts and a moving object, 3 JPEGs, a mixed set for refusals, one
  with a read-only folder for case 9, one offline; and, for the reference
  choice of 2026-11-21, a series of three raws in two folders, one of them
  read-only, whose default reference is in the read-only one, and a series
  whose 0 EV frame is not the first in time) so the owner's sign-off
  and QA can run the whole feature on a scratch library, never the real one
  (WORKFLOW Sign-off). The PRD's AC7 and AC8 scenes (`PhotoFixtures`) are the
  same data.
- **A read-only folder and an offline volume** are made by the script
  (`chmod`, a FAT32 disk image, as CLAUDE.md describes for cards), not by
  hand.
- Debug-script rule from CLAUDE.md: the merge **changes the library**, so it
  runs inside an undo group (`changing` in `DebugScript`) and the script
  waits for the catalog write before the group closes (as a measuring paste
  does, `waitForBatchMeasuring`); otherwise `registerUndo` raises.
- `print inspectorwidth`, `accessibility <role>` are unchanged; the grid's
  `accessibility` should list the new cell's label (`IMG_1234_HDR, TIFF`).

## 15. User guide terms

The engineer updates `docs/USER_GUIDE.md` in the same change. The review checks
these terms against the UI:

- **File ▸ Merge to HDR…** (⇧⌘L; the grid's context menu). A new paragraph:
  what it does (two to nine photos of one scene, lined up and combined into
  one new photo), who it is for, and the steps (select, choose, pick TIFF or
  DNG, Merge).
- **The reference and the two check boxes (2026-11-21):** the reference is
  the photo you click in the sheet's table (by default the 0 EV one, else the
  earliest; the sheet forgets the choice every time it closes). It names the
  result, is the folder and project the result goes in, gives it its
  metadata, is what the others are lined up to (Auto-align) and where moving
  things are taken from (De-ghost). **Auto-align** and **De-ghost** are
  checked every time the sheet opens. Auto-align off merges the photos as they
  are (for a tripod) and refuses nothing for failing to line up; De-ghost off
  blends the photos with no photo taking priority where things moved. The
  guide may use "ghost" only in the name De-ghost.
- **What is written:** a new file beside the **reference** photo,
  named `‹name›_HDR` and numbered (`_HDR-2`) if the name
  is taken; never a master changed; the first time the app writes into a
  source folder. The sentence the README gets at Ship (PRD "Dependencies").
- **What it uses:** the files as shot, not your adjustments (A2); all raws or
  all non-raw, never both; a RAW+JPEG pair counts once, as its raw; a
  photo and its own copy are the same file.
- **The result:** a normal photo of the project, with the reference's metadata
  (A3, R7), no link to its sources (A6), not in the frames' albums. TIFF is
  tone-mapped and ready to view; DNG is not (only if built).
- **Refusals:** the list in §6 in the guide's words, and "Stop" for a running
  merge.
- **Undo:** removes the photo from the library, never the file; Redo; a merge
  after Undo is numbered; deleting the file is the Finder's job.
- The key table gains ⇧⌘L (grid column).
- The Activity paragraph gains the merge's job, row and Stop.
- **Terms not used:** "virtual copy", "version", "stack", "HDR photo" (a merged
  TIFF isn't one in the display sense; the guide says "tone-mapped").

## 16. Implementation notes and acceptance

What changes and how each is checked. Glass panes and sheets don't snapshot,
so checks use `merge …`, `menuitems`, `activity` and `print`, or are manual
(numbered M‹n› at review).

| # | Change | Acceptance |
|---|---|---|
| H1 | File ▸ Merge to HDR… ⇧⌘L (§2.1, §3, §4): `can` with `canMerge` (≥ 2 targets, not merging, no sheet) | `menuitems "Merge to HDR…"`: dimmed with none, one photo or one video selected; enabled with 2 and with 12; dimmed while a merge runs (AC1). File menu order as §2.1 |
| H2 | Context menu (§2.2) | The grid context-menu probe lists it after Duplicate with two selected, not with one; the loupe, video loupe and comparison menus don't list it |
| H3 | The sheet (§5): frozen frames, `Table`, header, Format, Name and Folder lines, captions, Merge and Cancel; added to `LibraryModal` | `merge sheet` prints frames in capture order, the reference marked (0 EV frame not first in time: AC3), the name, the folder, formats offered. `LibraryModalTests` passes with the new case; the preset report waits for the sheet |
| H4 | Name line and numbering (§5.3) | Unit test: with `IMG_1234_HDR.tif` present the line says `-2`; with a master of that name it does too (AC2, R4); format change updates the extension |
| H5 | Refusals from the selection (§6.1), one message at a time in order | Unit test of `MergeSelection.refusal(frames:)` for each of the seven cases and for the order when two apply. `merge sheet` shows the text and the flagged frames; Merge is off. Nothing written (AC6, AC12) |
| H6 | Refusals from the disk (§6.2): pre-flight, off the main thread, again on Merge | `merge sheet` on a fixture with a read-only folder shows case 9 before any work; a deleted master shows case 8. A unit test with a stub file system for both. No file or row exists after (AC12) |
| H7 | The job (§7.1): `ActivityJob` `merge`, phases and details, Stop in the popover and File ▸ Stop Merge, `StoppableJob.merge` | `print merge` shows detail changes and a rising fraction; `menuitems Stop` reads "Stop Merge"; `merge stop` mid-run leaves no file, no row and no temporary file in the folder (AC9) |
| H8 | Results and failures (§7.2, §7.3): the rows and the announcements | `activity` after `merge wait` shows the success row with the path; the failure fixtures (a frame from another scene, a deleted master mid-run, a full disk image) show their warning, and the library has no new row |
| H9 | After it lands (§8.3): selection only when untouched | Debug script: merge from a selection and wait, `print` shows the new photo selected and focused; merge, change the selection with `select`, wait: selection unchanged. Unit test of the rule |
| H10 | Undo and redo (§9): one step "Merge to HDR", the file stays, Activity names the path | `menuitems Undo` reads "Undo Merge to HDR"; ⌘Z removes the row, the file is on disk, `activity` names its path (AC13). Redo restores it; with the file removed first, the warning shows. A second merge after Undo writes `_HDR-2` |
| H11 | Quit and removal while running (§7.4, §10) | Unit test: `QuitConfirmation.needed` returns `.merging`. `menuitems "Remove from Library…"` dimmed during a merge. `about quitask` equivalent for merge asks "Quit While Merging?" |
| H12 | The result as a photo (R13, AC11) | Opens in the loupe, takes an edit and Undo, History lists it, exports; existing goldens unchanged (`swift test`) |
| H13 | Strings (§13) | `LocalizationTests` passes (every literal has an entry); plurals render for 1 and several where they exist |
| H14 | `photocli merge` (R17, AC14) | `photocli merge` prints one JSON object with `path`, `frames`, `reference`, `format`, `align`, `deghost`; refused with the same texts for the cases of §6; refuses while the app has the library open. Takes a reference (a file in the series; a name that is not one of the frames is an error saying so), and an off switch for each of align and de-ghost; without them it behaves as the sheet's defaults (D-H10) |
| H15 | `photobench` brackets and the script commands (§14) | `merge sheet` and `merge start` work on a `photobench --brackets` library |
| H16 | `docs/USER_GUIDE.md` (§15) | Checked at design review |
| H17 | The reference is the table's single selection (§5.5): default from R3, never empty, rows keep order, every listed row selectable | Unit test of the model: default is the 0 EV frame (not the first in time), else the first by capture time; choosing another frame sets it; a `nil` choice leaves it; reopening gives the default again (AC3, AC3c). `merge reference` and `merge sheet` print the mark on the chosen row |
| H18 | What follows the reference (§5.8, §6.4) | Unit test: name, folder, project and the size refusal's naming and flags follow the reference (AC3a); on the two-folder fixture the case 9 refusal appears and clears as the reference moves between the read-only and the writable folder, and the text names the chosen frame (AC12); an answer for a superseded reference is discarded; the check for a folder runs once per folder. `merge reference` on the fixture prints each state |
| H19 | The check boxes (§5.6) | Unit test: both on at every open, independent, not stored (AC9a); `merge align off` and `merge deghost off` change nothing but their own value; nothing else on the sheet changes |
| H20 | Activity with Auto-align off (§7.1) | `merge start` after `merge align off` shows details "Reading", "Merging", "Tone mapping", "Saving", with no "Aligning", and a bar that still ends at 1; the alignment-failure text appears only with it on |
| H21 | Sheet height (§5.7) | `merge sheet` prints the form's content height at 3 frames against the ideal height; it is within the 600 pt ideal, so no scrolling, and the sheet's `idealHeight` is 600, `minHeight` 420, width 560 |

**Manual checks for review.md** (a person at the bundle; the script can't
do these): M1 the sheet's look (header, table, the flagged-row symbol, the
caption copy, a long path); M2 the menu's key and a real ⇧⌘L with a real
keyboard and with the search field focused; M3 a real Stop with a real mouse
and ⌘.; M4 the quit question with a real ⌘Q during a merge; M5 the result's
look in the loupe and in another viewer (TIFF "looks normal", DNG "flat"); M6
the toolbar's Activity item fitting a long name; M7 undo, redo and merge again
(`_HDR-2`) with real menus.

**Added by the 2026-11-21 revision** (a person at the bundle, on a scratch
library from `photobench --brackets`; VoiceOver, macOS 15 and macOS 26 are
not listed, per the owner's standing rule: the announcements' text and
posting are covered by unit tests, the rest by CI):

- **M8, the sheet's look at the default size.** Three frames: the sheet is
  560 pt wide, shows everything (table, both check boxes with their captions,
  Result) without scrolling, with the "Reference" mark whole (not
  "Referen…") even with a long file name; the check box captions are indented
  to their labels and on one line; the same in Increase Contrast and with
  Reduce Transparency. Then nine frames: the Form scrolls, the header and the
  buttons stay.
- **M9, choosing by pointer.** Click each row: the highlight and the mark move
  together, the header thumbnail, Name, Folder and the table caption follow
  at once, nothing reorders. ⌘-click the chosen row and click the empty space
  under the rows: one row stays chosen. The caption makes clear the rows can
  be clicked (is it discoverable? say so if not: then the pop-up fallback,
  §5.5).
- **M10, choosing by keyboard (Full Keyboard Access on).** Tab goes table,
  Auto-align, De-ghost, Format, Cancel, Merge. In the table Up and Down move
  the reference; Space on a check box toggles it; with the table focused,
  Return presses Merge (report if it doesn't, §5.5), Esc closes. Close and
  reopen: the reference is the default again (0 EV, not the first in time)
  and both boxes are checked.
- **M11, the reference and the folder refusal.** On the two-folder series
  (default reference in the read-only folder): the refusal shows, naming the
  default reference; choosing the frame in the writable folder lifts it and
  turns Merge on; choosing the other brings it back. On a slow volume (a
  FAT32 image or a network share) the spinner shows only after a pause,
  Merge stays off meanwhile and the Name row isn't stale when it comes on.
- **M12, a real merge with another reference.** Merge the walker series with
  the +2 EV frame as reference: the result is named from it, is in its folder
  and project, the Info tab shows that frame's metadata, and the walker is
  where he is in that frame (by eye). The same with the default: it differs.
- **M13, the two boxes.** Auto-align on with a series of unrelated scenes:
  refused, the Activity row naming the frame and ending "or turn off
  Auto-align". Auto-align off with the same: merged as given, Activity shows no
  "Aligning". Walker series with De-ghost on and off: the moving figure is
  single (on) or blended (off); where nothing moved the two results look the same.
- **M14, height.** On a 13-inch laptop at its default scaling, and with the
  library window made short, the sheet is never taller than 600 pt or the
  window, fits on screen, and the Form scrolls with the header and buttons
  in place, including with a two-line refusal and the same-exposure note.

## 17. Requirements issues (for the product manager)

| RI | Issue | Design default (already in §1–§16) |
|---|---|---|
| RI-H1 | **R1, AC1 and R14 disagree about the menu item.** R1 says the item is "off when the selection can't be merged". AC1 says it is off for one photo, none, or "a video selected". R14 says a video, an offline photo, an unwritable folder and the count limits are "refused with a clear message". A dimmed item can't carry a message. Which holds: dimmed, or message? | **Both, by cause.** Dimmed for what the selection plainly shows: fewer than two targets (a single video is one target), a merge running, a sheet up. Every other case (a video among several, mixed, offline, read-only folder, over 9) shows its message in the sheet and keeps Merge off. If the ruling is "dim for all", the messages are lost and a person can't learn why; if "message for all", one photo selected opens a sheet that can only say "select two" |
| RI-H2 | **R14's refusals leave out cases a merge can't handle.** (a) Two items of **one master** (a photo and its own copy, #62): they are the same file, since a merge reads masters (A2). (b) Frames of **different pixel sizes** (two cameras, a crop mode, a changed orientation): they can't be aligned by translation and rotation. (c) The PRD says nothing about the **same exposure** on every frame (not a bracket). Add (a) and (b) to R14, and say whether (c) should be refused or only noted | (a) and (b) are refusals with messages (§6.1 cases 4 and 6). (c) is a non-blocking note only (§5.2): a person may know their metadata lies, and a refusal would be wrong half the time |
| RI-H3 | **No way to tell or find a merged photo.** The design marks it by name and type badge only, because A6 stores no link and no migration is planned. A person with hundreds of photos may want a "made by merging" mark or a smart-album rule, and "show the frames this came from" (A6's deferred idea) needs the same stored fact. Is a stored flag or source link wanted now, or is the name enough for v1? | The name and badge are enough for v1 (§8.2). If the owner wants a mark: a stored column or table (a migration), then a glyph on the grid cell like the copy mark (VC §6.1) and a smart-album rule; that is a follow-up issue, not this feature |
| RI-H4 | **A merged photo can be selected as a frame beside its own source raws, and nothing tells the app it is one** (A6 stores no link). A merged DNG is a raw to the app, with the reference's metadata, so it passes every refusal; the merge then counts it again. Is a marker wanted (in the merged file itself, so no migration, or in the catalog with RI-H3) that lets the sheet say "‹name› is a merged photo"? | **No detection in v1** (D-H5c): the sheet already shows the frame by name and the reference is named by it, and the result of the mistake is a poor file the person can Undo, not lost work. If the owner wants it, it belongs with RI-H3 as one stored fact serving both |

**Design questions for the owner.** None block the build. Three judgment calls
the owner may overrule, recorded so a different answer changes only the lines
named: the key ⇧⌘L (§3), Display P3 for the TIFF and no color-space control
(§5.3), and the Format choice being remembered between merges instead of
resetting to TIFF each time (§5.3). The 2026-11-21 revision adds two more of
the same kind (§20): the reference is chosen by clicking the table's row,
with a Reference pop-up as the fallback (D-H6), and the sheet is 40 pt taller,
600 pt (D-H8). Note the one asymmetry the owner's ruling creates: Format is
remembered between merges, Auto-align and De-ghost reset to checked every
time.

**The PRD's questions of 2026-11-21 (6 to 9) as this design answers them:**
6 (photocli takes the options): built as the PRD proposes (H14, D-H10);
7 (Auto-align off still refuses a different scene): no, it does not (§6.3,
A14); 8 (a warning for an extreme reference): none (§5.5, A13); 9 (where the
reference is chosen, the labels, the captions): §5.5 to §5.7. None needs a
change to the PRD.

**One thing for the engineer to answer in `status.md`:** whether the DNG
writer exists (§5.3 has both variants), and whether an import or an export
running beside a merge shares the catalog write chain safely (§10).

## 18. Assumptions (stated, not raised)

- **A-H1.** The sheet is opened for every enabled invocation, including when
  DNG isn't built (the sheet still says where the file goes and shows the
  frames, which is worth the click for a minute-long job that writes beside
  masters).
- **A-H2.** The Photos table's Shutter and Compensation come from the
  catalog's metadata already read at import; no file is read to open the
  sheet.
- **A-H3.** A copy selected alone (with other photos) is a frame; its file
  stem and capture time come from its master, its rating, flag and label are
  its own (§6.1).
- **A-H4.** The merged photo does not join the frames' albums (R7 lists
  nothing about albums).
- **A-H5.** One merge at a time (§7.1); a queue is not built.
- **A-H6.** Activity shows no Dock progress or notification (§7).

## 19. Design questions from implementation

Rulings on the engineer's questions (asked in `status.md`, ruled at design
review, 2026-11-20). Cite them as D-H1 … D-H4.

**D-H1. The quit alert's buttons: "Keep Merging" and "Stop and Quit".**
Confirmed; §7.4's "Quit" is withdrawn. Reasons: (1) consistency (HIG: familiar
patterns): the importing and exporting alerts already give **Keep ‹Job›**
(default, Return and Esc) and **Stop and Quit**, and a person who has met one
has met them all; (2) "Stop and Quit" says what the button does to the work,
which is the thing the alert is about, where a bare "Quit" does not; (3) the
shared `QuitGuard.ask` already makes the safe button the default and keeps Esc
on it, which is right here, since quitting is what loses a minute of work. The
button is not destructive-styled (nothing is lost but the run). No code
change.

**D-H2. When the merge ends with the loupe showing: nothing moves.** §8.3 said
two things; the rule is the second. The new photo takes the selection and the
focus **only when the grid is showing** and the selection is still exactly the
frames the merge started from and the source holds the new photo (what
`MergeLanding.selects` does). With the loupe, review or comparison showing, the
selection, the focused photo and the loupe are all left as they are, and
Activity (row and VoiceOver announcement) is the signal. Reasons: in the loupe
the person is looking at one photo, possibly mid-edit; replacing it under them
40 seconds after they asked for something is the "moving what they didn't act
on" the section forbids; and a selection changed while the loupe shows
something else would come back as a surprise when they return to the grid.
The new photo is in the list (a source that holds it shows it), so arrow keys
and the film strip reach it. As built. The guide says it (review finding F1).

**D-H3. R18 "Show in Library" is not built; accepted.** It is a Could, §8.3
already allowed leaving it out, and nothing depends on it. The cost is real
only for a person who moved on: the success row has the full path as
selectable text and the search field finds `_HDR`. If the owner finds that thin
in use, it is an enhancement (an optional action on `ActivityLog.Message`),
not a defect of this feature.

**D-H4. The DNG caption reads "16-bit floating point, not tone-mapped. Tone it
in the Adjust tab."** Confirmed. The constraint (the system decoder reads
float DNGs only at 16 bits) is the engineer's measurement in `status.md`, and
it is a better file for the person: the app's own loupe can show it, and other
raw-capable apps can open it. Keeping the bit depth in the caption is right
for symmetry with the TIFF's "16-bit". Keep "floating point": it is the plain
word for what makes this file different from the TIFF, and the next sentence
says what to do with it. The product-manager owns the PRD's R5, Open question 1
and any AC that says 32-bit: they need the same change (RI-E1, below).
Judgment, not Apple policy.

**D-H5. Rulings on the second pass (review fixes), 2026-11-20.** The
engineer's four new strings, the numbering of results by stem, and a merged
DNG chosen as a frame. Judgment throughout; the HIG is silent on these.

**D-H5a. The four strings.**

1. **"“%@” is too large to merge. A photo can have at most %lld megapixels."
   Confirmed as written** (sheet case 6a; the same text in Activity when a
   decoder, not the catalog, finds the size). It names the frame and gives the
   rule; the remedy (leave that photo out) is the only one there is, so it
   needs no sentence. "megapixels" is spelled out, not "MP". One number,
   always 150 today, so no plural variation is needed (§13's rule holds: no
   string has two plural numbers).
2. **"These photos are too large to merge together on this Mac. Select
   fewer." Confirmed as written** (case 6b). "On this Mac" is the useful
   phrase: the budget is half the machine's memory, so the same selection may
   work elsewhere, and the person learns the limit is the machine's. "Select
   fewer" would be a dead end for exactly two frames, but two frames can't
   reach the budget in practice: two 150 MP frames hold 2.4 GB (8 bytes a
   pixel) against a budget of half the Mac's memory, which is 4 GB on an 8 GB
   Mac. So there is no second wording for two frames (from the arithmetic;
   recheck if `frameMemoryBudget` or the pixel limit changes). All rows are
   flagged, as in case 1: no one frame is at fault.
3. **"“%@” has a name or place a merged photo can't be saved beside."
   Rewritten.** "A name or place" is vague and names the cause in jargon. The
   reader is a person whose library has a bad record, and needs what can't be
   done and why. New text, two sentences like every other row of §7.3: **"A
   merged photo can't be saved beside “%@”. The library's record of its file
   name or location isn't valid."** It does not say "damaged" (that alarms and
   can't be verified here) and offers no remedy, since none is known to work.
   The catalog key is the English text, so the key changes with it; the
   comment keeps "a damaged library" for translators.
4. **"The library already has a photo with the same content." Confirmed as
   written.** It says what was found; "Nothing was added to the library"
   already precedes it in the row and covers the removed file. Practically
   unreachable, so more wording would buy nothing.

**D-H5b. Numbering by stem stands, with no caption in v1.** A TIFF and a DNG
of one series would otherwise share `IMG_1234_HDR.xmp`, each reading and
writing the other's values (code review C3): a data fault, so the numbering is
right, and it keeps R4's "never replace" intent. The cost is a name that reads
`IMG_1234_HDR-2.dng` with no `-1` beside it. The Name row shows it before
Merge is pressed and changes with the Format control, which is where the
person decides, so nothing is hidden (the same argument as §9's `_HDR-2` after
Undo). A caption naming the clashing file ("“IMG_1234_HDR.tif” is already
here") needs the clashing name from `MergeNaming` and one more string; it is
not worth that until someone is confused, and the guide already gives the
reason (a DNG merged after a TIFF of the same photos is
`IMG_1234_HDR-2.dng`, so the two never share a sidecar). Left as built. An
orphan `.xmp` with no photo beside it also numbers the result; rare, harmless.

**D-H5c. A merged DNG selected beside its own source raws: neither flagged nor
refused.** It passes every refusal because the app can't tell it from another
raw: no link is stored (A6) and the file carries the reference's metadata
(R7). Reasons not to act: (1) a refusal must be certain, and the only signals
(`_HDR` in the name, the reference's exposure data) also describe photos the
person named or shot that way, so a rule would block legitimate selections,
against user control; (2) the cost is a poor file after a minute, written
beside the originals and one Undo from gone, never lost work; (3) the sheet
already shows it: the frame is listed by name (`IMG_1234_HDR`), and when it
ties with the reference in time and compensation it can become the Reference,
so the Name row reads `…_HDR_HDR`, a plain signal before Merge. Reading each
file's tags to detect our own DNG would add disk work to opening the sheet
(A-H2) and a marker the PRD does not specify; that is **RI-H4** for the
product manager, default "no detection". The guide gets one sentence (review
finding F5).

## 20. Revision 2026-11-21: the reference choice and the two check boxes

Rulings on the questions of the revised PRD (its Open question 9, and the
placement questions in the brief of 2026-11-21). Cite them as D-H6 … D-H10.
The HIG has no page that settles these; each is judgment from its general
guidance (Tables and lists, Toggles, Sheets, Context menus, Accessibility),
labelled as such. This section wins where an earlier section still reads as
the first revision.

**D-H6. The reference is chosen by clicking its row in the Photos table.**
Single selection, always one row, the row's "Reference" mark kept in words.
Reasons: the person chooses by comparing, and everything they compare by is
in that table; choosing where the evidence is is direct manipulation, needs no
second control, and makes the mark and the choice one thing; selecting an
item in a list to choose it is the ordinary Mac meaning of a table's
selection, and the system gives keyboard (arrows, type-select, Tab) and
VoiceOver (VO-Space) behavior for nothing. Rejected: a Reference pop-up
(names alone, a second control for one fact, the fallback if the table's
"always one" selection can't be had, §5.5), a radio column (a fake control),
a context-menu or menu-bar action as the only route (hidden), a "Use as
Reference" button (a control to give the selection a meaning). Fixes the
screenshot's "Referen…": the mark never truncates. The choice is never stored
(AC3c). Every listed row can be chosen (A13). Detail: §5.5.

**D-H7. Auto-align and De-ghost are two system check boxes in the Photos
section under the table, each with a one-line caption saying what unchecking
does.** Not in Result: Result is about the file, these are about what is done
to the photos relative to the reference, and under the table they read in the
order of the task. Labels are the PRD's, "Auto-align" and "De-ghost". The word
"ghost" is allowed as the control's name only (§1's rule is relaxed for it and
nowhere else): the owner and the PRD use it and photographers know it; its
caption says what it does in plain words ("Moving things, such as people,
come from the reference only. Off: plain blend."). Captions: "Lines the other
photos up to the reference. Off: merged as they are." and the one above. No
warning for turning either off, no dimming, no effect on any refusal except
that with Auto-align off no frame is refused for failing to line up (A14).
Checked on every open; not stored (the owner's ruling), unlike Format. Detail:
§5.6.

**D-H8. The sheet's ideal height goes from 560 to 600 pt; width stays at 560;
it never grows further.** The content at three frames needs about 580 pt
(estimate in §5.7); the Form scrolls for more frames, longer text or a
refusal, with the header and buttons fixed. Two lines were cut to pay for the
two boxes (the Photos caption is one line; "Saved next to “‹reference›”." is
dropped from the Result caption). If the engineer's measure shows scrolling
at three frames, shorten the captions first and raise the height in steps of
20 pt only up to 640, and then ask. Judgment: 600 pt is about two thirds of the
height of a current 13-inch laptop display and fits the smallest scaled
one.

**D-H9. What follows the reference, and when.** Everything that came from the
one reference follows the new choice at once (§5.8): the thumbnail, the
caption, Name (numbered in the new folder), Folder, and the refusals that
depend on it (case 9 wholly, case 6's naming and flags; §6.4). Merge is off
until the new reference's folder check is done; the check runs once per
folder per sheet; a late answer for a superseded reference is discarded. A
frame in a read-only folder is a legitimate non-reference: only the
reference's folder is written (R2). One announcement for VoiceOver after the
answer is known, debounced (§11).

**D-H10. `photocli merge` takes the same three choices (R17, Open question
6, as proposed).** A reference (a file of the series), and an off switch
for each of align and de-ghost; without them, the sheet's defaults. The flag
names are the engineer's, following the command registry's conventions; the
JSON gains `align` and `deghost`. A reference that isn't one of the frames is
an error that says so (the sheet can't produce it). The text of every refusal
is the sheet's. The Activity failure for a frame that doesn't line up gains
a remedy, "…, or turn off Auto-align.", because the sheet now has the switch
(§7.3); `photocli`'s message for the same failure names its own flag for
turning alignment off instead.

**D-H5c, amended.** A person can now choose a merged DNG as the reference
(it is a listed row), and then the Name row reads `…_HDR_HDR`, the same plain
signal as before and now one the person made on purpose. No detection is
added (RI-H4 stands).
