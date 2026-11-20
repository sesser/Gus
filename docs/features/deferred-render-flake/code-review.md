# DeferredRenderTests fails intermittently in full runs: code review

Owner: code-reviewer. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md` (bug fix, issue #229).
Reviewed: `bug/deferred-render-flake`, `9002877..57acf76` (two commits: `8e33ead` the fix and test,
`57acf76` status). Build and tests: `swift build` clean; `swift test --filter DeferredRenderTests`
6 tests passed (the new test 2.19 s); the HDR users (`SharpeningMapTests|PreviewTests|StalePreviewTests|HDR`)
35 tests passed; one full `swift test`: 1243 tests in 177 suites passed (67.5 s, load average 17 to 22).
Without the fix (develop's `RenderEngine.swift` put back, then restored; worktree left clean): the suite
alone failed 3 of 3 runs, each at `DeferredRenderTests.swift:189` (the HDR check), the control at line 184
holding each time.

## Verdict

Ready for QA. The root cause is real and the fix matches it: the HDR rendition now owns the
pixels it already read, so nothing can send Core Animation back to its source; same bytes, format,
color space and headroom tag, no extra render or copy. The new test is deterministic on this
Mac, fails without the fix and has a working control. No findings; one follow-up (same cause,
other code) and one CI watch item below.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| none | | | | | |

## Questions

None for the designer or product manager.

For the main session (not a finding): the control in `hdrRenditionOwnsItsPixels` relies on
undocumented behaviour of Core Image's surface pool (96 other renders reclaim a read deferred
image's surface), measured only on this Mac (macOS 27.2). The fix itself does not rely on it.
CI on macOS 15 and 26 is the first run elsewhere. If the test fails there at line 184 ("Core
Image kept a read deferred image's pixels ... needs revisiting"), the cause is the control, not
the fix: the HDR check cannot go back to its source once the image is backed by a `CFData`.

## Checked and fine

- **Root cause.** I reproduced it: with develop's `makeHDRCGImage`, reading the rendition's pixels
  once and then making 96 other large renders in another context sends the next read or draw
  back to the source (3 of 3). The claim #65 relied on ("Core Animation does not render an image
  again whose pixels were read") holds only until the pool takes the surface back.
- **The fix (`RenderEngine.swift:184-198`).** I checked with a standalone probe (scratch, not
  committed) at 5472×3648, 4097×10, 2560×1707 and 4001×3:
  - The `CFData` from `dataProvider.data` is at least `bytesPerRow × height` (exactly equal for
    the deferred sizes). `maximumComponent` and Core Animation read within bounds.
  - The new provider hands back the same bytes: `rendered.dataProvider.data` points at the same
    buffer, and `CGImageCreateCopyWithContentHeadroom` shares it, so a 24 MP image is not copied
    twice.
  - Color space (`extendedLinearDisplayP3`), `bitmapInfo` (4357: half float, little-endian
    16-bit, premultiplied last), bits, row bytes and intent are carried over unchanged.
  - `shouldInterpolate` is carried over too (false for deferred images, as before).
  - The deferred image has no headroom of its own (0), so the tag is exactly what it was:
    `max(headroom, 1)` on the copy.
- **Failure paths.** A nil `dataProvider.data` still gives nil, so `renderFailed`, as before (the old
  `maximumComponent` failed on the same read). A `CGImage` init failure gives nil the same way.
- **Other callers.**
  - `PreviewGenerator.hdrImage` is the only product caller (full resolution and tier sizes).
  - `SharpeningMapTests:218` is a test and passes.
  - Tier sizes (sides of 4096 or less) are not deferred. They now hold the read `CFData` in place
    of the bitmap Core Image made, so they hold the same memory.
- **Memory.**
  - `DecodedImage.byteCount` (`bytesPerRow × height`) already charged 8 bytes per pixel to the
    `NSCache` (limit 512 MiB), so the cache's accounting is now true where it was nominal before.
  - `insertFullResolution` keeps one full-resolution entry, and `NSCache` still lets it go under
    pressure.
  - The new cost is about 160 to 190 MB of non-purgeable memory per full-resolution HDR rendition
    a layer or the cache holds. While comparing two HDR photos at 100%, each pane's layer holds
    one. That is the documented trade, and it is the same size the cache already accounted for.
  - The peak inside `makeHDRCGImage` is unchanged (pool surface plus the read copy).
- **Concurrency.**
  - `makeHDRCGImage` runs on `hdrLane`, off the main actor, as before.
  - `CFData` and `CGImage` are immutable, and `DecodedImage`'s `@unchecked Sendable` reason still
    holds.
  - No new shared state.
- **Test (`DeferredRenderTests.swift:140-190`).**
  - It uses Swift Testing, has no sleeps and keeps `.serialized`.
  - `hdrPulled > 0` proves the render happens before return.
  - The control fails loudly if the pool stops reclaiming.
  - Other suites rendering at the same time only add pressure, which helps the control.
  - With the fix the final check cannot fail: a `CFData` provider has no way back to the source.
  - Removing the second half of `coreAnimationRendersDeferredImages` is right: it asserted the
    claim that is false.
- **Rules.**
  - No rendered pixel changes, so no `currentPipelineVersion` bump is needed (HDR renditions are
    memory-only).
  - No golden moved, no tolerance loosened, no migration.
  - No UI strings, branding or new dependency.
  - The doc comment on `makeHDRCGImage` states the reason.
- **Historical records.** `docs/features/full-render-main-thread-stall/status.md:60` and `qa.md:32`
  still state the old claim. They are another feature's records, and this branch's `status.md`
  corrects them; they don't need editing.

## Follow-up

**Proposed issue (same root cause, other code; not part of this branch).** Title: "Kept decodes
over 4096 pixels can render their source again after other renders". Body:

- These keep a deferred `createCGImage` (RGBAh, working space) and reuse it through
  `CIImage(cgImage:)`:
  - `LiveRenderSession.base(for:)` (`LiveRenderSession.swift:542`, "decoded master reused per
    frame")
  - `LiveRenderSession.materialize` (`:241`)
  - `LinearRawDecode.rendered` (`LinearRawDecode.swift:61`; its doc calls it a "bitmap, held until
    its Decoded image is released")
  - possibly `SharpeningMapRefiner.swift:142` and `AutoAdjust.swift:266`.
- For sides over 4096 that image is deferred and lives in Core Image's reclaimable pool. A
  standalone probe of the `base` pattern at 5472×3648:
  - Frame 1 pulled the source 24 times and frame 2 pulled it 0 times.
  - After 96 renders of other images in another context, frame 3 pulled the source 24 times again.
  - In the app that would be a full decode of the master again during a live edit after
    background previews ran.
- The cost is speed, not a main-thread stall (these feed Core Image, not layers). Measure it with
  a real raw, then decide whether to own the pixels the way this fix does.

Engineer's fixes: none needed.

## Second pass: `0a5978c` (QA finding Q1)

Date: 2026-11-19. Reviewed: `192f4dd..0a5978c`, one commit: `hdrRenditionOwnsItsPixels` rewritten
(`DeferredRenderTests.swift:140-218`) and `status.md`. `qa.md` (`7f8eea6`) read for Q1.
Build and tests: `swift build --build-tests` clean. With the fix, `swift test --filter DeferredRenderTests`
8 of 8 passed (the test 2.15 to 2.82 s, load about 1.8); one full `swift test`: 1243 tests in 177
suites passed (70.5 s; the test 2.91 s; load 1.4 rising to 11). Without the fix (`RenderEngine.swift`
from `9002877`, which matches the local `develop`'s, put back, then restored with `git checkout`;
worktree clean): 8 of 8 suite runs failed, each with exactly one issue at `DeferredRenderTests.swift:216`
(the HDR check), none at the turnover `#require` (line 211); the pool turned over after 48 (2 runs)
or 56 (6 runs) other renders.

**Verdict.** Ready for QA's rerun of Q1. The rewrite answers both of Q1's failure modes, the assertion
is as strict as before, and the app fix is untouched. No new findings.

**Checked and fine.**

- **App fix unchanged.** `git diff 8e33ead..HEAD -- Sources/` is empty; `makeHDRCGImage` is as reviewed in
  the first pass.
- **Why the old control failed (the engineer's diagnosis holds).** The control was made and read
  *before* the rendition, so under least-recently-used reclaiming it was the first to go: 96 renders
  could take the control and leave the rendition (QA's 3 misses without the fix), or take neither
  (QA's 3 of 25 control failures with it). The fixed count of 96 made both depend on load.
- **The sentinel reasoning.**
  - Without the fix the rendition is read once inside `makeHDRCGImage` and not touched again until
    line 214. Every sentinel is made and read after it, so all are newer.
  - Round k reads sentinel k once. Sentinels 0..k-1 were refreshed by their own reads. Sentinel k
    has not been touched since it was made, and the rendition is older still. So if the pool gives
    back the least recently used surface first, sentinel k going back means the rendition went
    back before it.
  - Reading each sentinel once only is what makes this work: one control read every round becomes
    the newest again and is never taken back (the engineer's 800-render measurement). That is also
    why QA's "render until the control is asked again" could not end.
  - Pressure from other suites in a full run makes surfaces go sooner. It does not change the order,
    so it does not break the argument.
- **Strict, and never passes blind.**
  - The HDR check (line 216) is the same equality as before (`== hdrPulled`, no tolerance).
  - The turnover check is a `#require`: a recorded failure that stops the test, not a skip or a
    warning. If no sentinel is taken back within 40 rounds (320 renders), the test fails with
    "needs revisiting" before it reaches the HDR check. It cannot pass without having seen the pool
    turn over.
  - The cap leaves room. The most renders measured before a turnover is 120 (status.md), against
    the cap of 320. My runs took 48 and 56. At about 13 s, the cap's cost is bounded.
  - With the fix the HDR check cannot fail: the image is backed by a `CFData`. So the only failure
    left with the fix is the "needs revisiting" path, which is the right signal.
- **Remaining dependence (accepted, not a finding).** The test now relies on one undocumented
  property: the pool reclaims in least-recently-used order. If a macOS reclaimed a newer sentinel
  while keeping the older rendition, the test would pass without the fix (a missed regression),
  not fail.
  - Evidence on this Mac: 25 of 25 (engineer) and 8 of 8 (here) suite runs, plus 2 of 2 full runs,
    caught the bug without the fix, at the HDR check every time.
  - Evidence elsewhere: none. CI on macOS 15 and 26 is the first run off this Mac (the first pass's
    Questions note, restated in status.md). On CI the likelier symptoms are the "needs revisiting"
    `#require` (a paravirtual GPU's pool behaving differently) or `pulled > 0` failing in
    `readDeferredHDR` (a failed render). Both are loud, and neither points at the fix.
- **Deterministic as far as the test controls it.**
  - No sleeps and no clocks; the loop is bounded.
  - Each sentinel's re-render is told apart by its own counter (`calls > pulled`, against the count
    its own read made).
  - The suite stays `.serialized`, so its own tests don't interleave.
  - `readDeferredHDR` builds the old rendition exactly as develop's `makeHDRCGImage` did: `.RGBAh`,
    `hdrColorSpace`, 5472 × 3648, read once.
- **Test time.**
  - 2.15 to 2.91 s here, against 2.2 s for the first version in the first pass.
  - The 40 sentinels are about 1.5 s of that (status.md). The cap is about 13 s and was never
    reached.
  - The full run's time did not change (70.5 s).
- **Memory.**
  - Each sentinel and each other render is a 160 MB half-float surface in Core Image's purgeable
    pool. The CFData each read makes is dropped straight away.
  - Peak resident memory is the pool's business: it reclaims on its own after 8 to 120 renders.
  - The first version made about 97 such surfaces at 80 MB. This one makes about 80 to 100 at
    160 MB.
  - Not a concern on this Mac. On a 7 GB CI runner it is covered by the CI watch above.
- **status.md.**
  - The Bug section's test description, Verification and the Q1 row agree with the code.
  - The line numbers it gives (`:216`) are right.
  - The "Checks for review and QA" steps reproduce what I saw.

**Findings (second pass).** None.

**Follow-up.** First pass: no findings, nothing to confirm. Q1 is QA's finding; from the code side it is
addressed by `0a5978c`, and QA's rerun (25 suite runs and two full runs with the fix, 13 without)
confirms it in `qa.md`. The first pass's proposed issue (kept decodes over 4096 pixels in
`LiveRenderSession` and `LinearRawDecode`) and the CI watch item still stand.
