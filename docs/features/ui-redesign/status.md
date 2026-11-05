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
- Latest (with E10): `swift build` clean, no warnings; `swift test` 484 tests
  in 87 suites passed, 1 known issue (the same). No golden changed.

## Changes

| # | Pri | Change | State | Commit | Verified by |
|---|---|---|---|---|---|
| E1 | High | Empty-source states (N3) | Done | Show a source's own empty state (E1) | Rule: `EmptySourceState` (PhotoCore), suite "Empty source states" (each kind, library empty, filtered, non-empty). Debug script on a scratch library: `album`, `sidebar album 0`, `remove`, `print empty` → `emptySource(album)`; `smartalbum`, `sidebar smart 0` → `emptySource(smartAlbum)`; `sidebar builtin picks` → `emptySource(other)`; `rating 5` → `noMatches`. `snapshot` of the album and smart album shows the title, description, Edit Smart Album… and no Import buttons. Symbol (D-Q1, follow-up commit "Show the source's sidebar symbol in its empty state (E1)"): `SidebarSymbols.symbol(for:)` feeds every sidebar row and the empty state; `print empty` reports album `rectangle.stack`, smart album `square.stack.3d.up.badge.automatic`, Picks `flag`, and the snapshots show them untinted. An empty keyword can't be reached: a keyword with no photos leaves the sidebar and the selection moves to All Photos (seen with `addkeywords`, `keyword 0`, `undo`); a keyword source reports `symbol tag` from the same mapping. Manual: Edit Smart Album… opens the editor |
| E2 | Medium | Adjust tab states as `ContentUnavailableView` (N1) | Done (symbols to confirm, D-Q3) | Show the Adjust tab's states as content-unavailable views (E2) | Video, offline and unreadable are `ContentUnavailableView`s with N1's titles and descriptions; loading keeps its spinner; the header stays hidden. Found and fixed: a video in the loupe left the editor idle (the video loupe tears down the photo loupe), so the tab said "No photo"; `LibraryModel.loupeAdjustState` now lets a focused video decide, and the view and the debug script read it. Debug script (`print adjustments` now also prints `adjust tab`) on a scratch library: a video → `video`; a master on a detached disk image → `offline`; a version whose stack has `schemaVersion` 99 → `unreadable(newerVersion(99))`; a plain photo → `ready`. `LocalizationTests` now also scans `ContentUnavailableView("…")`, which found "No Selection" and "No Presets" missing from the catalog (added). Manual: the three views in the inspector (glass) |
| E3 | Medium | Settings check boxes (I10) | Done | Use check boxes in Settings (E3) | `.toggleStyle(.checkbox)` on the Settings form; nothing else changes. SwiftUI draws these toggles itself (no `NSButton` or `NSSwitch` in the window), so the check is visual: debug script launched with `open -W -n`, `menupress Settings…`, then the new `windowshot Settings <png>`, shows both options as check boxes with their labels, no switches. Guide: no change (it says only "turned off in Settings") |
| E4 | Medium | Adjust ▸ Import Look-Up Tables… (N5) | Done (flow to confirm, D-Q4) | Add Adjust ▸ Import Look-Up Tables… (E4) | The import page needs a chosen source, so the item runs the sheet's Import… panel on the library window, then opens the sheet on the import page (`LookTableLibraryModel.chooseImportFromMenu` / `openImportPage`); cancelling opens nothing. Placed after Manage Presets…, before Browse Look-Up Tables… (§4 order). Debug script (new `lutwindow importmenu <folder>`, `importrun`, `page`): sheet attached on "import (2 of 2 tables)", snapshot shows the Import Look-Up Tables page with Back; `lutwindow back` → tables; importing from that page posts "[Import Look-Up Tables] Imported 2 look-up tables.". `menuitems Look-Up` lists the item; its enablement is the same `can()` as Browse; a key-window run is pending (macOS refused to activate the app on two tries). Manual: the panel itself. Guide: no change (it doesn't describe look-up tables) |
| E5 | Medium | Adjust ▸ Reset Crop (N6) | Done | Add Adjust ▸ Reset Crop (E5) | After Crop / Finish Cropping; runs `editor.resetCrop()`, the heading's action. `AdjustmentEditor.canResetCrop` is now the one rule for the heading button and the menu (`LibraryMenuState.canResetCrop` adds "editable loupe photo"). Debug script (new `print menustate`): grid → false; loupe, uncropped → false; during a session with a crop and after Done → true; video → false. `adjust crop reset` (the same call) clears the crop; `print undo` shows one step "Reset Crop"; `undo` gives the crop back. `menuitems` / `menupress` in a key window: pending (macOS refused to activate the app); the item's enablement is `can { $0.canResetCrop }`. Guide: the crop paragraph names it |
| E6 | Low | Adjust ▸ Show / Hide Mask Overlay (N7) | Not started | | |
| E7 | Medium | Mask and component limits dim their commands (N8) | Done | Dim New Mask and Add to Mask at their limits (E7) | `MaskLimits.canAddMask(to:)` and `canAddComponent(to:)` beside `MaskLimits`; test "New Mask and Add to Mask stop at the limits" (31/32 masks, 15/16 components, agreeing with `allows`). Adjust ▸ New Mask ▸ reads `LibraryMenuState.canAddMask`; the heading's shape rows dim with the plural tooltips, and VoiceOver keeps each shape's name (`AppKitButton.accessibilityLabel`). The brush-point warning in Activity is unchanged. Debug script (`buttons` now prints disabled and tooltips; `print menustate`): after 32 × `adjust mask add`, menustate `addMask false`; the New Mask row "disabled tip 'A photo can have up to 32 masks.'"; a mask with 16 components: Add to Mask row "disabled tip 'A mask can combine up to 16 shapes.'"; a photo without masks: enabled. `menuitems Gradient`: the New Mask submenu's shape items are dimmed when it can't act; the "New Mask" submenu title itself reads enabled (D-Q5). Found: an `AppKitButton` with `isEnabled: false` can show enabled (SwiftUI applies its own enabled state to the control); the shape rows add `.disabled(…)`; the wider problem is listed below |
| E8 | Medium | View ▸ Play / Pause, Space (N9, I6) | Done (key-window checks pending) | Add View ▸ Play / Pause (E8) | After Show / Hide Film Strip; Space shown as a bare key; enabled by `canByKey { showsLoupeVideo }`; titled by `VideoPlayback.isPlaying`. New `VideoPlayback` (model) holds the video loupe's player and follows `timeControlStatus`; the menu, Space in the event monitor and the VoiceOver action all call `playback.toggle()`. Debug script (new `playpause`, the item's action): in the video loupe `print menustate` goes playing false → true → false; moving to another video resets it; in the grid `video false`. `key space` in the grid still opens the loupe with the Space item present. Pending, needs an active app (macOS refused activation on every try this session): `menuitems Play` enabled on a video and dimmed on a photo, the title flip, and Space playing in the video loupe through the monitor. Guide: the video paragraph names the item |
| E9 | Medium | Video loupe context menu (N9) | Done | Give the video loupe a context menu (E9) | `PhotoContextMenu.videoLoupe`: the photo items that apply to a video (Rating, Flag, Color Label, Add Keywords…, Suggest Keywords, Add to Album, Remove from Album; no adjustments, no Export), then Play / Pause (by state) and Show Grid. `VideoLoupeHostView.menu(for:)` answers only over the picture, by the double-click's hit rule (`VideoLoupe.isOnPicture`); the event monitor pops it up on right-click and Control-click, since AVKit's views take those clicks. Debug script (`contextmenu video`, new): lists exactly those items; "Play" becomes "Pause" while playing; running Play starts playback (`print menustate`), Show Grid returns to the grid. Manual: right-click and Control-click on screen, and that a click on AVKit's visible control bar keeps AVKit's behavior (the bar hides until hovered, so a scripted point lands on the picture). Guide: the video paragraph |
| E10 | Medium | Edit ▸ Deselect All ⇧⌘A, shared item (I5) | Done (key-window checks: manual) | Make Deselect All one item for both windows (E10) | One ⇧⌘A item, as ⌥⌘I: `ImportCommands(includesSharedItems: false)` in the library app, whose item acts for the import window while it is key (`ImportMenuContext.deselectAll`) and else collapses the grid's selection to the focused photo (`LibraryModel.collapseSelection`). Enabled in the grid with 2+ selected while it has the keyboard (so ⇧⌘A typed in a text field never changes the photo selection); dimmed in the loupe. The standalone importer keeps its own item. Debug script on the isolated copy (new `deselectall`; `print menustate` shows `selected`): `selectall` → selected 8; `deselectall` → selection 1, focus kept. Manual (the app wouldn't activate, `key nil`): `menuitems "Deselect All"` and `menukey` ⇧⌘A with each window key. Guide: key table row |
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
| E27 | Low | User guide kept current (I30, RI-5) | In progress | Correct the user guide's video and zoom keys (E27) | Done with their changes: E13 (folders chosen during an import join the queue), E14 (export results in Activity, no alert), E5 (Reset Crop), E8 (Play / Pause), E9 (the video loupe's context menu). Done on their own: "Include videos switch" → **Show Videos** in the Selection menu or the View menu; the key table's loupe column for ⌘= / ⌘− reads "zoom in / out". Left: "caption" → Description with E16. Designer review of the terms pending |
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
- **D-Q4 (E4, built; confirm): how Import Look-Up Tables… reaches the
  Import page.** The page lists the tables found in a chosen folder, so it
  can't open before something is chosen. Built: the open panel on the
  library window first (as Import Presets… does), then the sheet opens on
  the Import page; Cancel opens nothing. Option: open the sheet first and
  put the panel on it, so Cancel leaves the tables showing (small change).
  Recommendation: keep as built. Also: N5 says "after Import Presets…" but
  §4 lists it after Manage Presets…, next to Browse Look-Up Tables…; built
  per §4, which keeps the two look-up table items together. One line to
  move if N5 is meant literally.

- **D-Q5 (E7): the New Mask submenu's own title can't be dimmed.** E7's
  check says `menuitems "New Mask"` is dimmed at 32 masks. SwiftUI's
  `.disabled` on a `Menu` in `Commands` dims the items inside it, and
  AppKit keeps a submenu's title enabled; this was already so before E7
  (seen with no key window, when every other item is dimmed). Options:
  accept dimmed shape items under an enabled title (no cost); or reach
  into the AppKit menu after SwiftUI builds it and dim the title (fragile:
  SwiftUI rebuilds menus, and the debug script's menu probes would be the
  only test). Recommendation: accept, and change the check to the shape
  items.

### Found, not fixed (outside these changes)

- `AppKitButton(isEnabled: false)` doesn't reliably dim: SwiftUI applies
  its own enabled state to the hosted `NSButton` after `updateNSView`.
  Seen with the Crop heading's reset button on an uncropped photo; the
  mask eye button and the Adjust tab's other `isEnabled:` buttons are
  likely affected. A fix belongs in `AppKitButton` (for example,
  `.disabled(!isEnabled)` at each use, or a wrapper view), as its own
  change.

### Requirements issues (product-manager)

None open.

- **prd.md Q2, answered (E28): R1 keeps R2 as far as the debug script can
  tell.** With SwiftUI's help group replaced by nothing, both apps keep the
  Help menu in the menu bar, and AppKit still has it as `NSApp.helpMenu`,
  the menu it adds the command search field to. The field itself is drawn
  only when the menu opens, so seeing it and AC2 are a manual check in each
  app.
