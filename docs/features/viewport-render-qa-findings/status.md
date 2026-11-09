# QA findings on sharp live frames at 100%: status

Owner: swift-macos-engineer. Bug fix for what `docs/features/viewport-render-1to1/qa.md` found after PR #49
merged. Branch `bug/viewport-render-qa-findings`, from `develop` at `915d39a`. The baseline for the stall
measurements is `013c0e8`, the first parent of the #49 merge.

**Status: Done.** Q1 is fixed and Q2 did not reproduce. The stall this feature added after letting go of White Balance is gone. Next step: code-reviewer, then qa-tester, then the owner's sign-off.

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

**Check that fails without the fix.** `q1` on bundle copies, `print ml` 5 s and 11 s after the hold and after the
commit: `spinner true` three times before, `spinner false` three times after.

### Q2 and the longer stall after letting go at 100%

**Steps.** `qa.md` scripts `arrive` and `m13b`: maximized window on the Dell, typical stack, 100%, a 20 ms main-thread
heartbeat after an arrow key or a commit.

**Expected.** The main-thread stall is no longer than on `develop` before the feature.

**Actual, as QA reported (one run per build).** Arrival 590–613 ms against 0–390 ms. Longest gap after Amount 411–429
against 360–385 ms; White Balance 622–634 against 400–407 ms; Amount with machine learning on, 1.15 s.

**What several runs per build showed.** See the table under Measurements.

- **Arrival:** not reproduced. Across 6 runs per build the longest gap is the same on both, and a `sample` of the main
  thread gives the same time in the rendition's first draw on both (1535 samples for 4 arrivals on each).
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

A drag that starts before the full rendition has landed is soft until its decode lands, which R6 and ruling 9 allow.

**Test or check that fails without the fix.** `LiveRegionRendererTests` "Only a settled frame of the saved values
leaves the decode for later" pins the rule. The stall itself is measured below, not asserted in `swift test`.

**Not fixed here (the owner's call).** The existing part of the stall, the full rendition's first draw on the main
thread (`createCGImage` deferred in `RenderEngine`), is its own bug. It is listed in the follow-ups of
`docs/features/viewport-render-1to1/status.md`. `RenderEngine` and `LiveRenderSession.base` are untouched.

## Measurements

Longest main-thread gap in ms, per heartbeat window (20 ms heartbeat, `print loupe`, QA's method), the Dell, maximized
window, 24 MP synthetic DNG, typical stack, 100%, nothing else running. Alternating builds, in both orders.
`013c0e8` is the baseline; "before" is `915d39a`, this branch before the fixes; "after" is this change.

| Case | `013c0e8` | Before | After |
|---|---|---|---|
| Arriving at a photo at 100% (a full render drawn; 24 windows, 12, 12) | 367–397 | 372–393 | 379–394 |
| Letting go of Amount, direct commit (9, 3, 6 runs) | 447–554 | 377–387 | 381–423 |
| Letting go of Amount, after a drag (9, 3, 6) | 413–617 | 389–420 | 388–427 |
| Letting go of White Balance, direct commit (9, 3, 6) | 387–505 | **486–559** | 391–487 |
| Letting go of White Balance, after a drag (9, 3, 6) | 404–519 | 450–545 | 384–453 |
| Amount with machine learning on, direct commit (6, 3, 3) | 1823–1861 | 1800–1822 | 1817–1859 |
| Amount with machine learning on, after a drag (6, 3, 3) | 1064–1096 | 1074–1095 | 1088–1096 |

Arrival windows where the full rendition was already in memory (22–29 ms) are left out of the arrival row (5 windows on the
baseline, 1 before, 1 after). Main-thread samples in `CA::Transaction::commit` for four White Balance commits: baseline
1581 and 1675, before 1928, after 1624.

Reading the table:

- No "after" range goes above the top of the baseline's. Nothing this feature added remains in the stall.
- White Balance's direct commit was the one case the feature made slower, and it is fixed.
- Amount's stall is shorter than the baseline's, and was before these fixes too.
- QA's 590–613 ms on arrival and the 1.15 s with machine learning on are not this feature: arrival didn't reproduce on any
  build, and the baseline stalls just as long with machine learning on (1064–1096 ms after a drag, 1823–1861 on a commit).
  What remains is the existing deferred full render, its own bug.
- These gaps are higher than QA's for the same builds (the baseline's Amount 447–554 here, 360–385 in `qa.md`), so read
  only the comparison within this table.

AC9 was not re-measured: `LiveRegionRenderer.render` and how a region frame renders are unchanged; only when a decode starts
changed. No golden moved and no pipeline bump.

## Build and test

- Baseline at `915d39a`: not run before the first edit.
- Latest: `swift build` clean. `swift test`: **650 tests in 110 suites passed, 1 known issue** (the existing
  `LiveSessionTests` one). `LARGE_RENDER_TESTS=1 swift test --filter LiveRegionRendererTests`: 13 of 13 passed.

## What changed

- `Sources/PhotoApp/Model/AdjustmentEditor.swift`: the region-current path ends the machine learning wait; the decode waits for the
  full rendition (`decodeWaitsForFullRendition`, `loupeLoadsFullRendition`).
- `Sources/PhotoApp/Loupe/LoupeView.swift`: says when a full rendition is loading.
- `Sources/PhotoCore/Edits/LiveRegionRenderer.swift`: `LiveFrameRules.decodeWaitsForFullRendition`.
- `Tests/PhotoCoreTests/LiveRegionRendererTests.swift`: the rule's test.
- `docs/features/viewport-render-1to1/status.md`: code review's C17 corrections and the full-render follow-up.

## Open questions

No design questions and no requirements issues. The owner has already agreed that the existing full-render stall is its own bug.

## README

No change.
