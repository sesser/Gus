Issue: #229

# DeferredRenderTests fails intermittently in full runs: status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/deferred-render-flake`, from `develop` at `9002877`
(includes #222).

**Status: Done** (again, after QA finding Q1, see Review findings). Next:
code-reviewer's second pass (the test changed), then qa-tester to rerun Q1; no
UI changed, so no design review.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce.**
1. Full `swift test` on a loaded machine, now and then:
   `DeferredRenderTests` "Core Animation renders an unread deferred image when
   it draws it, and only then" fails at `DeferredRenderTests.swift:158`
   (`extended.calls == hdrPulled`, "Core Animation rendered the HDR rendition
   again") or at line 150 (the same check on a plain deferred image whose
   pixels were read). Recorded on #218 (2 of 3 runs, a different line each
   time), #87 (lines 150 and 158 in one run, 158 alone in another), #222's
   baseline and #221 merged with develop (2 of 2). The suite alone never
   failed.
2. Deterministically, in one process: render a deferred image (Core Image's
   short `createCGImage`, a side over 4096 pixels), read its pixels once
   (`dataProvider.data`), then render and read about 80 to 96 other images of
   that size in **another** `CIContext`, then read or draw the first image
   again: Core Image asks the first image's source for its pixels again.
   With 8 other renders it never did; with 32 to 48, in about two runs of
   three; with 80 or more, every time (17 of 17 runs, scratch probe).

**Expected.** The test is deterministic. And the claim it rests on, that the
HDR rendition (`RenderEngine.makeHDRCGImage`) is rendered where it is made and
never again by Core Animation on the main thread, holds whatever else renders.

**Actual.** The HDR rendition is rendered again when Core Animation draws it
after enough other renders, and the test fails whenever the rest of the
parallel run has rendered enough in between.

**Root cause. A real gap in app code, which the test caught under load.**
`makeHDRCGImage` returned Core Image's deferred image and relied on reading
its pixels (for the content headroom) to keep it rendered; #65 recorded that
Core Animation "does not render an image again whose pixels were read"
(`docs/features/full-render-main-thread-stall/status.md`, The fix). That only
holds while Core Image keeps those pixels: it holds them in an IOSurface of
its **process-wide** surface pool, released to the pool as purgeable (a
`vmmap --summary` of the process after one read shows 76 MB of IOSurface in
the volatile and empty columns, not in the non-volatile one), and later
renders, in any context, take surfaces back. Clearing the image's own
context's caches (`clearCaches()`) does not drop them; renders in another
context do. Once the surface is gone, the next reader renders the whole
graph again through the image's provider. In the test that reader is
`CARenderer`, and the other suites of the parallel run (goldens, previews,
exports, about 70 s of GPU work) are the other renders: hence "passes alone,
fails in full runs", at line 150 or 158, more often on a loaded machine.

In the app the reader is Core Animation's commit on the main thread: a
full-resolution HDR rendition (an HDR merge DNG or a gain-map photo over 4096
pixels at 100%) waiting in the memory cache (`PreviewService.hdrImage`,
`insertFullResolution`) after other renders, then shown again, was rendered
from the master on the main thread, the #65 stall (decode and the whole
stack). Not seen by a person; no report. SDR renditions were not affected:
#65 already renders them into a surface of their own (`makeSurfaceImage`), and
images 4096 pixels or smaller on both sides are not deferred.

The older record in the same file (`matchesCoreAnimationsRender` failing 2 of
5 full runs, #65 C1, also in `docs/features/dehaze-above-white/code-review.md`)
is a different cause, already fixed by `072518d`: a byte-for-byte comparison
of two Core Image renders that vary by one level. It has not been seen since.

**Test that fails without the fix.** `DeferredRenderTests.hdrRenditionOwnsItsPixels`
("The HDR rendition is rendered before it is returned, and never again"), as
rewritten for Q1. It makes the HDR rendition from a counting provider, then 40
**sentinels**: deferred renditions made the way develop's `makeHDRCGImage`
made it (half float, extended linear Display P3, 5472 × 3648, pixels read
once), so each is newer than the rendition. Then, in rounds, it has Core Image
render and read 8 other such images in a context of its own (a stand-in for
the rest of the app or of a parallel run) and reads the next sentinel, oldest
first, once (`turnOverSurfacePool`). It stops at the first sentinel whose
source is asked again: the pool has then turned over past the rendition. Only
then does it read and draw the rendition through `CARenderer` and require that
its source was not asked again. If no sentinel is taken back within 40 rounds
(320 other renders), it stops with "needs revisiting" (`#require`) instead of
passing blind. Without the fix the committed test failed **25 of 25** suite
runs, always at the HDR check (`DeferredRenderTests.swift:216`), never at the
turnover check (and the measuring build 25 of 25 suite runs and 2 of 2 full
runs, the same way); see Verification.

Why sentinels, measured on this Mac (scratch probes, not committed):
- The pool gives back its least recently used surfaces first: of two read
  images left alone, never the newer one alone (16 runs at 32 to 160 other
  renders: neither yet in 8, both in 7, only the older in 1).
- Reading an image whose surface is still in the pool makes it the most recent
  again: one image read after every round of 8 was never taken back in 800
  other renders (11 of 11 runs, half float or 8-bit, either kind of other
  render). So "render until the control is asked again" with one control never
  ends.
- So each sentinel is read once only. A sentinel taken back, newer than the
  rendition and never read since it was made, shows a deferred rendition would
  have been taken back too.

## The fix

- `Sources/PhotoCore/Preview/RenderEngine.swift`, `makeHDRCGImage`: the
  pixels it already read for the headroom (`dataProvider.data`, a CFData of
  its own) now back the returned `CGImage` (same width, height, bits, row
  bytes, color space, bitmap info and intent), and the deferred image is
  released when it returns. Same render, same bytes, same headroom tag
  (`CGImageCreateCopyWithContentHeadroom` as before). No extra render and no
  extra copy: the read was already a copy, and a data provider over a CFData
  hands back the same bytes (checked: the pointer is the CFData's own).
- **Behavior change:** the full-resolution HDR rendition now holds its 8
  bytes per pixel (about 190 MB for a 24 MP photo; see Memory) in ordinary
  memory for as long as the memory cache keeps it, instead of in a purgeable
  surface the system or Core Image could take back; in exchange it is never
  rendered again on the main thread. Pixels on screen are unchanged.
- `Tests/PhotoCoreTests/DeferredRenderTests.swift`:
  - `coreAnimationRendersDeferredImages` keeps its first half, renamed "Core
    Animation renders an unread deferred image when it draws it" (what
    `drawnByCoreAnimation` stands for: the old stall). Its second half, "and
    does not render one again whose pixels were read", is removed: it is not
    true (above), and nothing relies on it any more. Its HDR check moved, with
    the eviction the full run made by chance now made on purpose, into
    `hdrRenditionOwnsItsPixels` (above; rewritten for Q1).
  - The suite stays `.serialized`. Making it run apart from the other render
    suites was not needed: the fixed rendition does not depend on what else
    renders, and the test now makes the pressure itself.
- No `PreviewCacheKey.currentPipelineVersion` bump (no rendered pixel
  changes; HDR renditions are memory-only anyway), no golden moved, no
  migration, no UI change. `docs/USER_GUIDE.md` needs nothing: it says
  nothing about how the HDR render is held, and nothing a person sees
  changes except the absence of a stall.

**Memory.** For a 5472 × 3648 photo the HDR rendition is 5472 × 3648 × 8
bytes (half float RGBA) = 160 MB, as `DecodedImage.byteCount` already counted
it for the memory cache's budget; the bytes are now really held, and the
purgeable surface goes back to Core Image's pool. The memory cache keeps one
full-resolution rendition at a time (`insertFullResolution` drops the
previous one, SDR or HDR) in an `NSCache`, which still lets it go under
memory pressure, so this adds at most one such image of held memory. Peak
during `makeHDRCGImage` is as before (the deferred image's surface plus the
read copy).

## What the test protects

That the loupe's HDR rendition is rendered off the main thread, where it is
made, and that showing it again later, from the memory cache, never makes
Core Animation render the photo again on the main thread
(`CLAUDE.md`: images are fully decoded before they reach layers; #65).

## Verification

Machine: the owner's Mac (14 cores, 24 GB), shared with other agents' builds
and tests throughout (load averages below). Logs in this session's scratch
folder (`logs/before-N.log`, `logs/after-full-N.log`, `logs/without-fix-N.log`,
`logs/with-fix-alone-N.log`).

| Run | Result |
| --- | --- |
| Baseline `swift build` at `9002877` | Pass |
| Baseline: 8 full `swift test` on develop's code (`9002877`) | 1242 tests in 177 suites, **8 of 8 passed** (67 to 74 s), load averages 18 to 71. The flake did not show in these 8: it needs enough other rendering to land between the read and the draw, which the deterministic repro above makes on purpose |
| First test (`8e33ead`, 96 fixed renders and a control read before the rendition) | Superseded by Q1. Recorded here: develop's `makeHDRCGImage` 10 of 10 failed at the HDR check; with the fix 10 of 10 suite runs and 9 of 9 full runs passed on this Mac. QA found it flaky (Q1) |
| Q1 rewrite, measuring build (a temporary print of the turnover count; each sentinel then compared with one pull, since tidied to the count its read made), develop's `makeHDRCGImage`, suite alone ×25 | **25 of 25 failed**, each at the HDR check, none at the turnover check; the pool turned over after 8 to 120 other renders (median 40); load averages 5 to 9 |
| Measuring build, develop's `makeHDRCGImage`, full `swift test` ×2 | **2 of 2 failed**, one issue each, at the HDR check, nothing else; turned over after 8 renders; load averages 34 to 48 |
| Measuring build with the fix, suite alone ×25 | **25 of 25 passed**; turned over after 32 to 56 other renders; load averages 5 to 10 |
| Measuring build with the fix, full `swift test` ×3 | **3 of 3 passed**, 1243 tests in 177 suites (66.8 to 72.3 s); turned over after 8 to 32 renders; load averages 4 to 22 |
| **Committed test**, develop's `makeHDRCGImage` (`9002877`), suite alone ×25 | **25 of 25 failed**, each with one issue at the HDR check (`:216`), none at the turnover check; load averages 2 to 3 |
| **Committed test** with the fix, suite alone ×25 | **25 of 25 passed**; the test 2.53 to 2.97 s, the suite 4.15 to 4.59 s; load averages 3 to 13 |
| **Committed test** with the fix, full `swift test` ×2 | **2 of 2 passed**, 1243 tests in 177 suites (71.6 and 71.8 s); load averages 9 to 12 |
| `swift build --build-tests` | Pass, no new warnings (the two existing ones in `SmartAlbumTests` and `VirtualCopiesTests` remain) |

Test time: the rewritten test takes about 2.3 to 3.2 s alone and 2.4 to 2.6 s
in a full run (the 40 sentinels about 1.5 s of it), against 2.4 to 4 s for the
first version; the cap (320 renders) would take about 13 s, reached in no run.
Full runs stay at 67 to 73 s. Logs: this session's scratch folder, `logs/q1/`
(measuring build) and `logs/q1b/` (committed test).

## Review findings

| # | From | Finding | Answer |
| --- | --- | --- | --- |
| Q1 | qa-tester (`qa.md`) | `hdrRenditionOwnsItsPixels` was flaky: with the fix its control failed 3 of 25 suite runs and 1 of 2 full runs; without the fix it passed 3 of 13 (missed the bug). 96 fixed renders don't make the pool take surfaces back every time | Fixed in the test (the fix itself is unchanged, and QA confirmed it). Two causes: the count was fixed, and the control was made **before** the rendition, so with the pool giving back the oldest surface first the control could go while the rendition stayed (the 3 misses) or neither went (the control failures). QA's suggestion, rendering until the control is asked again, does not work as such: reading the control while its surface is still there makes it the newest again, and it was never taken back in 800 renders. Now 40 sentinels made after the rendition, each read once, oldest first, in rounds of 8 other renders, until one is taken back (cap 320, then "needs revisiting"); the HDR check runs only after that. Measured on the committed test: without the fix 25 of 25 suite runs fail at the HDR check, none at the turnover check; with it 25 of 25 suite runs and 2 of 2 full runs pass (plus the measuring build: 25 and 2 of 2 full runs failing without, 25 and 3 full runs passing with; Verification) |

Code review (`code-review.md`): no findings. Its CI note (the control rests on
undocumented pool behavior measured only on macOS 27.2) still applies to the
turnover check: if CI fails at "needs revisiting", the pool behaves
differently there, not the fix.

## Checks for review and QA

- Run the new test alone and in a full run; it should never fail with the fix.
- To see it fail without the fix: put develop's `makeHDRCGImage` back
  (`git show 9002877:Sources/PhotoCore/Preview/RenderEngine.swift`) and run
  `swift test --filter DeferredRenderTests`: the HDR check fails every time,
  the turnover check never.
- No manual check in the app: the stall it removes needs an HDR photo over
  4096 pixels at 100%, other full renders, then a return to it; nothing a
  person sees changes otherwise. Optional for QA if a full-resolution HDR
  DNG is at hand.

## README

Nothing: no requirement, build command or layout changes.

## Open questions

None.
