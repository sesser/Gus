# DeferredRenderTests fails intermittently in full runs: QA

Owner: qa-tester. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md` (bug fix, issue #229).
Tested: `bug/deferred-render-flake` at `192f4dd` (fix `8e33ead`, status `57acf76`, code review `192f4dd`; first pass) and at
`d887683` (test rewritten in `0a5978c`; rerun, see Follow-up),
on an Apple M4 Pro, macOS 27.2.1 (26B131), Xcode SDK 27.2. The machine was shared with other agents'
builds and tests throughout (load averages 5 to 17). No app was launched (the fix changes no UI), so the
owner's library and caches were never opened: nothing under `~/Library/Application Support/Gus` or
`~/Library/Caches/Gus` is newer than the start of this run, and no instance of mine is running.

## Verdict

Ready for the owner's sign-off, as of the rerun on `0a5978c` (code review second pass `d887683`; see
Follow-up). The first pass (`192f4dd`) did not pass: its test was flaky (Q1). The first-pass numbers below
are kept as the record. After the engineer's rewrite, with the fix 25 of 25 suite runs and 2 of 2 full runs
pass, and without the fix 25 of 25 suite runs fail at the HDR check. Only P1 (optional) is left for a person.

## Acceptance criteria

The Bug section of `status.md` has no numbered criteria; B1 to B8 are its claims, in order.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| B1. Full `swift test` no longer fails in `DeferredRenderTests` (steps 1) | Test | Full runs on the branch: run 1 passed (1243 tests, 73.2 s); run 2 failed with one issue, `DeferredRenderTests.swift:184` (the new control), nothing else (log `scratchpad/logs/full-2.log`). The old failing lines 150 and 158 did not occur | Fail on `192f4dd` (Q1); Pass on `0a5978c`: 2 of 2 full runs passed |
| B2. The test is deterministic (expected, first sentence) | Test | `DeferredRenderTests/hdrRenditionOwnsItsPixels`, suite alone with the fix, 25 runs: 22 passed, 3 failed at line 184 (control "Core Image kept a read deferred image's pixels through other renders") | Fail on `192f4dd` (Q1); Pass on `0a5978c`: 25 of 25 passed |
| B3. The test fails without the fix (Test that fails without the fix) | Test | Scratch copy of `192f4dd` with develop's `RenderEngine.swift` (`9002877`), suite alone, 13 runs: 8 failed at the HDR check (line 189), 2 failed at the control (line 184), 3 **passed** (runs 3, 12, 13) | Fail on `192f4dd` (Q1); Pass on `0a5978c`: 25 of 25 failed at the HDR check (line 216) |
| B4. The HDR rendition is rendered where it is made and never again by Core Animation, whatever else renders (expected, second sentence) | Test | With the fix the HDR check (line 189) never failed in 25 suite runs and 2 full runs; `makeHDRCGImage` backs the image with a `CFData` that has no way back to the source (read in `RenderEngine.swift:184-198`). `hdrPulled > 0` shows it renders before returning. Behavior holds; the test's detection is the problem | Pass |
| B5. Same render: pixels, format, color space and headroom tag unchanged by the fix | Test | Scratch probe (script 3): a 5472 x 3648 HDR image with a patch at (4, 3, 2) gave identical size, bits (16/64), bytes per row, bitmap info, color space (extended linear Display P3), headroom (4.0), byte count and an FNV-1a hash of all pixels on develop's `makeHDRCGImage` and on the branch's | Pass |
| B6. `coreAnimationRendersDeferredImages` still shows Core Animation renders an unread deferred image (the old stall) after its second half was removed | Test | `DeferredRenderTests/coreAnimationRendersDeferredImages`, passed in every run; `renderedWhereMade` (the SDR route, #65) and the within-one-level comparison also passed in every run | Pass |
| B7. The other HDR users are unchanged | Test | `swift test --filter "SharpeningMapTests\|PreviewTests\|StalePreviewTests\|LinearRawDecodeTests\|LiveSessionTests\|ComparisonTests\|HDR"`: 96 tests in 13 suites passed, including `hdrRenditionsKeepHighlightsAboveWhite`, `noHDRRenditionWhileClampingTablesAreActive`, "The HDR rendition is not kept under a hash the loaded stack does not have" and `SharpeningMapTests` (calls `makeHDRCGImage`) | Pass |
| B8. No rendering, golden, migration or UI change | Test | `git diff 9002877..HEAD -- Sources Tests` touches `RenderEngine.swift` and `DeferredRenderTests.swift` only; the 1242 other tests, goldens included, passed in both full runs | Pass |
| B9. The stall the fix removes (HDR photo over 4096 px at 100%, other renders, then back to it) | Person | P1 (optional) | Open |

## Findings

**Q1 (Fixed in `0a5978c`, confirmed in Follow-up). `hdrRenditionOwnsItsPixels` is flaky on the fixed branch and does not always fail without the fix.**
Found: the test's control (lines 181 to 185) requires that 96 other renders make Core Image render a
read, deferred image again. That is Core Image's process-wide surface pool and is not deterministic.
- Steps: `swift test --filter DeferredRenderTests` on the branch, repeated (script 1); or a full `swift test`
  (script 2).
- Expected: passes every time with the fix; fails every time with develop's `makeHDRCGImage`.
- Actual, with the fix: 3 of 25 suite runs fail at `DeferredRenderTests.swift:184` ("Core Image kept a
  read deferred image's pixels through other renders on Version 27.2.1 ...: this test can't tell whether
  the HDR rendition holds its own and needs revisiting"); 1 of 2 full runs failed the same way (3.96 s
  in that run, load 16 to 17 at its start).
- Actual, without the fix: 8 of 13 runs failed at the HDR check (as the engineer recorded), 2 failed at
  the control, and 3 passed, so the test missed the bug.
- Why it matters: the 184 failure is the same kind of intermittent full-run failure as the one in the
  issue, now in the fixed code's test, and it blocks CI the same way. The 10 of 10 and 8 of 8 in `status.md`
  were not reproduced here; the difference is load or timing, which is the problem.
- For the engineer (a suggestion, not a requirement): make the pressure adaptive rather than a fixed 96, for
  example make the other renders in rounds of 16 until the control's source is asked again (a cap of a
  few hundred, then `Issue.record` or skip with the "needs revisiting" message only if the cap is reached),
  and check the HDR rendition after the control has been seen to be reclaimed. That keeps the HDR check
  meaningful on every run and removes the dependence on one count. Re-measure with at least 25 suite runs
  and two full runs, with the fix (all pass) and without it (all fail at line 189).

No other findings. Nothing for the designer or product manager.

## Scripts

All commands run from `/Users/randy/Projects/Gus/.claude/worktrees/deferred-render-flake` unless noted.
Logs are in the session's scratch folder, `.../scratchpad/logs/`.

1. The suite alone, with the fix (3 runs, then 22 more with `--skip-build`):
   `swift test --filter DeferredRenderTests`
   Result: 22 of 25 passed; 3 failed at line 184 (runs 4, 13, 19 of the second batch).
2. Full runs:
   `swift test` (run 1) then `swift test --skip-build` (run 2).
   Result: run 1, 1243 tests in 177 suites passed in 73.2 s; run 2, 1 issue, line 184, 69.0 s. These are the
   two full runs of this QA.
3. Scratch copy without the fix, outside the checkout:
   `git archive HEAD | tar -x -C <scratch>/develop-copy`, then
   `git show 9002877:Sources/PhotoCore/Preview/RenderEngine.swift > <scratch>/develop-copy/Sources/PhotoCore/Preview/RenderEngine.swift`
   (checked identical to develop's), then in that folder 13 runs of
   `swift test --filter DeferredRenderTests` (the first with a build, the rest `--skip-build`).
   Result: 8 failed at 189, 2 at 184, 3 passed.
4. Probe, scratch copy only (`<scratch>/probe/HDRProbeTests.swift`, copied into the scratch copy's
   `Tests/PhotoCoreTests`, never into the checkout): builds a 5472 x 3648 `CIImage` of
   (0.25, 0.5, 0.75) with a 200 x 200 patch at (4, 3, 2) in `RenderEngine.hdrColorSpace`, calls
   `RenderEngine(contextCount: 1, name: "qa-probe").makeHDRCGImage`, prints width, height, bits, row bytes,
   bitmap info, color space name, `contentHeadroom`, the pixel data's byte count and an FNV-1a hash of it,
   and requires headroom 3.9 to 4.1 and data at least `bytesPerRow x height`. Run with
   `swift test --filter HDRProbeTests` once with the branch's `RenderEngine.swift` and once with develop's.
   Both printed
   `size=5472x3648 bits=16/64 bpr=43776 info=4353 cs=kCGColorSpaceExtendedLinearDisplayP3 headroom=4.0 bytes=159694848 fnv=1948759891858492291`.
5. HDR users:
   `swift test --skip-build --filter "SharpeningMapTests|PreviewTests|StalePreviewTests|LinearRawDecodeTests|LiveSessionTests|ComparisonTests|HDR"`
   Result: 96 tests in 13 suites passed.

No debug-script run of the app: the fix changes no UI and nothing a person sees, and `photobench` makes no
HDR image over 4096 pixels. The stall itself is P1.

## For a person

**P1 (optional, covers B9; no M-number, there is no `review.md`).** Only if a full-resolution HDR file
over 4096 pixels on a side is at hand (an HDR merge DNG or a gain-map JPEG/HEIC from a camera or phone).
Use a copy of the bundle with its own bundle identifier and `--library-root` on a scratch library, never
the real one.
1. Add the file to the scratch library, open it in the loupe on an HDR (EDR) display and press `Z` for 100%.
2. Open and zoom to 100% a few other large photos in turn (a minute or two, so other full renders run),
   then return to the HDR photo.
3. Look for: the HDR photo shows at once, with its highlights, no beach ball or hitch on returning. Before
   the fix a hitch of a second or more was possible on the return (the main thread decoding the master).
   Expected memory: about 160 to 190 MB more while that rendition is held; Activity Monitor is enough.
Not needed for sign-off if no such file exists: the unit test covers the mechanism.

## Follow-up

### Rerun of Q1 on `0a5978c` / `d887683` (2026-11-19)

The engineer replaced the fixed 96 renders and the control with sentinels: 40 deferred half-float images made
right after the rendition and read once, then rounds of 8 other renders until the pool gives back one
sentinel's surface (oldest first), and only then the HDR check at line 216. Same machine (M4 Pro, macOS
27.2.1, SDK 27.2), load averages 2 to 10 (lower than in the first pass). Logs in `scratchpad/logs/r2-*.log`.

| Run | Result |
| --- | --- |
| With the fix (the checkout), `swift test --skip-build --filter DeferredRenderTests` x25 | **25 of 25 passed** (6 tests, one gated off; the HDR test 2.46 to 2.86 s, the suite 4.4 s) |
| Without the fix: scratch copy of the branch's `Sources` and `Tests` (identical but for `RenderEngine.swift`, checked with `diff -rq`), `RenderEngine.swift` from `9002877`, same command x25 | **25 of 25 failed**, each at `DeferredRenderTests.swift:216` (`extended.calls == hdrPulled`, the HDR check). None passed, none failed at the "turned over" requirement |
| With the fix, full `swift test` x2 | 1243 tests in 177 suites **passed** both times (72.6 s and 70.3 s, load 2 and 10 at the start); the HDR test passed in 2.5 s each |

Q1: **Fixed.** The first pass saw 3 of 25 and 1 of 2 failures with the fix and 3 of 13 passes without it; neither
occurred in 52 runs here. Caveat, not a finding: the pool's behavior is undocumented and measured on this Mac
only; the test now says "needs revisiting" (and fails at the `#require`) if a macOS stops recycling surfaces,
so a CI failure on macOS 15 or 26 at that line is the test's premise, not the fix (as the code review noted).
Open: P1 (owner, optional). No other findings; nothing for the designer or product manager.

Counts for the claims B1 to B9: 8 Pass by test (B1 to B8, B5 by the first pass's scratch probe, which the rewrite does not
affect: `RenderEngine.swift` is unchanged between `192f4dd` and `0a5978c`), 0 by script, 1 open for a person
(B9, P1), 0 failed.

### Owner's sign-off

Signed off by the owner on 2026-11-19 ("Sign off, open the PR"), at commit `a19fc75`, relayed by the main session.
Between the last commit I tested (`d887683`) and `a19fc75` only this file changed (`git diff d887683..a19fc75 --stat`),
so the tested source and tests are the ones signed off.
Checks left open: P1 (a full-resolution HDR file over 4096 pixels at 100%, optional), skipped by the owner; it stays
open for a person and goes on the standing manual-checks issue (#82). VoiceOver, macOS 15 and macOS 26 are covered by
CI only (CI's first run of `hdrRenditionOwnsItsPixels` on macOS 15 and 26: a failure at its "needs revisiting"
requirement would be the test's premise about Core Image's pool, not the fix).
