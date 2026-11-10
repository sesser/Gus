# RAW edge smear: implementation status

Owner: swift-macos-engineer. Bug fix (no `prd.md` or `design.md`,
`docs/WORKFLOW.md` "Bug fixes") for GitHub issue #55. Branch
`bug/raw-edge-smear`, cut from `develop` at `13b1f90`. Nothing is committed
yet.

**Status: Done.** Ready for the second code review, then qa-tester. The
owner chose how to fix it on 2026-11-10 (relayed by the main session): every
RAW decode gets a render graph of its own, on the shared contexts ("The
fix"). The first version of the fix, a context of its own per decode, was
reviewed and taken out again for what it cost in memory ("C1"). No UI
changed, so no design review.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `13b1f90`, macOS 27.2). Import a folder of
Panasonic RW2 files shot at several focal lengths with one camera and the same
settings (the owner's `2026-11 Kayaking`, a DMC-ZS100), by card import or by
dragging the folder onto the library window. Open the photos in the loupe.

In a test, one process: render `P1040027.RW2` (9.1 mm), then `P1040058.RW2`
(12.7 mm), through one `PreviewGenerator`.

**Expected.** Every photo looks the same whatever was rendered before it.

**Actual.** Some photos (4 of the 54 in that folder, in file order) have their
left and right edges smeared: the outermost pixels of the corrected image
repeated outward, 3 to 4% of the width a side. Which photos depends on the
order of decoding. Measured before the fix, each against the same file
rendered alone:

| Path | Before the fix |
| --- | --- |
| Cached preview and thumbnail (import, background generation) | smeared |
| Loupe live frames (`LiveRenderSession`) | smeared |
| Live frames at 100% (`LiveRegionRenderer`) | smeared |
| Export resized to a 2048 px long edge | smeared |
| Export at full size | clean with this pair |
| Color Alignment, Align automatically | other values stored: red 5.19, blue −2.55 instead of 5.13, −2.43 |
| Auto Exposure, Auto White Balance (256 px draft) | same values with this pair |

So this is wider than the issue says: an export of several raws in one run
can be smeared too, and Align automatically can store values measured on a
smeared decode. A photo rendered alone in a process (`photocli render`, a
one-photo export after launch) is always clean.

**Root cause.** A fault in Core Image's RAW decoder, in state that belongs to
a `CIContext`.

- The decoder's lens correction is a kernel, `radialLens(image, map, parms)`.
  `map` is a 51-entry table built from the file's lens data and handed over
  as an `IOSurface`. How much of its input the kernel reads (its region of
  interest) depends on that table: `P1040027` reads `[169 53 2862 2028]` of a
  3200 × 2134 decode, `P1040058` reads `[65 17 3070 2100]`.
- Core Image gives every node of a render graph a digest (`recipe=` in
  `CI_PRINT_TREE=1` output). The table is not part of it: the map node has
  the same digest for every file and every format checked, and two raws of
  one camera with the same settings have identical digests for the whole
  graph, the node that reads the raw data included.
- A context that is asked for a render whose graph has a digest it has seen
  reuses what it prepared the first time, the regions of interest included.
  `CI_PRINT_TREE` prints a graph only when the context builds one, and it
  prints nothing for the second file. The second file is then corrected from
  the area the first one needed. Where it needs more, the sampler clamps:
  the smear. A first file that needed more than the second leaves no visible
  fault, which is why it looks random.

That the context reuses the prepared graph is inferred, not documented. What
supports it: every change that gives the second render another digest makes
it clean, and so does emptying the context.

**Scope of the stale state** (step 1 of the task; `P1040027` then
`P1040058`, 2560 px, one process, plain `CIRAWFilter` and `CIContext` with
the engine's options):

| Change between the two renders | Second render |
| --- | --- |
| nothing | smeared |
| a new `CIRAWFilter`, from the URL or from `Data` | smeared |
| the filter made, or its `outputImage` built, before the first render | smeared |
| rendered on another thread | smeared |
| `isLensCorrectionEnabled = true`, or `false` then `true` | smeared |
| `isLensCorrectionEnabled = false` | clean (no correction) |
| first file's graph built but never rendered | clean |
| first file at another size (full size, or a 256 px draft) | clean |
| another raw without lens correction rendered in between | smeared |
| anything after the decode that changes the digest (an exposure change, a crop, a translation) | clean |
| `CIContext.clearCaches()` | clean |
| **a new `CIContext`** | **clean** |

So it is per context: not per process, thread, device or filter. Serializing
decodes and a new decoder per file do not help (each decode already has its
own filter; the fault needs no concurrency). A helper process is not needed.

**Candidates tried.** All but the two marked stop the smear; they differ in
what they rest on and what they cost ("C1" has the figures).

- *A kernel argument of its own for each decode* (a clamp to bounds no pixel
  reaches), on the shared contexts. **Chosen by the owner.** No memory or
  speed cost. Rests on how Core Image keys what it reuses ("The fix").
- *A context of its own for each RAW decode.* The first version of this
  fix. Nothing is shared, so it does not depend on how Core Image keys what
  it keeps. It left about 50 KB behind per decode for good and cost about
  10% on RAW previews. Taken out.
- *Contexts kept and lent to one decode at a time, emptied with
  `clearCaches()` before each loan.* Built and measured after the first code
  review: as much memory left behind and as slow as a new context each
  time, with one more rule (nothing may render in a context once it is
  given back, so nothing Core Image would defer). Taken out.
- *A move by a whole number of pixels and back, different for each decode.*
  Bit for bit, and it stopped the smear (648 of 648), but only as long as
  Core Image compares graphs before it folds the two moves into none. Not
  used.
- *Image properties different for each decode* (`settingProperties`).
  **Does not work**: it stopped the smear with one dictionary and not with
  another of the same size (4 of 54 smeared).
- *A crop larger than the image, different for each decode.* **Does not
  work** (33 of 648 wrong): Core Image drops it. These two are why the key
  is a kernel argument, which it cannot drop.
- *A helper process for RAW decodes, replaced every so many decodes.* The
  only way seen to have nothing shared and bounded memory. Not built: a
  large change.

**Tests that fail without the fix.**

- `RAWEdgeSmearTests` (`Tests/PhotoCoreTests/RAWDecodeGraphTests.swift`), on
  real files named by `RAW_EDGE_SAMPLES`. To see it fail, take the key out
  on this branch: in `PreviewGenerator.decodeRAW`
  (`Sources/PhotoCore/Preview/PreviewGenerator.swift`) change
  `RAWDecodeGraph.output(of: raw)` to `raw.outputImage`, which is what
  `develop` renders, and run
  `RAW_EDGE_SAMPLES=<Kayaking>/P1040027.RW2:<Kayaking>/P1040058.RW2 swift test --filter RAWEdgeSmearTests`.
  5 of its 7 cases fail: previews, export at 2048 px, live frames, the 100%
  region and Color Alignment (the rows marked smeared above). Full-size
  export and the auto measurements pass either way with this pair and are
  kept as guards. With the line as written all 7 pass (both checked on the
  final tree). `--filter RAWEdgeSmearTests` runs that suite alone.
- `RAWDecodeGraphTests` (same file) runs everywhere, CI included, without
  camera files. With that same change its source check fails
  (`rawFiltersAreMadeInKnownPlaces`). It cannot show the smear itself.

## The fix

Lens correction stays on (owner's decision). Every RAW decode gets a render
graph of its own, so a context never uses for one decode what it prepared
for another.

- `Sources/PhotoCore/Preview/RAWDecodeGraph.swift` (new):
  `RAWDecodeGraph.output(of:)` returns a RAW filter's image through
  `CIColorClamp` with bounds near ±10³⁰, different for every decode
  (`Key`: a process-wide serial as two 22-bit digits, each as steps of
  `Float` above 10³⁰, so 2⁴⁴ decodes have bounds of their own). The clamp
  passes every pixel through; its bounds are kernel arguments, which are
  part of the graph's digest.
- `PreviewGenerator.decodeRAW` takes the decoder's image from it. Every
  decode path goes through `decodeRAW`: previews, thumbnails, full-size and
  HDR renditions, export, `photocli render`, Auto Exposure, Color Alignment,
  the fringe sample, the live session's base, the 100% texture, the
  sharpening map's input, and `CameraFrame.fullFrameFilter`'s whole-sensor
  filter.
- `AutoAdjuster.whiteBalance` builds its own filter and takes its image the
  same way.
- Nothing else changed. The engine plumbing of the first version
  (`RenderEngine.isolated()`, `renderCount`, `Decoded.engine`,
  `Rendering.engine`, the `engine:` argument of `decode` and the eight call
  sites that passed it on) is gone: `RenderEngine.swift` and those files are
  as on `develop`. The diff against `develop` is one new source file, three
  changed lines of source, the pipeline version, and the tests.

**What it rests on** (also in `RAWDecodeGraph`'s comment, where the next
person will look). None of it is documented by Apple:

1. A context keys what it reuses on the digest of the whole graph being
   rendered. Observed on macOS 27.2: any change after the decode that
   changes the digest stops the fault, and `CI_PRINT_TREE` prints a graph
   only when the context builds one.
2. A kernel's arguments are in that digest. They have to be, or no filter
   parameter would take effect; and Core Image cannot drop a kernel as it
   dropped the oversized crop.

It is not isolation by construction. If a later macOS reuses state by
something else, the smear can come back there with no error. The guard is
the real-file suites, `RAWEdgeSmearTests` and `RAWContextSoakTests`
(`RAW_EDGE_SAMPLES`): **run them on every new macOS.** CI cannot (no camera
raws). `RAWDecodeGraphTests` guards the rest in CI: the keys differ, the key
reaches the clamp and the decoder's image, keying changes no pixel beyond
float rounding, and no RAW filter is made in a file that is not on its list
(a tripwire for a new render path that forgets the key).

**Not bit for bit, and why that is not a look change.** The extra kernel
changes how the GPU compiles the arithmetic before it, so float values
differ by up to one unit in the last place (6 × 10⁻⁸ at white, 10⁻⁶ with
extended range and an adjustment after it; measured on the two Kayaking
raws). Half-float intermediates round at 5 × 10⁻⁴ and 8-bit output at
4 × 10⁻³, so now and then a value lands on the other side of a rounding.

What that comes to in files, measured on the 54 Kayaking raws:

- The decoder's image alone, rendered to 8 bits: 12,000 renders compared
  with renders without the clamp, none differed.
- Cached previews and thumbnails (through the whole pipeline and JPEG),
  `develop`'s against this branch's, 108 files: 73 are the same pixel for
  pixel; 6 are the smeared ones, now right; **29 healthy ones differ**, by
  1 to 4 levels (12 files by 1, 12 by 2, 3 by 3, 2 by 4) in a median of
  0.002% of their values and at most 0.03% (a few of JPEG's 8 × 8 blocks,
  where one value's rounding moved a block's coefficients). The branch
  against itself, run after run and at any concurrency: byte for byte the
  same. `develop` against itself: 3 of 108 differ, the smear moving with
  the order of decoding.

An earlier version of this file, and the report the owner decided on, said
only the first of those two, which read as if no file changed at 8 bits.
That was incomplete: about a quarter of healthy previews change by a few
levels in a few thousandths of a percent of their pixels. Nothing a person
can see, and every preview is made again under version 8 anyway, but
exports of healthy photos are not byte for byte what `develop` writes
either. If byte-for-byte matters, the move by whole pixels and back (see
Candidates) was bit for bit and also stopped the smear; it rests on one
assumption more. No golden moved.

**Left open for the later feature.** A per-photo lens correction switch would
be one more optional field of `RAWDecodeSettings`, set in `apply(to:)` only
when present. Nothing here stands in its way; none of it is built, and no
edit operation or checkbox was added.

### Pipeline version: bumped 7 → 8 (flagged)

`PreviewCacheKey.currentPipelineVersion` is now 8, and stays 8 (owner,
2026-11-10). **No healthy photo looks different** (float rounding only,
above). The bump is only to orphan previews already cached wrong. They sit
under the identity stack's hash, so nothing else would ever replace them,
and the owner allowed a bump for that. The comment on the constant says so,
as it does for 7.

Cost: every library regenerates its previews and thumbnails once, on demand,
and `removeObsoletePipelineVersions` deletes the `v7` folder. If the owner
would rather not pay that, the constant is the only line to revert; smeared
previews already cached would then stay until their photo is edited.

**Goldens: none updated, none moved.** `GoldenTests`, `ReferenceTests` and
`RAWDecodeTests` pass unchanged, the RAW goldens included (they are compared
on this Mac's macOS and decoder), within their existing tolerances.

### Speed and memory (this Mac, macOS 27.2)

No cost in either. `photobench` (release) on a scratch library of the 54
Kayaking RW2 files (copies), `develop` at `13b1f90` against this branch,
two to four runs each:

| Measure | `develop` | This branch |
| --- | --- | --- |
| `previews --tier preview --fresh` (2560 px and 512 px from one decode), 7 at a time: wall | 2.6 to 3.0 s | 2.7 s |
| same, mean per rendition | 335 to 378 ms | 333 to 341 ms |
| `previews --tier thumbnail --fresh`, 7 at a time: wall | 1.4 s | 1.4 s |
| `previews --tier preview --fresh --concurrency 1`: mean | 154.2 to 154.7 ms | 154.9 to 155.0 ms |
| `edits`: preview identity, mean | 132 to 135 ms | 130 to 132 ms |
| `edits`: preview edited, mean | 163 to 166 ms | 162 to 164 ms |
| `edits`: live first frame | 184 to 186 ms | 183 to 184 ms |
| `edits`: live next frame | 58 to 64 ms | 59 ms |
| `edits`: live white balance (a decode per frame) | 122 to 123 ms | 119 to 121 ms |

Memory, `RAW_CONTEXT_SOAK=24000 swift test --filter RAWContextSoakTests`
(debug; one 1200 × 800 synthetic DNG, preview and thumbnail from each
decode, 7 at a time, footprint after each twelfth): 432, 432, 439, 443, 444,
439, 440, 440, 441, 441, 444, 436 MB. Level, where the first version went
from about 500 MB to 1.1 GB over half as many. With real 20 MP raws the 7
shared contexts hold about 3.8 GB while they work, as they do on `develop`
(a context keeps what a decode of that size needs); that is not new and not
changed here.

## C1: memory left behind by every RAW decode (decided: choice 2)

This section is the record of the first version of the fix and why it was
replaced. "The tree" in it is that first version, not the tree now.

Code review (`code-review.md`, C1) found that the branch's footprint grew
with every RAW decode and never came back. Reproduced, and not bounded by
either way that was suggested for it: contexts that are kept and emptied
with `clearCaches()` between decodes, or a context recycled after so many
decodes.

**Measured.** `RAW_CONTEXT_SOAK=12000 swift test --filter RAWContextSoakTests`:
one 1200 × 800 synthetic DNG, preview and thumbnail from each decode through
`PreviewGenerator`, 7 at a time, debug build, footprint (`phys_footprint`)
after each twelfth of the run:

| Build | Footprint over 12,000 previews, MB | Left behind per preview | Previews of the 54 RW2, 7 at a time (release) |
| --- | --- | --- | --- |
| `develop`'s shared pool (code review's figures, to 6,000) | 417 to 433 | nothing | 2.6 to 2.9 s |
| A context per decode (in the tree) | 388 to 593 at the start, 912 to 1,235 at the end | 42 to 55 KB (code review: 53 KB over 24,000) | 2.9 to 3.1 s |
| Contexts kept, lent to one decode at a time, `clearCaches()` before each loan | 512, 573, 621, 673, 729, 772, 826, 884, 934, 990, 1,041, 1,094 | 53 KB | 2.9 to 3.1 s |
| Shared pool, each decode given a kernel argument of its own (option 2) | 427, 428, 447, 444, 444, 447, 439, 443, 444, 441, 445, 448 | nothing | 2.6 to 2.7 s |

Without project code (one synthetic DNG, one `jpegRepresentation` a turn,
4,000 to 12,000 turns, one thread): the same graph every time in one context
leaves 0.0 KB a turn; another kernel argument every time in one context 0.0
KB; `clearCaches()` before every turn 13.7 KB; a new context every turn 7.7
to 17.6 KB.

So what leaves memory behind is not the context object. It is a context
working out a RAW render from empty, whether the context is new or was just
emptied, and emptying is what stops the smear. That is why neither bound
works: lent contexts leave as much as new ones (and cost as much time: the
10% is the first render from empty, not making the context), and a context
recycled after N decodes still has to be emptied before each of them. The
GPU driver's `AGX: exceeded compiled variants footprint limit` appears with
both and not with the shared pool or option 2. With real 20 MP raws the
footprint moves by hundreds of MB from one sample to the next (1.0 to 2.3 GB
with a context per decode, 3.3 to 4.3 GB with contexts that are kept, as on
`develop`), so 50 KB steps cannot be read from it; the synthetic DNG shows
them.

What 50 KB a decode means: an import of 10,000 raws ends about 0.5 GB
higher until the app quits; dragging White Balance on a raw (a decode per
frame) adds about 50 KB a frame.

**The choices.**

1. **Keep a context per decode and accept the cost** (the tree as it was).
   Nothing is shared between decodes, whatever Core Image keys its reuse on.
   Costs: about 50 KB per RAW decode until quit, and about 10% on RAW preview
   generation.
2. **Give each decode a kernel argument of its own, on the shared
   contexts.** (Then `option-unique-graph.diff` in this folder.) The
   decode's image goes through `CIColorClamp`
   with bounds near ±10³⁰, different for every decode, so no two decodes
   have the same graph digest and the context never reuses one decode's
   preparation for another. Two places change (`decodeRAW` and Auto White
   Balance's own filter); a RAW decode then renders through the caller's
   engine again.
   - Measured with it: `RAWEdgeSmearTests` 7 of 7 on the Kayaking pair, all
     on one shared context; the soak above, level; the two raws in turn
     1,200 times, none wrong; without project code, 12,000 renders of the 54
     raws in changing order on 7 shared contexts, none wrong (the same run
     without the argument: 178 wrong of 3,000); speed as `develop`. The full
     suite passes, goldens included, except the four tests of
     `RAWRenderIsolationTests` that assert a separate engine, which would be
     rewritten to assert the argument.
   - What it rests on: that Core Image keys what it reuses on the graph's
     digest, and that a kernel's arguments are in the digest. The second
     must hold for any filter parameter to work. The first is what was
     observed on macOS 27.2, not documented. It is not isolation by
     construction: if another macOS reused state by something else, the
     smear could come back there, and only `RAWEdgeSmearTests` on real files
     would show it. (Whether the fault exists on another macOS at all is not
     known either.)
   - Not bit for bit: the extra kernel changes how the GPU compiles the
     arithmetic before it, so float values differ by up to one unit in the
     last place (6 × 10⁻⁸ at white, 10⁻⁶ with extended range and an
     adjustment after it). None of the 12,000 renders differed at 8 bits
     from the render without it. No cached preview would need replacing for
     this, and no golden moved.
   - Other tags tried: a move by a whole number of pixels and back is bit
     for bit and also stopped the smear (648 of 648), but only as long as
     Core Image compares graphs before it folds the two moves into none. A
     crop larger than the image did not stop it (33 of 648 wrong), nor did
     image properties of the same size. A tag Core Image can see through
     fails without a sign; a kernel argument is the one it cannot drop.
3. **Decode raws in a helper process that is replaced every so many
   decodes.** The only way found to have both: nothing shared, and the
   memory comes back when the helper exits. Not built or measured. It is a
   large change: pixels of 160 MB a decode across processes, a second
   executable in both bundles (`Scripts/build-app.sh`, signing), and every
   decode path in this fix moved behind it.

**Decision (owner, 2026-11-10, relayed by the main session): 2.** The
reasons given for recommending it: the leak is certain, on every Mac, for
every raw; the case choice 1 guards against that choice 2 does not is a
guess about other systems; and it is the smaller change with no speed cost.
It is now the fix. `option-unique-graph.diff` was applied in substance and
removed from this folder: the tree has the same clamp in a file of its own
(`RAWDecodeGraph.swift`), on `develop`'s engine code instead of the first
version's, since nothing used `isolated()` any more.

## Other formats (step 4)

Checked with the owner's files, read in place, each render against one made
alone (one shared context, file order, 2560 px):

| Files | Lens correction applies | Wrong before the fix |
| --- | --- | --- |
| RW2, DMC-ZS100, Kayaking (54) | 28 | 4 |
| RW2, GX85, `2026-03 Testing GX85` (60) | 60 | 6 |
| RW2, `TR76 Reunion/Sep 4` (60) | 0 | 0 |
| ORF, three folders (161) | 103 | 0 |
| ARW, five folders (105) | 13 | 0 |
| CR2 (40) | 0 | 0 |

- It is not one camera: another Panasonic body shows it.
- ORF and ARW go through the same `radialLens` kernel with the same
  undigested table, so they are exposed in principle. In the ORF folder
  checked for it (60 files) no two files had the same graph digest: every
  file built its own graph, so nothing was reused. In one ARW folder (18
  files, 9 corrected) graphs were reused three times without a wrong result.
  Not proven immune; the fix covers every format the RAW decoder reads,
  since it does not depend on the format.
- With a key per decode on shared contexts: the 54 Kayaking raws 12,000
  times in changing order, none wrong. (With a context per decode, the
  first version: Kayaking 270 of 270 and GX85 60 of 60.)
- The low edge scores the issue mentions for the playground library were
  not followed up file by file; an absolute edge score flags smooth edges
  too, which is why the tests compare against a render made alone.

## Build and test

Baseline at `13b1f90`: `swift build` complete, no warnings.

On the final tree (the key per decode), macOS 27.2:

- `swift build`: complete, no warnings.
- `swift test`: **690 tests in 116 suites passed, 1 known issue** (the
  existing one in `LiveSessionTests`, "Values above white survive the cached
  stages"). No signal 11 here.
- `Scripts/build-app.sh all`: exit 0, both bundles (`build/Gus.app` records
  SDK 27.2, minimum 15.0).
- `RAW_EDGE_SAMPLES=<Kayaking>/P1040027.RW2:<Kayaking>/P1040058.RW2 swift test --filter RAWEdgeSmearTests`:
  6 tests (7 cases) pass, everything on one shared context. The Color
  Alignment case takes about 80 s in a debug build. With the key taken out
  of `decodeRAW`, 5 of the 7 fail.
- `RAW_CONTEXT_SOAK=24000 RAW_EDGE_SAMPLES=<the same pair> swift test --filter RAWContextSoakTests`:
  passes. 24,000 previews of the synthetic DNG: 432 to 444 MB throughout.
  The two raws rendered in turn 2,400 times: every one byte for byte its
  render made alone. No `AGX: exceeded compiled variants footprint limit`.
  Again after C4, at 12,000: 429 to 443 MB, −0.5 KB a preview fitted, and
  the two raws in turn 1,200 times all equal. At the shortest length the
  soak now allows, 3,000, twice: 1.7 and 1.2 KB a preview fitted, passing.
- Through `PreviewService` (`photobench previews --tier preview --fresh` on
  the 54 files): the `develop` build caches 3 smeared previews and their 3
  thumbnails; this branch's 108 files are byte for byte the same on every
  run, at 7 at a time and one at a time, and differ visibly from `develop`'s
  in exactly those 6 (and by float rounding in 29 more: "The fix").
- Without project code, the same clamp on 7 shared contexts: 12,000 renders
  of the 54 raws in changing order, none wrong; the same run without it,
  178 wrong of 3,000.

- `CAMERA_RAW_SAMPLE=<copy of P1040037.RW2> swift test --filter SharpeningMapRawFileTests`: passes.
- `CAMERA_RAW_SAMPLE=<copy of a 16:9 GX85 RW2> swift test --filter CameraRAWMaskTests`:
  passes (the whole-sensor decode of `CameraFrame`, two decodes of one file
  with different keys compared).
- `LARGE_RENDER_TESTS=1 swift test --filter "LargeRenderTests|LargeBrushTests"`: passes.

Tests added (`Tests/PhotoCoreTests/RAWDecodeGraphTests.swift`):

| Suite | What it checks |
| --- | --- |
| `EdgeBandTests` | the smear detector on a synthetic image, with and without repeated edge columns |
| `RAWDecodeGraphTests` | every serial has bounds of its own, finite and beyond any pixel; keys made at the same time differ; the key's bounds are the ones the clamp applies, to a plain image and to the RAW decoder's (seen with bounds low enough to show); keying changes no pixel by more than two units in the last place, below and above white; no file makes a RAW filter that is not on the list, and the two that render one take its image through `RAWDecodeGraph.output(of:)` |
| `RAWEdgeSmearTests` (needs `RAW_EDGE_SAMPLES`) | previews, exports (full size and 2048 px), live frames, the 100% region, Color Alignment and the auto measurements of the second raw equal those made alone |
| `RAWContextSoakTests` (needs `RAW_CONTEXT_SOAK`, a number of previews: 12,000 when it is not a number, never fewer than 3,000) | the footprint stays level over thousands of RAW previews of a synthetic DNG, by limits that scale with the count (`SoakGrowth`: growth after the first quarter under 24 MB plus 5 KB a preview, and a fitted growth under 10 KB a preview, against the 50 KB a preview of the first version); with `RAW_EDGE_SAMPLES` too, two raws rendered in turn a tenth as often, each byte for byte its render made alone |
| `SoakGrowthTests` (runs everywhere) | those limits on footprints recorded from real runs: three level runs pass, at their own length and as if 3,000 long; the first version's two recorded runs fail both limits; 50 KB a preview at 3,000 fails both |

Each `RAWDecodeGraphTests` test was seen to fail with its subject broken:
the key not applied to the decoder's image, the clamp ignoring the key,
every key the same, a RAW filter made in another file, `decodeRAW` taking
`raw.outputImage`.

No other test changed: the test files the first version touched are as on
`develop`.

`docs/USER_GUIDE.md`: no change; nothing it describes behaves differently.

## Code review (`code-review.md`, 2026-11-10)

The first review was of the first version (a context per decode).

| # | Finding | What was done |
| --- | --- | --- |
| C1 | A context made and dropped per RAW decode leaves about 53 KB behind for good; `status.md` said there was no memory growth | Reproduced (42 to 55 KB a preview). Contexts kept and emptied between decodes left as much, so neither suggested bound worked ("C1"). The owner chose the key per decode instead, which leaves nothing behind (24,000 previews, level). The wrong claim is gone with the version it was about. |
| C2 | No test failed with `hdrImage` back on the shared engine | No longer applies: `hdrImage` renders on the shared engine by design, as on `develop`, and gets its key in `decodeRAW` like every other path. The test and the split of `hdrImage` made for it are gone with the engine plumbing. |
| C3 | The Bug section's "13b1f90 plus the test file alone" cannot be run | Rewritten for the fix as it is now: the one-line change that takes the key out, the command, and which 5 of 7 cases fail (Bug, "Tests that fail without the fix"). |
| C4 (second pass) | The soak allowed a fixed 100 MB whatever the count, so under about 2,700 previews it passed with the leak present; the per-preview figure was printed, not checked | The limits now scale with the count and the figure is asserted (`SoakGrowth`, in the table above), the fewest previews went from 1,200 to 3,000, where the leak is 110 MB against 35 MB allowed, and `SoakGrowthTests` checks the limits against the recorded runs in every test run. The default stays 12,000. |

For the second review, what is new: `RAWDecodeGraph.swift`, one changed
line each in `PreviewGenerator.decodeRAW` and `AutoAdjuster.whiteBalance`,
and `RAWDecodeGraphTests.swift`. What the first review checked about engines
and deferred renders no longer has anything to apply to.

Code review's question 1 (the pipeline version): 8 stands, confirmed by the
owner on 2026-11-10.

Seen while there, not changed: `Tests/PhotoCoreTests/SmartAlbumTests.swift:165`
warns about an unused result when that file is compiled. It is not part of
this change.

## For QA

- `RAWDecodeGraphTests` in the full run, and the two real-file suites with
  the Kayaking pair (commands under Build and test).
- In a copy of the bundle on a scratch library: import copies of the Kayaking
  RW2 files, open `P1040057`, `P1040058`, `P1040065` and `P1040080` in the
  loupe and at 100%, and look at the left and right edges. With the `develop`
  build the same import shows them smeared.
- For a person: the owner's own library shows the photos clean after the
  previews regenerate (the `v7` cache folder is removed when the library opens).

The app was not launched for this fix: no UI changed.

## Not known

- **macOS 26 and 15.** Everything was measured on 27.2. Whether the fault
  exists there is unknown, and so is whether the key stops it there if it
  does: both of the fix's assumptions were observed on 27.2 only. CI has no
  camera raws. Someone with a Mac on 26 or 15 and two such raws can answer
  both with `RAWEdgeSmearTests` (first with the key taken out, to see
  whether the fault is there at all).
- **Whether Apple knows.** Not reported. The scope table and a two-file
  reproduction are enough for a Feedback report if the owner wants one filed.
- **ORF and ARW**: exposed in principle, not reproduced (above).

## Open questions

None blocking.

1. For the owner, to confirm or not: healthy previews and exports are not
   byte for byte `develop`'s (29 of 102 cached files differ by 1 to 4 levels
   in a few thousandths of a percent of their values; "The fix"). The
   report the choice was made on understated this. If that is not
   acceptable, the whole-pixel move is the bit-for-bit alternative.
2. Photos whose Color Alignment was measured automatically before this fix
   may hold slightly wrong values (hundredths of a unit in the one case
   measured). They are stored edits, so nothing here touches them; Align
   automatically again measures them cleanly. Code review passed this to
   the product manager as a requirements issue.

## README

Nothing to change: no requirement, build command or layout changed.

Proposed for the owner's parts of `CLAUDE.md` (not edited here):

- Architecture rules, Rendering. Suggested addition: "Every `CIRAWFilter`
  whose image is rendered takes it from `RAWDecodeGraph.output(of:)`, which
  gives each decode a render graph of its own: a context that rendered one
  raw can otherwise smear the next one's edges. This rests on undocumented
  Core Image behaviour; run `RAWEdgeSmearTests` on real files on every new
  macOS." ("One Metal-backed `CIContext`" is as true as it was.)
- Commands: `RAW_EDGE_SAMPLES=wide.RW2:longer.RW2 swift test --filter RAWEdgeSmearTests`
  and `RAW_CONTEXT_SOAK=24000 swift test --filter RAWContextSoakTests`, and
  allow entries for them in `.claude/settings.json` next to
  `CAMERA_RAW_SAMPLE`.
- Scope so far (product manager, at Ship if this fix takes that step): the
  pipeline version and the rule above.
