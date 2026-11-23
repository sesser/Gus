# Copy Adjustments: choose what to copy: QA

Owner: qa-tester. Date: 2026-11-22. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/copy-adjustments-selective` at a4a7108, on an Apple M4 Pro, macOS 27.2.1 (26B131), Xcode SDK
27.2, Swift 6.4.2. Issue #243, Complexity hard.

## Verdict

**Passes.** All 12 acceptance criteria hold: 11 are shown by tests and by scripted runs of the bundle (Pass), and
AC12's Tab walk with Full Keyboard Access is the one criterion left for a person (P2); every other box and key path
passed by script. No findings for the engineer. The full `swift test` is green (1452 tests in 206 suites, 0
failures), `Scripts/build-app.sh` builds, and the owner's library and running processes were untouched (checked at
the end, below).

## Acceptance criteria

How: Test = a Swift Testing test in `Tests/PhotoCoreTests/CopyAdjustmentsTests.swift` (suite "Copy Adjustments",
24 tests, all run and passed in the full run and again alone with `swift test --filter
"CopyAdjustmentsTests|LibraryModalTests|RAWDecodeGraphTests|LocalizationTests"`: 43 tests in 8 suites). Script =
a debug-script run of the bundle copy (S-numbers below). I read each test: each asserts the stored values or the
sheet's state the AC names, so each would fail if Copy took everything, or Paste replaced more than the copied
items. The engineer showed the two C1 tests failing against the old transform; I did not repeat that (no
scratch build of `develop` was needed: the new types do not exist there, so the suite cannot compile without
them).

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 (R1, R4): Copy shows the dialog; Cancel changes neither clipboard nor photos; Copy with defaults then Paste works | Script | S2: `copyadjust sheet` opens it; Esc closes with the clipboard `none` and Paste Adjustments dimmed; with an earlier copy (`light`) a second sheet cancelled leaves `light`; Return with defaults copies `light` ("Copied Tone."), Paste enabled. S3 (menu path with a key window): `menupress Copy Adjustments…`, Esc, then Return, then `menupress Paste Adjustments` onto two photos. Entry points: grid and loupe context menus list "Copy Adjustments…" (S12), none for a video; toolbar items `copyAdjustments` and `pasteAdjustments` can be added (S12) | Pass |
| AC2 (R2): every heading and group and Crop & Straighten once, in the tab's order, with its names; heading box mixed when only some are checked | Test + Script | Tests `rowsFollowTheTab`, `headingStateIsDerived`. S1 `print copysheet`: 22 boxes in the order Crop & Straighten, Spots, Light (White Balance, Tone, Presence), Tone Curve, Color Mixer, Black & White, Color Grading, Details (Sharpening, Noise Reduction), Lens (Distortion, Lens Vignetting, Color Fringes, Color Alignment), Effects (Look-Up Table, Vignette, Grain); Light is `mixed`. The sheet's snapshot (S13) matches. Presets and Masks have no row | Pass |
| AC3 (R3): Exposure and Tone edited with a crop: Tone checked, Light mixed, other non-Lens groups unchecked "No changes", Crop & Straighten, Lens and Spots unchecked | Test + Script | Tests `defaultsFollowTheSource`, `uncheckedByDefault`, `turnedOffCountsAsChanged`, `noChangesAtAll`. S1 on IMG_00001 (exposure 0.5, contrast 20, crop 0.1,0.1,0.8,0.8): Tone on, Light mixed, Crop & Straighten off with no note, Spots and every Lens group off with "No changes" | Pass |
| AC4 (R4): with every box unchecked Copy is disabled | Test + Script | Tests `nothingCheckedCannotCopy`, `noChangesAtAll`. S2: `uncheck all` prints `copy off note 'Check something to copy.'`; Return leaves the sheet open (`alert after key return open`); a photo with no adjustments opens with the note and Copy off (S11) | Pass |
| AC5 (R5): only Color Grading copied changes only the target's Color Grading (stacks compared) | Test + Script | Test `onlyColorGrading` (stored stacks compared by content and render hash). S5: Color Grading copied from IMG_00001 (exposure 0.5, crop, grade shadows 40) and pasted on five photos: only `colorGrade` added; IMG_00002's crop, spot and exposure 1.0 unchanged; IMG_00001 unchanged | Pass |
| AC6 (R5): Tone Curve copied from a photo with none resets the target's | Test + Script | Test `copiedDefaultsReset`. S6: IMG_00003 with a curve and exposure 0.3; Tone Curve copied from IMG_00001 (none), pasted: `[exposure toneCurve]` becomes `[exposure]`, exposure still 0.3 | Pass |
| AC7 (R5, R6): paste on a multi-photo selection is one undo step; Undo restores every photo; History shows "Paste Adjustments" once per photo | Test + Script | Test `batchPasteHistory` (three photos, one write each, label once per photo, undo restores all). S5: five photos pasted, one `undo` restored all five, `redo` again; the loupe's History on IMG_00002 shows one "Paste Adjustments" row (plus the Undo and Redo rows) | Pass |
| AC8 (R7): Lens groups paste as now; a photo that can't be corrected is left unchanged and Activity says so; a paste that moves the frame of a target with spots asks first | Test + Script | Tests `frameQuestionIgnoresPastedSpots`, `frameQuestionCountsTheTargetsOwn`. S10: Spots and Distortion (Manual 10) pasted in the loupe onto a photo with no spots or masks: no question, Distortion pasted (spots left out by size); onto a photo with its own spot: the alert "Change distortion on a photo with masks or spots?"; Cancel writes nothing; Change pastes both; Undo reverts. S9d: Color Alignment (Auto) copied and pasted with one target's master hidden: the others get it, "1 photo was left unchanged: its original could not be read." The per-photo table read itself (Auto on a real raw) is code this branch does not touch (`git diff` of `LensCorrectionActions.swift` is the frame-question refactor only) and the scratch library has no real files with tables; the owner checked #87's reads | Pass |
| AC9 (R8): Spots to a same-size photo, one undo step; other size unchanged and Activity says so; off pastes as off; a source with no spots onto another size keeps its spots | Test + Script | Tests `spotsPasteBySize`, `sameSizeRule`, `spotPastePlan`, `spotPastePlanReachesWrittenPhotosOnly`, `maskFrameSizeMatchesTheDecode`. S7 (the sheet's Spots row checked, then Return): 1200x800 IMG_00003 got 2 spots; 900x600 SML_00001/SML_00002 and the turned IMG_00001 kept theirs: "Spots were not pasted onto 3 photos: their size differs from the photo the spots were copied from."; one `undo` restored everything. S8: spots turned off in the source pasted as off (`spots(off)`, 2 spots). S9: source with no spots pasted on a same-size photo reset it (2 spots to 0); a 900x600 photo kept its spot with "…onto 1 photo: its size differs…". M7 below | Pass |
| AC10 (R9): Crop copied is pasted as stored; unchecked, the target's crop is untouched | Test + Script | Test `cropPastesAsStored`. S6: crop 0.10,0.10,0.80,0.80 copied and pasted onto 900x600 photos and onto the photo of another size: the same rectangle as stored. S5 and S7 (Crop unchecked by default): no crop moved | Pass |
| AC11 (R6): Copy disabled for a video; Paste disabled until a copy; Paste while comparing disabled | Script | S4 (`open -W -n`, key window): `menuitems` with the video focused: Copy Adjustments… disabled, Paste Adjustments disabled before any copy, enabled after; comparing two photos: Copy enabled (takes the active photo: S14 shows "From IMG_00001", then "From SML_00001" after `compare active right`), Paste Adjustments disabled. A video's context menu has no Copy item | Pass |
| AC12 (R12): every box can be toggled and the dialog confirmed with the keyboard alone | Script, Person | S4b: every box is a system check box; `copyadjust sheet click <row>` presses each through AppKit (`performClick`, the path Space takes) and `mouse <row> box|label` posts real mouse events through the queue: one toggle each, never two; the heading rule (mixed to on to off) holds; Return copies and Esc cancels. Tab order and Space with Full Keyboard Access need a person: P2 | Open (P2) |

Counts: 8 criteria Pass with a test and a script (AC2 to AC7, AC9, AC10), 3 Pass by test and script or script alone
(AC1, AC8, AC11), 1 Open for a person (AC12, P2), 0 failed.

## Designer's manual checks, and where each stands

| M | What | Covered by |
|---|---|---|
| M1 | Look beside Export's with Increase Contrast | P1 (the default-width and 760 x 480 snapshots were looked at, S13: nothing clipped, the list scrolls, header, footer and buttons stay) |
| M2 | Full Keyboard Access Tab walk | P2 |
| M3 | 760 x 480 window | Script S13: sheet 420 x 480, list content 520, 340 shown, scrolls; at 1280 x 860 it is 420 x 660, not scrolled; the picture matches. By eye is part of P1 |
| M4 | Real mouse on a mixed heading, label, trailing text | Script posts real mouse events on a box and a label (S4b); a physical mouse is P3 |
| M5 | The real key flow | The menu path by script (S3); the real ⇧⌘C, Space, Return, ⇧⌘V, ⌘Z is P4 (`key` and `menukey` do not reach menu key equivalents) |
| M6 | A pack import that ends while the sheet is up | P6 (`LibraryModalTests` checks that the sheet is a listed modal; the ordering itself cannot be scripted) |
| M7 | Unreadable-size paste | Script S9b and S9c: Pass (below) |
| M8 | Paste tooltip | Text and update by script (`print clipboard` prints the toolbar's tooltip from the state it reads: `Paste Adjustments` with nothing, `Paste Adjustments: Tone`, `Paste Adjustments: Spots, Distortion`, `Paste Adjustments: 10 items` for `all`); the hover is P5 |
| M9 | ⌘Z at once after a one-photo Spots paste in the loupe | P4 (a script waits after each paste and cannot race it) |
| M10 | Spots + Distortion: no frame question for a target without spots or masks; "1 of 1" for one with a spot | Script S10: Pass for the loupe (no question without spots; the question with one spot). The multi-photo wording "1 of the N photos" was shown by the engineer (C1) and not repeated |

M7 detail (S9b): source IMG_00002 with 2 spots copied, its master then hidden, `selectall; pasteadjust`: one row only,
"Spots were not pasted onto 5 photos: their size, or the size of the photo they were copied from, could not be
read." (every photo but the video), nothing about "differs". S9c: source readable, target IMG_00003's master hidden,
IMG_00001, SML_00001 and SML_00002 of other sizes: two rows, "…onto 3 photos: their size differs from the photo the
spots were copied from." first, then "…onto 1 photo: its size, or the size of the photo they were copied from,
could not be read." The same-size source itself got its spots, nothing else changed.

## Findings

None. Three notes that are not findings:

- The debug script's `menuitems` reads the menu state a moment after `focus`: without a `wait 1`, a video
  showed Copy Adjustments… enabled once. With the wait it is disabled in every run (S4). Script timing, not the app.
- `key shift+cmd+c` and `menukey shift+cmd+c` do not open the sheet (they never reach the menu's key equivalent);
  `menupress Copy Adjustments…` and `copyadjust sheet` do. So the real shortcut is a person's check (P4).
- A launch with `open -W -n` is activated only some of the time (about two runs in three: the first run's
  `menustate` said `key false` and every menu item read as disabled); I reran until `menustate` said `key true`
  and recorded only those runs. `osascript` by process ID did not change that.

## Scripts

Setup, once: the bundle built with `Scripts/build-app.sh` (exit 0), copied to `$Q/Gus.app`, identifier changed to
`me.sesser.gus.debugtest.qa` and re-signed ad hoc; `$Q` is the scratchpad's `qa` folder.

```sh
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.qa $Q/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $Q/Gus.app
.build/release/photobench generate --output $Q/src1 --jpeg 3 --jpeg-size 1200x800 --dng 0 --heic 0 --videos 1
.build/release/photobench generate --output $Q/src2 --jpeg 2 --jpeg-size 900x600 --videos 0 --dng 0 --heic 0
# rename src2's files to SML_00001.JPG and SML_00002.JPG, then:
.build/release/photobench import --library-root $Q/lib0 --source $Q/src1
.build/release/photobench import --library-root $Q/lib0 --source $Q/src2
```

The library has IMG_00001 (1200x800 with EXIF orientation 6, so 800x1200 as shown), IMG_00002 and IMG_00003
(1200x800), SML_00001 (900x600, orientation 6), SML_00002 (900x600) and one video MVI_00004. Grid order: IMG_00001,
SML_00001, IMG_00002, SML_00002, IMG_00003, MVI_00004.

Runners (a fresh copy of `lib0` per run, `--library-root` on every launch):

```sh
# run.sh <name> "<script>"   direct launch (no key window)
rm -rf $Q/lib-$1 && cp -R $Q/lib0 $Q/lib-$1
$Q/Gus.app/Contents/MacOS/Gus --library-root $Q/lib-$1 --debug-script "$2"

# runopen.sh <name> "<script>"   with a key window; used for menus (S3, S4, S14); every script starts "wait 3; "
timeout 180 open -W -n --stdout $Q/out-$1.txt $Q/Gus.app --args --library-root $Q/lib-$1 --debug-script "wait 3; $2"

# m7.sh <name> <file stem> "<before>" "<after>"   as run.sh, but moves <stem>.JPG aside as soon as the
# `clipboard` line appears (the script waits 6 s after the copy) and moves it back at the end
```

**S1: sheet, rows, defaults (AC2, AC3)**, `run.sh s1`:

```
wait 2; focus IMG_00001; loupe; wait 1; adjust exposure 0.5; adjust contrast 20; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; grid; print clipboard; copyadjust sheet; print copysheet; quit
```

Showed the 22 boxes in the tab's order with the tab's names, Tone on, Light mixed, Crop & Straighten off (no
note), every other group "No changes", Spots and Lens off, Copy on, `clipboard none`, sheet 420 x 660 (ideal 660),
not scrolled; Crop's and Spots' captions as VoiceOver help and tooltip, every other row's tooltip its name, no help.

**S2: Cancel, Return, nothing checked (AC1, AC4)**, `run.sh s2`:

```
wait 2; focus IMG_00001; loupe; wait 1; adjust exposure 0.5; adjust contrast 20; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; grid; print clipboard; menuitems Paste Adjustments; copyadjust sheet; alert; alert key escape; print clipboard; menuitems Paste Adjustments; copyadjust sheet; copyadjust sheet uncheck all; alert; alert key return; print copysheet; copyadjust sheet check light; alert key return; print clipboard; print announcement; menuitems Paste Adjustments; copyadjust sheet; copyadjust sheet check colorGrade; alert key escape; print clipboard; quit
```

Esc: sheet closed, clipboard `none`. Unchecked: `copy off note 'Check something to copy.'`, Return left it
open. Tone checked then Return: closed, clipboard `light`, "Copied Tone.", tooltip "Paste Adjustments: Tone". A
later sheet with Color Grading checked then Esc left the clipboard `light`. (`menuitems` read disabled here only
because a direct launch has no key window: see S4.)

**S3: the menu path (AC1)**, `runopen.sh mp2`:

```
print menustate; focus IMG_00001; loupe; wait 1; adjust exposure 0.5; adjust contrast 20; grid; wait 1; menupress Copy Adjustments…; wait 2; alert key escape; print clipboard; menupress Copy Adjustments…; wait 2; alert key return; print clipboard; focus SML_00002; key shift+down; wait 1; menupress Paste Adjustments; wait 2; print stacks; quit
```

(`menustate key true`.) Esc: clipboard `none`; Return: `light`; Paste Adjustments from the menu gave SML_00002 and
IMG_00003 exposure 0.5 and contrast 20; IMG_00001 and the others unchanged.

**S4: Copy and Paste states for a video and while comparing (AC11)**, `runopen.sh o42` and `o51` (key true):

```
focus IMG_00001; wait 1; print menustate; menuitems Copy Adjustments; focus MVI_00004; wait 1; print menustate; menuitems Copy Adjustments; menuitems Paste Adjustments; quit
focus IMG_00001; wait 1; adjust exposure 0.5; grid; wait 1; print menustate; copyadjust all; wait 1; menuitems Paste Adjustments; focus IMG_00001; key shift+right; wait 1; print selection; compare on; wait 2; print compare; menuitems Copy Adjustments; menuitems Paste Adjustments; compare off; quit
```

Photo: Copy enabled. Video: Copy disabled, Paste disabled (no copy yet). After `copyadjust all` Paste enabled
("Copied 10 items."). Comparing two photos: Copy enabled, Paste disabled.

**S4b: every box, real mouse, heading rule (AC12)**, `runopen.sh k1`:

```
print menustate; focus IMG_00001; loupe; wait 1; adjust exposure 0.5; adjust contrast 20; grid; wait 1; copyadjust sheet; copyadjust sheet click develop; copyadjust sheet click develop; copyadjust sheet click light; copyadjust sheet click crop; copyadjust sheet mouse spots box; copyadjust sheet mouse colorGrade label; copyadjust sheet click lens; alert key return; print clipboard; quit
```

Light mixed, then on (all three, White Balance and Presence "Resets on paste"), then off (Copy off, "Check
something to copy."), then Tone alone back to mixed; Crop on; Spots on by a real mouse click on its box (one
toggle); Color Grading on by a real click on its label (one toggle); Lens on checks all four; Return closed and
copied `crop spots light colorGrade distortion lensVignetting colorFringes colorAlignment`.

**S5: Color Grading onto a selection, one undo step, History (AC5, AC7)**, `run.sh ac5`:

```
focus IMG_00002; loupe; wait 1; adjust exposure 1; adjust crop begin; adjust crop rect 0.2 0.2 0.5 0.5; adjust crop done; spots on; spot add 0.5 0.5; spots off; wait 1; focus IMG_00001; wait 1; adjust exposure 0.5; adjust grade shadows 200 40; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; grid; wait 1; print stacks; copyadjust colorGrade; print clipboard; selectall; deselectall; focus SML_00001; key shift+down; wait 1; print selection; pasteadjust; wait 2; print stacks; print messages; undo; wait 2; print stacks; redo; wait 2; print stacks; focus IMG_00002; loupe; wait 1; history wait; history; quit
```

After the paste every photo but the video has `colorGrade` with shadows 40; IMG_00002 kept crop 0.20,0.20,0.50,0.50,
its spot and exposure 1.0; IMG_00001 unchanged; "1 video was left unchanged." One `undo` restored every photo to its
earlier stack, `redo` applied it again. History of IMG_00002: "Paste Adjustments" (then "Undo …" and "Redo …"), below
Add Spot, Crop, Debug exposure.

**S6: Tone Curve reset and Crop as stored (AC6, AC10)**, `run.sh ac6`:

```
focus IMG_00003; loupe; wait 1; adjust curve rgb 0,0.1 1,1; adjust exposure 0.3; wait 1; print adjustments; focus IMG_00001; wait 1; adjust exposure 0.5; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; focus IMG_00002; adjust crop begin; adjust crop rect 0.3 0.3 0.4 0.4; adjust crop done; grid; wait 1; print stacks; focus IMG_00001; copyadjust toneCurve; focus IMG_00003; wait 1; pasteadjust; wait 2; print stacks; focus IMG_00001; copyadjust crop; focus SML_00002; key shift+up; wait 1; print selection; pasteadjust; wait 2; print stacks; quit
```

(The second crop, on IMG_00002, did not take; it is not needed.) IMG_00003 `[exposure toneCurve]` became
`[exposure]` with exposure 0.3. Crop pasted onto SML_00001, IMG_00002, SML_00002 as 0.10,0.10,0.80,0.80, whatever their
size; IMG_00003 (not selected) unchanged.

**S7: Spots by size through the sheet (AC9)**, `run.sh ac9`:

```
focus IMG_00002; loupe; wait 1; spots on; spot add 0.3 0.4; spot add 0.7 0.6; spots off; adjust exposure 1; focus IMG_00003; wait 1; spots on; spot add 0.5 0.5; spots off; focus SML_00001; wait 1; spots on; spot add 0.5 0.5; spots off; grid; wait 1; print stacks; focus IMG_00002; copyadjust sheet; copyadjust sheet check spots; copyadjust sheet confirm; selectall; pasteadjust; wait 3; print stacks; print messages; undo; wait 2; print stacks; quit
```

Copied "Spots, Tone." IMG_00003: 1 spot became 2; SML_00001 kept 1; SML_00002 and the turned IMG_00001 got
exposure 1 but no spots; "Spots were not pasted onto 3 photos: their size differs from the photo the spots were
copied from."; `undo` restored all six stacks.

**S8: Spots turned off (AC9)**, `run.sh ac9b`: as S7 but `spot enable off` on the source and `copyadjust spots`, pasted
onto IMG_00003: `spots(off)`, 2 spots. (Its second half pasted a no-spots source onto a turned photo, so see S9.)

**S9: no-spots source, same size and other size (AC9)**, `run.sh ac9c`:

```
focus IMG_00002; loupe; wait 1; spots on; spot add 0.3 0.4; spot add 0.7 0.6; spots off; focus SML_00002; wait 1; spots on; spot add 0.5 0.5; spots off; grid; wait 1; print stacks; focus IMG_00003; copyadjust spots; focus IMG_00002; key shift+down; key shift+down; wait 1; print selection; pasteadjust; wait 3; print stacks; print messages; undo; wait 2; print stacks; quit
```

IMG_00002 (same size as the source IMG_00003) went from 2 spots to none; SML_00002 kept its 1 spot; "Spots were
not pasted onto 1 photo: its size differs from the photo the spots were copied from."; `undo` brought the 2 spots
back.

**S9b, S9c (M7)**, `m7.sh m7a IMG_00002 …` and `m7.sh m7b IMG_00003 …`; the first argument of each is
`wait 2; focus IMG_00002; loupe; wait 1; spots on; spot add 0.3 0.4; spot add 0.7 0.6; spots off; grid; wait 1; copyadjust spots`
and the last is `selectall; pasteadjust; wait 4; print stacks; print messages; quit`. Results in M7 detail above.

**S9d: Color Alignment pasted with a master missing (AC8)**, `m7.sh ca IMG_00003 "wait 2; focus IMG_00002; loupe; wait 1; adjust align auto on; wait 1; print adjustments; grid; wait 1; copyadjust colorAlignment" "selectall; pasteadjust; wait 8; print stacks; print messages; quit"`:
IMG_00001, SML_00001, SML_00002 got `colorAlignment` (each measured), IMG_00003 did not: "1 photo was left unchanged:
its original could not be read." and "1 video was left unchanged."

**S10: the frame question (AC8, M10)**, `run.sh m10`:

```
focus IMG_00002; loupe; wait 1; lens distortion on; lens distortion manual; lens distortion amount 10; spots on; spot add 0.3 0.4; spot add 0.7 0.6; spots off; focus IMG_00003; wait 1; spots on; spot add 0.5 0.5; spots off; focus IMG_00002; wait 1; copyadjust spots distortion; print clipboard; print stacks; alert; focus SML_00002; wait 1; pasteadjust; wait 2; alert; print stacks; print messages; focus IMG_00003; wait 1; pasteadjust; wait 2; alert; alert press Cancel; wait 1; print stacks; pasteadjust; wait 2; alert press Change; wait 2; print stacks; undo; wait 1; print stacks; quit
```

SML_00002 (no spots, other size): `alert none`, got `lensDistortion`, no spots, size-differs warning. IMG_00003 (one
spot of its own): the alert "Change distortion on a photo with masks or spots?" with Cancel (Esc) and Change
(default); Cancel wrote nothing (`[spots]`, 1 spot); Change gave `[lensDistortion spots]` with 2 spots; `undo`
restored `[spots]`, 1 spot. (A first attempt that added the spots before Distortion on the source asked its own
question on that photo, as it should; it is not what this script tests.)

**S11: unreadable edits and a photo with no adjustments (R1)**, `Gus --library-root $Q/lib-ur` with a copy of `lib0`
where `sqlite3 … "update version set editStack='{\"operations\":[],\"schemaVersion\":99}' where id in (1,3)"`:

```
wait 2; print items; focus IMG_00001; copyadjust sheet; print clipboard; print messages; loupe; wait 1; copyadjust sheet; print messages; grid; focus IMG_00002; copyadjust sheet; print copysheet; alert key escape; quit
```

IMG_00001 (schema 99), grid and loupe: no sheet, "These edits were saved by a newer version of Gus. Editing is off
so they are not lost." (Copy Adjustments), clipboard `none`. IMG_00002 (no adjustments): the sheet opens with
`noAdjustmentsNote true`, Copy off, "Check something to copy.", sheet 420 x 680 (ideal 680). A video opens no sheet
(S4).

**S13: size and picture (M3)**, `run.sh sw`:

```
wait 2; windowsize 760 480; wait 1; focus IMG_00001; loupe; wait 1; adjust exposure 0.5; grid; wait 1; copyadjust sheet; snapshot $Q/sheet-short.png; alert key escape; windowsize 1280 860; wait 1; copyadjust sheet; snapshot $Q/sheet-default.png; alert key escape; quit
```

760 x 480: sheet 420 x 480, list 520 of which 340 shown (scrolls), header, masks note and buttons visible
(`sheet-short.png`). Default: 420 x 660, not scrolled (`sheet-default.png`): both pictures looked at; labels,
trailing text, captions, mixed Light box, the masks note ("Presets and Paste Adjustments leave masks out.") and the
buttons are as designed, nothing clipped.

**S12: entry points**, `run.sh cm` and `run.sh tb`:

```
wait 2; focus IMG_00001; contextmenu cell 0; loupe; wait 1; contextmenu loupe; copyadjust all; grid; focus MVI_00004; loupe; wait 1; contextmenu video; toolbar; quit
wait 2; focus IMG_00001; toolbar add copyAdjustments; toolbar add pasteAdjustments; toolbar; copyadjust light; wait 1; buttons; quit
```

"Copy Adjustments…" in the grid and loupe context menus, none in the video's; both toolbar items insertable; the
tooltip after a copy is "Paste Adjustments: Tone".

**S14: comparing (AC11)**, `runopen.sh cq2`:

```
print menustate; focus IMG_00001; key shift+right; wait 1; compare on; wait 2; compare active left; copyadjust sheet; alert key escape; compare active right; copyadjust sheet; alert key escape; compare off; quit
```

"From IMG_00001", then "From SML_00001": Copy takes the active photo.

**Full test run**: `swift test` (log in the scratchpad): "Test run with 1452 tests in 206 suites passed after 79.540
seconds", no `✘` line. `Scripts/build-app.sh`: exit 0, bundle signed.

**End-of-run checks**: no `Gus` process running (`pgrep -l -x Gus` empty); `find
~/Library/Application\ Support/Gus/Library -newer <marker made before the first launch>` printed nothing (the
newest owner file is `catalog.sqlite-wal`, Nov 20); `git status` of the checkout clean; the scratch sources I
moved for M7 are back in place.

## For a person

None needs VoiceOver, macOS 15 or macOS 26 (CI only). Build the bundle and run it on a scratch library, never the
owner's (`Scripts/build-app.sh`, then the executable with `--library-root <scratch library from photobench>`);
use a library with a few photos, one pair of the same size and one of another.

- **P1 (M1, M3 by eye): the sheet's look beside Export's, in Light and with Increase Contrast.** Edit one photo
  (Exposure, Contrast, Color Grading), grid, ⇧⌘C. Look at the header (thumbnail, title, "From …", Check All and
  Uncheck All), the rows (20 pt pitch, indented groups, the trailing "No changes" in readable contrast, Crop &
  Straighten and Spots captions aligned with their label, not the box), the footer's masks note, Cancel and Copy.
  Expect nothing clipped or crowded and the same look as File ▸ Export… Then shrink the window to its smallest
  and open it again: the list scrolls, header, footer and buttons stay on screen. In a window of the default
  size it does not scroll.
- **P2 (AC12, M2): Full Keyboard Access.** System Settings ▸ Keyboard ▸ Keyboard navigation on. Open the sheet,
  press Tab through every box (Check All and Uncheck All come first), Space on a few, Return, then ⇧⌘V on another
  photo. Expect every box reachable and toggled by Space (a heading toggles its groups, shows mixed), a box
  focused out of view scrolls into view, Return copies, Esc cancels, and Return with every box unchecked does
  nothing.
- **P3 (M4): a real mouse on a mixed heading.** With Tone checked and White Balance and Presence not, Light shows
  a dash. Click it: all three check; click again: all uncheck. Click a row's name and its trailing text: one
  toggle each, and the text follows the box ("Resets on paste" for a checked group with no changes).
- **P4 (M5, M9): the real keys.** On a series of the same size: edit one photo, ⇧⌘C, Space on a box, Return,
  select the rest, ⇧⌘V, then ⌘Z once: every photo is back, in one step. Then in the loupe, copy Spots and
  paste ⇧⌘V onto one photo of the same size and press ⌘Z at once: the paste is undone, not the step before it.
  (In the grid, with one photo, a ⌘Z in the first instant can undo the step before; that is the documented limit.)
- **P5 (M8): the toolbar items.** View ▸ Customize Toolbar…: add Copy Adjustments and Paste Adjustments. Click
  the Copy item: the sheet opens. Hover Paste Adjustments with nothing copied: "Paste Adjustments"; after copying
  Tone and Color Grading: "Paste Adjustments: Tone, Color Grading"; after another copy it follows.
- **P6 (M6, optional, low risk): a Luminar pack import ending while the sheet is up.** With one of your `.lnpc`
  packs, start Import Presets… (Adjust menu), then ⇧⌘C and leave the sheet up until the import ends. Expect the
  preset manager's report to wait and open only after the sheet closes.

## Follow-up

(Nothing yet: no findings. The owner's sign-off, the commit signed off, its date and any checks left open go here
when the main session relays them.)
