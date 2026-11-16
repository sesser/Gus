Issue: #73

# Dehaze and local tone at the frame's edge: status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/pre-hdr-merge-fixes`, cut from `develop` at
`1ef945a`. Origin: `docs/archive/PHASE6_PLAN.md`, finding 4 and "Roadmap".
The folder keeps the issue's slug, `dehaze-above-white`. The issue's title
does not describe the cause; the suggested title is "Dehaze and local tone
at the frame's edge" (for the product manager).

**Status: Done.** Both defects are fixed, every test passes, and no golden
changed. Next: code review, then QA. The UI is unchanged, so there is no
design review.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `1ef945a`). `swift test --filter EstimateEdgeTests`.
In the app:
- A photo with Dehaze at 60: move Shadows from 0 to 1 and watch the frame's
  outer 20 or so pixels.
- A mask with Dehaze on a photo whose global Shadows is above 0 (or
  Highlights below 0): edit another mask, then compare the live frame's
  edges with the preview saved on release.

**Expected.** The haze and local tone estimates are the same however Core
Image evaluates the image they measure, and they treat the frame's edge like
its inside: a small change of a slider makes a small change everywhere.

**Actual.** Measured on the synthetic hazy landscape at 640 × 480 and
1200 × 900. The goldens are 256 × 192, where the estimates are not reduced,
so no golden sees any of this.

| What | Before | After |
|---|---|---|
| Reduced haze, the same image as one graph against rendered to half float first (the live session's cached stages), after Shadows 40, exposure 0 and +2 | differs by 0.094 | 0 |
| The same without local tone, values up to 0.74 or up to 2.9 | 0 | 0 |
| Live session, cached against whole frame, local dehaze, global Highlights −20, values to 3.1 (`LiveSessionTests.aboveWhite`) | 0.016 over the tolerance (known issue) | within it (largest difference 0.0089) |
| The same in standard range with global Shadows 30 | 0.0055 over the tolerance | within it (0.0047) |
| Shadows at 1 (gain 1 … 1.02): output against input, worst pixel | 0.909 (corner, darkened) | 1.0005 |
| Dehaze 60, Shadows 0 → 1: change in the outer 40 px / inside | 0.200 / 0.011 | 0.0021 / 0.0026 |

**Root cause.** Values above white were not the cause. Finding 4 measured
on the extended-range DNG with Highlights −20, which requests the
extended-range decode and also puts global local tone ahead of the masks;
that local tone is what triggered it. There were two defects, both at the
frame's edge, plus one sensitivity that does no harm:

1. **Haze estimate** (`AdjustmentRenderer.hazeEstimate`).
   - The Lanczos reduction to the 256-pixel copy read past the frame, where
     the image is transparent, so the copy's outermost pixels came out
     partly transparent (alpha 0.88).
   - The color clamp after the minimum of the three components has an
     alpha floor of 1. Where Core Image computed the alpha, the clamp
     divided the colors by it, which brightened them.
   - Where Core Image took the image for opaque, the colors stayed
     premultiplied, which darkened them. It does that in one graph after a
     step that ends in `settingAlphaOne(in:)` (local tone, or dehaze
     itself).
   - So the dark channel at the edge differed by up to 14% between a whole
     render and the live session's cached stages. It also stepped when
     Shadows or negative Highlights left 0.
2. **Global local tone** (`AdjustmentRenderer.localTone` without given
   estimates).
   - The same transparent edge in the reduced luminance guide left the
     upsampled estimate partly transparent over the outer 8 or so pixels
     (alpha 0.908 at the corner).
   - The gain is multiplied in premultiplied, so any Shadows or negative
     Highlights darkened the border by up to 9%.
   - The masks' estimate had a fixed 16-pixel margin (finding 5), which left
     alpha 0.996.
3. **Not a defect:** the guide is luminance to the power 0.25, whose slope
   is unbounded at 0. Half-float rounding near black therefore moves the
   estimate by up to 0.05 in black areas, where the gain multiplies a value
   near zero. The output does not change visibly (about 10⁻⁶).

**Fix** (`Sources/PhotoCore/Edits/AdjustmentRenderer.swift`).
- **Haze.** `hazeEstimate` reduces the frame with its edge pixels repeated
  outward (`clampedToExtent`), cropped to the reduced extent the frame alone
  gives. The copy is opaque up to its edge, so the clamp's alpha floor
  changes nothing however Core Image evaluates the image.
- **Local tone.** `smoothedLuminance` now takes the frame and measures it
  with a margin of its edge pixels repeated, `luminanceMargin` = 16 pixels
  of the reduced copy (16 px up to 256 px, 75 px at 1200, 375 px at 6000),
  then crops. Global local tone and the masks' estimate call the same
  function, so they measure alike.
- **Why that margin.** Measured on frames of 640 to 6000 px: from 12
  reduced pixels up, the estimate's alpha at the edge equals the inside's
  (0.99999994 up to 1200 px; at 3000 and 6000 px within 3 × 10⁻⁴ of the
  inside, where the upsample leaves 0.9996 everywhere, see Follow-ups).
  Below 8 pixels the result was erratic.
- **Pipeline.** `PreviewCacheKey.currentPipelineVersion` 10 → 11, a plain
  bump.

**Tests that fail without the fix** (`Tests/PhotoCoreTests/EstimateEdgeTests.swift`):
- `hazeEstimateIsEvaluationIndependent`, cases (exposure 0, Shadows 40) and
  (exposure 2, Shadows 40). Before: 0.0937 and 0.0940 (tolerance 2⁻⁹).
  After: 0.
- `shadowsNeverDarkensTheEdge`. Before: 0.9086 of its input at (0, 0).
  After: at least 1.
- `LiveSessionTests.aboveWhite(withEstimates: true)`. Its known-issue
  marker is removed and it now passes. The macOS 26 intermittent marker
  (finding 6) stays, now over both cases. The margin may cure that too, but
  no macOS 26 runner has shown it yet.

Also added: `hazeEstimateScalesWithExposure` (passed before too; guards
HDR merge input from −2 to +2 EV, values to 2.9), `maskEstimateIsTheGlobalOne`
and `pipelineVersionBumped` (11). `LocalSharpenGroupOffTests` now expects a
version of at least 10 instead of pinning 10.

## Owner's ruling (2026-11-15)

Option 1: fix both defects by measuring the estimates on edge-replicated
input. Defect 2 (border darkening) is in scope.
- **Byte for byte** applies only to edits with no Dehaze above 0, Shadows
  or negative Highlights (global or in a mask); it was never the rule for
  the others.
- **Pipeline:** a plain bump to 11.
- **Goldens:** untouched.
- **`aboveWhite` floor:** derived consistently, not by eye.
- **Margin:** wide enough to reach alpha 1.

## Results

**Goldens.** All pass with no change: `GOLDENS_REPORT=1` gave 0 difference
for every case touching tone, dehaze or masks (`mask-color-hueRamp` 0.00002,
GPU noise within tolerance). UPDATE_GOLDENS was not run.

**Byte for byte.** Renders of the code at `1ef945a` against this branch,
1200 × 900, in standard range and above white (the scene × 4, values to
2.9), plus the synthetic DNG through `PreviewGenerator`. Float and 8-bit
output are identical for exposure, contrast, Highlights +40, Whites and
Blacks, Clarity, Vibrance and Saturation, Dehaze −40 (a veil, no estimate),
Sharpening, a crop with straightening, and a mask with exposure, contrast
and clarity. Vignette's float output differed by up to 0.001, but it
differs between two runs of the same code too: pre-existing, see
Follow-ups.

**Renders that change** (8-bit Display P3 steps; standard range / above
white):

| Edit | Standard range | Above white |
|---|---|---|
| Dehaze 60 | ≤ 1 step, 1.3% of bytes | ≤ 1 step, 0.3% of bytes |
| Shadows 40 | ≤ 9 steps, border only | ≤ 11 steps, border only |
| Highlights −40 | ≤ 8 steps, border only | ≤ 10 steps, border only |
| Shadows 40 with Dehaze 60 | ≤ 27 steps | ≤ 10 steps |
| Local dehaze 40 | ≤ 1 step | none in 8 bits |
| Local Shadows 50 | ≤ 1 step | none in 8 bits |
| Synthetic DNG, Shadows 30 with Dehaze 40 | ≤ 13 steps | |

**`aboveWhite` tolerance.** Each extra rounding to half float is off by at
most 2⁻¹¹ of the value, or by 2⁻²⁵ near zero (half the spacing 2⁻²⁴ of the
smallest half-float values). Three roundings, enlarged by `gain(after:)`,
give 3 × 2⁻¹¹ × gain relative plus 3 × 2⁻²⁵ × gain absolute. Before, the
absolute floor was 2⁻²⁴, multiplied by neither. At this test's gain (7.68)
the floor is 6.9 × 10⁻⁷. An earlier try with a 16-pixel full-resolution
margin exceeded the old floor by 3 × 10⁻⁷ at a below-black pixel. With the
final margin both cases pass under the old floor too, so this change makes
the tolerance consistent rather than rescuing the test.

**Speed.** A 6000 × 4500 render into a bitmap, median of 7: Shadows 40 took
622 ms (before 625), Dehaze 60 took 773 ms (before 841). The margin costs
nothing measurable.

## Verification

- **Baseline at `1ef945a`:** `swift build` clean; `swift test` 1032 tests
  in 153 suites passed, 1 known issue (`aboveWhite`).
- **Final:** `swift build` clean, no new warnings (the test target's two
  existing warnings, in `SmartAlbumTests` and `VirtualCopiesTests`, are
  unchanged). `swift test`: 1037 tests in 154 suites passed, no known
  issues.

## Open questions

None. The title suggestion above is for the product manager.

## Follow-ups (proposed issues)

- **Vignette renders differ from run to run** (bug). Two renders of the same
  1200 × 900 image with Vignette −40 differ by up to 0.00026 in standard
  range and 0.001 above white. That is in float only; 8-bit output was the
  same. Found while checking #73's byte-for-byte rule.
- **Local tone's estimate is a hair transparent everywhere on large frames**
  (bug). From about 3000 px, the edge-preserving upsample leaves the
  smoothed luminance's alpha at 0.9996 across the frame, so Shadows and
  Highlights darken by up to 0.04% everywhere. This is not an edge effect;
  #73 did not change it.

## README

Nothing to change.
