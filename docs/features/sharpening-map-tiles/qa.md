# Sharpening map tiles: QA

Owner: qa-tester. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`.
Tested: `bug/sharpening-map-tiles` at a452c86 (base `develop` at dfa0d5c), on a
Mac16,8, macOS 27.2 (26B123), app linked with the macOS 27.2 SDK (`vtool -show-build`),
on a 6016 × 3384 main display. Bug fix: the criteria are the **Bug** section of
`status.md`. Code review closed (C1–C5 fixed; C6 goes with Follow-up 2). No design
review, because the UI did not change, so no M-numbers exist for this bug.

Everything scripted ran against a copy of the bundle with its own bundle
identifier and a scratch library, built from `develop` at dfa0d5c (in a scratch
tree) and from the branch. Only QA's own copy of the RW2 was imported.

## Verdict

**Passes.** The bug shows in the bundled app on `develop` (40 of 124 snapshots
had whole wrong cells, at Fit and at 100%, on first refinements and after
Masking moves) and is gone on the branch (0 of 123 snapshots; within each script,
every Masking value gave one identical map across all launches). Both regression checks fail on
`develop` and pass on the branch, `swift test` is green, CI is green on the head
commit, and no golden or pipeline version moved. One person's check (P1) is open.

## Acceptance criteria

| AC | How | Evidence | Result |
|----|-----|----------|--------|
| B1. The bug reproduces in the real app on `develop` at Fit (Steps to reproduce, Actual) | Script | S0, S1, S2, S4's Fit frames: 33 of 76 Fit snapshots wrong. The launch's first refinement was wrong in all 9 Fit launches of S0, S1 and S2. In S2's cold-preview-cache launches 22 of 30 snapshots were wrong, first and later refinements alike (O2). Wrong cells are whole 1/4-width, 1/2-height rectangles: flipped, misplaced or noisier | Pass |
| B2. Reproduces at 100%, and back at Fit after 100% | Script | S3, S4: 6 of 38 snapshots wrong at 100%; S3's return-to-Fit frames: 1 of 10 wrong | Pass |
| B3. Gone at Fit on the branch, first refinement and after Masking moves (Expected) | Script | S1, S2, S4, S3's back-at-Fit frames: 0 of 84 wrong; in S1 and S2 the 9 distinct Masking values give one identical map each, in every launch that has them (8 launches) | Pass |
| B4. Gone at 100% with Masking moved, on the branch | Script | S3, S4, probe: 0 of 39 at 100%; identical across the launches of each script | Pass |
| B5. Cancelled refinements: the next refinement is correct (status.md, For QA 3; Cancellation) | Script, Test | S4 (branch): 0 of 12 wrong; its 9 Fit frames are identical to S2's correct map for the same Masking (worst 0), its 3 100% frames are identical across the launches and were viewed. Test: `SharpeningMapSessionTests.cancelledRefinementKeepsTheInput` passes (guard, not a regression test, per status.md) | Pass |
| B6. Every refinement equals the map from the full-resolution master, apart from the input's rounding (Expected) | Test | `SharpeningMapRawFileTests.refinedMapsMatchRenderedPixels`: 5 of 5 cold processes pass, each comparison worst 0 (same graph over eagerly rendered pixels, status.md). `refinedIsFullResolution` (synthetic, AC7 of sharpen-mask-preview) passes | Pass |
| B7. Fix: the kept input is rendered pixels, not a lazy image (Root cause; `deferred: false` in `SharpeningMapRefiner.materialize`) | Test | `SharpeningMapSessionTests.keptInputIsRendered` passes on the branch; read the diff (one word) | Pass |
| B8. Regression checks fail without the fix | Test | On `develop` + the test file (materialize made non-private so it compiles): `keptInputIsRendered` fails, 2 issues, `pulled > 0` and the later-reads expectation, exactly as stated; `refinedMapsMatchRenderedPixels` fails in 5 of 5 cold processes (12, 12, 13, 12, 9 of 15 comparisons, all worst 255) | Pass |
| B9. No golden changed; `currentPipelineVersion` did not move | Test, Read | `git diff dfa0d5c a452c86` touches no file under `Tests/PhotoCoreTests/Goldens` or `.../Reference`; `currentPipelineVersion` is 7 at both commits; `GoldenTests` pass in the full run | Pass |
| B10. `swift test` on the branch | Test | a452c86 in the checkout: 637 tests in 109 suites, passed, 1 known issue (`LiveSessionTests`, "Values above white survive the cached stages", the existing `withKnownIssue`) | Pass |
| B11. CI on the pull request head | Test | Run 42683751502 on a452c86: `Build and test (macos-15)` success, `Build and test (macos-26)` success | Pass |
| B12. On a real display, the owner's stack (status.md, For QA) | Person | P1 | Open |

Result is Pass, Fail, Open or Waived. Counts: 6 passed by test (B6–B11), 5 by script
(B1–B5), 1 open for a person, 0 failed.

How snapshots were judged: each script's frames were compared cell by cell (4 ×
2) with a reference frame from the branch's first run of the same script. A cell
is "wrong" when at least 4% of its pixels differ by 16 or more of 255 (luma) and
the worst difference is at least 64; all wrong cells were judged by eye as well.
Every snapshot was viewed directly, on a contact sheet at reduced size, or is
identical (content hash, or per-cell difference 0) to one viewed. S1 and S2's 65
branch snapshots group into exactly 9 images, one per distinct Masking value (23
comes up twice in each script; see Follow-up). The frames'
Masking and that the map is on screen are from `print sharpenmap` (`frame map of
applied values masking N`, `refining false`); as in `sharpen-mask-preview/qa.md`
(Q3), the script cannot say the frame on screen is the refined one, so each snapshot
waited 3–6 s, far longer than a refinement. The waits are in the scripts below.

## Findings

No failures and no missing tests against the fix. The first two below are
observations for the engineer; neither blocks.

**O1. On `develop` the wrong cells are not only the ones `status.md` lists.**
Status (Actual) names column 2 of 4 in the bottom half and column 4 in either
half, and says the owner saw the bottom half (those are headless runs). In the app
at Fit (S2) wrong cells also fell in column 1 and column 3 of the bottom half, and
at 100% (S3) in column 3 of the top half. Worth widening that sentence when
`status.md` is next touched; it changes nothing about the fix.

**O2. On `develop`, the preview cache's state changes how often later refinements are wrong.**
- Steps: S2 on `develop`, with the library's `Previews` folder cleared before the
  launch (cold) or kept (warm).
- Warm: only the launch's first refinement is wrong (2 of 20 snapshots wrong in
  S2, 3 of 15 in S1).
- Cold: 22 of 30 wrong, the first and later ones, in cells that change between
  refinements.
- On the branch the fault is absent in both cases, so this matters only for
  anyone reproducing it on an older build, and for why a warm-library retry
  can look clean. Unexplained, like the fault itself (Root cause: Not known).

## Scripts

Setup, scratch only (`Q` is a folder under the session scratchpad; nothing
touched the owner's library, preferences, playground, the running app, or the
original RW2):

```
git archive dfa0d5c | tar -x -C $Q/develop
git archive a452c86 | tar -x -C $Q/branch
(for t in develop and branch) cd $Q/$t && Scripts/build-app.sh
cp -R $Q/$t/build/Gus.app $Q/bundles/Gus-$t.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.qa-$t $Q/bundles/Gus-$t.app/Contents/Info.plist
codesign --force --deep --sign - $Q/bundles/Gus-$t.app
cp <scratch>/raw/P1040037.RW2 $Q/photos/P1040037.RW2
cd $Q/$t && swift run -c release photobench import --library-root $Q/libs/$t --source $Q/photos
```

Each launch: `$Q/bundles/Gus-<t>.app/Contents/MacOS/Gus --library-root $Q/libs/<t>
--debug-script "<script>"`, run directly so it never activates. Cold = `rm -rf
$Q/libs/<t>/Previews` before the launch. Cell numbers below are (column, row) from
the top left of the map, 4 columns by 2 rows. `SHOTS` is the launch's output folder.

**S0: first look, `develop`.** First-ever launch on that library.
`wait 2; print items; print title; focus P1040037; loupe; wait 3; print loupe; print responder; adjust amount 98; adjust radius 1.4; adjust detail 52; adjust masking 23; wait 2; sharpenmap on; wait 5; print sharpenmap; print loupe; snapshot SHOTS/dev-smoke-fit-23.png; adjust masking 30; wait 5; print sharpenmap; snapshot SHOTS/dev-smoke-fit-30.png; quit`
Result: Masking 23 wrong at (2,2) (noisier, misplaced water); Masking 30 wrong at
(4,1) (trees displaced). Both visible in the snapshots.

Branch probe, the same window as S3, one launch, clean at 100%:
`wait 2; focus P1040037; loupe; wait 3; adjust amount 98; adjust radius 1.4; adjust detail 52; adjust masking 23; wait 2; windowsize 3400 2300; wait 1; sharpenmap on; wait 4; print sharpenmap; print loupe; zoom; wait 6; print loupe; print sharpenmap; print responder; snapshot SHOTS/z-23.png; quit`

**S1: Fit, Masking moved, cold launch (preview cache warm).** Three launches per build.
`wait 2; focus P1040037; loupe; wait 3; adjust amount 98; adjust radius 1.4; adjust detail 52; adjust masking 23; wait 2; sharpenmap on; wait 4; print sharpenmap; snapshot SHOTS/fit-23.png; adjust masking 30; wait 3; print sharpenmap; snapshot SHOTS/fit-30.png; adjust masking 18; wait 3; print sharpenmap; snapshot SHOTS/fit-18.png; adjust masking 45; wait 3; print sharpenmap; snapshot SHOTS/fit-45.png; adjust masking 23; wait 3; print sharpenmap; snapshot SHOTS/fit-23b.png; quit`
Result: develop, the first refinement wrong at (2,2) in 3 of 3 launches (68.1% of
the cell's pixels off), the other 12 snapshots clean; branch, 15 of 15 clean,
identical across the three launches (worst 0).

**S2: Fit, ten maps (nine Masking moves, 23 first and last).** Five launches per build, 3 cold and 2 warm.
`wait 2; focus P1040037; loupe; wait 3; adjust amount 98; adjust radius 1.4; adjust detail 52; adjust masking 23; wait 2; sharpenmap on; wait 4; print sharpenmap; snapshot SHOTS/m00-23.png; adjust masking 30; wait 3; print sharpenmap; snapshot SHOTS/m01-30.png; adjust masking 18; wait 3; print sharpenmap; snapshot SHOTS/m02-18.png; adjust masking 45; wait 3; print sharpenmap; snapshot SHOTS/m03-45.png; adjust masking 12; wait 3; print sharpenmap; snapshot SHOTS/m04-12.png; adjust masking 35; wait 3; print sharpenmap; snapshot SHOTS/m05-35.png; adjust masking 27; wait 3; print sharpenmap; snapshot SHOTS/m06-27.png; adjust masking 20; wait 3; print sharpenmap; snapshot SHOTS/m07-20.png; adjust masking 40; wait 3; print sharpenmap; snapshot SHOTS/m08-40.png; adjust masking 23; wait 3; print sharpenmap; snapshot SHOTS/m09-23.png; quit`

| Masking | 23 | 30 | 18 | 45 | 12 | 35 | 27 | 20 | 40 | 23 |
|---------|----|----|----|----|----|----|----|----|----|----|
| develop cold 1 | (2,2) | (4,1) | (4,1) (3,2) | ok | (3,2) | (2,2) | ok | ok | ok | ok |
| develop cold 2 | (2,2) | (2,2) (4,2) | (1,2) (4,2) | (4,1) (2,2) | (2,2) | (4,1) | (4,1) | ok | (4,1) | (4,1) |
| develop cold 3 | (2,2) | (4,1) (2,2) | (4,1) | ok | (4,1) (4,2) | (4,2) | (4,2) | (4,1) | ok | (4,2) |
| develop warm 1, 2 | (2,2) | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| branch cold 1–3, warm 1–2 | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |

Develop: 24 of 50 snapshots wrong (22 of the 30 cold). Branch: 0 of 50, with one
identical image per Masking across all five launches. The 20 distinct wrong images
were each viewed: whole cells flipped, misplaced or noisier, the kayak upside down
in several.

**S3: 100%, full width in one snapshot, and back to Fit.** Five launches per build
(3 cold, 2 warm). The window was set to 3400 × 2300 (capped at the display's height,
6800 × 3324 px), which shows the full image width at 100% and 79% of its height
(`print loupe`: visible -72,189 2880x1446, magnification 1.000).
`wait 2; focus P1040037; loupe; wait 3; adjust amount 98; adjust radius 1.4; adjust detail 52; adjust masking 23; wait 2; windowsize 3400 2300; wait 1; sharpenmap on; wait 4; zoom; wait 6; print loupe; print sharpenmap; snapshot SHOTS/z-23.png; adjust masking 30; wait 5; print loupe; print sharpenmap; snapshot SHOTS/z01-30.png; adjust masking 18; wait 5; print loupe; print sharpenmap; snapshot SHOTS/z02-18.png; adjust masking 45; wait 5; print loupe; print sharpenmap; snapshot SHOTS/z03-45.png; adjust masking 12; wait 5; print loupe; print sharpenmap; snapshot SHOTS/z04-12.png; adjust masking 35; wait 5; print loupe; print sharpenmap; snapshot SHOTS/z05-35.png; adjust masking 23; wait 5; print loupe; print sharpenmap; snapshot SHOTS/z06-23.png; zoom; wait 5; print loupe; snapshot SHOTS/back-23.png; adjust masking 28; wait 3; print loupe; print sharpenmap; snapshot SHOTS/back-28.png; quit`
Result: develop, first refinement at 100% wrong in 4 of 5 launches, cell (3,1) (the
same image in all four), and a return-to-Fit frame wrong in 1 of 5 launches at (4,1);
the other 40 snapshots clean. Branch: 45 of 45 clean; identical across the five
launches; the 100% and return-to-Fit images viewed at every Masking value.

**S4: cancelled refinements.** Three cold launches per build.
`wait 2; focus P1040037; loupe; wait 3; windowsize 1320 860; wait 1; adjust amount 98; adjust radius 1.4; adjust detail 52; adjust masking 23; wait 2; sharpenmap on; wait 0.25; adjust masking 30; wait 4; print sharpenmap; snapshot SHOTS/c1-30.png; adjust masking 18; wait 0.2; adjust masking 40; wait 0.18; adjust masking 12; wait 4; print sharpenmap; snapshot SHOTS/c2-12.png; sharpenmap off; wait 2; sharpenmap on; wait 0.2; adjust masking 45; wait 4; print sharpenmap; snapshot SHOTS/c3-45.png; zoom; wait 6; adjust masking 30; wait 0.2; adjust masking 18; wait 6; print loupe; print sharpenmap; snapshot SHOTS/c4-100-18.png; quit`
Compares against the branch's S2 images for the same Masking (identical Fit layout,
checked), and for the 100% frame against the branch's first launch of this script
(its window shows only the center of the map, so those frames' cells are the
window's). Result: develop, 6 of 12 frames wrong (first refinement of a cancelled
Fit fill wrong at (2,2) in 3 of 3 launches; (4,1) at Masking 12 once; two 100%
frames wrong); branch, 0 of 12, every frame identical to the correct map (worst 0).

**Regression checks on `develop`** (scratch copy: `Tests/PhotoCoreTests/SharpeningMapSessionTests.swift`
from the branch, and `private func materialize` changed to `func materialize` so the
test can reach it, nothing else):

```
swift test --filter keptInputIsRendered
CAMERA_RAW_SAMPLE=$Q/photos/P1040037.RW2 swift test --filter SharpeningMapRawFileTests
```

`keptInputIsRendered`: failed, 2 issues, `Expectation failed: pulled > 0` and
`Expectation failed: provider.calls.withLock { $0 } == pulled`.
`SharpeningMapRawFileTests`, 5 cold processes (each a separate `swift test`): 12,
12, 13, 12, 9 of 15 comparisons failed, each `worst 255 against the same pixels`
(58 of 75). On the branch in the checkout, the same command 5 cold processes: all
pass, every comparison worst 0.

`swift test` on the branch (a452c86, in the checkout): 637 tests in 109 suites
passed with 1 known issue.

The P1 sidecar setting, on the branch copy (`defaults write me.sesser.gus.debugtest.qa-branch sidecars.write -bool false`, then `defaults delete` of it):
`wait 2; print disk; quit` prints `changed on disk 0, writes false` with the preference set and `writes true` without it.

Safety, after the run: no instance of QA's bundle copies still running (`pgrep`);
0 files newer than the run's start under `~/Library/Application Support/Gus`; the
checkout's `git status` clean apart from this file. The owner's playground was not
opened or looked at.

## For a person

**P1. No wrong cells in the Sharpening Map on your real display, with your stack (covers B12).**
No design review, so no M-number. Nobody has looked at the fix on a real display.
Takes a few minutes.

Do it in `~/Desktop/gus-playground`, where you saw the fault. Opening that
library is safe with the steps below: the commands make a copy of the app with
its own bundle identifier, so your real preferences and library stay out of it,
and pass `--library-root`. QA did not open or inspect that folder, so these steps
assume it is a library root (that it holds a `Library` folder, as `--library-root`
creates). A short second pass in a fresh library is the cold run (see **Warm or
cold** below).

Paste, then press Return (zsh; quit any running copy of the app first):

```
cd /Users/randy/Projects/Gus/.claude/worktrees/amazing-gates-111e8a
Scripts/build-app.sh
cp -R build/Gus.app ~/Desktop/Gus-branch-qa.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest ~/Desktop/Gus-branch-qa.app/Contents/Info.plist
codesign --force --deep --sign - ~/Desktop/Gus-branch-qa.app
defaults write me.sesser.gus.debugtest sidecars.write -bool false
open -W -n ~/Desktop/Gus-branch-qa.app --args --library-root ~/Desktop/gus-playground
```

The `defaults write` line matters: the copy's preferences are new, and in new
preferences the "Write XMP sidecar files" setting is on, and the app writes any
queued sidecars 1.5 s after opening a library. With it off, nothing is written
beside the masters that library points at. (QA confirmed that preference on a copy
of the app: `print disk` reports `writes false`.)

1. Open `P1040037.RW2` in the loupe, on the display where you saw the fault. Note
   Amount, Radius, Detail and Masking (your stack is saved in that library; you'll
   put it back). Don't show the map yet: step 2 has to be this launch's first map.
2. At Fit: **Adjust ▸ Show Sharpening Map** (or the toggle under Details ▸
   Sharpening). Wait for the small spinner to stop, then look at the whole map.
3. Move Masking four times (for example to 30, 18, 45, then 23). After each move,
   wait for the spinner to stop and look again.
4. Still at Fit, move Amount, Radius and Detail a little, one at a time, and look
   after each. QA moved only Masking with the map on; these three reuse the same
   kept input in the code, but nobody has run them. Amount and Detail each rerun
   the refinement but should leave the map looking exactly the same (it reads only
   Radius and Masking), so any change there is a fault.
5. Press **Z** for 100%. Wait for the spinner, then look. Move Masking twice more
   (for example 30, then back to 23); look after each. Press **Z** to return to Fit.
6. Press **⌘Z** once per slider move, or set all four back to the values from step
   1. Then **⌘Q** to quit.

What to look for, at Fit and at 100%: a straight-edged rectangle about one
quarter of the photo wide and half its height, in which the map's content is
visibly flipped or moved, or much noisier than the map around it (a thin white
line down the rectangle's right edge is a common sign). On the unfixed build it
was usually obvious within the first one or two refinements; look across all
four columns and both rows.

Pass: no rectangle like that in any view. If you see one, note the Masking
value, whether at Fit or at 100%, and take a screenshot, and send it back to the
engineer.

**Warm or cold.** On `develop` with previews already cached, only the launch's
first map went wrong (O2: 5 of 5 warm Fit launches). You have already looked at
this photo in `gus-playground`, so its cache is probably warm: there, step 2 is the
real test and the moves in steps 3 and 4 prove little. To repeat step 2, quit and
relaunch. That library's previews are in its own `Previews` folder, not in the app
copy's data, so going cold there would mean deleting part of the library. Don't:
use a fresh library for the cold run, where every move counts.

Copy (not move) your `P1040037.RW2` into a new folder,
`~/Desktop/gus-qa-cold/photos`. Quit the app, then paste:

```
cd /Users/randy/Projects/Gus/.claude/worktrees/amazing-gates-111e8a
swift run -c release photobench import --library-root ~/Desktop/gus-qa-cold/lib --source ~/Desktop/gus-qa-cold/photos
open -W -n ~/Desktop/Gus-branch-qa.app --args --library-root ~/Desktop/gus-qa-cold/lib
```

Open the photo in the loupe, set Amount 98, Radius 1.4, Detail 52 and Masking 23,
then do steps 2 to 5 and quit. A new library has no previews on its first launch;
on `develop` that case (S0) went wrong on the first map and after a Masking move.
Your own stack is not in this run, so it adds to the playground pass rather than
replacing it; if you would rather not open the playground at all, it is a fair
substitute without your stack. Afterwards, drag `Gus-branch-qa.app` and
`gus-qa-cold` from the Desktop to the Trash.

## Follow-up

**2026-11-09, from the product manager's review (`pm-review.md`).** Verdict
unchanged. Code unchanged since the tested commit: `git diff a452c86 HEAD` touches
only `pm-review.md` and this file. No new app runs or tests; the first item
re-read the existing snapshot files.

- **Count corrected: loose counting, no finding.** This file said S1 and S2's
  branch maps were 10 images. Comparing the files, their 65 snapshots are 9
  distinct images for the 9 distinct Masking values, each value's images identical
  across launches. Masking 23 comes up twice in each script, and its first and last
  maps are byte-identical PNG files in all 8 Fit launches (S1, S2) and all 5 at
  100% (S3), difference 0. So nothing here bears on R6 of `sharpen-mask-preview`.
  B3, the sentence under the table and S2's heading are corrected.
- **P1 extended; still one check, still Open.** Added that on a warm preview cache
  step 2 is the real test, and a fresh-library pass for the cold run, because the
  playground's previews live in its own `Previews` folder
  (`LibraryLocations.rooted(at:)`), which is not the bundle copy's data. Added step
  4, moving Amount, Radius and Detail, with the stack put back in step 6. Read for
  it, not run: the refiner's key ignores every Sharpen value
  (`SharpeningMapRefiner.swift:62-66`), a change to any of them schedules a
  refinement (`AdjustmentEditor.change`, `requestRender`), and the mask reads only
  Radius and Masking (`AdjustmentRenderer.sharpeningMask`).
