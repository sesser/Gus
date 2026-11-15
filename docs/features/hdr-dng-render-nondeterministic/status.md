Issue: #181

# A render of an HDR DNG is not deterministic: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"), from #170's code review. Branch `bug/squash-top-10`, on top of
`cb0df4c` (the #64 fix).

**Status: Done.** Next: code-reviewer, then qa-tester. No UI changed, so no
design review. One open question for the owner (the preview cache, below).

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `cb0df4c`, macOS 27.2, Apple silicon).
1. `P1180234-HDR.dng`: a Lightroom Classic 15.2.1 HDR merge, 4592 x 3448,
   half-float linear raw, JPEG XL compressed in 432 x 384 tiles, with a
   reduced linear raw copy (so it decodes at full size).
2. Run 16 times:
   `swift run -c release photocli render --input P1180234-HDR.dng --out o<N>.png --long-edge 800 --set whiteBalance.preset=tungsten --set whiteBalance.temperature=2850 --set whiteBalance.tint=0 --set exposure.ev=0.5 --set sharpen.amount=60`
3. Compare the files' SHA-1s.

**Expected.** One result: the same file and stack render the same pixels
every time (previews, exports, `photocli`).

**Actual.** Two results (5 and 11 of 16 here; 13 and 3 in the issue), and
sometimes three. They differ in one quarter of the frame (the bottom left,
x 0 to 403 and y 295 to 600 of 800 x 601): about 0.3% darker with different
fine texture, 19% to 25% of the samples, up to 4750 of 65535. Also in the
app: the HDR rendition (`hdrImage`) varies the same way, and when several
renders of the file run at once, as previews and exports do, about one in
four differs (in-process, 6 engines at once, 4 rounds).

**Bisection** (each line 10 to 16 runs in separate processes unless noted).
- The issue's stack minus each setting: white balance alone, +0.5 EV alone
  and no edits are each the same every time; Sharpening 60 alone varies. So
  the HDR path and white balance are not it.
- Within sharpening (`AdjustmentRenderer.sharpen`): Detail 100 (no halo
  limit, so no neighborhood minimum and maximum) is stable; Detail 0, 50 and
  99 vary; Detail 100 with Masking 50 is stable.
- Clarity, Dehaze, Shadows and Luminance noise reduction on the same file:
  stable. Sharpening on two camera raws (RW2, CR2) decoded at full size:
  stable. The other HDR merge in the folder (`P1180217-HDR.dng`): varies.
  A synthetic uncompressed 16-bit linear DNG at the same size: stable.
- The same sharpening graph over the decode rendered to a float bitmap, or
  over a tiled image provider holding the same pixels: stable (and equal to
  one of the two results).
- The decoder's own image (plain `CIRAWFilter`): bit for bit the same for
  any region asked for (whole, a quarter, 864 x 1152, 500 x 500), and when
  eight regions are asked for at once on eight contexts (6 rounds).
- `CI_PRINT_TREE`: the render is split into four parts (the program
  graph's `rois`); the varying quarter is the third part. The decoder's
  image is read by more than one program per part (the unsharp mask with
  the decode inline, the blur's processor and the minimum and maximum
  through an intermediate). A run of each result had the same programs and
  regions (only the digests, which change from run to run, differed).
  With `dump-intermediates` set (which serializes the render), 14 runs in a
  row gave the majority result.

**Root cause.** A timing-dependent fault inside Core Image when it renders
the system RAW decoder's lazy image of these linear DNGs (half-float, JPEG XL
compressed) in parts, with the image read by several programs: now and then
one part comes out different. It is not in the decoder's output (region- and
concurrency-independent, measured), not in our graph (stable over a bitmap
or a provider), and not specific to white balance or the HDR path. Which
internal Core Image step races could not be seen from outside (dumping the
intermediates hides it). It cannot be fixed in our code, but it can be
avoided deterministically: never hand the lazy decoder image of a linear DNG
to the rest of the graph.

**The fix.** `PreviewGenerator.decodeRAW` renders a linear DNG's decode whole
into a half-float bitmap before returning it (`LinearRawDecode.rendered`,
new; `DNGLayout.hasLinearRaw`, new: the main raw image is PhotometricInterpretation
34892). Everything downstream (previews, exports, `photocli`, the HDR
rendition, the fringe picker, Color Alignment's measurement, the sharpening
map's refinement, the 100% renderer and the live session) reads that bitmap.
Camera raws keep the lazy image. If the whole render fails (logged), the
decoder's image is used as before. Half float is the precision the loupe's
live session already keeps a decode in (`LiveRenderSession`,
`LiveRegionRenderer` materialize it the same way).

**Tests that fail without the fix** (`Tests/PhotoCoreTests/LinearRawDecodeTests.swift`,
checked by reverting `PreviewGenerator.swift` only, twice):
- `LinearRawDecodeTests.linearDNGDecodeIsRenderedWhole` and
  `reducedLinearDecodeIsRenderedWhole` (always run; synthetic linear DNG
  from `SyntheticDNG`'s new `linearRaw` option): the decode is backed by a
  rendered bitmap (`CIImage.cgImage`), the same pixels as the decoder's
  image within two half-float roundings (2⁻¹⁰ relative; measured 0.000975).
  Fail without the fix (`cgImage` nil), deterministically.
- `LinearDNGRenderSoakTests` (`LINEAR_DNG_SAMPLE=path`, a real HDR merge):
  `rendersAreTheSame` (the issue's stack, 24 renders, 6 at once on engines of
  their own) and `hdrRendersAreTheSame` (the same for the HDR rendition).
  Without the fix: 2 results each run (8:16 and 4:20; HDR 2:22 twice). With
  it: 1. The synthetic file does not trigger the fault (uncompressed
  integer), so this check needs the real file.

Also: `cameraRawDecodeStaysLazy` (a Bayer DNG keeps the lazy image),
`emptyAndInfiniteImagesAreNotRendered`, and `hasLinearRaw` added to
`PreviewTests.dngLayoutDescribesRawImages`.

## Rendering change

The fix changes how some edits of linear DNGs render, slightly, and makes
each the same every time. Measured on `P1180234-HDR.dng` at 800 px, old
build against new (levels of 65535, mean absolute difference over all
samples):

| Stack | Change |
| --- | --- |
| None | 0 (bit for bit) |
| Tungsten white balance | 0 (bit for bit) |
| Shadows +50 | 0.9 |
| Exposure +0.5 | 5.9 |
| Clarity +40 | 6.3 |
| The issue's stack | 7.1 (max 692) |
| Sharpening 60 | 38 (12 samples over 2048, max 4750) |

A 32-bit float bitmap instead of half float was tried: it leaves +0.5 EV
unchanged but changes unedited renders (mean 6), so half float was kept:
unedited previews, by far the most, stay as they were. Camera raws, JPEGs and
every other file are untouched (the code path is linear DNGs only). No
golden moved (the goldens have no linear DNG; full `GoldenTests` pass).

**Not bumped:** `PreviewCacheKey.currentPipelineVersion` (see Open questions).

**Cost** (`photocli render`, the issue's stack, 4 runs each): render time
0.45 s to 0.49 s, peak memory 216 MB to 347 MB (the bitmap is 8 bytes a
pixel, 127 MB for this file). Linear DNGs only. In the loupe a linear DNG is
now rendered whole twice when the live session decodes it (once here, once
into its own half-float copy), one more whole render than before (not timed
in the app).

## Results

Baseline at `cb0df4c`: `swift build` clean; the bug reproduced (above).

| Check | Result |
| --- | --- |
| `swift build` | Clean, no new warnings (the test build's warnings are in `SmartAlbumTests`, `VirtualCopiesTests` and `WhiteBalanceAcrossDecodersTests`, untouched) |
| `swift test --filter "LinearRawDecodeTests\|dngLayoutDescribesRawImages"` | 5 tests passed |
| `LINEAR_DNG_SAMPLE=…/P1180234-HDR.dng swift test --filter LinearDNGRenderSoakTests` | 2 tests passed (fail without the fix, above) |
| `photocli render`, separate processes, fixed build | The issue's stack 24 of 24 the same; Detail 99 12/12; 2000 px 12/12; `P1180217-HDR.dng` 12/12 |
| `swift test` (full) | 1014 tests in 148 suites passed, 1 known issue (`LiveSessionTests`, as before) |

No debug-script checks: no UI change. The app paths share `PreviewGenerator.decode`
(see The fix); the HDR rendition is covered by `hdrRendersAreTheSame`.

## Bug section mapped to checks

| Item | Check |
| --- | --- |
| The issue's `photocli render`, the same every time | `rendersAreTheSame` (in-process, 6 at once), and 24 separate `photocli` runs |
| HDR rendition the same every time | `hdrRendersAreTheSame` |
| A linear DNG's decode is rendered whole, same pixels | `linearDNGDecodeIsRenderedWhole`, `reducedLinearDecodeIsRenderedWhole` |
| Camera raws unchanged (still lazy) | `cameraRawDecodeStaysLazy`; full `GoldenTests` and `RAWDecodeTests` |
| Which files count as linear | `PreviewTests.dngLayoutDescribesRawImages` |

## Open questions

- **For the owner: bump the preview cache's pipeline version or not.**
  `CLAUDE.md` asks for a bump when the rendering of an existing stack
  changes, and this changes edited linear DNGs (table above). I did not
  bump, because a plain bump does more than this needs: cache keys can't
  tell a linear DNG from any other file, so every preview in the library
  would be made again, and offline masters' previews would be lost until
  their volume returns. The existing carry-over (`versionCarriedOver` 8 to 9)
  would also carry version 8's previews of linear DNGs into a version 10, and
  `WhiteBalanceAcrossDecodersTests` pins `currentPipelineVersion == 9`.
  Options:
  (a) no bump: cached previews of *edited* linear DNGs stay as they are
  (at most the differences above, already one of two random results before)
  until the photo is edited again or the cache is deleted; unedited ones are
  unchanged anyway. My recommendation.
  (b) bump to 10 with a carry-over of version 9 that leaves out previews
  under a non-identity edit stack (they are made again; unedited ones
  survive). Needs a design of the carry-over rule and its tests.
  (c) plain bump to 10, rewriting the carry-over: every preview is made again.
- **Scope of the rule.** It covers DNGs whose main raw is linear raw (HDR
  merges, panoramas, enhanced DNGs, Apple ProRAW). Floating-point Bayer
  DNGs and JPEG XL compressed Bayer DNGs stay lazy: I had no such file to
  test, and the synthetic ones are uncompressed.
- **macOS versions.** The fault and the fix were seen on macOS 27.2 only.
  `LinearDNGRenderSoakTests` is the check to run on a new macOS, like
  `RAWEdgeSmearTests`.

## README

No change to requirements, build commands or layout. New opt-in test
variable `LINEAR_DNG_SAMPLE` (`LinearDNGRenderSoakTests`); proposed for
`CLAUDE.md`'s command list (the owner's section):
`LINEAR_DNG_SAMPLE=path/to/merge-HDR.dng swift test --filter LinearDNGRenderSoakTests`.

## User guide

No change: nothing a person does or sees changes, other than renders of HDR
merges being the same each time.
