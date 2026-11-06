# ML noise reduction for RAW files: QA

Owner: qa-tester. Date: 2026-11-06. Step 4 of `docs/WORKFLOW.md`, run after
the merge to work down the checks the Ship pass left pending.
Tested: `feature/workflow-gaps` at `aee03c3`, the same commit as
`chore/project-cleanup` (`develop` at the PR #39 merge `334312c` plus
doc-only changes, so the shipped code), on an Apple M4 Pro,
macOS 27.2 (26B123), Xcode 27.2 with the macOS 27.2 SDK (the bundle records
`sdk 27.2`, `minos 15.0`).

## Verdict

**Passes, with one fix needed.** Every acceptance criterion that can run on
this Mac passes, by test and by script. The designer's M9 check fails: at
narrow window widths the "Machine Learning Not Applied" badge draws over the
loupe caption's rating and flag (Q1). What is left for a person is listed
under P1–P9: older macOS, real cameras and raws, the missing-model check
(RI-E6 d), the glass-pane look, VoiceOver, keyboard navigation and AC13.

## Acceptance criteria

Tests are in `Tests/PhotoCoreTests/MachineLearningNoiseReductionTests.swift`.
"ML" is the suite "Machine learning noise reduction" and "ML cli" is "Machine
learning noise reduction: photocli and export". On this Mac every test that
needs decoder version 9 ran and none was skipped. The full `swift test`
passed 551 tests in 96 suites, with 1 known issue: the `withKnownIssue` in
"Live render session", which was there before this feature.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Test | ML: "Flat areas: machine learning at Luminance 100 is quieter than at 0, export path and photocli render (AC1)". Fails without the behavior: if Luminance didn't reach the version 9 decoder, the two renders would be equal and `low < high` fails. | Pass |
| AC2 | Test | ML: "Edges: the machine learning render's edge contrast is not lower than classical at 100 (AC2)". It also asserts `outcome == .applied`, so a silent fallback fails it. | Pass |
| AC3 | Test | ML: "A stack without the setting keeps its parameters, render hash and decode settings (AC3)"; "The pinned default …(RI-7)"; "With the decoder's default at 9.dng, a stack that does not ask for it decodes with the pinned version (AC3)", which fails if the pin is removed. Goldens ("Module renders match their goldens", 47 cases), RAW goldens ("RAW decode settings match their goldens", which ran rather than skipped) and "Edit stack corpus" all pass. `PreviewCacheKey.currentPipelineVersion` is still 6. The only change to the corpus test since `054bf4e` is a doc-comment path. | Pass |
| AC4 | Test + Script | ML: the tests for legacy stacks (`9.dng` and `9`), the legacy stack with Profile off, the legacy stack with Noise Reduction off, "renders as before" (pixel-equal to a direct `9.dng` decode), Profile's `7.dng` kept, Profile-only preset, Profile paste and Profile off, the pre-feature preset (also after a catalog round trip and a preset-file round trip), the Decoder choice, and develop. Script [S-4](#s-4-decoder-pop-up-in-each-state) shows the pop-up and check box agreeing in every state. [S-photocli](#s-photocli-develop-render-export) shows `develop` never storing a disagreeing pair, in either `--set` order. | Pass |
| AC5 | Test + Script | ML: "Turning it on and off keeps the stored Color; Color is unavailable only while it applies (AC5)" and "Asked for and not applied, Color changes the render (AC5)". Script [S-1](#s-1-states-s1s8): Color is disabled with its tooltip in S2 only, enabled in S5–S8, and the stored 30 is kept across on and off. | Pass |
| AC6 | Test + Script + Person | ML: "The availability rule … (AC6)", "This Mac: …", "A missing model reads as not on this Mac … (AC6)" (seam), "No source file calls the decoder's model downloads (AC6, owner ruling 9)". Script [S-1](#s-1-states-s1s8): the synthetic DNG is available, S3 and S4 dim the box with their captions, and with `macos26` the older texts show ([S-9](#s-9-fallback-failure-and-export-rows)). [S-7](#s-7-paste-onto-a-mixed-selection-and-the-pair): a JPEG and the pair's JPEG show no check box. Still open for a person: macOS 15/26 (P6) and a real unsupported camera (P7). | Pass here; Open: P6, P7 |
| AC7 | Test + Script + Person | ML: "On a Mac without it … (AC7)"; ML cli: "Without it on this Mac: develop, render and export keep the setting and say why (AC7)". Script [S-9](#s-9-fallback-failure-and-export-rows), with the `notOnThisMac` override: the loupe shows S5 and the badge, an Exposure change keeps `machineLearning: true`, the export row says it wasn't applied, the stack still has it afterwards, and the canvas value reads "Machine learning not applied, 6 of 9". On a real Mac running macOS 15 or 26 (P6). | Pass under the seam; Open: P6 |
| AC7a | Test + Script | ML: "A failed decode on a supported file … (AC7a)"; ML cli: "A failed decode: render and export JSON and the export's Activity rows give the reason (AC7a)". Script [S-1](#s-1-states-s1s8): S8 caption, badge, session-only preview (`onDisk false sessionReason failed`). [S-9](#s-9-fallback-failure-and-export-rows): export row "1 photo was exported without machine learning noise reduction: it could not be applied to this photo." | Pass |
| AC8 | Script + Person | Script [S-10](#s-10-waiting-on-a-24-mp-ml-render): on the 6000 × 4000 DNG the spinner is off at 0.3 s and on at 0.8 s. During the wait the rating key `3` landed (rating 3 in the catalog) and → moved focus 7→8. The snapshot shows the photo, never a blank loupe. A real 24 MP raw on the owner's Mac is P4. | Pass on synthetic; Open: P4 |
| AC9 | Test + Script | ML: "Turning it on and off gives back the stack's bytes (AC9)". Script [S-6](#s-6-undo): the undo name is "Turn On Machine Learning", undo returns the stack to render hash `e62ede2fd4a0`, and redo restores it. [S-14](#s-14-z-in-the-active-app): launched active, the Edit menu shows "Undo Turn On Machine Learning ⌘Z" enabled, and the posted ⌘Z returns the stack to identity. The Luminance drag as one step is unchanged code (`change(… phase:)`) and was not driven by script. | Pass |
| AC10 | Test + Script | ML: "Paste and presets carry it to raws, never to other files; Reset All clears it (AC10)" (see Q4). Script [S-7](#s-7-paste-onto-a-mixed-selection-and-the-pair): pasting onto all 9 photos gave ML to the 4 DNGs and the pair's RAW, and left it off the 2 JPEGs, the 2 HEICs and the pair's JPEG. One Activity row says "…left off for 4 photos that aren't raw files." [S-8](#s-8-preset-reset-all-paste-onto-an-unsupported-camera): a Noise Reduction preset carries it, Reset All clears it, and a paste under the `cameraNotSupported` override stores it and shows S6. | Pass |
| AC11 | Test + Script | ML cli: "adjustments lists the setting; develop --dry-run prints a stack with it on (AC11)" and "Where it applies, render and export say so". Script [S-photocli](#s-photocli-develop-render-export) against a scratch library: same results, plus `invalidEdit` on a JPEG. | Pass |
| AC12 | Script | [S-bench](#s-bench-photobench-denoise): `photobench denoise --runs 3` runs. Medians: off 0.05 / 0.07 / 0.12 s, on 0.28 / 1.20 / 1.24 s, in line with the PRD's Measurements. | Pass |
| AC13 | Person | P9 (owner's judgment) | Open |

### Design checks (review.md M1–M9)

| M | How | Evidence | Result |
|---|---|---|---|
| M1 caption alignment | Person | P1 (glass pane: `snapshot` leaves it blank) | Open |
| M2 Increase Contrast | Person | P2 | Open |
| M3 VoiceOver | Script + Person | The canvas value "Machine learning not applied, 6 of 9" in S5 and S8 ([S-9](#s-9-fallback-failure-and-export-rows)). The check box, Color, pop-up and spinner speech are P3. | Partly Pass; Open: P3 |
| M4 waiting | Script + Person | [S-10](#s-10-waiting-on-a-24-mp-ml-render) on synthetic. A real raw and Reduce Motion are P4. | Partly Pass; Open: P4 |
| M5 keyboard | Script + Person | ⌘Z by [S-14](#s-14-z-in-the-active-app). Tab order and Space with Keyboard Navigation are P5. | Partly Pass; Open: P5 |
| M6 older macOS | Person | P6. Can't run on this Mac (macOS 27.2); the `macos26` override texts are checked in [S-9](#s-9-fallback-failure-and-export-rows) | Open |
| M7 real cameras | Person | P7. No camera raws in a photobench library | Open |
| M8 pair | Script | [S-7](#s-7-paste-onto-a-mixed-selection-and-the-pair): pasted onto the pair shown as its RAW, the RAW gets ML; after `pairfile jpeg` the JPEG shows no check box and has an empty stack | Pass |
| M9 caption at narrow window | Script | [S-12/13](#s-12-and-s-13-caption-line-at-narrow-widths): the badge overlaps the fifth star and the pick flag at the minimum window width | **Fail (Q1)** |

## Findings

**Q1 (Medium, M9). The "Machine Learning Not Applied" badge overlaps the
loupe caption's rating and flag at narrow window widths.**

- **Steps:** [S-12 and S-13](#s-12-and-s-13-caption-line-at-narrow-widths).
  Rate a DNG 5 and pick it, turn ML on, and put it in S6 (the
  `cameraNotSupported` override; S5 or S8 give the same badge). Hide the
  inspector and set `windowsize 600 450`. The window clamps to its minimum,
  760 × 532 pt, with the sidebar shown, so the loupe is about 440 pt wide.
- **Expected:** the badge, HDR, Offline and the film strip toggle don't
  overlap the centered rating, flag and label (review.md M9).
- **Actual:**
  - At 760 pt the badge's frame starts over the fifth star, and the green
    pick flag sits on top of "Machine". The film strip toggle stays clear.
  - At 820 pt the badge touches the flag.
  - At 900 pt there is a gap.
  - The same photo without the badge (`ml override clear`) is clear at
    760 pt.
- **Images:**
  `/private/tmp/claude-501/-Users-randy-Projects-Gus/ffe19c87-1232-45fa-9aaa-43df4389bead/scratchpad/qa/ml-denoise/s12-narrow.png`,
  `…/s13-820-caption.png`, `…/s13-900-caption.png`, `…/s13-noml-caption.png`
  (same folder).
- **Note:** the caption line is in the content area, which `snapshot`
  renders correctly. How the caption should give way is a design decision
  (see Design questions).

**Q2 (Low, debug script). `ml wait`, `ml ready` and `ml override` each leave
an empty, nameless undo step.**

- **Cause:** `"ml"` is in `DebugScript`'s `changing` set, so every `ml`
  subcommand gets an undo group.
- **Steps:** `ml on; ml wait; print undo; undo; print adjustments`.
- **Expected:** `undo 'Turn On Machine Learning'`, and the undo reverts it.
- **Actual:** `undo '' redo '-'`. `undo` reverts nothing: it undoes the
  empty group that `ml wait` left ([S-5](#s-5-undo-with-ml-wait-q2) against
  [S-6](#s-6-undo)).
- **Effect:** the `undo '…'` field of `print ml` reads '' after any of these
  subcommands, which is misleading in checks. Only `ml on`, `ml off` and
  `ml decoder` change photos and need a group.

**Q3 (Low, debug script). `ml override` can show a stale state.** It reloads
the editor at once, and two things then go wrong:

- **The last change is lost from view.** When `ml override` directly
  follows a change, the reload reads the stack from before that change,
  because the save is still on the write chain:
  - `adjust on noiseReduction; ml override notOnThisMac; print ml` printed
    `groupOn false`;
  - `ml off; ml override notOnThisMac; print ml` printed `asks true`
    ([S-4](#s-4-decoder-pop-up-in-each-state)).

  With `wait 1` before the override, both come out right
  ([S-5](#s-5-undo-with-ml-wait-q2)).
- **An old frame overrides the new setting.** A frame still in flight from
  the previous override can teach the editor `notOnThisMac`
  (`learnUnavailability`). In [S-9](#s-9-fallback-failure-and-export-rows),
  after `ml override notOnThisMac` and then `ml override fail`, the status
  stayed `notOnThisMac`, with that caption and badge, while the frame said
  `failed`.

This is debug-only: production overrides never change in a session. It does
make scripted checks unreliable unless they `wait` before an override and run
`ml override clear` between two overrides. The export row was right either
way.

**Q4 (Low, test). The AC10 test's "Reset All clears it" checks the Details
reset.** In "Paste and presets carry it to raws, never to other files; Reset
All clears it (AC10)" the assertion is `!raw.resetting(.details)
.asksForMachineLearning`. No assertion covers Reset All Adjustments. Reset
All was verified in the app by script ([S-8](#s-8-preset-reset-all-paste-onto-an-unsupported-camera):
the stack becomes `{"operations":[]}`), so the behavior passes. Add a Reset
All assertion, or rename the test.

No other test was found that would pass without the behavior its AC
describes.

## Design questions

For the designer (apple-ui-designer), raised by Q1.

**DQ-QA1. When a caption badge doesn't fit the loupe caption at narrow
widths, what gives way?**

Options:

- shrink the badge to an icon with a tooltip;
- truncate its text;
- wrap the caption onto a second line;
- move the badge somewhere else.

The facts, from S-12 and S-13 (sidebar shown, inspector hidden):

| Window width | Caption |
|---|---|
| 760 pt (the minimum) | "Machine Learning Not Applied" overlaps the fifth star and the pick flag |
| 820 pt | The badge touches the flag |
| 900 pt | Clear |
| 760 pt, same photo without the badge | Clear |

The sharpening map's badge has the same problem. In a narrow window it
truncates to "Shar…" (seen in the sharpen-mask-preview QA run). Please make
one ruling for both badges and for any later caption badge, so the
engineer's fix for Q1 follows one rule.

## Scripts

Everything ran against a copy of the bundle at
`$Q/QA.app`, with bundle identifier `me.sesser.gus.debugtest`, re-signed ad
hoc. `$Q` is
`/private/tmp/claude-501/-Users-randy-Projects-Gus/ffe19c87-1232-45fa-9aaa-43df4389bead/scratchpad/qa/ml-denoise`.
The scratch library was made by photobench:

```
swift run -c release photobench generate --output $Q/src/small --dng 3 --jpeg 2 --heic 2 --pairs 1 --dng-size 1600x1200
swift run -c release photobench generate --output $Q/src/big --dng 1 --jpeg 0 --heic 0 --dng-size 6000x4000
swift run -c release photobench import --library-root $Q/lib --source $Q/src/small
swift run -c release photobench import --library-root $Q/lib --source $Q/src/big
```

This gives RAW_00003–00005 (1600 × 1200 DNG), RAW_00001 (6000 × 4000 DNG),
PAIR_00008 (DNG + JPG), IMG_00001/2 (JPG) and IMG_00006/7 (HEIC). Version ids:
1, 2 JPG; 3, 4 HEIC; 5 PAIR DNG; 6 PAIR JPG; 7 RAW_00003; 8 RAW_00004;
9 RAW_00005; 10 RAW_00001. Each run starts from a fresh copy of that library:

```
rm -rf $Q/run-lib && cp -R $Q/lib.pristine $Q/run-lib
$Q/QA.app/Contents/MacOS/Gus --library-root $Q/run-lib --debug-script "<script>"
```

Stacks were read afterwards with
`photocli query images --library-root $Q/run-lib`.

The Light heading starts collapsed, so the Decoder pop-up isn't built until
it is expanded. `click 1321 411` (the Light disclosure) expanded it once, and
the debugtest copy's preferences keep it expanded.

### S-1: states S1–S8

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; ml ready; wait 1; scroll 0; wait 1; print ml; ml on; ml wait; print ml; adjust color-nr 30; ml wait; print adjustments; ml decoder 7.dng; ml wait; print ml; ml decoder 9.dng; ml wait; print ml; adjust off noiseReduction; ml wait; print ml; adjust on noiseReduction; ml wait; ml override notOnThisMac; ml wait; print ml; ml override cameraNotSupported; ml wait; print ml; ml override fail; adjust luminance-nr 35; ml wait; print ml; ml override clear; ml off; ml wait; print ml; print adjustments; ml override notOnThisMac; print ml; ml override cameraNotSupported; print ml; ml override clear; quit
```

What it showed, by state:

- **S1:** box off, enabled, with the §9 tooltip; Color enabled.
- **S2:** box on; caption "Luminance sets the amount. Color is kept but not
  used while this is on."; Color disabled with value 30 and the §5 tooltip;
  frame `applied`.
- **Decoder 7.dng:** ML goes off.
- **Decoder 9.dng:** ML goes back on.
- **S7:** `groupOff(applied)`, Color enabled, no badge.
- **S5:** caption "Not applied on this Mac. Luminance and Color apply
  instead." with the triangle (the macOS 27 text, §16); badge tooltip "…isn't
  available on this Mac…".
- **S6:** "Not applied: this camera isn't supported…"; badge.
- **S8:** "Not applied: it could not be applied to this photo…"; badge;
  `preview cached true onDisk false sessionReason failed`.
- **After `ml off`:** the stack is `rawDecode 7.dng`, plus Noise Reduction
  with color 30 and luminance 35, without ML. Profile's choice is kept.
- **S3:** box off, dimmed, "Not available on this Mac."
- **S4:** box off, dimmed, "Not available for this camera."

### S-4: Decoder pop-up in each state

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; ml ready; wait 1; print ml; adjust luminance-nr 20; ml wait; print undo; ml on; ml wait; print undo; print ml; ml decoder 7.dng; ml wait; print undo; print ml; ml decoder 9.dng; ml wait; adjust off noiseReduction; ml wait; print ml; adjust on noiseReduction; ml override notOnThisMac; print ml; ml override cameraNotSupported; print ml; ml override fail; adjust luminance-nr 30; ml wait; print ml; ml override clear; ml off; ml override notOnThisMac; print ml; ml override clear; quit
```

The pop-up, by state:

| State | Selected | Enabled | Items listed |
|---|---|---|---|
| S1 | "8.dng (default)" | yes | 9.dng (machine learning), 8.dng (default), 7.dng, 6.dng |
| S2 | "9.dng (machine learning)" | yes | same |
| 7.dng chosen | "7.dng" | yes | same |
| S7 | "7.dng" (Profile's choice) | yes | same |
| S6, S8, S5 | "7.dng" | no, tooltip "Turn off Use machine learning to choose another decoder." | S8 lists 9.dng; S5 and S6 don't (not available there) |

The two stale states after an override are Q3.

### S-5: undo with `ml wait` (Q2)

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; ml ready; wait 1; adjust luminance-nr 20; ml wait; wait 1; print adjustments; ml on; ml wait; wait 1; print undo; menuitems Undo; print adjustments; undo; wait 1; ml wait; print adjustments; print ml; redo; wait 1; ml wait; print adjustments; ml off; wait 1; ml override notOnThisMac; print ml; ml override clear; quit
```

- `print undo` gave `undo '' redo '-'`, and `undo` left `machineLearning:
  true` in place (Q2).
- `menuitems Undo` printed "disabled": a shell launch has no key window.
- With `wait 1` before the override, S3 came out right.

### S-6: undo

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; wait 3; adjust luminance-nr 20; wait 2; print undo; ml on; wait 3; print undo; print adjustments; undo; wait 2; print undo; print adjustments; print ml; redo; wait 3; print adjustments; ml wait; print undo; quit
```

| After | Undo | Redo | Stack | Hash |
|---|---|---|---|---|
| Luminance 20 | 'Debug luminance-nr' | – | luminance 20 | `e62ede2fd4a0` |
| `ml on` | 'Turn On Machine Learning' | – | luminance 20, `machineLearning: true` | `6a8287df9cea` |
| `undo` | 'Debug luminance-nr' | 'Turn On Machine Learning' | luminance 20 | `e62ede2fd4a0` (S1) |
| `redo` | | | `machineLearning: true` again | `6a8287df9cea` |
| a final `ml wait` | '' | | | |

That last row is Q2.

### S-7: paste onto a mixed selection, and the pair

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; wait 3; adjust luminance-nr 40; adjust color-nr 25; ml on; wait 3; copyadjust; grid; wait 1; selectall; pasteadjust; wait 5; print messages; focus PAIR_00008; loupe; wait 3; print ml; pairfile jpeg; wait 3; print ml; print adjustments; pairfile raw; wait 2; focus IMG_00001; loupe; wait 3; print ml; quit
```

- **Activity:** "[Paste Adjustments] information: Machine learning noise
  reduction was left off for 4 photos that aren't raw files."
- **The pair, shown as its RAW:** S2, and the pop-up shows "9.dng (machine
  learning)".
- **After `pairfile jpeg`:** `notOffered`, no check box, and stack
  `{"operations":[]}`.
- **IMG_00001:** no check box.

`photocli query images` afterwards:

| Photos | Noise Reduction stored |
|---|---|
| PAIR_00008.DNG, RAW_00001, RAW_00003, RAW_00004, RAW_00005 | `{color 25, luminance 40, machineLearning true}` |
| IMG_00001, IMG_00002 (JPG), IMG_00006, IMG_00007 (HEIC) | `{color 25, luminance 40}` |
| PAIR_00008.JPG | none (the paste didn't reach it) |

### S-8: preset, Reset All, paste onto an unsupported camera

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; wait 3; adjust luminance-nr 40; ml on; wait 3; preset save NRML; preset; adjust reset all; wait 3; print adjustments; preset apply NRML; wait 3; print adjustments; ml override cameraNotSupported; wait 1; copyadjust; grid; wait 1; selectall; pasteadjust; wait 5; print messages; focus RAW_00004; loupe; wait 3; print ml; quit
```

- `presets NRML [Noise Reduction]`.
- Reset All gave `{"operations":[]}`.
- Applying NRML gave `{luminance 40, machineLearning true}`.
- The paste under the `cameraNotSupported` override posted the same non-RAW
  row. RAW_00004 showed S6 with the box on and enabled, the caption, and the
  badge.
- In the catalog, all five raws have `machineLearning: true` and the four
  non-raws don't.

### S-9: fallback, failure and export rows

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; wait 3; ml on; wait 3; ml override notOnThisMac; wait 2; print ml; adjust exposure 0.5; wait 3; print adjustments; print ml; accessibility AXImage; export set dest=$Q/exp1 size=long:800 reveal=off; export run; wait 1; print messages; ml override fail; adjust exposure 0.6; wait 4; print ml; accessibility AXImage; export set dest=$Q/exp2; export run; wait 1; print messages; ml override macos26; wait 2; print ml; export set dest=$Q/exp3; export run; wait 1; print messages; ml override clear; wait 1; export set dest=$Q/exp4; export run; wait 1; print messages; quit
```

- **S5 and the Exposure change:** the stack holds `exposure 0.5` and
  `noiseReduction {machineLearning true}`.
- **Loupe canvas AXImage value:** 'Machine learning not applied, 6 of 9'.
- **Export rows, in order:**
  - "1 photo was exported without machine learning noise reduction: it
    isn't available on this Mac." (exp1)
  - "…: it could not be applied to this photo." (exp2)
  - "…: this Mac needs macOS 27 or later." (exp3, `macos26`, which also
    gave the S5 caption "Not applied on this Mac: it needs macOS 27 or
    later. …" and the matching badge tooltip)
  - for exp4, after clear, only "Exported 1 photo."
- **Catalog afterwards:** RAW_00003 still has `machineLearning: true`.
- **Stale status:** after `fail` the status stayed `notOnThisMac` while the
  frame was `failed` (Q3).

S-11 gave the camera row, "1 photo was exported without machine learning
noise reduction: its camera isn't supported.":

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; wait 3; ml on; wait 3; key 5; key p; ml override cameraNotSupported; wait 2; export set dest=$Q/exp5 size=long:800 reveal=off; export run; wait 1; print messages; inspector off; windowsize 600 450; wait 2; snapshot $Q/s11-narrow.png; windowsize 1000 650; wait 2; snapshot $Q/s11-wide.png; ml override clear; quit
```

### S-10: waiting on a 24 MP ML render

```
wait 2; focus RAW_00001; loupe; inspector on; tab adjust; wait 5; print selection; ml on; wait 0.3; print ml; wait 0.5; print ml; key 3; wait 0.2; print selection; key right; wait 0.3; print selection; print ml; wait 1; key left; wait 0.3; print selection; print ml; ml wait; print ml; snapshot $Q/s10-loupe.png; quit
```

- **At 0.3 s:** `spinner false`.
- **At 0.8 s:** `spinner true`, frame `notRequested (other values)`.
- **`key right`:** focus moved 7 → 8 during the wait.
- **Back on RAW_00001:** after `ml wait`, the frame is `applied` and the
  spinner is off.
- **Catalog:** RAW_00001's rating is 3.
- **Snapshot (seen):** the loupe shows the photo, with 3 stars and "8 of 9"
  in the caption.

### S-12 and S-13: caption line at narrow widths

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; wait 3; ml on; wait 3; key 5; key p; ml override cameraNotSupported; wait 2; print ml; inspector off; windowsize 600 450; wait 2; snapshot $Q/s12-narrow.png; print ml; windowsize 1000 650; wait 2; snapshot $Q/s12-wide.png; ml override clear; quit
```

```
wait 2; focus RAW_00003; loupe; inspector on; tab adjust; wait 3; ml on; wait 3; key 5; key p; ml override cameraNotSupported; wait 2; inspector off; windowsize 600 450; wait 2; print loupe; windowsize 820 532; wait 2; snapshot $Q/s13-820.png; windowsize 900 532; wait 2; snapshot $Q/s13-900.png; ml override clear; wait 2; windowsize 600 450; wait 2; snapshot $Q/s13-noml.png; quit
```

Every image was looked at:

| Image | Window | What it shows |
|---|---|---|
| `s12-narrow.png` | 1520 × 1064 px (the 760 × 532 pt minimum) | **The badge over the fifth star and the flag** |
| `s13-820.png` | 820 pt | The badge touching the flag |
| `s13-900.png` | 900 pt | Clear |
| `s12-wide.png` | 1000 pt | Clear: "6 of 9", five stars, a green flag, then "Machine Learning Not Applied" at the trailing edge before the film strip toggle |
| `s13-noml.png` | 760 pt, no badge | Clear |

S-11 also ran this sequence with an export first, but the export sheet stayed
open and its snapshots show the sheet. It is kept only for the camera row
above.

### S-14: ⌘Z in the active app

Launched with `open`, so the window is key:

```
open -W -n --stdout $Q/s14.log --stderr $Q/s14.err $Q/QA.app --args --library-root $Q/run-lib --debug-script "wait 3; focus RAW_00003; loupe; inspector on; tab adjust; wait 3; print responder; ml on; wait 3; print responder; menuitems Undo; menukey cmd+z; wait 2; print adjustments; print undo; quit"
```

- macOS activated it: `key AppKitWindow first LoupeHostView`.
- `menu Edit/Undo Turn On Machine Learning key cmd+"z" enabled`.
- After ⌘Z: stack `{"operations":[]}` (hash `6c76a50e5dc3`, the untouched
  photo's), and `undo '-' redo 'Turn On Machine Learning'`.

### S-photocli: develop, render, export

On a copy of the pristine library, with the app not running. Each `develop`
probe is a dry run on RAW_00004 (version 8) unless the version says
otherwise:

| `photocli` arguments | Result |
|---|---|
| `adjustments` | `machineLearning`: boolean, default false |
| `develop --version 8 --set noiseReduction.machineLearning=true --dry-run` | stack with `noiseReduction {machineLearning true}`, `written: false` |
| `develop --version 1 --set noiseReduction.machineLearning=true` (JPEG) | `invalidEdit` "noiseReduction.machineLearning applies to RAW files only" |
| `develop --version 1 --set rawDecode.decoderVersion=9.dng --dry-run` (JPEG) | `invalidEdit`, the same message |
| `… --set rawDecode.decoderVersion=9.dng --set noiseReduction.machineLearning=false --dry-run` | empty stack: ML off, no decoder |
| `… --set noiseReduction.machineLearning=false --set rawDecode.decoderVersion=9.dng --dry-run` | ML on, no `rawDecode` |
| `… --set rawDecode.decoderVersion=9 --dry-run` | ML on (RI-E3) |
| `… --set noiseReduction.machineLearning=true --set rawDecode.decoderVersion=7.dng --dry-run` | `rawDecode 7.dng` and ML on, which is allowed: Profile's choice is kept under ML |
| `develop --version 8 --set noiseReduction.machineLearning=true --set noiseReduction.luminance=60`, then `develop --version 8 --set exposure.ev=0.3` | written; ML is still on after the second |
| `render --version 8 --out …tif` | `machineLearning {requested true, applied true}` |
| `render … --original` | `{requested false, applied false}` |
| `export --version 8 --version 1 --to …` | `machineLearning` has one entry, for RAW_00004.DNG, applied; both files written |

### S-bench: photobench denoise

`swift run -c release photobench denoise --runs 3`: "Machine learning noise
reduction: available" (all ML-on runs "applied"). Medians:

| Output | ML off | ML on |
|---|---|---|
| Thumbnail | 0.05 s | 0.28 s |
| Preview | 0.07 s | 1.20 s |
| Export | 0.12 s | 1.24 s |

## For a person

Not runnable on this Mac:

- **macOS 15 or 26.** This Mac runs macOS 27.2 and wasn't simulated
  (only the engineer's `macos26` override texts were checked).
- **A Mac without the RAW 9 model.** This Mac has it.
- **Real camera raws.** The scratch library has synthetic DNGs only.

Use the bundled app, active, on a library that is not the owner's main one
unless noted. `ml override` is a debug-script command, so for S3–S5 run the
bundle's executable with `--debug-script "…; ml override <value>; wait 600; quit"`
and look while it waits.

- **P1 (M1). Caption alignment.**
  - Details ▸ Noise Reduction on a DNG, in S2, S5, S6 and S8.
  - Look for: the caption's first letter under the "U" of "Use machine
    learning", and a wrapped second line at the same indent. In S5, S6 and
    S8 the orange triangle starts at that edge and the text about 4 pt
    after it.
  - Check at the narrowest and a wide inspector, in the current design.
    Also macOS 15 (the earlier design) if a Mac is available.
- **P2 (M2). Increase Contrast** (System Settings ▸ Accessibility ▸
  Display).
  - In S2, "Color" and its value are readable but clearly dimmed next to
    Luminance, and the disabled slider reads as unavailable.
  - The tooltip shows over the label, slider and field.
  - In S3 and S4 the dimmed check box and caption are readable, and in
    S5, S6 and S8 the orange triangle is visible.
- **P3 (M3). VoiceOver.** The canvas value part was confirmed by script.
  Listen for:
  - the check box: "Use machine learning, checkbox", its state, "dimmed"
    in S3 and S4, and its help (the caption text in S3–S8), with the
    caption read after it;
  - Color in S2: its value, "dimmed" and the §5 help;
  - the Decoder pop-up: "9.dng (machine learning)" when on;
  - the spinner: "Applying machine learning noise reduction".
- **P4 (M4, AC8). A real 24 MP raw.**
  - Turn on Use machine learning. The spinner appears after about half a
    second and goes when the frame arrives.
  - During the wait, the arrow keys move to the next photo and 1–5 rate.
    The photo never goes blank, and the frame swaps without animation,
    also with Reduce Motion on.
- **P5 (M5). Keyboard Navigation** (System Settings ▸ Keyboard).
  - Tab reaches the check box after the Noise Reduction group check box
    and before Luminance's value field.
  - Space toggles it.
  - ⌘Z was confirmed by script (S-14).
- **P6 (M6, AC6, AC7, AC10). A Mac on macOS 15 or 26**, with a copy of a
  library holding a DNG with ML on (made on macOS 27).
  - A raw without ML shows the box dimmed with "Not available on this Mac:
    it needs macOS 27 or later."
  - The ML-on raw shows S5 and the badge with the "needs macOS 27 or later"
    tooltip.
  - Change Exposure, then export: the export row "…: this Mac needs macOS
    27 or later."
  - Paste ML-on adjustments onto another raw there: it stores ML and shows
    S5.
  - Back on macOS 27, the photos still have ML on.
- **P7 (M7, AC6). Real cameras.**
  - A camera raw from a camera on RAW 9's list shows "9 (machine
    learning)" in the Decoder pop-up, and checking the box applies.
  - A camera missing from the list shows the box dimmed with "Not
    available for this camera."
- **P8 (RI-E6 option d). A Mac or VM whose RAW 9 model was never fetched.**
  - Take care that nothing triggers a download.
  - Open a supported raw and turn on Use machine learning, then export it,
    and run `photocli render --version <id>`.
  - Record whether the decode fails (S8, "could not be applied to this
    photo"), falls back silently (the box shows S2 and `applied: true`
    while the render is classical), or fetches the model on its own.
  - A silent fallback breaks owner ruling 3 and goes to the product
    manager (roadmap row `ml-denoise-missing-model`).
- **P9 (AC13, owner).** On 2–3 of your own high-ISO raws at 1:1, compare
  Use machine learning at Luminance 100 with the classical sliders at 100.
  Judge whether noise is clearly lower, with no new artifacts. Record the
  cameras in prd.md AC13. If you use converter-made DNGs, include one with
  a `NoiseProfile` tag (PRD Open questions).

## Follow-up

None yet. When Q1 is fixed, rerun S-12 and S-13 and look at the caption at
760, 820 and 900 pt. Q2–Q4 can be checked by rerunning S-5 and the AC10 test.
