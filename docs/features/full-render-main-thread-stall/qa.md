# Full render main thread stall: QA

Owner: qa-tester. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Tested: `bug/pre-hdr-merge-fixes` at 072518d (the fix is 23c71f4 with the review fixes in 072518d;
the branch also carries #73's 476d6a9, QA'd in `docs/features/dehaze-above-white/qa.md`), on a
MacBook Pro (Mac16,8, Apple M4 Pro), macOS 27.2.1 (26B131), macOS 27.2 SDK (the bundle records
`sdk 27.2`, `minos 15.0`). The "before" is 476d6a9, the commit just under the fix, built in a scratch
clone outside the checkout, so #73's change is in both builds and only #65's differs.

Issue: #65. A bug fix: the criteria are the **Bug** section of `status.md` (steps, expected and actual,
root cause, the tests that fail without the fix), the issue, and the owner's ruling of 2026-11-15
(option B: render into an IOSurface off the main thread, keep today's time to sharp).

## Verdict

Passes. On release bundles the longest main-thread gap per arrival at 100% fell from 349-436 ms to
23-49 ms (one gap of 171 ms in 16), per saved change from 375-444 ms to 29-69 ms, and with machine
learning noise reduction on from 1237-2388 ms to 34-66 ms, with the time to sharp unchanged. The two
tests that fail without the fix do, and `swift test` passed three times in a row. One check needs a
person (P1), and the designer's review of the spinner, which `status.md` says now shows after a White
Balance release, has not been written (see Design question D1).

## Acceptance criteria

| AC | How | Evidence | Result |
|---|---|---|---|
| B1: arriving at a photo at 100% (→ / ←) no longer blocks the main thread for about 0.4 s | Script | Script 1 (`arrive`, 16 arrivals per build): before 349-436 ms, after 23-171 ms (15 of 16 at 23-49 ms). Median heartbeat 21.5-21.7 ms in every run, so nothing was throttled | Pass |
| B2: a saved change (Amount, Temperature) no longer blocks it | Script | Script 1 (`commit`, 16 per build): before 375-444 ms, after 29-69 ms. The 30-65 ms on both is the save's own work (the engineer's note; consistent here) | Pass |
| B3: with machine learning noise reduction on (1.3-2.7 s before) | Script | Script 1 (`mlcommit`, 8 per build): before 1237-2388 ms, after 34-66 ms | Pass |
| B4: the rendition is rendered where it is made, not by Core Animation's first draw | Test | `DeferredRenderTests.renderedWhereMade`. On a scratch copy of 476d6a9 with the test added and `makeSurfaceImage` shimmed to the old deferred `makeCGImage` call it fails with 2 issues (`pulled > 0`, and the re-read); passes on the branch (3 runs) | Pass |
| B5: Core Animation's draw of the rendition is the old screen within one level, and the rendition's own pixels pass through | Test | `DeferredRenderTests.matchesCoreAnimationsRender` (24 MP synthetic raw, typical stack, radial mask, vignette; with a control that a bitmap render differs by more than one level). With the old deferred route shimmed in, it fails ("not drawn as rendered"); passes on the branch. I did not rerun the engineer's bitmap-route failure (3146 rows) | Pass |
| B6: Core Animation renders an unread deferred image at its draw and not one read first, the HDR rendition included (why HDR keeps its deferred call) | Test | `DeferredRenderTests.coreAnimationRendersDeferredImages` (3 runs) | Pass |
| B7: the time to sharp after a change is kept (ruling: not the bitmap route's +0.7 s) | Script | Script 2 (`commitpoll`, `wbpoll`, `mlpoll`), table below: after Amount 381-472 ms against 367-425; White Balance release 420-492 against 396-443; machine learning on 1289-2063 against 1268-2060. Within the run-to-run spread, the White Balance release perhaps 40 ms later (n=4) | Pass |
| B8: the 100% frame still shows the photo, sharp and not blank | Script | Script 3: snapshots after arrival at 100% looked at (photo present, `viewport` says covered, no live frame, no tile, no spinner); the two builds' snapshots of the same state differ in 26 pixels by at most 5 of 255 levels | Pass |
| B9: the loupe's spinner after a raw setting is let go is as the designer expected (design 2.1, shown after 0.5 s) | Script | Script 2: after a White Balance release the spinner shows in 4 of 4 changes, from about 1.05 s to 1.13-1.30 s after the change started (82-256 ms on screen); after Amount, never (4 of 4); before, never. The UI changed in that sense, so the designer's review applies (D1) | Open |
| B10: the user guide says it | Read | `docs/USER_GUIDE.md` Editing at 100% gained the spinner-after-letting-go and no-pause sentences | Pass |
| B11: the window keeps responding at 100% on a real display, arrowing through photos | Person | P1 | Open |

## Findings

None for the engineer: no failure and no missing test.

**D1 (Design question, for the designer, via the main session).** `status.md` says the spinner now shows
after letting go of a raw setting at 100% when the full rendition takes over half a second from the last
input, and that "the designer's review applies". `docs/features/full-render-main-thread-stall/` has no
`review.md`. Script 2 shows the behavior (4 of 4 White Balance releases, 82-256 ms on screen, none
after Amount). Nothing for me to judge beyond that it is as `status.md` and the viewport-render-1to1
review (L1) describe.

Observations (not failures):

- **O1: one arrival gap of 171 ms.** In round 1 the branch had one arrival (the third of eight) with a
  171 ms gap; the other 15 were 23-49 ms, and no `commit` or `mlcommit` gap passed 69 ms. Before, no
  arrival was under 349 ms. Not reproduced; recorded in case it shows again (`$Q/logs/c1-Branch-arrive.log`).
- **O2: toolbar shows "Fit" at 100%.** In the branch's scripted snapshot the toolbar's zoom label reads
  "Fit" while `viewport` and the heartbeat say magnification 1.000. This matches the engineer's note on
  the scripted first `Z` (possibly #153); I saw it only in the branch's snapshot and did not look for it
  on the before. The measurements all report magnification 1.000.
- The measurement shows the main thread, not whether the commit, with the surface-backed image, costs
  more elsewhere. The engineer measured its draw at 10-15 ms against about 5 ms; I did not repeat the
  headless draw timing or the memory footprint (the engineer's table: 628 and 629 MB after, 619-716 MB
  before).

## Scripts

All run from `/private/tmp/claude-501/-Users-randy--claude-spares-spare-BGdTA8/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad/qa`
(`$Q`). Two release bundles, `Scripts/build-app.sh` in each tree: **Before65** from a clone at 476d6a9
(`$Q/before65`) and **Branch** from the checkout at 072518d. Each was copied to `$Q/app/<name>.app`, its
identifier set with `plutil -replace CFBundleIdentifier -string me.sesser.gus.debugqa`,
`NSAppSleepDisabled` inserted, signed with `codesign --force --deep --sign -`, and launched as
`$Q/app/<name>.app/Contents/MacOS/Gus --library-root $Q/lib --debug-script "<script>"` (every launch with
`--library-root`). The library `$Q/lib` is `photobench generate --dng 4 --dng-size 6000x4000 --jpeg 2
--jpeg-size 3000x2000` with the HEICs removed, then `photobench import`. The measuring scripts are the
engineer's (viewport-render-1to1 method, `.../scratchpad/tools/mkscript.py`), with the two raws renamed
to my library's (`RAW_00003`, `RAW_00004`); copies and my driver are in `$Q/tools65/` (`mkscript.py`,
`campaign.zsh`, `gaps.py`, `poll.py`, `sharp.py`, `ts.py`). The display was not checked to be asleep or
awake; the stall shows either way (the engineer's note).

Common start (`mkscript.py`, `pre`): window 3008 x 1662, inspector off, a typical stack on both raws, 100%:

```
wait 2; inspector off; loupe; wait 1; focus RAW_00004; ml ready; windowsize 3008 1662; wait 1; adjust reset all; <TYPICAL>; wait 3; focus RAW_00003; ml ready; adjust reset all; <TYPICAL>; wait 3; key z; wait 2; key right; wait 3; key left; wait 4; print loupe; print viewport
```

where `<TYPICAL>` is `adjust exposure 0.4; adjust contrast 15; adjust highlights -30; adjust shadows 25;
adjust whites 10; adjust blacks -5; adjust clarity 20; adjust dehaze 10; adjust vibrance 15; adjust
saturation 5; adjust curve rgb 0,0 0.3,0.25 0.7,0.78 1,1; adjust grade shadows 210 20; adjust grade
highlights 40 15; adjust amount 40; adjust radius 1; adjust detail 25; adjust masking 20`, and the end is
`print viewport; print frames; adjust reset all; focus RAW_00004; adjust reset all; ml off; wait 1; quit`
(the scratch library is left with no edits).

### Script 1: longest main-thread gap per event (heartbeat)

Each event is a marker (`print selection`) just before it, then 90 heartbeats, `print loupe; wait 0.02`
(20 ms), stamped as they arrive (`ts.py`); `gaps.py` reports the longest gap per event, 80 ms taken off
a gap that spans a `key`:

- `arrive`: `print selection; key right; <heartbeats>; wait 1.5`, then `left`, alternating, 8 events.
- `commit`: `print selection; adjust amount 55; <heartbeats>; wait 2`, then `adjust amount 45`,
  `adjust temperature 6000`, `adjust temperature 5500`, twice, 8 events.
- `mlcommit`: the same after `ml on; wait 6`, `adjust amount 55` and `45` twice, 4 events.

Two rounds, build order reversed in round 2 (`campaign.zsh`); every heartbeat line reads magnification 1.000.

| Case | Before65 (476d6a9) | Branch (072518d) |
|---|---|---|
| Arrival at a photo, 16 | 349-436 ms | 23-171 ms (15 of 16 at 23-49 ms) |
| Saved change, 16 | 375-444 ms | 29-69 ms |
| Saved change, machine learning on, 8 | 1237-2388 ms | 34-66 ms |

### Script 2: time to sharp, from `poll.py` (`print viewport` every 20 ms)

`commitpoll`: `print selection; adjust amount 55; <120 x (print viewport; wait 0.02)>; wait 1`, then
`adjust amount 45`, twice, 4 changes per round (2 rounds); `wbpoll`: `adjust scrub temperature 5000 6500 30
16` then `adjust scrub temperature 6500 5600 30 16`, twice, 4 changes (1 round); `mlpoll`: as `commitpoll`
after `ml on; wait 6` (1 round, 4 changes). "Sharp" is when the wait for the full rendition ends, or
the stall behind it (before: the stall; the wait clears at once and Core Animation renders at its
draw). Milliseconds after the wait began:

| Case | Before65 | Branch | Longest gap, before / after | Spinner, before / after |
|---|---|---|---|---|
| Amount, no pause (8) | 367-425 (median 418) | 381-472 (median 423) | 367-405 / 34-68 | never / never |
| White Balance drag let go (4) | 396-443 (median 441) | 420-492 (median 481) | 381-422 / 31-39 | never / 4 of 4 (82-256 ms on screen) |
| Amount, machine learning on (4) | 1268-2060 | 1289-2063 | 1246-2038 / 35-69 | never / never |

### Script 3: the 100% frame (`mkscript.py snap`)

After the common start, `key right; wait 3; print selection; snapshot <a>.png; print selection; snapshot
<b>.png; print selection; print viewport`, then `left`, alternating, 3 rounds. I looked at the last
Branch snapshot: the photo's content fills the loupe (a synthetic raw at 100%), the film strip below, glass
panes blank as `CLAUDE.md` says. `viewport covered yes magnification 1.000 ... live no tile none region
frame none spinner no`. `snapdiff` between the builds' snapshots of the same state: 26 pixels over 2 levels,
worst 5; between the Branch's own two snapshots: identical.

### Tests

`swift test` on the checkout, three times in a row (`$Q/test-1.log` to `test-3.log`): 1040 tests in 155
suites passed after 69.4, 69.7 and 67.6 s; no failed expectation, no known issue. The engineer's five runs
at 072518d also passed; the code review's five runs before it passed three times and failed twice, both
on C1, which 072518d fixed. `DeferredRenderTests` passed in each of mine (suite 67.6-69.4 s,
serialized). Without the fix: a scratch clone of 476d6a9 with `DeferredRenderTests.swift` added and
`$Q/before65/Tests/PhotoCoreTests/OldSurfaceShim.swift` (an extension giving `makeSurfaceImage` the old
deferred call) fails `renderedWhereMade` (2 issues) and `matchesCoreAnimationsRender` (the pass-through
check), log `$Q/before65-deferredtests.log`. `Scripts/build-app.sh all` succeeded
(`$Q/build-all.log`).

## For a person

- **P1 (B11).** At 100% on an awake display, on a real 24 MP raw (a copy of a library, or a scratch library),
  arrow through ten photos: the window keeps responding (no hitch, no spinning cursor) and each photo turns
  sharp about as fast as on `develop`. With machine learning noise reduction on (macOS 27), the same: the
  window keeps responding, though the photo you stop on may stay soft for up to one extra 1.3-2 s render
  after several quick arrows (code review C2). Say whether that is acceptable. Needs a person because the
  scripts time the main thread, not the feel; the display here may be asleep, and this is the owner's one
  real check for #65. No M-number: no design review has been written for this fix (D1).

Not asked: VoiceOver, macOS 15 or macOS 26 (the owner does not test them).

## Follow-up

Reruns after fixes and the owner's sign-off are recorded here.

Run safety: no instance of the app was left running. The owner's library folder had one file newer than my
start, `catalog.sqlite-shm`, from `photocli render <file> --out ...` runs without `--library-root` during
#73's checks (they open the standard library read-only to refuse a master as an output); `catalog.sqlite`
and `-wal` kept their times and sizes. See `docs/features/dehaze-above-white/qa.md`. The app was only ever
launched with `--library-root`.

### Second pass: d29424f and bb27fda (the owner's finding, and C3)

Date: 2026-11-15. Tested: `bug/pre-hdr-merge-fixes` at `bb27fda`, same Mac and SDK as above (macOS
27.2.1, `sdk 27.2`, `minos 15.0`). Since 072518d the branch gained `d29424f` (the loupe and the comparison
pane size the photo on arrival from the rendition's size, learned without rendering:
`PreviewGenerator.outputSize`, `PreviewService.outputSize`, `LoupeArrivalSize`) and `bb27fda` (code review
C3: a cancelled neighbour prefetch starts no size read). Criteria: the owner's finding in `status.md`
("the photo jumps down and to the left by about 25-50 px at 100% on arrow keys, Sony ARW") and review
finding C3.

**Verdict, second pass.** Passes. At 100% on real raws the image view's size is the rendered size from the
first poll to the last (24 of 24 arrivals on three kinds of raw, ARW, ORF and RAF, against 16 of 24 that
resized on the build without the fix), the comparison pane no longer changes its visible rect when its
full rendition lands, and the earlier numbers hold on the final build: longest main-thread gap per arrival
23-43 ms (before 441-484), per saved change 34-81 ms (before 462-547), time to sharp unchanged (519-624
ms against 522-594). `swift test` passed twice on `bb27fda`, 1045 tests each, and the new C3 test fails
without its guard. The owner has checked the arrow-key arrival by hand on `d29424f` (below). Nothing new
needs a person.

| AC | How | Evidence | Result |
|---|---|---|---|
| F1: at 100% an arrow key lands the photo at its rendered size and it does not resize or move when it turns sharp (Sony ARW) | Script | Script 4: ARW, 8 arrivals per build. Before (476d6a9): 8 of 8 resized, 3024 x 2012 at 83-91 ms then 3000 x 2000 at 134-322 ms. Final: 8 of 8 steady at 3000 x 2000 from the first poll (85-89 ms) | Pass |
| F2: the same on an Olympus ORF (catalog 4640 x 3472, rendered 4608 x 3072) | Script | Script 4: before 8 of 8 resized, 2320 x 1547 then 2304 x 1536 at 150-334 ms. Final: 8 of 8 steady at 2304 x 1536 | Pass |
| F3: a file whose metadata is right is unchanged (Fujifilm RAF, rotated or not) | Script | Script 4: RAF, 2448 x 1632, steady on both builds, 8 of 8 each | Pass |
| F4: the size is the rendition's, not the file's, and is learned without rendering | Test | `OutputSizeTests` ("Full rendition size before rendering", 5 tests), run with `CAMERA_RAW_SAMPLE` set to each of my ARW, ORF and RAF in turn: all 5 pass each time (the real-raw case "A real camera raw is sized as it renders" included; it is skipped without the variable, so a plain `swift test` does not run it). Cropped and turned raw, rotated JPEG, untouched raw, no size for a video | Pass |
| F5: a jump to a photo not visited (arrow or `focus`) shows the right size at once, or corrects once and early | Script | Script 4, `jump`: within a project (ORF to ORF, 3 apart) and across projects (ARW to ORF): final: ORF to ORF steady at 2304 x 1536, ARW to ORF at 2304 x 1536 from its first state after the jump (63 ms), no intermediate size; before: 2320 x 1547 at 62-70 ms then 2304 x 1536 at 317-324 ms in both. The engineer saw one early correction (about 0.1 s) on a first visit; I did not see it here | Pass |
| F6: a film strip click arrives at the rendered size | Script | Script 5: four clicks (ORF, RAF, ARW, ARW) at 100%, final: bounds 2304 x 1536, 2448 x 1632, 3000 x 2000, 3000 x 2000 and steady for 1.3 s after each. The click command itself waits 400 ms before the poll starts, so the first 0.4 s (where the early correction would be) is not seen; the arrow and `focus` runs cover that window through the same `show(index:)` | Pass (arrival after 0.4 s) |
| F7: Compare (S) arrives without a jump | Script | Script 6: two ARWs side by side at 100% (`compare on`, `key z`), then `key right` and `key left` (replace the active pane's photo), `print compare` every 20 ms. Final: the arriving pane's visible rect is 0.2690,0.2735 0.4620x0.4530 and fit 0.429 at the preview and unchanged when the full rendition lands (263 ms). Before: 0.2750,0.2719 and fit 0.426 at the preview, then 0.2772,0.2675 and fit 0.429 at the full rendition (the jump), both arrivals; and its left pane sat at 0.2732,0.2705 against 0.2690,0.2735 centred | Pass |
| F8: the stall fix is not undone: gap per arrival, per saved change, time to sharp | Script | Script 7 (real ARW pair, typical stack, release bundles): see the table | Pass |
| C3: a cancelled neighbour prefetch starts no size read | Test | `OutputSizeTests` "A cancelled caller starts no size read". In a scratch clone of the branch (`$Q/nofix-c3`, outside the checkout) with `PreviewService.swift` and `LoupeView.swift` put back to `d29424f`: the test fails with 3 issues (`cancelled == nil`, `loads == 0`, the size cached), log `$Q/nofix-c3-test.log`; passes on `bb27fda`. Read: it cancels the caller before the call and counts stack loads. It tests `outputSize`'s entry guard; the held-arrow case in `LoupeView` (the two `Task.isCancelled` guards) has no test of its own, only the review's reading | Pass |
| Memory, spinner, user guide, tests of 072518d | | as above; not repeated | |

**Script 7 numbers** (8 arrivals and 8 saved changes per build, two rounds, build order reversed in the
second; every heartbeat line reads magnification 1.000; median heartbeat 21.5-22.4 ms everywhere):

| Case | Before65 (476d6a9) | Final (bb27fda) |
|---|---|---|
| Longest main-thread gap, arriving at a photo (16) | 441-484 ms | 23-43 ms |
| Longest gap, saved change (Amount 55/45, Temperature 6000/5500; 16) | 462-547 ms | 34-81 ms |
| Time to sharp after an Amount change (8): wait began to sharp in | 522-594 ms (median 552) | 519-624 ms (median 566) |
| Spinner | never | never (Amount) |

The extra 14 ms in the median and the 30 ms at the top are inside the spread between runs on either
build (the 072518d pass saw the same). The numbers are higher than the synthetic DNG's (about 420 ms to
sharp) because a real 24 MP ARW decodes slower. Machine learning noise reduction and White Balance
releases were not rerun: `d29424f` and `bb27fda` change nothing on those paths and a short sample was asked.

**Owner's sign-off check, recorded as relayed by the main session.** On 2026-11-15 the owner checked a Sony
ARW and two Panasonic RW2 files by hand, arrow keys at 100%, on the build of `d29424f`: no jump, and the
sharpness arrives quickly. The owner approved that version. `bb27fda` was added after (a cancellation guard;
no visible behavior change) and is not part of what the owner looked at; this pass covers it by the C3 test,
the full suites and the runs above. Commit signed off: `d29424f`. Branch head now: `bb27fda`.

Checks left open: P1 in part. The owner's hand check covers P1's arrow-key half (responsiveness and speed
to sharp through several photos at 100%); the machine-learning half (macOS 27, quick arrows, whether the
photo you stop on staying soft for up to one extra 1.3-2 s render is acceptable, code review C2) was not
reported, so it stays open. D1 (the designer's view of the spinner after a White Balance release) is not
answered in `qa.md` by me. No new P items.

#### Scripts, second pass

Same setup as above: bundles `$Q/app/Before65.app` (476d6a9, from the first pass) and `$Q/app/Final.app`
(`Scripts/build-app.sh all` on `bb27fda`, copied, identifier `me.sesser.gus.debugqa`,
`NSAppSleepDisabled`, ad hoc signed), every launch
`Gus --library-root <scratch library> --debug-script "…"`. Two scratch libraries made with `photobench
import` from copies (not the originals) of the ARWs the engineer copied (three Sony ARWs) and files from
`~/gus-scratch/photos`: `$Q/libfinal` (the three ARWs, four ORFs `10M10287`-`10M10290` and four RAFs
`X1000558`, `X1000564`, `X1000565`, `X1000570`: 11 photos) and `$Q/libarw` (the three ARWs). Window 3008 x
1662, inspector off, the display state not checked. Tools in `$Q/toolsfinal/` (`arrival.py` and
`arrivals.py` are the engineer's, `mkscript.py`, `gaps.py`, `poll.py`, `ts.py` are the first pass's, with
my photo names; `run.zsh`, `camp.zsh`, `cmp.py` are new). Logs in `$Q/logsfinal/`.

- **Script 4, arrival size** (`run.zsh <build> <name> <photo> [jump <photo>]`, `libfinal`). The script
  `arrival.py <photo> 100` prints
  `wait 2; inspector off; loupe; wait 1; focus <photo>; windowsize 3008 1662; wait 2; key z; wait 2; key right; wait 3; key left; wait 4`
  then four times (`right`, `left`, `right`, `left`): `print selection; key <k>; <60 x (print loupe; print
  viewport; wait 0.02)>; wait 1.5`, and for `jump <far>`: `print selection; focus <far>; <60 x …>; wait 1.5`;
  then `quit`. `arrivals.py` lists each distinct image view size (the viewport line's `bounds`) per event
  with the time it appeared. Photos `DSC00328` (ARW, twice with `DSC00329`), `10M10287` (ORF), `X1000558`
  (RAF), each twice per build (8 arrivals), the jumps `10M10287` to `10M10290` and `DSC00328` to `10M10289`.
  Results in F1, F2, F3, F5. Sample (ARW, before): `event 0: MOVES 83 ms bounds 3024x2012 ...; 150 ms
  bounds 3000x2000`; (final) `event 0: steady 88 ms bounds 3000x2000`. The `visible` origin in these lines
  is `print loupe`'s and I do not read anything into the 5-7 point difference between the builds.
- **Script 5, film strip** (`$Q/toolsfinal/filmstrip.script`): the pre-roll above for `DSC00328` (focus
  index 8 of 11), then `print selection; filmstripclick <n>; <60 x poll>; wait 1.5` for n = 1, 5, 10, 8
  (all 11 cells on screen, `print filmstrip` visible 0..<11), `quit`. Both builds: no click refused
  (`film strip cell … not on screen` never printed), every state steady for 1.3 s after the first poll
  at 403-420 ms; sizes as in F6.
- **Script 6, Compare** (`$Q/toolsfinal/compare.script`): pre-roll as above without `key z`, then
  `compare animate off; compare on; wait 3; key z; wait 4; print compare; print selection; key right; <60 x
  (print compare; wait 0.02)>; wait 2; print compare; print selection; key left; <60 x …>; wait 2; print
  compare; compare off; wait 1; quit`. `cmp.py` prints each pane's state when it changes
  (magnification, fit, rendition `preview` or `full`, visible unit rect). Result in F7. Compare left on
  and off cleanly on both builds.
- **Script 7, gaps and time to sharp** (`camp.zsh`, `libarw`): the first pass's `arrive`, `commit` and
  `commitpoll` scripts (`mkscript.py`, with `DSC00329` and `DSC00328` for the two raws, typical stack on
  both, `key z`), round 1 Before65 then Final, round 2 the reverse. `gaps.py` for the first two, `poll.py`
  for the third.

#### Tests, second pass

- `swift test` on the checkout at `bb27fda`, twice in a row (`$Q/final-test-1.log`, `-2.log`): 1045 tests in
  156 suites passed both times (71.1 and 70.6 s), no failed expectation, no known issue. No flakiness seen,
  `DeferredRenderTests` (70-71 s) and `matchesCoreAnimationsRender` included.
  (The first-pass runs of 072518d: 1040 tests, 3 of 3.)
- `Scripts/build-app.sh all` succeeded (`$Q/final-build-all.log`); `vtool -show-build` on the bundle:
  `sdk 27.2`, `minos 15.0`.
- Goldens: no file under `Tests/PhotoCoreTests/Goldens` differs from 476d6a9 (`git diff --stat 476d6a9 HEAD`
  is empty there), `UPDATE_GOLDENS` not run, `Goldens` and `Golden harness` suites passed in both runs.
- `EstimateEdgeTests` (#73): suite "Whole-frame estimates at the frame's edge" passed in both runs; see
  `docs/features/dehaze-above-white/qa.md`.
- `OutputSizeTests` with `CAMERA_RAW_SAMPLE` set to an ARW, an ORF and a RAF: 5 of 5 each.

Run safety, second pass: no instance of the app was running when I finished (`pgrep -x Gus` empty; the
owner's own `checkbranch` copy was not running at any time I looked, and I started nothing of it). Every
launch carried `--library-root` on `$Q/libfinal` or `$Q/libarw`. One slip: in one batch my driver passed no
photo name, so the script was empty and each of the 10 launches stayed up with no work; each had
`--library-root $Q/libfinal` and I ended them by process ID. The owner's library folder
(`~/Library/Application Support/Gus/Library`) had no file newer than 20:27, when I started
(`catalog.sqlite` 07:09, `-shm` 18:55, `-wal` 07:09, `library.lock` 08:24).
