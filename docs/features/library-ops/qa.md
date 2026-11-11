# Library operations: QA

Owner: qa-tester. Date: 2026-11-11. Step 4 of `docs/WORKFLOW.md`. Issue: #61.
Tested: `feature/library-ops` at `38b7f21`, on a Mac16,8 (M4 Pro), macOS 27.2 (26B123), macOS 27.2 SDK
(`vtool -show-build`: minos 15.0, sdk 27.2).

## Verdict

**Passes.** All thirteen criteria pass by test, script or both. What is left needs a key window,
a real key press, the Finder, VoiceOver, or macOS 15 and 26 (P1–P16). One low finding (Q1): I saw
it once and could not make it happen again. It does not block the branch.

`swift test`: 724 tests in 118 suites passed, with the 1 known issue (`LiveSessionTests`
"Values above white survive the cached stages"). "Library removal" (19) and "Library operations
rules" (12) passed. `Scripts/build-app.sh` built `build/Gus.app`.

How the app was run: I copied the bundle to the scratchpad, set its identifier to
`me.sesser.gus.debugtest` and signed it ad hoc. Every launch used `--library-root` on a scratch
library (two folders from `photobench generate`, "Wrong Card": 4 JPEG, 1 DNG, 2 RAW+JPEG pairs,
1 video; "Keep": 3 JPEG in two folders, imported with `photobench import`). Later runs added
folders A, B and New and a FAT32 disk image. Each run was the copy's executable with
`--debug-script "…; quit"`. An `open -W -n` launch with System Events by process ID did not
make the app active (`print responder`: `key nil`), so no run had a key window. After the runs no
test instance was running, and nothing in `~/Library/Application Support/Gus/Library` was newer
than the session's start. The owner's own app (`/Applications/Gus.app`, started 2026-11-10 16:44)
was running the whole time. I did not touch it.

C4 (code review): no script reads `undo` after cancelling a sheet that is not a removal.

## Acceptance criteria

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Test, Script | `LibraryRemovalTests.renamingAProject` (stored after reopening, duplicates), `LibraryOpsRuleTests.projectNameRule` (trim, empty refused, unchanged no-op). Scripts R1, R1b, R1d: File ▸ Rename's action, the row's context menu Rename, Return in the sidebar. Name kept after relaunch, empty refused with "The name can't be empty.", Escape keeps the old name, "   Iceland 2026  " stored as "Iceland 2026" beside another "Iceland 2026". The menu item itself needs a key window: P2 | Pass |
| AC2 | Script | R1: undo "Rename Project" restores "Wrong Card", redo gives "Iceland 2026" again (PhotoApp has no tests) | Pass |
| AC3 | Test, Script | `renamingAProjectTouchesNoFile`. R1: folders on disk still "Wrong Card" and "Keep", `sourcePath` unchanged, SHA-256 and mtime of all 15 files (2 `.xmp`) unchanged, `sidecarQueue` empty | Pass |
| AC4 | Test, Script | `removingAPhotoTakesItsRowsAndNothingElse`, `everyVersionOfTheMasterGoes`, `stackLinks`, `cascadesQueueNothing`. R2a and R4: IMG_00002 had a rating of 3, keyword "beach", two albums, an exposure edit with history, and a sidecar written. After Remove, `sqlite3` finds no row naming its image or version in version, albumMember, stack, stackMember, versionKeyword, imagePair, keywordSuggestion, metadataSync, sidecarQueue or editHistory. Keyword "beach" and both albums "Best" stay (empty). Its `.JPG` and `.xmp` keep their hash and mtime | Pass |
| AC5 | Test, Script | `removingOneFileOfAPairRemovesBoth` (either file), `bothHalvesChosen`, `photoConfirmation`. R3b: grouped pair "…2 files in all", ungrouped JPEG cell "Remove “PAIR_00006.JPG”…" "…2 files in all", 8 photos "10 files in all". R4: removing the ungrouped JPEG cell also removed PAIR_00006.DNG (no rows for either) | Pass |
| AC6 | Test, Script | `removingAProject`, `removingAnEmptyProject`, `removingAProjectTouchesNoFile`, `projectConfirmation`, `projectConfirmationFromPlan`. R5: "Wrong Card" had its own album and smart album. The confirmation says "Its 2 albums are deleted." ("Keep", with one: "Its 1 album is deleted."; R4's "Wrong Card" with none: no album sentence). After Remove there are no project, image or version rows for it and no own album or smart album. "Keep"'s own album (2) and the library album (1 left) stay, the keyword stays, files unchanged | Pass |
| AC7 | Script, Person | R3: Cancel has Escape and Remove has no key (destructive). `alert key return` leaves the sheet open. `alert key escape` and `alert press Cancel` close it with every photo still there and nothing in Activity. R4 and R9d: undo and redo are empty (`'-'`) after a removal. A synthetic ⌘. left the sheet open (no key window), so ⌘., macOS 15 and 26, and Edit ▸ Undo dimmed in the menu are P6 and P11 | Pass (⌘. Open: P6) |
| AC8 | Test, Script | `removingAnOfflinePhoto`. R7: with the disk image detached, an offline photo of "100QA" and the project "QACARD2" were removed with no message | Pass |
| AC9 | Test, Script | `reimportAfterRemovingAProject`, `reimportAfterRemovingPhotos`. R6: "Keep"'s IMG_00002 has the same content as the removed "Wrong Card" IMG_00002 and was skipped as a duplicate before the removal. After it, it imported ("Imported: 1"). "Wrong Card" imported again as 9 new files with new ids, no edit history and no keywords. IMG_00004's rating came back from its sidecar, as ruled (Requirements issue 2 in `status.md`) | Pass |
| AC10 | Test, Script | `aFailedRemovalChangesNothing`. R4 with `removal fail on`: Activity warnings "[Remove from Library] The photos couldn't be removed. The library is unchanged." and "[Remove Project from Library] The project couldn't be removed…", each with the SQLite error. Items, selection and the "Set Rating" undo step stay as before. With `removal fail off` the removal went through | Pass |
| AC11 | Test, Script, Person | `revealList`, `revealOutcome`. R3b: grouped pair reveals PAIR_00006.DNG, the ungrouped JPEG cell PAIR_00006.JPG, 8 photos in one folder give 1 folder, All Photos 3 folders. The Finder's windows: P4 | Pass (Finder: P4) |
| AC12 | Test, Script | `projectFolderRule`, `canReveal`, `projectVolumes`. R7: a project from a card's root is `nofolder` and one from its folder is `folder`. Detached: both `nofolder`. The offline photo has `showInFinder false showTargetsInFinder false` and no Show in Finder in its context menu. A project whose folder was moved away is `nofolder`, and one with no `sourcePath` is `nofolder` | Pass |
| AC13 | Script, Person | R8: grid cell menu "…Export…, Show in Finder, —, Remove from Library…". Loupe "…Export…, Show in Finder, —, zoom items, Show Original, Show Sharpening Map, Crop, —, Remove from Library…". Video "…Show in Finder, —, Play, Show Grid, —, Remove from Library…". R1c: project row "New Album in Project…, New Smart Album in Project…, —, Rename, Show in Finder, —, Remove Project from Library…". `menuitems`: File ▸ Show in Finder ⇧⌘R, Remove from Library… ⌘⌫, Remove Project from Library… (the ellipsis on both removals). View ▸ Show Original (`\`) is a separate title. `LibraryCommands.swift` gives the File order of design §2.1. Enabled states with a key window: P9 | Pass |

Also checked by script: the focus rule (D-L8, design §6.3, §7.3) in R9d (see P16).

## Findings

**Q1 (low; seen once, not reproduced). After a second folder add, the new project's Show in Finder
stayed off until relaunch.** In R6 I ran `addfolder …/src/Keep; waitimport; addfolder …/src/Wrong Card;
waitimport; print projects`. It printed `Wrong Card=7 nofolder`, though its `sourcePath` was set,
the folder existed, and the library has one volume ("Macintosh HD"). After a relaunch (R6b) the same
project was `folder`. I tried four times in the same library and three times in fresh libraries
with the same steps, and never saw it again.
Expected: `folder` once the import has ended. Actual (once): `nofolder` until the next refresh.
Steps 1 and 3 of `refreshProjectFolders` (`LibraryOpsActions.swift:132`) read `onlineVolumeIDs` and
`projectVolumeIDs()` at different times. A refresh can be left holding a volume set that is out of
date if no later reload follows it. For the engineer to look at, not to block on: the menu item
checks again when it runs, and a refresh also follows the app coming forward. Log:
`r6.log` (scratchpad).

No missing tests. AC2, AC7, AC13 and the Activity half of AC10 have no test because PhotoApp has
no test target, as the code review notes. Scripts cover them above.

Notes, not findings:

- `alert key cmd+.` on a removal's confirmation did not close it. The engineer saw the same.
  With no key window this proves nothing either way, so it is P6.
- The script's `album <name>` right after `selectall` once added no photos. That is the debug
  script, not the feature, so I added those album members with `sqlite3` instead (R5 setup).

## Scripts

Runner: the copy's executable, `--library-root <scratch>/lib --debug-script "<script>"`, output to
a log. The paths below are short; `$S` is the scratch folder. Folder state was compared with a
SHA-256 and mtime listing of `$S/src` before and after each run.

**R2a, setup** (sidecars on):
`wait 2; sidecars on; focus IMG_00002; key 3; addkeywords beach; album Best; focus IMG_00004; key 2; addkeywords beach; album Best; focus IMG_00002; loupe; wait 2; adjust exposure 0.5; wait 1; grid; wait 1; print keywords; print undo; wait 4; quit`
→ IMG_00002: rating 3, "beach", in two "Best" albums, an edit with 1 history entry. `.xmp` written
for IMG_00002 and IMG_00004.

**R1, rename** (AC1–AC3):
`wait 2; project 1; print projects; renameproject; print projects; text Iceland 2026; key return; print projects; print responder; print undo; undo; print projects; print undo; redo; print projects; print undo; project 0; renameproject; key escape; print projects; renameproject; key delete; key return; print announcement; print projects; print undo; renameproject; text    Iceland 2026  ; key return; print projects; print undo; sidebar album 0; key return; print projects; quit`
→ The field starts with `'Wrong Card' selected 0..<10`. Saved as "Iceland 2026", then `undo 'Rename
Project'`. Undo gives back "Wrong Card", redo "Iceland 2026". Escape keeps "Keep". Empty: "The name
can't be empty.", name kept. The padded name is stored trimmed as a duplicate. Return on an album
does nothing. Folders on disk unchanged. (A blank undo name after `key` or `text` is the script's
own empty group, not the app.)

**R1b, relaunch:** `wait 2; print projects; hit 100 100; …; quit` → `[Iceland 2026=2 folder, Iceland 2026=8 folder]`.

**R1c and R1d, the row's menu and Return:**
`wait 2; contextmenu at 100 480; contextmenu at 100 510; contextmenu at 100 540; …; quit` lists the
project row menu above.
`wait 2; project 0; contextmenu at 100 540 Rename; print projects; text Wrong Card; key return; print projects; print undo; project 0; sidebarfocus; key return; print projects; text Keep; key return; print projects; print undo; quit`
→ Rename from the menu of a row that is not selected starts on that row and the selection stays
`selected 0`. Return in the focused sidebar starts it. Both save with "Rename Project".

**R3, confirmation keys** (AC7):
`wait 2; pairs grouped; project 1; print items; focus PAIR_00006; print selection; print reveal; removephotos; print removal; alert; alert key return; alert; alert key cmd+.; alert; alert key escape; print removal; print items; print undo; removephotos; alert press Cancel; print removal; print items; pairs separate; wait 1; print items; quit`
→ `alert button 'Cancel' key escape` and `'Remove' key none destructive`. After Return: `open`.
After ⌘.: `open`. After Escape: `closed`, `removal can start true … asking false`, items unchanged,
`undo '-'`. Cancel: the same.

**R3b, pairs and Show in Finder** (AC5, AC11):
`wait 2; print projects; pairs grouped; project 1; wait 1; print title; print items; focus PAIR_00006; print selection; print reveal; removephotos; alert; alert press Cancel; selectall; print selection; print reveal; removephotos; alert; alert press Cancel; pairs separate; wait 1; print items; focus 6; print selection; print reveal; removephotos; alert; alert press Cancel; project all; wait 1; selectall; print reveal; quit`
→ `reveal [PAIR_00006.DNG] folders 1`; "Remove “PAIR_00006.DNG” from the library?" with "Both files
of each RAW+JPEG pair are removed, 2 files in all." For 8 photos: 8 files revealed, `folders 1`,
"Remove 8 photos…", "10 files in all". Ungrouped JPEG cell: `reveal [PAIR_00006.JPG]`, "2 files in
all". All Photos: `folders 3`.

**R4, failure, then removals** (AC4, AC5, AC7, AC10):
`wait 2; pairs grouped; project 1; wait 1; print items; focus IMG_00004; key 1; print undo; removal fail on; focus IMG_00002; removephotos; alert press Remove; print messages; print items; print selection; print undo; removeproject; alert; alert press Remove; print messages; print projects; print undo; removal fail off; focus IMG_00002; removephotos; alert; alert press Remove; print items; print selection; print undo; print announcement; print keywords; print removal; pairs separate; wait 1; print items; focus 5; print selection; removephotos; alert press Remove; print items; print undo; pairs grouped; wait 1; print projects; quit`
→ Both failures: one warning each, items and `undo 'Set Rating'` unchanged. Then IMG_00002 is
removed: `undo '-'`, "Removed “IMG_00002.JPG” from the library.", `keywords beach=0`. The
ungrouped PAIR_00006 JPEG cell is removed and both PAIR_00006 cells are gone. The catalog checks
for AC4 and AC5 are above. Only IMG_00004.xmp changed, by its own new rating (sidecars on).

**R5, project with its own albums** (AC6). Setup: albums made by script, then `sqlite3` set
`projectId` ("Own" and "Own smart" to "Wrong Card", "KeepOwn" to "Keep") and added members.
`wait 2; project 0; wait 1; removeproject; alert; alert press Cancel; project 1; wait 1; removeproject; alert; alert press Remove; print projects; print title; print undo; print announcement; print responder; quit`
→ The texts are quoted in AC6. Then `projects [Keep=2 folder]`, title "All Photos", `undo '-'`,
"Removed the project “Wrong Card” from the library." `sqlite3`: albums
`Best=0,Best=0,KeepOwn=2,Library=1`, no smart album, keyword kept, queue empty. Files unchanged.

**R6, importing again** (AC9):
`wait 2; addfolder $S/src/Keep; waitimport; addfolder $S/src/Wrong Card; waitimport; print projects; project all; wait 1; print items; quit`
→ "Imported: 1. Already in the library: 2." then "Imported: 9. Already in the library: 1." The
`sqlite3` check is in AC9. This run also showed Q1.

**R7, offline, mount point, missing and no folder** (AC8, AC12). A FAT32 image `QACARD2`,
imported from `DCIM/100QA` and from its root, then detached. `src/New` was moved away, and
project A's `sourcePath` was set to NULL:
`wait 3; print projects; project 1; wait 1; print title; print items; focus 0; print menustate; print reveal; contextmenu cell 0; project all; wait 1; selectall; print reveal; project 1; wait 1; focus 0; removephotos; alert; alert press Remove; print items; print projects; project 0; wait 1; removeproject; alert; alert press Remove; print projects; print messages; quit`
→ `QACARD2 nofolder, 100QA nofolder, A nofolder, New nofolder`, the others `folder`. Before the
detach: `QACARD2=2 nofolder, 100QA=2 folder`. The offline photo: `showInFinder false
showTargetsInFinder false`; `reveal [] … offline 1 | 1 photo wasn't shown because its original
is offline.`; no Show in Finder in its menu. All Photos: "10 photos weren't shown because their
originals are offline or missing." Both offline removals went through.

**R8, menus** (AC13):
`wait 2; project 1; wait 1; print title; contextmenu cell 0; focus IMG_00001; loupe; wait 2; contextmenu loupe; grid; wait 1; focus MVI_00008; loupe; wait 2; contextmenu video; grid; wait 1; menuitems Finder; menuitems Library; menuitems Original; menuitems Rename; menuitems Delete; menuitems Export; menuitems Stop; menuitems Check for; print menustate; sidebarfocus; print menustate; sidebar album 0; print menustate; quit`
→ The menus are listed in AC13. `menustate`: with the sidebar focused on a project,
`sidebarKeys true showInFinder true`. On an album, `showInFinder false`. Every item is
`disabled` because there is no key window.

**Activation attempt:** `open -W -n --stdout <log> <copy> --args --library-root $S/lib --debug-script "wait 8; print responder; …; quit"`.
Then `pgrep -n -x Gus` (checked to be the copy's path) and System Events `set frontmost … unix id
<pid>` → `key nil`. I did not retry.

**R9d, focus** (D-L8 / M15, §6.3):
`wait 2; project all; wait 1; focus IMG_00009; loupe; wait 2; print selection; print title; contextmenu at 100 600 Remove Project from Library…; alert; alert press Remove; print projects; print selection; print title; removephotos; alert press Remove; print projects; print selection; print title; print announcement; print undo; quit`
→ The loupe was on B's IMG_00009 (focus 16). Removing project "New" from its row left it on
IMG_00009 (focus 11). Removing IMG_00009, now the last photo, moved the loupe to the previous one
(IMG_00008). Earlier, R9 removed the project that held the focused photo, and the focus moved to
the photo that followed.

## For a person

Run the bundle with `--library-root` on a scratch library, with the app frontmost. You need a
project imported from a folder, one imported from a card's root, a RAW+JPEG pair, a video, an
album and a smart album in a project, and a disk image you can detach. "Eng" is `status.md`'s
list, "Des" is `review.md`'s.

- **P1. The rename field's look** (Eng M1, Des M1). Same font and place as the name. The folder
  symbol and count badge stay. The row keeps its height and the whole name is selected. Afterwards
  the row's tooltip still shows the folder's path with its old name.
- **P2. Rename by menu, mouse and keys** (Eng M3, Des M2). File ▸ shows "Rename “‹name›”" with no
  ellipsis, enabled, for a selected project. Try it from there, from the row's menu, and with Return
  on the row. In each: Return saves, Escape restores, Tab saves, and clicking a photo in the grid
  saves while the grid gets the click. After Return or Escape the sidebar selection is in the accent
  color. Edit ▸ shows "Undo Rename Project".
- **P3. Empty name** (Eng M10, Des M3). Delete the whole name and press Return. The alert sound
  plays, the old name comes back, and Edit ▸ Undo adds no rename step.
- **P4. Show in Finder for photos** (Eng M2, Des M4). Three photos from one folder, ⇧⌘R: one Finder
  window with the three selected. Photos from two folders: two windows. A grouped pair selects the
  RAW. Pairs ungrouped, the JPEG cell selects the JPEG. Disk image detached, only its photos
  selected: File ▸ Show in Finder is dimmed. A mix: the online files open and Activity shows one
  information row.
- **P5. Show in Finder for projects** (Eng M2, Des M5). Click a project row, ⇧⌘R: its folder is
  selected in its parent. On an album row the item is dimmed. Click a photo in the grid with the
  project still selected: ⇧⌘R reveals the photo. The card-root project has no Show in Finder in its
  row menu and the File item is dimmed for it.
- **P6. Confirmation keys, on macOS 27** (Eng M4, Des M6, keys). In both confirmations:
  Return does nothing, Escape cancels, ⌘. cancels. Start an export, open a confirmation and press
  ⌘.: the confirmation closes and the export keeps running. If Return removes, design §6.2's
  `NSAlert` fallback applies. The owner is not asked to test macOS 26 and 15 (owner's rule,
  2026-11-11). That part stays open in #82; see below.
- **P7. The confirmation's look** (Eng M9, Des M6, look). The title is shown, Remove is red, the app
  icon (no caution triangle), no "Don't ask again" box.
- **P8. ⌘⌫ in text fields** (Eng M6, Des M7). Press ⌘⌫ in the toolbar search, the ⌘K keyword field,
  an Info tab field (Title) and the project rename field. Each deletes text before the insertion
  point and no confirmation appears. With the sidebar focused on a row, ⌘⌫ does nothing and File ▸
  Remove from Library… is dimmed.
- **P9. File menu states** (Eng M5, Des M8). Project selected: Rename “‹name›” enabled, Delete…
  dimmed, Remove Project from Library… enabled. Album selected: Remove Project from Library… dimmed,
  "Delete “‹name›”…" enabled. Grid focused with a selection: Remove from Library… ⌘⌫ enabled; with
  none, dimmed. Only offline photos selected: Show in Finder dimmed.
- **P10. Dimmed while busy** (Eng M7, Des M9). While a confirmation is up, the library's File items
  are dimmed. While a folder add or a card import runs, both Remove items are dimmed in the File menu
  and missing from the photo and project-row menus. They come back when it ends.
- **P11. After a photo removal** (Des M10). Edit ▸ Undo is dimmed in the menu (the script showed an
  empty undo stack). Remove every photo of a project from the loupe: the window goes back to the grid
  with the project's empty state.
- **P12. Removed: VoiceOver** (Eng M8, Des M11). Not asked of a person, by the owner's rule
  (2026-11-11): VoiceOver checks are never listed for a person. The script confirmed the
  announcement texts ("Removed “IMG_00002.JPG” from the library.", "Removed the project “Wrong
  Card” from the library.", "The name can't be empty.") through `print announcement`. Whether
  VoiceOver speaks them is not checked.
- **P13. Project removal and the selection** (Des M12). Remove the selected project with the sidebar
  focused: All Photos is selected and the sidebar keeps the keyboard. Remove a project that is not
  selected from its row: the selection stays. Remove a project while one of its albums is selected:
  All Photos is selected.
- **P14. The sidebar menu's look** (Des M13). Remove Project from Library… is last, after a separator,
  styled like the album rows' Delete… items.
- **P15. Activity during a long removal** (Des M14). Remove a few thousand photos. Activity shows
  "Remove from Library" with "Removing ‹N› photos…" under it, indeterminate, with no Stop button.
  File ▸ Stop does not name it.
- **P16. Focus kept when the focused photo is not removed** (Des M15). Script R9d covers this; a
  person needs only to look. All Photos, the loupe on a photo of project A. Remove project B from its
  row: the loupe stays on the same photo, and back in the grid that cell has the focus. Press ⌘⌫ and
  confirm: the loupe moves to the photo after it.

### For issue #82 (standing manual checks)

Only one: **macOS 15 and 26**. On those systems the confirmations' keys (P6: Return does nothing,
Escape and ⌘. cancel) and the feature's look are untested by a person. The README says they should
work in theory. Suggested line: "library-ops (`docs/features/library-ops/qa.md`): macOS 15 and 26
not checked by a person (confirmation keys, P6, and look)." VoiceOver (former P12) is not listed,
by the owner's rule.

## Follow-up

**Sign-off.** The owner signed off on `feature/library-ops` at `38b7f21` on 2026-11-11, relayed by
the main session.

- Done by the owner: P1–P5, P6 on macOS 27, and P7–P11 and P13–P16.
- Left open:
  - The macOS 15 and 26 parts of P6, and the feature's look on those systems. These stay in #82
    as above.
  - VoiceOver (P12). Not asked of a person under the owner's standing rule (2026-11-11), so it
    is not carried to #82.
- Q1 (low, not reproduced): no fix recorded. The sign-off was given with it open. Whether it
  becomes an issue is the main session's call.
