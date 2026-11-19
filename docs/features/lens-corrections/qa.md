# Lens corrections (Distortion and Lens Vignetting): QA

Owner: qa-tester. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/lens-corrections` at a97a56c (the last commit that changes
`Sources/`, `Tests/` or goldens; HEAD 59b40c4 adds only the code review's fifth
pass), on a Mac16,8 (Apple M4 Pro), macOS 27.2.1 (26B131), Xcode SDK 27.2.
Issue #87, PRD rev2 (2026-11-19), against `design.md`, `status.md`, `review.md`
(M1 to M23) and `code-review.md` (fifth pass, ready for QA).

## Verdict

**Passes.** 12 of 14 acceptance criteria pass by test or by script, none fails,
and no finding needs the engineer. Two are open for a person: AC13's by-eye check
(Lens Vignetting on the XF14 and XF23 files beside the camera's JPEG) and the live
half of AC10 (a drag and the 100% region against fit; no test or script reaches
them). The designer's M1 to M23 are folded into P1 to P13 below.

Safety checks (end of run): no instance of the app or `photocli` is running;
nothing under `~/Library/Application Support/Gus` or in `~/Library/Caches/Gus`,
`~/Library/Caches/me.sesser.gus` or `~/Library/Preferences/me.sesser.gus.plist` is
newer than the start of the run (11:53 PST); every app launch and every `photocli`
call, `render --input` included, carried `--library-root` on a scratch library.

## Acceptance criteria

How is Test, Script or Person. Evidence names the test (suite "Lens corrections"
in `LensCorrectionTests.swift` unless said) or the script in "Scripts" below.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 (R1, R14) Old stacks render as before; the check box is on every photo; on stores an explicit `on` | Test, Script | `explicitOn`, `untouched` (no lens step, same object back, without the groups); every existing golden still passes (`GoldenTests` green; `git diff --stat origin/develop...HEAD` shows only five added golden PNGs, no fingerprint file, no migration, no `PreviewCacheKey` change: `currentPipelineVersion` is 13); `photocli render` of the RAF and RW2 with no groups gives render hash `6c76a50e…` (an empty stack's); script A1, B1, C2, D1: `lens print` reports a check box (`checked false`) for both groups on a JPEG, a RAF, an RW2 and a DNG | Pass |
| AC2 (R2) Manual Distortion and Lens Vignetting match the CPU reference | Test | `distortionMatchesReference` (5 amounts, with and without Constrain, on `lensGrid`), `vignettingMatchesReference` (100, 35, −50), `vignettingScale`; goldens `lensDistortion-barrel-lensGrid`, `lensVignetting-lighten-grayRamp`; `photocli` render of the XF14 RAF with Lens Vignetting on Auto: corners 3.5 to 5.8 points brighter (mean of 60 px squares, 0 to 100), center unchanged (T1) | Pass |
| AC3 (R3) Auto reads a Fujifilm RAF's and a DNG's tables; no table gives the caption and an unchanged render; a non-raw starts in Manual; a manual Amount kept while Auto | Test, Script | `rafState`, `dngOpcodeParsing`, `dngFile`, `otherStates`, `captions`, `manualAmountKeptInAuto`, `segments`, `storedAmountClamped`; `dngSample` (opt-in, Adobe's `03_jxl_bayer_raw_integer.dng`, passes: its green plane moves nothing, so no distortion table); scripts B1 (XF14 RAF: Distortion `noTable`, Lens Vignetting `tableAvailable` then `usingTable`, applies), B2 (Auto Distortion with Amount 40 stored: `applies false`, amount kept, kept on a pasted JPEG), A1 (JPEG: Auto dimmed, checking starts Manual), D1 (RW2); `photocli render` T1: RAF Distortion Auto is byte-identical to off | Pass |
| AC4 (R4) Auto inert where the decoder or Fujifilm's built-in table corrects; Manual adds | Test, Script | `autoPlan`, `untouched`, `libRawBuiltIn`, `captions`, `fujifilmWarp`; script D1 (RW2 the system decoder corrects: `decoderCorrectsAuto`, Auto segment dimmed, Manual `decoderCorrectsManual` applies); `photocli render` T1 of the same RW2: Auto on both groups is byte-identical to off, Manual +40 differs and says `applied true` | Pass |
| AC5 (R5) Picker and Color Alignment read the corrected image; gain is before exposure | Test | `pickerSeesCorrectedImage`, `vignettingBeforeExposure`; mutation M6 and M7 (below) are caught | Pass |
| AC6 (R6) The frame question: asked once per visit, only when the frame moves, at commit for a drag, Cancel restores; once with counts for paste and preset; never for Undo, Redo, History, Reset All | Script (the rule: Test) | `movesFrame` for when it moves; scripts A1 (Turn On at Amount 0 asks nothing; Amount 40 asks; Cancel leaves 0 and the undo top at "Turn On Distortion"; Change records "Distortion Amount"; a second change on the visit, Constrain, and Lens Vignetting ask nothing), E2 (after Change and a new visit: Reset Lens asks, Cancel restores, Change records "Reset Lens"; Undo, Redo, Reset All and History revert never ask; Reset All on a new visit asks nothing), F2 (paste to 114 asks once "1 of the 114 photos has masks or spots", Cancel writes nothing, Return gives one "Paste Adjustments" that one Undo removes), F4 (the same for a preset) | Pass |
| AC7 (R7) Constrain to image fills the frame; the crop still applies after | Test | `constrainFills`, `cropAfterCorrection`; goldens `lensDistortion-pincushionOpen-lensGrid` (Constrain off), `lensDistortion-spotCrop-dustySky`; mutation M5 (below) is caught | Pass |
| AC8 (R8) Paste and presets carry both groups; each photo looks up its own table; no table: nothing applied, Amount kept | Test, Script | `groupsAndPresets`, `autoPlan`, `manualAmountKeptInAuto`; scripts F4 (preset "dl [Distortion, Lens Vignetting]" applies Manual 30 / 25 to every photo), B2 (Auto with Amount 40 on a JPEG: kept, not applied), G1 | Pass |
| AC9 (R9) A pair's JPEG has no Auto; one file's edit leaves the other; Manual on a decoder-corrected raw applies | Script, Test | script C2 (`pairs separate`: the JPEG's Auto dimmed `autoUnavailable notRaw`, a Lens Vignetting amount set on it leaves the DNG's off), D1 (RW2); `otherStates`, `segments` | Pass |
| AC10 (R10) Fit, 100%, a live drag, an export and `photocli` agree | Script, Test, Person | one renderer; export-size against fit measured through `photocli render` (T2: the full 4000×6000 render, reduced, against the 1200 px render, RMSE 1.64% with Distortion +40 and Lens Vignetting +50 against 1.56% with no edit, and 10.4% for the effect itself); `render --input` and `render --version` of the same file give identical bytes (T1). The live frames and the 100% region have no test and no script: P8 | Pass for export, preview and `photocli`; **Open** for live frames and 100% (P8) |
| AC11 (R11) Kernel or table failure is told on the group | Test, Script | `kernelFailure`, `corruptSwitch`, `rafState` (damaged), `dngFile` (damaged); script I1 (`lens force kernelfail`: Lens Vignetting row `kernelsUnavailable`, warning; `tablecorrupt`: `tableUnreadable` on both, warning; off again: `usingTable`) | Pass |
| AC12 (R14) Reset gives the identity hash; an unknown newer schema is refused as before | Test | `resetAndRoundTrip`; script E2 (Reset Lens and Reset All return distortion off, amount 0, History "Reset Lens" / "Reset Adjustments"); the schema refusal is the existing reader, unchanged by the diff | Pass |
| AC13 (all) Goldens with a bump, CPU references; by eye: Lens Vignetting on the XF14 and XF23 files within about 1 px of the camera's JPEG | Test, Person | five goldens present as the only golden changes (`lensCorrections-fujifilmAuto-lensGrid`, `lensDistortion-barrel-lensGrid`, `lensDistortion-pincushionOpen-lensGrid`, `lensDistortion-spotCrop-dustySky`, `lensVignetting-lighten-grayRamp`); `LensCorrectionReference.swift`; no tolerance loosened (the `GoldenTests.swift` diff only adds cases and the lens argument). By eye: P1. The PRD's wording for the DNG sample is to be fixed at Ship (the Adobe sample's distortion is a no-op on green, see AC3) | Goldens and references Pass; by-eye **Open** (P1) |
| AC14 (R15) A Source segment on an off group turns it on in one step; one Undo restores | Test, Script | `choosingSource`; script B1 (`lens vignetting manual`: on, Manual, undo "Lens Vignetting Source"; one `undo`: off, Source Auto, nothing left on the undo stack; `lens vignetting auto` twice: the first turns on in one step, the second records nothing) | Pass |

Counts: 14 criteria. Pass by test only: AC1 (with scripts as a second look), AC2,
AC5, AC7, AC12 = 5. Pass by test and script: AC3, AC4, AC8, AC9, AC11, AC14 = 6.
Pass by script (the rule itself by test): AC6 = 1. Open for a person: AC10 (live
half) and AC13 (by eye) = 2. Failed: 0.

## Findings

None for the engineer. Observations (not failures):

- **Q1 (note).** `PhotoApp` has no test target, so the frame question's gate
  (`AdjustmentEditor.commit`), the batch read and the Activity row are checked only
  by the scripts (A1, E2, F2, F4, G1, and the engineer's S3 to S10). If one of those
  paths is changed later, only the debug script will say.
- **Q2 (note).** `constrainFills` builds a `LensWarp` directly, so it does not
  cover how `LensCorrectionPlan` maps the Constrain check box; mutation M5 is caught
  by two goldens and `untouched` instead. Enough, but the mapping has no test of its
  own.
- **Q3 (note).** No test follows a decoder's lens flag from the file to a render
  (`PreviewGenerator` reads `isLensCorrectionSupported && isLensCorrectionEnabled`
  on the filter it decodes with). It is checked by `photocli render` on a real RW2
  here (AC4, T1), and the unit tests reach it through `CameraLensState.read`
  (mutation M4 is caught).
- **Q4 (note, existing).** The six RAW goldens are skipped on this macOS build
  (27.2.1, 26B131, against 27.2, 26B123 recorded; #214). Nothing in this branch
  changed their fingerprints.
- A script that runs `adjust reset lens` (or any command that asks) and then
  `alert none` without a `wait 1` sees no sheet and a question marked "asking": the
  sheet is attached a moment later. Script timing, not a defect (E1 shows it; E2
  waits and answers).

## Mutation checks (a scratch copy of the branch outside the checkout)

`git archive HEAD` into `…/scratchpad/qa87/mut`, one line changed at a time, then
`swift test --filter "LensCorrectionTests|GoldenTests"` (40 tests in 2 suites;
the unmutated copy passes). Each mutation must fail a test.

| # | One-line change | Failing tests |
|---|---|---|
| M1 | Auto with no table applies the manual Amount (R3, R8) | "A manual Amount saved while Source is Auto is kept and not applied", "Auto applies the file's tables, and nothing where something else corrects…", "A stack without the groups, or with Auto where it can't apply…", "Only a change of the warp moves the frame" |
| M2 | `movesFrame` always false (R6) | "Only a change of the warp moves the frame (R6)" |
| M3 | `choosingLensSource` no longer turns the group on (R15) | "A Source segment chosen while the group is off turns it on…" |
| M4 | the decoder-corrects flag ignored when a file is read (R4) | "A RAF's tables…", "Not a raw, and raws with no table we read", "The debug switch reads every usable table as damaged" |
| M5 | Constrain never reaches the manual warp (R7) | "A stack without the groups…", "Only a change of the warp moves the frame", goldens `lensDistortion-barrel-lensGrid` and `lensDistortion-spotCrop-dustySky` |
| M6 | warp before gain in the renderer (design order) | golden `lensCorrections-fujifilmAuto-lensGrid` only |
| M7 | the lens step after spots and crop (R5, mask frame) | "The crop still applies after the correction (AC7)", golden `lensDistortion-spotCrop-dustySky` |

## Scripts

Setup, once. `Q` is a scratch folder (`…/scratchpad/qa87`); nothing here touches the
owner's library, and each run copies the library afresh.

```
cd <checkout> && Scripts/build-app.sh
cp -R build/Gus.app $Q/app/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.qa87 $Q/app/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $Q/app/Gus.app
swift run -c release photobench generate --output $Q/synth --jpeg 6 --dng 2 --pairs 2
mkdir $Q/synth/Shoot-002 && cp <scratch copies of DSCF7407.RAF, P1180211.RW2> $Q/synth/Shoot-002/
swift run -c release photobench import --library-root $Q/template --source $Q/synth
```

`DSCF7407.RAF` (X-E3, XF14: vignetting table, distortion table all zero) and
`P1180211.RW2` (GX7 II, Lumix 12-32: the system decoder corrects) were copies of
the owner's files already in a scratch folder. `run.sh <name> "<script>"` copies
`$Q/template` to `$Q/runs/<name>/lib` and runs
`$Q/app/Gus.app/Contents/MacOS/Gus --library-root $Q/runs/<name>/lib --debug-script "<script>"`.
Index 109 is `PAIR_00109.DNG` and 110 `PAIR_00109.JPG` with `pairs separate`.

**A1: JPEG with a spot, the frame question (AC3 non-raw, AC6).**

```
wait 2; focus IMG_00001; loupe; tab adjust; wait 2; spots on; spot add 0.5 0.5; spots off; print undo; lens print; lens distortion on; print undo; lens distortion amount 40; alert none; print undo; lens print; alert press Cancel; print undo; lens print; lens distortion amount 40; alert press Change; print undo; lens print; lens distortion amount 20; alert none; print undo; lens distortion constrain off; print undo; lens vignetting amount 30; alert none; print undo; lens print; quit
```

Showed: Auto dimmed (`autoUnavailable notRaw`, no segment selected); "Turn On
Distortion" asks nothing (Amount 0 moves nothing) and starts in Manual; Amount 40
asks ("Change distortion on a photo with masks or spots?", Change default, Cancel
on Esc); Cancel leaves Amount 0 and the undo top "Turn On Distortion"; Change
records "Distortion Amount"; the next change, Constrain off and Lens Vignetting
(30) ask nothing.

**B1: the XF14 RAF, Source segments (AC3, AC14).**

```
wait 2; focus DSCF7407; loupe; tab adjust; wait 4; print title; lens print; lens vignetting manual; print undo; lens print; undo; print undo; lens print; lens vignetting auto; print undo; lens print; lens vignetting auto; print undo; undo; wait 1; print undo; lens print; quit
```

Showed: state `tables(fujifilm distortion false vignetting true)`; Distortion
`noTable`; Lens Vignetting `tableAvailable` (off). `lens vignetting manual`: on,
Manual, one step "Lens Vignetting Source"; one `undo`: off, Auto, undo stack empty.
`lens vignetting auto` turns it on (`usingTable`, applies); the second records
nothing.

**B2: Auto with a stored Amount, then a paste (AC3).**

```
wait 2; focus DSCF7407; loupe; tab adjust; wait 4; lens distortion on; lens print; lens distortion manual; lens distortion amount 40; lens print; lens distortion auto; lens print; print undo; copyadjust; grid; focus IMG_00002; pasteadjust; loupe; wait 2; lens print; focus DSCF7407; wait 2; lens print; quit
```

Showed: Auto with no table: `applies false`; Manual 40: `applies true`; back to Auto:
`applies false`, amount 40 kept; pasted on the JPEG it stays Auto with 40 stored,
`autoUnavailableNotRaw`, not applied.

**C2: RAW+JPEG pair (AC9).**

```
wait 2; pairs separate; wait 1; focus 109; loupe; tab adjust; wait 3; print title; lens print; lens vignetting on; lens print; focus 110; wait 3; print title; lens print; lens vignetting on; lens vignetting amount 20; lens print; focus 109; wait 3; print title; lens print; quit
```

Showed: the DNG offers Auto (`noTable`, synthetic file); the JPEG's Auto is dimmed
and its Lens Vignetting went to Manual 20; back on the DNG its group is unchanged
(Auto, `noTable`, amount 0).

**D1: RW2 the system decoder corrects (AC4, AC9).**

```
wait 2; focus P1180211; loupe; tab adjust; wait 4; print title; lens print; lens distortion on; lens print; lens distortion manual; lens distortion amount 40; lens print; lens distortion auto; lens print; quit
```

Showed: state `decoderCorrects`; row `decoderCorrectsAuto`, Auto dimmed; checking starts
in Manual (`decoderCorrectsManual`); Amount 40 applies; `lens distortion auto` does
nothing (Source stays Manual).

**E2: once per visit, Reset Lens, Undo, Redo, Reset All, History (AC6, AC12).**

```
wait 2; focus IMG_00001; loupe; tab adjust; wait 2; spots on; spot add 0.5 0.5; spots off; lens distortion on; lens distortion amount 40; alert press Change; focus IMG_00002; wait 2; focus IMG_00001; wait 2; lens print; adjust reset lens; wait 1; alert none; alert press Cancel; wait 1; print undo; lens print; adjust reset lens; wait 1; alert press Change; print undo; lens print; undo; wait 1; alert none; print undo; lens print; redo; wait 1; alert none; print undo; lens print; focus IMG_00002; wait 2; focus IMG_00001; wait 2; adjust reset; wait 1; alert none; print undo; lens print; history open; history wait; history revert 2; wait 1; alert none; print undo; lens print; quit
```

Showed: on a new visit (`answered no`), Reset Lens asks; Cancel keeps Amount 40;
Change records "Reset Lens" (`answered 1`); Undo and Redo show no sheet;
Reset All on another new visit asks nothing and records "Reset Adjustments"
(distortion off, amount 0); History revert to the state with Distortion 40 asks
nothing ("Revert to “Undo Reset Lens”", warp back on). E1 is the same without
waits: Amount 40 (Change), then 25 on the same visit asked nothing; on the next visit
Amount 10 asked again and Cancel restored 25.

**F2 and F4: paste and preset to a selection of 114 with one spot (AC6, AC8).**

```
F2: wait 2; focus IMG_00001; loupe; tab adjust; wait 2; spots on; spot add 0.5 0.5; spots off; grid; focus IMG_00002; loupe; wait 2; lens distortion on; lens distortion amount 30; grid; copyadjust; selectall; pasteadjust; wait 2; alert press Cancel; wait 1; print undo; pasteadjust; wait 2; alert key return; wait 2; print undo; focus IMG_00003; loupe; wait 2; lens print; focus IMG_00001; wait 2; lens print; undo; wait 2; print undo; focus IMG_00003; wait 2; lens print; focus IMG_00001; wait 2; lens print; quit
F4: wait 2; focus IMG_00001; loupe; tab adjust; wait 2; spots on; spot add 0.5 0.5; spots off; grid; focus IMG_00002; loupe; wait 2; lens distortion on; lens distortion amount 30; lens vignetting on; lens vignetting amount 25; preset save dl; grid; wait 1; copyadjust; selectall; preset apply dl; wait 2; alert none; alert press Cancel; wait 1; print undo; focus IMG_00003; loupe; wait 2; lens print; grid; wait 1; copyadjust; selectall; preset apply dl; wait 2; alert key return; wait 2; print undo; focus IMG_00003; loupe; wait 2; lens print; quit
```

Showed: one alert for the whole selection, "1 of the 114 photos has masks or
spots…"; Cancel writes nothing; Return gives one "Paste Adjustments" ("Apply Preset
dl") and the photos with and without the spot carry Manual 30 (and 25); one Undo
takes it back everywhere. The preset "dl" is listed as `[Distortion, Lens
Vignetting]`. (A first F1 run lost its second `selectall` to a missing grid focus,
a script slip: the runs above wait before it.)

**G1: a newer preset ends a pending paste read (C13).**

```
wait 2; focus P1180211; loupe; tab adjust; wait 3; spots on; spot add 0.5 0.5; spots off; grid; wait 1; focus IMG_00003; loupe; wait 2; lens distortion on; lens distortion amount 30; preset save dl; grid; wait 1; focus DSCF7407; loupe; wait 3; lens distortion on; grid; wait 1; copyadjust; selectall; lens pastethenpreset dl IMG_00017; print activity; alert none; print undo; focus P1180211; loupe; wait 3; lens print; focus IMG_00017; wait 2; lens print; focus DSCF7407; wait 3; lens print; quit
```

Showed: the paste's read was pending when the preset came (`read pending true`); at
the end Activity has no jobs and no row, no alert; the RW2 (a paste target with a
spot) has Distortion off, so the older paste was never written; IMG_00017 has the
preset's Manual 30; undo top "Apply Preset dl".

**H1: Constrain on a never-on group (design DQ-4).**

```
wait 2; focus IMG_00004; loupe; tab adjust; wait 2; lens distortion constrain off; print undo; lens print; focus P1180211; wait 3; lens distortion constrain off; print undo; lens print; focus DSCF7407; wait 3; lens distortion constrain off; print undo; lens print; quit
```

Showed: on the JPEG and the decoder-corrected RW2 the group turns on in Manual
(`manual`, `decoderCorrectsManual`) in the one step "Turn Off Constrain to Image";
on the XF14 RAF, where Auto can apply, it turns on in Auto (`noTable`).

**I1: failure switches (AC11).**

```
wait 2; focus DSCF7407; loupe; tab adjust; wait 3; lens vignetting on; lens force kernelfail; lens print; lens force tablecorrupt; lens print; lens force off; lens print; quit
```

Showed: `kernelsUnavailable` ("Lens correction could not be set up on this Mac, so
this group changes nothing."), then `tableUnreadable` on both groups ("The camera's
table in this file could not be read…"), both with a warning, then `usingTable`.

**J1: inspector width and controls.**

```
wait 2; focus DSCF7407; loupe; tab adjust; wait 3; lens distortion on; lens vignetting on; print inspectorwidth; buttons; snapshot $Q/runs/J1/a.png; quit
```

Showed: `inspectorwidth visible 283 controls 8…275 widest NSSegmentedControl 259 fits`
(the Tone Curve's, not a Source control); `buttons` lists the Lens, Distortion and
Lens Vignetting check boxes with "Turn off … to compare", the two Source segmented
controls (selected 0), Constrain to image with the tooltip "Scale the corrected
photo to fill its frame, with no empty edge.", and Reset Lens. The snapshot's
content area is right (the XF14 photo with Lens Vignetting on Auto; the glass panes
are blank, as known). The narrowest inspector (256 pt) can't be set by script: P2.

**T1 and T2: `photocli`, every call with `--library-root $Q/clilib` (a copy of the
template).** Versions: RAF 113, RW2 114, IMG_00001 1.

```
photocli render --version 113 --library-root $Q/clilib --out raf-off.png --long-edge 1200
  … --set lensVignetting.on=true                       (raf-vig.png)
  … --set lensDistortion.on=true --set lensDistortion.source=manual --set lensDistortion.amount=40   (raf-dist.png)
  … --set lensDistortion.on=true                       (raf-distauto.png)
photocli render --version 114 --library-root $Q/clilib … (off, Auto on both, Manual 40)
photocli render --version 1 --library-root $Q/clilib …   (JPEG: Auto, Manual 40)
photocli render --input $Q/raws/DSCF7407.RAF --library-root $Q/clilib --out input-vig.png --long-edge 1200 --set lensVignetting.on=true
photocli develop --version 113 --dry-run --library-root $Q/clilib --set lensDistortion.on=true --set lensDistortion.source=manual --set lensDistortion.amount=40
photocli develop --version 113 --library-root $Q/clilib --set lensDistortion.on=true ; … --reset lensDistortion
```

Showed: `render` prints `lensCorrections` per group: RAF off `noTable` /
`tableAvailable`, `applied false`; Auto Lens Vignetting `usingTable`, `applied
true`; Manual Distortion `manual`, `applied true`; the RW2 `decoderCorrectsAuto`
(not applied) for Auto and `decoderCorrectsManual` (applied) for Manual; the JPEG
`autoUnavailableNotRaw`, Manual applied. `cmp`: RAF off equals Distortion Auto,
byte for byte; RW2 off equals Auto on both groups; JPEG off equals Auto; the
Manual and the Lens Vignetting renders differ. `render --input` gives the same
bytes as `--version` (same render hash `7077d988…`). Mean brightness of 60 px
corners (off, then Lens Vignetting Auto): top left 83.4, 89.2; top right 69.1,
72.6; bottom left 74.6, 79.0; bottom right 73.6, 77.9; center 55.62, 55.64 (the
corners lift, the center does not). `develop` treats `on` as Black & White's: a
dry run shows `{"amount":40,"on":true,"source":"manual"}`; the write and the reset
leave the stack empty again and print no lens status (only `render` does). T2: the
full-size render of the same stack, reduced to 800×1200, against the 1200 px render:
RMSE 1.56% without an edit, 1.64% with Distortion +40 and Lens Vignetting +50;
off against on at 1200 px: 10.4%. (`--original` refuses `--set`, so Show Original
is P9.)

**Full test run.** `swift test` (whole log kept in `…/scratchpad/logs/full-test-1.log`):
**1240 tests in 176 suites passed** (69.3 s) on the first run; exit 0. The known
flake (`DeferredRenderTests`, #229) did not fail; the suite also passes alone (5
tests). `DNG_OPCODE_SAMPLE=…/03_jxl_bayer_raw_integer.dng swift test --filter
LensCorrectionTests/dngSample`: passes. `Scripts/build-app.sh`: builds, and the
executable records the macOS 27.2 SDK.

## For a person

No VoiceOver and no macOS 15 or 26 checks. Setup: build the bundle, give a copy its
own identifier, and launch it only with `--library-root` on a scratch library from
`photobench` (the commands are under "Scripts"); the owner may use a copy of their
own photos with a mask or a spot on at least one. A RAW+JPEG pair, an X-E3 XF14
or XF23 raw and a Lumix RW2 cover most of it.

- **P1 (M10, AC13).** Lens Vignetting on Auto on an X-E3 XF14 or XF23 raw beside
  the camera's own JPEG: corners within about 1 px of the JPEG's light in the outer
  quarter of the radius, by eye. This replaces the PRD's distortion by-eye check,
  which the owner's files can't give (the tables are all zero); the PRD's wording
  for AC13's DNG sample is to be corrected at Ship.
- **P2 (M1, M16).** The Lens heading at the narrowest (256 pt) and widest
  inspector, light, dark and Increase Contrast: both Source controls fit, nothing
  is clipped, the longest captions wrap, the check boxes are always visible and
  line up with the other groups', Constrain to image sits under its caption. With
  Keyboard Navigation on, Tab reaches check box, Source (arrows move, Space chooses),
  Amount field (arrows step), Constrain to image, in that order for each group.
- **P3 (M2, M7).** Real clicks on Source: a group off, click the selected segment:
  it turns on, one undo step "Distortion Source"; on, click the selected segment:
  nothing, no new step. Hover each segment, the dimmed Auto on a JPEG, on the Lumix
  RW2 and on a raw the system corrects included: the tooltip reads as design §5 and
  §3.2. Uncheck a group: its rows turn secondary and stay usable; moving Amount
  checks it again in one step.
- **P4 (M3).** Read the caption wording by file against design §4: the Lumix RW2
  (Auto stored, no segment selected, then Manual), the XF14 raw (Lens Vignetting off:
  "This file has a camera vignetting table. Turn on Lens Vignetting to use it.", on:
  "Using the camera's vignetting table from this file."; Distortion: "No distortion
  table was found…"), a Canon raw or a manual lens (the same), a JPEG (Auto
  unavailable, then Manual). The scripts read every row's text; this is for the
  wording and its look. Row 2a (Fujifilm's built-in table, a RAF LibRaw decodes) has
  no file on this Mac and rests on the test `libRawBuiltIn`.
- **P5 (M4, M5, M17).** The frame question with a real keyboard, on a photo with a
  spot: a check box, a Source click, an Amount drag released over the photo, a typed
  value with Return, Constrain to image, Reset Lens. Title and message as design §6;
  Change is the highlighted button; Return changes, Esc and ⌘. cancel. After Cancel
  the knob, field, check box and photo are as before, without a visible flip-flop,
  and Undo shows no new step; after Change, one step. A second change asks nothing;
  another photo and back asks again; add a spot and it asks again. With the sheet
  up, press ⌘V, ⌘Z, ⇧⌘Z, `\`, ⌥⌘R and an arrow key: nothing gets through.
- **P6 (M6, M18, M19, M22, M23).** A selection: mix a photo with a table, one
  without, a JPEG and one with a mask; Paste Adjustments from a photo with Manual
  Distortion 40, then Apply Preset with both groups on Auto. One alert each with
  "N of the M photos"; Cancel changes none; Change is one undo step. With five or
  more photos where a mask holder has Auto on a Fujifilm RAF or DNG, Activity shows
  the command's name with "N of M" and Stop while files are read, and the item
  disappears before the alert; Stop changes nothing. A long preset name is shortened
  in the toolbar capsule and whole in the popover; say whether a fast read makes the
  item blink. Start Auto Exposure on a large selection, then paste on another that
  reads files: both rows show, each Stop ends its own, the measurement survives; a
  paste that reads nothing adds no row. Paste, and while "0 of N" shows select other
  photos and paste again: no row stays. Read the guide's two sentences (lines 617 to
  621) against this.
- **P7 (M8, M9).** Constrain to image: on a wide raw or JPEG with Manual Distortion
  at +40 and −40: on, the photo fills the frame at both signs; off, a black edge
  shows for the pincushion setting; the crop still applies after. Sign and size: a
  JPEG with straight lines bowed outward: positive straightens them, negative bends
  them inward; Lens Vignetting positive lightens dark corners, negative darkens;
  one step of Amount is just visible at 100% in a corner.
- **P8 (M11, AC10).** At fit and at 100% a live drag of Amount and an export of the
  same value agree on a wide raw; the crop overlay and Straighten stay usable while
  Distortion changes; a spot ring lands on the same pixels after a correction
  (design §7). This is the one place no test and no script reaches.
- **P9 (M12, M13).** Presets: Save Adjustments as Preset and Manage Presets list
  Distortion and Lens Vignetting before Color Fringes in a tidy grid; an old "All
  settings" preset applied to a corrected photo turns Distortion off and asks when
  the photo has a mask or spot. Reset Lens returns the four groups to their starting
  state, the heading's check box mixed while some are on; `\` shows the photo without
  the correction; History lists "Turn On Distortion", "Distortion Source",
  "Distortion Amount", "Turn On/Off Constrain to Image", "Turn Off Distortion" and
  "Reset Lens", read against the Edit menu's Undo names.
- **P10 (M14).** While picking a fringe color with Distortion on (and with only Lens
  Vignetting on), the magnifier plate reads "After lens correction"; with both off,
  or Manual at 0, "Before edits".
- **P11 (M15).** A real RAW+JPEG pair: the JPEG's Auto is dimmed and a group checked
  on it starts in Manual; editing one file leaves the other. (Scripted on a synthetic
  pair, C2.)
- **P12 (M20).** First launch after a build: launch the new bundle on a scratch
  library, open a photo and watch the Adjust tab's Lens heading for three seconds:
  no flicker, no caption changing; then check a group and see the photo correct
  itself, late at worst.
- **P13 (M21).** In the grid select 20 photos, ⌘V, then ⌘Z at once: the paste is
  undone. Then the same with a selection of mask-holding Fujifilm RAFs, pressing ⌘Z
  while Activity shows the read; record what happens (the accepted limit: the step
  before the paste is undone).

## Follow-up

(Empty: reruns after fixes, the owner's reports on P1 to P13 and the sign-off go
here.)
