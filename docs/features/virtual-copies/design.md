# Virtual copies: design

Owner: apple-ui-designer. Date: 2026-11-11.
Issue: #62. Status: complete. Three requirements issues are open for the
product manager (§13), and R10 is deferred (§13, under D8). §1–§12 already
assume the default given for each, so the engineer can start. A different
ruling changes only the lines §13 names.

**Inputs.**

- Requirements: [`prd.md`](prd.md), R1–R11, AC1–AC9 and D1–D8 (owner,
  2026-11-11). Cited as "R‹n›", "AC‹n›" and "D‹n›".
- Current design: [`../ui-redesign/design.md`](../ui-redesign/design.md)
  (cited as "UID"; placement rules P1–P5) and
  [`../library-ops/design.md`](../library-ops/design.md) (cited as "LO";
  File menu groups §2.1, context menus §2.2, keys §3, removal §6).
- Code read on `develop` at `b26fb50`: `Views/LibraryCommands.swift`,
  `Grid/PhotoContextMenu.swift`, `Grid/PhotoCell.swift`,
  `Loupe/FilmStripCell.swift`, `Loupe/LoupeView.swift` (`LoupeCaption`),
  `Model/WindowTitle.swift`, `Model/LibraryOpsActions.swift` (strings),
  `Views/SmartAlbumEditor.swift` (rule titles), `PhotoUI/Palette.swift`
  (`FileKindText`), `PhotoCore/Catalog/LibraryQuery.swift`,
  `Catalog.duplicateVersion`, `Export/ExportNaming.swift`,
  `CardImport/ImportTemplate.swift`.
- HIG pages read 2026-11-11 (markdown versions): The menu bar (the File
  menu's Duplicate item), Keyboards (standard and custom shortcuts).

**Custom chrome.** One addition: a copy mark on the grid's and the film
strip's cells (§6.1, §6.2). Both cells are already drawn with layers (an
`NSCollectionView` of custom cells, for scrolling speed), and their offline
and video marks are drawn the same way. The new mark reuses that pattern with
an SF Symbol. No system component draws a badge on a collection view cell.
Everything else is a system component: menu items, `NSMenu` context menus,
the caption's existing `CaptionBadge`, and the system alert that removal
already uses.

## 1. Answers to the PRD's designer questions

| Question | Answer | Section |
|---|---|---|
| Where Duplicate lives | **File ▸ Duplicate**, ⌘D, first item of the photo-file group (before Show in Finder). Also in the grid's and the loupe's context menus, as the first item of the Export group. Not in the toolbar, the video loupe's menu or the film strip | §2, §3 |
| How a copy is marked in the grid | A `square.on.square` glyph on a dark backing at the image's top-trailing corner, the same form as the offline mark at the top-leading corner. The name under the cell reads "IMG_0412 copy" | §6.1 |
| …in the loupe caption | A **Copy** badge among the caption's badges. The window title shows the copy's name | §6.3 |
| …in the film strip | The same glyph at the thumbnail's top-trailing corner, the one corner the strip leaves free | §6.2 |
| How it is named in the grid | "‹base name› copy" for the first copy, then "‹base name› copy 2", "copy 3"…, numbered from `versionNumber`. This follows the Finder's naming for duplicates | §5 |
| …in export file names | The same name: "Original Name" and the `{name}` token give `IMG_0412 copy.jpg` and `IMG_0412 copy 2.jpg` | §5.3 |

**The words.** The command is **Duplicate**, and its result is a **copy**.
This is the Mac's pair of terms (the Finder's File ▸ Duplicate makes "‹name›
copy"), and the HIG's File menu lists Duplicate as the command that makes a
new item beside the original. Two words are never used in the UI, the user
guide or strings:

- "virtual copy": another photo application's term, so the clean-room rule
  excludes it. The folder's slug is internal, and it stays.
- "version": the catalog's internal word. It also means a different thing to
  photographers (an edited state of the photo).

The original stays "the original". A photo with no copies needs no word.

## 2. Placement

### 2.1 File menu

The new item is in **bold**. Everything else is as built (LO §2.1).

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
**Duplicate**                        ⌘D
Show in Finder                       ⇧⌘R
Export…                              ⇧⌘E
Remove from Library…                 ⌘⌫
─────────────
Check for Changes on Disk
Stop ‹job›                           ⌘.
─────────────
Close                                ⌘W
```

- **Why the File menu.** The HIG's File menu table lists Duplicate. The
  group already holds the commands that act on the photo targets as library
  items: Export… makes files from them, and Remove from Library… takes them
  out. Duplicate adds them, so it sits in the same group. Remove stays last
  in the group, where LO put it.
- **No ellipsis.** Duplicate acts at once and asks nothing (HIG Menus).
- **The title stays "Duplicate"** for any number of targets, as the Finder's
  does. The selection already shows how many.
- **Not the Photo menu.** That menu holds culling, keywords, albums and
  pairs, which change a photo's values. Duplicate makes new items, and Mac
  users look for it in File.

### 2.2 Context menus

As P2 and LO §2.2 require, the item has the same title and enablement as the
menu bar item, and it is left out (not dimmed) when it can't act.

- **Grid and loupe:** **Duplicate** is the first item of the group that holds
  Export…, Show in Finder and RAW+JPEG Pair ▸, giving the order Duplicate,
  Export…, Show in Finder, RAW+JPEG Pair ▸. The existing order is kept. The
  separator before the group now also appears when Duplicate is the only
  item in it.
- **Video loupe:** left out, because videos aren't duplicated (§4.1).
- **Film strip:** has no context menu (by design), and none is added.
- **Sidebar rows:** no item. Duplicate acts on photos, not on projects or
  albums.

### 2.3 Not placed

- **Toolbar:** nothing, not even as a palette item. Making copies is
  occasional, and ⌘D plus the context menu are close at hand. The toolbar
  holds the most frequent commands (HIG Toolbars). This is judgment.
- **Inspector:** no button.
- **VoiceOver custom actions on the grid and loupe:** none. The action
  lists stay the frequent culling commands (UIR §10). VO-Shift-M reaches the
  context menu.

## 3. Keys

| Command | Key | Why | Conflicts checked |
|---|---|---|---|
| Duplicate | **⌘D** | ⌘D is the Mac's key for duplicating a selected item (the Finder's File ▸ Duplicate). The HIG's standard table doesn't list ⌘D, so this follows convention, not Apple policy. The table's document form of Duplicate, ⇧⌘S, belongs to document apps ("Duplicate the active document or initiate a Save As") and would read as Save here | Not in the HIG standard table (⌥⌘D and ⌃⌘D are system keys; neither is used here). No `keyboardShortcut("d", …)` anywhere in `Sources/`, and nothing in `ImportCommands` (P3). The text system has no ⌘D binding |

**Enablement follows the keyboard, as ⌘⌫ does (LO §3).** File ▸ Duplicate
uses `canByKey`: it is enabled only while the grid, loupe or video loupe has
the keyboard. A Mac command acts on the selection in the view that has
focus. With the sidebar or a text field focused, ⌘D making copies of the
grid's photos would act on something the person isn't working in. It also
keeps Duplicate's enablement the same as its neighbour Remove from
Library…. The cost, as with ⌘⌫: a person who chooses the item with the
pointer while the search field has the keyboard finds it dimmed, and clicks
a photo first.

No bare key is added. Duplicate is not a culling command, and a single
letter that silently adds items is too easy to press by mistake.

## 4. Duplicate: behavior

### 4.1 Targets and enablement

- **Targets** are what the other photo commands act on: the grid's
  selection, or the photo in the loupe (review included).
- **Photos only.** Videos have no edits to vary, and making differently
  treated versions of a photo is the reason the feature exists (PRD
  Problem). In a mixed selection the videos are skipped (§4.4). This is
  raised as RI-V1.
- **Enabled when** the grid, loupe or video loupe has the keyboard, the
  targets include at least one photo, and no crop is being edited. A crop
  session is unsaved state, so finish or cancel it first, as with Rotate.
  It is dimmed while a sheet is up, as every library item is.
- **Offline photos can be duplicated** (assumption A1, the PRD's proposed
  answer). Everything a copy needs is in the catalog. The copy has the same
  render hash, so it shows the original's cached preview at once, offline
  too.
- **A RAW+JPEG pair** (R9, D5): a grouped cell duplicates only the file it
  shows (the RAW unless Photo ▸ RAW+JPEG Pair says otherwise). The copy is
  unpaired: its badge reads `RAW` (or `JPEG`), not `RAW+JPEG`, and the
  RAW+JPEG Pair submenu doesn't apply to it. With grouping off, each cell
  duplicates its own file.
- **A copy can be duplicated.** The new copy takes the copy's current
  values, as R1 says for any photo, and it is another copy of the same
  master, placed after that master's last copy (§4.2).
- **Already running jobs** (imports, exports, folder adds) don't block it.

### 4.2 Result and placement (R5)

- Each target gets one copy, inserted **right after the master's other
  items**: the original first, then its copies in the order they were made
  (`versionNumber`). This is the order `LibrarySort.orderTerms` already
  gives for capture date and file name. For rating it gives the same at
  creation, because the copy starts with the original's rating. After that,
  each copy sorts by its own values (RI-V2).
- **Selection afterwards (grid):** the new copies become the selection, and
  the copy of the focused photo takes the focus, scrolled into view. This is
  what the Finder does after Duplicate, and it puts the copies under the
  person's hand for the next step (apply a preset to them).
- **Loupe:** the loupe moves to the new copy, and the film strip follows.
  The **Copy** badge and the title (§6.3) show the change. In review it stays
  in review.
- **Filters:** a copy starts with the original's rating, flag, label,
  keywords and albums (R3, R4), so it matches whatever made the original
  visible. The "stays visible until the filter changes" rule covers it like
  any culled photo.
- **In an album or keyword source,** the copy appears there too, because it
  starts with the original's memberships (R4).

### 4.3 Undo (R1, AC1)

- **One undo step for the whole action**, named "Duplicate": Edit ▸ Undo
  Duplicate / Redo Duplicate.
- **Undo** removes the copies. The selection and focus go back to the
  originals, and the loupe goes back to the original it was on. **Redo**
  brings back the same copies (the same names, so the same numbers) and
  selects them again.
- Removing a copy later with Remove from Library… is not an undo step, and
  it clears the undo stack (LO §6.3). Right after a mistaken Duplicate,
  ⌘Z is the way back, and nothing tells the person otherwise. This is
  assumption A3.

### 4.4 Feedback

- **Success:** no alert and no Activity row, because the copies are visible
  (UID P4). VoiceOver hears "Made a copy of “‹name›”." for one photo, or
  "Made ‹N› copies." for several.
- **Videos skipped** in a mixed selection: one Activity **information** row
  titled "Duplicate", reading "‹N› videos weren't duplicated." This follows
  the ml-denoise precedent, where Activity says how many files were left out
  of a paste. No row when no video was among the targets.
- **Long batches:** if the write takes longer than about half a second
  (thousands of photos), Activity shows an indeterminate job, "Duplicating
  ‹N› photos…", with **no Stop**, because the change is one transaction, as
  in LO §6.3. Nothing changes in the grid until it is written.
- **Failure:** nothing changes. Activity posts a **warning** titled
  "Duplicate": "The photos couldn't be duplicated. The library is
  unchanged.", with the error as its detail. No alert (P4).
- **An unreadable edit stack** (the PRD's engineer question): the design
  prefers that the copy takes the stored stack unchanged, a snapshot with
  nothing written over, and is then uneditable like its original, with the
  same Adjust tab state. If the engineer finds that can't be done safely, the
  photo is skipped and counted in the same information row: "‹N› photos
  weren't duplicated because their adjustments can't be read." The engineer
  says which in `status.md`.

## 5. Naming

### 5.1 The display name

A copy has no file of its own, so the app gives it a name in the form the
Finder uses for duplicates:

| `versionNumber` | Name (from `IMG_0412.RW2`) |
|---|---|
| 1 (the original) | `IMG_0412` (unchanged) |
| 2 | `IMG_0412 copy` |
| 3 | `IMG_0412 copy 2` |
| *n* ≥ 3 | `IMG_0412 copy ‹n − 1›` |

- **Derived, not stored.** It comes from `versionNumber`, which never
  changes for a copy, so names are stable: removing "copy" doesn't rename
  "copy 2". `duplicateVersion` takes the highest number + 1, so a new copy
  made after the highest one was removed gets that number again, as the
  Finder reuses "copy 2" once the old one is gone. This is assumption A2.
- **Localized** through the String Catalog ("%@ copy", "%@ copy %lld"), as
  the Finder localizes its suffix.
- **One function**, used everywhere a photo's name is shown or spoken
  (`CatalogItem` needs `versionNumber`, read by the item queries). For
  originals it gives exactly today's `baseName`.
- **R10 (a name typed by the person) is deferred** (§13). When it comes, a
  typed name replaces "copy ‹n›" in this one function, and nothing else in
  this design changes.

### 5.2 Where it is used

| Place | Original | Copy |
|---|---|---|
| Grid cell name row (View ▸ Show File Names) | `IMG_0412` | `IMG_0412 copy 2` (middle truncation, as now) |
| Type badge | `RAW`, `RAW+JPEG`… | the copied file's type only, never a pair (§4.1) |
| Loupe window title | `IMG_0412.RW2` | `IMG_0412 copy 2`, without the extension. With the extension the title would name a file that doesn't exist on disk, and Show in Finder reveals `IMG_0412.RW2`. The caption's Copy badge names the file (§6.3) |
| Film strip tooltip, VoiceOver label (grid, strip, loupe) | `IMG_0412, RAW` | `IMG_0412 copy 2, RAW` |
| Removal confirmation title (one target) | `Remove “IMG_0412” from the library?` | `Remove “IMG_0412 copy 2” from the library?` |
| Inspector, Info tab, file rows | `IMG_0412.RW2` | `IMG_0412.RW2`: the Info tab describes the file, which is the master's |
| Activity rows that name photos (export failures, for example) | file name | display name |
| Search field | matches the file name | unchanged: typing "copy" doesn't find copies (R11 covers finding them) |

### 5.3 Export file names (R8, AC8)

- **Original Name** writes the display name: `IMG_0412 copy.jpg`,
  `IMG_0412 copy 2.jpg`.
- **Templates:** the `{name}` token (titled "Original Name" in the token
  field) expands to the display name, so `{name}-{export:yyyy-MM-dd}` gives
  `IMG_0412 copy-2026-11-11.jpg`. `{number}` and the other tokens are about
  the file and the capture, and are unchanged. A template without `{name}`
  gives the copy no suffix, and the batch's existing rule (`-2`, `-3`…) still
  keeps names apart. AC8 holds either way.
- The sanitizer keeps the space, as it keeps spaces in other names.
- No new token and no new export option. A token for the copy number alone
  was considered and rejected: one rule that holds for every naming choice
  is easier to predict than another pill in the field.
- `TemplateContext` gains the display name next to `originalName`, so the
  import window's templates (which never see a copy) are unchanged.

## 6. Marking a copy

The mark answers "is this the original or a copy?" at a glance, without
reading names: names can be hidden (View ▸ Hide File Names) or cut off in
narrow cells. The original is **not** marked as "has copies". Its copies sit
right after it, and a second mark on every photo with copies would add noise
to a culling surface for little gain. This is judgment.

### 6.1 Grid cell

- **Glyph:** SF Symbol `square.on.square`, white, 12 pt, on the same dark
  backing as the offline mark (black at 55%, corner radius 4, 22 × 18 pt).
- **Place:** the image area's **top-trailing** corner, mirroring the offline
  mark at top-leading (`offlineLayer`'s frame reflected). It is drawn at
  every cell size, including cells too narrow for the star strip, because it
  is identity, not decoration.
- **Not color:** it is a shape. The text (name row, VoiceOver) says "copy"
  too.
- **Rejected copies** dim with the image, as now. The mark stays at full
  opacity, as the offline mark does.
- **Right to left:** the corner mirrors with the layout, as the offline mark
  should.

### 6.2 Film strip

- The same glyph at the strip's mark size (`FilmStripMetrics.markGlyphSize`)
  on a `filmStripMarkBacking` at the fitted picture's **top-trailing** corner.
  That is the one free corner: offline is top-leading, video bottom-leading,
  and culling bottom-trailing.
- The tooltip and VoiceOver label use the display name (§5.2).

### 6.3 Loupe and review

- **Caption badge "Copy"** (the existing `CaptionBadge`), placed after the
  Machine Learning Not Applied badge and before Offline. Identity badges
  (Copy, Offline) sit nearest the strip toggle, where they don't move as
  transient badges (maps, Original, spinner) come and go.
  Tooltip: `A copy of “IMG_0412.RW2”. Its adjustments, rating, flag, label,
  keywords and albums are its own.`, with the master's file name. VoiceOver
  reads the badge's text, and the tooltip as its help.
- **Window title:** the display name (§5.2).
- **Review:** the caption, and with it the badge, is shown as usual. The
  film strip is hidden in review, as now.
- **History panel:** a new copy's list is empty (R2) and shows the panel's
  existing empty state. No "Made a copy" entry: duplicating doesn't change
  the copy's edits, and the History panel records edits only.

### 6.4 Accessibility

- The VoiceOver label carries the display name, so "copy 2" is spoken
  first, before type, rating and flag.
- The glyph layers are not separate accessibility elements. The label
  already says it.
- Increase Contrast: the backing and the white glyph are the offline mark's
  (grid) and `filmStripMarkBacking` (strip), so the copy mark is exactly as
  legible as the marks already there. No new palette role. White on black at
  55% over a white image area is the weakest case; it is a manual check (V6).
- Reduce Motion: no new motion. The grid's existing insert behavior applies
  (no animation is added).

## 7. Removing (R6, AC6)

LO §6's confirmation, with these changes. The rules (no default button,
Remove destructive, sheet on the library window) are unchanged.

- **Counting.** ‹N› in the title counts the targets as the grid shows them,
  copies included (D6).
- **Every target is a copy:** the message is replaced, since no file, sidecar
  or original is involved:
  - One: `The original and its file are not affected. The copy's edits are
    lost, along with its rating, keywords and albums. You can't undo this
    action.`
  - Several: `The originals and their files are not affected. The copies'
    edits are lost, along with their ratings, keywords and albums. You can't
    undo this action.`
- **Removing originals that have copies outside the targets:** a sentence
  before the standard one, counting only copies that aren't already targets:
  - `Its copy is removed with it.` / `Its ‹C› copies are removed with it.`
    (one target)
  - `‹C› copies of these photos are removed with them.` (several targets;
    plural rule)
  The pair sentence (LO §6.2, item 1) still counts files of pairs only, and
  copies never count as pair files.
- **Mixed targets** (originals and copies): the standard message, plus the
  copies sentence when it applies.
- **A copy of a pair's file** is removed alone. It isn't paired (D5), so the
  pair sentence never fires for it.
- **Project removal** is unchanged. "Its ‹N› photos" already counts copies,
  because the sidebar badge does (D6).
- **Focus after removal:** LO §6.3 and D-L8 are unchanged. Removing a copy
  usually focuses the next copy, or the original before it.

## 8. "Is a copy" smart-album rule (R11, Could)

If the engineer builds it:

- **Field** "Photo", of the existing flag kind (`isTrue` / `isFalse`), with
  the comparisons **is a copy** and **is not a copy**. It reads as "Photo is
  a copy" in the rule row, in the same sentence form as "Location is known".
- Listed last among the rule fields, after Description.
- No built-in smart album and no sidebar filter. A rule is enough for an
  occasional need. This is judgment.
- If it isn't built, nothing else in this design depends on it.

## 9. Things deliberately not changed

- Show in Finder for a copy reveals the master's file (its only file), as
  for the original.
- Sidecars: nothing in the UI suggests a copy's rating or keywords reach an
  `.xmp` (D3). The Copy badge's tooltip says the values are the copy's own,
  and makes no claim about sidecars.
- Drag and drop to albums and keywords, culling keys, presets, paste, Auto
  Exposure, crop and History act on a copy exactly as on any photo.
- No stacks UI (non-goal), and no compare view (non-goal).

## 10. Strings (catalog keys)

Added by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings`, each with
a comment naming its use. None mentions the product name. Plurals use
plural variations.

- Menu: "Duplicate" (File menu and photo context menus).
- Undo: "Duplicate" (undo action name; the same key can serve both if the
  comment names both uses).
- Names: "%@ copy" (a copy's name: the original's name without extension);
  "%@ copy %lld" (the same, numbered from 2).
- Caption: "Copy" (badge); "A copy of “%@”. Its adjustments, rating, flag,
  label, keywords and albums are its own." (badge tooltip; the master's file
  name).
- Activity: "Duplicate" (row title); "%lld videos weren't duplicated."
  (plural); "%lld photos weren't duplicated because their adjustments can't
  be read." (plural, only if §4.4's fallback is built); "Duplicating %lld
  photos…" (plural); "The photos couldn't be duplicated. The library is
  unchanged."
- VoiceOver: "Made a copy of “%@”."; "Made %lld copies." (plural).
- Removal: "The original and its file are not affected. The copy's edits
  are lost, along with its rating, keywords and albums. You can't undo this
  action."; "The originals and their files are not affected. The copies'
  edits are lost, along with their ratings, keywords and albums. You can't
  undo this action."; "Its %lld copies are removed with it." (plural, with
  the one form "Its copy is removed with it."); "%lld copies of these photos
  are removed with them." (plural).
- Smart album (if R11 is built): "Photo" (rule field); "is a copy", "is not
  a copy" (rule comparisons).

## 11. User guide terms

The engineer updates `docs/USER_GUIDE.md`. The review checks these terms
against the UI:

- **File ▸ Duplicate** (⌘D; grid and loupe context menus). A new paragraph
  says what a copy is: its own adjustments, history, rating, flag, label,
  keywords and albums, starting from the original's. It also covers where
  the copy appears, how it is marked and named, that videos aren't
  duplicated, that a pair's copy is one file and unpaired, that copies are
  never written to sidecars, how copies are removed, and undo.
- The key table gains ⌘D (grid and loupe columns).
- Export: one sentence on copies' file names (§5.3).
- Removing: removing a photo takes its copies; removing a copy takes only
  the copy.
- History: replace "A version made as a copy of another starts with an
  empty list" with wording that uses "copy" ("A copy (File ▸ Duplicate)
  starts with an empty list").
- **Terminology fix:** the Importing paragraph's "Duplicates (same content
  anywhere in the library) are skipped" becomes "Files already in the
  library (same content anywhere in it) are skipped". "Duplicate" now names
  a command, and the import UI already says "Already in Library". The words
  "virtual copy" and "version" never appear (§1).

## 12. Implementation notes and acceptance

What changes and how each is checked. Glass panes don't snapshot, so menu
checks use `menuitems` / `menupress`, and grid checks use `print`,
`accessibility` and `snapshot` of the content area.

| # | Change | Acceptance |
|---|---|---|
| V1 | File ▸ Duplicate ⌘D (§2.1, §3), `canByKey` with `targetsIncludePhoto` and not cropping | `menuitems Duplicate`: enabled in the grid with a photo selected; dimmed with only a video selected, with the sidebar focused, and during a crop. `menuitems` lists the File menu in §2.1's order |
| V2 | Context menus (§2.2) | The context-menu probe lists Duplicate before Export… in the grid and loupe, and doesn't list it in the video loupe |
| V3 | Duplicate: placement after the master's items, selection and focus, loupe moves to the copy, one undo step "Duplicate" (§4.2, §4.3) | Unit test on the catalog: order of versions for capture-date, file-name and rating sorts right after duplicating. Debug script: `menupress Duplicate`, then `print` shows the copy after the original, selected and focused; `menuitems Undo` reads "Undo Duplicate"; ⌘Z / ⇧⌘Z restore selection (AC1) |
| V4 | Display name (§5.1): one function, used in the grid name row, window title, VoiceOver labels, film strip tooltip, removal title, Activity | Unit test: version 1 → base name; 2 → "copy"; 3 → "copy 2"; a removed middle copy leaves the others' names. `accessibility` lists "IMG_… copy" for the copy's cell |
| V5 | Export naming (§5.3) | Unit test of `ExportNaming` with an original and two copies under Original Name and under `{name}`-based and `{seq}`-only templates: distinct names, the expected suffixes (AC8) |
| V6 | Grid and film strip mark (§6.1, §6.2) | `snapshot` of the grid shows the glyph at top-trailing on the copy only. Manual M-check: the strip's mark, Increase Contrast |
| V7 | Caption badge and title (§6.3) | Debug script in the loupe on a copy: `print` caption badges include "Copy"; window title is the display name. Manual: tooltip text |
| V8 | Activity rows for skipped videos, long batch and failure (§4.4); VoiceOver announcements | Unit test of composed strings. Debug script: a mixed photo-and-video selection gives one information row |
| V9 | Removal confirmation text (§7) | Unit test of composed strings: one copy; several copies; one original with two copies outside the targets; several originals with copies; mixed; a copy of a pair's RAW (no pair sentence) (AC6) |
| V10 | Smart-album rule, if built (§8) | Unit test of the SQL condition; editor title strings |
| V11 | `docs/USER_GUIDE.md` (§11) | Checked at design review |

## 13. Requirements issues (for the product manager)

| RI | Issue | Design default (already in §1–§12) |
|---|---|---|
| RI-V1 | **Videos.** R1 says "each selected photo", but a video is an item too, and the PRD doesn't say whether videos can be duplicated. A video has no adjustments, so its copy could differ only in culling, keywords and albums. Confirm that videos are not duplicated | Not duplicated. Duplicate is dimmed (and left out of the menus) when no target is a photo, and skipped videos are counted in Activity (§4.1, §4.4). If the ruling is "yes", only §4.1's photo rule, §2.2's video loupe line and the Activity row change |
| RI-V2 | **R5's "same sort position".** With View ▸ Sort By ▸ Rating, a copy rated differently from its original sorts by its own rating and no longer sits beside it. The two are independent items (D1), so this is expected, but R5 reads as if copies always stay adjacent. Amend R5 to "placed right after its original when made; afterwards it sorts by its own values"? | Copies sort by their own values. With capture-date and file-name sorts they always stay with their original (§4.2) |
| RI-V3 | **AC5's "status line".** There is no status line since the UI redesign: counts are in the window subtitle ("4,623 photos") and the sidebar badges. Amend AC5 to "the sidebar counts and the window subtitle include copies" | Both include copies (D6) |

**R10 deferred (D8).** The design defers both parts of R10, naming a copy
and making a copy the default version, and the owner should be told.
Making a copy the default moves sidecar ownership (D3) and changes which
version a RAW+JPEG pair links through (`ImagePairing` works on default
versions). It also changes which file's sidecar a later import reads, and
the order of the grid. Each of these is a design and engineering problem of
its own. Naming needs an editing surface (an inspector field or in-place
rename in the grid), an undo step, and rules for export names. Neither is
needed for the PRD's goal, which a numbered copy meets. §5.1 leaves a
single place where a typed name would plug in. Proposed follow-up issue
(enhancement): "Name a copy, and make a copy the original", slug
`copy-name-and-default`, body: "R10 of virtual-copies (#62), deferred at
design: let people give a copy a name (shown in place of ‘copy ‹n›’ and used
in export names) and make a copy the default version of its photo, which
takes over the sidecar and the RAW+JPEG pair link."

## 14. Assumptions (stated, not raised)

- **A1.** Offline photos can be duplicated (the PRD's proposed answer).
  The copy is catalog-only and shows the cached preview.
- **A2.** Copy names come from `versionNumber`. A number freed by removing
  the highest copy can be given to the next new copy (§5.1).
- **A3.** Removing a copy clears the undo stack, like any removal (LO §6.3).
  Undo Duplicate is the quick way back right after a mistaken Duplicate.
- **A4.** A copy of a copy is placed after its master's last copy, not
  directly after the copy it came from. All of one master's items stay
  together, in the order they were made.
- **A5.** The copy's display name is used in export file names, even under
  "Original Name". That option names the photo as the library shows it,
  which for a copy includes "copy".

## 15. Design questions from implementation

None yet. Rulings are recorded here as D-V1, D-V2….
