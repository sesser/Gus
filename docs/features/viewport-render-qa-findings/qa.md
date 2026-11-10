# QA findings on sharp live frames at 100%: QA

Owner: qa-tester. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`. Bug fix: the spec is the **Bug** section of `status.md`.
Tested: `bug/viewport-render-qa-findings` at `d4a28d0` (the fix is `643e80d`; `d4a28d0` only adds docs), against `915d39a` (`develop` at the cut, "before") and `013c0e8` (the first parent of the #49 merge, "baseline"), on a MacBook Pro with Apple M4 Pro (14-core CPU, 24 GB), macOS 27.2 (26B123), apps linked with the macOS 27.2 SDK (`vtool -show-build`), main display DELL U2723QE (framebuffer 6016 × 3384).

**How it was run.** Three scratch clones (no worktree, nothing built in the checkout), four bundle copies with their own identifiers (`after`, `before`, `baseline`, and `baseline2`, the same `baseline` binary under a second identifier as an A/A control), a scratch `photobench` library (6 synthetic 6000 × 4000 DNGs and one copy of a real 20 MP RW2), `--library-root` on every launch. `UPDATE_GOLDENS=1` was not run. The owner's library has no file newer than the start, `build/Gus.app` and `~/Desktop/gus-playground` were not touched, and the temporary `NSAppSleepDisabled` setting on my four scratch identifiers was removed at the end. Timings ran with nothing else heavy running, checked by a one-second process sampler on every timed run (no other build, test, photobench or app process appeared).

## Verdict

**Passes. Q1 and the added White Balance stall are fixed, this fix regressed nothing, and Q2 was a test-setup artifact, not a regression (second pass, below).** The spinner now ends when the sharp frame lands, and the White Balance stall the feature added is gone. With the inspector state set in the script, arriving at a photo at 100% costs the same on the baseline and on this branch: about 380 ms with the inspector hidden, about 610–620 ms with it open on Adjust. In my first pass the ~240 ms difference came from the inspector being open on Adjust in the `before` and `after` bundles only, left there by my own `maps` script. That rebuild of the Adjust tab on every arrival is real but predates the feature: it goes to the product manager as a follow-up.

## Acceptance criteria

| Item | How | Evidence | Result |
|---|---|---|---|
| Q1: the machine learning spinner ends when the sharp frame lands | Script | `q1`, on `before` and `after`. After the hold with a sharp frame on screen, `print ml` at 5 s, at 11 s and after the commit: `spinner true` three times on `before`, `spinner false` three times on `after` | Pass |
| Q1: it still shows during the wait | Script | `q1-wait`: on `after` the machine learning spinner is on from 946 ms until the sharp frame lands at 2110 ms (`tile shown … applied`), and the sharp-frame spinner covers the time from 525 ms | Pass |
| Q1: a newer value doesn't end it early | Script | `q1-newer`: two values in one hold. The spinner sequence on `after` matches `before` up to the end, and it ends only when the newest value's sharp frame lands (4293 ms). See the note on the machine learning spinner below | Pass |
| The added stall: after a direct White Balance commit at 100%, `print frames` shows `decode settling` on the `still` frame with the fix, `decode running` without it (code review C1) | Script | `c1`: three commits on each build. `after`: `decode settling`, and no sharp frame follows at once. `before`: `decode running`, and a sharp frame follows at once. A drag afterwards (`c1`, last block) is sharp from its first frame, so the decode runs once the full rendition has landed | Pass |
| The stall after letting go (M13): White Balance | Script | Campaign, below (`before` and `after` compared in the same inspector state; the baseline comparison is confounded, see the second pass): White Balance commit 449 ms against 439 ms on the baseline, against 562 ms on `before`. Paired by round, the fix takes off 113 ms, and the branch is +9 ms against the baseline, inside the A/A noise | Pass |
| The stall after letting go: Amount | Script | Campaign: 408 ms against 522 ms on the baseline, in different inspector states (second pass). Not re-run | Open, not shown either way |
| The stall after letting go: Amount with machine learning on | Script | Campaign: 1293 ms against 1267 ms on the baseline, in different inspector states (second pass). Not re-run | Open, not shown either way |
| Q2: arriving at a photo at 100% is no slower than the baseline (Bug section, "Expected") | Script | `campaign3` (second pass): 24 arrivals per build in each inspector state, the state set by the script and printed in every run, preferences deleted before each set. Inspector hidden: baseline 380 ms, branch 385 ms (+5, A/A ±16). Open on Adjust: 609 against 618 ms (+9, A/A ±9). The first pass's 379 against 624 ms compared different inspector states | Pass (second pass) |
| Nothing regressed: frame-by-frame on a slider and on crossings | Script | `ff-slider`: 27 frames, sharp from the first. `ff-crossing`: Exposure crossing 0 in both directions, 6 and 5 soft frames, Highlights 5, each `settling` then `running`, sharp again with no further input | Pass |
| Nothing regressed: the maps at 100% and at Fit | Script | `maps`, same script on `before` and `after`: identical render and refinement counts. Sharpening Map at 100%: tile down, `nearest true`, a pan renders nothing and doesn't restart the refinement. At Fit: `covered no`, map behaves as before. Fringe Map at 400%: `nearest true` | Pass |
| Full `swift test` and `LARGE_RENDER_TESTS=1` | Test | `swift test`: 650 tests in 110 suites passed, 1 known issue (the existing `LiveSessionTests` one). `LARGE_RENDER_TESTS=1 swift test --filter LiveRegionRendererTests`: 13 of 13, same worst differences as before (8 steps center, 2 corner, 7 and 2 with the crop, 4 raw, none over tolerance) | Pass |
| AC9 (speed) re-run | Not needed | The diff does not change how a region frame renders: `LiveRegionRenderer.render` and the render path are untouched; only when a decode starts and when the machine learning wait ends changed. `viewport-render-1to1/qa.md`'s AC9 stands | Not re-run, reason given |
| The accepted trade-off: a drag right after letting go is soft until its decode lands (code review: about 0.5 s, 1.4 s worst, under the 2.5 s timeout) | Script | `tradeoff`, in the frame-by-frame check's terms, below: 0 to 6 soft frames before the first sharp one, 80–471 ms of them (with the first sharp frame's own render, about 0.25–0.8 s). Never a timeout, never a soft frame after the first sharp one | Pass |

**The engineer's named test.** `LiveRegionRendererTests`, "Only a settled frame of the saved values leaves the decode for later", passes. As code review says, it is a truth table of the predicate; the check that fails without the fix is `c1` (above).

**A note on the machine learning spinner (not a finding).** While a value is being replaced mid-wait (`q1-wait`, `q1-newer`), the machine learning spinner can drop for a few hundred milliseconds between a soft interactive frame landing and the pause's refinement starting. The sharp-frame spinner fills most of that time. The sequence is the same on `before`, so this fix did not introduce it.

### Q2, second pass: the inspector state pinned

The engineer traced Q2 to saved state (`status.md`, "Q2: the cause"), and I confirmed it independently. My `maps` script runs `sharpenmap on`, which opens the inspector on Adjust (`SharpeningMapActions.swift:53`). I ran it on the `before` and `after` bundles only, before the campaign, so their saved preferences kept the inspector open while the baseline and its A/A copy had it hidden. My `maps` logs show `inspector true tab adjust`; the campaign logs didn't print it. With the inspector open on Adjust, each arrival rebuilds the Adjust tab, which is the SwiftUI layout pass the `sample` showed.

**Method (`campaign3`).** Builds: `013c0e8`, its A/A copy and `d4a28d0` (no source has changed since). Two sets, the first with `inspector off` and the second with `inspector on; tab adjust`, run before the photo loads. The scratch identifiers' preferences were deleted before each set, and `print inspector` runs before and after the arrivals in every log. Six rounds per set in alternating order (`baseline baseline2 after`, `after baseline2 baseline`, `baseline2 baseline after`, `after baseline baseline2`, `baseline after baseline2`, `baseline2 after baseline`). Each run does four arrivals with a 5 s heartbeat window and a beat before the key, as in the first pass. The process sampler showed nothing else running, no window was throttled, and none was cheap. `NSAppSleepDisabled` was set on the three scratch identifiers only and removed afterward.

| Inspector | Build | Arrivals | Logged state | Two gaps over 100 ms | Total of gaps over 100 ms, mean ± SD (range) | Paired by round against the baseline |
|---|---|---|---|---|---|---|
| Hidden | Baseline | 24 | hidden | 0 | 380 ± 11 ms (346–399) | |
| Hidden | A/A copy | 24 | hidden | 0 | 376 ± 14 ms (352–401) | −4 mean (−2, +2, −5, −7, −16, +4) |
| Hidden | This branch | 24 | hidden | 0 | 385 ± 12 ms (364–412) | +5 mean (+10, +13, +8, −2, −7, +9) |
| Open on Adjust | Baseline | 24 | open, Adjust | 8 | 609 ± 11 ms (587–627) | |
| Open on Adjust | A/A copy | 24 | open, Adjust | 11 | 612 ± 14 ms (589–653) | +3 mean (−5, +9, +1, +1, +7, +5) |
| Open on Adjust | This branch | 24 | open, Adjust | 13 | 618 ± 24 ms (585–707) | +9 mean (+3, +24, +8, +7, +4, +5) |

**Result.** In each state the branch is within the A/A noise of the baseline: +5 ms against A/A differences of up to 16 ms when hidden, and +9 ms against up to 9 ms (one round at +24) when open on Adjust. This method resolves about 15–25 ms, and no difference of that size shows. **Q2 is not a regression of the feature; it is withdrawn.** The ~230 ms in Q2 comes from the inspector being open on Adjust, and the baseline pays it too (609 against 380 ms). That is a pre-existing cost, recorded as a follow-up below.

**What this changes in the first pass.** The arrival comparison against the baseline (below) compared different inspector states and is superseded. The commit comparisons against the baseline (Amount, Amount with machine learning on, and the White Balance row's baseline column) carry the same confound and were not re-run. The `before` and `after` comparisons are in the same state and stand, including the White Balance fix (−113 ms) and "the fix doesn't change arrivals". The finding about cheap arrivals (no heartbeat before the key) does not depend on this and stands.

### Q2 and the stall after letting go: the first pass (arrival and baseline comparisons superseded)

Method (code review C2): each run does four arrivals (right, left, right, left, between two photos with the typical stack, at 100%, maximized window on the Dell) and four commits (Amount, White Balance, White Balance, Amount) and two commits with machine learning on, each with a 20 ms main-thread heartbeat, `print loupe`. Arrival windows last 5 s, with a heartbeat just before the key, so a stall during the key command's own 80 ms sleep is not missed (80 ms is subtracted from that gap). Six rounds for each of four builds in alternating order: `baseline baseline2 before after`, then `after before baseline2 baseline`, then `baseline2 baseline after before`, `before after baseline baseline2`, `baseline before baseline2 after`, `after baseline2 before baseline`. Every gap over 100 ms is counted.

**Arrivals at 100%: 24 per build.**

| Build | Arrivals | Cheap (longest gap under 60 ms) | One gap over 100 ms | Two gaps | Total of gaps over 100 ms, mean ± SD (range) |
|---|---|---|---|---|---|
| Baseline | 24 | 0 | 24 | 0 | 379 ± 21 ms (337–426) |
| Baseline, second copy (A/A) | 24 | 0 | 24 | 0 | 389 ± 23 ms (366–437) |
| Before the fix | 24 | 0 | 14 | 10 | 618 ± 26 ms (589–672) |
| This branch | 24 | 0 | 9 | 15 | 624 ± 30 ms (588–706) |

Every arrival, every gap over 100 ms (order right, left, right, left; `+` joins two gaps in one arrival):

| Round | Baseline | A/A copy | Before | After |
|---|---|---|---|---|
| 1 | 410, 361, 371, 390 | 433, 380, 388, 380 | 642, 598, 250+370, 597 | 465+240, 247+371, 594, 247+403 |
| 2 | 353, 376, 337, 366 | 428, 371, 371, 377 | 259+414, 257+372, 253+364, 600 | 248+353, 265+393, 255+380, 258+388 |
| 3 | 426, 377, 384, 375 | 424, 394, 437, 417 | 665, 389+235, 621, 600 | 644, 250+365, 384+231, 601 |
| 4 | 402, 372, 362, 370 | 369, 378, 366, 371 | 250+418, 376+226, 589, 593 | 636, 588, 594, 249+398 |
| 5 | 412, 378, 374, 380 | 403, 377, 382, 368 | 258+373, 282+372, 605, 598 | 598, 254+372, 369+234, 373+231 |
| 6 | 412, 372, 364, 377 | 409, 369, 368, 373 | 590, 250+368, 605, 599 | 250+415, 591, 265+378, 594 |

Per-round mean of the total per arrival: baseline 383, 358, 390, 377, 386, 381 (mean 379); A/A 395, 387, 418, 371, 382, 380 (mean 389); `before` 614, 629, 627, 613, 622, 603 (mean 618); `after` 642, 635, 619, 616, 608, 623 (mean 624). Differences paired by round:
- A/A (`baseline2 − baseline`): +12, +28, +28, −6, −3, −2; mean +10, SD 16, largest 28 ms.
- `after − baseline`: +259, +277, +229, +240, +222, +242; mean +245, SD 20, smallest +222.
- `before − baseline`: +231, +271, +237, +237, +236, +222; mean +239.
- `after − before`: +28, +5, −8, +3, −14, +20; mean +6, SD 16: the fix changes arrivals by nothing measurable.

**Noise floor and what can be resolved.** Two copies of one binary, in the same runs, differ by up to 28 ms per round (SD 16). So for arrivals this method resolves a difference of about 30 ms, and the 222–277 ms measured in every round is well above it. **That is a regression, in the feature, not noise.** The same goes for the reverse claim: the fix does not change arrivals (+6 ms mean, inside the noise).

**Why the arrivals called "cheap" (22–29 ms) were cheap.** They were a measurement artifact, not a cache. With a heartbeat just before the key and a 5 s window, 0 of 96 arrivals are cheap, on every build: every arrival has at least one gap over 100 ms. The memory cache keeps one full rendition, so going back to a photo misses it, and "already in memory" can't be the reason. What happened is that the earlier scripts (QA's `arrive`, and the runs in `status.md`) only had heartbeats after the `key` command, so a stall that falls inside that command's 80 ms sleep wasn't seen. Using the arrivals above and looking only at gaps after the first heartbeat after the key: 11 of 24 baseline arrivals, 8 of 24 of its A/A copy and 0 of 24 of `before` and `after` would have read as cheap, which matches the earlier imbalance (5 baseline against 1 each). The stall starts sooner on the baseline, so it was hidden more often. **So the "0" in `viewport-render-1to1/qa.md`'s "0–390 ms on `develop`" was wrong.** The baseline has a stall of about 380 ms on every arrival.

**Where the extra time goes (one `sample` per build, four arrivals, not a precise figure).** The first draw of the full rendition is the same: `LoupeController.display` 1259 samples on the baseline, 1231 on the branch. The added time is a SwiftUI layout pass of the window in the display cycle: `NSDisplayCycleFlush` 92 → 1067 samples, about 245 ms per arrival, `NSHostingView.layout`, `updateConstraints`. That is the second, ~250 ms gap in the "+" entries above, or both gaps merged into the ~600 ms ones. What invalidates the views on each arrival at 100% is the next question for the engineer.

**The stall after a commit at 100% (M13).** Direct commits on all builds, `adjust <name> <value>`, because the baseline has no `adjust scrub`. 12 commits per row, in the same runs. The longest gap and the total of gaps over 100 ms are the same here: one gap per commit.

| Commit at 100% | Baseline | A/A copy | Before | After | `after − baseline`, paired by round | Noise floor (A/A, largest) |
|---|---|---|---|---|---|---|
| Amount | 522 ± 42 ms (472–592) | 531 ± 48 ms | 410 ± 15 ms | 408 ± 11 ms (390–429) | −114 ms mean (−130, −138, −136, −70, −95, −114) | 81 ms (SD 45) |
| White Balance | 439 ± 43 ms (388–528) | 442 ± 49 ms | 562 ± 33 ms | 449 ± 33 ms (407–510) | +9 ms mean (+22, +37, −47, +22, +41, −18) | 41 ms (SD 35) |
| Amount, machine learning on | 1267 ± 14 ms (1252–1303) | 1253 ± 14 ms | 1271 ± 26 ms | 1293 ± 25 ms (1247–1320) | +26 ms mean (+4, +20, +28, +51, +16, +35) | 31 ms (SD 12) |

- **White Balance:** the fix's target. `before` is +123 ms over the baseline on average, and higher in every round (+66 to +173), in line with the earlier reports. On `after` it's +9 ms, inside the noise, and `after − before` is −113 ms (−70 to −144 in every round). The stall this fix targets is gone.
- **Amount:** the branch is not slower. The baseline's own run-to-run difference is large (A/A up to 81 ms, the same ~110 ms offset `status.md` noted on an unchanged path), so I can't say the branch is faster: only that a slowdown of more than about 80 ms would show, and none does.
- **Amount with machine learning on:** `after` is +26 ms against the baseline. A/A differences are up to 31 ms, so this can't be told apart from noise. Both builds stall about 1.3 s here, including the baseline, so it's not a regression of the feature.
- The resolvable differences for these commits are about 30–80 ms, set by the A/A rows, not the means.

### The trade-off: a drag started just after letting go

`tradeoff`, frame-by-frame terms: how many soft frames before the first sharp one, and their summed time. Maximized window, typical stack, 24 MP DNG, unless the row says otherwise. Each row is several runs of the step named; the first sharp frame's own render time adds to the time on screen.

| Step | `after` (this branch) | `before` (decode at commit) |
|---|---|---|
| Direct White Balance commit, drag Amount right away | 1 soft frame each time (80, 82, 111, 102 ms), then sharp | 1 soft frame (73, 145, 107, 96 ms) |
| Let go of a White Balance drag, then drag Amount | 4 and 2 soft frames (253, 168 ms) | 4 and 3 (327, 250 ms) |
| Three masks with Clarity, direct commit then drag | 0 soft frames, sharp from the first | not run |
| Three masks, let go of White Balance then drag | 4 soft (370 ms) | not run |
| Real RW2, direct commit then drag | 1 soft (132, 128 ms) | not run |
| Real RW2, let go of White Balance then drag | 6 soft (471 ms) | not run |

Time from the start of the drag to the first sharp frame on screen, by the frames' own times: about 0.25–0.4 s for a typical stack, up to 0.7–0.8 s for three masks, 0.25–0.6 s for the RW2, all inside the 2.5 s timeout. The frame-by-frame check's Allowed line covers this (any frame before the first sharp one may be soft), and no soft frame appeared after the first sharp one in any run. The fix makes no visible difference compared with `before` for this step.

## Findings

None open. **Q2 is withdrawn** after the second pass: it came from a difference in saved inspector state between bundles in my own setup, not from the feature (see "Q2, second pass").

**Method note for later QA.** Saved preferences persist per bundle identifier between runs. A check that opens the inspector, changes a tab or shows a map leaves that state for every later run of the same bundle. Before a timing comparison, delete the scratch identifiers' preferences, set the UI state the comparison depends on (inspector, tab, film strip, window size) in the script, and print it in every log.

**Code review's C4** (a raw small enough that Fit is 100%: the decode isn't rescheduled until the next drag) is still a known gap that R6 allows. It was not exercised: the scratch library has no photo that small.

## Requirements issues and design questions

**Follow-up for the product manager: rebuilding the Adjust tab on each arrival.** With the inspector open on Adjust, every arrival at a photo at 100% stalls the main thread about 230 ms longer than with it hidden: 609 against 380 ms on `013c0e8`, and the same on this branch. `sample` puts it in a SwiftUI layout pass of the window (`NSDisplayCycleFlush`), and the engineer traces it to the Adjust tab being rebuilt as the editor's state goes `.loading` → `.ready`. It predates the sharp live frames feature and is not changed by this fix, so it isn't for this branch. Proposed: a bug row, "the Adjust tab rebuilds on every photo while it's showing (about 0.23 s per arrow key at 100% on the Dell)", next to the full-render stall that is already a follow-up.

No design questions.

## Scripts

Setup, verbatim (zsh). `$Q` is this session's scratch folder. `ts.py` prefixes each line with its milliseconds since start. `frames.py` applies the frame-by-frame rule.

```zsh
git clone --no-hardlinks <checkout> $Q/trees/after;  git -C $Q/trees/after checkout d4a28d0
git clone --no-hardlinks <checkout> $Q/trees/before;  git -C $Q/trees/before checkout 915d39a
git clone --no-hardlinks <checkout> $Q/trees/baseline; git -C $Q/trees/baseline checkout 013c0e8
cd $Q/trees/<each> && Scripts/build-app.sh
cd $Q/trees/after && swift build -c release --product photobench
cp -R build/Gus.app $Q/app/Gus-<cfg>.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.<cfg> $Q/app/Gus-<cfg>.app/Contents/Info.plist
codesign --force --deep --sign - $Q/app/Gus-<cfg>.app
.build/release/photobench generate --output $Q/photos/dng --dng 6 --jpeg 0 --heic 0 --pairs 0 --videos 0 --per-folder 6
.build/release/photobench import --library-root $Q/lib --source $Q/photos/dng
.build/release/photobench import --library-root $Q/lib --source $Q/photos/rw2      # a copy of a real RW2

# Every run:
$Q/app/Gus-<cfg>.app/Contents/MacOS/Gus --library-root $Q/lib --debug-script "<script>; quit" | python3 -u $Q/ts.py > $Q/logs/<name>.log

# Fragments:
OPEN_LOUPE="wait 2; loupe; wait 1"
TYPICAL="adjust exposure 0.4; adjust contrast 15; adjust highlights -30; adjust shadows 25; adjust whites 10; adjust blacks -5; adjust clarity 20; adjust dehaze 10; adjust vibrance 15; adjust saturation 5; adjust curve rgb 0,0 0.3,0.25 0.7,0.78 1,1; adjust grade shadows 210 20; adjust grade highlights 40 15; adjust amount 40; adjust radius 1; adjust detail 25; adjust masking 20"
MASK="adjust mask set exposure 0.5; adjust mask set contrast 20; adjust mask set clarity 30"
Q1_BASE="$OPEN_LOUPE; focus RAW_00005; ml ready; windowsize 1900 1000; wait 1; adjust reset all; wait 1; zoom; wait 3"
ML_ON="ml on; wait 3"
hb(N)  = "print loupe; wait 0.02" repeated N times
mlp(N) = "print ml; print viewport; wait 0.1" repeated N times
```

Tests (scratch tree `after`):

```zsh
swift test
LARGE_RENDER_TESTS=1 swift test --skip-build --filter LiveRegionRendererTests
```

Each debug script ends `; quit`, omitted here.

`q1` (`before`, `after`): `$Q1_BASE; $ML_ON; adjust scrub luminance-nr 20 60 40 16 hold; wait 5; print ml; print viewport; snapshot …; wait 6; print ml; adjust scrub luminance-nr 60 60 1 16; wait 4; print ml; print viewport; ml off; wait 1; adjust reset all; wait 1`. `spinner true` three times on `before`, `false` three times on `after`.

`q1-wait` (`before`, `after`): `$Q1_BASE; $ML_ON; print ml; adjust scrub luminance-nr 20 60 40 16 hold; $(mlp 60) print frames; adjust scrub luminance-nr 60 60 1 16; wait 4; ml off; wait 1; adjust reset all; wait 1`.

`q1-newer` (`before`, `after`): `$Q1_BASE; $ML_ON; adjust scrub luminance-nr 20 40 20 16 hold; $(mlp 8) adjust scrub luminance-nr 40 70 20 16 hold; $(mlp 70) print frames; print ml; adjust scrub luminance-nr 70 70 1 16; wait 4; print ml; ml off; wait 1; adjust reset all; wait 1`.

`c1` (`before`, `after`): `$OPEN_LOUPE; focus RAW_00006; ml ready; windowsize 3008 1662; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 4; print frames; adjust temperature 6000; wait 2.5; print frames; print viewport; adjust temperature 5500; wait 2.5; print frames; print viewport; adjust temperature 6000; wait 2.5; print frames; print viewport; adjust scrub amount 40 90 120 16; wait 2.5; print frames; print viewport; adjust reset all; wait 1`.

`ff-slider` (`after`): `$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 3008 1662; wait 1; zoom; wait 4; print frames; adjust scrub amount 40 90 240 16; wait 3; print frames; print viewport; adjust amount 40; wait 2`.

`ff-crossing` (`after`): `$OPEN_LOUPE; focus RAW_00006; ml ready; windowsize 3008 1662; wait 1; adjust reset all; wait 2; zoom; wait 3; print frames; adjust exposure 0.5; wait 2; print frames; adjust scrub exposure 0.5 -0.5 300 16; wait 3; print frames; print viewport; adjust scrub exposure -0.5 0.5 300 16; wait 3; print frames; print viewport; adjust reset all; wait 2; adjust highlights 20; wait 2; print frames; adjust scrub highlights 20 -20 300 16; wait 3; print frames; print viewport; adjust reset all; wait 1`.

`maps` (`before`, `after`): `$OPEN_LOUPE; focus RAW_00006; ml ready; windowsize 1900 1000; wait 1; adjust reset all; $TYPICAL; wait 3; print frames; sharpenmap on; wait 3; print viewport; print sharpenmap; adjust scrub masking 20 30 10 16 hold; wait 1.5; print viewport; adjust scrub masking 30 30 1 16; wait 2; sharpenmap off; wait 2; print frames; print viewport; zoom; wait 3; adjust scrub amount 40 45 10 16 hold; wait 1; print viewport; sharpenmap on; wait 3; print viewport; print sharpenmap; pan 200 100; wait 0.6; pan 100 50; wait 1; print viewport; adjust scrub masking 20 30 10 16 hold; wait 1.5; print frames; print viewport; adjust scrub masking 30 30 1 16; wait 2; sharpenmap off; wait 2; print viewport; adjust fringe fill 1 purple; wait 1; fringemap on; wait 3; zoomstep; wait 2; zoomstep; wait 2; print loupe; print viewport; print fringe; fringemap off; wait 1; adjust reset all; wait 1`.

`tradeoff` (`before`, `after`): `$OPEN_LOUPE; focus RAW_00006; ml ready; windowsize 3008 1662; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 4; print frames; adjust temperature 6000; adjust scrub amount 40 90 200 16; wait 3; print frames; adjust temperature 5500; adjust scrub amount 90 40 200 16; wait 3; print frames; adjust temperature 6000; adjust scrub amount 40 90 200 16; wait 3; print frames; adjust temperature 5500; adjust scrub amount 90 40 200 16; wait 3; print frames; adjust scrub temperature 5000 6500 40 16; print frames; adjust scrub amount 40 90 200 16; wait 3; print frames; adjust scrub temperature 6500 5000 40 16; print frames; adjust scrub amount 90 40 200 16; wait 3; print frames; adjust reset all; wait 1`.

`tradeoff-masks` (`after`): `$OPEN_LOUPE; focus RAW_00006; ml ready; windowsize 3008 1662; wait 1; adjust reset all; adjust exposure 0.3; adjust contrast 15; adjust highlights -30; adjust shadows 25; adjust clarity 15; adjust vibrance 20; adjust amount 40; adjust mask add linear; $MASK; adjust mask add radial; $MASK; adjust mask add brush; adjust mask brush 0.1 0.1 0.3 0.3 0.5 0.4; $MASK; wait 4; zoom; wait 4; print frames; adjust temperature 6000; adjust scrub amount 40 90 300 16; wait 3; print frames; adjust temperature 5500; adjust scrub amount 90 40 300 16; wait 3; print frames; adjust scrub temperature 5000 6500 40 16; print frames; adjust scrub amount 40 90 300 16; wait 3; print frames; adjust reset all; wait 1`.

`tradeoff-rw2` (`after`, the RW2 copy): `$OPEN_LOUPE; focus P1040071; ml ready; windowsize 3008 1662; wait 1; adjust reset all; $TYPICAL; wait 3; zoom; wait 4; print frames; adjust temperature 6000; adjust scrub amount 40 90 200 16; wait 3; print frames; adjust temperature 5500; adjust scrub amount 90 40 200 16; wait 3; print frames; adjust scrub temperature 5000 6500 40 16; print frames; adjust scrub amount 40 90 200 16; wait 3; print frames; adjust reset all; wait 1`.

`campaign`, the timing script (one run per build per round, in the rounds' order; 4 arrivals, 4 commits, 2 commits with machine learning on; library photos RAW_00001 and RAW_00002 with the typical stack, RAW_00003 for commits, RAW_00004 with `ml on`):

```
$OPEN_LOUPE; focus RAW_00001; ml ready; windowsize 3008 1662; wait 1; zoom; wait 5;
print selection; print loupe; key right; $(hb 225) wait 0.5; print selection; print loupe; key left; $(hb 225) wait 0.5; print selection; print loupe; key right; $(hb 225) wait 0.5; print selection; print loupe; key left; $(hb 225) wait 0.5;
focus RAW_00003; ml ready; wait 3;
print selection; print loupe; adjust amount 55; $(hb 110) wait 0.5; print selection; print loupe; adjust temperature 6000; $(hb 110) wait 0.5; print selection; print loupe; adjust temperature 5500; $(hb 110) wait 0.5; print selection; print loupe; adjust amount 45; $(hb 110) wait 0.5;
adjust wb asShot; adjust amount 40; wait 2; focus RAW_00004; ml ready; wait 4;
print selection; print loupe; adjust amount 55; $(hb 180) wait 0.5; print selection; print loupe; adjust amount 45; $(hb 180) wait 0.5; adjust amount 40; wait 2
```

The first full pass had 5 runs throttled by App Nap or a covered window (heartbeats about 220 ms apart; detected by a median heartbeat over 40 ms), so rounds 2 and 3 were run again with `NSAppSleepDisabled` set on the four scratch identifiers only, and that setting was removed afterward. The numbers above use only unthrottled windows, equal counts per build.

`campaign3` (second pass, Q2): the scratch identifiers' preferences deleted, then six rounds per set on `baseline`, `baseline2` and `after`, with `hb(225)` as above:

```
$OPEN_LOUPE; <STATE>; wait 1; focus RAW_00001; ml ready; windowsize 3008 1662; wait 1; zoom; wait 5; print inspector;
print selection; print loupe; key right; $(hb 225) wait 0.5; print selection; print loupe; key left; $(hb 225) wait 0.5; print selection; print loupe; key right; $(hb 225) wait 0.5; print selection; print loupe; key left; $(hb 225) wait 0.5; print inspector
```

`<STATE>` is `inspector off` in the first set and `inspector on; tab adjust` in the second. Every log printed `inspector shown false tab adjust` or `inspector shown true tab adjust`, as set.

## For a person

The owner's list for sign-off. It covers this fix and everything left open in `docs/features/viewport-render-1to1/qa.md` (P1–P10 there, shown here as "was P…"). Each item says what is already passed by script. Set up a scratch library as the main session describes (step 5 of `docs/WORKFLOW.md`).

Q2's arrow-key check is gone: the second pass showed no difference from the baseline. Arrowing at 100% with the inspector open on Adjust costs about 0.23 s more than with it hidden on every build, which is the pre-existing follow-up above, not something to sign off here.

**In order of what matters most. P1–P4 are the ones worth doing. P5–P10 can be skipped or left open at sign-off by naming them.**

**P1. Detail while dragging (the owner's M1, was P1).** On a real 24 MP raw at 100% (`Z`), drag Sharpening's Amount, Radius and Detail, watching a fine edge. Then drag Luminance and hold still with the mouse down. *Pass:* the detail changes under your hand for Amount, Radius and Detail; for Luminance, the detail arrives while you hold, without letting go. Drag again, and the picture follows softly and never freezes or snaps to older values. After letting go, the settled image looks the same as the last sharp frame. *Already passed by script:* the frame-by-frame check on a slider and an Exposure crossing in this pass, and on the curve, wheels, mask handles and brush in `viewport-render-1to1/qa.md`, on a synthetic raw and the RW2 copy. A person is needed to judge how it looks.

**P2. The frame rate on the Dell (M9, was P2).** Maximized window, sidebar and inspector showing, a typical stack, at 100%. Drag Amount across its range; paint a brush stroke. *Pass:* an Amount drag reads as continuous at 6 to 7 frames a second; no spinner at the end of the drag; the stroke stays attached to the pointer. If it isn't acceptable, that's the follow-up in `viewport-render-1to1/status.md`, not a defect here. *Measured:* AC9, with no change to the frame path in this fix.

**P3. Machine learning at 100% (M4, was P3).** With machine learning on, at 100% on a real raw, drag Luminance and hold. *Pass:* the spinner with its machine learning label shows while the wait lasts, and goes when the detail lands, and stays gone (Q1). Change the value again during the wait; the spinner carries on and ends with the newest value. *Already passed by script* on the synthetic DNG on macOS 27 (`q1`, `q1-wait`, `q1-newer`). What's left is a real raw and the label on screen.

**P4. Letting go, and the swap (M5, M13, N2, AC10, was P5).** At 100% on a real raw: let go of White Balance with no pause, then of Amount, each followed by an arrow key or a pan within a second; then the same with machine learning on. Also start a new drag right after letting go of White Balance. *Pass:* the photo is never blank; after Amount the sharp frame stays until the full render replaces it; no fade and no shift at the swap (soft to sharp and back; Reduce Motion on and off); a fine edge doesn't move near the center or a corner; no spinning cursor after letting go or during a real three-mask drag; the first drag on a photo doesn't read as a blink; the new drag is soft for a moment, then sharp. *Already scripted:* stall figures (0.4–0.45 s after a commit; about 1.3 s with machine learning on, measured with the inspector open on Adjust); soft-to-sharp timing for the new drag (under 0.8 s). A person is needed for the feel.

**P5. The look of soft frames, the histogram and the curve (M2, M7, was P4).** At 100% and 400% on a real photo, drag White Balance and pan right after. *Pass:* no stair-stepped blocks in a soft frame; at 400% a settled photo shows real pixels as blocks. During a drag at 100%, the histogram and the curve's backdrop hold, never blank or dim, and catch up on a pause. A pan leaves them alone; at Fit they stay live. *Already passed by script:* soft frame vs sharp at 400% on an edge, histogram hold/catch-up (viewport-render-1to1 `m2`, `ac11`). *May be skipped* if P1 and P2 looked right.

**P6. The 100% boundary and the spinner (M3, M6, was P6).** Reach 100% by `Z`, the toolbar, ⌘=, and a pinch that selects the 100% segment: real pixels each time. A pinch stopping just below 100% is soft; say whether that's a trap. Hold White Balance still: if a spinner shows, its tooltip is "Refining the photo"; after letting go with no pause no spinner shows (known, L1). *Already passed by script:* `Z`, ⌘=, 97% not covered and soft, 99.5% covered and sharp; spinner timing (viewport-render-1to1 `m3`, `m6`). *May be skipped.*

**P7. Maps and handles (M11, M12, was P7).** At 400%, a refined Sharpening Map, a Fringe Map and the preview while replacing a pick show blocks, as on `develop`. With a linear or radial mask at 100%, handles stay over the sharp frame during and after a drag, after resizing the window and after entering and leaving review; the brush cursor too. *Already passed by script:* Sharpening and Fringe Maps `nearest true` at 400%; handles over the tile after a resize and review (`m11`, `m12`, `maps`). *Left:* the replaced-pick preview and the brush cursor. *May be skipped.*

**P8. Keyboard step on a slider (AC4, was P9).** Focus a slider with the keyboard and step it with the arrow keys at 100%. *Pass:* each step ends on a sharp frame of the current value. *May be skipped:* same path as a typed value, which passed by script.

**P9. VoiceOver (M8, was P8).** At the swap from soft to sharp nothing is announced; a slider speaks its value; the spinner reads its label. *Already passed by script:* nothing announced, the image and its actions present. *May be skipped* unless you use VoiceOver.

**P10. HDR, only if you have an extended-range display (M10, was P10).** An HDR photo at 100%: no HDR badge during a drag; it returns when the HDR rendition lands; after that a rating key doesn't bring a standard-range tile back. Not run here. *May be skipped* if you have no such display.

## Follow-up

- 2026-11-09, second pass at `fdc87c4` (no source change since `d4a28d0`): Q2 re-measured with the inspector state pinned. Withdrawn: not a regression. It came from inspector state saved by my own `maps` run. P3 (arrow keys) removed from the owner's list. The pre-existing Adjust-tab rebuild is listed for the product manager.
