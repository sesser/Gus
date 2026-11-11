# Library operations: code review

Owner: code-reviewer. Date: 2026-11-10. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/library-ops`, `1dc2dce`..`fd00a1f` (the implementation commit `fd00a1f`;
`417c60f`, the workflow change, and `87258a8`, the PRD and design, were not reviewed here).
Build and tests: `swift build` complete; `swift test` 723 tests in 118 suites passed, 1 known
issue (`LiveSessionTests` "Values above white survive the cached stages", as on the baseline).
`Scripts/build-app.sh` not run; the app was not launched (qa-tester's).

## Verdict

Ready for qa-tester once C1–C3 are in: no blocker. The catalog side (one transaction, pair
partners, queue cleanup, nothing on disk touched) is correct and its tests fail when the code
they cover is taken out. What is open is one ruled change not yet in the code, one test that
does not test what it names, and one debug-script command that can crash a scripted run.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Tests/PhotoCoreTests/LibraryRemovalTests.swift:449` (`cancelledQueueRunStops`); `Sources/PhotoCore/Sidecars/SidecarSync.swift:60-66` | The test passes without the change it is named for. It cancels the task right after creating it, so `try Task.checkCancellation()` at the top of `processQueue` (line 54, on `develop` already) throws before any file is looked at; the new stop between files (lines 63-66) is never reached. | In a copy of `fd00a1f` with `develop`'s `SidecarSync.swift`, `swift test --filter LibraryRemovalTests` passed 19 of 19, five runs out of five. Deleting lines 63-66 and 77 would go unnoticed. The test needs a run that is cancelled after its first file is written (two queued masters; cancel from the first write, by a reader or hasher the test controls) and then checks the second sidecar is unwritten and still queued. Nothing else covers the removal's wait for a sidecar run in flight (`pauseSidecarSync` is in PhotoApp, which has no tests). | Tests: a test fails without its change; deterministic |
| C2 | Should fix | `Sources/PhotoApp/Model/DebugLibraryOpsCommands.swift:31-43`; `Sources/PhotoApp/Model/DebugScript.swift:145-147` | `alert press <title>` and `alert key <key>` act on any sheet attached to the library window, and `alert` is not in `changing`, so no undo group is open when the button's action runs. That is right for a removal (it registers nothing and clears the stack) and wrong for every other confirmation the command reaches. | `…; alert press Delete` on "Delete the album “…”?" (`SidebarView.swift:216` → `deleteAlbum`, `AlbumActions.swift:73`; the same for a keyword or smart album) calls `registerUndo` with `groupsByEvent` off and no group: the Objective-C exception `CLAUDE.md` describes, which unwinds through Swift and crashes later. Adding `alert` to `changing` is not the fix: `removeAllActions()` inside an open group leaves `endUndoGrouping` without its begin. Open the group only when no removal is pending (`model.pendingRemoval == nil`), or have the command refuse sheets other than the removal confirmation and say so in its help. | Undo: new debug-script commands that change the library open an undo group |
| C3 | Should fix | `Sources/PhotoApp/Model/LibraryOpsActions.swift:182` | The owner's ruling on Activity titles (the command's title with the count under it, for photos and projects alike) is not in the code: a photo removal's job is titled "Removing ‹N› photos…" with no detail. Recorded by the engineer as O1 in `status.md`; listed here so the second pass covers it. | Removing 30,000 photos shows "Removing 30,000 photos…" beside the spinner where a project removal shows "Remove Project from Library" with the count under it. `RemovalJob(title: LibraryOpsText.removeFromLibrary, detail: LibraryOpsText.removing(count))`; both strings are in the catalog. | Owner ruling 2026-11-10 (design question 2) |

No Nits.

## Questions

For the designer:

- **Q1. Focus after removing a project that is not the source on screen (§7.3).**
  `removalDidFinish` (`LibraryOpsActions.swift:306`) always moves the focus to the photo
  after the last removed one. For photos that is §6.3: the focused photo is one of the
  removed. For a project removed from its row's menu while another source is shown it
  moves a focus that survived: in All Photos with the loupe open on a photo of project A,
  Remove Project from Library… on project B leaves the loupe on the photo that followed
  B's last one, not on the photo that was open; in the grid the focus and the scroll
  position jump there. §7.3 says "as §6.3" and names only the case where the project was
  the selected source. Recommended: keep the focused photo when it was not removed
  (`RemovalFocus` only when `focusedItem` is among `result.imageIDs`). If that is the
  ruling it is a small change for the engineer and one more case for
  `focusAfterRemoval`.

For the product manager:

- **Q2. Smart albums that name a removed project (R8).** R8 deletes the project's own
  albums and smart albums. A smart album of the library or of another project with a rule
  "Project is ‹X›" keeps X's id (`SmartAlbumRules.swift`, `choiceCondition`): after X is
  removed, "is" matches nothing and "is not" matches every photo, and the editor's picker
  shows no project for the rule. The same already happens to a keyword rule when its
  keyword is deleted. Not reachable before this branch (projects could not be removed).
  Leave as is, or a follow-up? Proposed issue in my report.
- **Q3. What Show in Finder reveals for a project made by a copying import (R15).**
  `CopyImporter` gives a new project the copy destination as its `sourcePath`
  (`CopyImporter.swift:216`), and the files go under it by the folder template
  (`{capture:yyyy}/{capture:yyyy-MM-dd}` by default). So for every project imported from a
  card to, say, `~/Pictures/Photos`, Show in Finder selects `~/Pictures/Photos` itself:
  the same folder for all of them, and not the folders that hold the project's photos.
  R15 says "its source folder when `sourcePath` is set", which is what the code does; the
  rulings so far cover a missing folder, a mount point and a remounted volume, not this.
  Accept, or dim the command for these projects, or reveal the photos' folders? Proposed
  issue in my report.

## Checked and fine

- **One transaction, all or nothing (R13).** `removePhotos` and `removeProject` each run in
  one `database.write`. `aFailedRemovalChangesNothing` fails the second statement after the
  masters are deleted and compares every table's row count. In the app the removal runs on
  the write chain (`removeInOrder`), after every change queued before it; a failure reports
  a warning in Activity, clears no undo step and reloads nothing.
- **The tests bite.** In a scratch copy: without the `sidecarQueue` delete in
  `removeImages`, AC4, AC6 and AC10 fail; without the guard in `saveSync`,
  `savingSyncForARemovedMaster` fails with the foreign-key error. (C1 is the exception.)
- **Referenced masters (R5, R4).** Nothing in the diff opens a master or a sidecar for
  writing, moves or deletes a file. Show in Finder hands file URLs to `NSWorkspace`; a
  project's folder is probed with one `resourceValues` call. The AC4, AC6 and AC3 tests
  compare every file's SHA-256 and date before and after, with a queue run and a disk
  check in between.
- **Sidecar queue.** No foreign key on `sidecarQueue`: deleted for the removed masters in
  the same transaction, after them. The cascade's `sidecar_keyword_removed` trigger queues
  nothing (the version is gone when it looks; `cascadesQueueNothing` passes with or without
  the explicit delete). Around the transaction the app cancels a sidecar run in flight,
  waits for it and starts none until the removal ends; the run never waits on the write
  chain, so the two cannot deadlock. `SidecarSync.resolve` is on the write chain, and
  `checkForChanges` writes no file and now records nothing for a master that is gone.
- **Pairs (R7).** Partners are found in `imagePair` in both directions, inside the
  transaction, so either file takes both; pairs never span projects (`ImagePairing.pair`).
  The plan's file count and the confirmation's pair sentence agree for a grouped pair, an
  ungrouped JPEG and both halves selected. No grid query gained a join on `imagePair`.
- **Ids are not reused.** `autoIncrementedPrimaryKey`: a version id captured for the
  confirmation, or left in a late write, never comes to mean another photo.
- **Undo.** Cleared only after a removal that succeeded, undo and redo alike, the editor's
  steps included (one undo manager). That is needed, not only tidy: undoing "Delete Album"
  restores members by version id. Rename is one step on `persist`, with no step for an
  unchanged or refused name.
- **Beside other jobs.** Both Remove items are off while a folder add or a copying import
  runs (`importProgress`, `cardImport.progress`); no catalog write follows either becoming
  nil. An export reads its rows up front (`ExportJob.items`). A late `setEditStacks` or
  `changeEditStacks` on a removed version writes nothing and records no history. A late
  culling write updates no row. Suggestions, the metadata re-read and the disk check
  tolerate a master that is gone. A crop open on a removed photo is ended without saving.
- **The confirmation's state.** `isRemoving`, `pendingRemoval` and `removalJob` stay
  consistent whichever of the button's action and the dialog's dismissal SwiftUI runs
  first; a failed read of the plan resets them.
- **Swift 6.** Catalog work goes through GRDB's async reads and writes; file checks run in
  detached tasks; `PendingRemoval.remove` is `@Sendable` over Sendable values; the
  continuation in `removeInOrder` is resumed exactly once. No `@unchecked Sendable`, no
  `nonisolated(unsafe)`.
- **Menus.** `LibraryCommands` reads `LibraryMenuContext` through `@FocusedValue` only.
  Remove from Library… is under `canByKey`, so ⌘⌫ is on only while the grid, loupe or
  video loupe has the keyboard; no text field lives inside those views (`isBrowser`), and
  the sidebar's rename field is in the sidebar pane. Whether a dimmed item lets ⌘⌫ through
  to a field is M6, for a person. File menu order and the context menus match design §2.
  No `ScrollView` added (`ScrollViewReader` around the existing `List`). No launch option
  added.
- **Strings and branding.** All 26 new keys are in `Localizable.xcstrings`, the eight
  counted ones with one and other forms; "Remove" and "Project name" reuse entries whose
  comments now name both uses. No product name in any string or persisted name.
  `LocalizationTests` and `BrandingTests` pass.
- **Migrations, rendering, dependencies.** `CatalogSchema.swift`, the goldens,
  `PreviewCacheKey` and `Package.swift` are untouched. `deleteProject` is replaced by
  `removeProject` in the two tests that used it.
- **Security.** No parser, subprocess, network code or file writing added.
  `/security-review` is not needed for this branch.
- **`projectVolumeIDs`.** Index scan; 26 ms warm on a 200,000-photo catalog.

Not covered by a test, by the project's layout (PhotoApp has none): AC2, AC7, AC13 and
the Activity half of AC10. `status.md` maps them to debug-script runs; qa-tester owns that.

## Follow-up

After the engineer's fixes.

### Second pass

Date: 2026-11-11. Reviewed: `fd00a1f`..`38b7f21` (`bef0feb`, the review fixes, and `38b7f21`,
the focus ruling). Build and tests: `swift build` complete; `swift test` 724 tests in 118
suites passed, the same 1 known issue. `Scripts/build-app.sh` not run; the app was not launched.

**Verdict.** C1, C2 and C3 are fixed and Q1 is built as ruled. Two new Nits (C4, C5), both in
the debug script; neither holds the branch. Ready for qa-tester, after the designer's second
pass on where the focus lands.

| # | State | Commit | Notes |
|---|---|---|---|
| C1 | Fixed | `bef0feb` | The test now tests its change, and the change under it is sound. In a scratch clone of `38b7f21` with `if isQueuePaused { break }` (`SidecarSync.swift:84`) taken out, `pausedQueueRunStopsAfterItsFile` fails with 4 issues (2 files written where 1 is expected); with it, it passes. The pause comes from a trigger on the catalog's own write of the first file's state, so there is no timing in it. See **The pause** below. |
| C2 | Fixed | `bef0feb` | `answering` (`DebugLibraryOpsCommands.swift:75`) opens a group around `press` and `key` unless `pendingRemoval` is set, read before the click, so a removal's `removeAllActions()` never runs inside a group and Delete on an album, keyword or smart album confirmation registers inside one. `removalDidFinish` is the only caller of `removeAllActions` in the app. `alert` is not in `changing`; the help line in `DebugScript.swift` says what it does. Leaves C4. |
| C3 | Fixed | `bef0feb` | `RemovalJob(title: removeFromLibrary, detail: removing(count))` (`LibraryOpsActions.swift:182`); `ActivityToolbarItem.jobs` passes both to the job row, as for a project. The two catalog comments say which line is which. |
| Q1 | Built as ruled | `38b7f21` | `RemovalFocus.index(count:focus:isRemoved:)` returns the focus when it is in range and not removed, and the old rule otherwise. `removalDidFinish` reads `focusIndex` and `items` together, before the reload, so the index and the list agree; the reload then keeps that version focused. Without the new line `focusSurvivesARemovalElsewhere` fails (3 issues); `focusAfterRemoval` still covers a removed focus and no focus. A crop open on a surviving photo now stays open (before, the moved focus ended it). |
| Q2 | Ruled: left as is | | Issue #143. No code. |
| Q3 | Ruled: accepted | | Issue #144. No code. |

**The pause (C1).** Traced for each state the sidecar task can be in when a removal reaches
`pauseSidecarSync` (all on the main actor, so the check and the cancel cannot be split):

- *Sleeping before its run* (`sidecarSyncIsWriting` false): cancelled; the sleep ends, and
  `processQueue` returns at `while !isQueuePaused` before it reads anything or checks
  cancellation. No file is looked at.
- *Inside a run*: not cancelled. The file in flight is written and recorded, the loop breaks
  before the next target, what is done is dequeued, and the outer loop ends. A pending
  request makes the task call `processQueue` once more, which returns at once.
- *After the run, in `refreshDiskChanges`*: waited for; it does not use the write chain, so
  the removal (which holds the chain) cannot deadlock with it.
- *A task created while the removal runs* (a change saved in that moment): allowed now that
  `scheduleSidecarSync` no longer refuses, and harmless: its run does nothing while paused,
  and `resumeSidecarSync` asks again.

`resumeSidecarSync` runs after a failed removal too. Nothing else in the app cancels
`sidecarSyncTask`, so no run is cancelled mid-file any more. `pauseQueue` is checked between
files only, never between writing a sidecar and recording it. `Mutex` is available at the
package's minimum (macOS 15) and is what lets a `nonisolated` call reach a run suspended
inside the actor. `photobench` and the tests that call `processQueue` never pause. This
replaces the sentence in **Checked and fine** that says the app cancels a run in flight.

**User guide.** Both edits match the code: Remove from Library… and Remove Project from
Library… are dimmed in the File menu (`LibraryCommands.swift:116`, `:138`) and left out of the
photo menus and the project row's menu (`PhotoContextMenu.swift:89`, `SidebarView.swift:304`)
while `canRemoveFromLibrary` is false; a project rename is one undo step; a removal clears
the stack.

New findings:

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C4 | Nit | `Sources/PhotoApp/Model/DebugLibraryOpsCommands.swift:75-80` | On a sheet that is not a removal's confirmation, `alert press Cancel`, `alert key escape` and `alert key return` now leave an empty undo group, which is an undo step that does nothing (checked: with `groupsByEvent` off, `beginUndoGrouping(); endUndoGrouping()` gives `canUndo` true and an empty action name). The script's `key` command has always done the same, so this follows the convention; it matters only to a script that reads the undo stack after cancelling. | `…; alert key escape; print undo` on "Delete the album “…”?" after a rating: the stack's top is a nameless step, and one `undo` changes nothing where the rating should come back. Either say so in the `alert` help line, or leave it and have qa-tester not read `undo` after a cancelled non-removal sheet. | Debug script: empty groups become undo steps (`DebugScript.swift:142`) |
| C5 | Nit | `Sources/PhotoApp/Model/DebugLibraryOpsCommands.swift:69-82` | The new doc comment for `answering` was put in the middle of `settle`'s: "Waits for the alert's answer to be handled and, once the alert has closed, for a removal it started to end." now heads `answering`, and `settle` keeps only "Prints how long a removal ran…". | A reader of `answering` is told it waits for a removal; the sentence describes `settle`. Move it back above `settle`. | Comments say what the code does |

Not reported as findings, for qa-tester: the group in C2 is held open for the second
`settle` waits after the click (400 ms and 600 ms around the wait for a removal), which is
what lets a SwiftUI button action that runs after the sheet closes register inside it; the
engineer's run (`alert press Delete`, then undo) is in `status.md`. `/security-review` is
still not needed: no parser, subprocess, network code or file writing in either commit.
