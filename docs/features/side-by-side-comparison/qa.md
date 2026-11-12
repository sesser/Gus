Issue: #63

# Side by side comparison: QA

Owner: qa-tester. Date: 2026-11-12. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/side-by-side-comparison` at `179f705`, on an Apple M4 Pro (24 GB), macOS 27.2.1
(26B131), macOS SDK 27.2 (the bundle records `sdk 27.2`). The Mac's display was asleep: every
scripted run used `compare animate off`, and display-link work (`compare panbench`) could not run.

## Verdict

Passes for everything that can be checked here: AC1 to AC6c pass by test and debug script, and
no finding blocks. AC7 stays open: its number is still pending the owner, and the hitch count
needs the display awake. C11, the code reviewer's traced nit, reproduces and is user-visible
(Q1, minor).

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
| AC3 | Test, Script | `sameSizeFramesLineUpPixelForPixel`, `differentlySizedPhotosStayOnTheSameRelativePoint`, `theFollowerIsClampedToItsOwnBounds`, `linkedPanesTakeTheSameMagnification`, `aPhotoAsSmallAsItsPaneStillTakesTheOtherTo100Percent`, the step and gesture tests, `theLinkIsOnUntilTurnedOff`; [script C](#c-ac3): `Z` puts both at 1.000 with the same visible unit rect; `pan` keeps them equal (0.5430,0.4665 on both); unlinked, `Z` leaves one at fit and one at 1.000; relinking brings the inactive pane to the active one. [Script D11](#d11-retracing-design-question-2) also covers linked steps with different fits. See Q1 for one state where the two panes' zoom states drift apart | Pass |
| AC4 | Test, Script | `leavingKeepsTheCurrentPairSelectedAndTheActivePhotoFocused`; [script A](#a-ac2-ac4-ac6c): after walking the active left side to RAW_00009, `S` gives `compare off`, `mode loupe`, focus 8 (RAW_00009, the active photo) and selection 7,8, the pair last on screen. The source stays All Photos. The single loupe coming back is covered only by the script | Pass |
| AC5 | Test, Script | `escLeavesReviewFirstAndComparisonStaysOn`; [script E](#e-ac5): `S` in review enters comparison (`review true`); culling and `A` work; Esc leaves review with comparison still on; `F` returns to review; `S` leaves comparison and stays in review (snapshot: single loupe, no sidebar, no strip) | Pass |
| AC6 | Test, Script | `aVideoIsRefusedAndNamed`, `anOfflinePhotoIsRefusedAndNamed`, `whenBothFailTheFirstPhotosFirstReasonIsGiven`, `theRefusalSaysWhetherOnePhotoOrTwoWereAsked`, `theWrongCountEntersNothing`; [scripts F and F2](#f-f2-ac6-ac6a): a photo and a video give "Can’t Compare These Photos" / "“MVI_00015.MOV” is a video. Only photos can be compared.", one OK button, comparison not entered. From the video loupe: "Can’t Compare This Photo". Offline is covered by the unit test only: creating a disk image is not permitted in this environment | Pass |
| AC6a | Test, Script | `theTwoFilesOfOnePairAreRefused`, `thePartnerIsNeverTheOtherFileOfThePair`, the walk, strip and pair-follow tests; [script F](#f-f2-ac6-ac6a): `pairs separate`, PAIR_00013.DNG with PAIR_00013.JPG selected: the alert "… are the RAW and JPEG files of one photo." and not entered. Grouped, PAIR_00013 with PAIR_00014 compares normally | Pass |
| AC6b | Test, Script | `theLoupesPhotoIsComparedWithItsPartnerWhateverIsSelected`, `oneSelectedPhotoIsComparedWithTheNextWhichIsActive`, `thePartnerSkipsWhatCannotBeCompared`, `aStripClickWalksTheActiveSideOrSwitchesSides`; [scripts B and B3](#b-b3-ac6b): from the loupe on IMG_00003, `S` shows IMG_00004 on the right, active ("Comparing IMG_00003 and IMG_00004. Right photo active."); `→` replaces the right photo; one photo selected in the grid, `S` compares it with the next. A film strip cell's press (its accessibility action, the click's handler) replaces the right photo; pressing the left photo's cell makes the left side active | Pass |
| AC6c | Test, Script | `commandsActOnTheActivePhotoOnly`, `thePartnerIsThePhotoLastComparedWith`, `aRememberedPairComesBackOnTheSameSidesWithTheSameOneActive`; [script A](#a-ac2-ac4-ac6c): `A` moves the ring, the active caption, the focus and the title to the left; `S`, `S` brings back RAW_00009 left (active) and RAW_00008 right, as left | Pass |
| AC7 | Script, Person | `photobench compare` here: both sharp p50 183 ms (mean 209) without adjustments and p50 1.16 s with a typical stack, 192 MB held, footprint 1.18 GB / about 4.3 GB. This matches `status.md`. In the app [panbench](#panbench-ac7): both 24 MP raws sharp 0.42 s after zooming in, footprint 106 MB, then 1,047 MB at 100% and 351 MB afterwards, but "the display link does not fire": no hitch count. The target itself is pending the owner (PRD Assumptions). P3 | Open |

## Findings

**Q1 (code review C11, confirmed; minor, user-visible).** After a linked zoom step leaves one
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
  surprising keypress. The fix waits on the designer's answer to the code review's first
  question (whether a pan follows D10's per-pane state or C2's shared state). Not run: the
  reverse case (a small Option-scroll or pinch on the fitted pane zooming the other one out),
  which `optionscroll` can't aim at the right pane.

No missing tests beyond what code review C3 accepted (undo and the single loupe coming back
on leaving are covered by script only, in the app target).

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
  the inactive photo does not move the ring. A double-click shows the grid.
- **P3. AC7's number** (pending the owner). With the display awake and nothing else busy, on a
  scratch library with two 24 MP raws (or copies of the owner's own raws), compare them and run
  `compare panbench 6`, then `compare link off; compare panbench 6`. Each should report
  `hitches 0`. First decide AC7's target and the raw size (PRD Assumptions).
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

## Follow-up

None yet.
