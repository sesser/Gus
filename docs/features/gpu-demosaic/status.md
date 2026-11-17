Issue: #196

# GPU demosaic for raws LibRaw decodes: implementation status

Feature, branch `feature/gpu-demosaic`, cut from `develop` at `34738c2`. The
PRD is the issue body (`gh issue view 196`), approved by the owner on
2026-11-16 with every open question at its default (Q1 a directional X-Trans
kernel written from published papers; Q2 Bayer in this issue; Q3 the speed
targets as written; Q4 a fixed baseline color noise reduction step with no
control; Q5 a fallback logged, not shown in the app; Q6 a hidden debug switch
keeps LibRaw's demosaic selectable; Q7 the owner's RAFs through environment
variables, never committed). There is no `design.md`: the PRD has no UI
change, and none was needed.

**Status: Done** (2026-11-16). Every requirement is built and tested and
every criterion measured. The owner ruled on both Requirements issues the
same day (PRD rev 2): AC3 is accepted as measured (follow-up #199, a sharper
X-Trans demosaic), AC4 applies only to files at ISO 800 or lower (high ISO is
judged by AC5 and AC6), and AC6 is accepted as a whole (five of 28 files at
detail 0.92x to 0.94x). The code review's findings C1 to C9 are fixed (below).
One open question for the product manager, Q2 below (AC2's edge chroma error
on the E-M5 III), does not block. Next: code review's second pass, the
designer is not needed (no UI change), then qa-tester.

## What was built

- **Unpack only** (`Demosaic/SensorMosaic.swift`): LibRaw opens and unpacks;
  the visible area is copied into page-aligned memory Metal uses in place,
  with the pattern (`CFAPattern`: Bayer 2 x 2 or X-Trans 6 x 6, checked over
  12 x 12 sites), the black of each pattern site (common, per color and
  repeating, as LibRaw sums them), the white span and the multipliers
  `LibRawDecoder` gives LibRaw, so the output has LibRaw's own scale and the
  existing color step takes it unchanged. LibRaw's buffers are freed
  (`libraw_recycle`) before the GPU's are made.
- **Kernels** (`Demosaic/DemosaicKernels.swift`, compiled at run time in the
  safe math mode with `#pragma clang fp contract(off)`; host
  `Demosaic/GPUDemosaic.swift`). They normalize as they read the 16-bit
  values, so no normalized mosaic is kept.
  - Bayer: the #194 spike's Hamilton–Adams green with gradient-weighted
    blending, red and blue by bilinear color differences.
  - X-Trans: four directional green estimates by the constant color
    difference assumption, with taps derived from the pattern
    (`Demosaic/DemosaicTables.swift`: on a Bayer pattern the same derivation
    gives Hamilton and Adams' taps, which a test checks), blended by inverse
    squared directional variation; red and blue as green less an
    edge-weighted mean of G − R or G − B over that color's sites in the 5 x 5
    window, with the distance weights moved so their centroid is the pixel.
    Within 6 pixels of an edge, where mirrored samples break the pattern, each
    color is the mean of its 3 x 3 (or 5 x 5) samples.
  - Half size: each color's mean in a window around each 2 x 2 block (2 x 2
    for Bayer, 4 x 4 for X-Trans).
- **Baseline color noise reduction** (R9): an edge-avoiding à trous smoothing
  of R − G and B − G, three levels (1, 2, 4 pixels apart), 5 x 5 B3-spline
  windows, rational weights by luminance and color difference against the
  noise the file's own Poisson–Gaussian model predicts at the pixel
  (`Demosaic/NoiseModel.swift`: estimated from neighbouring green pairs,
  median absolute deviation per level, weighted line fit, every eighth row);
  luminance is kept. Fixed strengths (h 2 for luminance, 3 for color,
  halving per level). It runs in place in bands of 256 rows through small
  float scratch textures, so no second full-size image is made.
- **Decode** (`Preview/LibRawDecoder+GPU.swift`): for a raw with a supported
  pattern and usable color data, LibRaw unpacks, the GPU demosaics, and the
  crop box, the orientation (LibRaw's flip, whole-pixel moves), a Fujifilm
  RAF's frame and lens corrections and the color step follow as before. Any
  other file, any GPU failure (no device, compile, allocation, execution) and
  the debug switch give LibRaw's own decode, unchanged, with a log notice
  naming the file (private) and the reason. A task cancelled after the unpack
  throws `CancellationError`, which the preview pipeline now passes on instead
  of reporting the file undecodable. `SystemRAWDecoder.reads` still decides
  which decoder a file gets; nothing changed for files the system reads.
- **`photocli render`** prints `decoder` (`systemRAW`, `libRaw`, `imageIO`)
  and, for LibRaw's decodes, `demosaic` (`{"method": "gpu", "pattern":
  "xTrans"}` or `{"method": "libraw", "reason": …}`), and takes `--demosaic
  libraw`.
- `PreviewCacheKey.currentPipelineVersion` is 12, a plain bump.
- `photobench demosaic` (`truth`, `real`, `timing`, `live`, `memory`,
  `pattern`); the #194 spike's measures are in `PhotoFixtures/DemosaicMeasure.swift`,
  shared with the tests. `SyntheticDNG` writes any CFA pattern.

## Debug switch (Q6)

Hidden, for comparing; never a user setting:

- the apps: launch option `--demosaic libraw`;
- every tool and the tests: `RAW_DEMOSAIC=libraw` in the environment;
- one render: `photocli render FILE --out OUT --library-root LIB --demosaic libraw`;
- in code and tests: `LibRawDecoder.$demosaicOverride.withValue(.libRaw)`, or
  `decode(url, demosaic: .libRaw)`.

Proposed for `CLAUDE.md` (the owner's file), under Commands:
`XTRANS_SAMPLES=a.RAF:b.RAF swift test --filter DemosaicXTransSampleTests`,
`BAYER_SAMPLES=a.RW2:b.CR2 swift test --filter DemosaicTruthTests`, and
`swift run -c release photobench demosaic --mode timing --files a.RAF`; and a
line under Rendering that raws LibRaw decodes are demosaiced by our kernels
(`Demosaic/`), with `--demosaic libraw` / `RAW_DEMOSAIC=libraw` to compare.

## Published sources (R11, AC8)

Written from these descriptions and from measurement; no code, table or
constant was taken from LibRaw's demosaic source, darktable, RawTherapee,
dcraw, LightCraft, lensfun or the Adobe DNG SDK, none of which was opened.

- Hamilton and Adams, US patent 5,629,734 (directional green with the own
  color's second difference) — Bayer green; the X-Trans green's derivation
  reduces to it on a Bayer pattern.
- Gunturk, Glotzbach, Altunbasak, Schafer and Mersereau, "Demosaicking: color
  filter array interpolation", IEEE Signal Processing Magazine 22(1), 2005
  (constant color difference methods) — the X-Trans green estimates and the
  red and blue interpolation of both kernels.
- Pekkucuksen and Altunbasak, "Gradient based threshold free color filter array
  interpolation", ICIP 2010 — blending directional estimates by inverse
  squared gradients (two directions for Bayer, generalized here to four).
- Kimmel, "Demosaicing: image reconstruction from color CCD samples", IEEE TIP
  8(9), 1999 — edge-directed weights for the color differences.
- Dammertz, Sewtz, Hanika and Lensch, "Edge-avoiding À-Trous wavelet transform
  for fast global illumination filtering", HPG 2010 — the noise reduction's
  structure (dilated B3-spline windows, edge-stopping weights, halving).
- Foi, Trimeche, Katkovnik and Egiazarian, "Practical Poissonian-Gaussian noise
  modeling and fitting for single-image raw-data", IEEE TIP 17(10), 2008 — the
  noise model σ² = a·x + b from the raw itself.
- Hampel's median absolute deviation (×1.4826) as a robust scale.
- Prototypes tried and dropped, measured (below): Hirakawa and Parks,
  "Adaptive homogeneity-directed demosaicing algorithm", IEEE TIP 14(3), 2005
  (homogeneity selection over four directions); directional linear minimum
  mean square error filters trained on binned truths (after Zhang and Wu,
  IEEE TIP 14(12), 2005); X. Li, "Demosaicing by successive approximation",
  IEEE TIP 14(3), 2005; steering kernel regression (Takeda, Farsiu and
  Milanfar, IEEE TIP 16(2), 2007); Freeman's median of color differences (US
  patent 4,724,395).

`THIRD_PARTY_NOTICES.md` is unchanged: nothing was derived from another
project's code (the PRD expected nothing).

## Build and tests

Machine: Apple M4 Pro (14 cores), 24 GB, macOS 27.2.1, Xcode 26 toolchain
(MacOSX 27.2 SDK).

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline, `develop` at `34738c2` (2026-11-16) | green, no warnings | 1047 tests in 156 suites passed (one unnamed failure in the first of three runs, not reproduced in the next two: flaky, not this feature's) |
| After the first pass | green, no warnings (debug, and `-c release` for `photobench` and `photocli`) | 1067 tests in 161 suites passed |
| After the code review's fixes, `522f41f` | green, no warnings | **1071 tests in 161 suites passed** (68 s) |

Latest full run: 2026-11-16, at `522f41f` (the review fixes; the commits
after it change only this file): 1071 tests in 161 suites passed. (An earlier
line here named `5003d8a`, a commit since rewritten; code review C4.)
At `522f41f`, `XTRANS_SAMPLES` with the X-E3 `DSCF5123` (ISO 400), an X-T3 at
ISO 160 and the X-T3 `DSCF4583` (ISO 6400): `DemosaicXTransSampleTests` passed
(2 tests, 317 s in a debug build; AC4 checked on the first two, recorded on the
third; no file under AC6's detail bound).

New suites, run in every `swift test` on small synthetic mosaics and DNGs
(they skip, saying so, where there is no Metal device):
`DemosaicKernelTests` (kernels against their CPU reference, half-float writes,
tables, half floats), `ColorNoiseReductionTests`, `GPUDemosaicDecodeTests`.
Opt-in: `DemosaicXTransSampleTests` (`XTRANS_SAMPLES`), `DemosaicTruthTests`
(`BAYER_SAMPLES`); the existing `LibRawFallbackTests` (`RAF_SAMPLE`) and
`LibRawAgainstSystemTests` (`RAW_BOTH_SAMPLES`) now run through the GPU path.

## Samples (never committed)

From the owner's archive (read only), 28 copies in the session's scratch
folder: X-E3 (ISO 200 to 8000, 13 files), X-T3 (ISO 160 to 12800, 9 files),
X100S (X-Trans II, ISO 200 to 3200, 6 files), plus the Bayer samples
GX85.RW2, Canon5DMkII.CR2 and EM5MarkIII.ORF in the owner's samples folder.

| Class | Decoder (`SystemRAWDecoder.reads`, macOS 27.2.1) | Used for |
|---|---|---|
| Fujifilm X-E3, lossless compressed | LibRaw (the system gives no image) | AC3, AC4, AC6, AC9, AC12, timing |
| Fujifilm X-T3 | system decoder (cross-check only) | AC3, AC4, AC5, AC6 (decoded through `LibRawDecoder` directly), timing |
| Fujifilm X100S (X-Trans II) | system decoder | another phase of the 6 x 6 pattern (LibRaw reports `RBGBRG/…`): our kernels take it |
| GX85 RW2, 5D II CR2, E-M5 III ORF | system decoder | Bayer path through `LibRawDecoder` directly; truths for AC2, AC3 |

The X100S's pattern is the X-E3's shifted by a row; `DemosaicTables` is made
from whatever 6 x 6 pattern LibRaw reports and is tested for all 36 phases.

## The PRD's thresholds and targets against the #194 spike (checked first)

Checked before any design decision, against `spike.md` and `status.md` of
`origin/feature/decode-pipeline-spike`.

- **R14 (X-Trans full size at most 1.0 s): confirmed** (spike 582 and 609 ms,
  525 to 550 ms of it LibRaw's unpack).
- **R15 (Bayer no slower than LibRaw at -O3; Should 0.4 s): confirmed** (spike
  92, 294, 304 ms).
- **R16 (half size no slower, about 0.6 s): confirmed**, unpack-bound.
- **R17 (GPU under 100 ms, Should): plausible, unmeasured by the spike.**
- **R18 (white balance frame no slower): confirmed**: the kept decode and the
  color step do not change.
- **R21 (peak at most 400 MB above baseline at 24 MP): confirmed with a design
  condition.** A noise step that reads the demosaiced image and writes a
  second full-size one would add 194 MB to the PRD's 340 MB; the design keeps
  no normalized mosaic and runs the noise step in place, in bands.
- **AC3, AC4 (X-Trans quality): kept as written, unmeasured by the spike.**
  The X-T3 sample is ISO 6400 (`exiftool`), so its false color (LibRaw 8.14
  against the X-E3's 4.09 at ISO 400) is chroma noise as much as demosaic
  error, and per-pixel ΔE against LibRaw includes LibRaw's noise.
- **AC5, AC6, AC7: kept as written.**

No requirement needed to change before the work. After it, two do (RI-1, RI-2).

## Measurements

### Speed (AC15; R14 to R18)

`photobench demosaic --mode timing --runs 6 --libraw`, release, files in the
file cache, decode plus render to 8-bit sRGB: first run, then the median of
the other five (min–max). Full table in `docs/PROFILING.md`.

| File | Ours full (R14/R15) | LibRaw full | Ours half (R16) | LibRaw half | GPU full (R17) |
|---|---|---|---|---|---|
| X-E3 RAF 24 MP | **0.62 s** ≤ 1.0 ✓ | 7.88 s | 0.56 s ✓ | 0.59 s | 78 ms ✓ |
| X-T3 RAF 26 MP | **0.65 s** ≤ 1.0 ✓ | 8.37 s | 0.59 s ✓ | 0.62 s | 85 ms ✓ |
| GX85 RW2 16 MP | **0.10 s** ✓ (Should ≤ 0.4 ✓) | 0.40 s | 0.08 s ✓ | 0.11 s | 24 ms ✓ |
| 5D II CR2 21 MP | **0.30 s** ✓ ✓ | 0.62 s | 0.28 s ✓ | 0.29 s | 32 ms ✓ |
| E-M5 III ORF 20 MP | **0.31 s** ✓ ✓ | 0.63 s | 0.29 s ✓ | 0.31 s | 30 ms ✓ |

R18 (`--mode live`, X-E3, medians of 30 frames, two runs each): a white
balance frame at fit 8.2 to 9.2 ms with our demosaic, 8.3 to 8.4 ms with
LibRaw's; exposure 8.5 to 9.0 against 8.4 to 8.6 ms (equal within run-to-run
noise). At 100% (`LiveRegionRenderer`): the full decode 0.76 s against 8.06 s,
the first region 4 ms against 4 to 5 ms, a white balance region 2.5 ms
against 2.5 to 2.6 ms.

R21/AC13 (`--mode memory`, one full-size decode in a fresh process, peak
footprint over the footprint before): X-E3 **295 MB** (LibRaw's own: 550 MB),
X-T3 **315 MB** (595 MB), 5D II 265 MB. Within the 400 MB bound.

### Quality against a known truth (AC2, AC3 synthetic half)

`BAYER_SAMPLES=… swift test --filter DemosaicTruthTests` (the same as
`photobench demosaic --mode truth --nr off`): each Bayer raw binned 2 x 2 is
the truth; sampled through RGGB and through the X-E3's X-Trans pattern into
DNGs; the kernels alone (no noise step) against LibRaw's own (AHD; three-pass
X-Trans). CPSNR over sRGB-encoded values; edge chroma error p95 in Lab of
linear sRGB at the truth's top 10% of L* gradient.

| Truth | Bayer: ours / LibRaw AHD, CPSNR | edge chroma p95 | X-Trans: ours / LibRaw 3-pass, CPSNR | edge chroma p95 |
|---|---|---|---|---|
| GX85 | **33.83** / 33.23 ✓ | **16.73** / 17.93 ✓ | 33.12 / 33.38 (−0.26) ✗ | 18.94 / 18.38 (1.03x) ✗ |
| 5D II | **41.95** / 41.96 ✓ | **8.28** / 8.34 ✓ | 41.52 / 42.61 (−1.09) ✗ | 8.81 / 7.93 (1.11x) ✗ |
| E-M5 III | **47.99** / 47.92 ✓ | 2.04 / 1.97 (1.04x; the PRD gives no figure for this smooth subject) | 47.58 / 47.91 (−0.33) ✗ | 2.54 / 2.03 (1.25x) ✗ |

AC2 (Bayer) is met for the files the PRD names; the E-M5 III's edge chroma
error is 4% over LibRaw's (2.04 against 1.97), where the PRD gives no spike
figure. AC3's synthetic half is **not met** (RI-1). The errors are thin
colored fringes along strong straight edges at angles none of the four
directions follows (error maps in the session's scratch folder; LibRaw's
homogeneity choice handles them better).

### Real X-Trans files against LibRaw's own (AC3 real half, AC4, AC6)

`photobench demosaic --mode real` (and `--nr off`), the middle 2048 x 2048,
through the built-in color step and look. False color and detail are each
picture on its own edges; ratios are ours over LibRaw's. The spike's LibRaw
figures are reproduced exactly (X-E3 4.09 / 2.53, X-T3 8.14 / 2.95).

| | Files | False color ≤ 1.0x | Detail ≥ 0.95x | Both | Blocks median ≤ 1, p95 ≤ 2 | Edge ΔE median ≤ 5 |
|---|---|---|---|---|---|---|
| Kernel alone (AC3) | 28 | 26 (ratios 0.52–1.01) | 17 (0.82–1.04) | 15 | 19 | 14 |
| With the noise step (AC6, AC4) | 28 | **28** (0.17–0.82) | 23 (0.92–1.09) | 23 | 16 | 11 |
| With the noise step, Should (≤ 0.5x at ≥ 0.9x) | 28 | 16 | | 16 | | |

The PRD's two files, with the noise step: X-E3 `DSCF5123` false color 0.75x
at detail 1.02x, blocks 0.27 / 1.43, edges 3.42 (AC4 ✓, AC6 Must ✓, Should ✗);
X-T3 `DSCF4583` (ISO 6400) 0.17x at 1.02x, blocks 0.95 / 2.33, edges 8.42
(AC6 ✓ Must and Should; AC4 ✗ on p95 and edges). Kernel alone: X-E3 0.83x at
1.02x (AC3 ✓), X-T3 0.66x at 0.90x (AC3 ✗ on detail).

The five files under AC6's detail bound with the noise step (X-E3 ISO 400,
800 and two at 3200; X-T3 ISO 160) are 0.92 to 0.94: they are already under
it without the step (0.85 to 0.93): the kernel is a little softer than
LibRaw's three passes. Turning the kernel's color difference correction up
makes it sharper on these measures (×1.5: detail 0.98 to 1.06) and less
accurate against the truth (5D II −0.4 dB more), so it was left at the
derivation's value. AC4 fails where the files are noisy: at ISO 1600 and up
LibRaw's own output differs from ours per pixel by its color noise (without
the noise step, the flat-area median ΔE between the two is already 5.3 on the
X-T3), and the noise step removes color blotches that survive 16-pixel
blocks. Full per-file tables: `photobench demosaic --mode real` output, kept
in the session.

### The X-T3 against the system decoder (AC5)

`RAW_BOTH_SAMPLES=… swift test --filter LibRawAgainstSystemTests` (at 1500 px):
block ΔE at 5500 K against the system decoder, `DSCF4583`: ours **10.4**,
LibRaw's 10.0: under 20 ✓ and within +1 ✓. Two more X-T3 files: ISO 160 17.4
both; ISO 12800 12.5 against 11.3 (+1.2). The suite's expectations pass.

### Flat areas and small details (AC6 flat, AC7)

`ColorNoiseReductionTests` (every run): a grey ramp with noise of σ 0.01, as a
DNG, through our decode and LibRaw's: color-difference noise in the flat
interior 0.20x (X-Trans) and 0.25x (Bayer) LibRaw's. Thin colored lines (one
pixel green, two pixels magenta) with noise σ 0.015: contrast 100% to 101% of
the input; edge ΔE median against the noise-free demosaic 1.24 to 1.29 (before
the step 1.89 to 1.98); without noise the step moves edges by ΔE 0.94 to 1.02
at the 95th percentile.

### Kernels against their CPU references (AC8a)

`DemosaicKernelTests` and `ColorNoiseReductionTests`, 96 x 96 mosaics with
noise, black 1022, white 16383, multipliers 0.55 / 1 / 0.72: every Float32
value of every kernel (Bayer RGGB and GBRG, X-Trans at three phases, half
size, each noise level 1, 2, 4) is **identical** to its plain-Swift reference
(27,648 values per case, 0 over the derived bounds, which are in the tests'
comments). Half-float outputs are within 2⁻¹⁰ of the Float32 outputs (Metal
rounds half writes toward zero). Bands of 16 rows give the same image as one
pass.

## Requirements and acceptance criteria

| Item | State | Test or check |
|---|---|---|
| R1 LibRaw unpacks, our kernels demosaic, `CameraColor` unchanged; system-read raws untouched | Done | `GPUDemosaicDecodeTests.whichDemosaic`, `.systemDecoderStillDecides`; the existing `LibRawDecoderTests`, `CameraColorStepTests`, `WhiteBalanceAcrossDecodersTests` pass both ways (`RAW_DEMOSAIC=libraw`) |
| R2 X-Trans first | Done | `DemosaicKernelTests`, the sample suites |
| R3 Bayer in this issue | Done | `DemosaicKernelTests`, `DemosaicTruthTests` |
| R4 other CFAs keep LibRaw's demosaic | Done | `GPUDemosaicDecodeTests.whichDemosaic` (a linear DNG: LibRaw's pixels, byte for byte) |
| R5 Fujifilm frame and lens corrections | Done | `LibRawFallbackTests` (RAF_SAMPLE) and `DemosaicXTransSampleTests.frameAndFallback`: 6000 x 4000, corrections on; alignment with the camera's JPEG median 0.30 px, p90 0.76 (LibRaw's demosaic: 0.31, 0.83) |
| R6 white balance re-runs only the color step | Done | `GPUDemosaicDecodeTests.whiteBalanceRunsNoDemosaic`; `LibRawDecoderTests.decodeSettingsDoNotDecodeAgain` |
| R7 directional X-Trans kernel | Done | four directions, `DemosaicTables` |
| R8 quality bar | Done, as ruled (PRD rev 2: AC3 accepted as measured, AC4 at ISO ≤ 800) | Measurements above |
| R9 baseline color noise reduction | Done | `ColorNoiseReductionTests`; real files above |
| R10 CPU references, safe math, fp contract off, 2⁻¹⁰ | Done | `DemosaicKernelTests`, `ColorNoiseReductionTests` |
| R11 clean room | Done | Published sources above; for code review |
| R12 Noise Reduction group unchanged | Done | no editor or stack code changed; `LibRawDecoderTests.machineLearningReasonIsTheCamera` (now through the GPU path) |
| R13 no stack change | Done | `EditStackCorpusTests` (bytes and hashes unchanged); no migration |
| R14 X-Trans ≤ 1.0 s | Done | 0.62 / 0.65 s |
| R15 Bayer no slower; Should ≤ 0.4 s | Done | 0.10 / 0.30 / 0.31 s |
| R16 half size no slower | Done | all five faster |
| R17 GPU < 100 ms (Should) | Done | 78 to 85 ms X-Trans, 24 to 32 Bayer |
| R18 live frames no slower | Done | above |
| R19 fallback per decode | Done | `GPUDemosaicDecodeTests.fallbackOnFailure` (execution failure, no device; Bayer and X-Trans); X-E3 in `DemosaicXTransSampleTests.frameAndFallback` |
| R20 logged; `photocli` names the demosaic | Done | `fallbackOnFailure` reads the log line back (`OSLogStore`); `renderReportsTheDemosaic` checks the `decoder` and `demosaic` keys and `--demosaic` (code review C6) |
| R21 cancellable, off the main thread, ≤ 400 MB | Done | `GPUDemosaicDecodeTests.cancellation`; 295 / 315 MB |
| R22 macOS 15 | Done | APIs: `MTLCompileOptions.mathMode` (15), linear textures, `makeBuffer(bytesNoCopy:)`; no `Float16` |
| R23 version 12, plain bump | Done | `GPUDemosaicDecodeTests.pipelineVersion` |
| AC1 | Done | as R1, R4 |
| AC2 | Done for GX85 and 5D II; E-M5 III edge chroma error 2.04 against 1.97 (1.04x), see Q2 | `DemosaicTruthTests` (`BAYER_SAMPLES`; it expects AC2, so it reports the E-M5 III) |
| AC3 | Accepted as measured (owner, RI-1, PRD rev 2; follow-up #199) | synthetic −0.26 to −1.09 dB; real files both bounds on 15 of 28. `DemosaicTruthTests` and `DemosaicXTransSampleTests` print it, they don't expect it |
| AC4 | Done at ISO ≤ 800 as ruled (RI-2): X-E3 `DSCF5123` ✓; 7 of 10 files at ISO ≤ 400 ✓, three just outside, accepted in rev 2 | `DemosaicXTransSampleTests` expects it for files at ISO ≤ 800 (the file's ISO from LibRaw), so it reports those three when they are among the samples |
| AC5 | Done | 10.4 against 10.0 |
| AC6 | Accepted as a whole (owner, rev 2): false color ≤ 1.0x on 28 of 28, detail ≥ 0.95x on 23 of 28 (five at 0.92x to 0.94x, both named files ✓); Should on 16 of 28; flat patches ✓ | `DemosaicXTransSampleTests` expects false color and records detail, listing the files under 0.95x (code review Q1, answered); `ColorNoiseReductionTests.flatColorNoise` |
| AC7 | Done | `ColorNoiseReductionTests.keepsLinesAndEdges` |
| AC8a | Done | above |
| AC8 | Done (code review found no copied code) | sources above |
| AC9 | Done | as R5 |
| AC10 | Done | as R6 |
| AC11 | Done | as R12, R13 (no UI or stack code changed) |
| AC12 | Done | as R19, R20; also a scratch allocation failure after the demosaic is encoded (`scratchAllocationFallsBack`, code review C1) |
| AC13 | Done | as R21 |
| AC14 | Done | `GPUDemosaicDecodeTests.pipelineVersion`; `docs/USER_GUIDE.md` says previews are made again once |
| AC15 | Done | tables above and in `docs/PROFILING.md` |
| AC16 | Done | the three new suites run everywhere on small mosaics; 24 MP only behind the sample variables |

## Requirements issues: ruled

Both were ruled by the owner on 2026-11-16 and recorded in the PRD (rev 2);
the reasoning that went to them stays in the PRD's Revisions and the commit
history of this file.

- **RI-1 (AC3): accepted as measured.** The X-Trans kernel alone is 0.26 to
  1.09 dB under LibRaw's three passes against binned truths, with 1.03x to
  1.25x its edge chroma error, and on 11 of 28 real files under 0.95x of its
  detail (0.82x to 0.94x). The feature ships with it; the sharper kernel is
  #199. With the noise step, false color is 0.17x to 0.82x on all 28.
- **RI-2 (AC4): applies at ISO 800 or lower.** At high ISO per-pixel and block
  ΔE against LibRaw's output measure LibRaw's color noise once ours is removed
  (X-T3 at ISO 6400: blocks 0.95 / 2.33, edges 8.42); high ISO is judged by AC5
  and AC6. At low ISO 7 of 10 files meet it; the three just outside are part of
  what the owner accepted.
- **AC6: accepted as a whole**, with five files at detail 0.92x to 0.94x
  (code review Q1: the sample suite records detail and lists those files; it
  expects false color).

## Questions for the product manager

- **Q2 (AC2, E-M5 III).** AC2 asks the Bayer kernel's edge chroma error p95 to
  be at most LibRaw AHD's; on the E-M5 III truth it is 2.04 against 1.97
  (1.04x). The PRD's spike figures leave that file out ("smooth E-M5 III not
  given"), and its CPSNR passes (47.99 against 47.92). The kernel is the #194
  spike's, unchanged. `DemosaicTruthTests` expects AC2 as written and so
  reports the E-M5 III when it is among `BAYER_SAMPLES`. Options: accept it as
  measured, or restrict AC2's edge chroma bound to the files the spike gave
  figures for. Nothing was loosened here.

## Code review (first pass) and the fixes

| # | Finding | Fix |
|---|---|---|
| C1 | An allocation failure of the noise reduction's scratch, after the demosaic was encoded, released a compute encoder without `endEncoding`: Metal aborts the process | `run` and `denoise` end the encoder on every throw (`do`/`catch` around the encoding). New fault `GPUDemosaic.InjectedFault.scratchAllocation` and test `scratchAllocationFallsBack`: Bayer and X-Trans decodes fall back to LibRaw's pixels, byte for byte, and the next decode is ours; `denoise` throws the failure. With the fix removed, the test aborts with `Command encoder released without endEncoding` (checked) |
| C2 | A raw stopped while it rendered for an export came back as `.writeFailed` and could make the export read as finished with failures | `ExportJob.outcome(of:name:)` maps `CancellationError` to a new `Outcome.cancelled`, and `ExportJob.tally` counts it neither done nor failed, so `summary.cancelled` holds and no failure is listed. Test `stoppedExportIsNotAFailure`: an export render of a raw only LibRaw decodes, in a stopped task, is `cancelled` and writes nothing; the tally's rules |
| C3 | The X-Trans sample suite still expected AC3 and AC4 as first written | AC4 expected only at ISO ≤ 800 (`LibRawDecoder.Output.iso`, new, from LibRaw's `iso_speed`); AC3 printed; AC6 false color expected, detail recorded and the files under 0.95x listed. The truth suite expects AC2 and prints the X-Trans half (AC3). No tolerance changed |
| C4 | `status.md` said Blocked and named a rewritten commit | This file: Done, the rulings, the AC rows, the last full run at `522f41f` |
| C5 | GPU tests returned and passed with no device; a compile failure did too | The three GPU suites (and the GPU tests of `GPUDemosaicDecodeTests`) are `.enabled(if: hasMetalDevice, "No Metal device: …")`; they call `GPUDemosaic.shared()` directly, so a compile failure fails them. Where the system decoder reads the small DNG (AC10, the export and render tests) they skip with `Test.cancel("…")`, saying why |
| C6 | `photocli render`'s `decoder` and `demosaic` keys and `--demosaic` had no test | `renderReportsTheDemosaic`: ours (`gpu`, `xTrans`), `--demosaic libraw` (`libraw`, `chosen`), `Automatic` accepted, `ahd` refused (`invalidValue`), a JPEG `imageIO` with no `demosaic` |
| C7 | The per-color blacks are read at an unchecked offset in LibRaw's struct | `SensorMosaic.blackLayoutHolds` checks `black`'s and `data_maximum`'s offsets against the header's layout (`curve` and `cblack` are too large for Swift to import); a mismatch makes the decode LibRaw's own (`Unsupported.blackLayout`). Test `blackLayout` |
| C8 | Row padding of GPU outputs was never written, so two decodes' data could differ | The padding is zeroed when the output is allocated (`PageAlignedStorage.zeroPadding`) |
| C9 | `Pixels` was `@unchecked Sendable` with only `Sendable` members | Plain `Sendable` |

## Design questions

None: no UI changed.

## README

The README's statements about LibRaw's speed (if any) should say that raws
macOS can't decode open at 100% in under a second (0.6 s for an X-E3), with a
fixed color noise reduction; `photobench demosaic` is a new tool mode; the
debug switch `--demosaic libraw` / `RAW_DEMOSAIC=libraw` is a development
option. No build command or layout change beyond `Sources/PhotoCore/Demosaic/`.

## Proposed follow-up issues

- Filed as #199: **enhancement: A sharper X-Trans demosaic (homogeneity-directed).** Body:
  #196's kernel is 0.3 to 1.1 dB under LibRaw's three passes against binned
  truths, with thin color fringes along strong edges at angles its four
  directions don't follow, and a little softer on real files (detail 0.82x to
  0.94x on 11 of 28). Build full-color candidates per direction in bands of
  rows and choose by homogeneity (Hirakawa and Parks 2005), keep the CPU
  reference and the 1 s budget. Measures and sample set as in #196's
  `status.md`.
- **bug (small): LibRaw's own X-Trans demosaic fails with an I/O error on
  frames of 450 rows or fewer** (the #194 spike's band finding, met again
  here with a 192-row synthetic X-Trans DNG). Only the fallback path is
  affected now, and no camera's frame is that small; worth a note.
