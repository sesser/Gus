# Library operations: design

Owner: apple-ui-designer. Date: 2026-11-10. Issue: #61. Status: complete,
with four requirements issues open for the product manager (§13). §2–§12
already assume the default given for each, so the engineer can start; a
different ruling changes only the lines named in §13.

**Inputs.**

- Requirements: [`prd.md`](prd.md), R1–R18 and AC1–AC13, with the owner
  rulings of 2026-11-10. Cited as "R‹n›" and "AC‹n›".
- Current design: [`../ui-redesign/design.md`](../ui-redesign/design.md)
  (cited as "UID"): placement rules P1–P5, the command map (§4), the I11
  deletion confirmations, RI-2 and RI-3.
- Code read at `1dc2dce` (`develop`): `Views/LibraryCommands.swift`,
  `Views/LibraryMenuContext.swift`, `Views/SidebarView.swift`,
  `Views/SmartAlbumEditor.swift` (`NameSheet`), `Grid/PhotoContextMenu.swift`,
  `Model/LibraryModel.swift`, `Catalog/Catalog.swift`,
  `Catalog/CatalogSchema.swift`, `PhotoUI/Import/ImportCommands.swift`.
- HIG pages read 2026-11-10 (markdown versions): Keyboards (standard
  shortcuts, custom shortcuts), Menus (ellipsis, unavailable items), Alerts
  (default and Cancel buttons, destructive style, caution symbol).

No custom chrome. Every surface here is a system component: menu bar items,
`NSMenu` context menus (as the grid and loupe already build them), a SwiftUI
`List` row with a `TextField` for the rename, and a system alert for the
confirmations.

## 1. Structure

The four operations are file-management commands on things the person has
selected, so they live where Mac users look for file commands: the **File**
menu, with second paths in the context menus of what they act on (UID P1,
P2). None goes in the toolbar (§2.4).

| Operation | Acts on | Menu bar | Context menus | Key |
|---|---|---|---|---|
| Show in Finder | the photos (grid selection, loupe photo), or the project selected in the sidebar when the sidebar has the keyboard | File | grid, loupe, video loupe, sidebar project row | ⇧⌘R |
| Rename (project) | the project selected in the sidebar | File ▸ Rename “‹name›” | sidebar project row | Return in the sidebar starts it |
| Remove from Library… | the photos (grid selection, loupe photo) | File | grid, loupe, video loupe | ⌘⌫ |
| Remove Project from Library… | the project selected in the sidebar | File | sidebar project row | none |

The two verbs are deliberate. **Delete** stays the word for things that exist
only in the library and go entirely (albums, smart albums, keywords, presets).
**Remove … from Library** is the word for photos and projects, whose files
stay on disk. That split is why Remove Project from Library… is its own item
and File ▸ Delete stays dimmed for a project: a project "Delete" would read as
deleting the folder (HIG Writing, choose one term for each thing; UID P5).

## 2. Placement

### 2.1 File menu

New items in **bold**. Everything else is as built (UID §4).

```
Import from Card or Folder…          ⌘I
Add Folder Without Copying…          ⇧⌘I
─────────────
New Album…                           ⌘N
New Smart Album…                     ⌥⌘N
Edit Smart Album…
Rename “‹name›”…  /  Rename “‹project›”
Delete “‹name›”…
**Remove Project from Library…**
─────────────
**Show in Finder**                   ⇧⌘R
Export…                              ⇧⌘E
**Remove from Library…**             ⌘⌫
─────────────
Check for Changes on Disk
Stop ‹job›                           ⌘.
─────────────
Close                                ⌘W
```

- **Sidebar-item group.** Remove Project from Library… joins Rename and
  Delete, the commands on what the sidebar has selected. A new separator
  after it ends that group.
- **Photo-file group.** Show in Finder, Export… and Remove from Library…
  act on the photo targets (or, for Show in Finder, the sidebar's project:
  §5.2). The two job items (Check for Changes on Disk, Stop) move into a
  group of their own, so the destructive item doesn't sit beside Stop.
- **Ellipses.** Both Remove items end in "…", because each asks for a choice
  in a confirmation before it acts (HIG Menus: the ellipsis signals that
  "people need to … make additional choices"). This is the app's existing
  rule for confirmations that can't be undone (UID I11: "Delete…",
  "Delete Preset…"). R17's names are unchanged; the ellipsis is
  typography, not part of the name, and AC13 should be read with it.
- **Rename for a project has no ellipsis**: it edits the name in place in the
  sidebar, as the Finder's Rename does, rather than opening another view.
  Albums and keywords keep "Rename “‹name›”…", which opens their sheet.
  The title follows the selection, so the two never show at once.

### 2.2 Photo context menus (grid, loupe, video loupe)

The rule from UID P2 and UIR §7 holds: an item that can't act is left out,
not dimmed.

- **Show in Finder** goes in the group that holds **Export…**, after it:
  Export…, Show in Finder, then the RAW+JPEG Pair ▸ submenu. Left out when no
  target can be revealed (§5.1). The video loupe gets it from the same shared
  photo items.
- **Remove from Library…** is always the **last item** of each of the three
  menus, alone in a final group after a separator: after Crop in the loupe,
  after Show Grid in the video loupe, after the RAW+JPEG Pair group in the
  grid. Shown whenever there are targets. Putting the one destructive,
  irreversible item last and apart keeps it away from the pointer's path
  through frequent items, and matches where the sidebar's project menu puts
  it (§2.3). Judgment; the HIG is silent on where a destructive item goes in
  a context menu.

### 2.3 Sidebar project row context menu

```
New Album in Project…
New Smart Album in Project…
─────────────
Rename
Show in Finder
─────────────
Remove Project from Library…
```

- The existing two items stay first (they are the row's current menu; don't
  move what people know).
- **Rename** is SwiftUI's `RenameButton`, which reads the row's
  `renameAction` (§4); its title is the system's "Rename".
- **Show in Finder** is left out when the project has no folder to reveal
  (§5.2).
- **Remove Project from Library…** is last and alone, as in §2.2.
- The menu acts on the row that was right-clicked, which need not be the
  selected one (as the album and keyword rows already do).

### 2.4 Not placed

- **Toolbar:** nothing, not even as palette items. Show in Finder is
  occasional and already one key away; a toolbar button for an irreversible
  removal invites accidental clicks for no gain in speed (HIG Toolbars: the
  most frequent commands). Judgment.
- **Inspector:** no reveal button beside the Info tab's File or Folder rows.
  The menu bar, the key and the context menus cover it; the Info tab stays a
  read-only list. Judgment.
- **VoiceOver custom actions:** none added to the grid or loupe; see §9.
- **`photocli`:** non-goal (prd.md).

## 3. Keys

Checked against every `keyboardShortcut` in `Sources/` and the HIG's
standard-shortcut table.

| Command | Key | Why | Conflicts checked |
|---|---|---|---|
| Show in Finder | **⇧⌘R** | Widely used for revealing an item's file in the Finder in Mac apps (judgment: the HIG's table lists no reveal command, so this is convention, not Apple policy). Show Original keeps bare `\` and its title; the two titles and keys share nothing (R17, AC13) | Not in the HIG standard table. Not used in the app. The Import window's Rescan is ⌘R; the HIG asks not to make a new key by adding a modifier to an unrelated command's key. Accepted: the two never act in the same window (Rescan only in the Import window, Show in Finder only in the library window), and ⇧⌘R is the key people are most likely to try for this command. A conscious tradeoff, recorded here |
| Remove from Library… | **⌘⌫** | The Mac's key for "remove the selected item" (the Finder's Move to Trash). It adds Command to bare ⌫, Remove from Album, a related command with the wider reach: the HIG's modifier rule is met because the commands are related (one removes from an album, the other from the library) | Bare ⌫ stays Remove from Album. ⌘⌫ is a text-editing key (delete to the start of the line): see the enablement rule below |
| Remove Project from Library… | **none** | Rare and irreversible; the HIG asks for custom keys only for frequent commands. ⌘⌫ is not reused for it: one key that removes photos or a whole project depending on which pane has focus is too easy to misfire for an action with no undo | — |
| Rename (project) | **none** in the menu; **Return** in the sidebar | Return on a selected item starts renaming, as in the Finder sidebar and list views. It is a view key, handled only while the sidebar has the keyboard and a project row is selected, so it can't clash with Return in the grid (open the loupe) | Return does nothing in the sidebar today |

**⌘⌫ is enabled only while the grid, loupe or video loupe has the keyboard**
(the bare-key rule, `canByKey`, UIR §6), though it carries a modifier. A menu
key equivalent is offered before the text field gets the key, so an item
enabled everywhere would answer ⌘⌫ typed in the search field or the keyword
entry with a removal confirmation instead of deleting text. With the sidebar
focused, ⌘⌫ does nothing, so it can never mean "remove the project". The cost:
choosing the item from the menu with the pointer while the sidebar or the
search field has the keyboard finds it dimmed. Click a photo first. The
menu shows the key, so this is the same behavior people already see on the
culling items.

## 4. Renaming a project in the sidebar (R1–R4)

**Starting.** Three routes, one behavior. Each puts the project's sidebar row
into editing:

1. File ▸ Rename “‹project›” (enabled when a project row is selected in the
   sidebar, whatever has the keyboard, like Rename for albums).
2. The row's context menu ▸ Rename.
3. Return while the sidebar has the keyboard and a project row is selected.

Build it with SwiftUI's `renameAction(_:)` on the project row, triggered by
`RenameButton` in the context menu and by the same action from the File item
and Return, focusing a `TextField` in the row through `@FocusState`. This is
SwiftUI's own rename mechanism; the engineer confirms it on macOS 15 and 26
(both have it, from macOS 13).

If the row isn't visible when File ▸ Rename runs, the window makes it so
first: shows the sidebar if hidden, turns the Projects section back on if it
was hidden with View ▸ Sidebar Sections, expands it, and scrolls to the row.
The person asked to rename something; showing it is the only way to do that.

**Editing.**

- The row's label is replaced by a text field in the row, same font and
  position, holding the current name, **all of it selected**, so typing
  replaces it and arrow keys move within it (the Finder's behavior).
- The folder symbol and count badge stay; the row keeps its height.
- **Return** saves. **Escape** cancels and puts the old name back. Clicking
  elsewhere or moving the keyboard elsewhere (Tab, a click in the grid)
  **saves**, as in the Finder.
- Bare keys stay off while the field has the keyboard (the sidebar has it,
  not the grid), so typing "P" or "5" never culls.
- After it saves or cancels, the sidebar keeps the keyboard with the row
  selected.

**Saving (R2, R3, R4).**

- Leading and trailing white space is trimmed (assumption A2).
- An empty or white-space-only name is refused: the old name comes back,
  editing ends, and the system alert sound plays (`NSSound.beep()`), the
  Mac's signal for input that wasn't taken. No alert: the person can see the
  result and simply rename again (HIG Alerts: don't alert for information
  alone). This is R2's "refused".
- A name equal to the current one saves nothing and adds no undo step.
- Duplicate names are allowed, with no warning (R2).
- A change is **one undo step**, named "Rename Project", so Edit shows
  "Undo Rename Project" / "Redo Rename Project" (R3).
- The catalog only: no folder or sidecar changes, and nothing in the UI
  suggests otherwise. The row's tooltip keeps showing the folder path, which
  makes it visible that the folder kept its name.
- If the projects are listed by name, the row moves to its new place, stays
  selected and is scrolled into view.

**Accessibility.** The field's accessibility label is "Project name". When
the edit ends, VoiceOver reads the row as usual. A refused empty name also
posts the announcement "The name can't be empty." so VoiceOver users learn
what the beep meant.

## 5. Show in Finder (R14–R16)

### 5.1 Photos

- **Targets** are what the other photo commands act on: the grid's
  selection, or the photo in the loupe or video loupe.
- **What is revealed.** Each target's original. A grouped RAW+JPEG pair
  (one cell) reveals its RAW, whichever file the cell shows (R14). With View ▸
  Group RAW+JPEG Pairs off, each file is its own cell, and a selected cell
  reveals that file (assumption, §13 RI-L4).
- **One call.** All the files go to the Finder in one request
  (`NSWorkspace.activateFileViewerSelecting(_:)`), so files in one folder open
  one Finder window with all of them selected (AC11). Files in several
  folders open one window per folder; that is the Finder's behavior and is
  raised as RI-L3.
- **Enabled** (menu) / **shown** (context menus) when at least one target's
  original is online. Menu validation never touches the disk: it reads the
  online state the grid and caption already know (the Offline badge). Dimmed
  when every target is offline (R16, AC12).
- **Some targets offline.** The online ones are revealed. Activity posts one
  **information** row, titled "Show in Finder": "‹N› photos weren't shown
  because their originals are offline." Nothing to act on, so no alert
  (UID P4). A file that turns out to be missing when the command runs (the
  volume is online but the file was moved) is skipped and counted the same
  way, with "…because their originals are offline or missing." when any is
  missing.
- **Never a mount point.** Only file URLs of originals are passed; if none
  is left after skipping, nothing opens (R16).

### 5.2 Projects, and which one File ▸ Show in Finder means

**Answer to the PRD's open question: a project's Show in Finder is not in the
context menu only.** UID P1 requires every command in the menu bar, so File
▸ Show in Finder also reveals a project, following the Mac rule that a
command acts on the selection in the view with the keyboard focus:

- **The sidebar has the keyboard:** File ▸ Show in Finder (and ⇧⌘R) acts on
  the selected sidebar row. A project with a folder to reveal: its folder. Any
  other row (an album, a date, Picks): dimmed, since those have no folder.
- **Anything else has the keyboard** (grid, loupe, video loupe, search field,
  inspector): it acts on the photo targets (§5.1).

The sidebar shows which pane has focus by its selection's accent color, so
the target is visible before the key is pressed. This needs a "sidebar has
the keyboard" value in `LibraryMenuState` beside `browserHasKeyboard`, from
the same first-responder observer.

**Revealing a project** opens its folder (`sourcePath`) in the Finder,
selected in its parent, in one window (R15).

**Enabled / shown** only when all hold (R16, AC12):
1. `sourcePath` is set;
2. it is not a volume's mount point (a card or disk imported from its root
   reveals nothing rather than the volume, R16);
3. its volume is mounted and the folder exists.

Check 3 is one file-system check for one path, made when the context menu is
built and when the sidebar selection or the mounted volumes change, not on
every menu update. The menu bar title stays "Show in Finder" in both cases:
the item names the action, and the selection names the object.

## 6. Removing photos (R5–R7, R9–R13)

### 6.1 Enablement

- **File ▸ Remove from Library… ⌘⌫:** enabled when there are targets and the
  grid, loupe or video loupe has the keyboard (§3). Offline photos and videos
  count like any other (R11). Dimmed while a sheet is up, as all library
  items are.
- **Context menus:** shown whenever there are targets.

### 6.2 Confirmation

A system alert attached to the library window as a sheet (window-modal), the
form the app's other irreversible deletions use (UID I11). It never
dismisses itself (R9).

**Title** (a question, sentence-style with a question mark; HIG Alerts):

- One target: `Remove “‹file name›” from the library?`, with the file name
  the grid's cell shows.
- Several: `Remove ‹N› photos from the library?` (plural rule), where ‹N›
  counts the targets as the grid shows them (a grouped pair is one photo,
  as in the Export sheet, UID I1).

**Message**, in this order:

1. Only when removing pairs adds files beyond ‹N› (R7, AC5):
   `Both files of each RAW+JPEG pair are removed, ‹F› files in all.`
   For one grouped pair, or the JPEG of an ungrouped pair, ‹F› is 2.
2. Always:
   `The files and their sidecar files stay on disk, unchanged. Their edits
   are lost, along with their ratings, keywords and albums in the library.
   You can't undo this action.`

The message states each thing R9 and R10 ask for: the count, that files on
disk are not touched, that edits are lost, and that it can't be undone.
"In the library" is precise on purpose: values written to sidecars stay in
those files, and a re-import reads them back (R12), but edits are never in
sidecars (CLAUDE.md), so "edits are lost" is said without qualification.
The text never uses the product name, so no `%@` for it is needed.

**Buttons:** `Remove` and `Cancel`.

- **No default button.** Return does nothing; Escape and ⌘. choose Cancel.
  The HIG asks for this: "you don't want to make a Cancel button the default
  button. If you want to encourage people to read an alert and not just
  automatically press Return to dismiss it, avoid making any button the
  default button." R9 asks for Cancel as the default; RI-L2 asks the product
  manager to amend it. Both protect against the same thing, a Return pressed
  without reading, so if the ruling keeps Cancel as the default, only this
  bullet changes.
- **Remove has the destructive style** (`role: .destructive`), as the app's
  other Delete buttons do (I11). The HIG says not to give a deliberately
  chosen action the destructive style, so that Return can confirm it. Here
  Return confirms nothing, and ⌘⌫ makes an accidental start likely, which is
  the case the style is for.
- **No caution symbol**: the app icon, as in the other confirmations. The
  HIG keeps `exclamationmark.triangle` for unexpected loss, not for commands
  whose purpose is to remove.
- **No "Don't ask again" box.** Removal can't be undone (R10).

Implementation note: build it as the existing deletions are built
(`confirmationDialog` on the library window). If SwiftUI on macOS 15 or 26
makes Remove (or Cancel) respond to Return and nothing turns that off, use
`WindowModal`'s `NSAlert` (PhotoUI), with Remove's key equivalent cleared and
Cancel's set to Escape, and note the reason in `status.md`. That is the
only acceptable reason to drop to AppKit here.

### 6.3 After confirming

- **Nothing changes on screen until the removal has been written.** The
  catalog change is all or nothing (R13), so the grid never shows photos gone
  that then come back.
- If it takes longer than about half a second (thousands of photos),
  Activity shows an indeterminate job, "Removing ‹N› photos…", with **no
  Stop**: a half-done transaction can't be stopped part way, and File ▸ Stop
  ⌘. doesn't name it. The window stays usable meanwhile; the two Remove items
  are dimmed until it ends.
- **Success:** the photos leave every source. The grid keeps the keyboard
  and focuses the photo that followed the last removed one in the grid's
  order, or the one before it if none followed; the loupe shows that photo.
  If the source is left empty, the loupe returns to the grid and the
  source's empty state shows (UID N3). Keywords that reach zero photos leave
  the sidebar as they already do; albums stay, empty if need be (R6). No
  Activity row and no alert: the result is visible. VoiceOver hears
  "Removed ‹N› photos from the library." (§9).
- **Failure:** nothing changes in the catalog or the grid. Activity posts a
  **warning**, titled "Remove from Library" (Activity titles are menu titles
  without the ellipsis, UIR §1): `The photos couldn't be removed. The
  library is unchanged.`, with the underlying error as its detail (R13,
  AC10). No alert, because the person can't act on it beyond trying again
  (UID P4).
- **Undo (R10, AC7):** the removal is not an undo step. After a removal
  succeeds, the window's undo stack is cleared, because earlier steps can
  refer to the photos that are gone (a rating or edit on them). Edit ▸ Undo
  is then dimmed until the next change. This is a visible cost, and the
  confirmation's "You can't undo this action" already covers it.

## 7. Removing a project (R8–R13)

### 7.1 Enablement

- **File ▸ Remove Project from Library…:** enabled when a project row is
  selected in the sidebar, whatever has the keyboard (as Delete is for an
  album). Dimmed for any other selection.
- **Sidebar context menu:** on every project row.
- An empty project (no photos) is removed the same way, with the same
  confirmation.

### 7.2 Confirmation

The same alert form as §6.2: sheet on the library window, `Remove` and
`Cancel`, no default button, Remove destructive.

**Title:** `Remove the project “‹name›” from the library?` (the same shape
as "Delete the album “‹name›”?").

**Message**, in this order:

1. `Its ‹N› photos are removed with it.` (plural rule; ‹N› is the number the
   sidebar badge shows), or `It has no photos.`
2. Only when pairs add files: the pair sentence of §6.2, with ‹F› for the
   whole project.
3. Only when the project has albums or smart albums of its own (RI-L1):
   `Its ‹K› albums are deleted.` (plural rule; albums and smart albums
   counted together).
4. Always: `The folder, its files and their sidecar files stay on disk,
   unchanged. The photos' edits are lost, along with their ratings, keywords
   and albums in the library. You can't undo this action.`
   With no photos, only `The folder stays on disk, unchanged.`

### 7.3 After confirming

As §6.3, with these differences: the project's row leaves the sidebar and the
sidebar selects All Photos (as when any source disappears), with the sidebar
keeping the keyboard; the Activity job and failure warning are titled
"Remove Project from Library" (failure text: `The project couldn't be
removed. The library is unchanged.`); VoiceOver hears "Removed the project
“‹name›” from the library."

## 8. Running jobs

PRD and design don't need anything here, but the engineer may find one:
removing photos that an export, an in-place import or a card import is
working on. If removal can't run safely beside such a job, both Remove items
are dimmed (and left out of the context menus) while it runs, the same rule
as Export while an export runs (UID I1). Return that as a design question
rather than choosing another behavior.

## 9. Accessibility

- **Menus and context menus** carry every command, and VoiceOver reaches
  them (VO-M for the menu bar, VO-Shift-M for a context menu on the focused
  cell, loupe or sidebar row). That meets R18 without new custom actions on
  the grid and loupe; their action lists stay the frequent culling commands
  (UIR §10). Judgment: adding an irreversible action to the rotor's quick
  actions adds risk for little gain.
- **Full Keyboard Access:** every route works without a pointer: ⇧⌘R, ⌘⌫,
  Return to rename in the sidebar, File menu items.
- **Confirmations** are system alerts, read by VoiceOver in full; Escape
  cancels.
- **Announcements** (`NSAccessibility` announcement, as the culling results
  use): after a photo removal "Removed ‹N› photos from the library." (one:
  "Removed “‹file name›” from the library."); after a project removal (§7.3);
  after a refused empty name (§4). Show in Finder makes no announcement: the
  Finder coming forward is announced by the system.
- **Rename field** label "Project name" (§4).
- **Disabled reasons:** menu items can't carry help text. Why Show in Finder
  is dimmed is visible elsewhere: the Offline badge on the cell and caption,
  the folder tooltip on the project row.
- **Color is never the signal:** the destructive button is red and also
  says "Remove".

## 10. Strings (catalog keys)

All added by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings`, with a
comment naming each use. None mentions the product name. Plurals use the
catalog's plural variations; no string has two plural numbers. If
`StringCatalogCompiler` can't handle a plural, the engineer says so rather
than splitting sentences.

- Menus: "Show in Finder" (File menu, photo and sidebar context menus);
  "Remove from Library…" (File menu, photo context menus); "Remove Project
  from Library…" (File menu, sidebar context menu); "Rename “%@”" (File menu,
  project selected; the existing "Rename “%@”…" stays for albums and
  keywords). The sidebar's "Rename" comes from `RenameButton` (system).
- Photo confirmation: "Remove “%@” from the library?"; "Remove %lld photos
  from the library?" (plural); "Both files of each RAW+JPEG pair are removed,
  %lld files in all." (plural); "The files and their sidecar files stay on
  disk, unchanged. Their edits are lost, along with their ratings, keywords
  and albums in the library. You can't undo this action."
- Project confirmation: "Remove the project “%@” from the library?"; "Its
  %lld photos are removed with it." (plural); "It has no photos."; "Its %lld
  albums are deleted." (plural); "The folder, its files and their sidecar
  files stay on disk, unchanged. The photos' edits are lost, along with their
  ratings, keywords and albums in the library. You can't undo this action.";
  "The folder stays on disk, unchanged."
- Buttons: "Remove". Reused: "Cancel".
- Activity: "Show in Finder" (row title, reuses the menu key); "%lld photos
  weren't shown because their originals are offline." (plural); "%lld photos
  weren't shown because their originals are offline or missing." (plural);
  "Remove from Library" and "Remove Project from Library" (row titles);
  "Removing %lld photos…" (plural); "The photos couldn't be removed. The
  library is unchanged."; "The project couldn't be removed. The library is
  unchanged."
- Accessibility: "Project name"; "The name can't be empty."; "Removed %lld
  photos from the library." (plural); "Removed “%@” from the library.";
  "Removed the project “%@” from the library."
- Undo: "Rename Project" (undo action name).

## 11. User guide terms

The engineer updates `docs/USER_GUIDE.md` (WORKFLOW Ownership). Terms the
review will check against the UI: **Show in Finder** (⇧⌘R; photos, or a
project when the sidebar has the keyboard), **Rename** (a project, in place;
Return in the sidebar), **Remove from Library…** (⌘⌫; files on disk and
sidecars untouched; edits lost; can't be undone; both files of a pair),
**Remove Project from Library…** (the project's own albums go with it), and
the distinction between *remove* (photos and projects, files stay) and
*delete* (albums, smart albums, keywords, presets). The key table gains ⇧⌘R
and ⌘⌫ (grid and loupe columns). The guide must never say "delete" for a
removal.

## 12. Implementation notes and acceptance

No code here; what changes and how each is checked. Glass panes don't
snapshot (CLAUDE.md), so sidebar checks use `print`, `buttons`, `menuitems`
and `menupress`, or are manual (numbered M‹n› at review).

| # | Change | Acceptance |
|---|---|---|
| L1 | `LibraryMenuState`: a project sidebar item (for Rename's title and enablement; Delete stays dimmed for it, titled "Delete…"); "sidebar has the keyboard"; whether Show in Finder can act (photos: any target online; sidebar: project folder check, §5.2) | `menuitems Rename` with a project selected shows "Rename “‹name›”" enabled; `menuitems Delete` shows "Delete…" dimmed |
| L2 | File menu order and separators (§2.1) | `menuitems` on the File menu lists the items in §2.1's order |
| L3 | Show in Finder ⇧⌘R for photos (§5.1), with the Activity information row when some are offline or missing | Unit test of the reveal list: pair grouped → RAW; ungrouped JPEG cell → the JPEG; offline skipped and counted. `menuitems "Show in Finder"`: dimmed with only offline photos selected, enabled with one online. Manual (AC11): three photos in one folder open one Finder window with three files selected |
| L4 | Show in Finder for projects: File item following focus, sidebar context menu (§5.2) | Unit test of the enablement rule: no `sourcePath`; a mount point; folder missing; volume unmounted; folder present. Manual: the sidebar focused on a project, ⇧⌘R opens its folder; focused on an album, the item is dimmed |
| L5 | Inline project rename (§4): `renameAction`, `RenameButton`, File item, Return; trim; refuse empty with beep and announcement; one undo step "Rename Project"; no step for an unchanged name | Unit test of the name rule (trimmed, empty refused, unchanged no-op). Debug script: rename by the File item (`menupress`), relaunch, `print` the sidebar shows the new name (AC1); ⌘Z / ⇧⌘Z (AC2). Manual: each of the three routes; Escape restores; clicking away saves |
| L6 | Remove from Library… ⌘⌫ (§6): enablement by key, confirmation, focus after removal, Activity on failure, cleared undo stack, announcement | `menuitems "Remove from Library…"` enabled in the grid with a selection, dimmed with the sidebar focused. `menukey` ⌘⌫ with the search field and with keyword entry focused: the text is deleted and no confirmation appears. Confirmation text checked by unit test of the composed strings for: one photo, several, one grouped pair (2 files), an ungrouped JPEG (2 files). Manual: Return in the confirmation does nothing; Escape cancels and nothing changes (AC7); Edit ▸ Undo is dimmed afterwards |
| L7 | Context menu items (§2.2, §2.3): Show in Finder after Export…; Remove from Library… last and alone; project row items | Debug script's context-menu probe on the grid, loupe and video loupe lists the items in order; Show in Finder absent for an offline photo. Manual right-click on a project row |
| L8 | Remove Project from Library… (§7) | `menuitems "Remove Project from Library…"` enabled with a project selected, dimmed with an album. Unit test of the composed confirmation (photos, pairs, project albums, empty project). After `menupress` and confirming, the sidebar selects All Photos |
| L9 | `docs/USER_GUIDE.md` (§11) | Reviewed at design review |

## 13. Requirements issues (for the product manager)

| RI | Issue | Design default (already in §2–§12) |
|---|---|---|
| RI-L1 | **A project's own albums and smart albums.** The catalog deletes them with their project (`album.projectId` and `smartAlbum.projectId` cascade). R6 says albums stay when photos are removed, and R8 applies "the same rule" to projects, but a project album would have no project to belong to. Should removing a project delete its albums and smart albums, or move them to the library's Albums? | Deleted with the project, and the confirmation says how many (§7.2 sentence 3). They exist to organize that project; moving them would leave empty albums with photos gone. If the ruling is "move", sentence 3 becomes "Its albums move to Albums." and the engineer moves them in the same transaction |
| RI-L2 | **R9's default button conflicts with the HIG.** R9 and AC7 say the default button is Cancel. HIG Alerts: "you don't want to make a Cancel button the default button. If you want to encourage people to read an alert and not just automatically press Return to dismiss it, avoid making any button the default button." Amend R9 and AC7 to: "No button is the default: Return does nothing; Escape and ⌘. cancel"? | No default button (§6.2). The PRD's intent, that Return never removes, holds either way |
| RI-L3 | **"One Finder window" (R14, AC11) holds only for files in one folder.** The Finder opens one window per folder it reveals, so a selection spanning 30 folders opens 30 windows. Is that acceptable, or should the command be limited (ask first above some number of folders, or reveal only the first folder)? | Reveal everything, no limit; AC11 tests one folder. Recommendation: no limit now, and a follow-up only if it bites |
| RI-L4 | **Which file an ungrouped pair reveals.** R14: "For a pair it reveals the RAW." With View ▸ Group RAW+JPEG Pairs off, the JPEG is its own cell; revealing the RAW when the person chose the JPEG cell would show them a file they didn't pick. Confirm that R14 means grouped pairs | A grouped cell reveals the RAW; an ungrouped cell reveals its own file (§5.1). Removal still takes both files (R7) |

## 14. Assumptions (stated, not raised)

- **A1.** "Offline" for Show in Finder is the state the app already shows
  (the Offline badge). Menu validation does no file-system work for photos;
  missing files are found when the command runs (§5.1).
- **A2.** Project names are trimmed of leading and trailing white space
  before saving. Inner white space is kept as typed.
- **A3.** A mixed selection with some offline photos reveals the online ones
  and reports the rest as information in Activity (§5.1). The PRD covers
  only "an offline photo".
- **A4.** Clearing the undo stack after a removal (§6.3) is acceptable under
  R10; the alternative, tracking which steps touch removed photos, adds
  complexity for steps that would mostly fail anyway.

## 15. Design questions from implementation

None yet. Rulings will be recorded here as D-L1, D-L2… for the engineer to
cite.
