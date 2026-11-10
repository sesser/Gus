# QA findings on sharp live frames at 100%: status

Owner: swift-macos-engineer. Bug fix for what `docs/features/viewport-render-1to1/qa.md` found after PR #49
merged. Branch `bug/viewport-render-qa-findings`, from `develop` at `915d39a`. The baseline for the stall
measurements is `013c0e8`, the first parent of the #49 merge.

**Status: Done.** Q1 is fixed, and the decode this feature started during a White Balance commit's first draw no
longer runs there. **Q2 (2026-11-09): no regression, no code change.** QA's +245 ms came from the inspector being open
on `before` and `after` only, a setting left over from QA's earlier `maps` runs. With the inspector in the same state
on every build, arrivals on this branch match the baseline within the A/A noise, with the inspector hidden and with it
open on Adjust (see "Q2: the cause" below). Next step: qa-tester to confirm Q2 with the inspector state pinned, then the
owner's sign-off. Code review (`code-review.md`) asked for no code change, and Q2 adds none.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

### Q1: the machine learning spinner stays on at 100%

**Steps.** A raw at 100%, machine learning noise reduction on (macOS 27). Drag Luminance and hold still with the
control held (`qa.md` script `q1`).

**Expected.** The spinner shows during the wait and goes when the sharp frame is on screen (R5, design §2).

**Actual.** The sharp frame lands, `print ml` keeps `spinner true` until the next value change. Not at Fit.

**Root cause, proved with a trace in a throwaway build.** The sharp frame ended the wait, then:

```
q1 stop
q1 region branch current false interactive true      (the sharp frame of the hold)
q1 arm luminance 60.0 interactive false              (the pause's refinement arms the wait again)
q1 region branch current true interactive false      (that frame is already on screen)
q1 short-circuit: nothing shown
```

`requestRender` arms the wait for any values that decode with machine learning. The render loop then finds a
region frame and a whole frame of those values already on screen and shows nothing, and only showing a frame ended
the wait. At Fit a whole frame always lands, so it can't happen there.

**Fix.** `AdjustmentEditor`'s render loop ends the wait when the region frame on screen is already of the awaited
values.

**Check that fails without the fix.** The `q1` script, an explicit check run on bundle copies (`PhotoCoreTests`
doesn't link PhotoApp, so `swift test` can't reach it): `print ml` 5 s and 11 s after the hold and after the
commit: `spinner true` three times before, `spinner false` three times after.

### Q2 and the longer stall after letting go at 100%

**Steps.** `qa.md` scripts `arrive` and `m13b`: maximized window on the Dell, typical stack, 100%, a 20 ms main-thread
heartbeat after an arrow key or a commit.

**Expected.** The main-thread stall is no longer than on `develop` before the feature.

**Actual, as QA reported (one run per build).** Arrival 590–613 ms against 0–390 ms. Longest gap after Amount 411–429
against 360–385 ms; White Balance 622–634 against 400–407 ms; Amount with machine learning on, 1.15 s.

**What several runs per build showed.** See the table under Measurements.

- **Arrival:** superseded by "Q2: the cause" below. My earlier "Q2 did not reproduce" and the imbalance of cheap arrivals
  (22–29 ms windows, 5 on the baseline against 1 on each feature build) were wrong. QA traced the cheap arrivals to scripts
  with no heartbeat right before the key, so a stall inside the key command's 80 ms sleep went unseen. With one, 0 of 96
  arrivals are cheap: every arrival stalls about 380 ms on every build.
- **Amount, and Amount with machine learning on:** not slower than the baseline in any run.
- **White Balance:** slower on a direct commit, by 60–90 ms a commit in the `sample` totals. This is the feature's added time.

**Root cause (White Balance).** `sample` shows the longest gap is the deferred full rendition's first draw inside
`CA::Transaction::commit`, on both builds: 1581–1675 samples over 4 commits on the baseline, 1928 on this feature.
The commit changes a raw decode setting, so the render loop started a full-resolution decode for the next
drag right then, competing for the GPU with that first draw.

**Fix.** The decode for the next drag now waits until the full rendition has landed:

- A non-interactive frame of the saved values, with nothing changing and no overlay, Show Original or hover preview,
  starts no decode (`LiveFrameRules.decodeWaitsForFullRendition`). A held control, an overlay, Show Original and a
  hover preview still decode at once.
- `scheduleRegionPrepare` doesn't start while a full rendition is loading, and runs when it lands. The arrival and `Z`
  paths go through this too, so the culling path can't compete either.

A drag that starts before the full rendition has landed is soft until its decode lands, which R6 ("the first frame of a
drag") and the frame-by-frame check's Allowed line allow. `decode settling` in `print frames` now also appears on a commit's
`still` frame, when the decode is waiting for the full rendition; the check's rule reads `interactive` lines only, so it
doesn't change that rule.

**Known gap (code review C4, not changed here).** When Fit is already 100% (a raw small enough), no full load starts, so nothing
restarts the decode after a commit until the next drag's second frame. R6 allows that soft start.

**Check that fails without the fix.** After a direct White Balance commit at 100%, `print frames` ends the commit's `still`
frame with `decode settling` with the fix and `decode running` without it, and without it a sharp frame follows straight away
(run on bundle copies from before and after: two commits each, same result). `LiveRegionRendererTests` "Only a settled frame
of the saved values leaves the decode for later" is only a truth table of the predicate: `PhotoCoreTests` doesn't link PhotoApp,
so it can't see whether the editor uses it. The stall itself is measured below, not asserted in `swift test`.

### Q2: the cause (2026-11-09)

**The +245 ms is the inspector's Adjust tab, open on QA's `before` and `after` bundles and closed on its two baselines.
The feature doesn't change arrivals.**

1. **Where the time goes.** I sampled the main thread only across four arrivals (`sample` started at a marker after `zoom`,
   so launch and quit are excluded) with QA's bundles and library. Inspector hidden: no `AppKitPlatformViewHost.viewDidMoveToSuperview`
   on either build, and window layout in the display cycle (`__NSWindowGetDisplayCycleObserverForLayout`) took 93 samples on
   the baseline against 88 on the branch. Inspector open on Adjust: `AppKitPlatformViewHost.viewDidMoveToSuperview` →
   `-[NSView _setDefaultKeyViewLoop]` → `layoutSubtreeIfNeeded` took **481 samples on the baseline and 477 on the branch**. That is
   the path in QA's `sample-after.txt`, and it costs the same on both builds.
2. **What invalidates the layout.** A new photo puts the editor in `.loading` (`AdjustmentEditor`, `state = .loading`) and
   then `.ready`. `AdjustView` switches on `model.loupeAdjustState` (which is `editor.state`), so each arrival tears down the whole
   Adjust tab, shows a `ProgressView`, and builds the tab again. A probe that logged every `addSubview` showed, per arrival, an
   `AppKitProgressView` host, then about 48 `AppKitButton`, 37 `AdjustSlider`, 20 `AppKitCheckbox` and 10 `AppKitDisclosure`
   representables. Each one hosted in an `AppKitPlatformViewHost` makes AppKit rebuild the window's key-view loop with a
   full `layoutSubtreeIfNeeded`. `AdjustView`, `InspectorView` and the editor's `.loading` step are unchanged since `013c0e8`.
3. **Why QA saw it on two builds only.** `browser.showsInspector` and the inspector tab are saved per bundle identifier.
   `sharpenmap on` opens the inspector on Adjust (`SharpeningMapActions.swift`). QA's `maps` script ran it on `before` and
   `after` only (14:52–14:53, before the campaign started at 15:04), and its own `maps-*.log` lines read `inspector true tab
   adjust`. `baseline` and `baseline2` never ran it, so the A/A pair matched while the two feature builds paid for the
   rebuild. The two-gap shape QA reported, about 250 + 370 ms, is that rebuild plus the full rendition's first draw.
4. **Checked in both states, QA's method** (below, under Measurements): with the same inspector state on every build, the
   branch is within the A/A noise of the baseline.

**No code change, so no new test.** The Bug section's "Expected" already holds. The check that shows it is the timing
campaign below, with the inspector state set in the script (`inspector off` or `inspector on; tab adjust`) and the scratch
identifiers' preferences deleted before each set, so no run inherits another's state. The rebuild itself shows with the
`addSubview` probe or `sample`, as in points 1 and 2. That cost belongs to the existing Adjust tab, not to this branch, and is
listed under Open questions.

**Not fixed here (the owner's call).** The existing part of the stall, the full rendition's first draw on the main
thread (`createCGImage` deferred in `RenderEngine`), is its own bug. It is listed in the follow-ups of
`docs/features/viewport-render-1to1/status.md`. `RenderEngine` and `LiveRenderSession.base` are untouched.

## Measurements

Longest main-thread gap in ms, per heartbeat window (20 ms heartbeat, `print loupe`, QA's method), the Dell, maximized
window, 24 MP synthetic DNG, typical stack, 100%, nothing else running. Alternating builds, in both orders.
`013c0e8` is the baseline; "before" is `915d39a`, this branch before the fixes; "after" is this change.

| Case | `013c0e8` | Before | After |
|---|---|---|---|
| Arriving at a photo at 100% (superseded: see the arrival table below) | 367–397 | 372–393 | 379–394 |
| Letting go of Amount, direct commit (9, 3, 6 runs) | 447–554 | 377–387 | 381–423 |
| Letting go of Amount, after a drag (9, 3, 6) | 413–617 | 389–420 | 388–427 |
| Letting go of White Balance, direct commit (9, 3, 6) | 387–505 | **486–559** | 391–487 |
| Letting go of White Balance, after a drag (9, 3, 6) | 404–519 | 450–545 | 384–453 |
| Amount with machine learning on, direct commit (6, 3, 3) | 1823–1861 | 1800–1822 | 1817–1859 |
| Amount with machine learning on, after a drag (6, 3, 3) | 1064–1096 | 1074–1095 | 1088–1096 |

The arrival row above is superseded: it used the longest gap, and windows with no heartbeat right before the key (the cheap
22–29 ms windows it left out were that artifact; see Bug, Q2).

**Arrivals at 100%, QA's method (2026-11-09).** QA's bundles (`013c0e8` as `baseline` and `baseline2`, the A/A pair, and
`d4a28d0` as `after`), QA's scratch library and QA's arrival script: a heartbeat right before each key, 225 heartbeats of 20 ms
(5 s windows), every gap over 100 ms counted, 80 ms off the gap spanning the key's sleep, by QA's `gaps.py`. Six rounds in
alternating order (`baseline baseline2 after`, `after baseline2 baseline`, `baseline2 baseline after`, `baseline after
baseline2`, `after baseline baseline2`, `baseline2 after baseline`), 4 arrivals per run, 24 arrivals per build per state. The
scratch identifiers' preferences were deleted before each state, with `NSAppSleepDisabled` set on them only. Median heartbeat
21.8–22.3 ms in every window, so none was throttled. No build, test, `photobench` or other app process ran during any run
(checked before each run and after it). `HEAD` (`2ec1da9`) differs from `d4a28d0` in docs only, so `after` is this branch.

| Inspector | Build | Arrivals | Gaps over 100 ms (1 / 2) | Stall per arrival, mean ± SD (range) | Paired by round against `baseline` |
|---|---|---|---|---|---|
| Hidden | `013c0e8` | 24 | 24 / 0 | 378 ± 11 ms (360–402) | |
| Hidden | `013c0e8`, A/A copy | 24 | 24 / 0 | 377 ± 10 ms (363–394) | −8, +4, −2, +11, −8, −2; mean −1 |
| Hidden | `d4a28d0` | 24 | 24 / 0 | 383 ± 12 ms (358–404) | −10, +10, +4, +14, +11, +2; mean +5, SD 9 |
| Open, Adjust | `013c0e8` | 24 | 14 / 10 | 611 ± 11 ms (594–630) | |
| Open, Adjust | `013c0e8`, A/A copy | 24 | 13 / 11 | 611 ± 13 ms (593–650) | +4, +2, −4, −15, +12, +5; mean +1 |
| Open, Adjust | `d4a28d0` | 24 | 6 / 18 | 620 ± 19 ms (588–694) | +6, +11, +9, +16, +12, +1; mean +9, SD 5 |

**Noise floor:** the A/A pair differs by up to 15 ms per round (SD 7–9), so about 15–20 ms is resolvable here. The branch
is +5 ms (hidden) and +9 ms (open) against the baseline, both inside that. QA's +245 ms is the 233 ms between the two
states, the same on both builds. With the inspector open the branch shows two gaps more often (18 of 24 against 10–11), but
the total is unchanged. A first, two-round run before this one gave the same result (hidden 378 against 374, open 633
against 649).

Main-thread samples in `CA::Transaction::commit` for four White Balance commits: baseline
1581 and 1675, before 1928, after 1624.

Reading the table:

- No "after" range goes above the top of the baseline's. That is a limited claim: see the last point.
- White Balance's direct commit was the one case that was slower before the fixes. It came back within the baseline's range, and
  its first-draw samples match (1624 after, 1581 and 1675 on the baseline, 1928 before).
- Machine learning on: all builds are the same, so the 1.15 s QA saw is on the baseline too.
- **How far this resolves.** The baseline's Amount rows sit 60–130 ms above both feature builds, on a code path the feature doesn't
  change, and they run 90–170 ms above QA's figures for the same commit. That is about the size of the effects being compared, so
  a difference of that size between builds in this table isn't established either way.

AC9 was not re-measured: `LiveRegionRenderer.render` and how a region frame renders are unchanged; only when a decode starts
changed. No golden moved and no pipeline bump.

## Build and test

- Baseline at `915d39a`: not run before the first edit.
- Latest: `swift build` clean. `swift test`: **650 tests in 110 suites passed, 1 known issue** (the existing
  `LiveSessionTests` one). `LARGE_RENDER_TESTS=1 swift test --filter LiveRegionRendererTests`: 13 of 13 passed.
- Q2 pass (2026-11-09): no source or test changed, so the results above stand. Nothing was built in the checkout.

## What changed

- `Sources/PhotoApp/Model/AdjustmentEditor.swift`: the region-current path ends the machine learning wait; the decode waits for the
  full rendition (`decodeWaitsForFullRendition`, `loupeLoadsFullRendition`).
- `Sources/PhotoApp/Loupe/LoupeView.swift`: says when a full rendition is loading.
- `Sources/PhotoCore/Edits/LiveRegionRenderer.swift`: `LiveFrameRules.decodeWaitsForFullRendition`.
- `Tests/PhotoCoreTests/LiveRegionRendererTests.swift`: the rule's test.
- `docs/features/viewport-render-1to1/status.md`: code review's C17 corrections and the full-render follow-up.
- Q2 (2026-11-09): no source change; this file only.

## Open questions

No design questions and no requirements issues. The owner has already agreed that the existing full-render stall is its own bug.

- **For qa-tester (Q2):** please re-run the arrival comparison with the inspector state set in the script and the scratch
  identifiers' preferences deleted before each set. A debug command such as `sharpenmap on` changes saved UI state (inspector
  shown, its tab), which then carries into later runs of that identifier.
- **A pre-existing cost for the product manager's next reconcile (not this branch's):** with the inspector open on Adjust, each
  arrival at a photo rebuilds the whole Adjust tab (`.loading` → `.ready`), and the ~100 AppKit-backed controls it hosts each
  rebuild the window's key-view loop. That is about 230 ms of main-thread time per arrival on `013c0e8` too, on top of the
  full rendition's first draw. It could be a bug of its own, like the full-render stall; I haven't measured it at Fit or
  changed it.

## README

No change.
