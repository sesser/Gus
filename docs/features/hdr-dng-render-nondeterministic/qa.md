# A render of an HDR DNG is not deterministic: QA

Owner: qa-tester. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`. Bug fix, issue #181.
Tested: `bug/squash-top-10` at 7047bad, on a Mac16,8 (M4 Pro), macOS 27.2.1 (26B131), Xcode SDK 27.2.

## Verdict
Passes. The fault reproduces without the fix on a second, different HDR merge (24 renders gave 4 different results) and gives one result with it, for both the SDR render and the HDR rendition; the two always-run tests fail without the fix and pass with it. The issue's own file (`P1180234-HDR.dng`) is not on this Mac, so the engineer's 24-of-24 `photocli` measurement on it is taken from `status.md`, not repeated.

## Acceptance criteria
The criteria are the Bug section of `status.md` and the issue.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| The same file and stack render the same pixels every time, in-process, several at once (previews, exports) | Test | `LinearDNGRenderSoakTests.rendersAreTheSame` with `LINEAR_DNG_SAMPLE` set; Script S1 | Pass |
| The HDR rendition (`hdrImage`) is the same every time | Test | `LinearDNGRenderSoakTests.hdrRendersAreTheSame`; Script S1 | Pass |
| A linear DNG's decode is rendered whole into a bitmap, with the same pixels as the decoder's image within two half-float roundings | Test | `LinearRawDecodeTests.linearDNGDecodeIsRenderedWhole`, `reducedLinearDecodeIsRenderedWhole` | Pass |
| Camera raws keep the lazy decode (nothing changes for them) | Test | `LinearRawDecodeTests.cameraRawDecodeStaysLazy`; full `GoldenTests` and `RAWDecodeTests` in the full run | Pass |
| Empty and infinite images are not rendered; which files count as linear | Test | `emptyAndInfiniteImagesAreNotRendered`; `PreviewTests.dngLayoutDescribesRawImages` | Pass |
| The issue's `photocli render` on `P1180234-HDR.dng`, 16 runs in separate processes, one result | Script | Not run: the file is not on this Mac. Engineer: 24 of 24 the same (`status.md`). Separate processes on a different merge did not show the fault even on `develop` (S2), so only the in-process soak discriminates | Open: the file is not here; no person check can be given without it |
| Rendering change is bounded and documented (edited linear DNGs differ slightly; unedited and white balance only: bit for bit) | Review | `status.md` "Rendering change"; `PreviewCacheKey.currentPipelineVersion` is 10 on this branch (from #71), which covers it | Pass |

Tests that fail without the fix: in a scratch copy of the branch with `PreviewGenerator.swift` put back to `develop`'s, `linearDNGDecodeIsRenderedWhole` and `reducedLinearDecodeIsRenderedWhole` failed (`decoded.image.cgImage` is nil: the decode stayed lazy), and both soak tests failed (S1). `cameraRawDecodeStaysLazy` passes either way, as it should.

Full run: `swift test` 1032 tests in 153 suites passed, 1 known issue. `Scripts/build-app.sh all` built.

## Findings
None. Two notes for the main session, neither a defect in the fix:
- Memory: each linear DNG decode now holds a half-float bitmap (127 MB for a 16 MP merge) until released, with no cap (`status.md` Cost, code review C1). The owner's call; not tested.
- The soak is opt-in. `CLAUDE.md`'s command list does not have `LINEAR_DNG_SAMPLE=… swift test --filter LinearDNGRenderSoakTests` yet (the engineer proposes it; the owner's section).

## Scripts
S1, the soak on a real HDR merge that is on this Mac: `/Users/randy/gus-scratch/photos/2016-05-21/10M10354-HDR.dng` (Lightroom 6.5 HDR merge, 4608 x 3456, linear raw, 16-bit float, Adobe Deflate; read only). 24 renders, 6 at once on engines of their own:

```
LINEAR_DNG_SAMPLE=/Users/randy/gus-scratch/photos/2016-05-21/10M10354-HDR.dng swift test --filter LinearDNGRenderSoakTests
```
- Branch: both tests passed (one distinct result of 24, SDR and HDR).
- Scratch copy of the branch with `PreviewGenerator.swift` from `develop`: both failed. `rendersAreTheSame`: "4 different renders: [1, 3, 5, 15]"; `hdrRendersAreTheSame`: "4 different HDR renders: [1, 1, 1, 21]".

This is not the issue's file or codec (JPEG XL, half float) but the same symptom, and it is stronger evidence than the synthetic file, which does not trigger the fault.

S2, the issue's `photocli` stack on that file, 16 runs each in separate processes, `develop` against the branch (every run passes `--library-root` on a scratch library):

```
photocli render --input <file> --out hdr/<n>.png --long-edge 800 --library-root <scratch library> --set whiteBalance.preset=tungsten --set whiteBalance.temperature=2850 --set whiteBalance.tint=0 --set exposure.ev=0.5 --set sharpen.amount=60
```
`develop`: 16 of 16 the same, branch: 16 of 16 the same, and the two differ from each other (the documented rendering change). So separate processes did not trigger the fault on this file; the in-process soak did.

## For a person
Nothing. The issue's own file and the macOS 15 and 26 behavior are not testable here; the owner has said they will not test macOS 15 or 26.

## Follow-up
Run `LinearDNGRenderSoakTests` on every new macOS, as for `RAWEdgeSmearTests` (the fault and the fix were seen on macOS 27.2 only).

## Summary for the issue
QA passes (#181). On another HDR merge the in-process soak fails without the fix (4 different results of 24, SDR and HDR) and gives one result with it; the two always-run tests fail without the fix and pass with it. The issue's own file is not on this Mac (engineer's measurement not repeated). Nothing for a person. `docs/features/hdr-dng-render-nondeterministic/qa.md`.
