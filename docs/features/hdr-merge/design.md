# HDR merge: design

Owner: apple-ui-designer. Date: 2026-11-20.
Issue: #150. Status: complete. Three requirements issues are open for the
product manager (§17). §1–§16 already assume the default given for each, so the
engineer can start; a different ruling changes only the lines §17 names.

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
| Progress and cancel | A job in the toolbar's Activity item, determinate, phase named in the popover; Stop in the popover and **File ▸ Stop Merge** (⌘.). A cancel or a failure leaves the library unchanged and posts one Activity row | §7 |
| The new master afterward | An ordinary photo of the naming photo's project and folder, in capture-date order beside its frames, named `IMG_1234_HDR`, with a TIFF or DNG type badge. It is **selected and scrolled into view only if the person has not changed the selection or the source** while it ran; otherwise Activity says where it is | §8 |
| Marking it | By name and type badge only. No "merged" mark, because no provenance is stored (A6) and no migration is planned | §8.2, RI-H3 |
| Undo | One step, "Merge to HDR": the photo leaves the library, the file stays, Activity names its path | §9 |
| Empty states | None needed: the item is dimmed with nothing to act on, and the sheet always has frames to show | §4 |
| Accessibility | System controls throughout; the refusal text sits first in the sheet's reading order; flagged rows carry a symbol and text, never color alone; the result and failures are announced | §11 |
| macOS 15 | No conditional UI: every component exists on 15 and gets the earlier look there | §12 |

**The words.** The command is **Merge to HDR…**, and what it makes is a **merged
photo**. A frame is one of the selected photos. The **reference** is the frame
that names the result and that the others are lined up to (PRD R3, A9). Words
not used in the UI, the guide or strings: "bracket" as a noun in menus (the
guide may say a "bracketed series" once, since photographers do), "ghost" and
"registration" (the app says what happens: "doesn't line up"), "stack" (that is
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
│  Photo          Type   Shutter   Compensation            │
│  IMG_1233       RAW    1/250 s   −2 EV                   │
│  IMG_1234 Reference RAW 1/60 s   0 EV                    │
│  IMG_1235       RAW    1/15 s    +2 EV                   │
│  “IMG_1234” names the result and is the photo the        │
│  others are lined up to.                                 │
│ Result                                                   │
│  Format        [ TIFF | DNG ]                            │
│  16-bit, Display P3, tone-mapped. Looks right in any app.│
│  Name          IMG_1234_HDR.tif                          │
│  Folder        …/Trip/Day 2                              │
│  Saved next to “IMG_1234”. The originals are not         │
│  changed, and your adjustments are not used: the photos  │
│  are merged as they were shot.                           │
├──────────────────────────────────────────────────────────┤
│                                    [ Cancel ]  [ Merge ] │
└──────────────────────────────────────────────────────────┘
```

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
  that decides "first" in R3), no selection, no sorting, 24 pt rows, as many
  rows as frames (2 to 9; above 9 the first nine plus the refusal), with a
  height that fits them and scrolls past 250 pt.
- **Columns:** **Photo** (the display name, `PhotoName.display`, so a copy
  reads "IMG_0412 copy"; the reference's name is followed by a secondary
  "Reference"), **Type** (RAW, JPEG, HEIC, TIFF: the grid's badge words, so a
  pair reads RAW), **Shutter** (the frame's exposure time, "1/250 s"), and
  **Compensation** ("−2 EV", "0 EV", "+2 EV", from the metadata; "—" when the
  file has none). Aperture and ISO are not columns: a bracket varies shutter
  or compensation, and four columns fit the sheet without a horizontal
  scroller. Numbers use `monospacedDigit`.
- **A flagged row** (the frame a refusal is about) starts with
  `exclamationmark.triangle`, and its accessibility value says "Problem". The
  message in the header says what the problem is. Never color alone.
- **Caption under the table:** "“‹reference›” names the result and is the
  photo the others are lined up to." 11 pt secondary, like the Export sheet's
  captions.
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
  tag. Using the naming photo's own space would mean a raw (which has none)
  and a JPEG (sRGB) get different files from the same command. No control: the
  sheet carries no color-space choice in v1.
- **If the DNG writer is not built** (the spike's answer, PRD Open question 1),
  the Format row and the DNG caption are **absent**, not a one-item picker and
  not a disabled "DNG": a control that offers a thing that isn't there only
  invites the question. The sheet then shows a plain row "Format: TIFF
  (16-bit, Display P3, tone-mapped)". Every other section is unchanged.
- **Name.** A read-only line: the name the file will get now, for the chosen
  format (`IMG_1234_HDR.tif`, or `IMG_1234_HDR-2.tif` when that exists, by
  `ExportNaming`'s numbering and `MasterFiles`'s rule). It changes with the
  format. The name is decided again when the merge starts (the folder may
  change in a minute); the caption says nothing about that, because the
  difference is rare and the Activity row names the real file.
- **Folder.** The naming photo's folder, as a path truncated at its head, with
  the full path as its tooltip (the Export sheet's folder row, without the
  Choose button). There is **no folder chooser**: R2 puts the result beside the
  reference. A series from several folders gets one more caption sentence: "The
  photos are in several folders. The result goes in the reference's."
- **Caption under the section:** "Saved next to “‹reference›”. The originals
  are not changed, and your adjustments are not used: the photos are merged as
  they were shot." This is the first time the app writes a new file into a
  source folder, so the sheet says where and that nothing else changes. The
  second sentence states A2, which people will otherwise discover by
  surprise (a white balance fixed on one frame is not carried).

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
| 6 | Frames of different sizes (see RI-H2) | "“‹name›” is a different size from “‹reference›”. Merged photos must be the same size." | the frame that differs |
| 7 | An offline photo (R14) | one: "“‹name›” is offline. Connect its drive and try again." Several: "‹N› of these photos are offline. Connect their drives and try again." (plural; the first is named in the table) | the offline frames |

- **A RAW+JPEG pair is one frame, and its file is the RAW** (R8), whichever
  cell was selected and whichever file Photo ▸ RAW+JPEG Pair shows. The Type
  column says RAW, so the choice is visible. The cost: a pair's JPEG selected
  with two stand-alone JPEGs is a mix (case 5). That is rare, and the table
  shows why.
- A copy as the **only** link to its master is fine (case 4 is only about two
  items of one master); the copy's file stem and metadata come from its master
  and from the copy's own rating, flag and label (R7 reads "the naming
  photo", and that is the item the person selected).
- **Order matters.** Count and kind (1–3) come before content (4–6) and
  availability (7), so one message answers the most basic problem first. After
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
| 9 | The naming photo's folder can't be written (read-only volume, no permission; R14, AC12) | "The merged photo would be saved next to “‹reference›”, in “‹folder›”, which can't be written to. It may be on a read-only disk, or you may not have permission." | the reference |

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
  time for the rare case.
- **A corrupt file** that opens but fails to decode: the same, named in
  Activity.

## 7. Running the merge: Activity

The job lives in the toolbar's Activity item and popover and nowhere else:
the sheet has closed, so no alert is attached to a window the person may have
left (UID P4: a background task reports in Activity). No Dock progress and no
notification in v1 (judgment: Export has neither).

### 7.1 While it runs

- **A job in the Activity item** (`ActivityJob`, id `merge`), **determinate**:
  the bar is the fraction of the pipeline's phases, weighted by cost (the
  engineer sets the weights from the spike: read and decode, align, merge and
  de-ghost, tone map, write; the bar never moves backward).
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
  - **Alignment (R9):** "“‹name›” doesn't line up with “‹reference›”. Merge
    photos of the same scene."
  - **Read:** "“‹name›” couldn't be read."
  - **Space:** "There isn't enough space on “‹volume›”."
  - **Write:** "The file couldn't be saved: ‹system reason›."
  - **Memory:** "There wasn't enough memory to merge these photos."
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
  removal that takes the naming photo's project out from under the merge could
  not leave "library unchanged" and the file both true. This is LO §8's
  mechanism (`RemovalAvailability`).

## 8. The new master in the grid

### 8.1 Where it appears

- A new master is catalogued in the naming photo's project (R6), so it
  appears in All Photos, that project, the Dates tree and any smart album
  whose rule it meets, like any import. It carries the naming photo's capture
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
  contains the new photo (All Photos, the naming photo's project, its date), no
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
  changed: the new photo has the naming photo's rating, flag and label (R7),
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
| The volume of the naming folder unmounts mid-merge | Write fails; §7.3 "Write"; no partial file (the temporary file is removed or, if the volume went, its absence is the result) |
| Sidecar sync | The result is a normal photo for it (A8) |

## 11. Accessibility

- **Menu item and context item:** standard system items, so VoiceOver reads
  them with their key. Reachable by VO-M and, for the grid, VO-Shift-M.
- **Sheet reading order:** title, subtitle, the refusal or note (header, so it
  is read before the controls), the table, the Result section, the buttons.
  Initial focus is on **Merge** when it is enabled, else on **Cancel**.
- **The table** is a system `Table`: VoiceOver reads each row as name, type,
  shutter, compensation, and the reference's "Reference". A flagged row's
  accessibility value is "Problem" (the symbol is decoration and hidden).
  Column headers are real headers.
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
  File item, Return and Esc in the sheet, ⌘. to stop, Tab through Format,
  Cancel and Merge.
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
  "“%@” names the result and is the photo the others are lined up to." (caption);
  "These photos have the same exposure settings. Merging them won't widen the
  range of light." (note); "Format"; "TIFF"; "DNG"; "16-bit, Display P3,
  tone-mapped. Looks right in any app."; "16-bit floating point, not
  tone-mapped. Tone it in the Adjust tab."; "TIFF (16-bit, Display P3,
  tone-mapped)" (the row when DNG isn't built); "Name"; "Folder"; "Saved
  next to “%@”. The originals are not changed, and your adjustments are not
  used: the photos are merged as they were shot."; "The photos are in several
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
  read-only disk, or you may not have permission."
- **Activity (job):** "Merge to “%@”" (popover title); "Reading %lld of %lld",
  "Aligning %lld of %lld" (no plural on either number), "Merging", "Tone
  mapping", "Saving", "Adding to the library" (details).
- **Activity (results):** "Merged %lld photos into %@." (plural; the path);
  "The merge was stopped. Nothing was added to the library."; "The photos
  couldn't be merged. Nothing was added to the library."; "“%1$@” doesn't line
  up with “%2$@”. Merge photos of the same scene."; "“%@” couldn't be read.";
  "There isn't enough space on “%@”."; "The file couldn't be saved: %@.";
  "There wasn't enough memory to merge these photos."; "The merged photo was
  saved at %@ but couldn't be added to the library. Add the folder again to
  import it."; "“%1$@” was removed from the library. The file is still at
  %2$@."; "“%@” couldn't be added back because the file has changed or is
  missing."
- **Optional (R18):** "Show in Library" (the row's button). Not built (D-H3).
- **Quit:** "Quit While Merging?"; "The merge is stopped and nothing is
  added."; "Keep Merging" (button; the second button is the shared "Stop and
  Quit", D-H1).
- **VoiceOver:** "Merged to “%@”."; "The photos couldn't be merged."; "The merge
  was stopped.".
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
| `merge sheet` | opens the sheet for the current selection (what the menu item does) | frames in order with type, shutter, compensation and role; the refusal text and its flagged frames, or "none"; the pre-flight status; the result's name, folder and format choices offered; whether DNG is offered |
| `merge format tiff\|dng` | sets the sheet's format | the Name line and caption |
| `merge start` | presses Merge | the job's id, title and the first detail |
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
  with a read-only folder for case 9, one offline) so the owner's sign-off
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
- **What is written:** a new file beside the **reference** photo (the 0 EV one,
  else the earliest), named `‹name›_HDR` and numbered (`_HDR-2`) if the name
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
| H14 | `photocli merge` (R17, AC14) | `photocli merge` prints one JSON object with `path`, `frames`, `reference`, `format`; refused with the same texts for the cases of §6; refuses while the app has the library open |
| H15 | `photobench` brackets and the script commands (§14) | `merge sheet` and `merge start` work on a `photobench --brackets` library |
| H16 | `docs/USER_GUIDE.md` (§15) | Checked at design review |

**Manual checks for review.md** (a person at the bundle; the script can't
do these): M1 the sheet's look (header, table, the flagged-row symbol, the
caption copy, a long path); M2 the menu's key and a real ⇧⌘L with a real
keyboard and with the search field focused; M3 a real Stop with a real mouse
and ⌘.; M4 the quit question with a real ⌘Q during a merge; M5 the result's
look in the loupe and in another viewer (TIFF "looks normal", DNG "flat"); M6
the toolbar's Activity item fitting a long name; M7 undo, redo and merge again
(`_HDR-2`) with real menus.

## 17. Requirements issues (for the product manager)

| RI | Issue | Design default (already in §1–§16) |
|---|---|---|
| RI-H1 | **R1, AC1 and R14 disagree about the menu item.** R1 says the item is "off when the selection can't be merged". AC1 says it is off for one photo, none, or "a video selected". R14 says a video, an offline photo, an unwritable folder and the count limits are "refused with a clear message". A dimmed item can't carry a message. Which holds: dimmed, or message? | **Both, by cause.** Dimmed for what the selection plainly shows: fewer than two targets (a single video is one target), a merge running, a sheet up. Every other case (a video among several, mixed, offline, read-only folder, over 9) shows its message in the sheet and keeps Merge off. If the ruling is "dim for all", the messages are lost and a person can't learn why; if "message for all", one photo selected opens a sheet that can only say "select two" |
| RI-H2 | **R14's refusals leave out cases a merge can't handle.** (a) Two items of **one master** (a photo and its own copy, #62): they are the same file, since a merge reads masters (A2). (b) Frames of **different pixel sizes** (two cameras, a crop mode, a changed orientation): they can't be aligned by translation and rotation. (c) The PRD says nothing about the **same exposure** on every frame (not a bracket). Add (a) and (b) to R14, and say whether (c) should be refused or only noted | (a) and (b) are refusals with messages (§6.1 cases 4 and 6). (c) is a non-blocking note only (§5.2): a person may know their metadata lies, and a refusal would be wrong half the time |
| RI-H3 | **No way to tell or find a merged photo.** The design marks it by name and type badge only, because A6 stores no link and no migration is planned. A person with hundreds of photos may want a "made by merging" mark or a smart-album rule, and "show the frames this came from" (A6's deferred idea) needs the same stored fact. Is a stored flag or source link wanted now, or is the name enough for v1? | The name and badge are enough for v1 (§8.2). If the owner wants a mark: a stored column or table (a migration), then a glyph on the grid cell like the copy mark (VC §6.1) and a smart-album rule; that is a follow-up issue, not this feature |

**Design questions for the owner.** None block the build. Three judgment calls
the owner may overrule, recorded so a different answer changes only the lines
named: the key ⇧⌘L (§3), Display P3 for the TIFF and no color-space control
(§5.3), and the Format choice being remembered between merges instead of
resetting to TIFF each time (§5.3).

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
