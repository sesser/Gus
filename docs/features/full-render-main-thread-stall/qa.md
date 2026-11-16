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
