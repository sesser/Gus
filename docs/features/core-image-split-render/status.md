Issue: #253

# Halves that don't line up at 100% (Core Image split render): status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/core-image-split-render`, from `develop` at
`9bcac27`. The fix was written on `feature/hdr-merge` (commit `079bf79`), where
the owner found the bug at sign-off; it is cherry-picked here as `390cb83` and
made independent of that branch.

**Status: Done** (2026-11-21). Next: code-reviewer, then qa-tester. No UI
changed, so no design review.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Report.** A 5472 × 3648 16-bit Display P3 TIFF (the owner's file, written
by the HDR merge of #150, where this was found; the merge is not needed to
reproduce it) with Exposure +1.05, Contrast +66, Highlights −45, Blacks −100:
fine at Fit; at 100% the picture showed two halves that didn't line up, the
left part a different place in the photo than the right, with a hard vertical
seam. A 4592 × 3448 TIFF of the same kind did not show it for the owner.

**Steps to reproduce** (before the fix; macOS 27.2, Apple silicon).
1. In the app: a scratch library and a bundle copy with its own identifier;
   any 5472 × 3648 16-bit RGB TIFF (uncompressed, Display P3, orientation 1)
   in a folder. Debug script:
   `windowsize 2200 1300; addfolder <folder>; waitimport; focus 0; loupe;
   adjust exposure 1.05; adjust contrast 66; adjust highlights -45;
   adjust blacks -100`, then eight times
   `zoom; wait 2; pan 2400 0; wait 7; snapshot /tmp/z<n>.png; zoom; wait 3`.
2. Headless: render such a TIFF (or a PNG) of 16 to 48 MP with Highlights −45
   or any Shadows at full size several times, each on a fresh `RenderEngine`
   (`PreviewGenerator.cgImage`, the loupe's 100% rendition).

**Expected.** The photo at 100%, the same every time.

**Actual.** In the app, 8 of 8 zooms on the owner's file showed the seam: left
of x = 2736 (half the width) the view showed pixels from the photo's right
part. Headless, about one render in three came out with the left half
repeating the right (7 of 24, 12 of 36, 8 of 30 in separate runs), at
4592 × 3448 as often as at 5472 × 3648, for PNGs and TIFFs written by other
means too, and at 6000 × 4000 and 8192 × 5464. Which process gets it is timing
(one run of 5472 × 3648 had 0 of 8, the next 4 of 12): the smaller TIFF not
showing it for the owner is that timing, not its size. JPEGs and HEICs go
through the same decode and are exposed the same way in principle.

**Root cause.** Not the file: the owner's TIFF and a 4592 × 3448 one have the
same layout (uncompressed chunky 16-bit RGB strips, Display P3, orientation
1, 300 ppi; only the size and RowsPerStrip differ), and a PNG fails the same
way. It is a fault inside Core Image, seen from outside with
`CI_PRINT_TREE=4`:
- A full-size render of this size to a GPU destination (an IOSurface or a
  texture) is split into two parts (`render_to_surface … rois=[0 0 5472
  3648]/2`, `intermediatesLimit=256MB`).
- A full-size non-raw decode was `CIImage(contentsOf:)`, which Core Image
  reads from the CPU: each part copies its share of the file into a pooled
  texture (`CGImageRef … rois=[0 0 2939 3648],[2533 0 2939 3648]`), and the
  parts are encoded one after the other without waiting.
- Local tone (Shadows, negative Highlights) reads the photo in several
  programs per part. Now and then the right part's copy lands before the left
  part's programs have read theirs: the right part's pixels under the left
  part's own gain, which is the signature in the bad renders.

Measured to separate the causes (same process, fresh engines, Highlights
−45): the same graph over a texture, still split into the same two parts,
0 of 30; the file read directly 8 of 30; a render to a bitmap (which reads
each part back) 0 of 69; the gain image alone 0 of 24. The copy of the file
into a texture is itself such a split render (`render_to_texture … /2`), and
`LiveRegionRenderer.materialize` (the 100% base for live frames) made exactly
that copy: a second route to the same seam.

**Tests that fail without the fix** (the copy turned off in
`PreviewGenerator.decodeWithImageIO`, `let image = lazy`; three runs on this
branch, 2026-11-21, each the same):
- `ImageIOFullDecodeTests.largeRenderKeepsItsParts` ("A full render of a 20 MP
  TIFF with Highlights keeps its parts in place"): 1 of 16 renders showed the
  right half on the left, and 15 of 15 differed from the first, in each of the
  three runs.
- `ImageIOFullDecodeTests.fullDecodeIsResident`, and the `decoded.url == nil`
  precondition of `renderUnchanged`: the full-size decode still reads the file
  (deterministic).
- `LensAlignStaleAreaTests.tileSeesTheInputArea` (JPEG case): the lazy decode
  shows a stale input area again (deterministic; see Tests).

## The fix

`PreviewGenerator.decodeWithImageIO` at full size copies the decode into a
32-bit float texture in the working space (`Preview/ResidentDecode.swift`,
new), in bands of at most 4 megapixels, each finished before the next starts
(a copy that small is never split), and the rest of every graph reads the
texture: no render reads the file from the CPU any more, however it is split.
Every full-size use goes through it: the loupe's 100% rendition, the 100%
base for live frames, export, `photocli render`, the sharpening map's
refinement, the fringe picker. `PreviewGenerator.outputSize` (the loupe's
early size) measures the lazy graph and stays a header read (`forSizeOnly`).
Previews and thumbnails are decoded smaller by ImageIO and are untouched.
Larger than 16384 pixels on a side (one texture's limit), no Metal device, or
a failed copy: the decode is read lazily as before, and logged.

The texture is rendered and read unflipped. Read through a flip transform (as
a first version did, and as `LiveRegionRenderer.materialize` did), a texture
was sampled one row off by run-time kernels: a heal's far pixels came out 0.4%
brighter on a gradient (`SpotTests.everyDecoderHeals` caught it), and the 100%
renderer's crop-and-straighten region drifted from the whole render
(`LiveRegionRendererTests`, 12 values over tolerance). So
`LiveRegionRenderer.materialize` now fills and reads its texture unflipped
too; with both, that test is back to 6 steps at worst, under its tolerance.

Files: `Sources/PhotoCore/Preview/ResidentDecode.swift` (new),
`Sources/PhotoCore/Preview/PreviewGenerator.swift` (`forSizeOnly` through
`rendering`, `outputSize`, `decode` and `decodeWithImageIO`),
`Sources/PhotoCore/Edits/LiveRegionRenderer.swift` (`materialize` unflipped).

## The one render change

Measured on the owner's file and a 20 MP JPEG of it, file against copy, in
8-bit output steps:
- Unedited: bit for bit in float (`renderUnchanged`).
- The owner's stack, a heal, an export-style resize to 2048 px: at most one
  step. Core Image may place its half-float intermediates differently over the
  copy; `renderUnchanged` checks the owner's stack and a heal against the 100%
  renderer's derived tolerance (one half-float rounding times the stack's
  gain).
- **Straightened or rotated (not quarter-turned) full-size renders of JPEG,
  HEIC, PNG and TIFF photos**: Straighten 2° (alone or with the owner's stack)
  gives worst 20 to 37 steps at a few high-contrast edges, 0.01% to 0.15% of
  values more than one step off, mean under 0.08 of a step. Reading the file,
  Core Image interpolated its encoded values before linearizing them; the copy
  is linear, so resampling now interpolates linear light. Raws were always
  resampled so (their decode is linear), and so were the loupe's live frames
  at 100% (their base is a linear texture): the full-size render now agrees
  with them.

No golden moved (goldens render their scenes from memory and a DNG).
**No `PreviewCacheKey.currentPipelineVersion` bump:** no cached preview or
thumbnail comes from this decode (they come from ImageIO's reduced decode,
unchanged), so nothing cached is stale. Only full-size renders (the 100%
rendition, exports, `photocli render`) of straightened or rotated non-raw
photos change, as above.

**Cost.** One more pass over the photo per full-size decode, and 16 bytes a
pixel of GPU memory held while the decode is in use (320 MB for 20 MP),
released with it. Measured for 20 MP, decode and render (on
`feature/hdr-merge`, same code): TIFF 0.083 s against 0.073 s, PNG 0.36 s
against 0.30 s, JPEG 0.09 s against 0.04 s.

## Alternatives dropped

- **A `CGImage` from `CGImageSourceCreateImageAtIndex`** instead of
  `CIImage(contentsOf:)`: clean on PNGs (0 of 36) but 8 of 16 on the 16-bit
  TIFF. It only changed the timing.
- **Rendering in bands of 1 to 4 MP**: no swaps on the owner's stack, but a
  stack with masks is still split inside a band (the masks' whole-photo
  estimates), each part copying the file. Cost +19% to +200%.
- **A larger `CIContextOption.memoryTarget`** (`kCIContextMemoryLimit`, macOS
  14): 1 GB keeps the owner's 20 MP render whole, but a stack with masks is
  split even at 2 GB.
- **A copy in the file's own color space and encoding** (16-bit unorm), meant
  to be read exactly as the file: bit for bit on the 16-bit TIFF, but JPEGs
  differed even unedited, and straightened regions by up to 229 steps.
- **Half float instead of float32** for the copy: half the memory, but about a
  third of the values of an edited render changed (up to 0.005).

## Tests

`Tests/PhotoCoreTests/ImageIOFullDecodeTests.swift` (new, suite "Full-size
ImageIO decodes", `.serialized`: each render holds a 20 MP photo):
- `fullDecodeIsResident`: the full-size decode of a TIFF and a JPEG no longer
  reads the file (`CIImage.url` nil; Core Image's own reader keeps it), and the
  measuring decode (`forSizeOnly`) still does.
- `largeRenderKeepsItsParts`: a 5472 × 3648 TIFF laid out as the owner's
  (uncompressed chunky 16-bit RGB, no alpha, Display P3, written with ImageIO
  in the test), the owner's values, 16 full renders on four fresh engines: no
  left half repeating the right, all the same.
- `residentCopyIsTheFile`: a copy made in several bands gives the file's
  values exactly.
- `renderUnchanged` (JPEG and 16-bit TIFF): unedited bit for bit; the owner's
  stack and a heal within the 100% renderer's derived tolerance.
- `bandsCoverTheExtent`: bands top first, no gaps or overlaps, each within
  `bandPixels`, offset extents placed right.
- `fullDecodeIsOriented`: an EXIF-rotated JPEG renders as Core Image's own
  reading of it.

Changed: `LensAlignStaleAreaTests.tileSeesTheInputArea`'s JPEG case (#228's
guard) asserted that the pipeline's full-size JPEG could show a stale input
area, because its lazy decode rendered only the area asked. The copy has every
pixel, as a bitmap's, so that case now pins the opposite (no area can be
stale); the blurred-scene case remains the guard that the tests can see a
stale area. For code review to confirm.

Made independent of `feature/hdr-merge` on this branch: the large TIFF is
written with ImageIO in the test (the merge's TIFF writer is not on
`develop`), and the suite is a top-level `.serialized` suite (the merge
branch's `MemoryHeavy` parent suite is not on `develop`). **Heads-up for
#150:** when `feature/hdr-merge` takes `develop` after this merges, its copy of
`ImageIOFullDecodeTests` conflicts with this one; keep this file, and nest it
under `MemoryHeavy` there if wanted.

## Baseline and results

- Baseline: `develop` at `9bcac27` builds clean (the two warnings in
  `SmartAlbumTests` and `VirtualCopiesTests` are older). The cherry-pick
  `390cb83` as it came did not build its tests on `develop` (`MemoryHeavy`
  and `MergeOutput.writeTIFF` not found); fixed as above.
- `swift build --build-tests` (Xcode's toolchain, Swift 6.4.2, macOS 27.2
  SDK): clean, no new warnings.
- Older SDK: `swift build --build-tests --build-system native --sdk
  /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` (SwiftPM's native
  build system, which passes the SDK to `swiftc`; Swift Build ignored `--sdk`
  and compiled against 27.2) builds every target, the tests included, against
  the macOS 26.5 SDK (PhotoUI needed `-Xswiftc -plugin-path` to Xcode's
  SwiftUI macro plugin, a Command Line Tools limit unrelated to this change).
  Compiler: Swift 6.4.2; Swift 6.2 itself was not run here. The APIs the fix
  uses (`CIRenderDestination(mtlTexture:commandBuffer:)`,
  `startTask(toRender:from:to:at:)`, `CIImage(mtlTexture:options:)`,
  `.rgba32Float`) are macOS 10.13 or older, and `LiveRegionRenderer` already
  used them on `develop`.
- Affected suites (`ImageIOFullDecodeTests`, `LensAlignStaleAreaTests`,
  `LiveRegionRendererTests`, `SpotTests`): 47 tests in 6 suites passed.
- `swift test`: 1282 tests in 184 suites passed (83.0 s). No golden moved;
  `UPDATE_GOLDENS` was not run; `PreviewCacheKey.currentPipelineVersion`
  unchanged (13).
- `Scripts/build-app.sh all`: both bundles build.
- Debug-script check: **not completed here.** A bundle copy
  (`me.sesser.gus.debugtest.split`, re-signed ad hoc) on a scratch library
  imported a 5472 × 3648 16-bit RGB TIFF written with ImageIO and applied the
  owner's values, but the loupe never reached 100%: a shell launch has no key
  window (`print responder`: `key nil`), so `zoom` (the `Z` key) is not
  handled, and `open -W -n` was not activated either; `zoomstep in` sets the
  target magnification (`print loupe`: 1.000) but its animation did not
  advance and every snapshot stayed at Fit. Bringing the process forward by
  System Events was not tried, so as not to take over the owner's screen. The
  fix was checked in the app on `feature/hdr-merge` (same code) on the owner's
  copied file: the unfixed bundle showed the seam on 8 of 8 zooms, the fixed
  one on none, all eight snapshots byte for byte the same. For QA: the Bug
  section's step 1 with the window active.

## Not verified

- **macOS 15 and macOS 26**: whether the fault exists there and whether the
  fix holds; CI is the first run (the APIs used are macOS 10.13 or older).
- **The HDR rendition** of a gain-map or HLG/PQ photo (`decodeHDR`) still
  reads `CIImage(contentsOf:)`; it renders to a bitmap, which never showed the
  fault, but it was not soaked.
- **Camera raws** (system decoder) were not soaked at full size with Shadows;
  #181 found them stable.
- **Photos larger than 16384 pixels on a side** keep the lazy decode, so they
  stay exposed.
- **Memory**: 16 bytes a pixel of GPU memory per full-size decode in use; not
  measured under an export of many large photos at once.

## README

Nothing: no requirement, build command or repository layout changed.

## User guide

Unchanged: nothing it describes changed (the guide doesn't describe the
resampling of straightened full-size renders).

## Proposed follow-ups

- **Watch: a split render can read another part's copy of a CPU-side image**
  (`bug`, or a watch item like `RAWEdgeSmearTests`; PhotoCore). Body: The
  fault behind #253 is Core Image's (macOS 27.2) and is avoided for full-size
  ImageIO decodes only (`ResidentDecode`). Still exposed in theory: the HDR
  rendition's `decodeHDR` (renders to a bitmap, never seen to fail), photos
  over 16384 pixels on a side, and any other lazily read image in a render
  large enough to be split. On every new macOS, soak camera raws, gain-map
  photos and a 20 MP 16-bit TIFF at full size with Shadows and negative
  Highlights (`swift test --filter ImageIOFullDecodeTests`, plus a longer
  soak like `RAW_CONTEXT_SOAK`); if Core Image no longer splits wrongly,
  `ResidentDecode` can go and the linear resampling of straightened non-raw
  renders can be reconsidered.

## Review findings

None yet.

## Open questions

None.
