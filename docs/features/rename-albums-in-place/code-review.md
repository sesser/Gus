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

None yet.
