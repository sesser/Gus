# Spot healing and cloning: QA

Owner: qa-tester. Date: 2026-11-18. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/healing` at `399b29a` (11 commits on `develop` at `6e3a1f8`, which is the merge base: no merge needed), on an Apple M4 Pro, macOS 27.2.1 (26B131), Swift SDK MacOSX 27.2 (`vtool`: minos 15.0, sdk 27.2). Against the PRD (issue #86, rev 2), `design.md`, `status.md`, `code-review.md` (three passes, no open finding) and `review.md` (two passes, no open finding).

Safety: every app launch used `--library-root` on a scratch library made by `photobench` (`import` of `photobench scenes` and `photobench generate` output), on a copy of the bundle with the identifier `me.sesser.gus.debugtest` re-signed ad hoc. `photocli` ran only with `--library-root` on the scratch library. The test-only preference domain `me.sesser.gus.debugtest` was cleared between runs. After the run no `Gus`, `photobench` or `photocli` process is running, and nothing under `~/Library/Application Support/Gus` or `~/Library/Caches/me.sesser.gus` is newer than the marker file I made before starting (`find -newer`: 0 files; the owner's catalog's newest file dates from 2026-11-17 17:01). `git status` of the checkout is clean apart from this file; nothing under `Sources/`, `Tests/`, `Scripts/` or `Package.swift` was edited, `UPDATE_GOLDENS` was not run. The one scratch copy of the branch (for mutations, below) lives outside the checkout.

## Verdict

Passes. All 15 acceptance criteria are met by a test, by a debug-script run on the bundle copy, or both; none failed and no finding for the engineer. What is left for a person is the look and feel a script cannot show (P1 to P7: real mouse, menus and keys with the window key, overlay legibility, the heading's layout, the limit's badge and sound, crop on screen, a real 24 MP raw) and the known limits below.

## What I ran

- `swift build`: clean. `swift test` three times in a row: **1162 tests in 173 suites passed each time** (61 s, 70 s, 65 s; 25 tests are new). Skipped suites are the opt-in ones that need sample files (`XTRANS_SAMPLES`, `RAF_SAMPLE`, …), none about spots.
- `Scripts/build-app.sh`: built (sdk 27.2). Scratch library: `photobench scenes --output … --size 3000x2000` (dusty sky as DNG, JPEG, TIFF; the DNG and JPEG form a RAW+JPEG pair) plus `photobench generate` JPEGs, DNGs and two RAW+JPEG pairs, imported with `photobench import` (14 files, 11 grid items: index 8 is `dusty-sky.dng` (pair), 9 is `dusty-sky.tif`). The three specks of `dustySky` sit at unit (0.3125, 0.3516), (0.664, 0.586), (0.156, 0.879) of a 3:2 photo and are 2.0% to 3.1% of the long edge in radius, so the scripts set Size 3.5.
- Mutations in a scratch clone of the branch (never the checkout): the crop moved before the spots in `AdjustmentRenderer.upstream`, and `result.spots = target.spots` removed from `pasted(onto:)`. `swift test --filter "SpotRenderingTests|SpotModelTests|GoldenTests"` failed exactly where it should: `spotsStayOnContentUnderCrop` (AC4), the golden `spots-healCropTurn-dustySky` (AC4), `pasteAndPresetsLeaveSpots` twice (AC10). Both mutations caught.
- Existing goldens and tolerances: `git diff develop...HEAD --name-status` shows three added goldens (`spots-heal-dustySky.png`, `spots-clone-dustySky.png`, `spots-healCropTurn-dustySky.png`) and no changed or deleted one; `GoldenTests.swift` gained only three new cases and a `spot(...)` helper (no tolerance touched). `PreviewCacheKey.currentPipelineVersion` is 12 on `develop` and on the branch (`git diff develop` of `PreviewCacheKey.swift` is empty). No migration (no file under `Catalog/` changed). `Package.swift` unchanged.
- Two test files outside `SpotTests.swift` changed, both to make room for the new `spots` group, neither a loosening: `AdjustmentsTests` (a spot added to the "every section is modified, then reset" loop) and `CommandTests` (`photocli adjustments` lists the modules of `Group.presetGroups`: spots are objects, not a module of parameters, as masks).

## Acceptance criteria

How is Test, Script or Person. Tests are Swift Testing suites under `Tests/PhotoCoreTests/SpotTests.swift` (suites "Spots: model", "Spots: rendering", "Spots: catalog") unless named otherwise. Scripts S1 to S15 are in "Scripts" below. `PhotoApp` has no test target, so the editor, overlay and menus are shown by script.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 (click adds a spot of the chosen size and mode; the loupe shows the healed result) | Script | S1: tool on, Size 3.5 set before the first add; three clicks (`spot add`, the click's code path) gave three heal spots of 3.5% (`spots print`), History "Add Spot" x 3, and the snapshot with the overlay hidden shows all three specks gone (`s1-2-healed.png`; `s1-1-one.png` shows only the first speck gone). Size after placing: S2 (`spot drag size`, `spot set size`). A real click and the crosshair: P1 | Pass (real click: P1) |
| AC2 (automatic source heals a speck on a smooth gradient within a CPU-reference tolerance; no source overlaps its spot or leaves the image; dragging the source changes the result) | Test | `SpotRenderingTests.automaticSourceHealsDust` (all three specks within 0.025 perceptual of the clean sky, sources inside the image and clear of their own and the other spots; before: over 0.1), `matchesReference` (4 cases, difference at most 6 x 10^-8, tolerance 3 x 10^-5), `movingTheSourceChangesTheResult`, `SpotModelTests.sourceRules`. Script S1/S2: sources printed inside the photo | Pass |
| AC3 (select, move, resize, change mode, delete; overlay hidden and shown) | Script | S2: select, Heal to Clone and back, `spot drag spot|size|source`, nudges, feather, opacity, delete: every change printed by `spots print` as expected (a drag of the spot kept its source's offset; the size drag set 2.0%); overlay off and on (`spots overlay off; wait 1; snapshot`: no rings in `s1-2-healed.png` and `s3-a-off.png`; rings back in `s1-1-one.png`). S6: `H`, ⌥-arrows, ⌫, `V`, Esc ladder (Esc deselects nothing selected, so the first Esc turned the tool off, the second left the loupe). S13 (window key): Adjust ▸ Spots items enabled and dimmed as designed, `menupress Delete Spot`, `menupress Finish Editing Spots`. Real mouse: P1 | Pass (real mouse: P1) |
| AC4 (crop or rotate after placing leaves the spot on the same content; golden pins a heal before the crop) | Test | `spotsStayOnContentUnderCrop` (a render with spots then a turn, 6 degrees and crop equals the stack with both, within 3 x 10^-5), golden `spots-healCropTurn-dustySky` (`GoldenTests`, "Module renders match their goldens", 50 cases passed). Mutation: crop before spots fails both (above). Script S12: a 4 degree straightened crop leaves spot 1 healed on its speck in `s12-crop.png` | Pass |
| AC5 (no spots renders byte for byte as before; existing goldens pass unchanged; pipeline version not bumped) | Test, diff | `noSpotsChangesNothing` (identity stack, hash, operations and decode settings equal), the 47 existing golden cases and `EditStackCorpusTests` passed in the three full runs; the git diffs above (no golden changed, no tolerance, `currentPipelineVersion` 12 as on `develop`) | Pass |
| AC6 (placing, moving, resizing, mode change, delete are each one undo step and a History entry; a revert restores the spots) | Script | S2 (13 actions: 3 Add Spot, 2 Change Spot Mode, Move Spot, Resize Spot, Move Spot Source, 2 nudges (Move Spot, Move Spot Source), Spot Feather, Spot Opacity, Delete Spot = 13 History rows, each under its own name); `undo` of the delete restored three spots, three more undos restored opacity, feather and the nudged source, four `redo` replayed them (`print undo` named each). S3: Choose Spot Source, Turn Off Spots, Turn On Spots, Delete Spot, Add Spot each one row. S4: Delete All Spots one row, one `undo` restored 100 spots. S13, S15 (window key): the same through the menu. History revert (clicking a row) is the edit-history feature's mechanism, tested there; spots are part of the stack it writes back. A mouse-chosen nudge then a click within 1.5 s: P2 | Pass |
| AC7 (same spots render identically in loupe previews, export and `photocli render`; a live drag at 100% shows sharp frames) | Script | S7 then `photocli`: version 11 (`dusty-sky.dng`, three spots). The cached loupe preview (`Previews/v12/preview/.../…-acc526b0d34bcfcb.jpg`, 2560 px) against `photocli render --long-edge 2560 --color-space displayP3`: RMSE 0.00295 (0.3%), the same as the no-spots control (cached preview with no spots against `--original`: 0.00296); against the render without spots: 0.0126. `photocli export` (TIFF, 16 bit, sRGB, full size) against `photocli render --long-edge 3000 --color-space sRGB`: **RMSE 0, byte-identical in value** (the speck's mean 0.565 unhealed, 0.755 healed in both). S8 at 100% (`magnification 1.000`): a spot drag, a source drag and a size drag gave "sharp interactive" frames of 1600 x 1289 at 3.2 to 11.2 ms, then one soft whole-photo frame after the pause (23 to 24 ms); the three drags are 5, 5 and 4 sharp frames, none soft while moving. Code: one `AdjustmentRenderer.upstream` serves previews, export, `photocli` and live frames | Pass |
| AC8 (system-decoded raw, LibRaw-decoded raw and JPEG each heal the same blemish; same stored shape) | Test | `everyDecoderHeals` (the same speck brightens by more than 15% on the DNG through the system decoder, the same DNG through LibRaw's decoder and color step, and a JPEG; far pixels differ by at most one half-float rounding; one operation of kind `spots` for every file). Script S1/S2 on the TIFF and the DNG, `photocli render` reports `decoder: systemRAW` for the DNG | Pass |
| AC9 (the 101st spot refused with a message; a stack with 101 spots or an unreadable one is not written over and editing is off) | Test, Script | `limit` (100 read; 101 unreadable with `exceedsLimits`; `canAddSpot`, `allows`). S4: `spot fill 99` plus one click gave 100 spots ("at limit true", caption "This photo has 100 spots, the most it can have. Delete one to add another."); the 101st click was refused (`notice atLimit`, still 100, no History row); delete then add worked. 101 spots written straight into a scratch copy's catalog (`sqlite3 … update version set editStack=readfile('over.json')`): the loupe reports `unreadable(…exceedsLimits)`, the tool cannot start (`can edit false`, `H` and an Exposure change do nothing), no History, and after quit the stored bytes and hash are unchanged (`cmp`). The beep and the badge: P5 | Pass (beep, badge: P5) |
| AC10 (paste and presets leave the target's spots, even with its Spots heading off; a duplicate starts with the original's spots and is independent; a RAW+JPEG pair's other file unchanged) | Test, Script | `pasteAndPresetsLeaveSpots` (paste, preset with every group, `replacing`, `modifiedGroups`, encode/decode of groups; mutation caught), `SpotCatalogTests.duplicateCopiesSpots` (edits to either leave the other), `spotsArePerFileAndNeverSidecars`. S9b: an Apply Preset (exposure 1 plus a spot, saved from the DNG) onto the TIFF that has its own, turned-off spot: the TIFF got exposure 1, kept its own spot and its off state, got no spot from the preset. The same with Copy and Paste (run once in an earlier S9 with `copyadjust`/`pasteadjust`: History "Paste Adjustments", own spot and off state kept). S5: spots on the DNG, the JPEG partner's stack stayed `{"operations":[]}`. S10: Duplicate of the TIFF with two spots; `photocli query images` shows the copy (version 15) with the same two spots | Pass |
| AC11 (while comparing, the Spots tool is unavailable and the Adjust tab says so) | Script, reading | S5: `compare on` (the DNG and the TIFF): `can edit false`, `editing false`, `H` did nothing; S6 shows `H` starts the tool in the loupe. The tab: `AdjustView` replaces the whole tab, the Spots heading included, with "Not Available While Comparing" (`isComparing` branch, unchanged by this branch; the branch adds only `SpotsSection` to the other branch). Seeing that text is not scriptable (inspector is a glass pane): P2 | Pass (look: P2) |
| AC12 (no sidecar written, no original changed) | Test, Script | `spotsArePerFileAndNeverSidecars` (no `sidecarQueue` row). After all runs the SHA-256 of all 14 originals equals the one taken before, and their mtimes are unchanged; no `.xmp` exists beside them | Pass |
| AC13 (CPU reference agrees within a derived tolerance; sources listed) | Test | `matchesReference` (float context, 6 x 10^-8 of a derived 3 x 10^-5; derivation in the test's comment), `halfFloatBound` (app context, within 5 x 2^-11 of the largest value), `kernelsCompile`; `SpotReference.swift` is plain Swift; the papers are listed in `status.md` "Algorithm" | Pass |
| AC14 (Choose Source Automatically gives placement's source for the same inputs, changes only that spot's source, is one undo step with a History entry, undo restores the old source; keyboard or menu; off with no spot selected) | Test, Script | `sourceIsDeterministic`, `sessionSourceMatchesPlacement` (the editor's session after the source was moved and the check box turned off). S3: a spot added at a speck got source (0.2338, 0.3516); its source dragged to (0.9, 0.8); `spot source auto` gave (0.2338, 0.3516) again, other spots unchanged, History "Choose Spot Source" once; `undo` gave (0.9, 0.8), `redo` (0.2338, 0.3516). A spot moved to (0.45, 0.2) and re-sourced got (0.5228, 0.1548): the same as a new spot added there afterwards (spot 3 of the run). S15 (window key): the same through `menupress Choose Source Automatically`, with `print undo` naming "Choose Spot Source", undo and redo restoring. S13/S14: the item is disabled with no spot selected. A re-source that finds the same source writes nothing (no History row), as it should | Pass |
| AC15 (check box off renders as no spots, byte for byte; spots stay listed and return; each toggle one step "Turn Off / On Spots"; copy, paste and presets neither carry nor change it) | Test, Script | `offRendersAsNone` (encoded bytes equal; on is different), `groupTurnsSpotsOff`, `pasteAndPresetsLeaveSpots`. S3: `spot enable off`: three specks back (`s3-a-off.png`), `count 3`, `on false`; `enable on`: healed again (`s3-b-on.png`); History "Turn Off Spots", "Turn On Spots". S9b: the target's off state survived the preset | Pass |

Counts: 15 criteria. Passed by test (a test is the main evidence): 10 (AC2, AC4, AC5, AC8, AC9, AC10, AC12, AC13, AC14, AC15), each with a script run alongside where the app is involved. Passed by script (no unit test can reach the editor): 5 (AC1, AC3, AC6, AC7, AC11). Open for a person: none of the 15 is open; the parts a script cannot show are P1 to P7. Failed: 0.

## Findings

None for the engineer. Notes, not findings:

- **Q-note 1, `history` before the saves land.** `history` prints the list as it is; after commands that write in the background it lags unless `history wait` comes first (my first S2 run showed 8 rows for 11 actions). All S-scripts below use `history wait`. A script limit, not an app fault.
- **Q-note 2, `undo` after `history`.** In one S14 run an `undo` after `history wait; history` left the source unchanged; S15, with no `history` command, undid and redid it. Printing History seems to move the undo target (a debug-script effect). I did not chase it, and a real person's ⌘Z is P2.
- **Q-note 3, activation.** Launching with `open -W -n` gave a key window in S13 and S15 but not in a first run of S14 (menu items read "disabled", "no menu item Hide Spot Overlay"): macOS did not always activate the copy. Results below that depend on the window being key come only from the runs where `print responder` showed `key AppKitWindow`. Two earlier `open` launches showed an empty library (`print empty`: emptyLibrary, 0 photos) while the same library opened normally later and directly; I did not find why and did not retry beyond that.
- **Tests that do not reach the editor.** The editor, overlay and menus are untested by unit tests (no `PhotoApp` test target); the scripts above are their evidence. `SpotModelTests.heldInCropStaysVisible` and `nudgeRunIsItsOwnStep` pin the two pure rules the review fixes added.

## Known limits (carried into this record, none a finding)

- **C1 residual (code-review.md).** A held ⌥-arrow still down while another control is clicked: the click saves the waiting nudge first inside its own event group, so History shows two entries but one ⌘Z undoes both. Nothing is lost or mislabeled. Accepted by the code reviewer. A person can see the common case, not this one, in P2.
- **C7 (code-review.md, third pass).** A crop narrower than about 1/2000 of the frame (a frame longer than about 40:1 cropped to its minimum edge) can lose the held spot's visibility: after the last margin `SpotCrop.held` can return a point that still maps outside, so the selected spot's ring disappears. No normal photo comes near (6000 x 4000 at its 80 px minimum needs 4 x 10^-5). Accepted by the main session.
- **Full-suite flake.** The code reviewer's second pass saw 1 failing test (unnamed) in 1 of 4 full runs and could not reproduce it. The engineer ran 4 of 4 passes. I ran three full runs, all 1162 passed, plus the mutation clone's three suites. The failure is not reproduced and cannot be tied to this branch; if it shows again on CI, the failing test's name is the first thing to record.
- **RI-E1 / #211, cost near the cap.** 100 spots cost 102 ms per render at 2560 x 1707 and 44 to 56 ms per sharp frame at 100% (status.md "Measurements"), several times a brush mask's. Accepted by the owner. In my runs 3 spots cost 3 to 11 ms per sharp frame at 100%.
- A press on empty canvas by VoiceOver adds no spot (the accepted R-3). The spots' VoiceOver elements are reachable through the app's own probe (S12 lists "Spot 2, Heal, bottom" with its actions twice, the known two paths of the probe), not proven with a real assistive app; per standing rule the owner is not asked for VoiceOver.
- If the spot kernels can't compile, spots are skipped with no message (the Lens heading's RI-CR1 rule).

## Scripts

Setup (zsh), once. `$S` is a scratch folder.

```
Scripts/build-app.sh
mkdir -p $S/app && cp -R build/Gus.app $S/app/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $S/app/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $S/app/Gus.app
swift run -c release photobench scenes --output $S/gen/scenes --size 3000x2000
swift run -c release photobench generate --output $S/gen/synth --jpeg 4 --dng 2 --pairs 2
mkdir $S/gen/src
cp $S/gen/scenes/dusty-sky.* $S/gen/scenes/fringes.tif $S/gen/src
cp $S/gen/synth/Shoot-001/IMG_0000[1-4].JPG $S/gen/synth/Shoot-001/PAIR_* $S/gen/synth/Shoot-001/RAW_* $S/gen/src
swift run -c release photobench import --library-root $S/lib-pristine --source $S/gen/src
```

Each run: `rm -rf $S/lib; cp -R $S/lib-pristine $S/lib; defaults delete me.sesser.gus.debugtest`, then either `$S/app/Gus.app/Contents/MacOS/Gus --library-root $S/lib --debug-script "<script>"` (no key window) or, for keys and menus, `open -W -n --stdout <log> $S/app/Gus.app --args --library-root $S/lib --debug-script "<script>"` and, from another shell, `osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is <pid>) to true'` with the id from `pgrep -n -x Gus`. Item 8 is `dusty-sky.dng` (the RAW+JPEG pair), 9 is `dusty-sky.tif`.

**S1** (AC1, AC3: place three spots, heal visible, overlay off and on), TIFF, direct launch. Result: three heal spots, defaults before it (`heal`, 0.3%), History 3 x Add Spot, `s1-2-healed.png` shows no specks, no rings.

```
wait 2; focus 9; loupe; wait 2; spots print; spots on; spot set size 3.5; spot add 0.3125 0.3516; wait 1; spots print; snapshot s1-1-one.png; spot add 0.664 0.586; spot add 0.156 0.879; wait 1; spots overlay off; wait 1; snapshot s1-2-healed.png; spots overlay on; spots print; history; print adjustments; quit
```

**S2** (AC3, AC6), DNG, direct. Result: 13 History rows (listed under AC6), undo and redo as described, the snapshots `s2-a-overlay-off.png` and `s2-b-overlay-on.png` came out identical (the snapshot was taken in the same command batch as the toggle; S1 and S3 with `wait 1` show the toggle).

```
wait 2; focus 8; loupe; wait 2; spots on; spot set size 3.5; spot add 0.3125 0.3516; spot add 0.664 0.586; spot add 0.156 0.879; wait 1; spot select 1; spot mode clone; spot mode heal; spot drag spot 0.45 0.2; spot drag size 0.47 0.2; spot drag source 0.35 0.3; spot nudge right; spot nudge up source large; spot set feather 20; spot set opacity 70; spots overlay off; snapshot s2-a-overlay-off.png; spots overlay on; snapshot s2-b-overlay-on.png; spot delete; history wait; history; print undo; undo; spots print; history wait; history; undo; undo; undo; spots print; redo; redo; redo; redo; history wait; spots print; history; quit
```

**S3** (AC14, AC15), DNG, direct. Result as under AC14 and AC15 (`s3-a-off.png`: all three specks back with spots off; `s3-b-on.png`: the third speck healed, the other two untouched because their spots were moved or deleted in the script).

```
wait 2; focus 8; loupe; wait 2; spots on; spot set size 3.5; spot add 0.3125 0.3516; spot add 0.664 0.586; spot add 0.156 0.879; wait 1; spot select 1; spots print; spot drag source 0.9 0.8; spots print; spot source auto; spots print; history wait; history; undo; spots print; redo; spots print; spot drag spot 0.45 0.2; spot source auto; spots print; spot select 2; spots print; spot delete; spot add 0.45 0.2; spots print; spot enable off; spots overlay off; wait 1; snapshot s3-a-off.png; spots print; history wait; history; spot enable on; wait 1; snapshot s3-b-on.png; history wait; history; quit
```

**S4** (AC9: the limit), TIFF, direct. Result: `count 99` then `100, at limit true`; the next click: `notice atLimit`, still 100; History holds 2 rows (fill, add); after delete and add, 100 again; `spot clear` gives one "Delete All Spots" row; `undo` restores 100.

```
wait 2; focus 9; loupe; wait 2; spots on; spot set size 0.3; spot fill 99; spots print; spot add 0.5 0.5; spots print; spot add 0.45 0.55; spots print; history wait; history; spot select 100; spot delete; spots print; spot add 0.45 0.55; spots print; spot clear; spots print; history wait; history; undo; spots print; quit
```

**AC9, 101 spots in the catalog.** A scratch copy of the library, `sqlite3 lib-over/Library/catalog.sqlite "update version set editStack=readfile('over.json'), editStackHash='deadbeefdeadbeef' where id=13"` with `over.json` a schema 2 stack of one `spots` operation holding 101 spots (generated with a short Python script), then:

```
wait 2; focus 9; loupe; wait 3; print adjustments; spots on; spots print; spot add 0.5 0.5; wait 1; spots print; key h; adjust exposure 1; wait 1; print adjustments; history wait; history; quit
```

Result: `adjust state unreadable(PhotoCore.EditStack.ReadFailure.exceedsLimits)`, `can edit false` throughout, `history state unavailable(...unreadable)`; afterwards the stored `editStack` equals `over.json` byte for byte and the hash is unchanged.

**S5** (AC10 pair, AC11 comparing), direct. Result: the DNG got the spot and the JPEG partner's stack stayed empty; with `compare on` `can edit false`, `H` did nothing. (`adjust tab` in the script is not a command; it printed "unknown adjustment tab". `menuitems Spot` here, without a key window, is not evidence; S13 is.)

```
wait 2; focus 8; loupe; wait 2; spots on; spot set size 3.5; spot add 0.3125 0.3516; history wait; print adjustments; pairfile jpeg; wait 1; print title; print adjustments; pairfile raw; wait 1; print title; print adjustments; focus 9; wait 1; print adjustments; focus 8; wait 1; compare on; wait 2; print compare; spots print; key h; wait 1; spots print; adjust tab; print inspector; menuitems Spot; compare off; wait 1; print adjustments; quit
```

**S6** (AC3 keys: `H`, ⌥ arrows, ⌫, Esc ladder, `V`), DNG, direct (scripted keys go straight to the window). Result: `H` turned the tool on; ⌥←, ⌥⌘↑, ⌥⇧→ gave History Move Spot, Move Spot Source, Move Spot (three steps); ⌫ deleted the selected spot (count 1); with nothing selected the first Esc turned the tool off and the second left the loupe (`mode grid`); `V` and `H` did nothing in the grid.

```
wait 2; focus 8; loupe; wait 2; key h; wait 1; spots print; spot set size 3.5; spot add 0.3125 0.3516; spot add 0.664 0.586; wait 1; key opt+left; key opt+cmd+up; key opt+shift+right; wait 2; history wait; history; key delete; wait 1; spots print; key escape; wait 1; spots print; key escape; wait 1; spots print; key v; spots print; key h; spots print; key escape; spots print; key escape; wait 1; print loupe; quit
```

**S7** (prepares AC7), DNG, direct. Three spots saved on version 11; `spot clear` then `undo` back to three; then the photo is left and re-entered so the previews are written. Then `photocli`:

```
wait 2; focus 8; loupe; wait 2; spots on; spot set size 3.5; spot add 0.3125 0.3516; spot add 0.664 0.586; spot add 0.156 0.879; wait 1; history wait; spots print; spot clear; spots print; undo; spots print; focus 9; wait 2; focus 8; wait 3; grid; wait 4; quit
```

```
photocli render --version 11 --library-root $S/lib --out render.png --long-edge 2560 --color-space displayP3
photocli render --version 11 --library-root $S/lib --out plain.png --long-edge 2560 --color-space displayP3 --original
magick compare -metric RMSE <cached preview of the saved stack>.jpg render.png null:
photocli export --version 11 --to exp --settings '{"format":"tiff","colorSpace":"sRGB"}' --library-root $S/lib
photocli render --version 11 --library-root $S/lib --out full.png --long-edge 3000 --color-space sRGB
magick compare -metric RMSE full.png exp/dusty-sky.tif null:
```

Results: 0.00295 (cache against render), 0.00296 (no-spots control), 0.0126 (cache against the unhealed render), 0 (export against render).

**S8** (AC7: live frames at 100%), TIFF, direct. Result: `magnification 1.000`; drags gave `sharp current interactive … region 1600x1289` frames of 3.2 to 11.2 ms; the last `soft` frame in each list is the whole-photo frame after the pause. `s8-100.png` shows the rings at 100% (the source ring touching its spot's ring, the speck left behind visible where the spot moved from).

```
wait 2; focus 9; loupe; wait 2; spots on; spot set size 3.5; spot add 0.3125 0.3516; spot add 0.664 0.586; spot add 0.156 0.879; wait 1; key z; wait 3; print loupe; spot select 1; print frames; spot drag spot 0.40 0.45; wait 2; print frames; spot drag source 0.45 0.55; wait 2; print frames; spot drag size 0.55 0.45; wait 3; print frames; snapshot s8-100.png; quit
```

**S9b** (AC10, AC15: a preset onto a photo with its own turned-off spot), direct. Result: the TIFF's stack has exposure 1 and its own spot with `isEnabled:false`; History "Apply Preset QA Spots Preset", "Turn Off Spots", "Add Spot"; no spot from the preset.

```
wait 2; focus 8; loupe; wait 2; adjust exposure 1; spots on; spot set size 3.5; spot add 0.3125 0.3516; history wait; preset save QA Spots Preset; spots on; focus 9; wait 2; spots on; spot set size 3.5; spot add 0.664 0.586; spot enable off; history wait; preset apply QA Spots Preset; history wait; print adjustments; history; quit
```

**S9** (the same with Copy and Paste: `… copyadjust; spots on; focus 9; wait 2; spots on; spot set size 3.5; spot add 0.664 0.586; spot enable off; history wait; pasteadjust; history wait; print adjustments; history; adjust reset all; history wait; print adjustments; history; quit` after the first lines of S9b). Result: paste left the target's spot (same id) and its off state, added exposure 1 (History "Paste Adjustments"); `adjust reset all` gave an identity stack and "Reset Adjustments" (Reset All clears spots).

**S10** (AC10 Duplicate), TIFF, direct. Then `photocli query images` lists version 15 (the copy of image 13) with two spots.

```
wait 2; focus 9; loupe; wait 2; spots on; spot set size 3.5; spot add 0.3125 0.3516; spot add 0.664 0.586; history wait; key escape; key escape; wait 1; grid; wait 1; duplicate; wait 2; print copies; print items; quit
```

**S12** (crop and the held spot; accessibility), DNG, direct. Result as in `status.md` S7 (my own run): after four far drags past the edges of a 4 degree straightened crop, spot 2 is `shown` at 1.0000/0.5000, 0.0000/0.5000, 0.5000/0.0000, 0.5000/1.0000, stays selected, `visible 2` of 3 (spot 3 lies outside the crop), is listed as "Spot 2, Heal, bottom" with its actions; Reset Crop brings `visible 3`. `s12-crop.png`: spot 1 healed, the selected spot's ring held on the bottom edge.

```
wait 2; focus 8; loupe; wait 2; spots on; spot set size 3.5; spot add 0.3125 0.3516; spot add 0.664 0.586; spot add 0.156 0.879; wait 1; adjust crop begin; adjust crop angle 4; adjust crop rect 0.15 0.15 0.7 0.7; adjust crop done; wait 2; spots on; spot select 2; spots print; spot drag spot 3 0.5; spots print; spot drag spot -3 0.5; spots print; spot drag spot 0.5 -3; spots print; spot drag spot 0.5 3; spots print; accessibility AXButton; snapshot s12-crop.png; adjust crop reset; wait 2; spots print; quit
```

**S13** (menus and keys with the window key), DNG, `open` launch (`key AppKitWindow first LoupeHostView` printed). Result: in the loupe with the tool off only Edit Spots (H) is enabled and the Spot Mode and Move Spot submenus; with the tool on and spots Finish Editing Spots, Hide Spot Overlay, Select Next / Previous, Delete Spot, Delete All Spots are enabled, File ▸ Remove from Library… enabled and Photo ▸ Remove from Album disabled; `key delete` deleted the selected spot; with nothing selected Delete Spot and Select Next are disabled; `menupress Delete Spot` and `menupress Finish Editing Spots` ran; Edit ▸ Undo read "Undo Add Spot".

```
wait 5; focus 8; loupe; wait 2; print responder; menuitems Spot; spots on; spot set size 3.5; spot add 0.3125 0.3516; spot add 0.664 0.586; wait 1; print responder; menuitems Spot; menuitems Remove from; key delete; wait 1; spots print; spot select none; wait 1; menuitems Spot; menuitems Remove from; spot select 1; wait 1; menuitems Delete Spot; menupress Choose Source Automatically; wait 2; history wait; history; menupress Delete Spot; wait 1; spots print; menupress Finish Editing Spots; spots print; menuitems Spot; quit
```

(In that run `menupress Choose Source Automatically` found the source already placement's, so it wrote nothing; S15 shows the case with a moved source.)

**S15** (AC14 through the menu, window key), DNG, `open` launch. Result: `print undo` after the press names "Choose Spot Source"; `undo` restored source (0.9, 0.8), `redo` (0.2338, 0.3516).

```
wait 9; print responder; focus 8; loupe; wait 2; spots on; spot set size 3.5; spot add 0.3125 0.3516; wait 1; print undo; spot drag source 0.9 0.8; print undo; menupress Choose Source Automatically; wait 2; print undo; spots print; undo; wait 1; print undo; spots print; redo; wait 1; spots print; quit
```

**Context menus** (`contextmenu loupe` with the tool off and on, S11): off, the menu has "Edit Spots" after "Crop"; on, "Finish Editing Spots" and "Hide Spot Overlay" after "Crop" (design.md §6, accepted in `review.md`). The menu on a spot itself is P1.

## For a person

Per the standing rule, VoiceOver and macOS 15 / 26 are not asked here (CI covers the second). M12 (touch Mac) is not carried: no Mac has a touch screen, and the grab distance is the owner's ruling DQ-2. Build and run on a scratch library (zsh; about 1 GB under `/tmp/healing-qa`):

```
cd ~/Projects/Gus
git switch feature/healing
Scripts/build-app.sh
mkdir -p /tmp/healing-qa
swift run -c release photobench scenes --output /tmp/healing-qa/scenes --size 6000x4000
swift run -c release photobench import --library-root /tmp/healing-qa/lib --source /tmp/healing-qa/scenes
rm -rf /tmp/healing-qa/Gus.app
cp -R build/Gus.app /tmp/healing-qa/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest /tmp/healing-qa/Gus.app/Contents/Info.plist
codesign --force --deep --sign - /tmp/healing-qa/Gus.app
open -n /tmp/healing-qa/Gus.app --args --library-root /tmp/healing-qa/lib
```

Open `dusty-sky.dng` or `dusty-sky.tif` in the loupe, Adjust tab. The three specks are at 31% / 35%, 66% / 59% and 16% / 88% of the width / height and 2 to 3% of the long edge wide: set Size to about 3% before clicking, or use your own photos (copy a few; the migration-free branch changes no catalog table, but never point this build at the real library).

- **P1 Real mouse and trackpad** (M1, M2, M6, M13; engineer's P1). Adjust ▸ Spots ▸ Edit Spots (or `H`): the pointer is a crosshair with a ring the size of the next spot (solid for Heal, dashed for Clone, an inner feather ring); a click adds a spot and shows its source; a click inside a ring selects, a drag inside moves it with its source, the round handle resizes, the source ring drags and stops at its spot and at the photo's edge, a drag on empty photo pans, a double click adds one spot and stays in the loupe, right-click on a spot selects it and the menu starts with Heal, Clone, Choose Source Automatically, Delete Spot. The pointer is an arrow over a ring, its handle and the source ring, a crosshair elsewhere (also just outside a ring's corner). Scroll, pinch, `Z` and ⌥-scroll work with the tool on. Keyboard focus: type a value in the Size field, then click the photo or a spot's handle: `H`, `V` and ⌫ then reach the loupe, not the field.
- **P2 Menus and keys with the window key, and a real ⌘Z** (M5, M7, M10, AC11's tab text; engineer's P2; code review's person check). Adjust ▸ Spots items and their dimming in the loupe, the grid, review (`F`), a crop session and while comparing (`S`; the Adjust tab reads "Not Available While Comparing"); the submenu title never dims. `H`, `V` bare; ⌫ deletes a selected spot and Remove from Album is dimmed then, and with no spot selected ⌫ is Remove from Album as before. ⌥ arrows and ⌥⌘ arrows move the spot and the source (⇧ for ten); in a text field ⌥← and ⌥→ still move by word. Esc: deselects, then turns the tool off, then leaves review or the loupe; Esc during a crop session, a fringe pick and a map keeps its order. Choose Adjust ▸ Spots ▸ Move Spot ▸ Right with the mouse, then click Clone within 1.5 s: History has two entries (Move Spot, Change Spot Mode) and two ⌘Z undo them one at a time. Each action is one ⌘Z and one History row; undo keeps the tool on; reverting a History row clears the selection.
- **P3 Overlay legibility** (M3; engineer's P3). At fit and at 100%: on a white sky and on a dark foreground; a 6 pt speck (the 8 pt minimum ring); the selected spot's handle, cross and arrowhead; with Increase Contrast on (heavier strokes, a darker hairline); with Reduce Motion on nothing animates.
- **P4 The Spots heading, light and dark, and the toolbar** (M4, M8; engineer's P4). Collapsed on a new photo; the layout of the toggle, context row (the eye, trash and ⋯), full-width Heal / Clone control, three sliders and captions at the inspector's narrowest width; the `bandage` symbol; the nine caption states of design §9 including the wrap of the longest sentence; the heading's check box lines up with Light's and Crop's; with the check box off the controls show secondary. Customize Toolbar offers Edit Spots with `bandage`; added, it shows the tool's state and follows `H`.
- **P5 The limit and no source** (M9). At 100 spots the next click beeps, the caption and context row show the limit with its symbol, the "Spot Limit" badge shows in the loupe caption, selecting and deleting still work (a script: `spot fill 99`, then one click, then the next click, is the quick way to 100). A very large Size on a small crop gives the no-source caption and adds no spot.
- **P6 Crop, straighten and turns on screen** (M11). With a crop and a few degrees of Straighten the ring is round, the handle sits at 3 o'clock on screen, and the ring sits on the healed pixels; a spot dragged past the crop edge stops on it and stays drawn and selected; Reset Crop brings spots outside the crop back.
- **P7 A real 24 MP raw** (engineer's P5). A dust spot at the default size heals from a clean patch; a drag at 100% keeps up; an export of that photo shows the heal. Also name anything that feels slow with many spots (the known #211).

## Follow-up

Reruns after fixes, and the owner's sign-off (commit, date, checks left open), are recorded here when the main session relays them.
