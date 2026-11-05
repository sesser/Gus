# UI redesign: implementation status

Owner: swift-macos-engineer. Tracks the engineer changes E1–E28 in
[`design.md`](design.md) §6 (feature `ui-redesign-reconcile`). Branch
`feature/ui-redesign-reconcile-impl`, cut from `develop` at `adb8d95`.

States: Not started · In progress · Done · Blocked (waiting on a question
below) · Deferred. "Commit" is the subject of the commit that finished the
change (`git log --grep "(E1)"` finds it).
"Manual" means a person has to look at the bundled app; those checks belong
to `ui-redesign-onscreen-check` unless noted.

## Build and test

- Baseline at `adb8d95` (2026-11-04): `swift build` clean; `swift test` 468
  tests in 84 suites passed, 1 known issue (the `withKnownIssue` in "Live
  render session", pre-existing).
- Latest (with E2): `swift build` clean, no warnings; `swift test` 483 tests
  in 87 suites passed, 1 known issue (the same). No golden changed.

## Changes

| # | Pri | Change | State | Commit | Verified by |
|---|---|---|---|---|---|
| E1 | High | Empty-source states (N3) | Done | Show a source's own empty state (E1) | Rule: `EmptySourceState` (PhotoCore), suite "Empty source states" (each kind, library empty, filtered, non-empty). Debug script on a scratch library: `album`, `sidebar album 0`, `remove`, `print empty` → `emptySource(album)`; `smartalbum`, `sidebar smart 0` → `emptySource(smartAlbum)`; `sidebar builtin picks` → `emptySource(other)`; `rating 5` → `noMatches`. `snapshot` of the album and smart album shows the title, description, Edit Smart Album… and no Import buttons. Symbol (D-Q1, follow-up commit "Show the source's sidebar symbol in its empty state (E1)"): `SidebarSymbols.symbol(for:)` feeds every sidebar row and the empty state; `print empty` reports album `rectangle.stack`, smart album `square.stack.3d.up.badge.automatic`, Picks `flag`, and the snapshots show them untinted. An empty keyword can't be reached: a keyword with no photos leaves the sidebar and the selection moves to All Photos (seen with `addkeywords`, `keyword 0`, `undo`); a keyword source reports `symbol tag` from the same mapping. Manual: Edit Smart Album… opens the editor |
| E2 | Medium | Adjust tab states as `ContentUnavailableView` (N1) | Done (symbols to confirm, D-Q3) | Show the Adjust tab's states as content-unavailable views (E2) | Video, offline and unreadable are `ContentUnavailableView`s with N1's titles and descriptions; loading keeps its spinner; the header stays hidden. Found and fixed: a video in the loupe left the editor idle (the video loupe tears down the photo loupe), so the tab said "No photo"; `LibraryModel.loupeAdjustState` now lets a focused video decide, and the view and the debug script read it. Debug script (`print adjustments` now also prints `adjust tab`) on a scratch library: a video → `video`; a master on a detached disk image → `offline`; a version whose stack has `schemaVersion` 99 → `unreadable(newerVersion(99))`; a plain photo → `ready`. `LocalizationTests` now also scans `ContentUnavailableView("…")`, which found "No Selection" and "No Presets" missing from the catalog (added). Manual: the three views in the inspector (glass) |
| E3 | Medium | Settings check boxes (I10) | Not started | | |
| E4 | Medium | Adjust ▸ Import Look-Up Tables… (N5) | Not started | | |
| E5 | Medium | Adjust ▸ Reset Crop (N6) | Not started | | |
| E6 | Low | Adjust ▸ Show / Hide Mask Overlay (N7) | Not started | | |
| E7 | Medium | Mask and component limits dim their commands (N8) | Not started | | |
| E8 | Medium | View ▸ Play / Pause, Space (N9, I6) | Not started | | |
| E9 | Medium | Video loupe context menu (N9) | Not started | | |
| E10 | Medium | Edit ▸ Deselect All ⇧⌘A, shared item (I5) | Not started | | |
| E11 | Medium | File ▸ Stop ‹job› ⌘., shared item (I4) | Not started | | |
| E12 | High | Export enablement: targets include a photo, no export running (I1) | Done | Enable Export only for photo targets (E12) | Rule: `ExportTargets.canExport` (PhotoCore), suite "Export enablement" (videos only, mixed, pair, while exporting, stops at the first photo). Debug script launched with `open -W -n`: `focus MVI_00007; menuitems Export` → File/Export… disabled; `contextmenu cell 0` on a video lists no Export…; on a photo and after `selectall` it is enabled / listed. The toolbar item uses the same `LibraryMenuState.canExport`; manual on-screen check that it dims (glass) |
| E13 | High | Add Folder Without Copying… always enabled, queues (I2) | Done | Keep Add Folder Without Copying… enabled during imports (E13) | Menu, toolbar Import ▸ menu and empty-library button lose their "importing" dimming; the panel already enqueues through `importFolders`, the drops' queue. Test: "aFolderChosenWhileOneImportsJoinsTheBatch" (FolderImportQueueTests). Debug script (new `addfolder <path>`, the panel's call) launched with `open -W -n` on a fresh library: two 800-photo folders; `print activity` shows "Add 2 Folders \| Folder 1 of 2 · 448 of 800", then "Folder 2 of 2 · 192 of 800"; `menuitems Add Folder` enabled before, during and after. Toolbar menu and empty-state button: manual. Guide: the queue sentence now covers chosen folders |
| E14 | High | Export results in Activity only, no alert (I3, D2) | Done | Report export results in Activity only (E14) | Rule: `ExportActivityReport` (PhotoCore), suite "Export results in Activity" (clean, failures listed, 10 listed + rest counted, skips as information). The alert and `ExportModel.Report` are removed. Debug script (new `print messages`) on a scratch project with one original moved away: one warning row "Exported 5 of 6 photos. 1 could not be written." plus the file and reason; no sheet or alert attached once the debug-opened Export sheet is closed. Again with the original back and `export run skip`: information rows "5 photos were skipped because their files already exist." and "Exported 1 photo.". D-Q2 checks (ruled keep as built): one original moved away, the other five already in the folder, both videos selected, `export run skip`: two rows titled “Export to “out””, the information row "5 photos were skipped…" then the warning "1 photo could not be written." with the file; no sheet or alert. A clean export of 8 selected (6 photos, 2 videos): one row, "Exported 6 photos.", none about videos. VoiceOver hears the sentence, not the list (manual). Guide: export paragraph |
| E15 | Medium | Suggest Keywords shows Info ▸ Keywords (I7) | Not started | | |
| E16 | Medium | "Caption" becomes "Description" (I8) | Not started | | |
| E17 | Medium | One shared field-label set (I9) | Not started | | |
| E18 | Medium | Delete confirmations for presets (I11) | Not started | | |
| E19 | Low | Reset All Adjustments enablement (I12) | Not started | | |
| E20 | Low | Save Adjustments as Preset… enablement (I13) | Not started | | |
| E21 | Low | RAW+JPEG Pair ▸ for pairs only, with checkmarks (I14) | Not started | | |
| E22 | Low | Toolbar Crop and Original show their on state (I15) | Not started | | |
| E23 | Low | Import Selection pull-down enablement (I16) | Not started | | |
| E24 | Low | Add Folder open panel prompt (I17) | Not started | | |
| E25 | Low | Remove Edit ▸ Find ▸ Clear Filter (I18, D1) | Not started | | |
| E26 | Low | View ▸ Info / Adjust checkmarks (I19) | Not started | | |
| E27 | Low | User guide kept current (I30, RI-5) | In progress | | Done with their changes: E13 (folders chosen during an import join the queue), E14 (export results in Activity, no alert). Not started: Show Videos instead of "Include videos switch", ⌘= / ⌘− in the key table's loupe column, and "caption" with E16. Designer review of the terms pending |
| E28 | Medium | Remove the dead Help item (N13, R1, R2) | Done | Remove the dead Help item from both apps (E28) | `CommandGroup(replacing: .help) {}` in each app. New debug command `helpmenu` (both apps, `HelpMenuProbe` in PhotoUI). Before: Help held "‹app› Help ⌘?" in both. After, AC1: library `menuitems Help` lists only the Help menu itself, no item; `helpmenu` in the library app and in the importer: Help is still in the menu bar and is still `NSApp.helpMenu`, with no items. AC2 (type "Export" / "Rescan" in Help's search field): manual in each app. Answer to prd.md Q2 below |

## Open questions

### Design questions (apple-ui-designer)

- **D-Q1 (E1): symbol for "No Photos in “‹source›”".** Ruled 2026-11-04
  (design.md §9): the source's sidebar symbol, untinted, from one mapping.
  Built.
- **D-Q2 (E14): how an export's results split into rows.** Ruled
  2026-11-04 (design.md §9): keep as built. The question as raised:
  I3 says failures are a warning and skips by choice are information, but
  not whether they share a row. Built: one row per export (the finished
  sentence; when photos failed, a warning that also lists them), plus a
  separate information row for skips by choice, posted first so the
  summary is newest. Videos skipped by design are no longer mentioned after
  the export (the old alert listed them only when it showed; the sheet's
  header already says "3 videos are skipped"). Options: keep as built (no
  cost); fold the skip sentence into the export's row when nothing failed
  (small); also add a videos sentence (small, one plural string).
  Recommendation: keep as built.

- **D-Q3 (E2, built; confirm): symbols for the Adjust tab states.** N1
  gives titles and descriptions only. Built with the pictures the app
  already uses for each thing: `video` (the film strip marks videos with
  `video.fill`), `externaldrive.badge.xmark` (the grid's offline badge),
  and `exclamationmark.triangle` ("Can't Open the Library", "Can't Read
  ‹source›"). Options: keep these (no cost), or name others (no cost
  beyond the edit). Recommendation: keep. Also: N1 doesn't rule on the
  idle "No photo" text, which stays as plain text; it shows only for a
  moment while the loupe opens.

### Requirements issues (product-manager)

None open.

- **prd.md Q2, answered (E28): R1 keeps R2 as far as the debug script can
  tell.** With SwiftUI's help group replaced by nothing, both apps keep the
  Help menu in the menu bar, and AppKit still has it as `NSApp.helpMenu`,
  the menu it adds the command search field to. The field itself is drawn
  only when the menu opens, so seeing it and AC2 are a manual check in each
  app.
