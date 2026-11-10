# Sharp live frames at 100%: QA

Owner: qa-tester. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`. PR #49.
Tested: `feature/viewport-render-1to1` at `fde04fc`, on a MacBook Pro with Apple M4 Pro (14-core CPU, 24 GB), macOS 27.2 (26B123), app linked with the macOS 27.2 SDK (`vtool -show-build`), main display DELL U2723QE (framebuffer 6016 × 3384).

**How it was run.** From a scratch clone of the branch (`git clone`), so nothing in the checkout was built. Bundle copy with the identifier `me.sesser.gus.debugtest` and its own preferences, a scratch `photobench` library (4 synthetic 6000 × 4000 DNGs and one copy of a real 20 MP RW2), `--library-root` on every launch (the debug-script runs and the few launches with `open`, which needs it the same way). `UPDATE_GOLDENS=1` was not run. The owner's library folder has no file newer than the start of this pass. **Another session's QA (PR #52) ran `swift-test`, `swift-build` and its own app copies on this Mac for most of this pass.** Functional checks are unaffected. AC9 and M13 were taken after it finished, from 12:15 to 12:49, under a one-second `ps` sampler listing any build, test, photobench or app process (`guard.sh`). What else ran is said at each figure. Rather than keep competing for the GPU, the timing runs stopped when the owner's `build/Gus.app` started at 12:48.

## Verdict

**Not ready to ship: AC7 fails on one regression for the engineer (Q1).** At 100% with machine learning noise reduction on, the caption's spinner stays on after the sharp frame has landed, until the next value change. Q2, a longer stall when arriving at a photo at 100%, also goes to the engineer. Every other criterion that can be checked here passes by test or script: AC1–AC3, AC5, AC6, AC8, AC9 (the restated speed target, Dell canvases), AC10–AC14, the Exposure and Highlights crossings of ruling 9, and every line of AC4 except one keyboard step. What's left for the owner is M1, a keyboard step and the items under "For a person" at the end. Below 100% and the maps behave as shipped.

The stall after letting go at 100% that RI-D1 asks about is real: 0.39 to 0.63 s after a commit on this branch (1.15 s with machine learning on), against 0.36 to 0.41 s on `develop`. It goes to the product manager with the figures below.

## Acceptance criteria

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 (R1, R12) | Test | `LiveRegionRendererTests`: `regionMatchesFullRender` (center and corner, uncropped and cropped-and-straightened), `onePixelDetailSurvives`, `rawRegionMatchesFullRender`. Default size and `LARGE_RENDER_TESTS=1` at 6000 × 4000: 12 of 12 pass. Worst difference 8 steps (center, uncropped), 2 (corner), 7 and 2 with the crop, raw 4; 0 of 24.4 million channel values over the tolerance. Read: `compare` checks every pixel of the region against the same area of the whole render, on `pixelGrid` (real one-pixel detail), so an enlarged frame or a shifted region fails, as code review's mutations also showed | Pass |
| AC2 (R1) | Script | `ac2`, `ac2-fit`. Frame-by-frame passes at 100%, 200% and 800% on the largest canvas: 27 / 60 / 86 frames with none soft, regions 4776 × 2893, 2388 × 1446, 598 × 362. At fit (magnification 0.268) and 50%: `covered no`, 24 and 22 whole-photo frames, no region, no decode label, as before. `LiveSessionTests` pass and the file is not in the diff | Pass |
| AC3 (R2) | Script | `ac3`. Three masks (linear, radial, brush) with Clarity at 100%, 4776 × 2893 region: an Amount drag (19 frames), mask Exposure (24) and mask Clarity (17) are sharp from the first frame, mean 288–354 ms | Pass |
| AC4 (R3) | Script; one line Person | Moving: `ac4-sliders` (13 sliders, each 44–46 frames, none soft after the first sharp); real mouse with the window key (`ac4-drags`: curve 24, wheel 30, mask handle 24, brush 24 frames, all sharp from the first; the handle moved from 0.5, 0.15 to 0.54, 0.198; each is 6 consecutive 9-event drags because `drag` posts 9 events). One-off (`ac4-oneoff`, `ac4-drags`): typed value, preset hover, look-up table hover, Show Original, red overlay and switching the overlay's mask each show a sharp frame of the current values (`tile shown`) once none is pending. Keyboard step on a slider: P9 | Pass; keyboard line Open |
| AC5 (R3, R12) | Test, Script | `originalMatchesFullRender`, worst 1 step. `ac4-oneoff` `original on`: tile shown; snapshot shows the unedited photo with the Original badge | Pass |
| AC6 (R4) | Script | `ac6`, `ac6-wb`, `rw2`. White Balance and Luminance held with no commit become sharp with no further input (WB 446 ms from the last input to a sharp frame of the applied values, Luminance 417 ms; a second WB drag 376 ms; RW2 482 and 480 ms; other QA running). Held frame against the frame after commit, content area, 12 million channel values: WB worst 3 steps, mean 0.036; Luminance worst 3, mean 0.035: R12 holds. Profile is a menu and commits on the first frame (R4's held state doesn't exist for it): sharp full rendition about 180 ms after, see RI-Q1 | Pass |
| AC7 (R5) | Script | `ac7`, `ml-spinner-100`, `ml-spinner-fit`, `q1`. The window keeps responding (main thread answered every 120 ms or less during the wait; the sharp frame landed about 2.4 s after the last input on the synthetic DNG), progress shows after the threshold (the spinner, 0.5 s after the wait begins), and the wait ends in a sharp frame, so the criterion's own clauses hold. But R5's "as it does today" and DR4 don't: the spinner does not go away once that sharp frame is on screen, and stays until the next value change: **Q1** | **Fail (Q1)** |
| AC8 (R6) | Script | `ac8`: snapshots at the start of a change, during a pan, during a zoom, a pan right after a commit and settled, each viewed. No empty area in any; blank check at most 1 of 960 blocks of 64 px one color (areas of flat color in the photo). Settled against held frame match: R12 as in AC6 | Pass |
| AC9 (R7) | Test (`photobench`) | `photobench viewport` with the Dell's two canvases, 60 frames per case, run with nothing else running (table below): all 8 typical-stack cases at or under 160 ms in the first run and the second. A third run was over on two 17.4 MP cases (163.7 and 164.3 ms); one re-run of those two cases gave 153.3 and 151.4 ms (that run overlapped a `swift-build` and the owner's app starting in its last 40 s; both can only slow it). No case over 160 ms twice | Pass |
| AC10 (R8) | Script; manual part Person | `ac10`, three masks, about 300 ms frames at 100%: rating keys `3` and `4` and next and previous photo all took effect while a frame was rendering. No spinning cursor during a real drag: P5 | Pass; manual part Open |
| AC11 (R9) | Script | `ac11`. At 100% after a pause the histogram hash is identical to the whole photo's at Fit with the same values, unchanged after two pans (region moved, hash the same). It holds through a drag and catches up on the pause (M7). Exact, no tolerance needed | Pass |
| AC12 (R10, R14) | Test | `GoldenTests` (4), no golden in the diff, `PreviewCacheKey.currentPipelineVersion` is 7 on the branch and on `develop` | Pass |
| AC13 (R11) | Script | `ac13` with a read-only watcher on the scratch catalog: one write during a 3.8 s drag (one stack hash change), one Undo restores the previous hash, Redo available | Pass |
| AC14 (R13) | Script | `ac14`: at 100% change Exposure, commit, go to fit at once: `previews hash` equals the saved hash, memory preview, disk preview and disk thumbnail all present; the snapshots at Fit and in the grid show the new edit. In the grid the printed `saved` is the closed editor's identity value; the preview key is the new hash | Pass |
| M1 (owner) | Person | P1 | Open |

**AC9's figures** (p95 ms, 60 frames per case; runs at 12:15, 12:21, 12:26 with nothing else running, the fourth at 12:46 overlapping a `swift-build` at its start and the owner's app in its last 40 s). The status.md figures are the engineer's earlier run.

| Case | status.md | Run 1 | Run 2 | Run 3 | Run 4 |
|---|---|---|---|---|---|
| 14.4 MP (4976 × 2892), Exposure | 139.5 | 144.87 | 143.61 | 144.30 | 144.29 |
| Amount | 146.7 | 144.19 | 145.10 | 145.82 | 136.83 |
| Saturation | 142.4 | 143.69 | 144.74 | 146.02 | 144.55 |
| Shadows | 147.4 | 140.24 | 142.30 | 141.18 | 141.14 |
| 17.4 MP (6000 × 2892), Exposure | 157.4 | 158.47 | 157.38 | 157.38 | 152.35 |
| Amount | 157.4 | 157.50 | 157.05 | **163.71** | 153.27 |
| Saturation | 159.2 | 157.05 | 156.81 | **164.34** | 151.44 |
| Shadows | 152.9 | 157.52 | 153.63 | 159.45 | 149.05 |
| Three masks, first / last moves, 14.4 MP (no target) | 288.6 / 279.2 | 245.6 / 249.0 | 246.2 / 251.6 | 255.7 / 261.1 | 372.6 / 250.5 |
| Three masks, 17.4 MP (no target) | 415.6 / 436.1 | 398.6 / 400.2 | 400.4 / 398.7 | 397.4 / 393.4 | 475.1 / 494.5 |

**Frame-by-frame, as recorded (rule applied to `interactive` lines, per C17).** No sharp frame took longer than the 2.5 s timeout to arrive, and no run of soft frames broke the rule (`frames.py`).

| Case | First frame sharp? | Soft frames after the first sharp (allowed runs) |
|---|---|---|
| Amount at 100%, 200%, 800%, largest canvas | Yes | 0 |
| A drag right after `Z`, texture not ready (`wiggle`) | 2 soft frames, 82 ms, then sharp | 0 |
| Exposure 0.5 to −0.5, default stack, DNG (`crossing`) | Yes | 6 (`settling`, 5 `running`), 118 ms |
| Exposure −0.5 to 0.5 | Yes | 3, 95 ms |
| Highlights 20 to −20 | Yes | 5, 104 ms |
| Highlights −20 to 20 | Yes | 5, 115 ms |
| Highlights 0 to −30, first drag | 5 soft before the first sharp (106 ms), then sharp | 0 |
| Exposure crossing 0 on the real RW2 (`rw2`) | Yes | 3, 233 ms |
| Highlights crossing 0 on the RW2 | Yes | 3 `running`, 113 ms |
| Six crossings back and forth with no pause (`wiggle`) | Yes | Each run 3 to 5, one `settling`, then `running` |
| First mask added then its slider dragged (`c4`) | Yes | 4, 222 ms |

**Design checks.** DR1 and DR9 are reading and tests (both pass: `LocalizationTests` 3, `BrandingTests` 7, the hints and guide paragraph as written, "100%" in the keys table, no internal terms). The rest:

| Check | What the script showed | Left for a person |
|---|---|---|
| DR2 / M2 soft looks soft | `m2` at 400%: `nearest false` on a soft frame and at the White Balance hold, `nearest true` on a settled photo and on the maps. Crops of a real edge in the snapshots: the soft frame is a smooth ramp about 30 pixels wide with no stair-steps; the held sharp frame and the settled frame show the same hard edge of real pixels | P4: the look of a drag on a real photo |
| DR3 / M3 spinner | `m3`, `m3b`: no spinner during Amount or WB drags, on arrival at photos at 100%, or on `Z` from Fit (masked photo, ML photo). A WB hold on a masked photo: spinner at 526 ms after the last input, gone when the sharp frame lands | P6: tooltip, look |
| DR4 / M4 machine learning | One spinner with its label, window responds. **Spinner doesn't end: Q1** | P3 after Q1 is fixed |
| DR5 / M5 swap | Not scriptable | P5 |
| DR6 / M6 the boundary | `m6`: `Z` and ⌘= (`zoomstep`): covered. 97%: `covered no`, soft frames. 99.5% (a pinch's rounding): `covered yes`, sharp frames | P6: pinch, trap |
| DR7 / M7 histogram and curve | `ac11`: hold during a drag, catch up on a pause, a pan leaves it, Fit stays live | P4: curve backdrop, never blank |
| DR8 / M8 VoiceOver | `m12`: `print announcement` prints none at the swap, `accessibility AXImage` shows the image and its actions | P8 |
| M1 R4 while moving | `ac6`, `rw2`: `tile none` while the value moves, sharp on the hold, `tile none` again when it resumes; Luminance and WB; Profile is a menu | P1 |
| M9 the Dell | Frame times in AC9 | P2 |
| M10 HDR | Not run: no HDR photo in the scratch library, and `system_profiler` reports no HDR mode for the Dell here | P10 |
| M11 maps | `m11`: map at 100% and 400% `nearest true`, the photo's tile comes down, a pan renders nothing and doesn't restart the refinement (C15). Fringe map and replaced slot not run | P7 |
| M12 handles | `m12`: `layers tile,view` after a window resize and after review; snapshot shows the mask's handles over the tile. Brush cursor not checked | P7 |
| M13 after letting go | `m13a`, `m13ml`, `m13b`. No blank at any moment. After White Balance the soft frame stays about 0.93 s; after Amount the sharp frame stays until the full rendition replaces it. A key or pan within a second both work. The window stalls 0.39–0.63 s, 1.15 s with machine learning on: figures under RI-D1 | P5: spinning cursor, how it feels |

## Findings

**Q1 (Medium). At 100% with machine learning noise reduction on, the caption's spinner stays on after the sharp frame has landed.**
Steps: raw at 100%, machine learning on (macOS 27). Drag Luminance and hold still with the control held.
Expected: the machine learning spinner shows while the wait lasts and goes when the sharp frame is on screen (R5, "as it does today"; design §2 "A machine learning wait", MLD §6; M4).
Actual: the sharp frame of the applied values lands about 2.4 s after the last input (`print viewport`: `tile shown … applied`, `spinner no`), but `print ml` keeps `spinner true` indefinitely: in `ac7` it was still true 32 s after the frame landed and after the commit; in `ml-spinner-100` true for all 8 s watched. The caption's spinner is visible in the snapshot (`q1`), right end of the caption, 5 s after the frame landed. It goes on the next value change that lands a frame (Amount, say) or when machine learning is turned off. At Fit (`ml-spinner-fit`) the spinner does not stick, and on `develop` a whole frame always lands for the awaited values. This is a regression of this branch.
Likely cause (from reading the code, not proven): the pause's refinement calls `requestRender`, which starts the machine learning wait, then the render loop finds the frame already on screen (`current` in the region branch, and the whole-frame check after it) and `continue`s, so no frame lands to end the wait. Rerun with `q1` once fixed.

**Q2 (Medium). Arriving at a photo at 100% stalls the main thread longer than on `develop`.**
Steps: `arrive-branch` and `arrive-develop`, the largest window, a typical stack on two photos, at 100%, arrow to the next photo and back twice with a 20 ms heartbeat, nothing else running (one run per build, the branch first).
Expected: arriving at a photo at 100% loads as today (design §2.1) and the window keeps responding (R8).
Actual (longest heartbeat gaps after the arrow key): branch 239 + 374 ms and 590 ms, 230 + 377 ms and 591 ms; `develop` none over 22 ms one way and 383 and 390 ms the other. So each arrow key at 100% on this branch costs about 0.2 to 0.6 s more of main-thread stall than on `develop`.
Not profiled: `sample` on the main thread during `key right` is the next step, and it may be the same deferred first draw as RI-D1. Culling at 100% is a normal way of working, so if this can't be brought down cheaply it should come back as a Requirements issue rather than ship unnoticed.

## Requirements issues and design questions

**RI-D1 (the designer's, for the product manager): M13's figures.** Measured on a quiet Mac (`ps` sampler empty for each run), window 3008 × 1662, typical stack, 4776 × 2893 region at 100%, one run per row. Each row is a 20 ms main-thread heartbeat straight after letting go. The soft frame's time is "after the full rendition's `awaitsFull` clears".

| After letting go with no pause | Picture until the full rendition | Longest main-thread stall |
|---|---|---|
| White Balance | Soft frame, about 0.93 s | 527 ms |
| Amount | Sharp frame stays; full rendition replaces it at 0.82 s | 391 ms |
| White Balance, then a pan | Soft frame, about 0.93 s | 498 ms |
| Amount, then an arrow key within 0.4 s | Key handled; moved to the next photo | gaps up to 252 ms, then the arrival stall (Q2) |
| Machine learning on, Amount | Sharp frame stays; full rendition at 1.25 s | 1152 ms |
| Machine learning on, White Balance | Soft; sharp spinner at 534 ms; not yet landed after the 864 ms watched | none over 37 ms |

A commit's stall is on `develop` too, but it is longer on this branch. Same commands, both builds, longest heartbeat gap in the 1.7 s after each commit:

| Commit at 100% | `develop` | Branch |
|---|---|---|
| Amount (2 commits) | 385, 360 ms | 429, 411 ms |
| White Balance (2 commits) | 407, 400 ms | 622, 634 ms |

By the code this is the full rendition's first draw on the main thread (the deferred read in RI-D1); it was not profiled here, and what adds the time on this branch is not known. One run per build per row, so read the comparison as indicative. A spinning cursor normally needs a longer freeze than these, so none is expected; P5 confirms it on the owner's own files. No spinner is shown (L1).

**RI-Q1 (for the product manager). AC6 and Profile.** AC6 asks for "a scripted change with no commit and then a pause" for White Balance, Profile and Luminance. Profile is a menu in the app and commits on the first change, so its held state doesn't exist. QA checked what exists: after the commit the full rendition lands about 180 ms later and matches R12. Suggested: restate AC6 for Profile as "after the change is saved". No code change needed.

No design questions.

## Scripts

Setup, verbatim (zsh). `$SCRATCH` is this session's scratch folder; `ts.py` adds each line's milliseconds since start and `frames.py` applies the frame-by-frame rule (`status.md`, interactive lines only).

```zsh
QA=$SCRATCH/qa
git clone --branch feature/viewport-render-1to1 <checkout> $SCRATCH/branch
cd $SCRATCH/branch && Scripts/build-app.sh && swift build -c release --product photobench
.build/release/photobench generate --output $QA/photos/dng --dng 4 --jpeg 0 --heic 0 --pairs 0 --videos 0 --per-folder 4
.build/release/photobench import --library-root $QA/lib --source $QA/photos/dng
cp "<a real .RW2>" $QA/photos/rw2/                         # a copy; the original was only read
.build/release/photobench import --library-root $QA/lib --source $QA/photos/rw2
cp -R build/Gus.app $QA/app/Gus-QA.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $QA/app/Gus-QA.app/Contents/Info.plist
codesign --force --deep --sign - $QA/app/Gus-QA.app

# Each run; a develop copy (me.sesser.gus.debugtest.dev, a `git clone --branch develop`) was built the same way for the two develop comparisons.
$QA/app/Gus-QA.app/Contents/MacOS/Gus --library-root $QA/lib --debug-script "<script>; quit" | python3 -u $QA/ts.py > $QA/logs/<name>.log

# Fragments used below:
OPEN_LOUPE="wait 2; loupe; wait 1"
TYPICAL="adjust exposure 0.4; adjust contrast 15; adjust highlights -30; adjust shadows 25; adjust whites 10; adjust blacks -5; adjust clarity 20; adjust dehaze 10; adjust vibrance 15; adjust saturation 5; adjust curve rgb 0,0 0.3,0.25 0.7,0.78 1,1; adjust grade shadows 210 20; adjust grade highlights 40 15; adjust amount 40; adjust radius 1; adjust detail 25; adjust masking 20"
MASK="adjust mask set exposure 0.5; adjust mask set contrast 20; adjust mask set clarity 30"
POLL<n>="print viewport; wait 0.03" (or 0.05), repeated n times
```

Tests (scratch tree, with `swift test` outputs 646 tests in 109 suites, 1 known issue, the existing `LiveSessionTests` one):

```zsh
swift test
LARGE_RENDER_TESTS=1 swift test --skip-build --filter LiveRegionRendererTests
swift test --skip-build --filter GoldenTests      # also: LiveSessionTests, LocalizationTests, BrandingTests
```

Debug scripts (each ends `; quit`, omitted here):

`ac2`: `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 3008 1662; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 3; print loupe; print viewport; print frames; adjust scrub amount 40 90 240 16; wait 3; print frames; print viewport; print adjustments; zoomstep; wait 2; print loupe; print viewport; print frames; adjust scrub amount 90 40 240 16; wait 3; print frames; print viewport; zoomstep; wait 2; zoomstep; wait 2; print loupe; print viewport; print frames; adjust scrub amount 40 90 240 16; wait 3; print frames; print viewport; print adjustments`. Each zoom passes the check; see the table.

`ac2-fit`: `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 1500 800; wait 1; print loupe; print viewport; print frames; adjust scrub amount 40 90 100 16; wait 2; print loupe; print frames; print viewport; zoomstep; wait 2; print loupe; print viewport; print frames; adjust scrub amount 90 40 100 16; wait 2; print frames; print viewport; zoomstep; wait 2; print loupe; print viewport; print frames; adjust scrub amount 40 90 200 16; wait 2; print frames; print viewport`. Fit and 50%: soft whole frames (`covered no`), as before; 100%: 65 sharp frames.

`ac3`: `$OPEN_LOUPE; focus RAW_00002; ml ready; windowsize 3008 1662; wait 1; adjust reset all; adjust exposure 0.3; adjust contrast 15; adjust highlights -30; adjust shadows 25; adjust clarity 15; adjust vibrance 20; adjust amount 40; adjust mask add linear; $MASK; adjust mask add radial; $MASK; adjust mask add brush; adjust mask brush 0.1 0.1 0.3 0.3 0.5 0.4 0.7 0.6 0.9 0.8; $MASK; wait 4; print adjustments; zoom; wait 3; print viewport; print frames; adjust scrub amount 40 90 400 16; wait 3; print frames; print viewport; adjust mask select 0; adjust scrub mask:exposure 0.5 1.5 400 16; wait 3; print frames; print viewport; adjust mask select 2; adjust scrub mask:clarity 30 60 300 16; wait 3; print frames; print viewport`. Passes.

`crossing`: `$OPEN_LOUPE; focus RAW_00003; ml ready; windowsize 3008 1662; wait 1; adjust reset all; wait 3; zoom; wait 3; print frames; adjust exposure 0.5; wait 2; print frames; adjust scrub exposure 0.5 -0.5 300 16; wait 3; print frames; print viewport; adjust scrub exposure -0.5 0.5 300 16; wait 3; print frames; print viewport; adjust reset all; wait 3; print frames; adjust highlights 20; wait 2; print frames; adjust scrub highlights 20 -20 300 16; wait 3; print frames; print viewport; adjust scrub highlights -20 20 300 16; wait 3; print frames; print viewport; adjust reset all; wait 2; print frames; adjust scrub highlights 0 -30 300 16; wait 3; print frames; print viewport; adjust reset all; wait 2`. Soft runs as in the table.

`wiggle` (first part): `$OPEN_LOUPE; focus RAW_00003; ml ready; windowsize 1900 1000; wait 1; adjust reset all; wait 2; adjust exposure 0.2; wait 2; zoom; wait 3; print frames; adjust scrub exposure 0.2 -0.2 25 16 hold; adjust scrub exposure -0.2 0.2 25 16 hold; adjust scrub exposure 0.2 -0.2 25 16 hold; adjust scrub exposure -0.2 0.2 25 16 hold; adjust scrub exposure 0.2 -0.2 25 16 hold; adjust scrub exposure -0.2 0.2 25 16; wait 3; print frames; print viewport; adjust reset all; wait 1; zoom; wait 2; adjust exposure 0.4; adjust amount 40; wait 2; print frames; zoom; adjust scrub amount 40 90 200 16; wait 3; print frames; print viewport`. Then its last block (`zoom; wait 2; zoomstep; zoomstep; adjust scrub amount 90 50 200 16`) ended at 50%, so it is `covered no` and all soft, which is correct.

`ac4-sliders` (one line per slider, in turn: radius 1 2, detail 25 60, masking 20 40, contrast 15 40, shadows 25 50, whites 10 30, blacks -5 -30, clarity 20 40, dehaze 10 30, vibrance 15 40, saturation 5 30, vignette 0 -40, grain 0 30): `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 3; print frames; adjust scrub <name> <from> <to> 160 16; wait 1.2; print frames; …; print viewport`. All pass.

`ac4-oneoff`: `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 2; zoom; wait 3; print frames; editvalue Amount; text 55; key return; wait 1.5; print frames; print viewport; adjust amount 70; wait 1; preset save QAHover; adjust amount 40; wait 2; print frames; preset preview QAHover; wait 1.5; print frames; print viewport; preset previewend; wait 2; print frames; print viewport; original on; wait 2; print frames; print viewport; snapshot …; original off; wait 2; print frames; print viewport; snapshot …; adjust mask add radial; adjust mask set exposure 1; wait 2; print frames; adjust mask add linear; adjust mask set exposure 0.5; wait 2; adjust mask overlay on; wait 2; print frames; print viewport; adjust mask select 0; wait 2; print frames; print viewport; adjust mask overlay off; wait 2; print frames; print viewport`. Each ends on a sharp frame of the current values.

`ac4-drags` (launched with `open -W -n --stdout … <copy> --args --library-root … --debug-script …`, so the window is key; recon runs located the curve, the wheels and the look-up table menu): `wait 2; loupe; wait 1; focus RAW_00001; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; adjust mask add linear; adjust mask set exposure 0.5; wait 2; zoom; wait 3; print responder; print frames; scroll 640; wait 0.4; drag 1750 540 1750 500; wait 0.25; drag 1750 500 1750 540; wait 0.25; drag 1750 540 1750 505; wait 0.25; drag 1750 505 1750 545; wait 0.25; drag 1750 545 1750 510; wait 0.25; drag 1750 510 1750 550; wait 0.25; wait 2; print frames; print viewport; scroll 1000; wait 0.4; drag 1750 620 1762 600; wait 0.25; drag 1750 600 1762 620; wait 0.25; drag 1750 620 1762 604; wait 0.25; drag 1750 604 1762 624; wait 0.25; drag 1750 624 1762 608; wait 0.25; drag 1750 608 1762 628; wait 0.25; wait 2; print frames; print viewport; pan 0 400; wait 1; hit 960 144; print adjustments; print frames; drag 960 144 980 160; wait 0.25; drag 980 160 1000 176; wait 0.25; drag 1000 176 1020 192; wait 0.25; drag 1020 192 1040 208; wait 0.25; drag 1040 208 1060 224; wait 0.25; drag 1060 224 1080 240; wait 0.25; wait 2; print frames; print viewport; print adjustments; pan 0 -400; wait 1; adjust mask add brush; adjust mask brush 0.40 0.40 0.41 0.41; wait 1; print frames; drag 800 400 900 460; wait 0.25; drag 900 400 1000 460; wait 0.25; drag 1000 400 1100 460; wait 0.25; drag 1100 400 1200 460; wait 0.25; drag 1200 400 1300 460; wait 0.25; drag 1300 400 1400 460; wait 0.25; wait 2; print frames; print viewport; scroll bottom; wait 0.5; menuhover 1727 591 Built-in/Warm; print frames; print viewport; menuhover end; wait 2; print frames; print viewport; adjust reset all; wait 1`. As in AC4.

`ac6`: `$OPEN_LOUPE; focus RAW_00004; ml ready; windowsize 1900 1000; wait 1; adjust reset all; wait 1; adjust temperature 5500; wait 2; zoom; wait 3; print frames; print viewport; adjust scrub temperature 5500 6200 100 16 hold; print viewport; $POLL30; print frames; snapshot …; adjust scrub temperature 6200 6900 100 16 hold; print viewport; $POLL30; print frames; adjust scrub temperature 6900 6900 1 16; wait 3; print viewport; print frames; snapshot …; adjust reset all; wait 2; print frames; adjust scrub luminance-nr 0 40 100 16 hold; print viewport; $POLL30; print frames; snapshot …; adjust scrub luminance-nr 40 40 1 16; wait 3; print viewport; print frames; snapshot …; adjust reset all; wait 2; print frames; print viewport; adjust look neutral; print viewport; $POLL30; print frames; print viewport; adjust look standard; wait 2; print frames`.

`ac6-wb` (the match for AC6, held vs settled at the same value): `$OPEN_LOUPE; focus RAW_00004; ml ready; windowsize 1900 1000; wait 1; adjust reset all; wait 1; adjust temperature 5500; wait 2; zoom; wait 3; adjust scrub temperature 5500 6200 80 16 hold; wait 1.5; print viewport; snapshot held; adjust scrub temperature 6200 6200 1 16; wait 3; print viewport; snapshot settled; adjust reset all; wait 2`. Snapshot pairs compared in the content area with a scratch Swift tool: worst 3 steps.

`ac7` and `ml-spinner-100`/`ml-spinner-fit`/`q1`: as `ac6`, on RAW_00004 with `ml on` first, plus `print ml`; `q1`: `$OPEN_LOUPE; focus RAW_00004; ml ready; windowsize 1900 1000; wait 1; adjust reset all; wait 1; zoom; wait 3; ml on; wait 3; adjust scrub luminance-nr 20 60 40 16 hold; wait 5; print ml; print viewport; snapshot …; wait 6; print ml; adjust scrub luminance-nr 60 60 1 16; wait 4; print ml; print viewport; ml off; wait 1; adjust reset all; wait 1`. Sharp frame on screen, spinner on: Q1.

`ac8`: `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 2; zoom; wait 3; print viewport; adjust scrub amount 40 60 20 16 hold; snapshot …; print viewport; adjust scrub amount 60 60 1 16; wait 3; print viewport; pan 500 200; snapshot …; print viewport; wait 2; zoomstep; wait 0.04; snapshot …; print viewport; wait 2; zoomstep out; wait 2.5; adjust scrub amount 60 80 20 16; pan -400 -300; snapshot …; print viewport; wait 4; print viewport; snapshot …`. No empty areas.

`ac10`: `$OPEN_LOUPE; focus RAW_00002; ml ready; windowsize 3008 1662; wait 1; adjust reset all; adjust exposure 0.3; adjust contrast 15; adjust highlights -30; adjust shadows 25; adjust clarity 15; adjust vibrance 20; adjust amount 40; adjust mask add linear; $MASK; adjust mask add radial; $MASK; adjust mask add brush; adjust mask brush 0.1 0.1 0.3 0.3 0.5 0.4; $MASK; wait 3; zoom; wait 3; print frames; print items; adjust scrub amount 40 60 30 16 hold; key 3; print items; adjust scrub amount 60 70 20 16 hold; key 4; print items; adjust scrub amount 70 75 15 16 hold; print frames; print selection; key right; print selection; print items; wait 2; print viewport; print frames; key left; wait 1; print selection; key 0; adjust reset all; wait 1`.

`ac11`: `$OPEN_LOUPE; focus RAW_00002; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 3; print loupe; print viewport; zoom; wait 3; print loupe; print viewport; adjust scrub amount 40 70 40 16 hold; wait 1.2; print viewport; adjust scrub amount 70 40 40 16 hold; wait 1.2; print viewport; adjust scrub amount 40 40 1 16; wait 2; print viewport; pan 1400 300; wait 1.5; print viewport; pan -900 -600; wait 1.5; print viewport; adjust scrub exposure 0.4 1.0 60 16 hold; print viewport; wait 1.2; print viewport; adjust scrub exposure 1.0 0.4 60 16 hold; wait 1.2; print viewport; adjust scrub exposure 0.4 0.4 1 16; wait 2; print viewport; adjust scrub saturation 5 30 80 16 hold; print viewport; adjust scrub saturation 30 5 80 16; wait 0.05; print viewport; wait 2.5; print viewport`.

`ac13` (the catalog watcher, a scratch `sqlite3` read-only poll of `pragma data_version` and the version's `editStackHash`, ran beside it): `$OPEN_LOUPE; focus RAW_00003; ml ready; windowsize 1900 1000; wait 1; adjust reset all; wait 1; adjust amount 40; wait 2; zoom; wait 2.5; print adjustments; adjust scrub amount 40 90 240 16; wait 2; print adjustments; print undo; undo; wait 2; print adjustments; print undo; print frames`. The watcher saw 3 stack changes: the `adjust amount 40`, the drag's one commit, the undo.

`ac14`: `$OPEN_LOUPE; focus RAW_00003; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 3; print viewport; print previews; snapshot …; adjust scrub exposure 0.4 1.2 80 16; zoom; wait 3.5; print loupe; print viewport; print previews; snapshot …; print adjustments; grid; wait 2; print previews; snapshot …`.

`m3`: `$OPEN_LOUPE; focus RAW_00002; ml ready; windowsize 1900 1000; wait 1; adjust reset all; adjust exposure 0.3; adjust contrast 15; adjust clarity 15; adjust amount 40; adjust mask add linear; $MASK; adjust mask add radial; $MASK; adjust mask add brush; adjust mask brush 0.1 0.1 0.3 0.3 0.5 0.4; $MASK; wait 3; zoom; wait 3; print viewport; adjust scrub amount 40 60 30 16 hold; print viewport; wait 0.3; print viewport; adjust scrub amount 60 40 30 16; wait 2; print viewport; adjust scrub temperature 5000 6500 40 16 hold; print viewport; $POLL40; print frames; adjust scrub temperature 6500 5500 40 16; wait 2; print viewport; print frames; key right; wait 0.25; print viewport; wait 0.45; print viewport; (then left, right, left, right the same way); zoom; wait 2; print viewport; zoom; wait 0.3; print viewport; wait 0.5; print viewport; wait 2; print viewport`.

`m3b`: `$OPEN_LOUPE; focus RAW_00004; ml ready; windowsize 1900 1000; wait 1; adjust reset all; ml on; wait 2; print ml; print viewport; zoom; wait 0.1; $POLL20 at 0.1 s; ml off; wait 1; adjust reset all; wait 1`.

`m6`: `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 2; zoom; wait 2.5; print loupe; print viewport; print frames; optionscroll 900 500 -0.203; wait 1; print loupe; print viewport; print frames; adjust scrub amount 40 50 40 16; wait 1.5; print frames; print viewport; optionscroll 900 500 0.1696; wait 1; print loupe; print viewport; print frames; adjust scrub amount 50 60 40 16; wait 1.5; print frames; print viewport; print viewport; zoom; wait 2; zoomstep; wait 1.5; print loupe; zoomstep; wait 1.5; print loupe; print viewport`.

`m11`: `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 3; adjust scrub amount 40 45 10 16 hold; wait 1; print viewport; sharpenmap on; wait 3; print viewport; print sharpenmap; zoomstep; wait 2; zoomstep; wait 2; print loupe; print viewport; pan 200 100; wait 0.6; pan 100 50; wait 1; print viewport; adjust scrub masking 20 30 10 16 hold; wait 1.5; print frames; print viewport; adjust scrub masking 30 30 1 16; wait 2; sharpenmap off; wait 2; print viewport; zoomstep out; wait 1; zoomstep out; wait 2; print loupe; print viewport`.

`m12`: `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; adjust mask add radial; adjust mask set exposure 0.5; wait 2; zoom; wait 3; adjust scrub amount 40 60 15 16 hold; wait 0.7; print viewport; snapshot …; windowsize 1700 950; wait 1; print viewport; snapshot …; review on; wait 0.3; print review; review off; wait 1.2; print review; adjust scrub amount 60 62 3 16 hold; wait 0.7; print viewport; snapshot …; adjust scrub amount 62 62 1 16; wait 2; accessibility AXImage; print announcement`. Also compared: leaving review at 100% moves the view (to x 0) on `develop` too (`review-branch`, `review-dev`), so not a finding.

`m2`: `$OPEN_LOUPE; focus RAW_00004; ml ready; windowsize 1900 1000; wait 1; adjust reset all; wait 1; adjust temperature 5500; wait 2; zoom; wait 2.5; zoomstep; wait 1.5; zoomstep; wait 2; print loupe; print viewport; snapshot …; adjust scrub temperature 5500 6200 60 16 hold; print viewport; snapshot …; wait 1.5; print viewport; snapshot …; adjust scrub temperature 6200 6200 1 16; wait 3; pan 240 120; snapshot …; print viewport; wait 2.5; print viewport`.

`rw2` (on the copy of the real RW2, 3648 × 5472): `$OPEN_LOUPE; focus P1040071; ml ready; print adjustments; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 4; print loupe; print viewport; print frames; adjust scrub amount 40 90 200 16; wait 3; print frames; print viewport; adjust exposure 0.2; wait 2; adjust highlights 0; wait 2.5; print frames; adjust scrub exposure 0.5 -0.5 240 16; wait 3; print frames; print viewport; adjust reset all; wait 2.5; print frames; adjust highlights 20; wait 2.5; print frames; adjust scrub highlights 20 -20 240 16; wait 3; print frames; print viewport; adjust reset all; wait 2.5; print frames; adjust scrub temperature 4500 6500 100 16 hold; print viewport; $POLL30; print frames; adjust scrub temperature 6500 6500 1 16; wait 3; print viewport; adjust reset all; adjust scrub luminance-nr 0 40 100 16 hold; print viewport; $POLL30; print frames; adjust reset all; wait 2`.

`c4`: `$OPEN_LOUPE; focus RAW_00003; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 2; zoom; wait 3; print frames; original on; wait 1.5; original off; wait 1; print frames; adjust scrub amount 40 70 160 16; wait 2.5; print frames; print viewport; adjust mask add linear; adjust scrub mask:exposure 0 1 160 16; wait 2.5; print frames; print viewport; adjust reset all; wait 2; print frames; adjust mask add linear; adjust scrub mask:exposure 0 1 160 16; wait 3; print frames; print viewport; adjust reset all; wait 1`. Sharp after Show Original; first mask's decode is an allowed run.

Timings, under `guard.sh` (one `ps` a second, flagging only other build, test, photobench and app processes):

```zsh
.build/release/photobench viewport --windows 4976x2892,6000x2892 --frames 60 --json $QA/ac9-c<n>.json
```

`m13a` (HB40 is `print viewport; wait 0.02` repeated 40 times, HB6 and HB30 the same): `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 3008 1662; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 4; adjust scrub temperature 5000 6500 60 16; $HB40 wait 3; print frames; adjust scrub amount 40 60 60 16; $HB40 wait 3; print frames; adjust scrub temperature 6500 5600 60 16; pan 300 100; $HB40 wait 3; print frames; adjust scrub amount 60 40 60 16; $HB6 key right; wait 0.1; print selection; $HB30 key left; wait 3; print selection; print frames; adjust reset all; wait 1`.

`m13ml`: `$OPEN_LOUPE; focus RAW_00004; ml ready; windowsize 3008 1662; wait 1; adjust reset all; wait 1; zoom; wait 3; ml on; wait 4; adjust scrub temperature 5000 6500 60 16; $HB40 wait 4; print frames; adjust scrub amount 40 60 60 16; $HB40 wait 4; print frames; ml off; wait 1; adjust reset all; wait 1`.

`m13b` on both builds (HBL60 is `print loupe; wait 0.02` repeated 60 times): `$OPEN_LOUPE; focus RAW_00002; ml ready; windowsize 3008 1662; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 4; adjust amount 55; $HBL60 wait 3; adjust temperature 6000; $HBL60 wait 3; adjust temperature 5500; $HBL60 wait 3; adjust amount 45; $HBL60 wait 3; adjust reset all; wait 1`.

`arrive` on both builds: `$OPEN_LOUPE; focus RAW_00002; ml ready; windowsize 3008 1662; wait 1; adjust reset all; $TYPICAL; wait 3; focus RAW_00001; ml ready; adjust reset all; $TYPICAL; wait 3; zoom; wait 4; key right; $HBL60 wait 3; key left; $HBL60 wait 3; key right; $HBL60 wait 3; key left; $HBL60 wait 2; adjust reset all; focus RAW_00002; ml ready; adjust reset all; wait 1`.

## For a person

Each needs the bundled app on a real raw. Copy the bundle and pass `--library-root <a scratch library>` (or use your own library copy) so edits don't touch your catalog. In order of what matters most.

**P1. Detail while dragging (owner's M1; covers design M1).** On a real 24 MP raw at 100% (`Z`), drag Sharpening's Amount, Radius and Detail, watching a fine edge, then Noise Reduction's Luminance. *Look at:* whether the edge changes in real pixels as you drag. For Luminance, hold still with the mouse down and see the detail arrive without letting go. Drag again and check the picture follows softly and never freezes or snaps back to older values. *Pass:* detail is judged while moving for Amount, Radius and Detail; the settled image after letting go looks the same as the last sharp frame.

**P2. The frame rate on the Dell (M9).** Window maximized, sidebar and inspector showing, a typical stack, at 100%. Drag Amount across its range, and paint a brush stroke. *Pass:* an Amount drag reads as continuous at 6 to 7 frames a second, no spinner at the end of the drag, the stroke stays attached to the pointer. If not, that is the follow-up already in `status.md` ("faster region frames"), not a defect here.

**P3. Machine learning at 100% (M4, after Q1 is fixed; macOS 27).** With machine learning on, drag Luminance and hold. *Pass:* one spinner with its machine learning label while the wait lasts, the last frame stays, the window responds, and the spinner goes when the sharp frame lands. (Q1 is the failure to confirm fixed.)

**P4. The look of soft frames, the histogram and the curve (M2, M7).** At 100% and 400%, drag White Balance, and pan right after. *Pass:* no stair-stepped blocks on the soft frame; at 400% a settled photo shows real pixels as blocks. During a drag at 100% the histogram and curve backdrop hold, never blank or dim, and catch up on a pause; a pan leaves them alone; at Fit they stay live.

**P5. After letting go, and the swap (M5, M13, N2, AC10).** At 100% on a real raw: let go of White Balance with no pause and press an arrow key or try to pan within a second; then the same after Amount; then with machine learning on. *Look at:* the photo is never blank; after Amount the sharp frame stays until the full rendition replaces it; no fade and no shift at the swap, soft to sharp and back, with Reduce Motion on and off; a fine edge doesn't move near the center or a corner. *Pass:* no spinning cursor appears after letting go or during a real drag with three masks; a stall of a few tenths of a second after letting go is what was measured (under RI-D1), but report if it's objectionable. Also: does the start of the first drag on a photo read as a blink (N2)?

**P6. The 100% boundary and the spinner (M3, M6).** Reach 100% by `Z`, by the toolbar, ⌘=, and a pinch that selects the 100% segment: real pixels each time. A pinch that stops just below 100% is soft: say whether that's a trap. Hold White Balance still: the spinner, if it shows, is labeled "Refining the photo". After letting go with no pause no spinner shows; that's expected (L1), not a failure.

**P7. Maps and handles (M11, M12).** At 400% a refined Sharpening Map, a Fringe Map and the preview while replacing a pick show blocks, as on `develop`. At 100% with a linear or radial mask selected, handles stay over the sharp frame during and after a drag, after resizing the window and after entering and leaving review, and the brush cursor too.

**P8. VoiceOver (M8).** At the swap from soft to sharp nothing is announced; a slider speaks its value; the spinner reads its label.

**P9. Keyboard step on a slider (AC4).** Focus a slider with the keyboard and step it with the arrow keys at 100%. Each step ends on a sharp frame of the current value.

**P10. HDR, if you have an extended-range display (M10).** An HDR photo at 100%: no HDR badge during a drag; it returns when the HDR rendition lands; after that a rating key doesn't bring a standard-range tile back. Not run here: no HDR photo in the scratch library, and the Dell reports no HDR mode.

## Could not run

- A real 24 MP camera raw at 100% in the owner's hands (P1); a real 20 MP RW2 copy was run instead for the frame-by-frame checks.
- Keyboard step on a slider (P9); pinch (P6); how soft frames and frame rate feel (P1, P2, P4, P5).
- Machine learning on a real raw (P3); only the synthetic DNG on macOS 27.
- An HDR photo or an extended-range display (M10, P10). VoiceOver speech (P8).
- The fringe map and the replaced fringe slot preview (M11, P7); the brush cursor (M12, P7).
- A second AC9 re-run and more M13 repeats: the owner's app started at 12:48, so timing stopped there.

## Follow-up

- **Q1: Fixed** on `bug/viewport-render-qa-findings` (spinner ends when the sharp frame lands). **Q2: Withdrawn**, not a regression. My arrival comparison ran the builds with different saved inspector states, and with the state pinned the feature matches the baseline. See [`../viewport-render-qa-findings/qa.md`](../viewport-render-qa-findings/qa.md).
- **Arrival figure corrected.** Q2's "`develop` none over 22 ms one way" (the "0" in "0–390 ms") was a measurement artifact: those scripts had no heartbeat before the arrow key, so a stall inside the key command's 80 ms sleep went unseen. Measured properly, `013c0e8` stalls about 380 ms on every arrival with the inspector hidden and about 610 ms with it open on Adjust, the same as the feature. The 590–613 ms branch figures were taken with the inspector open on Adjust.
- 2026-11-09: this list's owner checks P1–P10 were done at the sign-off of `bug/viewport-render-qa-findings` at `32083ae`, carried over and renumbered in that branch's `qa.md` (each item there says which P it was here). Nothing is left open.
