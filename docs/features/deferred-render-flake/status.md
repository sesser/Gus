Issue: #229

# DeferredRenderTests fails intermittently in full runs: status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/deferred-render-flake`, from `develop` at `9002877`
(includes #222).

**Status: Done.** Next: code-reviewer; no UI changed, so no design review; then
qa-tester.

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
("The HDR rendition is rendered before it is returned, and never again"). It
makes the HDR rendition from a counting provider, then makes Core Image
render and read 96 other 5472 × 3648 images in a context of its own
(`renderOthers`, a stand-in for the rest of the app or of a parallel run),
then reads and draws the rendition through `CARenderer` and requires that its
source was not asked again. A control in the same test, a plain deferred
image read before those renders, must be rendered again after them, so the
test can tell (a macOS that stops recycling those surfaces fails the control
with "needs revisiting" instead of passing blind). With develop's
`makeHDRCGImage` the test failed **10 of 10** runs of the suite alone, always
at the HDR check (`DeferredRenderTests.swift:188` at that commit), the control
holding every time.

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
    `hdrRenditionOwnsItsPixels` (above).
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
| New test, develop's `makeHDRCGImage`, suite alone ×10 | **10 of 10 failed** at the HDR check; control held 10 of 10 |
| With the fix, suite alone ×10 | 10 of 10 passed (6 tests, one gated off; 3.8 to 4.2 s, the 96 renders take about 2.4 s) |
| With the fix, full `swift test` ×1 (`8e33ead`) | 1243 tests in 177 suites passed (67.3 s, load 25) |
| With the fix, 8 full `swift test` (`8e33ead`) | 1243 tests in 177 suites, **8 of 8 passed** (68.7 to 72.1 s), load averages 19 to 33; `hdrRenditionOwnsItsPixels` passed in each (3.1 to 4.0 s), its control holding each time |
| `swift build`, `swift build --build-tests` | Pass, no new warnings |

## Checks for review and QA

- Run the new test alone and in a full run; it should never fail with the fix.
- To see it fail without the fix: put develop's `makeHDRCGImage` back
  (`git show 9002877:Sources/PhotoCore/Preview/RenderEngine.swift`) and run
  `swift test --filter DeferredRenderTests`: the HDR check fails every time.
- No manual check in the app: the stall it removes needs an HDR photo over
  4096 pixels at 100%, other full renders, then a return to it; nothing a
  person sees changes otherwise. Optional for QA if a full-resolution HDR
  DNG is at hand.

## README

Nothing: no requirement, build command or layout changes.

## Open questions

None.
