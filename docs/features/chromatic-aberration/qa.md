# Chromatic aberration and color fringe removal: QA

Owner: qa-tester. Date: 2026-11-08. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/chromatic-aberration` at `1eb04aa` (PR #48), exported to a
scratch folder (the checkout was not switched or built), on a Mac16,8 (Apple
M4 Pro), macOS 27.2 (26B123), Swift 6.4.2, macOS 27.2 SDK (`vtool -show-build`
on the bundle: minos 15.0, sdk 27.2). CI on `1eb04aa` passed on both runners
(reported by the main session after the first run; QA did not check it).

## Verdict

**Passes, and the owner approved it for Ship on 2026-11-08** (sign-off under
**For a person**). Nothing failed, and there are no findings against the feature's
behavior. Of 35 criteria, 15 pass by test, 16 by script, 1 in part by reading the
code (AC25's pan clause) and 3 by the owner's check (AC1a, AC17, AC27), with
one caveat on AC1a's `accessibility` clause, which the product manager is ruling
on in the Ship pass (RI-Q1). The three findings for the engineer are low and are
**open follow-ups, not fixed before Ship**: missing automated coverage, a debug
command that can quietly do nothing, and a debug-script limit on posted clicks.

**Two runs.** The first ran with the screen locked, so the app had no key
window and `click`, `drag`, `doubleclick`, menu state and the real Esc path could
not run. The **rerun** was with the screen unlocked (`CGSSessionScreenIsLocked`
absent, `IOConsoleLocked` No) and the copy active and key. **It used posted
events only**, sent by the debug script through `NSApp.postEvent` or the menu
probes: no physical mouse, trackpad or keyboard. Its results are marked
"posted" below. It moved no acceptance criterion to Pass, because each open
one still has a part only a person, or a real pick, can show. It closed much of
what was blocked: see **Rerun** under Follow-up.

A posted click that **completes a pick** raises in the debug script and is
**blocked, not failed** (Q3). That produced two crash reports of the QA copy,
`Gus-2026-11-08-202308.ips` and `Gus-2026-11-08-202337.ips` (see Tests).

## Tests

`swift test --no-parallel` in the scratch export at `1eb04aa`: **634 tests in
108 suites passed, 1 known issue** (the pre-existing `withKnownIssue` in "Live
render session", `Tests/PhotoCoreTests/LiveSessionTests.swift:257`). Four suites
skip without their environment variables, as always (camera raw sample, large
renders, large brush, large sharpening map). 99 seconds.

- **Goldens and pipeline.** `git diff develop...1eb04aa` touches no file under
  `Tests/PhotoCoreTests/Goldens` and does not change
  `PreviewCacheKey.currentPipelineVersion` (still 7). `UPDATE_GOLDENS` was not
  run. "Goldens" and "Edit stack corpus" passed.
- **Crash reports.** First run: 20 `Gus-*.ips` before, 20 after, none new.
  Rerun: **2 new, both from the QA copy**, `Gus-2026-11-08-202308.ips` and
  `Gus-2026-11-08-202337.ips` (22 now). Both are a posted click that completed a
  fringe pick: `NSInternalInconsistencyException` from
  `NSUndoManager.registerUndo` via `AdjustmentEditor.apply`, because the script
  turns `groupsByEvent` off (`DebugScript.swift:118`) and nothing groups that
  undo step. The later `SIGSEGV` in `LibraryModel.actionTargets` is the aftermath
  of that exception unwinding through Swift, the case `CLAUDE.md` warns about. The
  exception's reason text is redacted in the log, so the cause comes from the
  stack and the code. See Q3. No further posted click completed a pick.
- **Trial reverts.** I did not revert any source line to prove a test fails.
  The "fails without the fix" claims in `code-review.md` (C1, C2's rule, C4, C6,
  F3) are the code reviewer's. I read the tests below, and each one asserts the
  behavior its criterion names, except where the table says otherwise.

## Acceptance criteria

Result is one of **Pass (test)**, **Pass (script)**, **Pass (reading)**,
**Pass (owner)** (the owner's sign-off under **For a person**) or **Open**. Script and Test results are from runs at `1eb04aa` on the scratch
bundle unless stated. Script names (S1…) are under **Scripts**. A row counts
under the weakest evidence any of its clauses needed: a test-covered criterion
with one script clause is Pass (script).

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Test | `ColorFringesTests` "AC1": picks through the click's rule, grayed fringes and disc rim, clearing restores one | Pass (test) |
| AC1a | Test, Script, Person | Rendering: `ColorFringesTests` "AC1a". S7: `menupick` on each slot's real ⋯ pull-down fills Color 1 with Purple and Color 2 with Green, one undo step each; `print fringe` reports each. **Not met as written:** the AC asks for the `accessibility` command to list the route, and `accessibility any` lists no Lens control, because SwiftUI builds its tree only for an attached assistive app (Requirements issue below). VoiceOver route: P10, confirmed by the owner. **The owner's check can't have shown the `accessibility` debug command listing the route**, so that clause is not shown by any check here; the product manager is ruling on it in the Ship pass (RI-Q1) | **Pass (owner)** (P10), `accessibility` clause with RI-Q1 |
| AC1b | Test, Script | `ColorFringesTests` "AC1b" (same bytes, hash and pixels). S8: Tolerance widens; pick replaces listed, listed replaces pick, clear, each one undo step ("Pick Fringe Color", "Choose Fringe Color", "Clear Fringe Color"). S11 and S13: paste and preset carry `color1` unchanged | Pass (script) |
| AC2 | Test | `ColorFringesTests` "AC2" | Pass (test) |
| AC3 | Test | `ColorFringesTests` "AC3" | Pass (test) |
| AC4 | Test | `ColorFringesTests` "AC4" ×2 | Pass (test) |
| AC5 | Test | `ColorAlignmentTests` "AC5" ×2. Also S11: a 1200 × 800 scene (c) measured red 40.22, blue −29.93, a 6000 × 4000 one 40.03, −29.95 (truth 40, −30) | Pass (test) |
| AC6 | Test | `ColorAlignmentTests` "AC6": overlap within the crops' own difference; a 3° crop measures the same | Pass (test) |
| AC7 | Test | `ColorAlignmentTests` "AC7", `LensRenderingTests` (channels against the reference). S9: a Red/cyan move leaves automatic off, "Set by hand" caption | Pass (test) |
| AC8 | Test | Full run, "Goldens" and "Edit stack corpus"; `git diff` as above; `ColorFringesTests` "R11" | Pass (test) |
| AC9 | Script | S9: undo names "Turn On Automatic Alignment", "Choose Fringe Color", "Red/cyan"; `original on` leaves the stack and hash unchanged; each group off keeps its values and drops from the hash; Reset gives the identity hash `6c76a50e5dc3` | Pass (script) |
| AC10 | Test | `ColorFringesTests` "AC10". It compares `fringeMap` renders at scale ¼ and 1 through the renderer, not the loupe's or an export's own path. That the export uses the same renderer is by reading (CLAUDE.md, Export) | Pass (test) |
| AC11 | Test | `LensCommandTests` "AC11" runs the real command registry | Pass (test) |
| AC12 | Test, Script | `ColorFringesTests` "AC12". S14: a `.MOV` shows the Adjust tab's video state; `print magnifier` finds no loupe and arming does nothing | Pass (script) |
| AC13 | Test, Script | `ColorAlignmentTests` "AC13". S11: a grid paste measured each online photo itself (40.22 / −29.93 on scene (c), −19.99 / 24.99 on the second); S13: a preset measured the receiver's own (red −20.01, blue 25.01) | Pass (script) |
| AC13a | Script | S11: a paste over 7 photos left the offline photo's stack and hash byte for byte unchanged; Activity "1 photo was left unchanged: its original is offline.", one undo step "Paste Adjustments". **Offline is a stand-in:** `hdiutil create` was refused here, so the photo's row points at a volume that is not mounted (scratch catalog only). No file was touched | Pass (script) |
| AC13b | Test, Script | `LensPresetTests` ×3. S13: an imported file with no group list ("All settings") cleared both slots and alignment as one undo step, "Apply Preset Older", and one undo restored them | Pass (script) |
| AC14 | Test | `LensCommandTests` "AC14" | Pass (test) |
| AC15 | Script | `photobench edits`, S15 (table under Scripts) | Pass (script) |
| AC16 | Script | S2 and S16: shown after arming from the eyedropper and Pick from Photo; hidden over the surround (`magnifier move 1.05 0.5`); gone on Esc, another photo, crop session, review; never for a fill from the list | Pass (script) |
| AC17 | Test, Script, Reading, Person | `PixelMagnifierTests` "AC17, AC22". S3: 270,951 drawn cells at the view's fit, 100% and 800%, every level, all within 1 of a CPU reference of scene (d), no pixel with two values. S4: a click sent while arming, before the pixels are held, stored the same color as a click after they were ready. **Not script-testable:** the not-ready picture and dashes (arrive too fast, P6). **By reading only:** the stretched live frame clause (no script makes a live frame while picking; the picture comes from the held pixels, `PixelMagnifier.picture`, never from the frame). Not-ready state confirmed by the owner (P6) | **Pass (owner)** (P6) |
| AC18 | Test, Script | `PixelMagnifierTests` "AC18" ×2. S5: 52 points on and near the fringes at the view's fit, 100% and 800%: the outlined `maskPoint` is the stored sample and the verdict is the click's result every time; at 100% and 800% it is the pixel under the pointer (33 of 33, within one pixel); 18 picks' stored colors reconverted to P3 are within 1 of the values shown | Pass (script) |
| AC19 | Test | `PixelMagnifierTests` "AC19" (values, and Exposure, Saturation, a look-up table and the other slot leaving every sampled pixel unchanged, each shown to change the render; Color Alignment changing it). S6: in the app, Exposure, Saturation and the other slot left all 1225 cells identical | Pass (test) |
| AC20 | Test | `PixelMagnifierTests` "AC20" ×2. In the app a neutral reads 30/30/30/30 and 217/217/217/217 | Pass (test) |
| AC21 | Test | `PixelMagnifierTests` "AC21". S5 and S12: "Almost no color" on the light ground and the click refused with the caption | Pass (test) |
| AC22 | Test, Script | `PixelMagnifierTests` "AC17, AC22" at backing 1 and 2. S3: device pixels per photo pixel are 1, 2, 4, 8, 16 at each level at the view's fit, 100% and 800%, at backing 2. Backing 1 is by test only (no standard display here; P7 on a real one). `-`, `=` and the accessibility actions keep picking armed and the slot unchanged | Pass (script) |
| AC23 | Script | S10: level 400 set on one photo read 400 on another photo and slot, after a relaunch, and under another `--library-root`; hash and stack unchanged, `catalog.sqlite` byte-identical. Level restored to 800 | Pass (script) |
| AC24 | Test, Script | `PixelMagnifierTests` corners, crop, quarter turn. S17: outlined 0,0 / 1199,0 / 0,799 / 1199,799 at 1200 × 800, drawn cells only inside the photo; a crop draws only 300…899 and 200…599; a quarter-turned picture matches the reference through the clockwise mapping; the composite stays inside the canvas | Pass (script) |
| AC25 | Test, Script, Reading | S18: with the pointer still, Color Alignment changed the same pixel from 31/222/217 to 210/217/217, undo restored it, and the click then took and refused what it showed. Zoom re-reads (S3). Rerun, posted events (S26): a real-pointer-path drag leaves the magnifier on the pixel under the pointer; with the pointer then still, `Z` re-reads, and the next click took exactly that outlined point. **Pan with the pointer still is by reading only** (`visibleRectChanged`, `LoupeView.swift:602`): no posted event scrolls the photo under a still pointer. P4 checks it | **Pass (reading)** |
| AC26 | Script, Test | S10: arming and every level path add no undo step (`print undo` names only the pick). Full run for goldens. `print undo` shows `''` after a scripted `key` even with no photo involved (control run, S10): the script's own empty group, not a step from the feature | Pass (script) |
| AC27 | Script, Person | S12: `hit` over the magnifier's drawing reaches `LoupeImageView`; `-`/`=`, `]` and `Z` leave picking on, and Esc and a move to another photo end it, as design §4 says. **Rerun, posted events (S26):** a click on a neutral spot takes the outlined point and is refused, picking on, no undo step; a drag pans and picking stays on; a double-click stays in the loupe; a click on the surround does nothing. **Blocked, not failed:** a posted click that completes a pick raises in the script (Q3). **Not reached:** the clamped click (`windowsize 560 420` still placed the magnifier beside the pointer). Real input confirmed by the owner (P2) | **Pass (owner)** (P2) |
| AC28 | Script | S10: `accessibility any` lists no magnifier element; canvas actions Pixel Magnifier Zoom In and Out change the level and announce "Pixel magnifier at 1600%."; first responder `LoupeHostView` before and after arming; `-` and `=` step it. VoiceOver speech: P10 | Pass (script) |
| AC29 | Test, Reading | `PixelMagnifierTests` "AC29" ×2. `grep` finds no fringe type in `PixelMagnifier.swift`, `PixelMagnifierView.swift` or `PixelMagnifierActions.swift` (the AC gives this half to code review, which confirmed it, C5) | Pass (test) |
| AC30 | Script | S10: `adjust mask add colorRange` (`isSamplingColor` true, `MaskEditing.swift:122`) leaves the magnifier inactive, 0 bytes held. Sampling itself is unchanged: `git diff` of the sampling code shows no change (by reading) | Pass (script) |
| AC31 | Script | S15 for the times. Memory: 183 MB held while picking; `print magnifier` shows `heldBytes 0` after picking ends (S1, S2) | Pass (script) |

### Counts

| | ACs |
|---|---|
| Passed by test | 15: AC1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 14, 19, 20, 21, 29 |
| Passed by script | 16: AC1b, 9, 12, 13, 13a, 13b, 15, 16, 18, 22, 23, 24, 26, 28, 30, 31 |
| Passed by reading only, in part | 1: AC25 (the pan clause; the other clauses by script). P4, which covers that clause, is among the checks the owner confirmed |
| Failed | 0 |
| Passed by the owner's check | 3: AC1a (P10; see RI-Q1 for its `accessibility` clause), AC17 (P6), AC27 (P2) |
| Open | 0 |

### Design checks

| DR | Result | Evidence |
|---|---|---|
| DR1 | Script for structure; look open | `buttons`: Lens, Reset Lens, the group check boxes. Glass pane: P8 |
| DR2 | Script for structure; swatch and row open | `buttons`, `contextmenu fringe` (Pick from Photo, header, Purple, Green, Clear dimmed when empty). P8, P9 |
| DR2a | Pass (script) | S19: in a crop session Pick from Photo is dimmed and the list and Clear are not; a fill while armed disarms; the map stays on and follows; clearing the last pick ends it. Look: P8 |
| DR2b | Open | P10 |
| DR3 | Pass (posted) in part; open | S26: click on a neutral spot, drag, double-click, surround; keys (S12). A click that completes a pick is blocked by Q3. P2 |
| DR4 | Pass (script) | S5 and `ColorFringesTests` "The pixel rule" |
| DR5 | Pass (script), real size open | S20: armed on a filled slot, the snapshot shows the slot's graying gone (seen); the caption says the effect is hidden; Esc restores. 24 MP refine and spinner: P12 |
| DR6 | Pass (posted) in part | S28, key window: Show Fringe Map dimmed with no pick, enabled with one, dimmed in the grid, during a crop and in review; `menupress Show Fringe Map` shows it. Video, offline and unreadable stacks not run |
| DR7 | Pass (script), look open | `fringemap on`: snapshot seen, gray-on-black in the frame; `print fringe` for badge and legend. P8 |
| DR8 | Pass (script) | S19 and S21: an eyedropper suspends the fringe map and it returns; the sharpening map replaces it; arming ends the sharpening map |
| DR9 | Pass (script) | S9: captions for measured and set by hand; a slider move unchecks; unchecking zeroes both |
| DR10 | Pass (script) in part | S11, S13. Stop while measuring was not run |
| DR11, DR12 | Open | P10, P7 |
| DR13 | Pass (test) | `LocalizationTests` in the full run |
| DR14 | Pass (script and posted) in part | S21: picking, then the map, then the loupe. S28: Esc in a crop session cancels it. Review not in the sequence |
| DR15 | Pass (script) | AC16 |
| DR16 | Pass (script) | S17, placement test; flicker: P5 |
| DR17 | Pass (test and script) | AC17, AC22, F3 snapshot seen; legibility: P7 |
| DR18 | Pass (script) in part | Values and the refusal: S5. Not ready: P6 |
| DR19 | Pass (script and posted) in part | S22: pop-up in `buttons` only while picking; `-` `=` no wrap; context submenu with the level checked. S27, key window: View ▸ Pixel Magnifier items dimmed unless picking, the level checked, Zoom In dimmed at 1600%, Zoom Out at 100%, `menupress 400%` sets it and picking stays on. `menupick` could not drive the inspector pop-up ("no menu button at that point"); it stays with P10 |
| DR20 | Pass (script) | AC28; speech: P10 |
| DR21 | Open | P7 |
| DR22 | Pass (script) | S23; VoiceOver once: P11 |

### Review findings, rechecked

| # | How I checked it | Result |
|---|---|---|
| C1 | S11: a paste over 7 photos, one stack at schema 99: that one untouched, "1 photo was left unchanged: its edits can't be changed in this version." | Script |
| C2 | Unit `LensReviewFixesTests` "A replaced run owns nothing" passes. **It covers the rule only.** The replacement race itself has no test and no script | **Weak: rule by test, race by reading only** (Q1) |
| C3 | Reading: `mouseDragged` returns inside the 3-point threshold (`LoupeView.swift:1132`) and the pick uses the mouse-down location. **Rerun, posted (S26):** a press at 368 released at 370 (2 points, within the threshold) took 0.0506, the press point; a click at 370 alone takes 0.0529. The outline during the press is not visible to a script | **Pick point by posted events; outline by reading** (P3) |
| C4 | Unit table "Refinement follows what is on screen". The call site is by reading | Test, in part |
| C5 | AC29 | Test |
| C6 | `LensCommandTests` "AC11" | Test |
| C7 | S24: `pasteadjust uncheck`, batch ended, photo unchanged | **Script only** (no test target reaches `AdjustmentEditor`, Q1) |
| C9, F1 | No automated check. Reading: `visibleRectChanged` invalidates the cursor rects (`LoupeView.swift:604`). **Rerun, posted (S26):** the magnifier, which uses the same photo rect as the crosshair, follows drag and zoom. Cursor shape and cursor rects are still not visible to a script | **Reading only** (P4) |
| C10, C14 | S15 prints the 100% and cropped rows; the 800% label is in `docs/PROFILING.md` | Script, reading |
| C11 | No "snap" in `DebugAdjustCommands.swift` | Reading |
| C12 | No move, remove or `hideoriginal` in any debug-script source; the scan test passes | Test, reading |
| C13 | S24: `pasteadjust loupeuncheck`, the batch carried on and all 6 were written | **Script only** (Q1) |
| F2 | **Rerun, posted (S27):** with the app active, `magnifier resignkeyboard` moved the first responder to the window, and a posted Esc through the app (`menukey escape`) ended picking with the responder still off the loupe. In the Tolerance field the first posted Esc handed the keyboard back with picking on, and the second cancelled (S29). Physical key, open menus, sheets and popovers not covered. First run's S25 was inconclusive | **Posted** (P10) |
| F3 | Unit "R29: the grid covers…"; S17's snapshot at 1600% seen: lines stop at the photo | Test, snapshot; hairline: P7 |
| F4 | S21: `fringemap on; fringearm 1; sharpenmap on`, picking none | Script |
| F5 | **Rerun, probe (S29):** `contextmenu at` over the row's swatch and name printed `Common Fringe Colors [section]`, and `[image]` on Purple and Green, with the separators. Other points on the row printed "no context menu". This is the menu built for a right-click, not a real right-click, and `[image]` doesn't show the color. The first run's failure was at other points on the row, so it may not have been the lock | **Probe** (P9) |
| DQ-1 | Reading: the guide's sentence is there. Revisit on real raws: P1 | Reading |
| DQ-2 | S11: one row, its count, then `bad.tif: the original could not be read.`, after the offline row. A file imported already truncated (never altered after import) | Script |
| DQ-3 | The script waits inside its undo group, so the job is never on screen | Open (P13) |
| DQ-4, DR22 | S23, reproduced with `magnifier failsample on\|off`, including a click waiting for pixels that never arrive. **It simulates the read failure in memory.** A real ejected volume was not tried (`hdiutil` was refused here) | Script |

## Findings

For the engineer. None blocks on behavior. **Q1, Q2 and Q3 were not fixed before
Ship; the owner was asked and chose to ship. They stay open as follow-ups.**

**Q1. Low. Open follow-up. Missing automated coverage for four review fixes.** A missing test
is a finding (`.claude/agents/qa-tester.md`).
- C2's replacement race: `Sources/PhotoApp/Model/AdjustmentActions.swift:65`,
  `:86`, `:89`; `Sources/PhotoApp/Model/BatchActions.swift:91`, `:106`. The rule
  (`LatestRun.owns`) is tested, not the case it exists for.
- C7 and C13: `Sources/PhotoApp/Model/AdjustmentEditor.swift:1440`. Debug script
  only, because no test target reaches `AdjustmentEditor`.
- C3: `Sources/PhotoApp/Loupe/LoupeView.swift:1132`. No test, no script.
- C9/F1: `Sources/PhotoApp/Loupe/LoupeView.swift:604`. No test, no script.

Expected: a test where one can reach the behavior. The honest alternative is to
accept these as script or person checks, as they are recorded here.

**Q2. Low. Open follow-up. `magnifier resignkeyboard` can silently do nothing.**
`Sources/PhotoApp/Model/DebugLensCommands.swift:74` uses `NSApp.mainWindow`, which
is nil in a process that isn't active.
Steps: launch with `--debug-script` while the app can't be activated; `fringearm 1;
magnifier resignkeyboard; print responder`.
Expected: the keyboard leaves the loupe, or the command says it could not.
Actual: it prints `first responder nil`, `print responder` still shows
`LoupeHostView`, and a following `menukey escape` proves nothing about F2. The
other commands in that file find the window a different way. **Rerun:** with the
app active and key it behaves correctly (the responder moves to the window, S27).
The finding stands only for a process that is not active.

**Q3. Low. Open follow-up. A posted click that completes a fringe pick raises
under the debug script.** `Sources/PhotoApp/Model/DebugScript.swift:118` turns `groupsByEvent` off;
`click` and `doubleclick` (`:286`, `:325`) aren't in the script's grouped commands, and
the pick lands in a Task after the command returns, so nothing groups its undo
step. `menukey` (`:383`–`:388`) already works around this for posted keys.
Steps: an `open` launch with the screen unlocked; arm a slot; `click` on a fringe.
Expected: the pick is saved. Actual: `NSInternalInconsistencyException` from
`NSUndoManager.registerUndo` (`AdjustmentEditor.apply` ← `commit` ← `change` ← the Task
in `pickFringe(at:devicePixelsAcross:)`), then a crash in `LibraryModel.actionTargets`.
Crash reports `Gus-2026-11-08-202308.ips` and `Gus-2026-11-08-202337.ips`. The
reason text is redacted in the log, so the cause comes from the stack and the code.
It is limited to the script (`groupsByEvent` is only off there), and it blocks any
posted-event check of a completed pick, so those are recorded as blocked, not failed.

### For the designer (Design question)

**DQ-Q1. `review.md` M9 and `design.md` DR22 still describe the removed path.**
`review.md:173` says "With the file moved away before arming (`magnifier
hideoriginal`…)", and DR22's row says "with an original removed before arming".
`hideoriginal` was removed for C12, and the project's rule forbids moving an
original. P11 below uses `magnifier failsample on`. Should those two lines be
updated?

### For the product manager (Requirements issue)

**RI-Q1. AC1a asks for a route the `accessibility` command can't list.** It says
the list "can be reached and used, and each slot then reports its color", checked
through "the `accessibility` command". That command sees SwiftUI elements only
with an assistive app attached (`CLAUDE.md`), and at `1eb04aa` it lists no Lens
control. Should AC1a's accessibility clause move to M2, where a person checks it
anyway? The owner's check can't have shown this clause. The product manager is
ruling on it in the Ship pass.

## Scripts

Every launch ran the copy's executable, or an `open` launch where stated, with
`--library-root` on a scratch library and `--debug-script "…"`. The copy:
`me.sesser.gus.qa-ca1`, re-signed ad hoc. Libraries and scenes came from
`photobench scenes` at 1200 × 800 and 6000 × 4000 and from `photobench import`.
Every run ended in `quit` under a time limit.

S1 (show and hide, on `pixel-grid.tif`): `wait 2; focus 5; loupe; wait 2; fringearm 1; wait 1; print magnifier; magnifier move 0.5 0.5; print magnifier; magnifier move 1.05 0.5; print magnifier; magnifier move 0.5 0.5; key escape; wait 0.5; print fringe; print magnifier; quit`. Hidden over the surround, gone after Esc, `heldBytes 0`.

S2 (AC16): `… focus 1; loupe; wait 2; fringearm 1; wait 0.6; magnifier move 0.5 0.5; print magnifier; key right; wait 1.5; print magnifier; print fringe; key left; wait 1.5; fringearm 2; wait 0.6; magnifier move 0.5 0.5; adjust crop begin; wait 0.5; print magnifier; adjust crop cancel; wait 0.5; fringearm 1; wait 0.6; magnifier move 0.5 0.5; review on; print magnifier; review off; wait 1; loupe; wait 1; adjust fringe fill 1 purple; wait 0.5; magnifier move 0.5 0.5; print magnifier; print undo; quit`.

S3 (AC17, AC22, view at fit, 100%, 800%), 6000 × 4000 `pixel-grid.tif`, generated: `focus 5; loupe; fringearm 1`, then for each view (`optionscroll <x> <y> 50` for 800%, `-13.86` from there for 100%) and each level 100…1600 `magnifier level <l>; magnifier move <unit on screen>; print magnifier pixels`, compared with a CPU reference of `TestScene.pixelGridColor` (`decode`, then Rec. 2020 to Display P3): 270,951 cells, worst difference 1, 0 pixels seen with two values, device pixels per photo pixel 1/2/4/8/16. Run without a key window: `zoom` (animated) lags a step behind, so the view was set with `optionscroll`, which is not animated.

S4 (click before pixels are ready), `fringes.dng`, 6000 × 4000: `adjust fringe pick 1 0.1185 0.3` with no prior arming, against `fringearm 1; wait 2; magnifier move …; adjust fringe pick 1 0.1185 0.3`: both stored 0.8892, 0.0243, −0.0391 at sample 0.1184, 0.2999.

S5 (AC18), generated: for 19 points across the first bar and green fringe at fit, 19 at 800%, 14 at 100% (`y` 0.3): `fringearm 1; wait 0.5; magnifier move <x> 0.3; print magnifier; adjust fringe pick 1 <x> 0.3; print fringe`. 52 points, 0 outline differing from the stored sample, 0 verdict differing from the click, 0 stored colors more than 1 from the values shown, 34 refused and 18 picked.

S6 (AC19 in the app): `… focus 1; loupe; wait 2; fringearm 1; wait 0.7; magnifier move 0.1185 0.3; print magnifier pixels; key escape; adjust exposure 1.5; adjust saturation 40; adjust fringe fill 2 green; wait 1; fringearm 1; wait 0.7; magnifier move 0.1185 0.3; print magnifier pixels; quit`. All 35 rows identical.

S7 (AC1a), on a TIFF with no edits: `search; wait 2; focus 4; loupe; wait 2; tab adjust; scroll 1700; wait 0.5; menupick 1293 530 Purple; wait 0.6; print undo; menupick 1293 578 Green; wait 0.6; print fringe; print undo; print adjustments; quit`. Both slots filled, each "Choose Fringe Color". The coordinates come from `buttons`: Color 2 moves down once Color 1's Tolerance row appears, and a raw's inspector is laid out differently. The Fringe Map snapshot in DR7 is from `fringemap on` on a photo with Purple.

S8 (AC1b): `adjust fringe clear 2; adjust fringe pick 1 0.1185 0.3; print fringe; print undo; adjust fringe fill 1 green; print fringe; print undo; undo; print fringe; undo; print fringe; adjust fringe tolerance 1 60; print adjustments; adjust fringe clear 1; print adjustments; undo; print adjustments`.

S9 (AC9, DR9): `adjust fringe fill 1 purple; adjust align auto on; print undo; print adjustments; original on; wait 1; print adjustments; original off; adjust off colorFringes; print adjustments; adjust on colorFringes; adjust off colorAlignment; print adjustments; adjust on colorAlignment; adjust align redcyan 12; print fringe; adjust align auto off; print fringe; adjust reset all; print adjustments; print undo`.

S10 (AC23, AC26, AC28, AC30): `fringearm 1; wait 0.7; magnifier level 400; magnifier move 0.5 0.5; print magnifier; print undo; key -; print magnifier; key =; key =; print magnifier; …; key escape; print undo; print adjustments`, then two relaunches, one on another `--library-root`, each `fringearm 2` or on another photo and `print magnifier` (400 both times), then `magnifier level 800`. `accessibility any; accessibility AXImage; accessibility AXImage 0 Pixel Magnifier Zoom In; print announcement`. `adjust mask add colorRange; print magnifier`. Control: `key z; print undo` on a photo with no edits also shows `''`.

S11 (AC13, AC13a, C1, DQ-2): a scratch library with 7 photos, the file `bad.tif` written truncated before import, one row pointed at a volume not mounted, one stack set to schema 99 in the scratch catalog. `focus lateral-color; loupe; wait 2.5; adjust align auto on; adjust fringe fill 1 purple; copyadjust; grid; wait 1; selectall; pasteadjust; wait 1; print undo; print messages; quit`. Rows in order: offline, unreadable, unchangeable. Stacks read back with `sqlite3 -readonly`.

S12 (AC27, keys): `contextmenu fringe 2 Pick from Photo; wait 0.7; magnifier move 0.5 0.5; print magnifier; key ]; print items; key z; wait 1; print fringe; key escape; print magnifier`. `hit 858 484` while the magnifier shows.

S13 (presets, AC13b): `adjust fringe fill 1 purple; adjust align auto on; adjust exposure 0.3; preset save QA1; preset import …/older.guspreset; focus lateral-color-2; wait 3; preset apply QA1; print adjustments; print undo; adjust fringe fill 2 green; preset apply Older; print adjustments; print undo; undo; print adjustments`.

S14 (video): `search MVI_10001; print items; focus 0; loupe; wait 3; print adjustments; print magnifier; fringearm 1; print magnifier`.

S15 (AC15, AC31): `photobench edits --limit 3 --frames 20` on a generated library of 6000 × 4000 DNG, HEIC and JPEG. See below.

S16 (Pick from Photo): in S12.

S17 (AC24, F3): `magnifier move 0.0005 0.0005; print magnifier pixels`, then the three other corners; `adjust crop begin; adjust crop rect 0.25 0.25 0.5 0.5; adjust crop done`; corners again; `adjust crop reset`; `adjust crop turn right`; `magnifier move 0.25 0.25; print magnifier pixels`. F3: `magnifier level 1600; magnifier move 0.0005 0.0005; snapshot …`.

S18 (AC25): `fringearm 1; wait 0.7; magnifier move 0.91375 0.89063; print magnifier; adjust align redcyan 40; wait 1.5; print magnifier; undo; wait 1.5; print magnifier; adjust align redcyan 40; wait 1.5; adjust fringe pick 1 0.91375 0.89063; print fringe`.

S19 (DR2a, DR8): `adjust crop begin; print fringe; contextmenu fringe 1; adjust fringe fill 1 purple; adjust crop cancel; fringearm 2; adjust fringe fill 2 green; print fringe; fringemap on; adjust fringe clear 2; print fringe; adjust fringe clear 1; print fringe; original on; adjust fringe fill 1 purple; fringearm 1; print adjustments; key escape; sharpenmap on; fringearm 1; print sharpenmap; print fringe`.

S20 (DR5): `fringearm 1; wait 1.5; print fringe; snapshot …; key escape; wait 1.5; print fringe`.

S21 (DR8, DR14, F4): `fringemap on; fringearm 1; key escape; print fringe; key escape; print fringe; key escape; print loupe`. And `adjust fringe fill 1 purple; fringemap on; fringearm 1; sharpenmap on; print fringe; print sharpenmap`.

S22 (DR19): `tab adjust; scroll 1700; buttons; fringearm 1; buttons`. "800%" pop-up in the second list only.

S23 (DR22, DQ-4): `magnifier failsample on; fringearm 1; wait 1; print fringe; print magnifier; print undo; print announcement; magnifier failsample off; fringearm 1; wait 1; magnifier move …; print magnifier`; and with no arming first, a waiting click: `magnifier failsample on; adjust fringe pick 1 0.1185 0.3; print fringe; print undo`; and pixels held then failing: `fringearm 1; wait 1; magnifier failsample on; adjust fringe pick 1 0.1185 0.3; print fringe`. Results: picking none, the caption, 0 bytes held, no undo step, the announcement; retried and ready; the waiting click dropped; held pixels still picked.

S24 (C7, C13): `… adjust align auto on; copyadjust; grid; wait 1.5; selectall; pasteadjust loupeuncheck; wait 1; print undo; quit` (all 6 written), and from the loupe `pasteadjust uncheck` (batch ended, stack unchanged).

S25 (F2, inconclusive): `fringearm 1; wait 0.7; magnifier move 0.5 0.5; magnifier resignkeyboard; print responder; menukey escape; print fringe`.

S26 (rerun, posted, libbig `fringe-subjects.tif`, window key, on neutral spots only): `fringearm 1; wait 1.2; click 368 255; wait 1; print fringe; print undo; print magnifier; zoom; wait 1.2; drag 600 300 480 240; wait 0.6; print loupe; print fringe; print undo; print magnifier; zoom; wait 1.2; print magnifier; click 480 240; wait 1; print fringe; …; doubleclick 368 255; wait 1.2; print fringe; print loupe; hit 260 400; click 260 400; wait 0.8; print fringe; print loupe; print undo; click 390 255; print fringe; drag 368 255 370 255; print fringe; print undo`. Refused at 0.0506 with the outline on it; the drag panned visible 950,678 to 1070,618 with picking on and no undo step; the outline after `Z` at the same pointer was 0.1759, 0.2746 and the click took 0.1759, 0.2746; double-click stayed in the loupe; surround unchanged; press-and-slip took the press point.

S27 (rerun, posted, key window): `menuitems Zoom; menuitems %`, at rest and while picking and at levels 1600 and 100; `menupress 400%; print magnifier; print fringe`; `magnifier resignkeyboard; print responder; menukey escape; print fringe; print magnifier; print responder`; `menukey cmd+=; wait 0.8; print loupe; print fringe`.

S28 (rerun, posted, key window): `adjust fringe fill 1 purple; menuitems Fringe Map; grid; wait 1; menuitems Fringe Map; loupe; wait 2.5; adjust crop begin; wait 0.6; menuitems Fringe Map; key escape; print adjustments; review on; menuitems Fringe Map; review off; wait 1; loupe; wait 1.5; menupress Show Fringe Map; print fringe`.

S29 (rerun, posted, `lib`): `tab adjust; scroll 1700; contextmenu at 1048 530; contextmenu at 1150 530; click 1261 530; print fringe; adjust fringe fill 1 purple; fringearm 2; editvalue Tolerance; print responder; menukey escape; print fringe; print responder; menukey escape; print fringe; windowsize 560 420; fringearm 1; magnifier move 0.5 0.5; print magnifier`. The eyedropper armed from a posted click; `[section]` and `[image]` in the menu; Esc handed the keyboard back, then cancelled.

S30 (rerun, posted, key window): `zoom; wait 1.2; fringearm 1; wait 1.2; menukey cmd+-; wait 0.8; print loupe; zoom; wait 1; zoom; wait 1.2; menuitems Zoom Out; menukey cmd+-; wait 0.8; print loupe; print fringe`.

Rerun also found (S27, S30, posted): after `Z` to 100%, `menukey cmd+-` did nothing until `menuitems Zoom Out` had run (it refreshes the menu as an opening menu does), then zoomed from 1.0 to 0.5, whether or not picking. Picking stayed on. A posted key can't tell whether a real ⌘− is affected: see P2.

S15's figures, median ms, 6000 × 4000 files, this Mac, with nothing else running:

| | DNG | HEIC | JPEG |
|---|---|---|---|
| live next frame (exposure) | 59.4 | 21.9 | 23.0 |
| live saturation (the color slider) | 59.8 | 21.8 | 22.4 |
| live fringe tolerance (two slots) | 69.4 | 25.3 | 25.1 |
| live color alignment | 12.3 | 27.8 | 28.5 |
| magnifier first pixels (arming) | 119 | 38 | 52 |
| update per pointer move, 800% | 0.14 | 0.15 | 0.14 |
| update per pointer move, 100% | 3.4 | 3.5 | 3.5 |
| same, straightened crop | 3.7 | 3.8 | 3.9 |
| memory held while picking | 183 MB | 183 MB | 183 MB |
| live saturation, magnifier held | 61.6 | 22.4 | 22.6 |

Fringe Tolerance is 10 ms slower than Saturation on DNG, and 3 ms on HEIC and
JPEG (R18, no target; ruling 12). With the magnifier held, Saturation is 1.8 ms
slower on DNG and 0.6 and 0.2 ms on the others. The AC gives no threshold, and I
read that as "no worse". An earlier run, made while debug scripts were also running,
gave 0.9 to 2.8 ms.

## For a person

**Owner's sign-off, 2026-11-08:** "I've checked all the "For a person" checks in
qa.md and everything seems to work well. I approve. Ship it"

**P1–P13 below are confirmed by the owner.** The rows in the tables above that
point to a P item are covered by this sign-off. The steps stay as written, as the
record of what was asked.

Run on the bundle, against a copy with its own bundle identifier and a scratch
library, always with `--library-root`. **The two sets of M-numbers are different
lists:** "PRD M" is `prd.md`, "review M" is `review.md`.

| Source | Goes to |
|---|---|
| PRD M1 | P1 |
| PRD M2 | P10 |
| PRD M3 | P2 (clamped click), P5, P7 |
| review M1 | P2 |
| review M2 | P6 |
| review M3 | P7 |
| review M4 | P8 |
| review M5 | P10 |
| review M6 | P12 |
| review M7 | P13 |
| review M8 | P4, P5 |
| review M9 | P11 |
| F1/C9 | P4 |
| C3 | P3 |
| F2 | P10 |
| F5 | P9 |
| DQ-4 VoiceOver | P11 |

**P1. Real photos (PRD M1, not blocking; DQ-1).** Real photos with fringes, at
100%, including at least one with strongly out-of-focus bright highlights with
colored rims. Look for: fringes gone or nearly gone; real purple or green
subjects keep their color; the listed Purple and Green match what you find. For
bokeh rims: grayed, or if not, whether the Fringe Map shows them outside the
edge rule and whether widening Tolerance fixes them. On a raw, change White
Balance a lot after picking and note whether the fringe comes back (DQ-1).

**P2. Real input while picking (review M1, the clamped click in PRD M3, AC27,
DR3).** A real mouse, with a photo armed. **A click on a fringe picks and saves**;
a posted click can't complete this (Q3). **A double-click on a fringe picks once**
and stays in the loupe (posted, the double-click stayed in the loupe on a neutral
spot). A real right-click opens the context menu with Pixel Magnifier ▸ and picking
stays on; the magnifier stays while the menu is open and updates when a level is
chosen. Make the window small enough that the magnifier lies under the pointer: a
click over its drawing picks (`windowsize 560 420` did not get there). **⌘− right
after `Z`:** it zooms out with picking on; a posted ⌘− did nothing here until the
menu had been refreshed (S30), which a real key may not share. Posted and already
checked, so only a physical check remains of: a drag pans and the magnifier
follows; a click on the surround does nothing.

**P3. The outline holds still during a slightly moving click (C3).** At 100% on
a Retina display, armed, press on a fringe pixel and move the pointer about 1
point before releasing. Look for: the outline stays on the pressed pixel, and
the stored color is that pixel's (the plate's values before release). Posted
events showed a slipping press takes the press point (S26); the outline during the
press, and a real pick, are what remain.

**P4. The crosshair follows a zoom, pinch or scroll (F1/C9, review M8, AC25's pan).**
Arm at fit, press Z; arm at 100%, press Z. Then pinch and scroll while armed. The
crosshair is over the photo only and agrees with the magnifier, with no flicker.
With the pointer held still, scroll or pan the photo: the outline and values
change to what is now under the pointer.

**P5. Feel (PRD M3, review M8, R36).** On a real raw, on Retina and a standard
display if available, and after moving the window between them. The magnifier
feels attached to the pointer, flips without flicker at the right and bottom
edges, arming has no hitch, and the level can be changed in practice while
picking.

**P6. Not ready (review M2, R20, AC17).** On a raw of 24 MP or more, arm the
eyedropper: an empty ring, dashes and the level, a spinner only after about half
a second, and a click at that moment stores the pick. While dragging a slider
(a stretched live frame), the magnifier still shows the photo's own pixels.

**P7. Legibility (review M3, PRD M3, DR12, DR17, DR21, R33).** Outline, ring and
plate read over white, black and busy content, at each level, on Retina and a
standard display. On the plate, the letters and three-digit values don't run
together ("G255" touches in the snapshot). With Increase Contrast: heavier outline, stronger
grid, no dimmed text. The outline encloses exactly its pixel at 100%. The picture
is the same way up as the view, and a quarter-turned photo matches. At a corner at
800% and 1600%, the grid stops at the photo's edge and the hairline marks it (F3).
Reduce Motion: nothing animates.

**P8. The inspector's look (review M4, DR1, DR2, DR2a, DR7).** Glass panes don't
snapshot. Lens after Details; "Pixel magnifier" fits its 80 pt label column; the
pop-up row sits between Fringe Map and the caption and only the caption moves when
it appears; swatches are the Color Mixer's size and readable when dark; the
fringe map in the frame at fit and 100%.

**P9. A real right-click shows swatches (F5, review M4).** Right-click anywhere on
a slot row. The "Common Fringe Colors" header is a real section header, and Purple
and Green show their own colors. The menu's structure is confirmed by the probe
(`[section]`, `[image]`, S29); a real right-click and the swatch colors are what
remain.

**P10. Keyboard and VoiceOver (PRD M2, review M5, F2, AC1a, R1a, R33, DR2b, DR11,
DR14, DR20).** With Keyboard Navigation on and no pointer, on a scene (a) photo:
the §11 Tab order, the pop-up after Fringe Map, Space opens it. Fill both slots from the
list, change each Tolerance, show and hide the Fringe Map, clear a slot. **Real Esc:** Esc with the keyboard on the eyedropper or a closed pop-up
cancels picking; with a pop-up or ⋯ menu open it only closes the menu and picking
stays on; in the Tolerance field the first Esc hands the keyboard back; with
picking on, Esc in the Export sheet or the ⌘K popover closes only that (F2). Posted
Esc already showed the off-loupe and the Tolerance-field cases (S27, S29); a physical
key, and the menu, sheet and popover cases, are what remain. `-`
and `=` at default settings. VoiceOver announces each step understandably: the
slot group, "Pick Color 1", "Color 1 commands", the menu's header and items,
"Color 1 tolerance", "Pixel magnifier zoom" and its value, "Pixel magnifier at
800%." after a key, the canvas actions, and nothing as the pointer moves.

**P11. Pixels can't be read (review M9, DQ-4, DR22).** On a scratch library only,
through the debug script: `magnifier failsample on`, then arm (review M9's
`magnifier hideoriginal` no longer exists, see DQ-Q1). The eyedropper turns off,
the pointer is the arrow, and the sentence is readable under the slots in the
inspector's glass pane. **VoiceOver says it once.** With `magnifier failsample off`,
clicking the eyedropper works.

**P12. Replacing at 100% (review M6, DR5).** On a 24 MP photo, arming a filled
slot shows the photo without that slot's graying at full resolution, the spinner
only after 0.5 s, and Esc restores.

**P13. Long preset title (review M7, DQ-3).** Apply a preset with a long name and
Align automatically to several photos: the toolbar shortens the name in the
middle, and the popover shows it whole with "‹n› of ‹m›" and Stop.

Known limitation, no check: **RI-CR1** (Lens kernels failing to compile) was ruled
accepted in `prd.md` and no criterion covers it; it is not in this list.

## Follow-up

Reruns after fixes: each finding Fixed or Not fixed, and each P item when the
owner reports it done.

**Owner's sign-off, 2026-11-08:** P1–P13 confirmed by the owner (quote under **For a
person**). AC1a, AC17 and AC27 moved to passed by the owner's check. Q1, Q2 and Q3:
**Not fixed, open follow-ups**; the owner was asked and chose to ship. RI-Q1 is with
the product manager in the Ship pass.

**Rerun, 2026-11-08, screen unlocked, posted events only, at `1eb04aa` (no source
change).** Scripts S26–S30, `open` launches of the QA copy brought forward by process
ID. `print responder` was checked at the start and at checkpoints in each launch: the
first launch lost key and was discarded, and in S29 the first checkpoint read `key
nil` before the probes, with key confirmed at the next checkpoint. Not a physical-input check.

- **Moved to posted evidence:** DR3 (in part), DR6, DR14 (crop), DR19 (the menu), C3 (the pick point),
  F2, F5, AC25's zoom with a real pointer path, and the menu-state and Esc parts of P2 and P10.
- **Unchanged:** the acceptance counts (15 test, 16 script, 1 reading, 0 failed, 3 open)
  and AC1a, AC17, AC25 (pan) and AC27. AC27 stays open: a posted click can't
  complete a pick, and the clamped click wasn't reached.
- **Blocked, not failed:** a posted click that completes a pick (Q3); two QA-copy crash
  reports, named under Tests.
- **Q2:** correct with the app active; it stands for an inactive process.
