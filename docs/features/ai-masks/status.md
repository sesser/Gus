Issue: #88

# AI masks: implementation status

Feature, branch `feature/ai-masks`, cut from `develop` at `ed423d7`. The PRD
is the issue body (`gh issue view 88`), approved by the owner on 2026-11-18.
R1 makes a spike the first step: no design or build starts until the PRD has
been revised by its findings.

**Status**

| Item | State |
| --- | --- |
| R1, the spike (this file) | Done, 2026-11-20, on this Mac only |
| PRD revision from the findings | Not started (Requirements issues RI-1 to RI-6, below) |
| Design (`design.md`) | Not started: waits on the PRD revision |
| R2 to R12, the feature | Not started: waits on the design |

## Build and test

- Baseline, `develop` at `ed423d7`: `swift build` clean.
- With the spike: see **Latest results** at the end.

## How the spike was measured

All spike code is in one file of the benchmark tool, outside every shipped
target: `Sources/PhotoBench/AIMaskSpike.swift`, the mode `photobench
aimask-spike`. Nothing in the apps or `photocli` calls it. It is throwaway:
the feature build replaces it with real code and deletes it.

```zsh
swift run -c release photobench aimask-spike --files a.JPG:b.ORF --runs 5 --upscale --devices --sizes --output /tmp/aimask
```

`--long-edge full` runs at full resolution (default 2560, the preview tier);
`--dir DIR` takes every photo in a folder. `--output` writes overlays, the
low-resolution masks and edge crops of each upscaling method as PNGs: never
commit them, they are the owner's photos.

For each file it renders the detection input (the master through an empty
stack: oriented, before any crop, the decoder's own look, 2560 px long edge,
sRGB), runs `VNGenerateForegroundInstanceMaskRequest` and
`VNGeneratePersonInstanceMaskRequest` (and, for comparison,
`VNGeneratePersonSegmentationRequest` at `.accurate`), and reports mask size
and format, instances, confidence, coverage, the share of soft pixels (between
2% and 98%), whether repeated runs agree, agreement between compute devices,
the effect of the input size, the time of each run, the stored size of the
all-instances mask under each encoding, and the upscaling comparison.

**Photos.** The owner's scratch copy of one folder of his library
(`gus-scratch/photos/2016-05-21`: 120 camera JPEGs, with their Olympus ORF
and Fujifilm RAF raws). Nothing from it is committed. Two sets:

- *Survey*: all 120 JPEGs, one run each.
- *Fixed set*: 12 files, 5 runs each, with every option. By content:
  `10M10296` (flower close-up, no person), `10M10325` (one person, clear
  edges), `X1000553` (group of four or more, people against a tent),
  `X1000587` and `X1000559` (street crowds, more than four people),
  `10M10306` (lone tree in a field), `10M10308` (object subject, no person),
  `X1000574` (portrait orientation, object subject), `10M10287` (landscape,
  no subject), `10M10292` (portrait orientation, small subject), and the raws
  `10M10296.ORF` and `X1000553.RAF` (the same scenes through the RAW path).
  Full resolution was also run on `X1000553.RAF` (4896x3264) and
  `10M10325.ORF` (4608x3072).

**Machine.** Apple M4 Pro, macOS 27.2.1 (26B131), macOS 27.2 SDK, Swift
6.4.2. Times are wall clock in one process, release build.

## Findings (R1, AC1)

### 1. Availability

- **macOS 27.2: both requests exist and work.** `supportedRevisions` is
  `[1]` for both (and for the person segmentation).
- **macOS 15:** the SDK's own headers declare both
  `VNGenerateForegroundInstanceMaskRequest` and
  `VNGeneratePersonInstanceMaskRequest` `API_AVAILABLE(macos(14.0))`, with
  `VNInstanceMaskObservation`, and neither is deprecated in the 27.2 SDK.
  That settles the PRD's doubt (person request "confirmed only by a
  third-party source") from a first-party source; it does not show they *run*
  on macOS 15, which was not tried (below).
- **The macOS 15 "redesign"** is Vision's Swift-only API: value-type requests
  (`GenerateForegroundInstanceMaskRequest`,
  `GeneratePersonInstanceMaskRequest`, `InstanceMaskObservation`, `async`
  perform), `@available(macOS 15.0)`, beside the `VN` classes, with the same
  single revision. Either API works with the app's macOS 15 minimum. macOS 26
  and 27 add no new mask request except `GenerateIterativeSegmentationRequest`
  (macOS 27 only; seeded by a point, box or scribble; its model is downloaded
  on demand, `DownloadableAssetsRequest`). That one would conflict with R10's
  intent and is not part of this slice; it may matter later for picking one
  instance.
- **No download.** Neither mask request is a downloadable-asset request in
  the 27.2 SDK: their models come with the OS. The spike uses no network API.
  Network traffic was not monitored.
- **Not tried: macOS 15 and macOS 26.** This Mac has only 27.2, and no other
  Mac was available. See RI-6.

### 2. Mask resolution and format

| Request | Label map | Soft mask (`generateMask(forInstances:)`) | Values |
| --- | --- | --- | --- |
| Foreground (Subject) | 512x512, 8-bit (`L008`) | 512x512, 32-bit float (`L00f`) | almost binary: 0.0% to 0.6% of pixels soft |
| Person (People) | 512x384 or 384x512, 8-bit | same, 32-bit float | soft: 2% to 60% of pixels soft |
| Person segmentation (comparison) | none | 2016x1512 or 1512x2016, float at `.accurate` | 0% to 27% soft |

- **The size is fixed by the model, not by the photo.** Foreground is always
  512x512, for 3:2 and 2:3 photos alike; person is always 4:3. The mask is
  stretched over the frame, so the stored raster must keep its own width and
  height and map to the mask frame in unit coordinates.
- **The input size barely matters.** The same file rendered at 512, 1024,
  2560 and 4096 px gave the same mask size and coverage within one percentage
  point, except one soft person mask (an ORF: 45.2%, 44.2%, 39.4% at 1024,
  2560, 4096).
- **Coarse at 100%.** On a 24 MP 3:2 file one foreground mask pixel spans
  about 9.6 x 6.4 output pixels, so edges need the upscaling of section 7.
- Vision's own `generateScaledMaskForImage` gives a mask at the image's size
  (section 7).

### 3. Quality and instance counts (this Mac only)

Survey of 120 JPEGs: Subject found something in 65 (one instance in 51, two
in 13, three in 1); People in 56 (four instances in 22, one in 20, two in 8,
three in 6); neither in 44. In 11 photos People found people where Subject
found nothing (street crowds).

Fixed set (coverage of the frame, instances in brackets):

| File | Content | Subject | People | Person segmentation |
| --- | --- | --- | --- | --- |
| 10M10296.JPG | flower close-up | 14.0% (1) | 35.5% (1), false | 31.1%, false |
| 10M10325.JPG | one person | 22.9% (1) | 22.9% (1) | 22.8% |
| X1000553.JPG | group, 5+ people | 57.8% (1) | 59.9% (4) | 61.0% |
| X1000587.JPG | street crowd | none | 8.6% (4) | 16.8% |
| X1000559.JPG | street crowd | none | 48.3% (4) | 51.9% |
| 10M10306.JPG | tree in a field | 30.4% (1), confidence 0.28 | none | 0.0% |
| 10M10308.JPG | object | 29.5% (1) | none | 0.0% |
| X1000574.JPG | object, portrait | 12.2% (1) | none | 0.0% |
| 10M10287.JPG | landscape, no subject | none | none | 0.0% |
| 10M10292.JPG | small subject, portrait | 0.7% (1) | none | 0.0% |
| 10M10296.ORF | flower close-up | 14.1% (1) | 44.2% (1), false | 15.8% |
| X1000553.RAF | group | 56.6% (1) | 61.6% (4) | 62.4% |

What looking at the overlays showed:

- **Subject** is clean on clear subjects (a flower's petals, a cap against a
  tent, an object) and selects a tree as one blob, the sky between its
  leaves included. It found nothing in the two no-subject landscapes (the R6
  path). It often ignores people in a crowd (two street scenes: nothing), so
  Subject is not a superset of People.
- **People stops at four.** Apple says the request segments "up to four
  individuals" (WWDC23, session 111241). In one street crowd about nine people
  are visible and four are selected; several in the middle of the frame are
  not. The semantic person segmentation selected all of them (but lost a
  child's curly hair that the instance mask kept). RI-1.
- **People has false positives.** On the flower close-up both person models
  select the flower and leaves, the instance request with confidence 0.999;
  confidence does not tell this apart from real people (0.96 to 0.999). The
  person mask there also carries a fine 4-pixel grid of low soft values over
  the background. RI-2.
- **The same scene through JPEG and raw** gives the same instances and
  Subject coverage within 1.2 points; the soft People mask of the flower
  differs more (35.5% against 44.2%).
- **Determinism.** Within one process on one compute device, five runs gave
  bit-identical masks for every file and kind. Across compute devices they
  differ: People on the CPU or GPU against the Neural Engine differs by up to
  0.05 on 0.3% to 28% of pixels; Subject flips a handful of pixels (single
  values up to 0.94). Vision's default device is not fixed either: in a fresh
  process the default matched the Neural Engine, but after an earlier request
  in the same process had asked for the GPU, later default runs matched the
  GPU. So the same photo can give a different mask on a later recompute on the
  same Mac, and will on a Mac without a Neural Engine (Intel Macs run macOS
  15 and 26). This supports R5 as written: store the result, never recompute
  silently.
- **Between OS versions:** not measured (15 and 26 not tried).

### 4. Cost of one detection (M4 Pro, macOS 27.2.1)

| Step | Time |
| --- | --- |
| Render the detection input, 2560 px, empty stack | JPEG 100 to 160 ms (median 120), ORF 330 to 410 ms, RAF 100 to 165 ms |
| Subject: perform, `generateMask`, read | warm 12 to 27 ms (survey median 14); first in a process 30 to 118 ms |
| People: the same | warm 8 to 13 ms (survey median 9); first in a process 10 to 262 ms; 2.05 s once, the first run after a new build |
| People forced to the CPU / GPU | 93 to 134 ms / 30 to 260 ms |
| Memory, first use in a process | Subject +54 MB, People +18 MB (process footprint) |

Adding a component therefore costs about 0.15 to 0.5 s, most of it the
render of the input, not the detection. The detection itself is short enough
that cancellation (R4) matters mostly for the render.

### 5. Stored size of one mask

The all-instances soft mask quantized to 8 bits (largest error 1/510 against
the float mask), over the fixed set:

| Encoding | Subject (9 masks) min / median / max | People (7 masks) min / median / max | Person segmentation (12) min / median / max |
| --- | --- | --- | --- |
| 32-bit float, raw | 1,048,576 | 786,432 | 12,192,768 |
| 8-bit, raw | 262,144 | 196,608 | 3,048,192 |
| 8-bit, LZFSE | 621 / 3,052 / 5,360 | 10,894 / 53,646 / 110,529 | 3,816 / 262,949 / 692,056 |
| 8-bit gray PNG | 1,814 / 6,100 / 8,293 | 12,483 / 49,471 / 89,604 | 16,390 / 269,208 / 569,852 |

(bytes). Binary Subject masks compress best with LZFSE; soft People masks
with PNG.

**In the stack, against the limits.** A typical stack (`EditBenchmark.typical`,
971 bytes of JSON, a 615-byte history snapshot) with one mask whose component
carries the PNG inline as base64:

| Kind | Stack JSON | History snapshot (LZFSE) | Snapshots in 4 MiB |
| --- | --- | --- | --- |
| Subject | 3.6 to 12.3 KB | 1.9 to 8.9 KB | 473 to 2,181 |
| People | 17.9 to 120.7 KB | 13.4 to 91.7 KB (median 50.8) | 45 to 312 (median 82) |
| Person segmentation | 23 to 761 KB | 5.9 to 578 KB | 7 to 713 |

- `MaskLimits` bounds counts (32 masks, 16 components each, color samples,
  brush points), not bytes. Inline, a stack could hold 512 AI components:
  about 56 MB of JSON at the largest People mask measured.
- `EditHistory` keeps 100 entries or 4 MiB per version, the newest always
  kept. One inline People component already drops the history below 100
  entries on most photos measured (median 82, worst 45); every further AI
  component divides it again, and every entry repeats every raster.
- Stored in a table and referenced by digest, a component adds about 150
  bytes to the stack, and the history is unaffected.

### 6. Storage recommendation

**A catalog table of rasters, content-addressed, referenced from the
component by digest.** Not inline in the stack (section 5), and not keyed by
the master's content hash and kind as R5 prefers (RI-4).

- Table `maskRaster` (new migration): `digest` (SHA-256 of the stored bytes,
  primary key), `width`, `height`, `encoding`, `data` BLOB, `createdAt`, and
  provenance for diagnosis (request, revision, OS version). Rows are never
  updated.
- The component stores its kind (`subject`, `people`, `background`) and the
  digest. A Background component can reference its Subject raster (it is
  Subject inverted), so no second detection or row is needed.
- Why the digest and not master hash plus kind:
  1. **Render hash.** The render hash covers the stack only. With the raster
     under a key the stack doesn't hold, Update would change the render while
     the render hash, and so every cached preview's key, stays the same. With
     the digest in the stack, the hash changes exactly when the raster does,
     and no pipeline version bump is ever needed for it.
  2. **Virtual copies and pairs (R8).** A master-keyed row is shared by every
     version of the master: Update on a copy would silently change the
     original. With digests, Duplicate copies the reference (no new row) and
     the two diverge only when one is updated. The two files of a RAW+JPEG
     pair have different stacks and so their own rows.
  3. **Undo and history.** An old snapshot or an undo restores the old
     digest, whose row is still there; nothing has to be recomputed (R5).
- Lifetime: a row lives while any version's stack or any `editHistory`
  snapshot names it. Removing versions and trimming history leave orphans to
  sweep (in the same transaction, or at launch); at 2 to 110 KB a row, a
  late sweep costs little.
- Encoding: **8-bit gray PNG**. Lossless, self-describing (the size is in
  it), read by ImageIO into a Core Image graph with no code of ours, and a
  reviewer can open a row's bytes as an image. LZFSE of the raw bytes would
  be 10% to 60% smaller for Subject and up to 20% larger for People; either
  fits. A PNG encoder may write different bytes for the same pixels on another
  OS: harmless, since rows are never encoded again, only copied.
- Strict reading (R12): new shape names make a stack unreadable to older
  builds, which then never write over it, the existing rule for masks. A
  digest whose row is missing (a damaged or partly copied catalog) is a
  different case: RI-5.

### 7. Edge-aware upscaling: proposal

**The guided filter** (He, Sun and Tang, "Guided Image Filtering", ECCV 2010
and TPAMI 2013) with a gray guide, run at the render's own size:

1. The stored raster is placed in the mask frame and sent through
   `crop.apply` like the brush (`MaskRenderer.framed`), sampled bilinearly.
2. Guide: the luminance of the image entering the mask step, the image the
   luminance and color ranges select on (`MaskRenderer.selection`), in its
   perceptual encoding.
3. Window radius: one mask pixel in output pixels (the output size over the
   raster's size, rounded up: 5 at 2560 px, 9 to 10 at full size on these
   files); ε = 1e-3. Starting values for the build, to be pinned there by a
   CPU reference and goldens.
4. Implementation: two stitchable color kernels (prepare `I, p, I², Ip`;
   coefficients `a, b`; then `a·I + b`) and two box blurs, compiled at run
   time like the Lens kernels. A CPU reference (plain Swift, as in the spike)
   for `ReferenceTests`.

Evidence (overlays and crops at 2560 px and at 100% on the two raws, judged
by eye):

| Method | Result |
| --- | --- |
| Bilinear | Staircase of one mask pixel, about 10 px steps at 100% |
| Guided filter at output size, gray guide (proposed) | No staircase; follows outlines, including a black jacket against a dark red tent; slightly soft (a few pixels) where guide contrast is low |
| The same, color guide (3x3 per pixel) | No visible gain; 4 to 5 times the CPU cost, and a 3x3 solve per pixel |
| Fast guided filter (coefficients at mask resolution, He and Sun 2015), gray or color | Good at 2560 px; soft over 20 to 40 px at 100%, because its coefficients are themselves upsampled 6 to 10 times |
| Vision's `generateScaledMaskForImage` | Needs the request handler of the detection run, so it cannot be used at render time from a stored raster; acts as a plain resampler: values overshoot (−0.66 to 1.40 on People masks), visible soft halo around a cap at 2560 px |
| `CIGuidedFilter` (built in) | Close to the proposed method at radius 4; parameters undocumented; one run gave non-finite pixels on one photo, not reproduced in three later runs. Not recommended |

Cost: the spike's GPU prototype, in the app's half-float working format,
including reading the result back: at 15 to 16 MP about 75 to 90 ms against
22 to 35 ms for rendering the guide alone (about 50 to 60 ms for the filter);
at 2560 px 24 to 35 ms against 10 to 19 ms. It agrees with the CPU reference
to a mean of 0.001 to 0.0026; single pixels differ by up to 0.3 to 0.8 in
half float and up to 0.18 to 0.43 in float. The variance `E[I²] − E[I]²`
loses precision in half float: the build should compute it in float or
about a centered guide, and match its box to the reference's exactly.

Consequence: because the guide is the image entering the mask step, the
upscaled mask follows what is seen and moves very slightly with global
edits before it (the filter is invariant to linear changes of the guide only
up to ε), as the range masks already do. The stored raster never changes, and
a stack renders the same every time. No existing stack's render changes, so
no `PreviewCacheKey.currentPipelineVersion` bump.

## Requirements issues (for the product manager)

- **RI-1, People stops at four people.** R2 says People is "all detected
  people"; Vision's instance request returns at most four (22 of the 56
  survey photos with people hit four; in a street crowd several people in the
  middle of the frame were left out). Options: (a) keep the instance request
  and say so in the user guide (and the reason line, if design wants); cost
  none; keeps instances for a later pick-one. (b) Use
  `VNGeneratePersonSegmentationRequest` (semantic, no limit, macOS 12+):
  selected everyone here but lost fine hair, has no instances (no later
  pick-one), and its raster is 2016x1512, 4 to 700 KB stored (median 263 KB)
  unless stored smaller. (c) Union of both: two detections and the larger
  raster. Recommendation: (a) for this slice, with a follow-up to evaluate
  (c).
- **RI-2, People can select something that is not a person.** A flower
  close-up came back as one person at confidence 0.999, from both person
  models; confidence can't filter it. R6's "nothing detected" doesn't happen
  there; the person removes the component. Recommendation: accept as a known
  limit and name it in the user guide; no threshold.
- **RI-3, R4's input.** R4 says detection runs "from the preview-tier image".
  The cached preview is rendered with the stack: cropped, turned, straightened
  and edited, while R7 puts the mask in the mask frame (before the crop).
  Proposal: "from a render of the mask frame at the preview tier's long edge
  (2560 px)", that is the master through the stack's frame-defining steps only
  (no crop or turns; lens distortion when on, since the mask frame is the
  corrected frame), with no other adjustments, so the result doesn't depend
  on edits made before adding it. Cost: that render, 100 to 410 ms here,
  cancellable. Any input from 1024 px up gives the same mask.
- **RI-4, R5's storage key.** R5 prefers "a catalog table keyed by content
  hash and kind". Keyed so, Update on one version would silently change every
  version of the master (R5, R8), and the render hash would not change with
  the raster (stale previews). Proposal: R5 says "a catalog table of rasters
  referenced from the component by the raster's digest" (section 6). Needs a
  migration; that is within the PRD's stated impact.
- **RI-5, a missing raster.** If a component's raster row is missing (a
  damaged or partly copied catalog), should the component behave as R6
  (kept, selects nothing, reason shown, render as without it; recommended,
  and Update recomputes) or make the whole stack unreadable as R12 does for a
  stack this build can't parse (editing off)? Recommendation: as R6, since the
  stack itself is readable and the reference is kept for a later repair.
- **RI-6, AC1's OS coverage.** macOS 15 and 26 were not tried. Options:
  (a) accept the spike as run on 27.2 and add to the feature build a test that
  runs both requests on a synthetic fixture and checks they run without error
  and give the sizes above; CI runs it on macOS 15 and 26 at the pull request
  (availability and sizes only: no real photos there, so no quality or
  instance comparison); cost small. (b) The owner lends a Mac with 15 or 26
  for the fixed set; cost his time. (c) Leave 15 and 26 unmeasured. Since R5
  stores the result and never recomputes, OS differences only matter when a
  mask is made or updated. Recommendation: (a).

## Design questions

None for the spike. For the designer once design starts: Background can
reference the Subject raster (section 6), so whether Background is a kind of
its own in the UI or Subject with Invert is a presentation choice, not a
storage one.

## Not done, deliberately

- No design, no feature code: R1 forbids both until the PRD is revised.
- macOS 15 and 26 not tried (RI-6). Network traffic not monitored (the spike
  uses no network API).
- The spike's numbers come from one machine; times on a Mac without a Neural
  Engine were approximated by forcing the CPU and GPU.

## README

Nothing for the README: `photobench aimask-spike` is throwaway spike code,
removed by the feature build.

## Latest results

2026-11-20, with the spike: `swift build` and `swift build -c release
--product photobench` complete with no warnings; `swift test`: 1,253 tests
in 179 suites passed. The spike adds no test (it measures, it asserts
nothing) and changes no shipped target.
