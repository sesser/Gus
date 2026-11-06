# Sharpening mask preview: QA

Owner: qa-tester. Date: 2026-11-06. Step 4 of `docs/WORKFLOW.md`.
Tested: `chore/project-cleanup` at `aee03c3ceea2599c37dfd370660b9c56b3a1f18f` (develop with PR #37's merge `64334b7` and ml-denoise on top), on an Apple M4 Pro, macOS 27.2 (26B123), bundle linked with the 27.2 SDK (`vtool -show-build`: sdk 27.2, minos 15.0). The main display reports EDR (`print hdr`: potential 4.18).

## Verdict

The feature passes everything a test or script can show. 11 of 14 acceptance criteria pass, and the 3 still open (AC4's drag, AC5's speech, AC13) need a person. QA closed two of the designer's checks (M7 and M8) and the active-window `menuitems` check that status.md had open. Seven checks are left for a person (P1–P7), plus one macOS 15 smoke test (P8). Nothing failed. Q1 is a serious cache bug that is not part of this feature. It showed up during these runs and still needs an owner.

## Acceptance criteria

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Test, Script | `SharpeningMapTests` "Masking 100 holds back the smooth region and keeps the edge; Masking 0 is full everywhere (AC1)". Script s2: at Masking 0 the photo area is 100% white (255,255,255) | Pass |
| AC2 | Test | `SharpeningMapTests` "The map equals the mask the sharpening step blends with (AC2)", 8 cases (4 Masking/Radius pairs × scales 1 and 0.5) | Pass |
| AC3 | Test, Script | `SharpeningMapTests` "Raising Masking never raises a pixel's mask (AC3)", 2 cases. Script s2: mean gray falls 255 → 4.4 → 3.4 → 2.3 → 1.7 → 1.0 for Masking 0, 10, 25, 50, 75, 100 | Pass |
| AC4 | Script, Person | Keyboard increments, script o3 (app active): with the value field focused, ↑ ↑ gives map frames at Masking 1 and then 2 ("map of applied values"). Committed steps, script s2: the map darkens step by step. A real drag at fit cannot be scripted (no key window for a slider drag) → P4 | Open (drag) |
| AC5 | Script, Person | Script o1/o3 (app active): Adjust ▸ Show Sharpening Map from the menu, ↑/↓ in Masking's value field, then Esc gives value field → loupe → map hidden ("Showing the photo.") → grid. Help search, Tab/Space and spoken output → P1, P3 | Open (person) |
| AC6 | Test, Script | `SharpeningMapTests` "At render scale 0.1 the map still shows Masking, where the renderer skips sharpening (AC6)". Scripts s2/s3: map shown and neutral at fit (0.311), 100% (1.000), 386% (3.857) and 800% (8.000). Snapshots line up with the photo at 100% and 386% | Pass |
| AC7 | Test | `SharpeningMapSessionTests` "After a pause the map is the full-resolution map, at 1:1 and downscaled at fit (AC7)", Masking 25/50/100. This tests the refiner's output; the editor's "after a pause" trigger is not observable (Q3) | Pass |
| AC8 | Test, Script | `SharpeningMapSessionTests` "Map frames never give a histogram and never count as the photo (R7, AC8)". Script s4: six toggles at fit and at 100% left the catalog row (stack, hash, `modifiedAt`), `sidecarQueue` (0) and all 44 cache files byte-for-byte unchanged; Undo stayed disabled. Script s5: one Undo after `adjust masking 60` restored 30 with the map still on; redo and undo follow. After hiding, the loupe, the new cached preview (2560 px) and the thumbnail are color photos, not maps (chroma 0.97). See Q1 for an unrelated stale-thumbnail bug seen in this run | Pass |
| AC9 | Script | s6: overlay suspended (menu state `overlay false`, snapshot 100% neutral, no red) and restored; Show Original suspended and restored, not restored after a Masking change; `original on` and `adjust mask overlay on` end the map; during crop the toggle is dimmed with "Finish cropping to show the sharpening map." and the context menu leaves the item out. o1 (app active, key window): the control drag with a brush mask painted a stroke (hash `9a38e0cd25e5` → `254afb55a715`); with the map shown, the same drag left the stack and hash `254afb55a715` unchanged | Pass |
| AC10 | Script | o4/s9: `accessibility AXImage` value "Sharpening map, 104 of 107" and "Sharpening map, no sharpening applied, 106 of 107". o4/o5: an arrow key, review and the grid end the map; o5b (relaunch): `asked false` | Pass |
| AC11 | Test, Script | `SharpeningMapTests` "Amount and the group's switch don't change the map (AC11)" and "Not applied only when nothing at all is sharpened (AC11's four cases)". Script s9: (a) "Sharpening Map · Not Applied" with "Amount is 0…"; (b) the same with "Sharpening is turned off…"; (c) group off and then Amount 0, each with Mask 1 at Sharpness 50: plain badge, no "no sharpening applied" in the VoiceOver value or the announcement, and the legend ends "Masks with Sharpness still sharpen the areas they cover."; (d) mask turned off: not applied again | Pass |
| AC12 | Script | o2 (app active, `key AppKitWindow` at every point): `menu Adjust/Show Sharpening Map disabled` for the video, the offline master (detached disk image) and the unreadable stack (`schemaVersion` 99); `sharpenmap on` does nothing. The unreadable row stayed at 99 | Pass |
| AC13 | Person | P5 | Open |
| AC14 | Test | `swift test`: 551 tests in 96 suites passed, 1 known issue (the existing "Live render session" one); `GoldenTests` pass; no golden changed since `c436d49`; `PreviewCacheKey.currentPipelineVersion` is still 6 | Pass |

### Design checks (design.md §12) and the designer's manual checks

| Item | How | Evidence | Result |
|---|---|---|---|
| DR1 | Script (app active) | o2/o3: grid disabled; editable loupe photo enabled, and after `menupress` the title flips to "Hide Sharpening Map" (o1); crop, review, video, offline and unreadable disabled. The item comes directly after Show Mask Overlay (o3 `menuitems`). This closes status.md's open "active-window `menuitems`" check | Pass |
| DR2 | Script, Person | Toggle under Masking, its state follows the menu, enabled at Amount 0 and with the group off, tooltips for crop and review (o2, o4). Height measured 24 pt on first layout and 20 pt afterwards (both accepted, D-Q2). Look → P2 | Pass (look open) |
| DR3 | Script, Person | Menu path, ↑/↓ and the Esc order scripted (o3). Help search and Tab/Space → P1 | Open |
| DR4 | Script, Person | Canvas value, the Show / Hide actions (run through `accessibility … Hide/Show Sharpening Map`), and announcements recorded (o4, s9). Speech → P3 | Pass (speech open) |
| DR5 | Script | Snapshots: neutral (max chroma 0) and the same frame as the photo at fit, 100% and 386% | Pass |
| DR6 | Test | "Mask 0, 0.5 and 1 show as 0, the interface's middle grey and white" | Pass |
| DR7 | Person | P4 (synthetic files refine too fast for the spinner) | Open |
| DR8 | Script | Overlay, Original, crop, New Mask, zoom keeps it, arrow, review, grid and relaunch all scripted. Paint ends the map through `addMask(.brush)`. Film strip: `focus 102` (`model.setFocus`, the call `FilmStripController.focus` makes) ends the map (s8). The click event itself could not be delivered: macOS left the app without key status (o5, o6) | Pass (see P1 step 6) |
| DR9 | Test, Script | AC11 | Pass |
| DR10 | Script | o4: inspector hidden on Info, `sharpenmap on` → inspector shown, Adjust, Details expanded, toggle at offset 228; hiding leaves it shown | Pass |
| DR11 | Person | P5 | Open |
| DR12 | Person | P6 | Open |
| DR13 | Test | `LocalizationTests`, `BrandingTests` pass; guide paragraph read | Pass |
| DR14 | Script | o3 | Pass |
| M1 | Person | P1 | Open |
| M2 | Person | P2 | Open |
| M3 | Person | P3 | Open |
| M4 | Person | P4 | Open |
| M5 | Person | P5 | Open |
| M6 | Person | P6 | Open |
| M7 | Script | Brush drag: o1 (app active). Film strip: s8 (same `setFocus` path); the physical click is one step in P1 | Pass |
| M8 | Script | s2/s3: fit, 100%, 386%, 800% | Pass |
| M9 | Person | P7 | Open |

### Review follow-ups (review.md "Fixes for the engineer")

1. The overlay now frees the refiner: done. s6 prints `fullResolution false` after `adjust mask overlay on` ends the map.
2. Guide wording: done. In USER_GUIDE.md, section "Importing and culling", the paragraph that begins "**Sharpening Map**: Masking (Details ▸ Sharpening) holds sharpening back…" now says "Press Esc, click the toggle, or choose **Adjust ▸ Hide Sharpening Map** to see the photo again." The D-Q1 sentence that follows it ("While the map is shown, hovering a preset or look-up table shows the map with it.") is there too.
3. Run `menuitems` with the app active, and add a D-Q1 script check: status.md records the D-Q1 check but left the menus unconfirmed. QA confirmed every state (DR1 above) and reran D-Q1 (s10: `frame map of other values masking 10`, then `map of applied values masking 85`).

## Findings

**Q1. Saving an edit can cache the previous look under the new edit hash (not this feature; needs an owner).**
- Steps (no sharpening map involved): run c2, then c3 (below). On IMG_00003, `adjust exposure 1.5`, wait 8 s in the loupe, go to the grid, then relaunch.
- Expected: the grid thumbnail and cached preview for the new hash `822f9568…` show the brighter photo.
- Actual: the loupe shows it brighter (mean 212/115/127), but `thumb/de/de71…-822f9568f0de6aea.jpg` is byte-identical to the unedited `…-6c76a50e5dc3f0cd.jpg`. The grid shows the old look, and it is still wrong after relaunch.
- It does not happen every time. It reproduced on IMG_00001 (no map), RAW_00005 and RAW_00006 (map shown, then hidden), and IMG_00003 (no map). IMG_00002 got a correct, brighter cache.
- Likely cause, from reading the code, not confirmed: `AdjustmentEditor.apply` calls `library.setEditStackHash` (the grid asks for the new key at once) while `persist` writes the stack to the catalog asynchronously. A thumbnail generated in between could read the old stack and store it under the new key.
- The map's own guarantee holds: no map frame ever reached the cache. This is a separate bug for the engineer and product manager to triage.

**Q2. ⇧↑ / ⇧↓ in a slider's value field may not step by 10 (existing code, but on design §8's keyboard path).**
- `SliderRow.control(_:textView:doCommandBy:)` (AdjustControls.swift:345) handles only `moveUp:` and `moveDown:` and reads `NSEvent.modifierFlags`. In a text view, Shift-arrow is bound to `moveUpAndModifySelection:` / `moveDownAndModifySelection:`, which falls through to `default`.
- Script o3: `key shift+up` and `key shift+down` left Masking at 2 (plain ↑ worked).
- Expected (design §8): ×10.
- Caveat: a scripted key is not a held hardware Shift, so P1 step 3 confirms it by hand.
- R3 and AC5 are still met with plain ↑/↓.

**Q3. Nothing observable shows that the frame on screen after a pause is the refined one (missing check, AC7/R6).**
- The AC7 test covers the refiner's pixels, and the editor that triggers it is in PhotoApp, which the tests can't link.
- `print sharpenmap` reports `refining` and `fullResolution`, but not whether the current frame came from the live session or the refiner, or its pixel size.
- Suggestion: add that to `print sharpenmap` (for example `frame map refined 6000x4000`), so a script can show the 150 ms pause → refined frame at fit and at 100%.

**Q4. Debug-script tooling: `key` always opens an undo group, so a key that changes nothing leaves an empty undo step.**
- o3 printed `undo ''` after `key shift+down` did nothing. This is the same class as the `ml wait`/`ml ready` note from the ml-denoise QA.
- It affects scripted undo checks only, not the app.

## Scripts

Setup (scratch only; nothing touched the owner's library or preferences):

```
Scripts/build-app.sh
cp -R build/Gus.app $S/ ; plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $S/Gus.app/Contents/Info.plist ; codesign --force --deep --sign - $S/Gus.app
.build/release/photobench generate --output $S/src --jpeg 4 --dng 2 --videos 1      (4 JPEG, 2 DNG, 100 HEIC, 1 MOV)
.build/release/photobench import --library-root $S/lib --source $S/src
hdiutil create -size 60m -fs APFS -volname QAOFFLINE $S/qaoffline.dmg ; hdiutil attach … ; photobench generate --output /Volumes/QAOFFLINE/off --jpeg 8 --dng 0 --heic 0 --videos 0
photobench import --library-root $S/lib --source /Volumes/QAOFFLINE/off ; hdiutil detach /Volumes/QAOFFLINE      (project 0 "off": offline)
sqlite3 $S/lib/Library/catalog.sqlite "update version set editStack=replace(editStack,'\"schemaVersion\":1','\"schemaVersion\":99') where id=1"      (IMG_00001 in project 1: unreadable)
```

Runs marked "exec" launch `$S/Gus.app/Contents/MacOS/Gus --library-root $S/lib --debug-script "<script>"`. Runs marked "open" launch `open -W -n --stdout <log> $S/Gus.app --args --library-root $S/lib --debug-script "<script>"`, so the app is active. `$O` is the output folder. Catalog and cache state was read with `sqlite3` (version row, `sidecarQueue`) and `stat` over `Previews/` before and after. Snapshot pixels were measured with a small CoreGraphics tool (mean RGB, white, black and chromatic fractions over the photo area).

- **s2 (exec)**: progressive map, zoom.
  `windowsize 1600 1000; wait 1; focus RAW_00005; loupe; wait 4; adjust amount 60; adjust masking 0; wait 2; snapshot $O/s2-photo-fit.png; sharpenmap on; wait 2; print sharpenmap; snapshot $O/s2-m000.png; adjust masking 10; wait 0.05; print sharpenmap; wait 2; snapshot $O/s2-m010.png; adjust masking 25; wait 2; snapshot $O/s2-m025.png; adjust masking 50; wait 2; snapshot $O/s2-m050.png; adjust masking 75; wait 2; snapshot $O/s2-m075.png; adjust masking 100; wait 2; print sharpenmap; snapshot $O/s2-m100.png; adjust masking 30; wait 2; print loupe; zoom; wait 3; print loupe; print sharpenmap; snapshot $O/s2-map-100pct.png; sharpenmap off; wait 2; snapshot $O/s2-photo-100pct.png; sharpenmap on; wait 1; optionscroll 1000 500 20; wait 3; print loupe; print sharpenmap; snapshot $O/s2-map-400.png; sharpenmap off; wait 2; snapshot $O/s2-photo-400.png; quit`
  - Results: mean gray over the photo area 255.0 / 4.4 / 3.4 / 2.3 / 1.7 / 1.0 (Masking 0/10/25/50/75/100), chroma 0 in every map; magnification 0.311 → 1.000 → 8.000, with the map on screen at each. At 100% the map's white edges line up with the photo's ellipse boundaries.
- **s3 (exec)**: the same start, then `zoom; optionscroll 719 389 3` three times.
  - Results: magnification 1.568, 2.460, 3.857. The map at 386% shows a white edge band exactly where the photo's boundary is in the following photo snapshot.
- **s4 (exec)**: toggles only.
  `windowsize 1600 1000; wait 1; focus RAW_00005; loupe; wait 4; print disk; print undo; print adjustments; sharpenmap on; wait 2; sharpenmap off; wait 2; sharpenmap toggle; wait 2; zoom; wait 3; sharpenmap toggle; wait 2; sharpenmap on; wait 2; sharpenmap off; wait 2; print undo; print adjustments; menuitems Undo; quit`
  - Results: `undo '-'` before and after; `Edit/Undo … disabled`; hash `29c02d5f41a2` before and after. The state diff (catalog row, `sidecarQueue`, 44 cache files with mtimes) was empty. Sidecar writing was on (`writes true`).
- **s5 (exec)**: undo with the map shown, then hide.
  `windowsize 1600 1000; wait 1; focus RAW_00005; loupe; wait 4; sharpenmap on; wait 2; adjust masking 60; wait 2; print undo; print sharpenmap; undo; wait 2; print undo; print sharpenmap; print adjustments; redo; wait 2; print sharpenmap; adjust exposure 1.2; wait 2; print sharpenmap; snapshot $O/s5-map-after-exposure.png; sharpenmap off; wait 3; print sharpenmap; snapshot $O/s5-photo-after-hide.png; grid; wait 4; print sharpenmap; snapshot $O/s5-grid.png; quit`
  - Results: `undo 'Debug masking'` → after Undo, `map of applied values masking 30` and `undo '-' redo 'Debug masking'`; Redo gives 60.
  - With the map shown and Exposure changed, the histogram stays (`histogram true`, ruling 5).
  - After hiding: a photo frame; the new cache files are color. The thumbnail kept the pre-exposure look (Q1).
- **c2, c3 (exec)**: Q1 without the map.
  - c2: `windowsize 1600 1000; wait 1; focus IMG_00003; loupe; wait 5; adjust exposure 1.5; wait 8; snapshot $O/c2-loupe.png; grid; wait 5; snapshot $O/c2-grid.png; quit`
  - c3: `windowsize 1600 1000; wait 1; focus IMG_00003; wait 5; snapshot $O/c3-grid-relaunch.png; quit`
  - Results: `cmp` shows the new-hash thumbnail identical to the old one, and the grid shows the unedited look after relaunch.
- **s6 (exec)**: overlay, Original, crop.
  `windowsize 1600 1000; wait 1; focus IMG_00004; loupe; wait 4; adjust amount 50; adjust mask add radial; adjust mask overlay on; wait 2; print sharpenmap; sharpenmap on; wait 2; print sharpenmap; print menustate; snapshot $O/s6-map-over-overlay.png; sharpenmap off; wait 2; print sharpenmap; adjust mask overlay off; original on; wait 1; sharpenmap on; wait 2; print sharpenmap; sharpenmap off; wait 2; print sharpenmap; sharpenmap on; wait 1; adjust masking 30; wait 2; sharpenmap off; wait 2; print sharpenmap; sharpenmap on; wait 2; original on; wait 2; print sharpenmap; original off; sharpenmap on; wait 2; adjust mask overlay on; wait 2; print sharpenmap; adjust mask overlay off; sharpenmap on; wait 2; adjust crop begin; wait 1; print sharpenmap; print menustate; sharpenmap on; wait 1; print sharpenmap; contextmenu loupe; adjust crop cancel; wait 1; print sharpenmap; contextmenu loupe; quit`
  - Results:
    - Overlay true → map shown (overlay false, menustate overlay false, snapshot all white with chroma 0) → hidden (overlay true).
    - Original suspended and restored (`original true`), and not restored after the Masking change (`original false`).
    - Original on, and the overlay on, each end the map (`fullResolution false`).
    - During crop: `canShowSharpenMap false`, toggle disabled with "Finish cropping…", `sharpenmap on` ignored, the context menu has "Finish Cropping" and no map item. After cancelling: "Show Original", "Show Sharpening Map", "Crop".
- **o1 (open, key window)**: menu, Esc, brush.
  `windowsize 1600 1000; wait 1; focus IMG_00004; loupe; wait 4; print responder; menuitems Sharpening; menupress Show Sharpening Map; wait 2; print sharpenmap; menuitems Sharpening; print announcement; key escape; wait 1; print sharpenmap; print announcement; menuitems Sharpening; adjust mask add brush; wait 1; print adjustments; drag 600 400 900 450; wait 2; print adjustments; sharpenmap on; wait 2; print sharpenmap; print responder; drag 600 500 900 550; wait 2; print adjustments; print sharpenmap; print loupe; quit`
  - Results: `key AppKitWindow`; Show (enabled) → Hide (enabled) after `menupress`; "Showing the sharpening map." → Esc → "Showing the photo."
  - The brush drag without the map painted (strokes added, hash changed); the drag with the map left hash `254afb55a715` and the strokes unchanged.
- **o2 (open, key window)**: menu state per state.
  `windowsize 1600 1000; wait 1; project 1; wait 1; focus IMG_00002; print responder; print menustate; menuitems Sharpening; loupe; wait 4; print responder; menuitems Sharpening; adjust crop begin; wait 1; print responder; menuitems Sharpening; buttons; adjust crop cancel; wait 1; review on; wait 1; print responder; print menustate; menuitems Sharpening; review off; wait 1; focus MVI_00107; wait 4; print responder; print menustate; menuitems Sharpening; sharpenmap on; wait 1; print sharpenmap; focus IMG_00001; wait 4; print responder; print adjustments; print menustate; menuitems Sharpening; sharpenmap on; wait 1; print sharpenmap; project 0; wait 1; focus IMG_00006; loupe; wait 4; print responder; print menustate; menuitems Sharpening; sharpenmap on; wait 1; print sharpenmap; quit`
  - Results: key window at every point. The item is disabled in grid, crop, review, video (`VideoLoupeHostView`), unreadable (`unreadable(newerVersion(99))`) and offline; enabled on the editable photo.
- **o3 (open, key window)**: menu order, value field, Esc order.
  `windowsize 1600 1000; wait 1; project 1; wait 1; focus IMG_00002; loupe; wait 4; menuitems; sharpenmap on; wait 2; editvalue Masking; wait 0.5; print responder; print sharpenmap; key up; wait 0.6; print sharpenmap; key up; wait 0.6; print sharpenmap; key shift+up; wait 0.6; print sharpenmap; key shift+down; wait 1; print sharpenmap; print undo; key escape; wait 0.5; print responder; print sharpenmap; key escape; wait 0.5; print sharpenmap; print announcement; key escape; wait 1; print menustate; quit`
  - Results: `Adjust/Show Mask Overlay` is followed by `Adjust/Show Sharpening Map`. First responder `NSTextView`. Masking 0 → 1 → 2 (map frames). ⇧↑ and ⇧↓ left it at 2 (Q2).
  - Esc → `LoupeHostView` (map still shown) → Esc → hidden, "Showing the photo." → Esc → `mode grid`.
- **o4 (open)**: context menu, VoiceOver actions, ends, reveal.
  `windowsize 1600 1000; wait 1; project 1; wait 1; focus IMG_00004; loupe; wait 4; contextmenu loupe Show Sharpening Map; wait 2; print sharpenmap; print announcement; accessibility AXImage; accessibility AXImage 0 Hide Sharpening Map; wait 1; print sharpenmap; print announcement; accessibility AXImage 0 Show Sharpening Map; wait 2; print sharpenmap; key right; wait 3; print selection; print sharpenmap; key left; wait 3; sharpenmap on; wait 2; print filmstrip; review on; wait 1; print review; print sharpenmap; inspector on; wait 1; print sharpenmap; review off; wait 2; sharpenmap on; wait 2; grid; wait 1; print sharpenmap; loupe; wait 3; print sharpenmap; inspector off; tab info; wait 1; print inspector; sharpenmap on; wait 2; print sharpenmap; sharpenmap off; wait 1; print inspector; focus IMG_00002; wait 3; sharpenmap on; wait 2; accessibility AXImage; print announcement; quit`
  - Results: the context menu shows the map. Canvas actions end with "Show Original, Hide Sharpening Map", and both actions work and announce.
  - The arrow ends the map (focus 103 → 104). Review ends it, and in review with the inspector brought back the toggle is disabled with "Exit Review (F) to show the sharpening map.". The grid ends it, and so does reopening the loupe.
  - Reveal from Info with the inspector hidden: shown, Adjust, offset 228.
  - Not-applied value and announcement on IMG_00002.
- **o5 / o5b**:
  - o5 (open): `windowsize 1600 1000; wait 1; project 1; wait 1; focus IMG_00004; loupe; wait 4; sharpenmap on; wait 2; print sharpenmap; print filmstrip; filmstripclick 102; wait 3; print selection; print sharpenmap; key right; wait 3; print selection; sharpenmap on; wait 2; review on; wait 1; print sharpenmap; review off; wait 1; sharpenmap on; wait 2; print sharpenmap; quit`
  - o5b (exec, relaunch): `wait 2; project 1; wait 1; focus IMG_00004; loupe; wait 4; print sharpenmap; print menustate; quit`
  - Results: review ends the map. After relaunch, `asked false`, `sharpenMap false`. The film strip click hit the cell but did not move focus.
- **o6 (open)**: the film strip retry.
  `windowsize 1600 1000; wait 1; project 1; wait 1; focus IMG_00004; loupe; wait 4; print responder; filmstripclick 102; wait 3; print selection; filmstripclick 103; wait 3; print selection; sharpenmap on; wait 2; print responder; filmstripclick 102; wait 3; print selection; print sharpenmap; quit`
  - Results: `key nil`. macOS did not activate the app, so even the control click did not move focus. Not retried further; o7 got `key nil` as well.
- **s8 (exec)**: the film strip's model path.
  `wait 2; project 1; wait 1; focus IMG_00004; loupe; wait 4; sharpenmap on; wait 2; print sharpenmap; focus 102; wait 3; print selection; print sharpenmap; quit`
  - Results: `asked true` → focus 102 → `asked false`.
- **s9 (exec)**: AC11.
  `windowsize 1600 1000; wait 1; project 1; wait 1; focus IMG_00004; loupe; wait 4; adjust amount 0; sharpenmap on; wait 2; print sharpenmap; print menustate; print announcement; snapshot $O/s9-a.png; adjust amount 50; adjust off sharpening; wait 2; print sharpenmap; accessibility AXImage; adjust mask select 0; adjust mask set sharpen 50; wait 2; print sharpenmap; print menustate; accessibility AXImage; sharpenmap off; wait 1; sharpenmap on; wait 2; print announcement; adjust on sharpening; adjust amount 0; wait 2; print sharpenmap; accessibility AXImage; snapshot $O/s9-c.png; adjust mask enable off; wait 2; print sharpenmap; accessibility AXImage; adjust mask enable on; wait 2; print sharpenmap; quit`
  - Results: as in the AC11 row. The snapshot shows the caption badge "Sharpening Map · Not Applied".
- **s10 (exec)**: D-Q1.
  `wait 2; project 1; wait 1; focus IMG_00003; loupe; wait 4; adjust amount 50; adjust masking 10; preset save QALow; adjust masking 85; wait 1; sharpenmap on; wait 2; preset preview QALow; print sharpenmap; preset previewend; print sharpenmap; preset delete QALow; quit`
  - Results: `map of other values masking 10`, then `map of applied values masking 85`; the map stays on.

Tests run: `swift test` (551 tests in 96 suites, 1 known issue) and `swift test --filter "SharpeningMapTests|SharpeningMapSessionTests|GoldenTests|LocalizationTests|BrandingTests"` (30 tests in 6 suites passed).

## For a person

Use the bundle from `Scripts/build-app.sh` on a scratch library. Each item lists the designer's check it covers.

- **P1 (M1, plus Q2 and DR8's film strip click). Keyboard only, default keyboard settings:**
  1. Open a photo in the loupe. Press ⌘?, type "sharpening" and press Return. The map shows, and Masking is in view.
  2. Click into Masking's value field. ↑ and ↓ step by 1, and the map follows each step.
  3. Press ⇧↑. Expected: +10. Record what happens (Q2).
  4. Press Esc twice. The first returns the keyboard to the loupe, the second shows the photo.
  5. Turn on System Settings ▸ Keyboard ▸ Keyboard navigation. Tab from Masking's value field reaches the Sharpening Map button, and Space toggles it.
  6. With the map shown, click a neighboring film strip thumbnail. The next photo shows as a photo, and the toggle is off.
- **P2 (M2). Toggle look on macOS 26:** in the inspector, the Sharpening Map toggle's bezel should match the Original toggle's height and style. Check it in the two layouts where it measures 24 pt and 20 pt (here it measured 24 pt on first layout and 20 pt after). Also look on macOS 27.
- **P3 (M3). VoiceOver:**
  - On the toggle, VO speaks "Sharpening Map" and its on/off state.
  - On the loupe, VO-Command-Space lists Show / Hide Sharpening Map.
  - Showing the map from the menu speaks "Showing the sharpening map." once, not overlapping with the canvas value.
  - With Amount 0 it adds "No sharpening is applied."
- **P4 (M4, AC4 drag, DR7). Real compressed 24 MP raw, at fit and at 400%:**
  - Drag Masking from 0 to 100. The map darkens continuously while dragging, with no spinner during the drag.
  - After release, the spinner appears only if the exact map takes more than half a second, then goes away.
  - Repeat with ↑/↓ steps.
- **P5 (M5, AC13, DR11). EDR display with an HDR photo:** use a gain-map HEIC or a floating-point DNG, with View ▸ Show HDR on. This Mac's display reports EDR (potential 4.18), so it qualifies.
  - With the map shown, its white equals the interface's white (compare with a white menu or inspector area).
  - The HDR badge is hidden while the map is shown and returns after.
- **P6 (M6, DR12). Increase Contrast, then Reduce Motion:**
  - The badge and the legend under the toggle stay legible.
  - Photo ↔ map swaps without animation.
  - Showing from the menu with Masking scrolled out of view jumps to it rather than scrolling.
- **P7 (M9). Real photos with smooth areas at the frame edge** (sky to the edge), Masking around 60 at fit: can you still see where the photo ends against the dark surround? If not, it is a follow-up design change, not a fix here. In the synthetic snapshots the black map against the surround is visible but faint.
- **P8 (no M-number; platform). macOS 15, earlier design:** smoke test on a Mac running macOS 15:
  - The toggle under Masking is clickable inside the inspector's scroll view.
  - The map shows and hides from the toggle, the menu and Esc.
  - The badge appears in the caption.

## Follow-up

Reruns after fixes, and P items as the owner reports them.

| Item | State | Notes |
|---|---|---|
| Q1 | Open | Not this feature; needs an owner and its own bug |
| Q2 | Open | Confirm by hand in P1 step 3 |
| Q3 | Open | |
| Q4 | Open | Tooling only |
| P1–P8 | Open | |
