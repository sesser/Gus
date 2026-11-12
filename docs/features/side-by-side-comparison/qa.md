Issue: #63

# Side by side comparison: QA

Owner: qa-tester. Date: 2026-11-12. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/side-by-side-comparison` at `179f705`, on an Apple M4 Pro (24 GB), macOS 27.2.1
(26B131), macOS SDK 27.2 (the bundle records `sdk 27.2`). The Mac's display was asleep: every
scripted run used `compare animate off`, and display-link work (`compare panbench`) could not run.

Re-run after D12: `feature/side-by-side-comparison` at `553fc23`, same Mac and SDK (see
[Re-run after D12](#re-run-after-d12)).

Re-run after the merge with develop (#155 rename albums in place, #62 virtual copies) and the
D14 / D15 fix: `feature/side-by-side-comparison` at `34d618d`, same Mac, macOS 27.2.1 (26B131),
SDK 27.2, display asleep (see [Re-run after the merge with develop](#re-run-after-the-merge-with-develop)).

## Verdict

Passes for everything that can be checked here: AC1 to AC6c pass by test and debug script, and
no finding is open. Q1 (code review C11) is fixed at `553fc23` (D12) and no longer reproduces.
AC7 stays open: its number is still pending the owner, and the hitch count needs the display
awake.

Later on 2026-11-12 the owner reverted D12 (`f6c80f7`), so Q1 is back as a known limitation
(#153), and signed off at `09f068c` with checks left open: see [Follow-up](#follow-up).

**After the merge with develop (`34d618d`): passes.** D14 (Duplicate while comparing) and D15 (a
copy's name and Copy badge) pass by script, the AC1 to AC6c regression scripts give the first
pass's results on the merged code, and #62's Duplicate / undo / redo and #155's rename in place
still work. No new finding for the engineer; Q2 (code review C16) is a known weakness of the
tests, not a fault. This is a re-run after the sign-off: the owner's sign-off at `09f068c`
stands as recorded, and **the merged result needs the owner's acknowledgement** (and M10, M11
are new checks for a person, P7 and P8).

## Acceptance criteria

`swift test`: 773 tests in 119 suites passed, 1 known issue (the Live render session's existing
one). `swift test --filter Comparison`: 49 tests in 2 suites (`Comparison`, `Palette contrast`)
passed. The test names below are in `Tests/PhotoCoreTests/ComparisonTests.swift`. The model and
views are in the app target, so the tests check the PhotoCore rules the model calls, and the
scripts check the wiring.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Test, Script | `twoSelectedPhotosAreComparedInSourceOrder`, `activeIsTheLeftPhotoWhenFocusIsNeither`, `aLoadOnlyReplacesALesserRendition`, `panesAreEqualColumnsWithAGutterRoundEach`; scripts [orient](#orient-ac1) and [G](#g-ac1-at-100-and-c4): both photos shown, each at its own fit with its preview, and `rendition full` at 100%. A pane at 100% shows the same render as the single loupe (by eye, the snapshots). That the pictures are identical follows from the code: the panes make the same `PreviewService` requests (code review C5) | Pass |
| AC2 | Test, Script | `commandsActOnTheActivePhotoOnly`, `theGridActsOnItsSelection`; [script A](#a-ac2-ac4-ac6c): `key 3` rates only the active RAW_00008 (`RAW_00008:3`, RAW_00007 stays 0); `undo` gives back 0; after `A`, `key 2` rates only RAW_00007. Undo is covered only by the script (code review C3, accepted) | Pass |
| AC3 | Test, Script | `sameSizeFramesLineUpPixelForPixel`, `differentlySizedPhotosStayOnTheSameRelativePoint`, `theFollowerIsClampedToItsOwnBounds`, `linkedPanesTakeTheSameMagnification`, `aPhotoAsSmallAsItsPaneStillTakesTheOtherTo100Percent`, the step and gesture tests, `theLinkIsOnUntilTurnedOff`; [script C](#c-ac3): `Z` puts both at 1.000 with the same visible unit rect; `pan` keeps them equal (0.5430,0.4665 on both); unlinked, `Z` leaves one at fit and one at 1.000; relinking brings the inactive pane to the active one. [Script D11](#d11-retracing-design-question-2) also covers linked steps with different fits. Mixed states (one pane fitted, one zoomed in) after D12: `aPanOnTheZoomedPhotoLeavesTheFittedOneFitted`, `aSmallGestureOnTheFittedPhotoLeavesTheZoomedOneAlone`, `aFollowerBroughtDownToItsFitIsFitted`, `aWalkedPhotoOpensWhereTheOtherPaneIs` and the [re-run](#re-run-after-d12) scripts (Q1, fixed) | Pass |
| AC4 | Test, Script | `leavingKeepsTheCurrentPairSelectedAndTheActivePhotoFocused`; [script A](#a-ac2-ac4-ac6c): after walking the active left side to RAW_00009, `S` gives `compare off`, `mode loupe`, focus 8 (RAW_00009, the active photo) and selection 7,8, the pair last on screen. The source stays All Photos. The single loupe coming back is covered only by the script | Pass |
| AC5 | Test, Script | `escLeavesReviewFirstAndComparisonStaysOn`; [script E](#e-ac5): `S` in review enters comparison (`review true`); culling and `A` work; Esc leaves review with comparison still on; `F` returns to review; `S` leaves comparison and stays in review (snapshot: single loupe, no sidebar, no strip) | Pass |
| AC6 | Test, Script | `aVideoIsRefusedAndNamed`, `anOfflinePhotoIsRefusedAndNamed`, `whenBothFailTheFirstPhotosFirstReasonIsGiven`, `theRefusalSaysWhetherOnePhotoOrTwoWereAsked`, `theWrongCountEntersNothing`; [scripts F and F2](#f-f2-ac6-ac6a): a photo and a video give "Can’t Compare These Photos" / "“MVI_00015.MOV” is a video. Only photos can be compared.", one OK button, comparison not entered. From the video loupe: "Can’t Compare This Photo". Offline is covered by the unit test only: creating a disk image is not permitted in this environment | Pass |
| AC6a | Test, Script | `theTwoFilesOfOnePairAreRefused`, `thePartnerIsNeverTheOtherFileOfThePair`, the walk, strip and pair-follow tests; [script F](#f-f2-ac6-ac6a): `pairs separate`, PAIR_00013.DNG with PAIR_00013.JPG selected: the alert "… are the RAW and JPEG files of one photo." and not entered. Grouped, PAIR_00013 with PAIR_00014 compares normally | Pass |
| AC6b | Test, Script | `theLoupesPhotoIsComparedWithItsPartnerWhateverIsSelected`, `oneSelectedPhotoIsComparedWithTheNextWhichIsActive`, `thePartnerSkipsWhatCannotBeCompared`, `aStripClickWalksTheActiveSideOrSwitchesSides`; [scripts B and B3](#b-b3-ac6b): from the loupe on IMG_00003, `S` shows IMG_00004 on the right, active ("Comparing IMG_00003 and IMG_00004. Right photo active."); `→` replaces the right photo; one photo selected in the grid, `S` compares it with the next. A film strip cell's press (its accessibility action, the click's handler) replaces the right photo; pressing the left photo's cell makes the left side active | Pass |
| AC6c | Test, Script | `commandsActOnTheActivePhotoOnly`, `thePartnerIsThePhotoLastComparedWith`, `aRememberedPairComesBackOnTheSameSidesWithTheSameOneActive`; [script A](#a-ac2-ac4-ac6c): `A` moves the ring, the active caption, the focus and the title to the left; `S`, `S` brings back RAW_00009 left (active) and RAW_00008 right, as left | Pass |
| AC7 | Script, Person | `photobench compare` here: both sharp p50 183 ms (mean 209) without adjustments and p50 1.16 s with a typical stack, 192 MB held, footprint 1.18 GB / about 4.3 GB. This matches `status.md`. In the app [panbench](#panbench-ac7): both 24 MP raws sharp 0.42 s after zooming in, footprint 106 MB, then 1,047 MB at 100% and 351 MB afterwards, but "the display link does not fire": no hitch count. Target accepted by the owner at sign-off (zero dropped frames, linked and not, 24 MP raws; see Follow-up); the hitch count is still unmeasured. P3 | Open |
| D14 (PRD Decision 16, R3; design §16 D14) | Script, Person | Unit test `undoAndRedoOfDuplicateKeepOrEndTheComparison` pins the rule only (Q2). [Merge re-run](#re-run-after-the-merge-with-develop) scripts d14refuse, d14menu, d14a to d14cd, d14zoom: Duplicate refused while comparing (and in review), dimmed in File, no Duplicate in the pane menu; undo / redo cases (a) to (d) as ruled; zoom and position kept through undo and redo at 100%. M11's keys and look: P8 | Pass (P8 open) |
| D15 (PRD Decision 16, R7; design §16 D15) | Script, Person | Merge re-run script d15: captions `'RAW_00007.DNG'` and `'RAW_00007 copy'` with `[copy]` on the copy only; announcements and pane labels use the copy's name; narrow window snapshot keeps the badge while the name truncates. Truncation on a real 13" layout: P7 (M10) | Pass (P7 open) |

## Findings

**Q1 (code review C11, confirmed; minor, user-visible). Fixed at `553fc23` (design §16 D12);
see [Re-run after D12](#re-run-after-d12).** After a linked zoom step leaves one
pane at its fit and the other zoomed in, a pan of the zoomed pane flips the fitted pane to
"zoomed".
- Steps ([script C11](#c11)): RAW_00007 (6000 × 4000, fit 0.165) on the left, IMG_00006
  (800 × 600, fit 1.000) on the right and active, linked, both at fit. `zoomstep in` twice
  (⌘= ⌘=), then `pan 300 200` on the raw.
- Expected (design §16 D10, fifth bullet): IMG_00006 stays `zoom fit` (it is at its own fit),
  the menu still offers Zoom to 100%, and `Z` takes both to 100%.
- Actual: before the pan, IMG_00006 is at `1.000 zoom fit rendition preview` and the menu state
  is `isZoomed: false`. After the pan it is `1.000 zoom actualSize rendition full`, and the menu
  state is `isZoomed: true, isActualSize: true`, so View says Zoom to Fit. `Z` then takes both
  photos to fit (the raw from 0.500 to 0.165) instead of both to 100%.
- User-visible: yes. After ⌘= and a drag, `Z` zooms out where the person expects 100%, and the
  menu title changes, though nothing moved on the fitted photo. It also starts a full-resolution
  render of the fitted photo (cheap for this JPEG; for a raw beside a raw it is a 24 MP render of
  a photo shown at fit). The next step or `Z` puts both right, so it does no harm beyond one
  surprising keypress. Ruled D12 (each pane's own result). The reverse case (a small
  Option-scroll on the fitted pane) was run in the re-run, with the fitted photo on the left,
  where `optionscroll` and `pan` act.

**DQ-QA1** is ruled D13 (accepted as built); the re-run's D11 script shows the same stops.

No missing tests beyond what code review C3 accepted (undo and the single loupe coming back
on leaving are covered by script only, in the app target).

**Q2 (code review C16; known weakness, not blocking).** `undoAndRedoOfDuplicateKeepOrEndTheComparison`
(`Tests/PhotoCoreTests/ComparisonTests.swift`) calls only `ComparisonRules.reconcile`, which the
D14 commit did not change, so it passes with the fix taken out. The wiring (`!isComparing` in
`canDuplicateTargets`, `replaceItems` calling `reconcileComparison`, the focus chosen after an
undo that ends the comparison) is in the app target and guarded only by the scripts in
[Re-run after the merge with develop](#re-run-after-the-merge-with-develop): rerun d14refuse,
d14a to d14cd and d14zoom after any change to `LibraryModel.replaceItems`, `apply` or
`DuplicateActions`. Remedy, if the engineer takes it: move the focus choice after a replacement
into `ComparisonRules` and test it there, or say in the test's comment that the wiring is checked
by script.

Tooling notes from the merge re-run (no action on this branch):
- The script wraps every `key` command in an undo group of its own; a key that changes nothing
  (`key shift+right`, `key z`) leaves an empty, unnamed undo step (`print undo` shows `undo ''`),
  so a later `undo` undoes nothing. Real typing groups by event and leaves none. Scripts that test
  undo should select with `focus` / `compare on` and zoom with `zoom`.
- `menukey cmd+d s` (or `cmd+d 5`) drops the ⌘D whenever another key follows it in the same
  command, even in the single loupe with nothing compared; `menukey cmd+d` alone works with the
  window key. So "⌘D, then `S` before the copies land" cannot be scripted (see the re-run).

Tooling notes (no action on this branch): the `filmstripclick` click posted to a window that is
not key does not arrive (the accessibility press does). The video loupe's `S` from `key` does
not reach its local event monitor, as `CLAUDE.md` says; `compare on` takes the same path as the
menu item. `alert` reports `key none` for OK; that is already a proposed issue in `status.md`.

### Design question (for apple-ui-designer; the code review's second question, confirmed)

**DQ-QA1: D11's "Zoom In retraces Zoom Out" does not hold when the active photo's fit is not
itself a zoom step.** [Script D11](#d11-retracing-design-question-2): RAW_00001 (portrait
4000 × 6000, fit 0.196, active) on the left, RAW_00007 (fit 0.165) on the right, linked.
⌘= from fit: 0.250 / 0.250, then 0.500 / 0.500 (two presses). ⌘− back: 0.250 / 0.250, then
0.196 / 0.196, then 0.196 / 0.165 (three presses; the extra stop is at the active photo's fit).
100% is never skipped and every state is correct by D10; the two commands just aren't exact
inverses. Accept, or say which side changes.

### Requirements issue (for product-manager, already open)

AC7's number, the owner's raw size and the arrival frames are still "Proposed, pending owner".
AC7 can't pass until the owner accepts them and P3 is run.

## Scripts

All runs used a copy of the bundle at
`<scratch>/GusQA.app` with bundle identifier `me.sesser.gus.debugtest.compare-qa` (re-signed
ad hoc). Each ran as
`<scratch>/GusQA.app/Contents/MacOS/Gus --library-root <scratch>/lib --debug-script "<script>"`.
The library came from `photobench generate --output src --jpeg 6 --dng 6 --heic 0 --pairs 2
--videos 1 --jpeg-size 800x600 --dng-size 6000x4000`, plus a second
`generate --dng 2 --dng-size 4000x6000` (portrait raws), each `photobench import`ed with
`previews --tier preview`. Index numbers changed after the second import (date sort). The
scripts after that point use names.

### orient (AC1)
```
wait 3; compare animate off; print items; print menustate; focus 0; key shift+right; compare on; wait 2; print compare; snapshot <out>/ac1.png; quit
```
Left IMG_00001 (portrait), right IMG_00002 active, both `magnification 1.000 fit 1.000 zoom fit
rendition preview`. The ring is drawn around the right pane (neutral: the window is not key);
the captions read "IMG_00001.JPG · 1 of 15" and "IMG_00002.JPG · 2 of 15"; the subtitle is
"Comparing · All Photos". Snapshot looked at: both photos are whole in their panes, and the
strip shows IMG_00002 outlined and IMG_00001 filled.

### A (AC2, AC4, AC6c)
```
wait 3; compare animate off; focus 6; key shift+right; compare on; wait 1; print compare; key 3; wait 1; print items; undo; wait 1; print items; key a; wait 1; print compare; key 2; wait 1; print items; print undo; key right; wait 1; print compare; key s; wait 1; print compare; print selection; print menustate; key s; wait 1; print compare; quit
```
Entering: RAW_00007 left, RAW_00008 right, active. `key 3`: `RAW_00007:0 RAW_00008:3`; undo:
both 0. `key a`: active left, focus 6, title RAW_00007.DNG. `key 2`: `RAW_00007:2` only; undo
'Set Rating'. `→`: the left side walks to RAW_00009 (left 9, right 8). `S`: `compare off mode
loupe selection 7,8 focus 8`. `S`: RAW_00009 left and active, RAW_00008 right, as left.

### B, B3 (AC6b)
```
wait 3; compare animate off; focus 2; loupe; wait 1; key s; wait 1; print compare; print announcement; key right; wait 1; print compare; filmstripclick 0; wait 1; print compare; key s; grid; focus 4; wait 1; key s; wait 1; print compare; quit
```
```
wait 3; compare animate off; focus 2; loupe; wait 1; key s; wait 1; accessibility AXImage 7 press; wait 1; print compare; accessibility AXImage 4 press; wait 1; print compare; quit
```
B: from the loupe on IMG_00003: right IMG_00004 active, announcement "Comparing IMG_00003 and
IMG_00004. Right photo active."; `→`: right is IMG_00005. `filmstripclick` hit a strip cell but
the posted click changed nothing (the window is not key). From the grid with IMG_00005 alone
selected, `S`: IMG_00005 left, IMG_00006 right and active. B3: pressing IMG_00006's strip cell
puts it on the right side (active); pressing IMG_00003's cell (the left photo) makes the left
side active.

### C (AC3)
```
wait 3; compare animate off; focus 6; key shift+right; compare on; wait 1; key z; wait 3; print compare; pan 400 -250; wait 1; print compare; compareclick left 0.2 0.3; wait 1; print compare; compare link off; key z; wait 1; print compare; pan 200 0; wait 1; print compare; compare link on; wait 2; print compare; key z; wait 1; print compare; print menustate; quit
```
`Z`: both `1.000 actualSize rendition full visible 0.4097,0.3415 0.1807x0.3180`. `pan`: both
`0.5430,0.4665`. `compareclick left` on the inactive pane: it only becomes active (no zoom).
Unlinked `Z`: left 0.165 fit, right still 1.000. Relink: right goes to fit with the active pane.
`Z`: both at 1.000 again.

### C11
```
wait 3; compare animate off; focus 6; loupe; wait 1; key s; wait 1; key left; wait 1; print compare; zoomstep in; wait 2; print compare; zoomstep in; wait 2; print compare; pan 300 200; wait 2; print compare; print menustate; key z; wait 2; print compare; quit
```
RAW_00007 (fit 0.165) left, IMG_00006 (fit 1.000) right and active. ⌘=: 0.250 / 1.000 fit; ⌘=:
0.500 / 1.000 fit, `isZoomed: false`. `pan`: IMG_00006 `zoom actualSize rendition full`,
`isZoomed: true, isActualSize: true`. `Z`: both to fit (0.165 / 1.000). See Q1.

### D11 retracing (design question 2)
```
wait 3; compare animate off; focus RAW_00001; loupe; wait 1; key s; wait 1; key right right right right right right; wait 2; compare active left; print compare; zoomstep in; wait 2; print compare; zoomstep in; wait 2; print compare; zoomstep out; wait 2; print compare; zoomstep out; wait 2; print compare; zoomstep out; wait 2; print compare; zoomstep out; wait 2; print compare; quit
```
RAW_00001 (0.196, active) / RAW_00007 (0.165): in 0.250 / 0.250, 0.500 / 0.500; out 0.250 /
0.250, 0.196 / 0.196 (the right pane `actualSize`, above its fit), 0.196 / 0.165 (both `fit`),
then nothing. See DQ-QA1.

### E (AC5)
```
wait 3; compare animate off; focus RAW_00007; key shift+right; review on; wait 2; key s; wait 1; print compare; key 2; wait 1; key a; wait 1; key x; wait 1; print compare; key escape; wait 2; print compare; key f; wait 2; print compare; key s; wait 1; print compare; print menustate; snapshot <out>/review.png; quit
```
Review opened the loupe on RAW_00008; `S`: RAW_00008 / RAW_00009 active, `review true`. `2`
rated RAW_00009, `A` then `X` rejected RAW_00008. Esc: `review false`, comparison still on. `F`:
`review true`. `S`: `compare off mode loupe`, focus RAW_00008. Snapshot looked at: review's
single loupe (no sidebar, strip or inspector), "10 of 17" and the reject mark.

### F, F2 (AC6, AC6a)
```
wait 3; compare animate off; focus MVI_00015; key shift+left; wait 1; print selection; compare on; wait 1; alert; print compare; alert press OK; wait 1; focus MVI_00015; loupe; wait 2; key s; wait 1; alert; alert press OK; grid; wait 1; pairs separate; wait 2; focus PAIR_00013; key shift+right; wait 1; print selection; compare on; wait 1; alert; print compare; alert press OK; pairs grouped; wait 2; focus PAIR_00013; key shift+right; compare on; wait 1; print compare; quit
```
```
wait 3; compare animate off; focus MVI_00015; loupe; wait 2; print menustate; compare on; wait 1; alert; print compare; alert press OK; quit
```
The alert texts are quoted in the AC table, and comparison was not entered (`compare off`) each
time. The video loupe's scripted `S` did not arrive (tooling note); F2's `compare on` in the
video loupe gave "Can’t Compare This Photo". Grouped: PAIR_00013 and PAIR_00014 compared.

### G (AC1 at 100%, and C4)
```
wait 3; compare animate off; compare link on; focus RAW_00007; loupe; wait 2; key z; wait 3; snapshot <out>/single100.png; key z; wait 1; key s; wait 1; compare active left; key z; wait 3; print compare; snapshot <out>/compare100.png; key z; wait 1; filmstrip off; wait 1; filmstrip on; wait 2; print compare; quit
```
Both panes at 1.000 on the same unit rect. The comparison snapshot shows the middle of
RAW_00007 (the gray ellipse on the ochre ground) beside RAW_00008, in the single loupe's
colors. The single loupe's 100% snapshot is still at fit: its zoom animation never finishes
while the display sleeps. C4 with animation off: after the strip toggles, both panes report
`zoom fit`. Their rendition stays `full` because these panes had been at 100% (a pane keeps its
full-resolution picture until it shows another photo, `status.md` Memory). The C4 check from a
fresh fit with animation on is P1.

### panbench (AC7)
```
wait 3; focus RAW_00007; key shift+right; compare on; wait 2; compare panbench 6; compare link off; compare panbench 6; quit
```
"photos 6000x4000 and 6000x4000 both sharp yes after 0.42 s, footprint 106 MB before, 1047 MB
at 100%", then "the display link does not fire (display asleep …); nothing measured", linked
and not linked.

### Re-run after D12

At `553fc23` (D12, D13), 2026-11-12, display asleep. `swift test`: 777 tests in 119 suites
passed, 1 known issue (the Live render session's). `swift test --filter Comparison`: 53 tests in
2 suites passed. The new `ComparisonLink.follow` tests are read: Q1's case expects the fitted
photo returned unchanged (the old wiring set it to the leader's zoom, so the case could not have
passed before), the reverse case expects nil at 1.03 and 1.06 zoomed past the threshold.

A fresh bundle (`Scripts/build-app.sh`, `sdk 27.2`) copied to `<scratch>/GusQA.app` with bundle
identifier `me.sesser.gus.debugtest.compare-qa-d12`, re-signed ad hoc, on a fresh scratch library
made as above. Every run starts `wait 3; compare animate off; compare link on` (the link is a
preference; one early D10/D11 attempt ran unlinked after an unlinking script and was rerun).
Order: IMG_00006, RAW_00007, RAW_00008, … RAW_00001 and RAW_00002 among the JPEGs. `pan` and
`optionscroll` act on the left pane.

**C11 (Q1): no longer reproduces.**
```
focus RAW_00007; loupe; wait 1; key s; wait 1; key left; wait 1; print compare; zoomstep in; wait 2; print compare; zoomstep in; wait 2; print compare; pan 300 200; wait 2; print compare; print menustate; key z; wait 2; print compare; pan 200 100; wait 2; print compare; key z; wait 2; print compare; quit
```
RAW_00007 left (fit 0.165), IMG_00006 right (fit 1.000) active. ⌘=: 0.250 / 1.000 fit; ⌘=:
0.500 / 1.000 fit. After `pan 300 200` the raw moved (0.3193,0.1820 to 0.4193,0.0820) and
IMG_00006 is still `1.000 fit 1.000 zoom fit rendition preview`, `isZoomed: false`. `Z`: both
1.000, zoomed in, `isActualSize: true`. A pan there leaves both zoomed in (C2). `Z`: 0.165 /
1.000, both fitted. Snapshot after the pan looked at: the raw zoomed in on the left, the whole
JPEG in the right pane, ring on the right.

**Reverse case** (fitted JPEG on the left, raw active on the right at 0.500 after ⌘= ⌘=), run
once with 0.2 lines (3%) and once with 0.6 lines (9.4%):
```
focus IMG_00006; key shift+right; compare on; wait 1; compare active right; zoomstep in; wait 2; zoomstep in; wait 2; print compare; hit 275 350; optionscroll 275 350 <lines>; wait 2; print compare; quit
```
3%: IMG_00006 1.030, `zoom fit`, preview; RAW_00007 left exactly as it was (0.500, same visible
rect, zoomed in). 9.4%: both 1.094, zoomed in, `rendition full`. The ring stays on the right.

**C2, equal raws, and walks**:
```
focus RAW_00007; key shift+right; compare on; wait 1; key z; wait 3; print compare; pan 300 200; wait 2; print compare; key right; wait 3; print compare; key z; wait 2; print compare; key right; wait 3; print compare; quit
```
`Z`: both 1.000 zoomed in, same unit rect; `pan`: both still zoomed in at 0.5097,0.2415. A walk
at 100% (right side to RAW_00009): it opens at 1.000, zoomed in, `rendition full`, on the same
rect. `Z`: both fitted. A walk at fit (to RAW_00010): fit, `rendition preview`.

**A walk in a mixed state** (C11's setup, then walking the fitted right side):
```
focus RAW_00007; loupe; wait 1; key s; wait 1; key left; wait 1; zoomstep in; wait 2; zoomstep in; wait 2; print compare; key left; wait 3; print compare; key right; wait 1; key right; wait 3; print compare; quit
```
To IMG_00005 (fit 1.000): it opens at its fit, fitted, preview; the raw untouched at 0.500. To
RAW_00008: it opens at 0.500, zoomed in, on the raw's rect.

**Relinking** (D12 rule 4):
```
focus RAW_00007; key shift+right; compare on; wait 1; compare link off; key z; wait 2; print compare; compare link on; wait 2; print compare; quit
```
```
focus IMG_00006; key shift+right; compare on; wait 1; compare link off; zoomstep in; wait 2; zoomstep in; wait 2; print compare; compare link on; wait 2; print compare; quit
```
Equal raws, the active one at 1.000: relinking brings the other to 1.000, zoomed in. Raw active
at 0.500 beside the fitted JPEG: relinking leaves the JPEG at 1.000, fitted, preview.

**AC3** (script C, rerun as written above, with names): same results as the first pass,
`0.5430,0.4665` on both after the pan.

**D10**:
```
focus IMG_00006; key shift+right; compare on; wait 1; compare active left; key z; wait 2; zoomstep in; wait 2; print compare; zoomstep out (five times, printing each)
```
2.000 / 2.000; ⌘−: 1.000 (fit) / 1.000 zoomed in, Zoom Out still enabled; then the raw alone
0.500, 0.250, 0.165 (fitted, Zoom Out dimmed); the last press changes nothing.

**D11 / D13** (script D11 above, link on, RAW_00001 active with RAW_00008): in 0.250 / 0.250,
0.500 / 0.500; out 0.250 / 0.250, 0.196 / 0.196, 0.196 / 0.165 (both fitted); in 0.250 / 0.250.
As D13 accepts.

**C9** (both fitted, a 3% Option-scroll on the left):
```
focus IMG_00006; key shift+right; compare on; wait 1; print compare; optionscroll 275 350 0.2; wait 2; print compare; quit
```
IMG_00006 1.030 and RAW_00007 0.170, both `zoom fit`, `rendition preview`.

**AC2, AC4, AC6c** (script A, with names): the same results as the first pass.

After the runs no instance was running and the owner's library folder had no file newer than the
start. The scratch library, bundle copy and its preferences were removed.

### Re-run after the merge with develop

At `34d618d` (merge `bf3f55e` with #155 and #62, then D14 / D15 in `6345a70`), 2026-11-12,
display asleep. `swift test`: 816 tests in 121 suites passed, 1 known issue (the Live render
session's). `swift test --filter 'ComparisonTests|VirtualCopiesTests|Comparison'`: 81 tests in 3
suites passed. `Scripts/build-app.sh`: complete, `vtool` shows `sdk 27.2`.

A copy of the bundle at `<scratch>/GusQA.app`, bundle identifier
`me.sesser.gus.debugtest.compare-qa2`, re-signed ad hoc. Library: `photobench generate --output
src --jpeg 6 --dng 6 --heic 0 --pairs 2 --videos 1 --jpeg-size 800x600 --dng-size 6000x4000`,
`import`, `previews --tier preview` and `--tier thumbnail`; every run started from a fresh copy
of it. Each ran as `<scratch>/GusQA.app/Contents/MacOS/Gus --library-root <scratch>/lib
--debug-script "wait 3; compare animate off; compare link on; rating any; flag any; pairs
grouped; sort captureDate asc; wait 1; <script>"` (filters and window size are preferences and
carry between runs). Order: IMG_00001 … IMG_00006, RAW_00007 … RAW_00012, PAIR_00013, PAIR_00014,
MVI_00015; a copy goes right after its original.

**d14refuse** (D14.1):
```
focus RAW_00007; key shift+right; compare on; wait 1; print compare; duplicate; print copies; menuitems Duplicate; print menustate; review on; wait 2; print compare; duplicate; print copies; quit
```
`duplicate unavailable`, `canDuplicate false`, list unchanged (15), `File/Duplicate key cmd+"d"
disabled`; the same in review (`review true`).

**d14menu** (D14.1, pane menu):
```
focus RAW_00007; key shift+right; compare on; wait 1; contextmenu at 700 300; contextmenu at 400 300; print compare; quit
```
Both panes' menus: Rating, Flag, Color Label, Add Keywords…, Suggest Keywords, Copy Adjustments,
then one separator, Export…, Show in Finder, then the zoom items, Link Zoom and Position
(checked), Stop Comparing. No Duplicate. The right-click on the inactive left pane made it active.

**d14a** (copy beside its neighbor, undo takes the copy):
```
focus RAW_00007; duplicate; print copies; compare on; wait 1; print compare; print undo; undo; wait 2; print compare; print copies; print announcement; print undo; quit
```
Compared `'RAW_00007 copy'` [copy] (left) with RAW_00008 (right, active). Undo: `compare off
mode loupe selection 7 focus 7` (RAW_00008 alone), announcement "RAW_00008, RAW, 8 of 15", redo
'Duplicate'.

**d14b** (two copies, undo takes both):
```
focus RAW_00007; key shift+right; duplicate; print copies; compare on; wait 1; compare active left; print compare; undo; wait 2; print compare; print copies; print announcement; quit
```
Compared `RAW_00007 copy` (left, active) with `RAW_00008 copy`. Undo: `compare off mode loupe
selection 6 focus 6`: RAW_00007, the active copy's original (the undo's own focus would have
been RAW_00008), announced "RAW_00007, RAW, 7 of 15".

**d14cd** (undo, then redo, of another photo's Duplicate while comparing):
```
focus RAW_00007; duplicate; focus IMG_00003; duplicate; print copies; focus 8; compare on; wait 1; print compare; print undo; undo; wait 2; print compare; print copies; print undo; print announcement; redo; wait 2; print compare; print copies; key 5; wait 1; print items; print copies; print undo; quit
```
(c) Undo of IMG_00003's Duplicate: same sides (RAW_00007 copy left, RAW_00008 right, active),
selection the pair (8,9 → 7,8 as the list shrank), focus the active photo, positions now "of
16", no comparison announcement. (d) Redo: unchanged again; the copy is back in the list only;
`key 5` rates RAW_00008 alone ('Set Rating').

**d14zoom** (`review.md` sixth pass, the M11 addition: a pair at 100%, undo of a Duplicate made
before comparing):
```
focus IMG_00003; duplicate; focus RAW_00007; compare on; wait 1; zoom; wait 3; pan 300 200; wait 2; print undo; print compare; undo; wait 3; print compare; print copies; redo; wait 3; print compare; print undo; snapshot <out>/d14zoom.png; quit
```
Before, after the undo and after the redo, both panes: `magnification 1.000 zoom actualSize
rendition full visible 0.5097,0.2415 0.1807x0.3180`; selection 7,8 → 6,7 → 7,8, focus the active
photo. Snapshot looked at: both raws zoomed in on the same spot, ring on the right, captions "8
of 16" and "9 of 16". (A first attempt with `key shift+right` and `key z` hit the tooling note's
empty undo step; this version avoids `key`.)

**⌘D in the single loupe, then `S` at once.** Not scriptable (tooling note): `key cmd+d s` and
`menukey cmd+d s` (launched with `open -W -n --stdout … --args --library-root <scratch>/lib …`,
window key) both entered the comparison with no copy made; `menukey cmd+d 5` without comparing
also made no copy; `menukey cmd+d` alone made one. A one-photo Duplicate lands in milliseconds,
so a person can hardly reach this either. The copies landing while comparing take the same path
as (d)'s redo (`showCopies` → `replaceItems` → kept), which passes.

**filter** (a compared photo leaves the source by a filter change):
```
focus RAW_00007; compare on; wait 1; compare active left; key 5; wait 1; compare active right; print compare; rating 5; wait 2; print compare; print announcement; print title; quit
```
RAW_00008 (active) leaves under "5 stars": `compare off mode loupe`, RAW_00007 alone, announcement
"RAW_00007, RAW, 5 stars, 1 of 1".

**d15** (a photo beside its copy):
```
focus RAW_00007; duplicate; focus RAW_00007; compare on; wait 1; print compare; print announcement; snapshot <out>/d15.png; compare active left; print announcement; compare active right; accessibility AXImage; key right; wait 1; print announcement; key left; wait 1; print announcement; print compare; …; windowsize 700 600; …; focus RAW_00007; compare on; wait 2; print compare; snapshot <out>/d15narrow.png; quit
```
Captions: left `'RAW_00007.DNG'` badges [], right `'RAW_00007 copy'` badges [copy]; title
`RAW_00007 copy`. Announcements: "Comparing RAW_00007 and RAW_00007 copy. Right photo active.",
"Left photo active: RAW_00007", walking "Right photo: RAW_00008, RAW, 9 of 16" and back "Right
photo: RAW_00007 copy, RAW, 8 of 16". Pane labels `'RAW_00007, RAW'` / `'RAW_00007 copy, RAW'`,
strip cells the same. Narrow window (panes 262 pt) snapshot looked at: the right caption reads
"RAW…copy" with the Copy badge, the left "RAW_00007.DNG"; the strip cell of the copy has its
copy mark. Refusal alerts naming a copy: only the offline case can name one (a copy is never a
video, and is never half of a pair), and offline can't be made here, so that text is checked by
code review (C15) only. **paircopy2**: with `pairs separate`, PAIR_00013's copy beside
PAIR_00013.JPG compares (no alert; Decision 16), captions `'PAIR_00013 copy'` [copy] and
`'PAIR_00013.JPG'`.

**Regression (AC1 to AC6c)** on the merged code, scripts as in the first pass with names:
- **A**: same results: `RAW_00008:3` then undo 0; `A` moves to the left; `RAW_00007:2`; `→`
  walks left to RAW_00009; `S` gives `compare off mode loupe selection 7,8 focus 8`; `S` brings
  back RAW_00009 (left, active) and RAW_00008.
- **B, B3**: from the loupe on IMG_00003, IMG_00004 right and active, the same announcement; `→`
  to IMG_00005; from the grid, IMG_00005 with IMG_00006. Strip cell presses: IMG_00006 to the
  right; IMG_00003's cell makes the left side active.
- **C**: `Z` both 1.000 on `0.4097,0.3415`; pan both `0.5430,0.4665`; `compareclick left` only
  activates; unlinked `Z` left to fit, right stays 1.000; relink brings the right to fit; `Z`
  both 1.000.
- **D10**: 2.000 / 2.000; ⌘−: 1.000 fit / 1.000 zoomed in, Zoom Out enabled; 0.500, 0.250,
  0.165 fit (Zoom Out dimmed); the last press changes nothing.
- **C11** (#153, accepted): after ⌘= ⌘= and a pan of the raw, IMG_00006 flips to `actualSize
  rendition full` and `Z` takes both to fit, exactly as recorded before D12; unchanged by the
  merge.
- **E**: review, `S`, culling, `A`, Esc (comparison stays), `F`, `S` (single loupe, review).
- **F, F2**: video: "Can’t Compare These Photos" / "“MVI_00015.MOV” is a video. Only photos can
  be compared."; separate pair: "“PAIR_00013.DNG” and “PAIR_00013.JPG” are the RAW and JPEG
  files of one photo."; grouped pair compares; from the video loupe "Can’t Compare This Photo".

**#62 sanity** (`dup`): `duplicate` on IMG_00003: 15 → 16, the copy focused, undo 'Duplicate',
"Made a copy of “IMG_00003”."; undo: 15, focus the original; redo: 16, the copy back; in the
loupe the title `IMG_00003 copy`, the Copy badge and its tooltip; `key 5` rates the copy only.

**#155 sanity** (`rename`, `renamecmp`): `renamealbum; text Best picks; key return` renames
Keepers in place, undo 'Rename Album' gives Keepers back, redo Best picks. Renaming an album
from its row menu while comparing (`renamealbum 0`) leaves the comparison as it was (sides,
active side, selection, focus), before and after its undo.

After the runs no instance was running and the owner's library folder had no file newer than the
start. The scratch library, the bundle copy and its preferences were removed.

## For a person

The owner does not check VoiceOver or macOS 15 and 26 (README). P1 and P3 need the display
awake; they are commands, so qa-tester can also run them when the Mac is awake.

- **P1. Animations** (M3; code review C4, C9, D10, D11 with animation). With the display awake,
  in the library window: from the loupe press `S`. The loupe's photo shrinks into the left pane
  and the other fades in on the right, in about a sixth of a second. `S` again: the active photo
  grows back. With the right photo active, `S` `S` gives the same pair, and the photo moves into
  the right pane. Linked, press ⌘= and ⌘− a few times, and `Z` twice: each change animates and
  ends with both photos at the same size. Then, from fit, hide and show the film strip (⌥⌘B
  twice) and check that both photos refit and stay at fit (scripted:
  `compare on; filmstrip off; wait 1; filmstrip on; wait 2; print compare` should show
  `zoom fit` and a rendition that is not `full` on both).
- **P2. Real mouse and trackpad** (M2, C9). A click on the inactive photo only moves the ring;
  the next click zooms. A drag starting on it activates and pans both. A small pinch (a few
  percent) leaves both at fit, and a bigger pinch zooms both together. Scrolling or pinching over
  the inactive photo does not move the ring. A double-click shows the grid. Added with D12
  (`review.md` fourth pass, M2): with a raw beside a small JPEG (about the pane's size), linked,
  the JPEG active, press ⌘= twice, then drag the raw with the mouse. The JPEG must not change,
  View must still say Zoom to 100%, and `Z` must take both to 100%. (Scripted with `pan` in the
  re-run; this is the real drag.)
- **P3. AC7's number** (pending the owner). With the display awake and nothing else busy, on a
  scratch library with two 24 MP raws (or copies of the owner's own raws), compare them and run
  `compare panbench 6`, then `compare link off; compare panbench 6`. Each should report
  `hitches 0`. Target and raw size decided by the owner at sign-off (see Follow-up).
- **P4. Menus and alert keys** (M1, M5). With the window key while comparing, the View menu
  shows Stop Comparing (S), Switch to Left/Right Photo (A) naming the inactive side, and Link
  Zoom and Position checked; Show Original and Show History are dimmed. Compare Side by Side is
  dimmed with three photos selected. On the refusal alert (a photo and a video selected, `S`),
  Return and Esc both close it.
- **P5. Looks** (M4, M6, M7, M8). The ring is the accent color, gray with another app in front,
  thicker with Increase Contrast. In the strip, the active photo is outlined and the other is
  filled. The link button has a bezel when linked and none when unlinked. The toolbar's Compare
  item (add it with Customize Toolbar) shows a bezel while comparing. In a window about 1,000 pt
  wide with the sidebar and inspector shown, both photos are usable; narrowing further, the
  position goes first, then the name shortens, and the marks stay.
- **P6. Full Keyboard Access** (M9). Tab from the sidebar lands on the comparison once, and the
  next Tab goes on to the inspector. The arrow keys walk the active side while it has focus.
- **P7. A photo beside its copy in a narrow window** (M10, D15). Select a photo, File ▸
  Duplicate (⌘D), select the photo and its copy in the grid and press `S`. With the sidebar and
  inspector shown on a 13" display (or the window made narrow), the copy's caption keeps its Copy
  badge and its marks (rating, flag, label) while its name truncates in the middle; the other
  caption has no badge. (Scripted at 262 pt panes: the badge stays and the name reads "RAW…copy";
  this is the look on a real layout.)
- **P8. Duplicate while comparing** (M11, D14). With the window key while comparing, ⌘D beeps
  and makes no copy, File ▸ Duplicate is dimmed, and a right-click on either pane shows no
  Duplicate. Then, from the `review.md` sixth pass: Duplicate another photo, compare a pair and
  zoom both to 100% (`Z`) on some detail, then Edit ▸ Undo Duplicate (and Redo): both panes keep
  their zoom and position, and the same photos stay on the same sides. (Scripted with `zoom`,
  `pan` and `undo`; this is the real keys and menus.)

## Follow-up

- 2026-11-12, `553fc23` (D12, D13): **Q1 Fixed** ([Re-run after D12](#re-run-after-d12)).
  DQ-QA1 ruled D13, accepted as built. No new findings. P1 to P6 still open; P2 gained the M2
  drag item from `review.md`'s fourth pass.
- 2026-11-12, `f6c80f7`: the owner reverted D12 (`status.md`, "D12 reverted"); D13's wording
  stays. **Q1 Not fixed, accepted as a known limitation: #153** (linked, after ⌘= twice and a
  drag of the zoomed photo, the fitted photo's zoom state can flip and `Z` goes to fit instead of
  100%; the next step or `Z` puts both right). The D12 scripts in
  [Re-run after D12](#re-run-after-d12) and the D12 drag item in P2 describe the reverted rule and
  no longer apply.
- **Sign-off.** The owner signed off on 2026-11-12 ("looks good") after trying the bundled app on
  a playground library. Commit signed off: `09f068c` (`feature/side-by-side-comparison`).
  Owner decisions the same day:
  - AC7's target is accepted as proposed: zero dropped frames while panning two sharp raws at
    100% on the reference Mac, linked and not linked. The long frames when a full-resolution
    picture arrives stay outside it.
  - The owner's usual raw size is 24 MP (the size `photobench compare` and the panbench scripts
    used).

  **Checks left open at sign-off** (for the pull request and #82):
  1. **AC7 hitch count (P3).** `compare panbench 6`, then `compare link off; compare panbench 6`
     on two 24 MP raws with the display awake; each should report `hitches 0`. Never measured:
     the display was asleep. AC7 stays Open until it is.
  2. **Animations (P1, M3).** Entering and leaving comparison, ⌘= / ⌘− and `Z` animating with
     both photos ending at the same size, and the film strip toggle (⌥⌘B twice) refitting both.
  3. **Real pinch and trackpad (P2, M2).** Click, drag, pinch, scroll over the inactive photo,
     double-click, with a real mouse and trackpad (the D12 drag item excepted: that is #153).
  4. **Menus with a key window and alert keys (P4, M1, M5).** The View menu's comparison items
     and their state while comparing; Return and Esc on the refusal alert.
  5. **Looks (P5, M4, M6, M7, M8) and Full Keyboard Access (P6, M9).** M1 to M9 in `review.md`
     were tried informally by the owner, not recorded one by one, so each stays open.

  Known limitation: #153 (above). VoiceOver and macOS 15 and 26 are not owner checks (README).
- 2026-11-12, `34d618d`: **re-run after the merge with develop** (#155, #62) and D14 / D15
  ([Re-run after the merge with develop](#re-run-after-the-merge-with-develop)). Full `swift
  test` and `Scripts/build-app.sh` pass. D14 and D15 pass by script; AC1 to AC6c give the first
  pass's results; #62 and #155 sanity runs pass; #153 behaves as accepted. No new finding for
  the engineer. Q2 (code review C16) recorded as a known weakness: the D14 wiring is guarded by
  script only. New checks for a person: P7 (M10) and P8 (M11). The sign-off above (at
  `09f068c`) is unchanged; **the merged result at `34d618d` needs the owner's acknowledgement**,
  with P7 and P8 either done or named as left open (for the pull request and #82).
