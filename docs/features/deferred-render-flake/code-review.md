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
