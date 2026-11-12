# Rename albums in place: code review

Owner: code-reviewer. Date: 2026-11-11. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/rename-albums-in-place`, `c72d48e`..`629b6b3` (source and tests last
changed in `43468c6`; `df28ab1` and `629b6b3` are docs only). Build and tests: `swift build`
complete; `swift test` 731 tests in 119 suites passed, 1 known issue (the same as before).
The app was not launched: what depends on how SwiftUI and AppKit move the keyboard is
marked "by reading" and handed to QA (Q1).

## Verdict

Ready for QA. No blocker. One Should fix (C1) is certain in the code but its starting
state is reached only if a rename stays open when its row leaves the list, which I could
not confirm without running the app; QA's check Q1 settles it. Three nits.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix (by reading; Q1 confirms) | `Sources/PhotoApp/Model/SidebarRenameActions.swift:75-79`; `Sources/PhotoApp/Views/SidebarView.swift:217-221`, `:399-413` | A rename ends only through its field (`onSubmit`, `onExitCommand`, the focus change) or `endSidebarRenameIfGone`. When the row leaves the list with the field in it (View ▸ Sidebar Sections or Hide Section hides its section, the section's or the project's disclosure folds it, the sidebar is hidden), the field's view is removed, and a removed view's `onChange` does not run, so `sidebarRename` stays set with no field. `beginSidebarRename` then takes its same-row branch, which returns after `revealSidebarRow` and before `showsSidebar = true` and `setSidebarSection(…, shown: true)`. The `beginProjectRename` it replaces had no such branch and always ran both. | Select an album, File ▸ Rename (field opens), View ▸ Sidebar Sections ▸ Albums to hide the section. File ▸ Rename “‹name›” is still enabled; choosing it does nothing visible: the section stays hidden and no field appears (R8, AC9; the same for a project and the Projects section, which worked before this branch). Until another row's Rename is chosen from a menu, Return on any selected project or album is ignored (`sidebarRename == nil` guard), and that other Rename then saves the hidden row's draft. | Correctness: state that drifts from what is on screen; PRD R8 |
| C2 | Nit (the other outcome of Q1) | `Sources/PhotoApp/Model/DebugScript.swift:154-164`, `:560-573` | If hiding or folding does end the rename by saving, the new `sidebarpane off` and `sidebarsection … collapse`, and `sidebarsection … hide`, save a changed name outside an undo group: none is in `changing`, and the extra grouping covers only `renameproject` and `renamealbum`. | `renamealbum; text X; sidebarpane off`: `registerUndo` with `groupsByEvent` off and no group raises the Objective-C exception CLAUDE.md describes. Applies only if C1's state is not reached. | CLAUDE.md, debug script: commands that change photos open an undo group |
| C3 | Nit | `Tests/PhotoCoreTests/AlbumRenameTests.swift:159` | `listed.shuffled()` feeds the comparator a different order on every run. | The expected result is fixed, so a correct comparator always passes, but a wrong one could fail on one run and pass on the next, with nothing to reproduce it from. A fixed permutation (the reversed list is already there; add a rotated or interleaved one) checks the same thing. | Tests are deterministic |
| C4 | Nit | `docs/features/rename-albums-in-place/status.md:11-12`, `:16`, `:272` | The commits named (`ea5a84a`, `1f14384`, baseline `fcc9058`) are not on the branch. They have the same trees as `5129a6e`, `43468c6` and `e2eb548`, which are. | Someone following the status to a commit lands on one that is not an ancestor of the branch and will be gone after garbage collection. (`design.md`'s "code read at `66f3c64`" is the same, now `eb3c73d`; the designer's file.) | WORKFLOW: `status.md` current |

## Questions

- **Q1, for QA (decides C1 or C2).** With no text typed, so nothing is saved either way:
  `sidebar album 1; renamealbum; sidebarsection albums hide; print albums; renamealbum; print albums; sidebarsection`.
  If the first `print albums` still shows `renaming 1` with `field without the keyboard`,
  C1's state is real; the second `renamealbum` should then give `hidden sections []` and a
  field, and by reading it will not. Repeat with `sidebarpane off` and with
  `sidebarsection albums collapse`. If instead the rename has ended at the first print, C1
  is withdrawn and C2 stands (do not type text before `sidebarpane off` or a `sidebarsection`
  command until it is fixed; `click` is not grouped either, as before this branch).
- **Design question (for the designer), if Q1 shows C1's state.** Design §2.3 says what ends
  a rename when the keyboard moves; it does not say what happens when the row itself goes
  away under the field (its section hidden or folded, its project folded, the sidebar
  hidden, review mode). Save, as for "the keyboard moved elsewhere", is the reading that
  fits; the designer should say so before the engineer picks.
- **RI-RA1 (for the product manager), relayed from `status.md`, with one addition.** The
  in-place rule only trims the ends, so besides keeping runs of spaces an album name now
  has no length limit; the removed sheet cut names at 200 characters and New Album still
  does. The branch follows the spec (PRD A3, design §2.4); the product manager rules on a
  follow-up.
- **Coverage, for QA's mapping.** `PhotoApp` has no test target, so the routes, the endings,
  undo and redo, and one rename at a time (AC1, AC2, AC4, design §2.3) rest on the debug
  script (status S1–S3, S8), as the project rename's did. `renamingAnAlbum` and
  `renamingAnAlbumChangesOnlyItsName` call `Catalog.renameAlbum`, which this branch did not
  change: they pin AC1's storage and AC7 and would pass on `develop` too. The tests that
  fail without the branch are `renameRoutes`, `rowPlace` and
  `renamedAlbumTakesItsPlaceInTheList`.

## Checked and fine

- **The shared rename state.** `renamingProjectID`, `projectRevealRevision`,
  `revealProjectRow`, `beginProjectRename`, `endProjectRename` and `ProjectNameField` are
  gone from `Sources/`, `Tests/` and `Scripts/`; every route (File item, both rows'
  `renameAction`, Return, the debug commands) goes through `beginSidebarRename`. Each rename
  ends once: `endSidebarRename` compares the object (`===`) and clears it before saving, so
  a late focus change from a replaced field is ignored. Starting on another row saves the
  open one first, then both reveals collapse to the new row's. A deleted or removed row
  clears the state from both `refreshProjects` and `refreshSidebar`.
- **No leftover sheet or `ProjectRename`.** `SidebarSheet.renameAlbum`, its `id` and its
  `SidebarSheetView` case are removed; `grep renameAlbum Sources` finds only the model's and
  the catalog's functions and the debug command. `ProjectRename` remains only in
  `CLAUDE.md` ("Scope so far") and `docs/features/_inventory.md`, which are the product
  manager's at Ship (status "README" says so), and in library-ops' own records.
- **Undo on the write chain.** `renameAlbum` changes the name in memory, then `persist`,
  then `afterPendingWrites { refreshSidebar }`, and registers the inverse with the name it
  replaced. Because the name in memory is already the new one, an undo pressed before the
  write lands reads the right `previous` and queues behind it (on `develop` that undo was a
  silent no-op). A failed write is put right by the refresh. An unchanged name registers
  nothing. Saving while another rename starts stays in one event's group.
- **Catalog only.** One `UPDATE album SET name`; no migration, no trigger on `album` feeds
  `sidecarQueue` (test and S5 agree), no file touched, nothing joins `imagePair`, pairs not
  involved.
- **Album order in memory.** `AlbumSummary.isListedBefore` matches
  `ORDER BY name COLLATE NOCASE, id`: ASCII letters folded, other bytes compared unsigned,
  the shorter of two names first, ties by id; it is a strict order, so `sort` is safe. The
  test compares it with the catalog on mixed case, digits, prefixes and non-ASCII names.
- **Row identity.** Album rows are identified by `SidebarSelection.album(id)`; projects by
  `.project(id)`, smart albums by uuid (another type), so `scrollTo` cannot hit the wrong
  row and ids from different tables cannot collide.
- **Menus.** `LibraryCommands` still reads the model through the focused menu context;
  the title and the action both come from `SidebarRenameRoute`, so they cannot disagree.
  Keyword and smart album paths are unchanged apart from the smart album menu's separator.
- **Swift 6 concurrency.** `SidebarRename` is a main-actor `@Observable` class used only by
  the main-actor model and views; the PhotoCore enums are `Sendable`; the scroll `Task`
  inherits the main actor; no work moved onto or off the main actor.
- **Strings and branding.** "Album name" is in `Localizable.xcstrings`; the four changed
  comments match their use; no key became unused ("Rename Album" is the undo name, "Rename"
  and "Name" the keyword sheet's). `LocalizationTests` and `BrandingTests` pass. No
  persisted name, no new dependency, nothing borrowed from another application.
- **Debug script.** `projectalbum` is in `changing`; `renamealbum` and `renameproject` get a
  group when a rename is open, which is the only time they save.
- **User guide.** The rename paragraph, the albums paragraph and the Undo paragraph say
  what the code does (AC10).
- **Design review** (`review.md`, `629b6b3`, landed during this review): docs only, ruling
  D-RA1 matches the code (`opening: false` after a save, an undo or a redo).

## Follow-up

Second pass, 2026-11-11. The fixes are in `ba57bb2` (source, tests, user guide) and
`53f4a51` (`status.md`).

| # | State | Commit | Confirmed by |
|---|---|---|---|
| C1 | Fixed | `ba57bb2` | Reading, and `rowLeavesTheList`. `beginSidebarRename` now shows the sidebar and the row's section on every start, the same row included, and keeps the draft (`SidebarRenameActions.swift:75-85`). A rename whose row leaves the list ends by saving: `SidebarView` reports `SidebarListState` changes and `sidebarListChanged` ends it (`:93-98`). The state C1 described (a rename open with no field after its section is hidden or folded) is no longer reached, so Return is not left ignored. The engineer ran Q1 on the reviewed commit and saw C1's state, then R1–R3 after the fix (`status.md`); QA repeats them |
| C2 | Fixed | `ba57bb2` | Reading. `sidebarpane`, `sidebarsection` and `review` open an undo group while a rename is open (`DebugScript.swift:166-169`). Each sleeps inside its group (300, 500 and 1,500 ms; `:573`, `:578`, `:463`), so the save made by the view's `onChange` on the next update lands in the group |
| C3 | Fixed | `ba57bb2` | `AlbumRenameTests.swift:158-165`: three fixed orders, each checked to differ from the sorted list. No `shuffled()` left in the suite |
| C4 | Fixed, with one new stale name (C5) | `53f4a51` | `5129a6e`, `43468c6` and `e2eb548` are ancestors of the branch |

## Second pass

Owner: code-reviewer. Date: 2026-11-11. Reviewed `f85a2b1`..`278cb9d`: `ba57bb2` (the
fixes), `53f4a51` (status) and `278cb9d` (the design review's second pass, docs only; its
ruling D-RA2 is the behavior as built). Build and tests: `swift build` complete;
`swift test` 732 tests in 119 suites passed, the same 1 known issue; `AlbumRenameTests`
8 tests passed, `rowLeavesTheList` among them; `LocalizationTests` and `BrandingTests`
pass. The app was not launched; the script checks R1–R3 are the engineer's and QA's.

The branch was rewritten since the first pass: the commits this file calls `629b6b3` and
the one `status.md` calls `227ed46` are now `2bfce9b` and `f85a2b1` (same trees).

### Verdict

Ready for QA. C1–C4 are fixed and the new code brings no blocker and nothing to fix in
source. One nit in `status.md` (C5) and one question for QA (Q2).

### New finding

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C5 | Nit | `docs/features/rename-albums-in-place/status.md:15`, `:236` | The code review's commit is named `227ed46`, which is not on the branch; it is `f85a2b1`. C4 again, for a hash added by the fix. | "The commit after `227ed46`" leads to a commit that is not an ancestor of the branch. Since the branch's hashes have changed twice, naming commits by their subject line would last longer than a hash. | WORKFLOW: `status.md` current |

### Question

- **Q2, for QA's "For a person" list (not a finding).** `listState` covers every way a row
  leaves the list except one that is AppKit's: the sidebar's list makes row views lazily,
  so a row being renamed that is scrolled far out of view could lose its field without
  `SidebarListState` changing. I could not settle this by reading (AppKit normally keeps
  the row holding the first responder). Check: with enough albums to scroll, start a
  rename, type, scroll the row well out of view with the wheel and back. Expected: the
  field is still there with the typed text and Return saves. If the field is gone, File ▸
  Rename on the row brings it back with the text (the same-row start), so nothing is
  lost; report it then as a follow-up bug, not for this branch (the project rename on
  `develop` has the same property).

### Checked in the new commits and fine

- **Re-entrancy of `sidebarListChanged`.** It ends the rename through `endSidebarRename`,
  which clears `sidebarRename` before saving. The save (`renameAlbum`, `renameProject`)
  changes `albums` or `projects` and sets `sidebarReveal` with `opening: false`; the
  reveal handler then opens nothing and scrolls to a row that is not listed, so
  `listState` does not change again and nothing loops. A second call finds
  `sidebarRename` nil and returns false.
- **Edge, not level.** `removed` is true only when the row was listed before the change
  and is not after it. File ▸ Rename on a hidden or folded row sets the rename first and
  then opens what hides it: every step is unlisted to unlisted or unlisted to listed,
  for a library album, a project's album (the project inserted by the reveal handler one
  update later) and a project. If the split view cannot show the sidebar and sets
  `showsSidebar` back, that is a listed to unlisted change and the rename ends, saved.
- **Saved once.** Whichever comes first, the field losing the keyboard (`sidebarpane
  off`, review) or the list change, the other finds `sidebarRename !== rename` or nil and
  does nothing. Starting on another row still ends the open one inside
  `beginSidebarRename`, before any list change is reported; the `onChange` then sees the
  new row, which is listed, and leaves it alone.
- **Same-row start.** `if sidebarRename == nil { … }` creates the rename only when none
  is open or the other row's was just ended; an open one on the same row keeps its draft.
  Return in the list is still guarded by `sidebarRename == nil`.
- **Undo group rule.** In the app the save runs in the event's own group as before. In
  the debug script the three commands that can now end a rename are grouped only while
  one is open, and none is in `changing`, so no group is left open and none is added
  when no rename is open. One thing for QA's scripts: a grouped command that saves
  nothing (the name unchanged, or `sidebarsection` only printing while a rename is open)
  leaves an empty step, as `key` and `text` do (`status.md`, Debug-script results), so
  an `undo` right after it undoes nothing. `click` and `loupe` stay ungrouped, as the
  script's header says.
- **Focus handed back.** `listHasKeyboard = true` is set only when `sidebarListChanged`
  ended a rename and the sidebar is still shown; folding or hiding with no rename open
  moves nothing, and a rename that already ended through its field returns false, so the
  list does not take the keyboard from wherever the person moved it. With the sidebar
  hidden nothing is forced (design D-RA2; the designer's manual check M5).
- **`SidebarListState`, `SidebarRowPlace.isListed`** (PhotoCore, no AppKit or SwiftUI,
  `Sendable`): a library album depends on the sidebar and the Albums section, which holds
  exactly the albums with no project (`SidebarView.swift:126`); a project's album on the
  sidebar, the Projects section and its own project's disclosure; a project's row on the
  sidebar and the Projects section only, since it is the disclosure's label. The test
  covers each, and that opening is never a removal. It does not compile without the fix.
  `sidebarListChanged` itself is in `PhotoApp`, which has no test target: it rests on
  R1–R3, as the other routes do (first pass, Coverage).
- **Rules.** No catalog, migration, sidecar, pairing, rendering or dependency change; no
  new UI string (the user guide's sentence is docs); no brand value; no persisted name.
  `/security-review` is not needed.
