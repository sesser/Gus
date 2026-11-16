# Dehaze and local tone at the frame's edge: code review

Owner: code-reviewer. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/pre-hdr-merge-fixes`, commit `476d6a9` (#73) on base `1ef945a`
(the branch also carries `23c71f4`, #65, reviewed in
`docs/features/full-render-main-thread-stall/code-review.md`). Build and tests:
`swift build` clean; full `swift test` run five times, 1040 tests in 155
suites: three runs passed, two failed with one issue each, both in #65's
`DeferredRenderTests.matchesCoreAnimationsRender` (that file's C1). Nothing
in #73's tests or the goldens failed in any run.

## Verdict

Ready for QA. The fix does what the Bug section says. The global estimate
and the masks' estimate go through one function. Goldens, migrations and
the byte-for-byte rule hold, and the pipeline bump is in place. I found
nothing to fix.

## Findings

None.

## Questions

None for the designer or the product manager. The status suggests a new
issue title ("Dehaze and local tone at the frame's edge") for the product
manager. The main session can pass that on.

## Checked and fine

- **One function for both estimates.** `localEstimates` (masks) and
  `localTone` without given estimates (global) both call
  `smoothedLuminance(_:extent:)`. The old `scaleFrom:` parameter and the
  separate 16-pixel padding in `localEstimates` are gone. The haze side was
  already shared: `dehaze` and `localEstimates` both call `hazeMap`. These
  are the only callers in `Sources/`; the live session reaches them only
  through `localEstimates` and `upstream`.
  `maskEstimateIsTheGlobalOne` is true by construction now, but it guards
  against the two drifting apart again.
- **Margin.** `luminanceMargin` is 16 reduced pixels: `(16 / scale)` rounded
  up, which gives 16 px at 256 px or less, 75 at 1200 and 375 at 6000. The
  guide and the reduced copy are both built on the padded frame, and the
  upsample is cropped back to `extent`. The reduced copy's scale comes from
  the frame, not the padded frame, so the margin doesn't change the inside.
  At 256 × 192 (the goldens) this is the same 16-pixel margin the masks'
  estimate used before. I measured the alpha in a scratch clone (not the
  repository): `smoothedLuminance` gives 1.0 at the corner and the center at
  640 and 1200 px. At 3000 and 6000 px it gives 0.99989 at the corner and
  0.99979 to 0.99989 at the center. That matches the status's "Local tone's
  estimate is a hair transparent everywhere on large frames" follow-up,
  which is not an edge effect.
- **Haze estimate.** `hazeEstimate` takes `smallExtent` from the reduction
  of the unpadded frame, then reduces the clamped image and crops to that
  extent. So the reduced extent, and with it the airlight's
  `areaMaximum` region, is the same as before; only the outer pixels'
  contents change. `hazeMap`'s upsample still uses an unpadded guide. I
  checked whether that leaves the edge transparent: the haze map's alpha is
  1.0 at the corner, the edge midpoints and the center at 640, 1200, 3000
  and 6000 px. Dehaze 60 on a flat grey 1200 × 900 frame gives the same
  output/input ratio (1.0015688) at the corner, the edges, 8 px in, 40 px in
  and the center. Dehaze has no edge darkening of its own.
- **Byte for byte.** The changed code runs only for a non-identity
  `LocalToneCurve` (Shadows ≠ 0 or Highlights < 0), for `dehaze` with
  amount > 0, or for a mask that has one of those (`localEstimates`
  checks the same conditions). Negative Dehaze returns before `hazeMap`. So
  every other stack renders through unchanged code, which is the scope of
  the owner's ruling.
- **Pipeline version.** `currentPipelineVersion` 10 → 11, with the reason in
  the doc comment. `removeObsoletePipelineVersions` deletes `v10` at
  launch, and no carry-over is involved. `EstimateEdgeTests.pipelineVersionBumped`
  pins 11. `LocalSharpenGroupOffTests` went from `== 10` to `>= 10`,
  which still checks its own bump. `PreviewTests` reads the constant. No
  other test pins a version.
- **Goldens.** `git diff 1ef945a..HEAD` touches nothing under
  `Tests/PhotoCoreTests/Goldens`. `GoldenTests` passed in every full run.
  `UPDATE_GOLDENS` was not run.
- **`aboveWhite` tolerance.** The floor went from 2⁻²⁴ to 3 × 2⁻²⁵ × gain,
  so the tolerance was loosened in the same commit as the code change. It
  is not a finding, for three reasons:
  - The derivation is right. A half-float rounding is off by at most 2⁻²⁵
    in the subnormal range (half of 2⁻²⁴), and the new floor is enlarged by
    `gain(after:)`, like the relative term.
  - The owner ruled it ("derived consistently").
  - I restored the old floor (`0x1p-24`) in a scratch clone, and both cases
    of `LiveSessionTests.aboveWhite` passed. The test passes on the fix, not
    on the looser floor.
- **Known-issue markers.** The `withEstimates` known issue is removed. The
  macOS 26 intermittent marker now covers both cases, which is correct: it
  passes when Apple's fault isn't there and records it when it is.
- **New tests.** `hazeEstimateIsEvaluationIndependent` (2⁻⁹, explained in
  its comment) and `shadowsNeverDarkensTheEdge` (1 − 2⁻¹⁰, two roundings)
  have tolerances derived from the formats, not tuned. Both are Swift
  Testing, synthetic, with no sleeps. They passed in all five full runs.
- **Concurrency, persistence, strings.** Pure Core Image graph changes in
  PhotoCore: no new state, no isolation changes, no migration, no UI strings
  and no brand values.

## Follow-up

(After the engineer's fixes. Nothing open.)

## Security review

Not needed. The change adds no parser, subprocess, file writing outside the
library, or network code.

## Summary for the issue

**Code review (#73): ready for QA, no findings.**
- The global and mask luminance estimates share `smoothedLuminance`, with a
  margin of 16 reduced pixels of repeated edge pixels. The haze estimate
  reduces the frame with its edge pixels repeated. In a scratch clone, the
  haze map's alpha is 1 at the edge and Dehaze on a flat frame is uniform
  out to the corners.
- Pipeline version 11. No golden moved. Stacks without Dehaze > 0, Shadows
  or negative Highlights go through unchanged code.
- The `aboveWhite` floor change is derived correctly, and the test also
  passes under the old floor.
- No `/security-review` needed.
- Full file: `docs/features/dehaze-above-white/code-review.md`
