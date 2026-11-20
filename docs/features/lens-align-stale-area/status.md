Issue: #228

# Color Alignment's input area: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/lens-align-stale-area`, cut from `develop` at
`1a1dc44`.

**Status: Blocked** on a ruling (see Requirements issues). The fault the issue
describes does not occur: `lensAlign` cannot read an earlier render's input
area, because everything its area callback depends on is in the graph's digest.
No source changed. The branch adds three guard tests and this file. No UI
changed, so no design review.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Suspected fault** (from #87's engineer, `docs/features/lens-corrections/status.md`
F1). A Core Image context reuses what it prepared for an earlier render whose
graph has the same digest, and a kernel's area callback (ROI) is not in the
digest. `lensAlign`'s callback depends on the alignment values, so a live drag
of Red/cyan or Blue/yellow on a JPEG could read the area an earlier value
needed and repeat edge pixels.

**Steps to reproduce** (as the issue asks). Render Color Alignment with one
pair of values, then with another, through one context. Compare the second
render with the same graph rendered in a fresh context.

**Expected.** Each render matches a fresh context's render.

**Actual.** It matches, on every variant tried (at `1a1dc44`, macOS 27.2):

- `AdjustmentRenderer.align` alone, and the whole renderer: 2000 × 1400 and
  640 × 480, `pixelGrid` and `lensGrid` scenes, half-float and float
  contexts, the whole extent, a 64 px corner tile and a quarter. Pairs went
  from values near 0 to ±50, from +50 to −50, and from 49.99 to 50.
  None of the 192 comparisons differed.
- Inputs that show a stale area: the scene through a blur (an intermediate that
  Core Image renders only for the area asked of it) and a JPEG decoded by
  `PreviewGenerator`. A bitmap input does not show one, because all its pixels
  are uploaded whatever is asked. No comparison differed.
- A live drag on a JPEG, at full size, through the whole pipeline, in a 64 px
  tile at the corner, as the loupe renders the visible area at 100%. Every
  value matched.

**The harness does see the fault when it exists.** These were temporary
experiments, not committed:

- *Same arguments, a different callback.* The `lensAlign` kernel was rendered
  twice in one context with the same values: first with an area callback too
  small (reach 1), then with the right one. The second render repeated the
  first's edge: 192 components in the tile differ from a fresh context's
  render, in RGBAh and RGBAf, with both sensitive inputs. So the context does
  reuse the area when the digest matches.
- *A value carried in a table image.* A kernel read its magnification from a
  1-pixel table (`CIImage(bitmapData:)`), and its callback used the same value.
  Two renders with different table contents went stale in one context (128
  components). So a bitmap image's contents are not in the digest.
- *Values as a `CIVector` argument instead of two floats.* No fault. Vector
  arguments are in the digest too.

**Root cause: there is no fault.** The digest carries a kernel's scalar and
vector arguments, not its callback. `lensAlign`'s callback reads only two
things. One is `center`, from the input's extent: an argument, and part of the
input's own graph. The other is `reach`, from the red and blue magnifications,
which the kernel takes as `Float` arguments. Any change that changes the area
also changes the digest. The only gap is two `Double` values that round to the
same `Float`. Their reach differs by less than 10⁻⁶ of a pixel at any corner,
which the callback's 2 px margin covers (bilinear needs 1 px).

#87's warp was exposed for a different reason. Its area depends on the
correction table, and the table is a bitmap image whose contents are not in the
digest. The failing pair in `LensCorrectionTests`, Manual 60 then −60 without
Constrain, has identical scalar and vector arguments and differs only in its
table. With the warp's key removed for a moment, that test failed as #87
recorded (2 of 2 runs). This also confirms the explanation above.

**Tests** (`Tests/PhotoCoreTests/LensAlignStaleAreaTests.swift`, suite "Color
alignment's input area"). All three pass with and without any change, because
there is nothing to fix. They are guards: they fail if a later change carries
the values in a way the digest doesn't see (a table image, say), or if a macOS
release changes what the digest holds.

- `tileSeesTheInputArea` (blurred scene, JPEG): with a callback that ignores
  the values, the tile comes out wrong. This proves the inputs and the tile can
  show a stale area, so the other two tests cannot pass because they hide one.
- `dragInOneContext`: a drag sequence (1/−1 … 50/−50, −50/50, 12/3) through one
  context, each value equal to a fresh context's render, component for
  component.
- `jpegDragInOneContext`: the same drag on a JPEG through `PreviewGenerator`
  at full size, in the corner tile.

## Rendering

No source changed, so no golden moved and nothing is rendered differently. No
`PreviewCacheKey.currentPipelineVersion` bump and no migration. The keyed clamp
the issue proposes was not added. It would fix nothing. It is not
guaranteed byte for byte either: `RAWDecodeGraph.keyed` notes the GPU may
compile the arithmetic before it differently, and #55 measured differences of 1
to 4 levels. That change would need a pipeline bump and the owner.

## Build and test

| When | `swift build` | `swift test` |
| --- | --- | --- |
| Baseline 1, `1a1dc44`, clean | pass | 1249 tests in 178 suites, pass |
| Baseline 2, `1a1dc44`, clean | pass | 1249 tests in 178 suites, pass |
| After 1, with the guard tests | pass, no new warnings | 1252 tests in 179 suites, pass |
| After 2, with the guard tests | pass | 1252 tests in 179 suites, pass |

`swift test --filter LensAlignStaleAreaTests`: 3 tests (4 cases), pass,
about 0.7 s alone.

No debug-script check: no UI or behavior changed.

## Requirements issues

- **RQ-1. The issue's premise does not hold.** Options:
  - (a) Close #228 as not planned ("not reproducible: the alignment values are
    kernel arguments, which are in the digest"). Merge the guard tests from
    this branch as a test-only bug branch, through code review and QA without
    sign-off or Ship.
  - (b) Close #228 as not planned and drop the branch.
  - (c) Add the keyed clamp anyway, as a precaution. Not recommended: it fixes
    nothing measurable, may change bytes and needs a pipeline bump.

  Recommendation: (a). The tests cost under a second, and they guard against
  a later change that would bring the fault in for real.

## README

No changes to requirements, build commands or the repository layout.

## Review findings

None yet.
