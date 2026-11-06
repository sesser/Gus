# UI redesign reconcile (E1–E28): QA

Owner: qa-tester. Date: 2026-11-06. Step 4 of `docs/WORKFLOW.md`.
Tested: `chore/project-cleanup` at aee03c3ceea2599c37dfd370660b9c56b3a1f18f
(develop plus doc-only changes; ui-redesign-reconcile merged in PR #34,
`1e89a7b`), on an Apple silicon M4 Pro Mac, macOS 27.2 (build 26B123),
macOS SDK 27.2 (26B118); both executables record `sdk 27.2`, `minos 15.0`.

**Scope.** Only the reconcile work: prd.md AC1 and AC2 (R1, R2) and the
engineer changes E1–E28 in design.md §6, including every item in
status.md "Pending manual checks". The older ui-redesign steps 1–15 and the
film strip are not covered. There is no designer `review.md` for this
feature, so the P items below cite E numbers and status.md's pending checks
instead of M numbers. Checks only a person can make are gathered under the
roadmap item `ui-redesign-onscreen-check` (owner, 2026-11-06).

## Verdict

Passes. Nothing in E1–E28 failed. Everything a script or test can show was
shown, including most of status.md's key-window checks. Open: AC2 and the
on-screen checks P1–P10, which only a person can make. Three low findings
(Q1–Q3) and one incident in this QA run (see Incident).

## Acceptance criteria

`swift test`: 551 tests in 96 suites passed, 1 known issue (the
pre-existing `withKnownIssue` in "Live render session"). The suites below
were also run on their own:
`swift test --filter 'EmptySourceStateTests|StoppableJobTests|ExportEnablementTests|ExportActivityReportTests|PairDisplayTests|FieldLabelTests|MaskModelTests|FolderImportQueueTests|LocalizationTests|BrandingTests'`
(51 tests, 10 suites, all passed).

"Key window" means a launch with `open -W -n` in which `print responder`
showed `key AppKitWindow` around the check.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 (R1) No "‹app› Help" item, both apps | Script | S1: library `helpmenu` gives `help menu 'Help' in menu bar true items []`, and `menuitems Help` lists only the menu itself. S2: the importer's `helpmenu` gives `items []`, Help still in the menu bar and still `NSApp.helpMenu`. The PRD asked for a by-hand check in the importer; the importer's own `helpmenu` replaces it | Pass |
| AC2 (R2) Help ▸ Search finds "Export" / "Rescan" | Person | P1 | Open |
| E1 Empty-source states | Test + Script | Suite "Empty source states" (each kind, empty library, filtered, non-empty). S3: `print empty` gives `emptySource(album)` with `rectangle.stack`, `emptySource(smartAlbum)` with `square.stack.3d.up.badge.automatic`, `emptySource(other)` with `flag` (Picks), and `noMatches` for a filter. Snapshots show "No Photos in “Empty Test”" with the album description, "No Photos in “Three Stars”" with "No photo meets this smart album's rules." and Edit Smart Album…, Picks with title and flag only, and "No Photos Match" with Clear Filter; none shows Import buttons. S23 closes status.md's pending check: clicking Edit Smart Album… in the empty state opens the "Edit Smart Album" sheet for Three Stars (snapshot) | Pass |
| E2 Adjust tab states | Script | S4, S16: `adjust tab video`, `offline`, `unreadable(newerVersion(99))` (stack set to `schemaVersion` 99 in the scratch catalog), `ready`; the loupe shows its Offline badge. `grep '"No photo"' Sources` finds nothing. How the views look in the glass inspector, and no text before the spinner: P2 | Pass; P2 open |
| E3 Settings check boxes | Script | S20: `menupress Settings…`, `windowshot Settings`: both options are check boxes with their labels, no switches (looked at) | Pass |
| E4 Adjust ▸ Import Look-Up Tables… | Script | S1: `Adjust/Import Look-Up Tables… (after a separator)`, then `Adjust/Browse Look-Up Tables…`. S18: `lutwindow importmenu` attaches the sheet on `import (2 of 2 tables)`; snapshot shows the Import Look-Up Tables page with Back; `back` gives `tables`; importing posts "[Import Look-Up Tables] Imported 2 look-up tables.". The open panel itself and Cancel: P6 | Pass; P6 open |
| E5 Adjust ▸ Reset Crop | Script | S5: menustate `resetCrop` false uncropped, true in a session with a crop and after Done; S4: false on a video. S12, key window: `menuitems Reset Crop` disabled uncropped, enabled after a crop. S13, key window: `menupress Reset Crop` leaves undo 'Reset Crop'; both `undo` and a posted ⌘Z (`menukey cmd+z`) bring the crop back (stack holds the 0.1/0.8 crop again; redo 'Reset Crop'). S7: same without a key window. Closes status.md's pending E5 check | Pass |
| E6 Adjust ▸ Show / Hide Mask Overlay | Script | S5: `maskSelected` false with no selection, true after `mask select 0`, `overlay true`. S12, key window: "Show Mask Overlay" disabled on a photo with no mask selected, enabled once a mask is added and selected, and "Hide Mask Overlay" after `menupress`. Closes the pending E6 check | Pass |
| E7 Mask and component limits | Test + Script | Test "New Mask and Add to Mask stop at the limits" (31/32 masks, 15/16 components). S5/S8: after 32 masks menustate `addMask false`; with Masks expanded, the five New Mask shape buttons are "disabled tip 'A photo can have up to 32 masks.'" and, on a 16-component mask, the five Add to Mask buttons are "disabled tip 'A mask can combine up to 16 shapes.'" | Pass |
| E8 View ▸ Play / Pause, Space | Script | S4: `playpause` takes `playing` from false to true. S12, key window: View/Play disabled on a photo. S14, key window: in the video loupe a posted Space (`menukey space`, through the event queue and the loupe's monitor) gives `playing true` and the item reads "View/Pause … enabled"; a second Space gives `playing false`. Partly closes the pending E8 checks: Play dimmed on a photo, the title flip and Space through the monitor are closed. "Space still opens the loupe from the grid" was not checked in a counted key-window run (S11's `key space` ran without activation): P5 | Pass; P5 open |
| E9 Video loupe context menu | Script | S4: `contextmenu video` lists Rating, Flag, Color Label, Add Keywords…, Suggest Keywords, Add to Album, then Play and Show Grid; no adjustment items and no Export…. After `playpause` it lists Pause. `contextmenu video Show Grid` returns to the grid. Real right-click and Control-click, and AVKit's bar: P4 | Pass; P4 open |
| E10 Edit ▸ Deselect All ⇧⌘A | Script | S9: `selectall` gives selection 10, then `deselectall` gives selection 1 with focus kept. S11, key window: "Edit/Deselect All key shift+cmd+a enabled" with 10 selected. As the engineer saw, a posted ⇧⌘A left the selection at 10 in a key window (posted ⌘Z does reach Undo, S13), so real keys are needed: P5 | Pass; P5 open |
| E11 File ▸ Stop ‹job› ⌘. | Test + Script | Suite "File ▸ Stop's job". S10: folder add gives `stop addFolders`, then an export gives `stop export`, and `stop` posts "Export stopped after 16 photos." and leaves `stop none`. S14, key window: during an export "File/Stop Export key cmd+"." enabled"; `menupress Stop Export` posts "Export stopped after 18 photos."; then "File/Stop … disabled". Closes the pending "Stop Export" check. "Stop Import" with the Import window key: P5 | Pass; P5 open |
| E12 Export enablement | Test + Script | Suite "Export enablement". S4: video focused gives `export false` and the cell's context menu has no Export…; a photo's has Export…. S11 and S12, key window: File/Export… disabled with a video focused, enabled on a photo. The toolbar's Export: P3 | Pass; P3 open |
| E13 Add Folder Without Copying… during imports | Script | S10: a second folder chosen while one imports joins the batch: "Add 2 Folders \| Folder 2 of 2 · 448 of 600". S14, key window: "File/Add Folder Without Copying… enabled" before and after an add. S15 caught the add running (`stop addFolders`, "Add Folder \| 192 of 600") but macOS did not activate the app (`key nil`), so "enabled during" in a key window was not seen; the item's only condition is `.disabled(!can())` (key window), with no import state. The test named in status.md doesn't test this change (Q1). Toolbar Import menu and the empty library's button: P3 | Pass; P3 open |
| E14 Export results in Activity only | Test + Script | Suite "Export results in Activity". S17a: 8 photos and 2 videos selected; one row, "Exported 8 photos.", none about videos, `sheet or alert none`. S17b: one original moved away, the other 7 outputs already present, `export run skip`: "[Export to “out4”] information: 7 photos were skipped because their files already exist.", then "warning: 1 photo could not be written. / IMG_00003.JPG: …"; no sheet or alert. The failure's reason text is wrong (Q3, existed before these changes). VoiceOver and the popover's layout: P8 | Pass; P8 open |
| E15 Suggest Keywords shows Info ▸ Keywords | Script | S21: Keywords collapsed (clicked its heading: `keywords expanded false`), loupe on the Adjust tab, `contextmenu loupe Suggest Keywords` gives `tab info keywords expanded true`. S9: from the grid with the inspector hidden, the cell's Suggest Keywords gives `inspector shown true tab info`. The toolbar palette item: P3 | Pass; P3 open |
| E16 "Caption" becomes "Description" | Test + Script | `LocalizationTests` pass; `grep -i caption Sources` finds no UI string (only `Caption` views, the loupe caption, a comment and the `.caption` field identifier); the removed catalog keys are gone. The preset editor's sections: P7 | Pass; P7 open |
| E17 One shared field-label set | Test | Suite "Field labels" (each descriptive field its own label; Changed on Disk uses the Info tab's label; preset editor fields one label each; every label used); `LocalizationTests`. The three surfaces on screen: P7 | Pass; P7 open |
| E18 Delete confirmations for presets | Person | P7 (the manager's ⋯ menu and the metadata preset editor can't be reached by the debug script) | Open |
| E19 Reset All Adjustments enablement | Script | S4: unedited photo in the loupe gives `resetAll false`, and `contextmenu loupe` has no Reset All Adjustments; S5: after a crop `resetAll true` and it is listed. S12, key window: "Adjust/Reset All Adjustments disabled" on an unedited loupe photo, which closes the pending check. In the grid the context menu still lists it for an unedited photo, as I12 rules | Pass |
| E20 Save Adjustments as Preset… enablement | Script | S4: video focused gives `savePreset false`, photo true; S16: unreadable stack in the loupe gives false. S11, key window: "Adjust/Save Adjustments as Preset… disabled" with a video focused | Pass |
| E21 RAW+JPEG Pair ▸ for pairs, with checkmarks | Test + Script | Suite "RAW+JPEG Pair menu state". S9: single JPEG gives `pair none`; pair on its RAW gives context "Show the RAW File checked"; on its JPEG, "Show the JPEG or HEIC File checked"; both pairs selected, both "mixed". S14, key window, menu bar: pair on its JPEG gives "Show the RAW File enabled", "Show the JPEG or HEIC File enabled checked"; with all selected both "enabled mixed". Closes the pending menu-bar check | Pass |
| E22 Toolbar Crop and Original on state | Person | S22: both items can be added (`toolbar add crop`, `add original`), but SwiftUI draws them with no AppKit button, so `toolbar` and `buttons` can't read the state: P3 | Open |
| E23 Import Selection enablement | Script | S19d: 3,000 shots selected: `copying false selectAll true deselectAll true`; right after `import start`: `copying true selectAll false deselectAll false`. The pull-down's items on screen: P9 | Pass; P9 open |
| E24 Add Folder panel prompt | Person | `ImportPanel.run` sets `panel.prompt` to "Add Folder" (code read). The panel's button: P6 | Open |
| E25 Remove Edit ▸ Find ▸ Clear Filter | Script | S1: `menuitems Find` lists Edit/Find and Edit/Find/Find… only; `menuitems Clear Filter` lists one item, View/Filter/Clear Filter | Pass |
| E26 View ▸ Info / Adjust checkmarks | Script | S11, key window, inspector on Info: "View/Info key opt+cmd+"1" enabled checked" | Pass |
| E27 User guide current | Script | `grep` of `docs/USER_GUIDE.md`: "⌘= and ⌘− … zoom in / out", "**File ▸ Stop Export**, **Stop Adding Folders** or **Stop Import**", "**Show Videos** in the Selection menu or the View menu", "**View ▸ Play / Pause**", "**Adjust ▸ Reset Crop**", "there is no alert" for export; no "Include videos" | Pass |
| E28 Dead Help item removed | Script, Person | AC1 and AC2 above | AC1 Pass; AC2 Open |

## Findings

**Q1 (low, test gap, E13).** `FolderImportQueueTests.aFolderChosenWhileOneImportsJoinsTheBatch`
does not fail without E13. It checks `FolderImportQueue`, which already
queued a second batch of drops before E13. E13's change is dropping the
"importing" dimming from the menu item, toolbar menu and empty-state
button, and no test covers that. The rule is inline `.disabled(!can())` in
PhotoApp, which has no test target. Expected: the test either names what
it covers (the queue, not the enablement), or the enablement lives in a
testable rule (as `ExportTargets.canExport` does for E12). Actual: status.md
lists the test as verifying E13. Verified here by script instead (S10,
S14).

**Q2 (low, debug script).** Read-only `adjust` subcommands open an undo
group. `adjust crop show` only prints, but the whole `adjust` verb is in
`changing` in `DebugScript`, so it leaves an empty undo step. Steps (S6,
run 6 in Scripts): `adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8;
adjust crop done; adjust crop reset; print undo; adjust crop show; undo;
print undo`. Expected: `undo` reverses Reset Crop. Actual: the undo
reverses the empty step, so "Reset Crop" stays on top and the crop does
not come back. That reads as a Reset Crop bug, but it isn't one: without
the `show` (S7) or from the menu in a key window (S13) the crop comes back.
This is the same class as the known empty steps from `key` and
`ml wait`/`ready`/`override`. `adjust crop begin` leaves one too (S7's last
undo shows `undo '' redo 'Crop'`). Also: `pgrep -f <bundle path>` matches
`timeout`/`open` wrappers as well as the app, so a script that
re-activates by PID needs the app's own PID.

**Q3 (low, existed before these changes; E14 surfaces it).** An export's
failure reason says the volume is not connected when the file is missing
from a connected volume. Steps (S17b): move one original
(`IMG_00003.JPG`) out of its folder, leave its volume (Macintosh HD)
mounted, and export it. Expected: a reason that says the file is missing
(the volume is connected). Actual: "IMG_00003.JPG: the volume “Macintosh
HD” is not connected." `ExportJob` maps `!item.isOnline`
(`FileManager.fileExists`) to `.offline(volumeName:)`, whose doc comment
covers both cases ("not mounted … or the file is gone"); the code is from
`20c213e` (2026-10-28). Since E14, this Activity warning is the only
report the person gets, so the wrong reason matters more now. Possibly a
Requirements/Design question for the wording (a string change).

Not observed here: the reported "saving an edit sometimes caches the old
look under the new hash" (no check here looked at rendered previews after
saving).

### Incident in this QA run (for the owner)

At 10:23:17 one of my re-activation calls, `open "<scratch>/Gus.app"`
(the re-run of `open` that CLAUDE.md suggests), ran after the scripted
instance had already quit. It started a new copy of the `.debugtest`
bundle with no arguments, and that copy opened the **default library**,
`~/Library/Application Support/Gus/Library`. I found it about 3 minutes
later and quit it with a normal quit Apple event
(`tell application id "me.sesser.gus.debugtest" to quit`). Read-only
`ls`/`find` afterwards showed that only `library.lock` and
`catalog.sqlite-shm` changed (both written when the library is opened).
`catalog.sqlite` (Nov 4 05:51) and `catalog.sqlite-wal` (Nov 5 16:52) are
unchanged, so it made no catalog writes, and nothing changed under
`~/Library/Caches/Gus`. Preferences went to the `.debugtest` domain. No
debug script ran in that copy.

Cause: re-running `open` on a bundle launches it if it isn't running. A
guard is to activate the running process by PID, and only while it runs.
`open` should never be re-run against a bundle after its scripted instance
may have quit. Recommendation for the owner, whose file it is: say so in
CLAUDE.md's debug-script paragraph. In later runs here (S15) I activated by
PID through System Events instead, which can't launch anything.

## Scripts

Setup: copies of `build/Gus.app` and `build/Gus Importer.app` (built by
`Scripts/build-app.sh all` at the commit above) in
`$Q=/private/tmp/claude-501/-Users-randy-Projects-Gus/ffe19c87-1232-45fa-9aaa-43df4389bead/scratchpad/qa/ui-redesign-reconcile`,
with bundle identifiers `me.sesser.gus.debugtest` and
`me.sesser.gus.importer.debugtest` (`plutil -replace`, then
`codesign --force --deep --sign -`). Scratch library `$Q/lib`. Sources came
from `photobench generate`:

- `$Q/src/Shoot/Shoot-001`: 6 JPEGs, 2 DNG+JPEG pairs, 2 videos (`--jpeg 6 --dng 0 --heic 0 --pairs 2 --videos 2 --video-seconds 4`).
- Big folders: 600 JPEGs each (`--jpeg-size 2400x1600`, renamed `FolderA`/`FolderB`; later `FolderC` to `FolderE` at other sizes).
- `CardH`: 3,000 JPEGs at 640x480 (`--jpeg 3000 --per-folder 3000 --jpeg-size 640x480`).
- One JPEG on a FAT32 image (`hdiutil create -size 40m -fs "MS-DOS FAT32" -volname QAOFF`), imported, then detached.
- Two `.cube` files (`LUT_3D_SIZE 2`) in `$Q/luts`.

Unless marked "key window", each script ran as
`"$Q/Gus.app/Contents/MacOS/Gus" --library-root $Q/lib --debug-script "<script>"`.
Key-window runs used `open -W -n --stdout <log> "$Q/Gus.app" --args --library-root $Q/lib --debug-script "<script>"`.
Note: project indexes move as folders are added; S11 to S13's `project 2`
pointed at FolderA, not Shoot-001, so their pair and video probes are not
counted (S14 repeats them with `project 3` checked by `print title`).

**S1. Import, Help, Find, look-up table items (run 1)**
```
wait 2; addfolder $Q/src/Shoot/Shoot-001; waitimport; wait 2; print items; print empty; helpmenu; menuitems Help; menuitems Find; menuitems Clear Filter; menuitems Look-Up; quit
```
Showed: `projects Shoot-001=10 | Imported: 12`; `help menu 'Help' in menu bar true items [] | menu bar [Gus, File, Edit, View, Photo, Adjust, Window, Help]`; `menu Help enabled` (the menu only); `Edit/Find`, `Edit/Find/Find…` only; `View/Filter/Clear Filter` only; `Adjust/Import Look-Up Tables… (after a separator)` then `Adjust/Browse Look-Up Tables…`.

**S2. Importer Help menu**, run with `"$Q/Gus Importer.app/Contents/MacOS/Gus Importer" --debug-script "…"`
```
wait 2; helpmenu; quit
```
Showed: `help menu 'Help' in menu bar true items [] | menu bar [Gus Importer, File, Edit, View, Window, Help]`.

**S3. Empty states (E1)**
```
wait 2; focus IMG_00001; album Empty Test; sidebar album 0; wait 1; selectall; remove; wait 1; print empty; snapshot $Q/e1-album.png; smartalbum Three Stars; sidebar smart 0; wait 1; print empty; snapshot $Q/e1-smart.png; sidebar builtin picks; wait 1; print empty; snapshot $Q/e1-picks.png; sidebar all; rating 5; wait 1; print empty; snapshot $Q/e1-nomatch.png; rating any; quit
```
Showed the four states and symbols in the AC table; I looked at all four snapshots.

**S4. Video, loupe and photo states (E2, E8, E9, E12, E19, E20)**
```
wait 2; focus MVI_00010; print menustate; contextmenu cell 0; focus IMG_00001; contextmenu cell 9; loupe; wait 2; print adjustments; print menustate; contextmenu loupe; grid; wait 1; focus MVI_00010; loupe; wait 3; print adjustments; print menustate; contextmenu video; playpause; print menustate; contextmenu video; contextmenu video Show Grid; wait 1; print menustate; quit
```
Showed: video in the grid gives `export false savePreset false`, and its menu has no Export…. Photo in the loupe gives `adjust tab ready`, `resetAll false`, and the loupe menu has no Reset All Adjustments. Video loupe gives `adjust tab video`, a menu that ends "Play, Show Grid", then `playing true` and "Pause", and Show Grid gives `mode grid`.

**S5. Crop, mask overlay, mask limits (E5, E6, E7, E19).** The 32 mask
adds and 15 component adds were built with
`M32=$(for i in $(seq 1 32); do printf 'adjust mask add linear; '; done)` and
`C15=$(for i in $(seq 1 15); do printf 'adjust mask component radial add; '; done)`:
```
wait 2; tab adjust; focus IMG_00002; loupe; wait 3; print menustate; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; print menustate; adjust crop done; wait 2; print menustate; contextmenu loupe; menuitems Reset Crop; adjust crop reset; wait 1; print undo; adjust crop show; undo; wait 2; adjust crop show; print menustate; adjust mask add radial; print menustate; adjust mask select none; print menustate; adjust mask select 0; adjust mask overlay on; print menustate; menuitems Mask Overlay; grid; wait 1; focus IMG_00003; loupe; wait 3; ${M32}print menustate; menuitems Gradient; buttons; adjust mask select 0; ${C15}buttons; quit
```
Showed `resetCrop` false, true, true; `resetAll` true after the crop, with Reset All Adjustments listed; `maskSelected` true, false, true; `overlay true`; after 32 masks, `addMask false`. The menu probes are dimmed with no key window. The undo here hit Q2.

**S6. Undo after Reset Crop, compared with after Crop (run 6)**
```
wait 2; focus IMG_00004; loupe; wait 3; print responder; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; wait 2; print undo; adjust crop show; adjust crop reset; wait 1; print undo; adjust crop show; undo; wait 2; print undo; adjust crop show; print adjustments; print menustate; grid; wait 1; focus IMG_00005; loupe; wait 3; adjust crop begin; adjust crop rect 0.2 0.2 0.6 0.6; adjust crop done; wait 2; print undo; undo; wait 2; print undo; adjust crop show; quit
```
Showed: undo of Crop works; "undo of Reset Crop" leaves 'Reset Crop' on top (Q2).

**S7. Undo of a change and of Reset Crop**
```
wait 2; focus IMG_00006; loupe; wait 3; adjust exposure 1; wait 1; print undo; print adjustments; undo; wait 2; print undo; print adjustments; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; wait 2; adjust crop reset; wait 1; print undo; undo; wait 1; print undo; undo; wait 1; print undo; adjust crop show; quit
```
Showed `undo 'Reset Crop'`, then `undo 'Crop' redo 'Reset Crop'`, then `undo '' redo 'Crop'` (an empty step from `crop begin`, Q2).

**S8. Masks heading expanded at the limits (E7)**
```
wait 2; tab adjust; focus IMG_00003; loupe; wait 3; scroll bottom; wait 1; buttons; click 1354 503; wait 1; scroll bottom; wait 1; adjust mask select 0; wait 1; buttons; quit
```
Showed the five shape buttons "disabled tip 'A photo can have up to 32 masks.'" and the five Add to Mask buttons "disabled tip 'A mask can combine up to 16 shapes.'".

**S9. Pairs, Deselect All, Suggest Keywords (E10, E15, E21)**
```
wait 2; print items; focus IMG_00001; print menustate; focus PAIR_00008; print menustate; contextmenu cell 2; pairfile jpeg; wait 1; print menustate; contextmenu cell 2; selectall; wait 1; print selection; print menustate; contextmenu cell 3; deselectall; print selection; pairfile raw; wait 1; focus IMG_00002; loupe; wait 3; tab adjust; print inspector; contextmenu loupe Suggest Keywords; wait 4; print inspector; grid; wait 1; inspector off; tab adjust; wait 1; print inspector; contextmenu cell 8 Suggest Keywords; wait 4; print inspector; quit
```
Showed `pair none`, `on/off` (RAW checked), `off/on` (JPEG checked), `mixed/mixed` (both mixed); `selection 10`, then `selection 1, focus 3`; `tab adjust`, then `tab info`; `shown false`, then `shown true tab info`.

**S10. Folder adds, Stop (E11, E13)**
```
wait 2; print menustate; addfolder $Q/src/Big/FolderA; wait 0.3; print activity; print menustate; menuitems Add Folder; addfolder $Q/src/Big/FolderB; wait 0.5; print activity; wait 2; print activity; menuitems Add Folder; waitimport; print activity; menuitems Add Folder; project all; wait 1; selectall; wait 1; export window; export close; export set dest=$Q/out1 size=full format=tiff bits=16; export run nowait; wait 1; print menustate; print activity; stop; wait 2; print menustate; print messages; quit
```
Showed `stop addFolders`; "Add 2 Folders | Folder 2 of 2 · 448 of 600"; "2 folders. Imported: 1,200."; `stop export`; "Export stopped after 16 photos."; `stop none`; `sheet or alert none`.

**S11. Key window, first attempt** (only its grid probes, taken before activation was lost, are counted: View/Info checked; Export… and Save Adjustments as Preset… disabled on a video; Deselect All enabled with 10; a posted ⇧⌘A left 10)
```
wait 4; print responder; project 2; wait 1; inspector on; tab info; wait 1; menuitems Info; focus MVI_00010; menuitems Export; menuitems Save Adjustments; focus IMG_00001; menuitems Export; menuitems Stop; menuitems RAW+JPEG; focus PAIR_00008; menuitems Show the RAW File; selectall; wait 1; print selection; menuitems Deselect All; menukey shift+cmd+a; wait 1; print selection; focus IMG_00006; key space; wait 3; print menustate; print responder; menuitems Reset All Adjustments; menuitems Reset Crop; menuitems Mask Overlay; menuitems Play; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; wait 2; menuitems Reset Crop; menupress Reset Crop; wait 1; print undo; print adjustments; menukey cmd+z; wait 2; print undo; print adjustments; adjust mask add radial; menuitems Mask Overlay; menupress Show Mask Overlay; wait 1; menuitems Mask Overlay; tab adjust; menupress Suggest Keywords; wait 3; print inspector; grid; wait 1; focus MVI_00010; loupe; wait 3; print responder; menuitems Play; key space; wait 1; print menustate; menuitems Pause; key space; wait 1; print menustate; grid; wait 1; addfolder $Q/src/C/FolderC; wait 0.5; print activity; menuitems Add Folder; waitimport; menuitems Add Folder; sidebar all; wait 1; selectall; export window; export close; export set dest=$Q/out2 size=full format=tiff bits=16; export run nowait; wait 1; menuitems Stop; menupress Stop Export; wait 2; menuitems Stop; print messages; menuitems Look-Up; quit
```
Lesson: `menuitems` straight after `focus` can read the previous focus; leave `wait 1` between them.

**S12. Key window, loupe menus (E5, E6, E8, E12, E19)**. In this run `project 2` was FolderA, so its pair probes are not counted.
```
wait 3; print responder; project 2; wait 1; focus IMG_00001; wait 1; menuitems Export…; menuitems Show the; focus PAIR_00008; wait 1; menuitems Show the; selectall; wait 1; menuitems Show the; focus IMG_00004; loupe; wait 3; print responder; menuitems Reset All Adjustments; menuitems Reset Crop; menuitems Mask Overlay; menuitems Play; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; wait 2; menuitems Reset Crop; menupress Reset Crop; wait 1; print undo; menukey cmd+z; wait 2; print undo; print adjustments; adjust mask add radial; wait 1; menuitems Mask Overlay; menupress Show Mask Overlay; wait 1; menuitems Mask Overlay; grid; wait 1; focus MVI_00010; loupe; wait 3; print responder; menuitems Play; key space; wait 1; print menustate; menuitems Pause; key space; wait 1; print menustate; quit
```
Showed (`key AppKitWindow` in the grid and the loupe): Export… enabled on a photo; in the loupe, Reset All Adjustments, Reset Crop, Show Mask Overlay and Play disabled; after the crop, Reset Crop enabled; then Show Mask Overlay enabled, then Hide Mask Overlay enabled. In this run the posted ⌘Z after Reset Crop left 'Reset Crop' on top; S13 repeats it with a key window throughout and passes.

**S13. Key window, undo paths (E5)**
```
wait 3; print responder; project 2; wait 1; focus PAIR_00008; wait 2; print menustate; menuitems RAW+JPEG; menuitems Show the; grid; focus MVI_00010; loupe; wait 4; print responder; print menustate; menuitems Play; menukey space; wait 2; print menustate; menuitems Pause; menukey space; wait 2; print menustate; grid; wait 1; focus IMG_00005; loupe; wait 3; print responder; adjust exposure 1; wait 1; print undo; menukey cmd+z; wait 2; print undo; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; wait 2; menupress Reset Crop; wait 1; print undo; undo; wait 2; print undo; print adjustments; menupress Reset Crop; wait 1; print undo; menukey cmd+z; wait 2; print undo; print adjustments; print responder; quit
```
Showed (key window from the loupe on): ⌘Z undoes 'Debug exposure'. `menupress Reset Crop` then `undo` gives `undo 'Crop' redo 'Reset Crop'`, with the crop back in the stack. `menupress Reset Crop` then posted ⌘Z gives the same.

**S14. Key window, pair menu, Space, Add Folder, Stop Export (E8, E11, E13, E21)**
```
wait 3; print responder; project 3; wait 1; print title; focus PAIR_00008; wait 2; print menustate; menuitems RAW+JPEG; menuitems Show the; selectall; wait 2; print menustate; menuitems Show the; focus MVI_00010; wait 1; loupe; wait 4; print responder; print menustate; menuitems Play; menukey space; wait 2; print menustate; menuitems Pause; menukey space; wait 2; print menustate; grid; wait 1; menuitems Add Folder; addfolder $Q/src/D/FolderD; wait 0.5; print activity; menuitems Add Folder; waitimport; menuitems Add Folder; sidebar all; wait 1; selectall; wait 1; export window; export close; export set dest=$Q/out3 size=full format=tiff bits=16; export run nowait; wait 1; print menustate; menuitems Stop; menupress Stop Export; wait 2; menuitems Stop; print messages; print responder; quit
```
Showed: title Shoot-001; "Show the RAW File enabled", "Show the JPEG or HEIC File enabled checked", then both "enabled mixed". Video loupe: after a posted Space, `playing true` and "View/Pause … enabled"; after the second Space, `playing false`. "Add Folder Without Copying… enabled" (activity had not shown the job yet at 0.5 s). "File/Stop Export … enabled"; menupress gives "Export stopped after 18 photos.", then "File/Stop … disabled".

**S15. Add Folder during an add, re-activation by PID**
```
wait 3; print responder; menuitems Add Folder; addfolder $Q/src/E/FolderE; wait 0.2; print menustate; print activity; menuitems Add Folder; wait 1; print activity; print responder; menuitems Add Folder; waitimport; menuitems Add Folder; quit
```
Showed `stop addFolders`, "Add Folder | 192 of 600"; `key nil` (macOS did not activate the app; not retried).

**S16. Adjust tab, offline and unreadable (E2, E20)**. Before it: `update version set editStack='{"operations":[],"schemaVersion":99}' where id=1` on the scratch catalog, OFF_00001.JPG imported from the disk image, then `hdiutil detach`.
```
wait 2; project 0; wait 1; print title; focus OFF_00001; loupe; wait 3; print adjustments; snapshot $Q/e2-offline.png; grid; wait 1; project 6; wait 1; print title; focus IMG_00001; loupe; wait 3; print adjustments; print menustate; grid; wait 1; focus IMG_00002; loupe; wait 3; print adjustments; quit
```
Showed `adjust tab offline`, `adjust tab unreadable(…newerVersion(99))` with `savePreset false`, and `adjust tab ready`. In the snapshot (looked at) the loupe has its Offline badge, and the glass inspector is blank as expected.

**S17a / S17b. Export reporting (E14)**
```
wait 2; project 6; wait 1; print title; selectall; wait 1; export window; export close; export set dest=$Q/out4 size=long:800; export run; print messages; quit
```
Then `mv` `IMG_00003.JPG` away and delete `out4/IMG_00003.tif`:
```
wait 2; project 6; wait 1; selectall; wait 1; export window; export close; export set dest=$Q/out4; export run skip; print messages; print activity; quit
```
Showed the rows quoted in the AC table (and Q3).

**S18. Import Look-Up Tables… (E4)**
```
wait 2; project 6; wait 1; focus IMG_00004; loupe; wait 2; lutwindow importmenu $Q/luts; wait 2; lutwindow page; lutwindow snapshot $Q/e4-import.png; lutwindow back; wait 1; lutwindow page; lutwindow importmenu $Q/luts; wait 2; lutwindow importrun; wait 2; print messages; luts; quit
```
Showed `page import (2 of 2 tables)`, then `page tables`; "[Import Look-Up Tables] Imported 2 look-up tables."; collection "Luts: QA_Cool, QA_Warm". The snapshot (looked at) shows Back, "Import Look-Up Tables" and both tables.

**S19d. Import window during a copy (E23)**
```
wait 2; import open; wait 2; import source $Q/src/H/CardH; import dest $Q/copydest3; print import; import start; print import; wait 0.2; print import; quit
```
Showed `selected 3000 … copying false selectAll true deselectAll true`, then `copying true selectAll false deselectAll false` twice. Smaller sets (600 and 120 shots) finished before the first probe.

**S20. Settings (E3)**
```
wait 2; menuitems Settings; menupress Settings…; wait 2; windowshot Settings $Q/e3-settings.png; quit
```
Showed two check boxes, "Open the import window when a card is inserted" and "Write XMP sidecar files when photos change" (looked at).

**S21. Suggest Keywords with Keywords collapsed (E15)**
```
wait 2; project 6; wait 1; focus IMG_00005; inspector on; tab info; wait 1; click 1365 356; wait 1; print inspector; loupe; wait 3; tab adjust; wait 1; print inspector; contextmenu loupe Suggest Keywords; wait 4; print inspector; tab info; wait 1; buttons; quit
```
Showed `tab info keywords expanded false`, then `tab adjust … false`, then `tab info keywords expanded true`.

**S22. Toolbar items (E12, E22)**
```
wait 2; project 6; wait 1; focus MVI_00010; wait 1; toolbar; focus IMG_00005; loupe; wait 3; toolbar add crop; toolbar add original; adjust crop begin; original on; wait 1; toolbar; adjust crop cancel; quit
```
Showed the items `export`, `crop` and `original` but no AppKit button in them, so there is no state to read.

**S23. Edit Smart Album… from the empty state (E1)**
```
wait 2; sidebar smart 0; wait 1; click 808 594; wait 2; print messages; export windowshot $Q/e1-editor.png; sheet none; wait 1; quit
```
Showed `sheet or alert SheetPresentationWindow`; the snapshot (looked at) is the "Edit Smart Album" sheet for Three Stars (Rating is at least ★★★).

## For a person

All on a scratch library, never your own: run a copy of the bundle with its
own identifier and `--library-root <scratch folder>`, as in Scripts. P1–P9
are on macOS 27; P10 repeats the short ones on macOS 15 and 26.

**P1. Help search, both apps (AC2, E28).** Library app: open Help in the
menu bar and type "Export". Look for File ▸ Export… offered in the results,
and highlighted in the File menu when you point at it. Help must have no
"‹app› Help" item. Standalone importer: open Help, type "Rescan", and look
for File ▸ Rescan offered and highlighted. No "‹app› Help" item there
either (the script already found none).

**P2. Adjust tab states in the inspector (E2).** Open the loupe on a video:
the Adjust tab shows "No Adjustments for Videos" with a video symbol. On a
photo whose volume is disconnected (detach a disk image after importing
from it): "Original Offline", "Connect its volume to adjust this photo.",
with a drive-and-x symbol. Opening the loupe on any photo shows no text
before the spinner. The Original toggle and ⋯ menu are hidden in each
state. Look for: centered system content-unavailable layout, legible on the
glass pane. (Unreadable "Can't Edit This Photo" needs a damaged stack; the
script showed it is chosen.)

**P3. Toolbar, glass (E12, E13, E15, E22).**
1. Grid, select only videos: the toolbar's Export item is dimmed. Select a photo: it is enabled.
2. While Add Folder Without Copying… is adding a large folder, the toolbar Import button's menu still offers Add Folder Without Copying… enabled. Also, with an empty library, the empty state's Add Folder Without Copying… button stays enabled after you start an add, until photos appear.
3. View ▸ Customize Toolbar…: add Suggest Keywords, Crop and Original. Click Suggest Keywords while the inspector shows Adjust: it switches to Info with Keywords expanded.
4. In the loupe, click Crop: its button shows the selected (on) bezel while cropping and goes back to off at Done. Click Original: on while the original shows, off after. Labels stay "Crop" and "Original".

**P4. Video loupe context menu, real clicks (E9).** In the video loupe,
right-click on the picture, then Control-click: each shows Rating, Flag,
Color Label, Add Keywords…, Suggest Keywords, Add to Album (and Remove
from Album in an album), then Play (or Pause while playing) and Show Grid.
Hover so AVKit's control bar shows and click its play button: AVKit's own
control acts, and no app menu appears over the bar.

**P5. Real keys (E8, E10, E11).**
1. Grid with several photos selected: press ⇧⌘A. The selection collapses to the focused photo.
2. Click into the toolbar search field, type, press ⇧⌘A: the grid's selection does not change. Same in the keyword entry (Photo ▸ Add Keywords…).
3. Import window key (File ▸ Import from Card or Folder…, a source with several shots): ⇧⌘A deselects its shots.
4. Start a copy and keep the Import window key: File shows "Stop Import ⌘." enabled, and ⌘. stops it.
5. Grid, a photo or video focused (the window key): press Space. The loupe opens, while View ▸ Play / Pause is still in the menu (E8).

**P6. Open panels (E4, E24).** Adjust ▸ Import Look-Up Tables… opens an
open panel on the library window. Cancel: nothing else opens. Choose a
folder with `.cube` files: the Look-Up Tables sheet opens on its Import
page. File ▸ Add Folder Without Copying…: the panel's default button reads
"Add Folder", not "Import".

**P7. Preset sheets and field labels (E16, E17, E18).**
1. Import window ▸ options ▸ metadata preset ▸ New Preset… (or Edit…): the editor's sections are Metadata and Contact; "Description" appears once, as a field label; the labels read Alt text, Extended description, Usage terms, Postal code, Email, State/Province, Country/Region (sentence-style).
2. The Info tab's Metadata and Contact use the same words.
3. Changed on Disk (make a sidecar change outside the app, then File ▸ Check for Changes on Disk): rows use the same words, plus Rating, Flag, Color label, Keywords.
4. Adjust ▸ Manage Presets… ▸ a row's ⋯ ▸ Delete…: an alert asks "Delete the preset “‹name›”?" with "Photos it was applied to keep their adjustments.", Delete and Cancel. Cancel keeps the preset; Delete removes it.
5. The metadata preset editor's Delete Preset…: the same question with "Copies already imported keep their metadata.". Cancel keeps it; Delete removes it.

**P8. Export results with VoiceOver (E14).** Export a selection where one
original was moved out of its folder. Open the Activity popover: the
warning row lays out its sentence and the file list on several lines
without clipping. With VoiceOver on, the warning's announcement is the
sentence ("1 photo could not be written."), not the file list.

**P9. Import window Selection pull-down during a copy (E23).** Start
copying a few thousand shots: the Selection pull-down's Select All and
Deselect All are dimmed, and the cell context menu's selection items too.
They are enabled again when the copy ends.

**P10. Other systems (macOS 15, macOS 26).** On each, with the bundle
built here: P1 (Help search in both apps), Settings shows two check boxes
(E3), P2's video state, and P3 step 1.

## Follow-up

None yet. Q1–Q3 go to the engineer; P1–P10 to `ui-redesign-onscreen-check`.

- 2026-11-06: Text corrections, no new runs. E8 is marked partly closed:
  "Space still opens the loupe from the grid" had no counted key-window
  run, so it is now P5 step 5 (P5 also cites E8). The Verdict now says
  P1–P10, matching "For a person".
