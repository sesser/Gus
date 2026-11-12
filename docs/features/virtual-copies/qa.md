Issue: #62

# Virtual copies: QA

Owner: qa-tester. Date: 2026-11-11. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/virtual-copies` at `6cb318a` (source as of `18af935`), on a Mac16,8 with macOS 27.2.1 (26B131), the macOS 27.2 SDK (bundle `vtool -show-build`: sdk 27.2), and Swift 6.4.2.

## Verdict

**Passes.** All nine criteria pass: each has a test that fails without the behavior, and seven are also shown in the bundled app by script. AC7 is scoped as P2 scopes it. There is one minor finding, Q1, which is the code reviewer's C4, now reproduced in the app. It loses no data but drops the undo stack. It does not block sign-off unless the owner wants it fixed on this branch. P1, P2 and P3 (PRD) are pending the owner.

`swift test`: 758 tests in 119 suites passed, with 1 known issue (`LiveSessionTests` "Values above white survive the cached stages", the same as the baseline). `VirtualCopiesTests`, `SidecarSyncTests` and `LibraryRemovalTests` also pass when run alone (60 tests). `Scripts/build-app.sh` built the bundle.

## Acceptance criteria

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1: one more version with an equal stack; undo removes it, redo restores it | Test, Script | `VirtualCopiesTests.duplicateAddsAVersionWithAnEqualStack`, `undoRemovesAndRedoRestoresTheSameCopy`, `removeCopiesLeavesOriginals`, `aBatchIsAllOrNothing`. Scripts S1, S2: 15 → 16 items; undo name `Duplicate`; after undo 16 → 15 with the original focused; redo puts back the same row (catalog id 19 before and after) | Pass |
| AC2: editing the copy leaves the original's stack, render hash and history byte-identical | Test, Script | `editingTheCopyLeavesTheOriginal`, `previewKeysFollowEachStack`. S4: the copy's stack hash is `822f9568f0de`, the original's stays `6c76a50e5dc3` (identity). `editHistory` has one row, for the copy only | Pass |
| AC3: rating the copy leaves the original, and the reverse | Test, Script | `cullingIsPerCopy`. S1: `key 5` on the copy rates it 5 and the original stays 0. S4: the copy is 4 and picked, the original 0 and unflagged (catalog) | Pass |
| AC4: the copy has the original's keywords and albums; adding to the copy leaves the original | Test, Script | `keywordsAndAlbumsAreSeededThenIndependent`, `copiesAreStackless`. S5: the original has `dog` and album `Orig`, and so does its new copy. S4: `beach`, `sand` and `CopyAlbum` are on the copy only | Pass |
| AC5: two items for the master, the copy marked; counts and subtitle include copies; the copy sits next to its original | Test, Script | `theCopyIsAnItemAndIsCounted`, `theCopyIsPlacedAfterItsOriginal` (6 sorts), `aCopySortsByItsOwnRating`, `placementEdges`, `onePassPlacementMatchesOneAtATime`. S1: subtitle `16 photos`, library 16, month and Last Import 16. The copy is at index 2, right after its original, marked `*`, with a grid mark (22×18). Snapshot `r1-grid.png` (looked at): the mark is at the top-right, and the name is `IMG_00002 copy`. S2: the strip marks and loupe title are right; `r2-loupe.png` (looked at) shows the Copy badge in the caption and the strip mark | Pass |
| AC6: removing a copy leaves the original; removing the original takes its copies and the confirmation names their number | Test, Script | `removingACopyLeavesTheOriginal`, `removingTheOriginalTakesItsCopies`, `removalConfirmationForCopies`, `removingACopyOfAPairsRAW`, `LibraryRemovalTests.everyVersionOfTheMasterGoes`. S6: both texts as designed; removing `IMG_00003.JPG` took its copy, and removing `IMG_00005 copy` left `IMG_00005` | Pass (see Q1) |
| AC7: duplicating, editing, rating and keywording the copy queues nothing; no `.xmp` written or flagged (scoped by P2: adjustments, culling, keywords, albums) | Test, Script | `copiesNeverReachASidecar` (real files and a real queue run), `renamingACopysKeywordQueuesNothing`, `SidecarSyncTests.copiesTakeNoPartInSidecarReview`, `aPairsChangeIsNotListedForACopy`, `twoVersionsOfOneMasterListItsChangeOnce`. S3 and S4, with sidecars on: after Duplicate, an edit, a rating, a flag, keywords and an album on the copy, `sidecarQueue` held 0 rows and no `.xmp` existed. Control in S5: a keyword on an original wrote `IMG_00004.xmp`, holding `dog` and not the copy's rating | Pass. Descriptive fields: known and pending (P2) |
| AC8: original and copy exported together give two distinct files whose pixels match their own edits | Test, Script | `exportingOriginalAndCopyTogether` (pixels), `exportNamesForCopies`, `importTemplatesAreUnchanged`. S7: 16 files, including `IMG_00002 copy.jpg`, `IMG_00004 copy.jpg` and `PAIR_00013 copy.jpg`. Mean gray level: `IMG_00004.jpg` 125.8, `IMG_00004 copy.jpg` (−2 EV) 64.5. The unedited `IMG_00002 copy.jpg` is byte-identical to `IMG_00002.jpg` | Pass |
| AC9: duplicating a pair's RAW leaves the JPEG untouched and unpaired from the copy; rating the copy doesn't change the JPEG | Test, Script | `aPairsCopyIsUnpaired`. S6: `PAIR_00013 copy` has no `:pair`; `key 5` on it left the DNG and JPEG versions at 0; `imagePair` unchanged (12↔13); the JPEG still has one version | Pass |

Also run by script: a video can't be duplicated (`canDuplicate false`, `duplicate unavailable`), and the video loupe's context menu has no Duplicate (S7, S8). A mixed ⌘A Duplicate skips the video, with the row `[Duplicate] 1 video wasn't duplicated.` and the announcement `Made 16 copies.` (S7). Numbering is `copy`, `copy 2`, `copy 3` (S7). Context menus in the grid and the loupe have Duplicate first in the Export… / Show in Finder group (S7). In review mode the copy keeps its title, badge and edit (S8; `r8-review.png` looked at). 19,999 copies were made in 1.4 s, with the Activity job `Duplicating 19,999 photos…` (S9). R11 (Could) is covered by test only (`smartAlbumRuleForCopies`).

## Findings

**Q1 (minor; code review C4, now reproduced).** A removal asked for while an Undo of Duplicate is still taking the copies away is confirmed and run as if the copies were there.
- Steps (S9, on a 20,000-photo library): ⌘A, Duplicate (19,999 copies), Undo, then Remove from Library… straight away, while the copies are still selected.
- Expected: no confirmation for photos that are gone (or one that matches what is left), and the undo stack kept, so that Redo Duplicate is still possible.
- Actual: once the undo has landed, "Remove 19,999 photos from the library? The originals and their files are not affected. The copies' edits are lost…" appears. Remove deletes nothing (the catalog still has 20,002 versions and 0 copies) but announces "Removed 19,999 photos from the library." and empties the undo stack (`undo '-' redo '-'`), so Redo Duplicate and every earlier step are lost. With a few photos the window is milliseconds.
- Suggested fix (the reviewer's): a plan that finds none of its versions ends the request without asking and leaves the undo stack alone. If the owner would rather not fix it on this branch, the proposed follow-up issue (`bug`) is: "Remove from Library right after undoing Duplicate asks about copies already gone and clears undo". Body: the steps above, from virtual-copies (#62) QA Q1.

No missing tests: each criterion's test fails without the behavior it names.

Note on the script (not a defect): `undo` and `redo` return before their write lands. A `print copies` right after them showed the list before the change (S1). With `wait 2` in between, it shows the change (S2). As the code review warned, `alert` right after an undo of a large Duplicate printed `alert none` (S9).

## Scripts

Run on a copy of the bundle at `$S/Gus-qa.app` with identifier `me.sesser.gus.debugtest.virtual-copies-qa`, ad hoc signed. Each run was `"$S/Gus-qa.app/Contents/MacOS/Gus" --library-root <lib> --debug-script "<script>"`, with `S` set to a scratch folder of this session. `lib` came from `photobench generate --jpeg 8 --dng 2 --heic 2 --pairs 2 --videos 1` and `photobench import` (17 files: 15 items, one video). `big` came from the same import plus `photobench synthesize --count 20000`. Every launch passed `--library-root`.

**S1** (lib): `wait 2; print copies; print title; print sidebar; focus IMG_00002; print menustate; duplicate; print copies; print title; print undo; print sidebar; print announcement; print messages; snapshot $S/r1-grid.png; key 5; print copies; focus IMG_00002; print copies; print undo; undo; print copies; print undo; undo; print copies; print title; print undo; redo; print copies; print title; print undo; quit`
- 15 → 16 items. `IMG_00002 copy` is marked `*` at index 2 and focused. Subtitle `16 photos`. Undo is `Duplicate`. Announcement: `Made a copy of “IMG_00002”.` No Activity row.
- `key 5` rated the copy only. The undo prints ran before the write landed (see the note under Findings).

**S2** (lib): `wait 2; focus IMG_00003; duplicate; print copies; print undo; undo; wait 2; print copies; print title; print undo; redo; wait 2; print copies; print title; print undo; focus IMG_00003 copy; loupe; wait 2; print copies; print filmstrip; snapshot $S/r2-loupe.png; key 5; wait 1; print copies; grid; wait 1; print copies; quit`
- Undo: 17 → 16, the original focused, redo is `Duplicate`. Redo: 17, the copy focused, with the same catalog id.
- Loupe: title `IMG_00003 copy`, badge `Copy`, help `A copy of “IMG_00003.JPG”. Its adjustments, rating, flag, label, keywords and albums are its own.`
- Strip tips: `IMG_00002 copy, JPEG` and `IMG_00003 copy, JPEG`.

**S3** (lib): `wait 2; sidecars on; wait 6; print disk; quit`. This turned sidecars on. Afterwards there was no `.xmp`, `sidecarQueue` held 0 rows, and `metadataSync` had 15 rows.

**S4** (lib): `wait 2; focus IMG_00005; duplicate; loupe; wait 2; print copies; adjust exposure 1.5; wait 2; history; key 4; key p; addkeywords beach, sand; album CopyAlbum; wait 1; print copies; print keywords; print sidebar; print undo; wait 4; print disk; grid; wait 1; print copies; quit`
- Catalog afterwards:
  - The original is unchanged: rating 0, flag 0, hash `6c76a50e5dc3`, no history.
  - The copy has rating 4, is picked, has hash `822f9568f0de`, one history entry, keywords `beach` and `sand`, and is in `CopyAlbum`.
- `sidecarQueue` held 0 rows and there was no `.xmp`.

**S5** (lib): `wait 2; sidebar all; wait 1; focus IMG_00004; addkeywords dog; album Orig; wait 1; sidebar all; wait 1; focus IMG_00004; duplicate; print copies; key 3; wait 1; print copies; print keywords; print sidebar; wait 5; quit`
- The copy starts with `dog` and `Orig`. Counts: `dog=2`, `Orig=2`.
- Rated 3, the copy changed and the original stayed 0.
- `IMG_00004.xmp` was written (from the original's keyword) and holds `dog` and no rating.

**S6** (lib): `wait 2; sort fileName desc; wait 1; focus PAIR_00013; print menustate; duplicate; print copies; key 5; wait 1; print copies; pairs separate; wait 1; print copies; pairs grouped; sort captureDate; wait 1; focus IMG_00002 copy; removephotos; alert; alert press Cancel; focus IMG_00003; removephotos; alert; alert press Remove; wait 1; print copies; print announcement; focus IMG_00005 copy; removephotos; alert; alert press Remove; wait 1; print copies; print undo; quit`
- Pair: `PAIR_00013` keeps `:pair`, and `PAIR_00013 copy` has none. After `key 5` the copy is rated 5 and both pair files stay at 0. `imagePair` is unchanged.
- The confirmation for a copy reads `Remove “IMG_00002 copy” from the library?` / `The original and its file are not affected. The copy's edits are lost, along with its rating, keywords and albums. You can't undo this action.`
- The confirmation for an original reads `Remove “IMG_00003.JPG” from the library?` / `Its copy is removed with it. The files and their sidecar files stay on disk, …`
- Remove: `IMG_00003` and its copy are gone. Removing `IMG_00005 copy` left `IMG_00005`.
- Buttons: Cancel (Escape) and Remove (destructive, no key).

**S7** (lib): `wait 2; sort fileName desc; wait 1; focus MVI_00015; print menustate; duplicate; contextmenu cell 4; sort captureDate; wait 1; focus IMG_00004; contextmenu cell 3; focus IMG_00004 copy; loupe; wait 2; adjust exposure -2; wait 2; contextmenu loupe; grid; wait 1; selectall; export window; wait 1; export set format=jpeg names=original size=long:800 dest=$S/out reveal=off; export print; export run; export close; wait 1; selectall; duplicate; print copies; print messages; print announcement; quit`
- With the video focused: `canDuplicate false`, `duplicate unavailable`. (`cell 4` turned out to be a copy, not the video; S8 checks the video's own menu.)
- Context menus: `Duplicate`, `Export…`, `Show in Finder` follow a separator.
- Export: 16 files with distinct names. Pixels as given under AC8.
- Mixed Duplicate: `1 video wasn't duplicated.` and `Made 16 copies.`

**S8** (lib): `wait 2; focus MVI_00015; loupe; wait 2; contextmenu video; grid; wait 1; focus IMG_00004 copy; review on; wait 3; print review; print copies; snapshot $S/r8-review.png; review off; wait 2; menuitems Duplicate; quit`
- The video loupe menu has no Duplicate.
- Review shows the copy's title and badge, and the −2 EV edit is visible in the snapshot.
- The menu reads `File/Duplicate key cmd+"d" disabled (after a separator)`. It is disabled because a scripted launch has no key window, so P1 checks it with a real one.

**S9** (big): `wait 4; selectall; duplicate; print copies; print undo; undo; removephotos; alert; print removal; wait 6; print copies; alert; alert press Remove; wait 3; print copies; print undo; print announcement; quit`
- Duplicate ran 1.4 s, with the job `Duplicating 19,999 photos…`.
- After the undo, `alert none`, then `removing true asking false`. Then the confirmation for 19,999 copies appeared, and Remove removed nothing, cleared undo and announced the removal (Q1).

## For a person

The owner doesn't check VoiceOver or macOS 15 and 26, so they aren't listed here. Run the bundle with `--library-root` on a scratch library from `photobench`, as `docs/WORKFLOW.md` step 5 gives.

- **P1 (M1, M5).** Make the library window key.
  - File ▸ Duplicate is enabled with a photo selected in the grid and in the loupe.
  - It is dimmed with only a video selected, with the sidebar focused, with the search field focused, and while a crop is being edited.
  - ⌘D from the keyboard makes a copy.
  - Right-click a photo in the grid and in the loupe: Duplicate is first in the Export… group. Right-click a video: there is no Duplicate.
  - Scripts showed the menu state and the context menus, but not the menu bar's enablement in a key window.
- **P2 (M2).** Look at the copy mark at the smallest and largest thumbnail sizes, and in the film strip at its smallest size.
  - Check it on a mostly white photo and on a rejected (dimmed) one, with Increase Contrast on and off.
  - On an offline copy, check that the offline mark and the copy mark don't crowd each other.
- **P3 (M3).** In the loupe on a copy, hover the Copy badge. Its tooltip appears, and the badge stays clear of the other caption controls at a narrow window width.
- **P4 (M4).** Duplicate a photo in the middle of a long, scrolled grid, then undo and redo. The copy appears right after its original, selected and in view, and nothing else jumps or flashes.
- **P5 (M6).** Change a photo's sidecar in another app, then select a copy of that photo. The inspector shows no Changed on Disk section, and the Changed on Disk source lists only the original.

**Pending owner decisions** (PRD, not checks): P1 (videos are not duplicated), P2 (descriptive Info fields are shared with the original and queue its sidecar; AC7 is scoped to exclude them), and P3 (keyword suggestions are per master). Each is built as the PRD recommends.

## Follow-up

None yet.
