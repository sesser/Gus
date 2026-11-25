Issue: #285 · Complexity: Spike

# Spike: showing and editing gain-map photos in HDR

Owner: swift-macos-engineer. Serves feature #282. Branch `docs/spike-gain-map-hdr`,
from `develop` at `4561cb3`. Time box 80 tool calls; about 55 used.

**Status: Done.** The question is answered by measurement on real files. Nothing
was shown on a screen: every number below is read from rendered pixels, so how
it looks on the display is for a person (see **Not checked**).

## Question

What does it take for gain-map photos to be shown and edited in HDR in the loupe
(#282), with no adjustment, release, zoom or histogram update switching to the
SDR version, and with no existing SDR rendering changed? (Five sub-questions in
#285; answered in order under **Findings**.)

## Short answer

Edit the file's SDR version exactly as today, and apply the file's gain map as
the last step of the render ("gain last"). Then:

- Every adjustment works in HDR with no change to any adjustment, masks, look-up
  tables and grain included. None needs to be unavailable.
- SDR renders are byte for byte as now by construction: the SDR code path is not
  touched; HDR is one extra step after it.
- One set of sliders holds exactly: at native pixels the HDR-over-SDR ratio of
  each pixel moved by at most 0.0006 stops RMS under every control tested (a file
  with an ISO gain map), against 0.15 to 0.3 stops for Contrast, Tone Curve and
  Highlights when the expanded HDR picture is edited instead.
- A prototype of it in the real `LiveRenderSession` and `PreviewGenerator.hdrImage`
  (three hunks, in the appendix) gave live frames and settled renditions that
  agree within 0.005 stops for every stack tried, Contrast, a curve, Color
  Grading, grain and a crop included (#277 measured 0.86 stops between them),
  at 1.2 to 1.6 ms more per frame.

The alternative, editing the expanded HDR picture ("expand first"), needs new
HDR versions of the tone table, the Color Mixer, Color Grading, look-up tables
and grain, and still makes the two versions respond differently to one slider.
It is not recommended.

## What was tried

Environment: macOS 27.2.1 (26B131), Apple M4 Pro, Swift 6.4.2. A copy of
`develop` under the session scratchpad with a probe added to `photobench`
(debug build; PhotoCore is optimized in debug). Nothing under `Sources/`,
`Tests/`, `Scripts/` or `Package.swift` is committed. No app was launched.

Files:

| Name here | What it is | Gain map as macOS reports it |
| --- | --- | --- |
| `IMG_0546.HEIC` (owner's, the #277 file) | iPhone HEIC, 4032 × 3024, orientation 6 | Apple's (version 131072, headroom 2.62) and ISO 21496-1 (−0.15 to +1.39 stops, gamma 0.73), 2016 × 1512, one channel, 8 bit |
| `IMG_0542.HEIC` (owner's) | iPhone HEIC, 4032 × 3024, orientation 1, a dark scene | Apple's (headroom 3.74) and ISO (−0.08 to +1.90 stops, gamma 0.77), 2016 × 1512 |
| `IMG_0561.HEIC` (owner's) | iPhone HEIC, 5711 × 3212, orientation 1 | **Apple's only** (headroom 4.55), 2856 × 1606; no ISO gain map |
| Pixel sample | A public Ultra HDR JPEG (`MishaalRahmanGH/Ultra_HDR_Samples`, `Originals/…_01.jpg`), 4080 × 3072 | Adobe `hdrgm` XMP only in the file (no ISO segment); macOS reports an ISO gain map: 0 to +2.66 stops, 1020 × 768 |
| Synthetic HEIC and JPEG | Written by Core Image (`.hdrImage`), a ramp scene lifted −0.15 to +1.39 stops | ISO only, full size |

The owner's files were copied to the scratchpad and read there; the copies and
every rendering of them were deleted at the end. Nothing of them is committed
and no personal metadata was read or recorded. All three carry a gain map.

Measures (all in linear Display P3, relative to SDR white):

- **Light**: mean, median, 90th and 99th percentile luminance and the largest
  component of a render reduced to 480 pixels.
- **Ratio drift**: for an edit, the RMS over pixels of how far
  log2(HDR luminance / SDR luminance) moved from the unedited pair's. Zero means
  the HDR version changed exactly as the SDR version did. Measured on reduced
  renders and, for the final numbers, on three 640 × 480 windows at native pixels
  (reduction averages the gain over texture and reads 0.01 to 0.06 where native
  pixels read 0.000).
- **Ramp**: a gray ramp 0 to 8 times SDR white in the working space through
  each adjustment, to see where values above white stop.

Two ways of making the HDR picture were compared on every control:

- **Expand first**: `renderer.render(stack, to: expandedHDRDecode)` (the file
  decoded with `.expandToHDR`, as `hdrImage` does for HLG and PQ today).
- **Gain last**: `renderer.render(stack, to: sdrDecode).applyingGainMap(gainMap)`
  (`CIImage.applyingGainMap`, macOS 15 and later).

## Findings

### 1. The adjustments that turn HDR off today

Unedited, gain last equals the system's own HDR decode: RMS 0.0000 stops against
`.expandToHDR` on all four real files, and `.expandToHDR` equals ImageIO's
`kCGImageSourceDecodeToHDR`.

**Under gain last, nothing stops any of them.** They run on the SDR version, as
now, and the gain map multiplies the result. No adjustment changes, no new
kernel, no golden moves, and SDR output is the same code as today.

**Under expand first**, per adjustment (ramp outputs are for a gray input):

| Adjustment | What stops it above SDR white (measured) | How it could work | Cost | SDR byte for byte |
| --- | --- | --- | --- | --- |
| Contrast, Whites, Blacks, Highlights above 0, Tone Curve (one `ToneTable` through `CIColorCurves`) | The table itself does not clamp at white: it continues with slope one (3.0 in, 3.004 out) and clamps where its domain ends, 4.95 × white (6.0 in, 4.954 out). Two things do stop it. On the lazy `.expandToHDR` decode Core Image clamps the picture near white before the table (99th percentile 1.46 → 0.94), though not on the same pixels held as a bitmap (1.47 → 1.48); see Traps. And where it runs, the controls act only below white, so HDR highlights get none of the contrast or curve. | An HDR-only table with a wider domain over a materialized decode, plus a definition of each control above white | Small to code, medium to define, reference and golden | Only if the SDR path keeps today's table: a domain of 4 moved SDR values (0.645 → 0.644 at 0.5 in) |
| Color Mixer, Color Grading (cubes through `CIColorCubeWithColorSpace`) | A hard clamp: every gray input at or above 1.0 comes out 1.000 | The filter's `extrapolate` passes grays (2.0 → 2.000) but not colors: an identity cube turned (2.00, 1.20, 0.60) into (1.66, 1.69, 0.90). So each needs its own kernel, with a CPU reference and goldens | Large (two kernels) | Only if SDR keeps the cubes |
| Look-up tables | The same clamp, and a `.cube` file defines 0 to 1 only | No faithful extension exists. Any rule (apply to the part below white, carry the rest as a ratio) is gain last under another name | Medium, plus a product decision | Yes |
| Dehaze | Nothing clamps (8.0 in, 8.136 out at +50). It is excluded because its haze estimate and airlight read the picture's levels, so on the brighter HDR picture it does something else (ratio drift 0.06 to 0.29 stops) | Could simply be let through; it would not match the SDR result | None to small | Yes |
| Grain | `CILinearLightBlendMode` clamps at 1.0 (every input above white comes out 1.000) | Arithmetic in place of the blend, in an HDR path | Small | Only if SDR keeps the blend |
| Masks using any of them | The same modules through `applyLocal`; luminance and color ranges select on the image entering the mask step, which is another picture in HDR | Follows the modules; range masks would select different areas in HDR and SDR | Follows | Follows |

Even with all of that built, expand first cannot meet "one set of sliders"
(next section).

### 2. One set of sliders: how the two versions respond

Change from the unedited render in stops (median / 90th / 99th percentile),
`IMG_0546.HEIC`, expand first on a materialized copy so the tone table is not
clamped:

| Control | SDR | Expand first | Gain last |
| --- | --- | --- | --- |
| Exposure −1 | −1.00 / −1.00 / −1.00 | −1.00 / −1.00 / −1.00 | −1.00 / −1.00 / −1.00 |
| Contrast +50 | +0.25 / +0.30 / +0.23 | +0.30 / +0.05 / +0.01 | +0.25 / +0.30 / +0.23 |
| Whites +50 | +0.05 / +0.13 / +0.16 | +0.10 / +0.21 / +0.20 | +0.05 / +0.13 / +0.16 |
| Highlights −50 | −0.18 / −0.32 / −0.35 | −0.30 / −0.54 / −0.59 | −0.18 / −0.32 / −0.35 |
| Curve (an S) | +0.15 / +0.22 / +0.15 | +0.21 / +0.03 / +0.01 | +0.15 / +0.22 / +0.15 |
| Dehaze −50 | +0.04 / −0.18 / −0.23 | −0.12 / −0.29 / −0.32 | +0.04 / −0.18 / −0.23 |

Ratio drift at native pixels, stops RMS, range over three windows:

| Control | Expand first, `0546` | Gain last, `0546` | Expand first, `0561` | Gain last, `0561` (Apple-only map) |
| --- | --- | --- | --- | --- |
| Exposure ±1 | 0.000 | ≤ 0.0001 | 0.000 | 0.011 to 0.035 |
| Contrast ±50 | 0.18 to 0.22 | ≤ 0.0001 | 0.26 to 0.31 | 0.011 to 0.037 |
| Whites ±50 | 0.06 to 0.09 | 0.0000 | 0.07 to 0.11 | ≤ 0.001 |
| Blacks +50 | 0.03 to 0.04 | 0.0000 | 0.03 to 0.08 | 0.009 to 0.021 |
| Highlights +50 | 0.07 to 0.09 | 0.0000 | 0.08 to 0.11 | ≤ 0.001 |
| Highlights −50 | 0.15 to 0.20 | 0.0000 | 0.21 to 0.32 | 0.002 |
| Shadows +50 | 0.03 to 0.06 | 0.0000 | 0.04 to 0.09 | 0.009 to 0.019 |
| Tone Curve (S) | 0.17 to 0.18 | ≤ 0.0001 | 0.22 to 0.25 | 0.014 to 0.031 |
| Color Mixer | 0.22 to 0.34 (clamped) | 0.0000 | 0.39 to 0.67 (clamped) | ≤ 0.004 |
| Color Grading | 0.18 to 0.27 (clamped) | 0.0000 | 0.27 to 0.64 (clamped) | ≤ 0.001 |
| Look-up table | 0.17 to 0.24 (clamped) | 0.0000 | 0.23 to 0.60 (clamped) | ≤ 0.006 |
| Dehaze +50 / −50 | 0.06 to 0.07 / 0.14 to 0.19 | ≤ 0.0001 | 0.08 to 0.09 / 0.16 to 0.29 | 0.009 to 0.040 |
| Clarity +50 | 0.03 to 0.05 | 0.0000 | 0.03 to 0.07 | 0.009 to 0.031 |
| Vibrance +50 | 0.02 to 0.03 | 0.0000 | 0.02 to 0.14 | ≤ 0.006 |
| Grain 50 | 0.16 to 0.23 (clamped) | 0.0000 | 0.22 to 0.59 (clamped) | ≤ 0.006 |
| Saturation, Black & White, Vignette, Sharpening | ≤ 0.02 | 0.0000 | ≤ 0.04 | ≤ 0.013 |
| Noise reduction 50 | 0.05 to 0.06 | 0.0006 | 0.03 to 0.12 | 0.004 to 0.019 |

- **Behave badly under expand first**: Contrast, Tone Curve, Highlights in both
  directions, Whites, Dehaze, and everything that clamps. The cause is not a
  bug: these controls depend on a pixel's level, and the HDR version's mid-tones
  are brighter (the median by 0.7 stops on `0546`, 1.0 on `0561`, 1.65 on the
  Pixel file), so the same slider works on other tones.
  Fine: Exposure, Saturation, Black & White, Vignette, Sharpening.
- **Under gain last none behaves badly.** With an ISO gain map the ratio is
  held exactly. With an Apple-only gain map (`0561`) Core Image's
  `applyingGainMap` depends slightly on the base's level: up to 0.04 stops RMS
  after an edit that moves levels. Small, but not zero; see Risks.
- **What gain last gives up.** The controls work on SDR tones. Light above SDR
  white has no handle of its own: Highlights −50 lowers the HDR 90th percentile
  by 0.32 stops, as in SDR, where expand first lowered it 0.54. There is no
  "how much HDR" control, though one would be cheap later
  (`applyingGainMap(_:headroom:)` scales the gain map's weight). No picture
  information is lost either way: the expanded decode is this same SDR picture
  times this same gain map.
- **Geometry.** The gain map goes through the stack's crop, turns and
  straightening like any image: crop-then-gain equalled gain-then-crop within
  0.0003 stops RMS (a crop with a quarter turn and 3°; the owner's three files
  and the synthetic one). A half- or quarter-size gain map needs no scaling by
  hand.

### 3. Live frames and the histogram

Prototype (appendix): the gain map applied as the last step of
`LiveRenderSession.render` and of `PreviewGenerator.hdrImage`, frames as
half-float images. Live frame against the settled rendition, same stack, 2560
pixels:

| File | Stack | Now (SDR both) | Prototype: live / settled mean, headroom | Live over settled |
| --- | --- | --- | --- | --- |
| `0546` | Unedited | 0.275 / 0.275 | 0.493 / 0.493, 2.49 | −0.001 stops |
| `0546` | Exposure −1 | 0.138 / 0.138 | 0.247 / 0.247, 1.25 | −0.001 |
| `0546` | Contrast +20 | 0.294 / 0.294 | 0.530 / 0.530, 2.50 | 0.000 |
| `0546` | Curve, Color Grading, grain, crop with 2° | 0.376 / 0.374 | 0.688 / 0.686, 2.57 | +0.004 |
| `0561` | Contrast +20 | 0.381 / 0.381 | 0.821 / 0.821, 4.57 | 0.000 |
| `0561` | Curve, Color Grading, grain, crop | 0.313 / 0.312 | 0.676 / 0.675, 4.60 | +0.003 |
| Pixel | Contrast +20 | 0.305 / 0.305 | 1.115 / 1.116, 6.32 | −0.001 |
| Pixel | Curve, Color Grading, grain, crop | 0.355 / 0.354 | 1.292 / 1.291, 4.80 | +0.001 |

Before #277's fix the two were 0.86 stops apart on `0546`.

Speed, median milliseconds:

| What | SDR now | HDR, gain last |
| --- | --- | --- |
| `LiveRenderSession` interactive frame, `0546` / `0561` / Pixel (prototype; the HDR frame has no histogram) | 8.1 / 7.6 / 11.3 | 9.3 / 9.0 / 12.9 |
| Probe, typical stack at 1920 × 2560, to a `CGImage` | 12.5 | 15.1 (half float, with the scan for the largest value) |
| The same to an IOSurface, no read-back | 12.5 | 12.6 |
| Probe, 2560 × 1440 region of the full-size decode (100%) | 10.0 | 10.0 to a surface, 11.7 to a `CGImage` |
| Settled full-size rendition, `0561` (warm; cold decode not measured) | — | 24 (expand first: 26) |

So HDR frames cost nothing on the GPU; the 1 to 3 ms is reading the frame back
to find its largest value. `LiveRegionRenderer` itself was not prototyped; the
region figures are the probe's.

Memory: a half-float frame is twice an 8-bit one (37 MB against 18 MB at
1920 × 2560; 28 against 14 at 2560 × 1440). The gain map kept for a session is
one byte per gain-map pixel: 3.1 MB (`0546`), 5.1 MB (`0561`), 0.8 MB (Pixel). No
second decode of the master is held: the base is the SDR decode the session
already keeps. A resident copy built from ImageIO's raw auxiliary data gave the
same result as the lazy one (RMS 0.0000).

Histogram: `Histogram(image:)` must not be given an HDR frame. It took 81 to
124 ms (0.2 ms for an SDR frame) and counted a tone-mapped picture (nothing in
the top bin of a frame with a third of its pixels above white, and a lower mean
than the darker SDR frame's). A float histogram of a 256-pixel reduction took
7.5 to 12 ms in the unoptimized probe.
What the HDR histogram shows (an axis that runs past SDR white, or the SDR
version's histogram) is a design decision; both are cheap.

What switches to SDR today, each needing HDR for #282's "never switches":
live frames (`LoupeView`, `setImage(…, extendedRange: false)`), the 100% region
(`LiveRegionRenderer`, 8-bit), the settled rendition for stacks
`preservesExtendedRange` turns away, the cached SDR preview shown first when a
photo opens, and frames with a mask overlay or a map. Gain last can make the
first paint HDR too (the cached SDR preview times the gain map through the
crop); not prototyped.

### 4. Which files macOS reads, and what decoding gives

| File | Read | HDR over SDR, mean (median) | Headroom |
| --- | --- | --- | --- |
| iPhone HEIC, Apple and ISO gain maps (`0546`) | Yes | +0.84 stops (0.270 → 0.439) | 2.62 |
| iPhone HEIC, Apple and ISO (`0542`, dark) | Yes | +0.97 stops (99th percentile 0.64 → 2.24) | 3.74 |
| iPhone HEIC, Apple's gain map only (`0561`) | Yes | +1.11 stops (0.310 → 0.621) | 4.55 |
| Pixel Ultra HDR JPEG, Adobe `hdrgm` XMP only | Yes, reported as an ISO gain map | +1.86 stops (0.312 → 0.980) | 6.31 |
| Core Image's own ISO HEIC and JPEG | Yes | as written (RMS 0.005 to 0.011 from the source) | 2.62 |

- All four real files lift mid-tones, not only highlights, as #277 found for
  one. The Pixel file's HDR version is nearly two stops brighter on average.
- `.expandToHDR`, ImageIO's HDR decode and `applyingGainMap` give the same
  picture; ImageIO's is 10 bit, Core Image's is float.
- `applyingGainMap(_:headroom:)` renders for a smaller headroom by the gain
  map's own rule (at 1.5: 99th percentile 0.94 to 1.5), which is how a display
  with less headroom than the file should be served.
- Not tested, no file: an iPhone JPEG with Apple's gain map, a gain map with
  three channels or an HDR base, other makers' Ultra HDR, orientations other
  than 1 and 6.

### 5. Writing (for a later export issue; not part of #282)

- `CIContext.heifRepresentation` and `jpegRepresentation` with `.hdrImage` write
  our SDR render as the base and derive an ISO gain map from our HDR render.
  Read back from `0546`: SDR within 0.016 to 0.020 stops RMS of ours, HDR within
  0.018 to 0.021, headroom 2.62. `.hdrGainMapImage` (the file's own gain map on
  the edited base) works as well for an uncropped photo.
- Core Image writes ISO 21496-1 only: no Apple gain map and no Adobe `hdrgm`
  XMP. Whether older Android and older Apple systems show such a file in HDR was
  not checked.
- ImageIO's `kCGImageDestinationEncodeToISOGainmap` makes its own SDR base by
  tone mapping (0.44 stops darker than ours on `0546`): not usable where the
  exported SDR must be our SDR render.

### Traps found (each cost time; each belongs in a test)

1. **Core Image returns the gain map unoriented.** Applied as loaded to an
   orientation-6 photo it gives a wrong picture (0.27 stops RMS off) with no
   error. Orient it by the file's EXIF orientation first.
2. **A lazy `.expandToHDR` decode is clamped near white by a filter that works
   in another color space** (`CIColorCurves` in the perceptual space here). The
   same pixels as a bitmap, a materialized copy, and SDR-with-gain-map are not.
   Removing the image's headroom tag changed nothing. The mechanism was not
   established. It matters to anything that edits HLG or PQ decodes (#283).
3. **`CIColorCube…extrapolate` is not an identity above white for colors.**
4. **`Histogram(image:)` on an HDR image is slow and tone-mapped.**
5. **`applyingGainMap` with an Apple-only gain map depends on the base's level**
   (up to 0.04 stops RMS).
6. **Today's comment on `preservesExtendedRange` is partly wrong**: the tone
   table does not clamp at white. Under gain last the property is no longer
   asked for gain-map photos at all.

### Which synthetic findings hold on the real files

All of them: gain last equals the system's HDR decode unedited; the clamps (the
ramp is synthetic by nature); expand first's drift; the crop geometry; frame
times; the writing round trip. Two things only the real files showed: the
orientation trap (the synthetic file has orientation 1) and the Apple-only gain
map's small level dependence. The synthetic file's gain-last drift (0.001 on
reduced renders) understated nothing: at native pixels the real ISO file reads
0.0000 to 0.0006.

## Recommendation

**Build #282 as gain last, with every adjustment available in HDR.** The
cheaper alternative the owner asked to weigh (some controls unavailable in HDR)
buys nothing here: under gain last no control costs anything, and under expand
first the controls that would be left available (Highlights, Shadows) are among
those that respond differently in the two versions.

Order of work:

1. **PhotoCore: the gain map as a source.** Load (ISO or Apple's, non-raw files
   only), orient, keep a resident copy for a session, apply through the stack's
   geometry. Tests on synthetic files for all eight orientations; identity
   against ImageIO's HDR decode; ratio held under every module; the opt-in
   real-file test of #277 extended.
2. **The per-photo choice.** Stored with the photo and undoable (owner's
   ruling). See Open questions for where.
3. **Settled rendition**: `hdrImage` for a gain-map photo whose choice is HDR,
   for any stack (no `preservesExtendedRange` test).
4. **Live frames** in `LiveRenderSession` and `LiveRegionRenderer`, the frame's
   headroom, `LoupeView`'s layer state, the first paint on opening, overlays.
5. **Histogram** in HDR, as designed.
6. **Loupe UI** (the designer's): the choice, which version shows, the
   comparison panes, the debug script's `print hdr`.

Risks:

- **Geometry beyond the crop.** Manual Distortion (available on any photo) and
  spots change where pixels are. The gain map must take the Distortion warp,
  and a healed or cloned spot should take the gain of its source, or a removed
  highlight leaves its glow. By construction, not measured.
- **Headroom on screen.** A frame's largest value moves with the edit (2.49 to
  2.57 on `0546`; 6.3 on the Pixel file, above the Dell's 4.18) and a single
  sharpening halo can raise it. If Core Animation tone-maps by that tag, the
  picture's brightness could shift while a slider moves. Rendering for the
  screen's headroom with `applyingGainMap(_:headroom:)` and a steady tag is the
  likely answer; it needs a person's eyes.
- **Apple-only gain maps** (trap 5): accept 0.04 stops, or apply Apple's formula
  in a kernel of our own.
- **Core Image behavior, observed on macOS 27.2.1 only.** `applyingGainMap`
  exists from macOS 15; nothing was run on macOS 26.
- **Render hash.** If the choice is an operation in the edit stack it enters
  `renderHash` and every toggle remakes SDR previews that have not changed,
  unless that operation is left out of the hash.

**Proposed Complexity for the implementation: Hard.** It touches the edit
stack's format or the catalog (the stored choice), the render path of the loupe
and off-main-actor work (`LiveRenderSession`, the region renderer, the preview
service's HDR lane), and reads auxiliary data from outside files.

## Open questions

For the product manager (PRD):

- Gain last means HDR light above SDR white has no control of its own, and
  there is no "how much HDR" control. Acceptable for #282, or is a strength
  control wanted (cheap)?
- The Pixel file's HDR version is 1.86 stops brighter on average and exceeds
  this Mac's display headroom. Should the loupe render for the display's
  current headroom (the gain map's own rule), or show the full version and let
  the system compress it?
- HLG, PQ and DNG merges gain nothing from this (they have no gain map). The
  live-frame and histogram work is reusable for them; the editing model is not.

For the designer:

- What the histogram shows in HDR.
- What the loupe shows while a mask overlay, the sharpening map or the fringe
  map is up, and during Show Original and a crop session.

For the implementation's plan:

- Where the choice lives: an edit-stack operation outside the groups (history
  and undo come free; must stay out of `renderHash`, presets, paste and
  `photocli adjustments`) or a column on `version` (a migration; its own undo
  step). Not decided here.

## Not checked

- Anything on a display: brightness while dragging, the first paint, the layer
  switching to extended range, Core Animation's tone mapping. No app was
  launched; `LoupeView` was not changed.
- `LiveRegionRenderer` with the gain map (probe timing only), Distortion and
  spots with a gain map, the first paint from the cached preview.
- Cold decode times; memory by measurement (frame and gain-map sizes are
  exact, footprint readings were too noisy to report).
- macOS 26 and 15; a JPEG with Apple's gain map; mirrored orientations.

## Appendix: the prototype

Applied to a copy of `develop` at `4561cb3`, switched by an environment
variable so both behaviors ran in one process. A sketch, not the design: no
per-photo choice, no histogram for HDR frames, the gain map loaded lazily.

New file `Sources/PhotoCore/Preview/GainMapSource.swift`:

```swift
public enum GainMapSource {
    /// The file's gain map turned as the decoded image is, nil without one.
    /// Core Image returns the auxiliary image as stored, not oriented.
    public static func load(_ url: URL) -> CIImage? {
        guard !SupportedFormats.isRaw(pathExtension: url.pathExtension), FileKind(pathExtension: url.pathExtension) != .video,
              let map = CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true]) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation != 1 else { return map }
        return map.oriented(forExifOrientation: Int32(orientation)).settingProperties(map.properties)
    }

    /// `rendered` (the stack over `decoded`, through `crop`) with the gain map,
    /// taken through the same crop, applied last.
    public static func apply(_ map: CIImage, to rendered: CIImage, decoded: CIImage, crop: Crop) -> CIImage {
        let fit = CGAffineTransform(translationX: decoded.extent.minX, y: decoded.extent.minY)
            .scaledBy(x: decoded.extent.width / map.extent.width, y: decoded.extent.height / map.extent.height)
        let placed = crop.apply(to: map.transformed(by: fit))
        return rendered.applyingGainMap(placed.settingProperties(map.properties))
    }
}
```

`PreviewGenerator.hdrImage`, at its start:

```swift
if getenv("SPIKE_GAINMAP_HDR") != nil, let map = GainMapSource.load(source) {
    let decoded = try Self.decode(source, longEdge: decodeLongEdge(source, stack: stack, longEdge: longEdge), draft: false,
                                  settings: renderer.decodeSettings(for: stack))
    var image = try renderer.apply(stack, to: decoded.image, context: decoded.context)
    image = GainMapSource.apply(map, to: image, decoded: decoded.image, crop: renderer.geometry(for: stack))
    if let longEdge { image = image.scaledToFit(longEdge: longEdge) }
    guard let rendered = engine.makeHDRCGImage(image) else { throw Failure.renderFailed }
    return rendered
}
```

`LiveRenderSession.render`, in place of the frame's final scale and
`makeCGImage` (with `gainMap` and `gainMapLoaded` as stored properties):

```swift
var extended = false
if getenv("SPIKE_GAINMAP_HDR") != nil, content == .photo, !overlaid {
    if !gainMapLoaded {
        gainMap = GainMapSource.load(self.source)
        gainMapLoaded = true
    }
    if let gainMap {
        image = GainMapSource.apply(gainMap, to: image, decoded: source, crop: renderer.geometry(for: stack))
        extended = true
    }
}
image = image.scaledToFit(longEdge: Int((Double(longEdge) * factor).rounded()))
guard let rendered = extended ? generator.engine.makeHDRCGImage(image)
    : generator.engine.makeCGImage(image, colorSpace: colorSpace) else {
    throw PreviewGenerator.Failure.renderFailed
}
let histogram = overlaid || content != .photo || extended ? nil : Histogram(image: rendered)
```

The probe's ratio drift, for whoever repeats the measurement (`luma` is linear
Display P3 luminance per pixel; pixels under 0.005 are skipped):

```swift
static func drift(_ hdr: Light, _ sdr: Light, _ hdr0: Light, _ sdr0: Light) -> Double {
    var sum = 0.0, n = 0.0
    for i in 0..<hdr.luma.count {
        guard sdr.luma[i] > 0.005, sdr0.luma[i] > 0.005, hdr.luma[i] > 0.005, hdr0.luma[i] > 0.005 else { continue }
        let a = log2(Double(hdr.luma[i] / sdr.luma[i])) - log2(Double(hdr0.luma[i] / sdr0.luma[i]))
        sum += a * a
        n += 1
    }
    return n > 0 ? (sum / n).squareRoot() : .nan
}
```

Controls and values tested: Exposure ±1; Contrast ±50; Whites ±50; Blacks +50;
Highlights ±50; Shadows +50; a Tone Curve through (0.25, 0.18) and (0.75, 0.82),
and one with white at 0.9; Color Mixer orange saturation +50, luminance +20;
Color Grading highlights hue 40 amount 50; a 17-point look-up table; Dehaze ±50;
Clarity +50; Vibrance +50; Saturation +50; Black & White on; Vignette −50;
Grain 50; Sharpening 80; Noise Reduction luminance 50.
