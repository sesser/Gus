Issue: #61

# Library operations: status

Owner: swift-macos-engineer. Branch: `feature/library-ops`. State: **Done** (2026-11-10).
Nothing is blocked. The findings of the code review and the design review are fixed
(**Review findings**); they go back to code-reviewer and the designer for the second pass,
then qa-tester. The code review's questions Q1–Q3 are ruled; Q1 is built.

Spec: [`prd.md`](prd.md) (R1–R18, AC1–AC13), [`design.md`](design.md) (§12 L1–L9).
The implementation is commit `fd00a1f`, the first rulings and the review fixes `bef0feb`,
the rulings on Q1–Q3 and the focus change the commit after that.

## Results

| | Baseline (`87258a8`) | Now |
|---|---|---|
| `swift build` | clean, no warnings | clean, no warnings |
| `swift test` | 693 tests in 116 suites passed, 1 known issue | 724 tests in 118 suites passed, the same 1 known issue |
| `Scripts/build-app.sh all` | not run | both bundles built |

New suites: `LibraryRemovalTests` (19 tests) and `LibraryOpsRuleTests` (12). Two existing
tests call `removeProject` in place of `deleteProject`, which is gone (one way to remove a
project, and it clears the sidecar queue).

## What was built

- **PhotoCore** (no AppKit or SwiftUI, all tested):
  - `Catalog/LibraryRemoval.swift`: `photoRemovalPlan`, `removePhotos`, `projectRemovalPlan`,
    `removeProject`.
  - `Catalog/ProjectRename.swift`: the name rule (trim, refuse empty, unchanged is a no-op).
  - `Browser/FinderReveal.swift`: which file each target reveals, what is left out
    (`FinderReveal`), and whether a project has a folder to reveal (`ProjectFolder`).
  - `Browser/RemovalConfirmation.swift`: what each confirmation says, in order
    (`RemovalConfirmation`); when a removal may start (`RemovalAvailability`); the focus
    after one (`RemovalFocus`).
  - `Catalog.projectVolumeIDs()`; `Catalog.saveSync` skips a master that is gone;
    `SidecarSync.pauseQueue` / `resumeQueue`: a queue run ends after the file it is on.
- **PhotoApp**: `Model/LibraryOpsActions.swift` (the three commands and their words),
  `LibraryMenuState` and `LibraryCommands` (File menu), `PhotoContextMenu`, `SidebarView`
  (in-place rename, project row menu), `MainView` (the confirmation), `ActivityToolbarItem`
  (the removal job), `LibraryWindowObserver` (the sidebar has the keyboard).
- **PhotoUI**: `WindowReader` is public (the rename field uses it); 26 String Catalog keys.
- **Debug script**: `alert`, `renameproject`, `removephotos`, `removeproject`,
  `sidebarfocus`, `removal fail on|off`, `print projects|reveal|removal`; `print menustate`
  gained the new fields; `key` knows `delete`, `tab`, `r`, `.` (`Model/DebugLibraryOpsCommands.swift`).
- **`docs/USER_GUIDE.md`**: two rows in the key table and four paragraphs (design §11).

## The PRD's questions for the engineer

**Is removal one transaction (R13)?** Yes. `removePhotos` and `removeProject` each run in one
`database.write`, which GRDB wraps in one SQLite transaction. The masters are deleted and the
schema's cascades take versions, edit history, keyword links, album memberships, stack
members, pair links, suggestions and `metadataSync`. `aFailedRemovalChangesNothing` makes
the removal's second statement fail after the masters are deleted and checks every table's
row count is as before. Removing a project with 29,989 photos took 0.7 s in the app.

**How are pending `sidecarQueue` entries dropped?** `sidecarQueue` has no foreign key, so
nothing cascades to it: `removeImages` deletes the entries of the removed masters itself,
in the same transaction, after the masters. Deleting keyword links by cascade fires the
`sidecar_keyword_removed` trigger, but the version is already gone when it looks, so
nothing is queued again (checked in SQLite and in `cascadesQueueNothing`); the explicit
delete does not depend on that. Around the transaction the app stops sidecar writing: a run
in flight is paused and waited for, and none writes until the removal has ended
(`pauseSidecarSync`), so no sidecar is written for a photo while or after it is removed.
A change made in the last second and a half before a removal (still queued) therefore never
reaches the sidecar, as R6 says.

## Acceptance criteria

"Script" is a debug-script run against a copy of the bundle (identifier
`me.sesser.gus.debugtest`) on a scratch library; see **Debug-script results**.

| AC | Test | Script | Left for a person |
|---|---|---|---|
| AC1 | `renamingAProject` (stored after reopening; duplicate names), `projectNameRule` (empty kept out) | D, E: File ▸ Rename's action, the row's context menu, Return in the sidebar; name kept after relaunch; empty refused; duplicate saved | M1, M3 |
| AC2 | — | D: undo "Rename Project" restores, redo reapplies | |
| AC3 | `renamingAProjectTouchesNoFile` | D: folder on disk keeps its name, `sourcePath` unchanged | |
| AC4 | `removingAPhotoTakesItsRowsAndNothingElse`, `everyVersionOfTheMasterGoes`, `stackLinks`, `cascadesQueueNothing` | B: no rows left, keyword and album stay, files' hashes and dates unchanged | |
| AC5 | `removingOneFileOfAPairRemovesBoth`, `bothHalvesChosen`, `photoConfirmation` | C: "2 files in all" for a grouped pair and for an ungrouped JPEG; both files gone | |
| AC6 | `removingAProject`, `removingAnEmptyProject`, `removingAProjectTouchesNoFile`, `projectConfirmation`, `projectConfirmationFromPlan` | F: own albums gone, the library's album kept, "Its 2 albums are deleted." only with albums | |
| AC7 | — | A: Remove has no key equivalent, Cancel has Escape; Return leaves it open; Escape and Cancel change nothing. B: Edit ▸ Undo empty after | M4 (⌘., macOS 15 and 26) |
| AC8 | `removingAnOfflinePhoto` | I: a photo and a project on a detached disk image removed | |
| AC9 | `reimportAfterRemovingAProject`, `reimportAfterRemovingPhotos` | — | |
| AC10 | `aFailedRemovalChangesNothing` | G: warning in Activity with the error, nothing changed, undo kept | |
| AC11 | `revealList`, `revealOutcome` | C: the files for one folder, three folders, a grouped pair (RAW), an ungrouped JPEG | M2 (the Finder's windows) |
| AC12 | `projectFolderRule`, `canReveal`, `projectVolumes` | I: dimmed for offline photos, for a project at a mount point, and for one on a detached volume | M2 |
| AC13 | — | H: File menu order and keys; grid, loupe, video loupe and project row menus | M5 (enabled states) |

Also tested: `savingSyncForARemovedMaster`, `pausedQueueRunStopsAfterItsFile`, `focusAfterRemoval`
(design §6.3), `focusSurvivesARemovalElsewhere` (§7.3, Q1), and for design §8 `removalAvailability`, `importIntoARemovedProjectFails`
and `batchEditAfterARemoval`.

## Design §12

| # | State | Check |
|---|---|---|
| L1 | Done | `print menustate`: `sidebarItem project …`, `sidebarKeys`, `showInFinder`. Titles and enabled states with a key window: M5 |
| L2 | Done | H: `menuitems` lists File in §2.1's order, with the separators |
| L3 | Done | `revealList`, `revealOutcome`, `canReveal`; C and I |
| L4 | Done | `projectFolderRule`; I |
| L5 | Done | `projectNameRule`; D, E, M |
| L6 | Done | `photoConfirmation`; A, B, C, J. ⌘⌫ in text fields: M6 |
| L7 | Done | H, K |
| L8 | Done | `projectConfirmation`; F |
| L9 | Done | `docs/USER_GUIDE.md` |

## Debug-script results

On macOS 27.2 this session. **macOS would not bring the test copy forward** (`open`, System
Events by process id, and `NSApp.activate` all left `print responder` at `key nil`), so no
run had a key window. Everything that needs one is under **For a person**: every library
menu item is dimmed without it, `menupress` and `menukey` do nothing, and a real ⌘. or ⌘⌫
cannot be sent. The scripts drive the commands' own entry points instead (`renameproject`,
`removephotos`, `removeproject`), which is what the menu items call.

Library: two projects from `photobench generate`, "Wrong Card" (4 JPEG, 1 DNG, 2 RAW+JPEG
pairs, 1 video: 8 photos, 10 files) and "Keep" (3 JPEG in two folders).

- **A, confirmation keys.** `removephotos; alert; alert key return; alert key escape`:
  buttons `Cancel` (key escape) and `Remove` (no key, destructive); Return left it open;
  Escape closed it with every photo still there, no message, no undo step. `alert press
  Cancel` the same.
- **B, one photo.** Rating, a keyword, an album and an exposure edit on IMG_00002, then
  Remove: 7 photos, focus on the photo that followed, `undo '-'`, announcement "Removed
  “IMG_00002.JPG” from the library.", album "Best" kept with 0, keyword kept; catalog rows
  for edit history, keyword links, album members and the sidecar queue all 0; SHA-256 and
  modification dates of the ten files unchanged.
- **C, pairs and Show in Finder.** Grouped pair showing its JPEG: `print reveal` gives
  PAIR_00006.DNG; title "Remove “PAIR_00006.JPG” from the library?" with "Both files of each
  RAW+JPEG pair are removed, 2 files in all." Eight selected: "Remove 8 photos…", "10 files
  in all". Ungrouped JPEG cell: reveals PAIR_00006.JPG, removal takes the DNG too. All
  Photos selected: 11 files in 3 folders.
- **D, rename.** `renameproject`: the field has the keyboard with the name selected
  (`selected 0..<10`); typing and Return saves; the sidebar's list has the keyboard after;
  undo and redo; after a relaunch the name is kept; the folder on disk is still "Wrong Card".
- **E, rename edges.** Return in the sidebar starts it; Escape keeps the old name; an empty
  name is refused with "The name can't be empty."; "   Keep  " saves "Keep" beside another
  "Keep"; Return on an album does nothing.
- **F, project.** Empty project: "It has no photos. The folder stays on disk, unchanged."
  "Wrong Card" with an album and a smart album of its own: "Its 8 photos are removed with
  it. Both files of each RAW+JPEG pair are removed, 10 files in all. Its 2 albums are
  deleted. …"; after Remove the sidebar selects All Photos and keeps the keyboard, the
  library's album stays with 3, files unchanged.
- **G, failure.** `removal fail on`: Activity warning "[Remove from Library] The photos
  couldn't be removed. The library is unchanged." with the SQLite error under it; 8 photos,
  the selection and the "Set Rating" undo step as before; the same for the project. With
  the failure off the removal goes through.
- **H, menus.** Grid: … Export…, Show in Finder, —, Remove from Library… Loupe: … Export…,
  Show in Finder, —, zoom items, Crop, —, Remove from Library… Video: Show in Finder, —,
  Play, Show Grid, —, Remove from Library… File: Rename…, Delete…, Remove Project from
  Library…, —, Show in Finder ⇧⌘R, Export… ⇧⌘E, Remove from Library… ⌘⌫, —, Check for
  Changes on Disk, Stop ⌘.
- **I, offline and mount points** (a FAT32 disk image). A project imported from the
  volume's root has no folder to reveal; one from a folder on it has. After detaching:
  both have none; an offline photo has `showTargetsInFinder false` and no Show in Finder in
  its menu; a mixed selection reveals the online files and Activity says "4 photos weren't
  shown because their originals are offline."; the offline photo and project are removed.
- **J, loupe.** With a crop open on the photo: after Remove the loupe shows the previous
  photo (the last one was removed), no crop, no undo step. Removing the rest: back to the
  grid, "No Photos in “Keep”".
- **K, project row menu.** New Album in Project…, New Smart Album in Project…, —, Rename,
  Show in Finder, —, Remove Project from Library… Rename and Remove run from a row that is
  not selected; the selection stays.
- **L, row out of view.** 62 projects, the last selected, Projects hidden and collapsed:
  `renameproject` shows the section, scrolls to the row (`sidebar shows 1257..<2387 of
  2397`) and the field takes the keyboard.
- **N, beside an import.** While a folder of 3,000 photos is added: `removal can start
  false`, no Remove from Library… in the cell's menu, `removephotos` asks nothing. After
  it: both back.
- **Large.** 30,000 photos removed in one go: 0.7 s, Activity job "Remove from Library"
  / "Removing 30,000 photos…" (after F1). A project of 29,989: 0.7 s, "Remove Project from
  Library" / "Removing 29,989 photos…".
- **After the review fixes** (second commit). `alert press Delete` on "Delete the album
  “Test”?": the album goes, undo "Delete Album" brings it back, no crash (C2); a removal's
  confirmation after it still clears the stack. With sidecar writing on: three photos
  rated and one of them removed at once: sidecars written for the other two only, the queue
  empty, nothing flagged as changed on disk.

## For a person (not checked by me)

- **M1.** The rename field's look: same font and place as the name, folder symbol and
  count stay, row keeps its height; the row's tooltip still shows the folder path.
- **M2.** Show in Finder in the Finder: three photos of one folder open one window with
  three files selected; several folders, one window each; a project's folder selected in
  its parent. With the sidebar focused on a project ⇧⌘R opens its folder; on an album the
  item is dimmed.
- **M3.** Rename by mouse and keys: File ▸ Rename “‹name›” (no ellipsis) enabled with a
  project selected; clicking in the grid while renaming saves; Tab saves.
- **M4.** In both confirmations: Return does nothing, Escape cancels, **⌘. cancels** (I
  could not send a real ⌘.; a synthetic one sent to the sheet did not close it, which a
  window that is not key may explain). **On macOS 15 and 26: Return does nothing.** If
  either fails, design §6.2's fallback applies (an `NSAlert` with Remove's key equivalent
  cleared), and ⌘. would get a key handler there.
- **M5.** With a key window: `menuitems Rename` shows "Rename “‹name›”" enabled and
  `menuitems Delete` "Delete…" dimmed for a project; Remove Project from Library… enabled
  for a project and dimmed for an album; Remove from Library… enabled in the grid with a
  selection, dimmed with the sidebar focused; Show in Finder dimmed with only offline
  photos selected.
- **M6.** ⌘⌫ typed in the search field and in the ⌘K keyword field deletes text and no
  confirmation appears (`menukey cmd+delete`); with the sidebar focused it does nothing.
- **M7.** Both Remove items are dimmed in the File menu while a folder add or a card
  import runs (script N covers the rule and the context menu, not the menu bar).
- **M8.** VoiceOver: the confirmation is read in full; the announcements after a removal
  and after a refused empty name; the rename field is "Project name".
- **M9.** The confirmation's look: Remove red, the app icon, no caution symbol.
- **M10.** An empty name plays the alert sound.

## Decisions within the spec

- **The confirmation is SwiftUI's `confirmationDialog`**, as design §6.2 asks, like the
  app's other deletions. On macOS 27.2 it gives Remove no key equivalent and Cancel
  Escape, with or without my code (the existing "Delete the album" dialog is the same), so
  the one reason the design allows for `NSAlert` did not arise here. macOS 15 and 26 are
  M4.
- **Design §8, running jobs.** §8 dims the Remove items beside a job a removal can't run
  safely with. That is the two imports: a folder add or a card import fails with a
  foreign-key error if its project is removed under it (`importIntoARemovedProjectFails`).
  It is not an export, which works from the rows and keywords it read when it started and
  then only reads files, and not a batch measurement (Auto Exposure, a paste that
  measures), whose final write changes only the photos still there
  (`batchEditAfterARemoval`). So both Remove items are off, and left out of the context
  menus, while an import runs, and only then. See Design question 1.
- **Which projects can be revealed** is worked out for all projects off the main actor
  when projects or volumes change and when the app comes forward, and menus read the
  result. Design §5.2 asks for one check when the context menu is built; SwiftUI builds a
  row's context menu with the row, not on the right-click, so a check there would run for
  every row on every update. The folder is checked again when the command runs.
- **"Its volume is mounted"** is taken from the volumes of the project's own photos, not
  from the path, so another card mounted at an offline card's path is not taken for it.
- **A stack that loses every member is deleted; one that keeps a member stays.** Stacks
  have no UI yet.
- **`deleteProject` is replaced by `removeProject`**, which also clears the sidecar queue.

## Known limits

- An import started while a removal is being confirmed or is running is not blocked. If it
  copies into the project being removed, the import fails with an error; nothing is lost.
- A project's folder is its absolute `sourcePath`. If its volume is mounted somewhere else
  than at import, Show in Finder is dimmed for the project (its photos are still found).
- Cached previews of removed photos stay in the Caches folder (they are keyed by content,
  and a re-import reuses the unedited ones). Ruled: left as is; purging them is issue #142.
- `importRun` rows of a removed project stay, pointing at no project; Last Import falls
  back to the newest run that still has photos.

## Questions and rulings

Returned in my report on 2026-11-10. The owner ruled the same day, relayed by the main
session: "defaults are fine" for every one, so each stays as built except Design question
2. Nothing is open. The designer and the product manager have not yet recorded these in
`design.md` §15 and `prd.md`; that is theirs to do.

Design questions:

| # | Question | Ruling |
|---|---|---|
| 1 | Which jobs keep a removal from starting (§8) | As built: the two imports only. Exports and batch measurements do not block one, and an import started during a removal is not blocked |
| 2 | Activity job titles | **The command's title with the count under it, for photos and projects alike** (D-L2 in `review.md`). Done: O1 under **Review findings** |
| 3 | The message's sentences joined in one paragraph | As built |
| 4 | "The folder …" in the project confirmation when the project has no source folder, or photos in several | As built |
| 5 | Rename from the menu of a row that is not selected | As built: the selection is left alone |
| 6 | The destructive role on the sidebar's Remove Project from Library… | Kept; the photo menus' item stays plain |
| 7 | Show in Finder on a project whose folder has just gone | As built: nothing opens and the item dims, with no message |
| 8 | A folder deleted in the Finder is noticed when the app comes forward, not at once | As built |

Requirements issues:

| # | Issue | Ruling |
|---|---|---|
| 1 | Cached previews of removed photos stay in the Caches folder | Left as is on this branch. Purging them is follow-up issue #142 |
| 2 | R12 and sidecars: what was written to a sidecar before the removal comes back at re-import; a change still queued does not | Intended. The user guide's wording stays |
| 3 | A project's folder is its absolute `sourcePath`, so Show in Finder is dimmed for a project whose volume is mounted at another path | Accepted |

## README

No change to requirements, build commands or the repository layout. For the feature list:
rename a project in place; Show in Finder (⇧⌘R) for photos and projects; Remove from
Library… (⌘⌫) and Remove Project from Library…, which change the catalog only.

## Review findings

From [`code-review.md`](code-review.md) (C) and [`review.md`](review.md) (F, I), 2026-11-10.
After the fixes (`bef0feb`): `swift build` clean, `swift test` 723 tests in 118 suites
passed with the same known issue, `Scripts/build-app.sh all` built both.

| # | Finding | State |
|---|---|---|
| O1 = C3 = F1 | A photo removal's Activity job is titled with its count, not the command | **Fixed.** `RemovalJob(title: removeFromLibrary, detail: removing(count))`; the catalog comments on "Remove from Library" and "Removing %lld photos…" say so. Script: `removal ran 0.7 s, Activity job 'Remove from Library' detail 'Removing 30,000 photos…'` |
| C1 | `cancelledQueueRunStops` passed without the change it was named for | **Fixed, and the code under it changed.** Writing the test the reviewer asked for showed the stop itself was wrong: a cancelled task's catalog writes throw, so a run cancelled mid-file kept the file it had just written on the queue, and could end between writing a sidecar and recording it (the next run could then take the app's own file for another app's change). A removal now pauses the queue instead of cancelling the run: `SidecarSync.pauseQueue()` makes a run in flight end after its file, recorded and dequeued, and `resumeQueue()` lets the rest go. The task is cancelled only while it is still waiting to start a run. `pausedQueueRunStopsAfterItsFile` pauses from inside the run, when the first file's state is recorded (a SQL function on the catalog's write, no timing), and checks one sidecar written, recorded and dequeued, the other unwritten and queued, nothing written while paused, the rest written after `resumeQueue`. With the stop between files taken out it fails (4 expectations) |
| C2 | `alert press` / `alert key` answer any sheet with no undo group | **Fixed.** They open an undo group around the answer unless the sheet is a removal's confirmation (`pendingRemoval != nil`), which registers nothing and clears the stack. `alert` is not in `changing`. Script: `alert press Delete` on an album's confirmation, then undo |
| F2 | The user guide's Undo paragraph does not list project renames | **Fixed**, and it now says a removal cannot be undone |
| I1 | The guide says only "dimmed" for Remove during an import | **Taken**: "dimmed, and left out of the context menus", for both Remove commands |
| I2 | "Project name" is one key for two uses | Left, as the review says: until a localization asks |
| I3 | A rename field that never gets the keyboard would stay a field | Left: script L shows the guard works; the review's remedy is for M2 failing |

### The code review's questions

Ruled by the owner on 2026-11-11, relayed by the main session: the reviewer's
recommendation for each. The designer and the product manager have not recorded them in
`design.md` and `prd.md` yet.

| # | Question | Ruling | State |
|---|---|---|---|
| Q1 | Which photo has the focus after a removal that did not take the focused one (a project removed from its row's menu while another source is on screen) | **The focused photo keeps the focus when it was not removed.** §6.3's rule applies only when it was | **Built.** `RemovalFocus.index(count:focus:isRemoved:)` returns the focus when the removal left it; `removalDidFinish` passes `focusIndex`. Test `focusSurvivesARemovalElsewhere`; `focusAfterRemoval` still covers a removed focus. Script: All Photos, the loupe on MVI_00008 of "Wrong Card" (index 7), Remove Project from Library… on "Keep" from its row: the loupe stays on MVI_00008 (now index 4); removing a photo still moves to the one after it |
| Q2 | Smart albums of the library or another project whose rule names a removed project | Left as is: the rule stays and matches nothing ("is") or everything ("is not"), as a rule on a deleted keyword does | No change. Follow-up issue #143 (`smart-album-removed-project`) |
| Q3 | Show in Finder for a project made by a copying import reveals the copy destination, the same folder for every such project | Accepted: R15 says "its source folder when `sourcePath` is set" | No change. Follow-up issue #144 (`project-reveal-copy-destination`) |

After this change: `swift build` clean, `swift test` 724 tests in 118 suites passed with
the same known issue, `Scripts/build-app.sh all` built both. It changes `Sources/` and
tests after the reviews, so it takes code-reviewer's second pass with `bef0feb`; the
designer's too, since it changes where the focus lands.
