Issue: #218

# Black & White module (film filters): QA

Owner: qa-tester. Date: 2026-11-18. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/bw-module` at 7c321aa (sources as of 9e7bfe9; 7c321aa adds only reviews), on an Apple silicon Mac, macOS 27.2.1 (26B131), bundle linked with SDK 27.2, minos 15.0 (`vtool -show-build`).

**Owner's library: one thing to know.** After the run, `~/Library/Application Support/Gus/Library/catalog.sqlite-shm` has a newer modification time (21:23:24, then again 21:30:54 when I repeated the command to find the cause). `catalog.sqlite` (Nov 17 13:50) and `catalog.sqlite-wal` (Nov 17 17:01) did not change, and no other file in the folder is newer than my start. The cause is my own `photocli render --input <file> --out <png>` calls, which I ran without `--library-root`: `photocli render --input` opens the default library (a read; it touched the shared-memory file only). Every app launch, `photobench` and every other `photocli` call passed `--library-root` on a scratch library. No Gus process was left running. See Q2.

## Verdict

Passes. All 14 acceptance criteria are met by tests or by scripted checks against a copy of the bundle on a scratch library; the full `swift test` passed on the first run (1189 tests in 174 suites), the no-change gesture records nothing, the labels, `photocli develop`'s `on` rules and the Color Fringes swatch colour behave as ruled, and 17 of 17 mutations of the behaviour were caught by the tests. What is left is what a person has to see (look, tints, menu enablement with a key window, a real click that moves nothing, strength on real photos): P1 to P12.

## Acceptance criteria

How: Test, Script or Person. Scripts are S1 to S8 below. "Test" names are in the suite `Black & White` (`BlackAndWhiteTests`) unless said.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 (R1, R13): off or never touched renders as before | Test | `offRendersNothing` (3 scenes: off, never used and turned off are byte-identical to no module); `EditStackCorpusTests` and `GoldenTests` pass; no existing golden or fingerprint file changed (see AC13). Mutation M1 and M11 fail it | Pass |
| AC2 (R3): on, sliders 0: R = G = B = Rec. 709 luminance | Test | `luminanceMix` (4 scenes, exact R = G = B and equal to the CPU reference `BlackAndWhiteReference` within the derived tolerance). Mutation M5 (Rec. 2020 weights) fails it. Script S7: `photocli render` with `on` gives R = G = B on seven sampled points | Pass |
| AC3 (R4): neutral grey keeps its level | Test | `neutralsKeepTheirLevel` (9 mixes, chart neutrals, grey ramp to 4.0). Mutation M4 (no normalisation) fails it | Pass |
| AC4 (R5): direction, and against the reference | Test | `directions` (each filter on the red, green, blue, yellow and sky patches; Red darkens blue more than Orange, Orange more than Yellow) and `mixesMatchReference` (27 cases). Mutation M7 (Red passes blue) fails `directions`. Script S7 shows it on a rendered photo: Red darkens the blue-green ellipse and the sea-green, lightens the tan one; Blue does the opposite | Pass |
| AC5 (R2): 0 to 100, refuses outside, reads back | Test | `amountsAreRangeChecked` (model refuses out-of-range, NaN, infinity; `photocli` parser too). Script S3: `photocli develop --set blackAndWhite.red=150` gives `invalidEdit … outside 0.0 … 100.0`. Mutation M8 fails it | Pass |
| AC6 (R6): quick-set is one undo step | Script, Test | S2: `adjust bw filter red` on yellow 30 / blue 20 gives red 100 and the rest 0 with `quickSet red segment 2`; one `undo` restores yellow 30, blue 20, on; `redo` brings red back; three undos return to the identity stack. `quickSets` pins the values. The control's look and a real click are P1, P3 | Pass |
| AC7 (R7): after the Color Mixer, before Vibrance, Saturation and Color Grading | Test | `colorMixerFeedsTheMix` (mixer luminance moves the grey; group off gives exactly the mixer-only render), `stepsAfterIt` (Color Grading tints the grey; Saturation +60 and Vibrance +40 leave every grey value unchanged). Mutation M2 (step before the mixer) fails the first; M3 (step after Saturation) fails the second | Pass |
| AC8 (R8): no clipping, R = G = B | Test | `luminanceMix` and `mixesMatchReference` (ramp to 4.0 kept, brightest pixel above 3.9). Mutation M6 (clamp in the group) fails both | Pass |
| AC9 (R9): every decoder; video skipped | Test, Script | `everyDecoder` (JPEG, LibRaw-decoded raw, system-decoded DNG: each equals the reference applied to that decoder's colour render). S6: a paste of the group over a select-all of 14 photos reaches JPEG, HEIC, DNG and the RAW of the pair and skips the video (`photocli query images` after: the video has no operation). The test uses fixtures, not a real camera raw | Pass |
| AC10 (R10): global only, masks render over it | Test | `notALocalControl`, `masksWorkOnTheGray`, `maskWhiteBalanceTints` (owner ruling DQ-1) | Pass |
| AC11 (R11): copy/paste, preset, batch are one undo step; copy independent | Test, Script | `presets`, `paste`, `copiesAndBatches` (virtual copy starts equal then changes alone; a preset over two photos is one write). S6: a paste over 12 photos is one step ("Paste Adjustments"); one `undo` returned all 12 to no operation. The preset path's single step is the same `changeAdjustments` path; not separately scripted | Pass |
| AC12 (R1, R12): check box = on with all 0; reset is identity; the three labels | Test, Script | `stackRepresentation` (`{on:true}`, non-identity hash), `checkBox`, `resetIsIdentity`. S2 and S3: toggle on a fresh photo gives `on true`, all 0, stack `{"on":true}`; History rows read "Turn On Black & White", "Black & White Filter" (slider, quick-set and No Filter), "Turn Off Black & White", "Reset Black & White"; after reset the stack is `{"operations":[],…}` and the hash is `6c76a50e5dc3`, the same as a never-edited photo. The PRD's "Turn On / Off" is "Turn On" / "Turn Off" in the app, as the owner accepted in the design wording. Mutations M11 and M16 fail the tests | Pass |
| AC13 (R13): no pipeline bump, no golden moved | Test, Script | `pipelineVersionUnchanged` (>= 12); `git diff develop HEAD`: `PreviewCacheKey.swift` untouched (`currentPipelineVersion = 12`), no migration file, no `Package.swift` or `Scripts/` change, Tests/PhotoCoreTests/Goldens: 3 files added (`blackAndWhite-noFilter-patchChart`, `-red-hazyLandscape`, `-yellowGreen-hueRamp`), 0 modified or deleted, no `.fingerprint.json` touched. `GoldenTests`: 53 module cases pass. The three new goldens are all grey, looked at | Pass (RAW goldens: see Q4) |
| AC14 (R14): grain stays neutral | Test | `grainStaysGray` (two grain settings and a vignette: every pixel exactly R = G = B) | Pass |

Counts: 14 ACs, 14 Pass, 0 Fail. Passed by test alone: 10 (AC1, 2, 3, 4, 5, 7, 8, 10, 13, 14). Passed by test plus a script check that decides part of it: 4 (AC6, AC9, AC11, AC12). Open for a person: none of the ACs on its own, but P1 to P12 below cover what the scripts can't see.

### Other checks asked for

| Check | How | Result |
|---|---|---|
| No-change gesture records nothing (F1, C1) | Script S1, Test `noChangeGestureChangesNothing` | Pass. On a fresh photo `adjust bw set red 0`, `set yellow 0`, `set blue 0`: `on false`, stack hash and JSON unchanged, History 0 entries. `set red 20` then gives `on true`, one entry; `set red 20` again adds no entry (still 1). `print undo` before: `'-'`; after: `''` (an unnamed group). That is the script's own empty undo group, as the engineer noted: `adjust exposure 0` on a fresh photo, an unrelated group, gives the same `''` (S1 control). So the evidence is the stack, the hash and History, not the undo name. Mutation M9 (the C1 bug back) fails the test |
| On / off / reset / History labels | Script S3 | Pass (above) |
| `photocli develop` `on` rules (C2, C3) | Script S4, Test `scriptedOnState` | Pass: 11 cases on a photo that never had the group and on one at `{on, red 100}`; table below. Mutations M13 and M14 fail the test |
| Three new goldens present, nothing else moved | git diff, Test | Pass (AC13) |
| Color Fringes swatch colour (owner ruling) | Script S5, Test `fringeSwatchesKeepColor` | Pass. Purple slot swatch is `0.4257,0.2014,0.7279` before B&W, with Red 100 on, with it turned off and on again; Saturation -100 then makes it grey (`0.2870` each), as the designer noted. Mutation M15 fails the test |
| Monochrome caption | Script S8 | Pass: a gray JPEG reads `caption monochrome`; colour JPEG, raw DNG, the pair's DNG and a video read `static` |
| Mutation checks | Scratch copy outside the checkout | 17 of 17 killed (table below) |
| `DeferredRenderTests` | Rerun | Passed in the full run (1 of 1) and alone 3 of 3 (5 tests each, about 2 s). No failure seen, so nothing to count beyond that; the engineer recorded 2 failures in 3 full runs earlier |

### `photocli develop` `on` rules (S4)

| Command (`--dry-run`) | Fresh photo | Photo at `{on, red 100}` |
|---|---|---|
| `--set blackAndWhite.red=40` | `{on, red 40}` | `{on, red 40}` |
| `--reset blackAndWhite --set …green=50` | `{on, green 50}` | `{on, green 50}` |
| `--reset all --set …red=40` | `{on, red 40}` | `{on, red 40}` |
| `--reset blackAndWhite.on --set …red=40` | `{red 40}` (color) | `{red 40}` (color) |
| `--set …on=false --set …red=40` | `{red 40}` (color) | `{red 40}` (color) |
| `--set …on=true` | `{on}` | `{on, red 100}` |
| `--set exposure.ev=1` | exposure only | exposure; B&W unchanged |
| `--set …red=150` | refused (`invalidEdit`) | refused |
| `--set …red=0` | `{on}` (grey, as the user guide says) | `{on}` |
| `--reset blackAndWhite` | no change | identity |

The result no longer depends on what the photo held, which was C2.

### Mutation checks (scratch copy outside the checkout)

A copy of `HEAD` made with `git archive` in the scratchpad, each change made to one line, `swift test --filter "BlackAndWhiteTests|AdjustmentsModelTests|AdjustmentParameterTests"` run, the line restored. Baseline: 41 tests pass.

| # | Mutation | Caught by |
|---|---|---|
| M1 | the conversion never runs | 8 tests (luminanceMix, directions, mixesMatchReference, masks, grain, mixer, decoders, grading) |
| M2 | step before the Color Mixer | `colorMixerFeedsTheMix` |
| M3 | step after Vibrance and Saturation | `stepsAfterIt` |
| M4 | weights not normalised | `neutralsKeepTheirLevel` and 3 more |
| M5 | Rec. 2020 weights instead of Rec. 709 | `luminanceMix` and 4 more |
| M6 | clamp to 0...1 inside the group | `luminanceMix`, `neutralsKeepTheirLevel`, `mixesMatchReference`, `everyDecoder` |
| M7 | Red filter passes blue | `directions` |
| M8 | range check removed from a slider value | `amountsAreRangeChecked` |
| M9 | a no-change set switches the group on (the C1 bug) | `noChangeGestureChangesNothing` |
| M10 | changing a filter no longer switches the group on | `changingAFilterSwitchesItOn`, `noChangeGestureChangesNothing` |
| M11 | reset leaves the group | `resetIsIdentity`, `checkBox`, `offRendersNothing`, `colorMixerFeedsTheMix`, `resettingEverySectionGivesBackTheIdentity` |
| M12 | paste and presets drop the group | `presets`, `copiesAndBatches` |
| M13 | `photocli`: on follows the stored state only | `scriptedOnState`, `amountsAreRangeChecked` |
| M14 | `photocli`: `on=true` no longer clears turned-off | `scriptedOnState` |
| M15 | swatch keeps the conversion | `fringeSwatchesKeepColor` |
| M16 | `on` not stored | `stackRepresentation` and 6 more |
| M17 | group out of place in the headings | `placement` |

Not mutated: the history label strings, the heading and menu (they live in PhotoApp, which has no test target; S2 and S3 are their check).

## Findings

None fails an acceptance criterion. For the main session, to file or decide:

- **Q1 (observation, no action).** In a script, any `adjust bw …` command, even one that changes nothing (`print`, a quick-set already in effect, a value already set), opens the script's own undo group, so `print undo` reads `''` afterwards and a following `undo` undoes the empty group. Check "no step" with the stack, the hash and `history`, not with `undo`. This is the script's artefact (control: `adjust exposure 0`), not the app's. The real click path is P9.
- **Q2 (follow-up issue, not this branch).** `photocli render --input <file> --out <png>` without `--library-root` opens the default library (the owner's), which `CLAUDE.md` and the workflow say a test launch must not do. Here it only touched `catalog.sqlite-shm`; no data changed. `photocli`, like `photobench`, is not covered by the launch guard (`CLAUDE.md`, library-launch-guard). Proposed title: "photocli render --input opens the default library". The code is not in this branch's diff. My mistake: I should have passed `--library-root`.
- **Q3 (observation).** RAW goldens were not compared on this Mac: `RAW decode settings match their goldens` is skipped (goldens made on macOS 27.2 26B123, this Mac is 27.2.1 26B131). `GoldenTests` still passes (53 module cases and the other two). The branch changes no fingerprint file, so nothing moved, but the RAW goldens' comparison is still unrun on 27.2.1. The engineer already proposed the follow-up (rewrite the fingerprints for the new build, in their own commit).
- **Q4 (observation).** The History labels and the heading's words live in PhotoApp and have no unit test; the labels are pinned only by the scripts here (S2, S3). Fine for this branch; a regression would show in `qa.md`'s rerun, not in `swift test`.

Design questions: none. Requirements issues: none.

## Scripts

All run on a copy of the bundle: `Scripts/build-app.sh` output copied to `$S/app/Gus.app`, `CFBundleIdentifier` set to `me.sesser.gus.debugtest`, re-signed ad hoc (`codesign --force --deep --sign -`). `$S` is the session scratchpad. Scratch library: `photobench generate --output $S/src --jpeg 6 --dng 2 --heic 2 --videos 1 --pairs 1`, plus a gray JPEG made with `sips -m "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc" IMG_00006.JPG --out GRAY_00099.JPG`, then `photobench import --library-root $S/lib --source $S/src` (14 files). Every run used a fresh `cp -R $S/lib $S/libN`. Launcher (`run.sh`):

```
timeout 180 $S/app/Gus.app/Contents/MacOS/Gus --library-root "$1" --debug-script "$3"
```

**S1. No-change gesture (and the control).** On a fresh photo:

```
wait 2; focus IMG_00001; loupe; wait 2; tab adjust; wait 1;
history open; wait 1; history;
print undo; print adjustments;
adjust bw set red 0; print undo; adjust bw print; print adjustments;
adjust bw set yellow 0; adjust bw set blue 0; print undo; adjust bw print;
history wait; history;
adjust bw set red 20; print undo; adjust bw print; history wait; history;
adjust bw set red 20; print undo; adjust bw print; history wait; history;
quit
```

Showed: stack `{"operations":[]}` and hash `6c76a50e5dc3` before and after the three no-op sets; `on false … modified false`; History 0 entries; `print undo` `'-'` then `''`. `set red 20`: `on true`, undo `'Black & White Filter'`, History 1 row; the second `set red 20`: History still 1 row. Control (`adjust exposure 0; print undo`) also gives `''`.

**S2. Quick-set undo step.**

```
wait 2; focus IMG_00001; loupe; wait 2; tab adjust; wait 1; history open; wait 1;
adjust bw set yellow 30; adjust bw set blue 20; history wait; print adjustments;
adjust bw filter red; history wait; print undo; print adjustments;
undo; history wait; print undo; print adjustments;
redo; history wait; print undo; print adjustments;
undo; undo; undo; history wait; print undo; print adjustments;
quit
```

Showed: `{blue 20, on, yellow 30}` then `{on, red 100}` ("Black & White Filter"); one undo gives back `{blue 20, on, yellow 30}`; redo `{on, red 100}`; three undos the empty stack (`undo '-'`).

**S3. Labels, on / off / reset, History.**

```
wait 2; focus IMG_00001; loupe; wait 2; tab adjust; wait 1; history open; wait 1;
print adjustments;
adjust bw toggle; print undo; history wait; print adjustments;
adjust bw filter red; print undo; history wait;
adjust bw filter red; history wait;
adjust bw set green 30; print undo; history wait;
adjust bw filter blue; print undo;
adjust bw nofilter; print undo;
adjust bw off; print undo;
adjust bw on; print undo;
adjust bw reset; print undo; history wait; print adjustments; history;
quit
```

Showed: undo names "Turn On Black & White", "Black & White Filter" (red, green set, blue, No Filter), "Turn Off Black & White" (`applies false turnedOff true`, values kept, `checkbox off`, `segment -1`), "Turn On Black & White", "Reset Black & White" (`on false modified false`). The repeated `filter red` added no row. History, newest first: Reset Black & White, Turn On Black & White, Turn Off Black & White, Black & White Filter ×4, Turn On Black & White (8 rows). A second run with `history wait` before the final `print adjustments` (`adjust reset` control) gave identity stack and hash `6c76a50e5dc3`.

**S4. `photocli develop` rules.** Debug build of `photocli`, `--library-root $S/lib7` (a copy of the scratch library):

```
photocli develop --version 2 --set blackAndWhite.red=40 --dry-run
photocli develop --version 2 --reset blackAndWhite --set blackAndWhite.green=50 --dry-run
photocli develop --version 2 --reset all --set blackAndWhite.red=40 --dry-run
photocli develop --version 2 --reset blackAndWhite.on --set blackAndWhite.red=40 --dry-run
photocli develop --version 2 --set blackAndWhite.on=false --set blackAndWhite.red=40 --dry-run
photocli develop --version 2 --set blackAndWhite.on=true --dry-run
photocli develop --version 2 --set exposure.ev=1 --dry-run
photocli develop --version 2 --set blackAndWhite.red=150 --dry-run
photocli develop --version 2 --set blackAndWhite.red=0 --dry-run
photocli develop --version 2 --reset blackAndWhite --dry-run
photocli develop --version 2 --reset blackAndWhite.red --dry-run
```

and the same for version 3 after `photocli develop --version 3 --set blackAndWhite.on=true --set blackAndWhite.red=100`. Results in the table above.

**S5. Color Fringes swatch.**

```
wait 2; focus IMG_00001; loupe; wait 2; tab adjust; wait 1;
adjust fringe fill 1 purple; wait 1; print fringe;
adjust bw filter red; wait 1.5; print fringe;
adjust bw toggle; wait 1; adjust bw print; print fringe;
adjust bw toggle; wait 1; print fringe;
adjust saturation -100; wait 1.5; print fringe;
quit
```

Showed `swatch 0.4257,0.2014,0.7279` on all four prints through the toggles; `0.2870,0.2870,0.2870` after Saturation -100.

**S6. Paste over a selection; video skipped; one undo.**

```
wait 2; focus IMG_00001; loupe; wait 2; tab adjust; wait 1; adjust bw filter red; history wait; copyadjust;
grid; wait 1; selectall; pasteadjust; wait 3; print undo; undo; wait 2; print undo; quit
```

then `photocli query images --library-root $S/lib12` (and, with the `undo` left out, on `$S/lib13`). After paste: 12 photos carry `{on, red 100}` (JPEG, gray JPEG, HEIC, DNG, the pair's DNG), the pair's JPEG and the video have none; `print undo` `'Paste Adjustments'`. After one `undo`: only IMG_00001 (the source) still has it.

**S7. Rendered end to end.** `photocli render --input IMG_00001.JPG --long-edge 1024 --out <png>` with no stack, `--set blackAndWhite.on=true`, and `--set blackAndWhite.<filter>=100` for each filter (this is the command that touched the shm file, Q2), then a small PNG reader (`python3 -I`) at seven points. Every point has R = G = B with the group on. Teal ellipse: off (0.28, 0.44, 0.42), none 0.417, Red 0.374, Blue 0.427; tan ellipse: none 0.643, Red 0.680, Blue 0.590; green background: none 0.532, Red 0.470, Green 0.565, Blue 0.511. Red darkens the blue-green and lightens the warm tan; Blue does the opposite on tan.

**S8. Heading state, caption, snapshots.**

```
wait 2; focus GRAY_00099; loupe; wait 2; tab adjust; wait 1.5; adjust bw print;
focus IMG_00001; wait 2; adjust bw print;
focus RAW_00007; wait 3; adjust bw print;
focus PAIR_00011; wait 3; adjust bw print;
focus MVI_00012; wait 2; adjust bw print; print adjustments;
quit
```

Caption `monochrome` for the gray file only; `adjust tab video` and an idle editor on the video. And

```
wait 2; focus IMG_00001; loupe; wait 2; tab adjust; wait 1.5; snapshot a-color.png;
adjust bw toggle; wait 2; snapshot b-nofilter.png;
adjust bw filter red; wait 2; snapshot c-red.png;
adjust bw filter blue; wait 2; snapshot d-blue.png;
adjust bw off; wait 2; snapshot e-off.png;
scroll bottom; wait 1; buttons;
quit
```

Looked at all five: colour; plain grey; Red (the green field and the sea-green go darker, the tan and brown ellipses lighter); Blue (the tan ellipse darker, the lime ellipse lighter); back to colour with the box off. The film strip thumbnail follows. The glass panes are blank in snapshots, as `CLAUDE.md` says. `buttons` with the heading folded shows the check box "Black & White" (`state off`, tip "Turn on Black & White") and its reset "Reset Black & White". The engineer's run with the heading open showed the segmented control's `selected` index following the state.

**Not run, and why.** `menuitems Black` under `open -W -n --stdout … --args …` and once more with `osascript … set frontmost of (first process whose unix id is <pid>)` gave `key nil` both times: macOS did not make the window key, so every Adjust item, the submenu's items included, read disabled (`Adjust/Black & White enabled`, `…/Turn On Black & White disabled`, `editLoupePhoto false`). Menu enablement, the check marks and the real keyboard and mouse are therefore P3, P4, P9. I did not retry.

## For a person

No VoiceOver, macOS 15 or macOS 26 checks. Run the bundle on a scratch library from `photobench`, always with `--library-root`; the exact command comes from the main session at sign-off.

- **P1. Look of the heading (M1).** Adjust tab on a colour JPEG. Black & White sits between Color Mixer and Color Grading, folded, with an empty check box and a dimmed reset. Open it: the segmented control (Yellow, Orange, Red, Green, Blue, none selected), five sliders grayed with no fill, the two-line caption. Collapse All / Expand All include it; quit and relaunch: the fold state is kept. The longest segment names fit at the inspector's narrowest width. With Full Keyboard Access on, Tab reaches the check box, the segments, each slider and field, arrow keys move them, and the heading folds from the keyboard.
- **P2. Tints (M2).** Choose Red: only the Red slider fills red. Move each slider and look at the five fills in Light, Dark and with Increase Contrast (System Settings, Accessibility, Display). Is Yellow's fill legible in Light? Uncheck the box: the fills go and the rows gray. If any tint is poor the design allows dropping all of them.
- **P3. Menu (M3).** In the loupe, Adjust ▸ Black & White ▸: the first item reads "Turn On Black & White"; after choosing it "Turn Off Black & White" and No Filter is checked. Choose Red Filter: it is checked and the segment selected; move a slider a little: both checks clear; type 100 back: both return. Choose the checked filter again: no new History entry. (The script could not make the window key, so enablement is untested.)
- **P4. Enablement (M4).** With the loupe's photo: all seven items enabled. In the grid: all dimmed, the submenu title still opens. While comparing (S) and while cropping (C): dimmed. On a video and an offline photo: dimmed; the Adjust tab shows its own messages.
- **P5. Cropping (M5).** In a crop session move a Black & White slider and tick the check box: it applies like another heading's, and Done / Cancel behave as before.
- **P6. Monochrome file (M6).** A gray JPEG or TIFF shows "This photo has no color, so the filters change nothing." and the controls still move; a colour JPEG with no colour in it, and a raw, show the standard caption. (The script confirmed which caption is selected, not how it reads.)
- **P7. Strength (M7).** On a blue sky with clouds, a portrait and foliage, try each quick-set. Are Red and Green at 100 too heavy? Is Orange between Yellow and Red? The filter numbers are the engineer's estimates and not owner-confirmed (status.md); if too strong, the table changes, not the 100.
- **P8. History and undo at the window (M8).** Check the box ("Turn On Black & White"), drag a slider (one "Black & White Filter" entry), choose Blue (one entry), uncheck (one entry); press ⌘Z once after each and confirm each undoes one step and the segment and box follow. Use the heading's reset: "Reset Black & White", box unchecked, segment none, reset dimmed again.
- **P9. A click that moves nothing (M9).** On a photo that never had the group: click a slider's knob without moving, double-click a filter's label, press Return in a value field. The photo stays in colour, History gets no entry and Edit ▸ Undo is not "Undo Black & White Filter". Then type 30 in a field: the photo turns gray, one entry. (The scripts proved the model and the stack; only the real gesture and Edit menu are left.)
- **P10. Presets, paste, copies, menus (M10).** Save Adjustments as Preset…: "Black & White" is listed between Color Mixer and Color Grading and checked for a converted photo. Copy and paste a converted photo onto two selected photos from the grid: both go gray, one undo step (the script did a paste over 12; this is the menu and key path). Duplicate a converted photo: the copy starts converted and then changes alone.
- **P11. Fringe swatch look (M11).** On a photo with a Color Fringes slot filled (Purple), turn Black & White on: the photo goes gray and the slot's swatch in the Lens heading stays purple. Turn it off: unchanged. Saturation at -100 grays the swatch; that is expected. (Values checked in S5.)
- **P12. Live drag (QA's own, no M-number).** With a gray result visible, drag a slider in the loupe and judge that the preview follows smoothly with no flash of colour (the scripts render settled frames only; this is motion and timing).
- **P13. Quick-set width at three inspector widths (M12, designer's third pass).** A script cannot set the inspector's width (`windowsize` leaves it at 300 pt), so this is the one width check left. Adjust tab on a colour photo, Black & White heading open, then drag the inspector's divider.
  - Narrowest (280 pt pane, 256 pt of content, 51 pt a segment): all five names read in full, "Orange" included, no ellipsis; the selected segment's capsule still has air around its name (the designer rates Orange as tight). Nothing on the tab is cut off on either side: the Presets buttons, slider labels, value fields and the heading's check box. Choose each segment and look at the selected state.
  - Default (300 pt, 276 pt of content): the row has the same left and right edges as the sliders (scripted: controls 8 to 292 in a 300 pt pane, `fits`).
  - Widest (420 pt): the segments stretch evenly, the row still lines up with the sliders, nothing else moves.
  - With the Tone Curve heading open too: record whether the tab clips at the narrowest width. Expected (its four segments are 276 pt wide and the content is 256 pt: the follow-up in Q5); do not fail this branch for it.
  - Increase Contrast, or a larger text size if offered: look again at the narrowest width.

## Follow-up

### Rerun for the owner's sign-off finding (2026-11-19, commits 69f1ef1 and 95fa5b9)

Owner: qa-tester. Date: 2026-11-19. Tested: `feature/bw-module` at e012174 (sources as of 69f1ef1; 95fa5b9 and e012174 change only `status.md` and the reviews), same Mac and macOS build as above (27.2.1, SDK 27.2, minos 15.0).

**Verdict: the finding is fixed.** With the Black & White heading open, the Adjust column fits the inspector (`print inspectorwidth`: visible 300, controls 8...292, `fits`; the same build without the flag: -26...326, `overflow`). The Tone Curve, Color Grading and Spots mode controls are the same width as before (276 pt in a 300 pt inspector, identical in the two builds). The full `swift test` passed (1189 tests in 174 suites, 63.8 s). One check stays for a person: the narrowest inspector width (P13, the designer's M12), which no script can set.

| Finding | State | Evidence |
|---|---|---|
| Owner finding: Adjust column wider than the inspector with Black & White open | **Fixed** | S9 and S10 |
| Q1 to Q4 (first QA) | Unchanged: observations and follow-ups, no new information | |
| **Q5 (new, follow-up, not this branch)** | Open, for the main session to file | The Tone Curve control is 276 pt wide in a 256 pt content area at the narrowest inspector, as the engineer and the designer say. Not measurable by script (the inspector stays 300 pt under `windowsize`), so this is arithmetic plus the intrinsic width in `status.md`; M12 and P13 show it. Proposed title: "Tone Curve channel control widens the Adjust tab at the narrowest inspector width"; the fix is `fillsWidth: true` on that control. Color Grading (three segments) and Spots (frame fills) were also 276 pt wide, so check them at the narrowest width in P13 |

**What changed since 7c321aa, checked.** `git diff --stat 7c321aa HEAD` lists, under `Sources/`, only `Model/DebugScript.swift` (the `print inspectorwidth` command and its header line), `Views/BlackAndWhiteSection.swift` (one line: `fillsWidth: true` on the quick-set control) and `Views/CurveEditor.swift` (the `fillsWidth` property, off by default, a `sizeThatFits` that answers only when it is on, and a compression-resistance line). Nothing under `Tests/`, `Scripts/`, `Sources/PhotoCore`, `Package.swift`, the String Catalog or `docs/USER_GUIDE.md`. In `docs/`: `status.md` (the new "Owner finding at sign-off" section), `review.md` and `code-review.md` (third passes) and `qa.md` (my first run, added after 7c321aa). `PreviewCacheKey.currentPipelineVersion` untouched. The only other callers of `AppKitSegmented` (Tone Curve, Color Grading, Spots) pass no new argument.

**No unit test is possible** for this (the view is in PhotoApp, which no test target imports; engineer and code reviewer agree). The regression check is S9 below. Note that `print inspectorwidth` would trap on an `Int(infinity)` if a visible hosting-view scroll view held no visible control (code review's observation); none does today.

### Scripts for the rerun

Builds, both copies of the bundle with their own identifiers and a re-signed ad hoc signature: After is `Scripts/build-app.sh` on the checkout (`me.sesser.gus.debugtest.fix218after`); Before is `git archive HEAD` extracted to a scratch directory outside the checkout with one line changed (`, fillsWidth: true` removed from the quick-set control in `BlackAndWhiteSection.swift`), built the same way (`me.sesser.gus.debugtest.fix218before`). Scratch library: the `photobench` one from the first run (12 items), copied fresh for each run. Launcher: `timeout 180 <app>/Contents/MacOS/Gus --library-root <copy of the scratch library> --debug-script "<script>"`; every launch carries `--library-root`, and no `photocli` or `photobench` command was run this time. The headings' open state is the app's own preference (`adjust.section.<name>`) in each copy's own preference domain, written with `defaults write <copy's id> adjust.section.blackAndWhite -bool true` (and `tone`, `colorGrading`, `spots` for the second run, `false` for the rest), and the domains were deleted after.

**S9. Width with the Black & White heading open (only it open).**

```
wait 2; focus IMG_00001; loupe; wait 2; inspector on; wait 1; tab adjust; wait 2;
print inspector; print inspectorwidth; buttons;
scroll bottom; wait 1; print inspectorwidth; tab info; wait 1; print inspectorwidth; quit
```

| Build | Adjust tab | Adjust tab, scrolled to the bottom | Info tab |
|---|---|---|---|
| After | visible 300 controls 8...292 widest NSSegmentedControl 276 **fits** | same, **fits** | visible 300 controls 12...288 widest NSTextField 276 fits |
| Before (flag off) | visible 300 controls -26...326 widest NSSegmentedControl 345 **overflow** | same, **overflow** | same as After, fits |

`buttons`: the "Filter" control is 276 pt wide after, 345 pt before (the engineer's numbers, reproduced). The control starts at the same x as the sliders after the fix.

**S10. The other segmented controls, kept widths.** Run A: Tone, Color Grading and Spots headings open, Black & White closed (`print inspectorwidth` and `buttons` at the top of the tab and scrolled to the bottom). Run B: all four open (adds `windowsize` steps at the end of S9's script: 1000 x 700, 800 x 600, 700 x 600 and 2200 x 1000, each followed by `print inspectorwidth`).

| Control | Run A, Before | Run A, After | Run B, Before | Run B, After |
|---|---|---|---|---|
| Spots mode (Heal / Clone) | 276 | 276 | 345 | 276 |
| Tone Curve channels (4 segments) | 276 | 276 | 345 | 276 |
| Color Grading ranges (3 segments) | 276 | 276 | 345 | 276 |
| Black & White quick-set | not shown | not shown | 345 | 276 |
| Column | visible 300, controls 8...292, fits | same, fits | visible 300, controls -26...326, **overflow** | visible 300, controls 8...292, **fits** |

Run A is identical in the two builds: the flag changed no other control. In run B (before) the three other controls were as wide as the Black & White one only because the column had been widened for it (their own width is Run A's). After the fix every segmented control matches the pane's content width. At every window size in run B (the 2200 pt one included) the inspector stayed 300 pt, so the script cannot show another width. At 300 pt the Tone Curve control (276 pt) exactly fills the column; that it would not fit in 256 pt is Q5.

I did not take a snapshot: the inspector is a glass pane and snapshots leave it blank (`CLAUDE.md`), so the widths above are the evidence, and the look is P13.

### Checks on the owner's data

No Gus process was left running (`pgrep -x Gus` empty). After the runs, nothing under `~/Library/Application Support/Gus` is newer than my start (the listing of every file and its modification time is identical to the one taken before; `catalog.sqlite-shm` still has the earlier run's time, 21:30:54 on 2026-11-18) and nothing under `~/Library/Caches/me.sesser.gus` is newer. In `~/Library/Caches` itself only a system file (`com.apple.nsservicescache.plist`) changed.

### Sign-off

Owner's sign-off on #218 (relayed by the main session; recorded by qa-tester, committed by the main session).

- **Signed off:** 2026-11-19, at commit `9e547bc` (head of `feature/bw-module`; the sources are as of 69f1ef1, the later commits change only `status.md`, the reviews and this file).
- **How:** by eye, on a `photobench` scratch library, with the bundle run under `--library-root`. Earlier in the session the owner found the Adjust column wider than the inspector with the Black & White heading open; that was fixed (69f1ef1, 95fa5b9, rerun above: S9 and S10) and the owner then reported: "They are fixed now. Signed off on #218."
- **Checks left open:** none named by the owner. No VoiceOver, macOS 15 or macOS 26 checks (not asked of the owner, per the standing rule).

| Item | State | Note |
|---|---|---|
| P1 to P6 (look, tints, menu, enablement, cropping, monochrome file) | Checked by the owner, fine | Not itemised by the owner; recorded under the blanket sign-off. |
| P7 (filter strength on real photos, M7) | Checked by the owner, fine | The owner's judgment of strength was part of the look check on his photos; he did not report it separately and named no change to the filter table. The numbers remain the engineer's estimates (`status.md`). |
| P8 to P11 (History and undo, a click that moves nothing, presets and paste and copies, fringe swatch) | Checked by the owner, fine | Not itemised. |
| P12 (live drag, no flash of colour) | Checked by the owner, fine | Not itemised; motion judged by hand. |
| P13 (quick-set width, M12) | Checked by the owner, fine | This is the finding he raised and re-checked after the fix, at the inspector width he used. He did not say whether he also tried the narrowest and widest widths or the Tone Curve heading open at the narrowest width; with nothing reported against them, they are recorded as fine under the sign-off, not as separately confirmed. |

No P item stays open. Carried outside this branch: **Q5** (the Tone Curve, Color Grading and Spots mode controls are 276 pt wide and do not fit the 256 pt content area at the narrowest inspector; proposed fix `fillsWidth: true`) is a follow-up issue for the main session to file, not a check on this branch.
