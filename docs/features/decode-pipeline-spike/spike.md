# Our own GPU raw pipeline: the spike (#194)

Run 2026-11-16 on an Apple M4 Pro (10 performance and 4 efficiency cores,
24 GB), macOS 27.2.1 (26B131), Swift 6.4.2 with the macOS 27.2 SDK,
`photobench` built `-c release`. The vendored LibRaw 0.22.3 as the app
builds it. Written from published descriptions and measurement: the
demosaics from their papers (cited in `MetalDemosaic.swift`), lensfun's
models from its manual and header documentation, the lensfun database read
as data by our own parser. No lensfun, LibRaw-derived or other project's
code was copied; the Adobe DNG SDK was not opened (#170 ruling C1). The
spike code is throwaway (`Sources/PhotoBench/DecodeSpike/`; `status.md`
says what to keep and has every command).

**Timing conventions.** Raws were in the OS file cache for every run (no
cache purge: "cold" below means the first run in a fresh process, not a cold
disk). "Median" is over the runs after the first; the spread is given as
min–max. LibRaw is single-threaded here (see Question 1).

## Verdict

1. **LibRaw's time is its demosaic, then its unpack.** A full Bayer decode
   is 0.9 to 1.2 s, of which the AHD demosaic is 640 to 835 ms; an X-Trans
   decode is 8.7 to 9.4 s, of which the three-pass demosaic is 8.1 to 8.7 s
   (93%). The unpack (decompression) is 62 ms (GX85), 241 to 256 ms (CR2,
   ORF) and 507 to 544 ms (compressed RAF), single-threaded. **The build
   leaves speed on the table: SwiftPM compiles LibRaw at `-Os`; at `-O3`
   AHD is 3 times as fast** (GX85 638 → 216 ms, 5D II 828 → 286 ms) and
   X-Trans 10% faster. Bands across cores (#177) take an X-E3 from 9.0 s to
   1.85 s with 8 bands.
2. **The hybrid works and is fast.** LibRaw's unpack, our Metal demosaic,
   our existing color step: GPU demosaic 5 to 15 ms at 16 to 26 MP, end to
   end 85 to 92 ms (GX85) and 290 to 610 ms (the rest), of which 68 to 90%
   is LibRaw's unpack. Against a known truth our Hamilton–Adams kernel is as
   good as LibRaw's AHD (5D II 41.96 dB both; GX85 33.84 against 33.23) in
   about 1/50 of the time AHD takes as the app builds it (1/20 at `-O3`). The Metal kernels equal their CPU reference **bit for
   bit** on all five files. X-Trans has only a bilinear kernel here: fast
   (14 to 17 ms) but with about twice LibRaw's false color.
3. **Owning the decode removes #89's obstacle.** The hybrid through Adobe
   Standard's matrices reaches #89's option (c): median ΔE 0.88 (GX85), 0.62
   (5D II), 0.86 (E-M5 III) against (c)'s 0.91, 0.57, 0.78; with lensfun's
   correction the GX85 goes to 0.81. White balance becomes a color step on a
   kept image: **7 to 9 ms a frame, against 99 to 173 ms** for the system
   decoder, which decodes again; and Kelvin means Adobe's Kelvin (as shot
   4688 K against Lightroom's 4700 K; the system decoder says 5388 K).
4. **lensfun's data correct the GX85 within 3 px of the camera's own
   correction, but only once its radius is measured.** Applied as the
   published PTLens convention says (radius 1 at half the shorter side) the
   12-32 mm's distortion is over-corrected about twice (median 17 px off,
   corner +34 px); with the radius scaled by 0.68 to 0.70, median 0.7 to 0.9
   px, max 3.3 px. Lateral color: better than both references (red +0.08,
   blue +0.03 px). Distortion, lateral color and vignetting run in one
   resampling pass of 1.0 to 1.7 ms (bilinear) or 3.3 to 5.8 ms (bicubic),
   a separate pass after the demosaic: merging it into the demosaic is 7
   times slower. Vignetting could not be checked against any reference.
5. **Budget at 24 MP:** a preview from a raw in 0.3 to 0.6 s, all but 20 to
   30 ms of it LibRaw's unpack; a slider frame 7 to 9 ms from the kept full
   demosaic, 1.3 to 2.2 ms from a kept preview-size one. The system decoder
   is faster than our whole pipeline for the Bayer files it reads (5D II
   preview 124 ms against 293 ms) because our unpack alone is slower.
6. **Recommendation:** build LibRaw at `-O3` now; then our GPU demosaic for
   the raws LibRaw decodes (X-Trans first, which needs a better kernel than
   bilinear); then an opt-in own decode for Bayer cameras, which is what #89
   (profiles) needs; lensfun corrections after the owner settles licensing
   and the radius question. Don't replace the system decoder for the cameras
   it reads well: we'd lose its noise reduction, machine learning denoise,
   per-camera exposure and its speed.

## Inputs

| File | Camera (EXIF) | Lens | Size (LibRaw's visible area) | Mosaic |
|---|---|---|---|---|
| `GX85.RW2` (owner's samples folder) | Panasonic DMC-GX7MK2 (the GX85), ISO 200 | Lumix G Vario 12-32 mm at 12 mm, f/4 | 4608 x 3464, 16.0 MP | Bayer BG/GR |
| `EM5MarkIII.ORF` | Olympus E-M5 Mark III, ISO 200 | adapted Canon FD 300 mm f/4 L (manual, entered in camera) | 5240 x 3912, 20.5 MP | Bayer RG/GB |
| `Canon5DMkII.CR2` | Canon EOS 5D Mark II, ISO 200 | unrecorded manual 50 mm | 5634 x 3752, 21.1 MP | Bayer GB/RG |
| `DSCF5123.RAF` (#161's QA sample) | Fujifilm X-E3, compressed | XF35mmF2 R WR | 6032 x 4028, 24.3 MP | X-Trans |
| `DSCF4583.RAF` (#161's QA sample) | Fujifilm X-T3 | XF23mmF1.4 R | 6246 x 4170, 26.0 MP | X-Trans |

The X-E3 is one the system decoder gives no image for (#161); the X-T3 it
reads. Lightroom's exports (16-bit sRGB TIFF, Adobe Standard, lens profile
off, the GX85's own distortion and lateral color correction applied) are the
external reference. No sample was copied.

## Question 1: where a LibRaw decode's time goes

**Method.** `photobench decodespike --mode stages`: the decode exactly as
`LibRawDecoder.decode` sets it up (linear 16-bit camera RGB, our
multipliers, highlight mode 1, file white level), timed between LibRaw's own
progress events (scale_colors, pre_interpolate and convert_to_rgb report a
start and an end; the demosaic is what lies between pre_interpolate's end and
convert_to_rgb's start), then `libraw_dcraw_make_mem_image` and our RGBA
repack. Five runs each.

**How LibRaw is built.** `Package.swift` builds it with SwiftPM's defaults:
**`-Os` in release** (`-O0` in debug), no `-ffast-math`, thread-safe
(`LIBRAW_NOTHREADS` not defined). **No OpenMP**: Apple's clang ships no
`libomp`, `Package.swift` passes no `-fopenmp`, and LibRaw's own header
undefines `LIBRAW_USE_OPENMP` on Apple builds with `_REENTRANT`. LibRaw has
OpenMP loops in its AHD and X-Trans demosaics, the Fujifilm compressed and
CR3 decoders, raw2image and some post-processing; none run in parallel here.

Median ms (min–max within 1 to 2% everywhere; full tables in the run logs):

| File | Size | Unpack | raw2image + black | Demosaic | convert_to_rgb | make_mem_image + repack | **Total** |
|---|---|---|---|---|---|---|---|
| GX85 half | 2304 x 1732 | 62 | 47 | 2 | 4 | 9 | **126** |
| GX85 full | 16.0 MP | 63 | 93 | **640** | 16 | 71 | **893** |
| E-M5 III half | | 256 | 31 | 3 | 5 | 5 | **302** |
| E-M5 III full | 20.5 MP | 256 | 32 | **835** | 21 | 21 | **1173** |
| 5D II half | | 241 | 32 | 3 | 5 | 5 | **287** |
| 5D II full | 21.1 MP | 241 | 32 | **826** | 21 | 21 | **1153** |
| X-E3 half | | 507 | 43 | 0 | 7 | 6 | **566** |
| X-E3 full | 24.3 MP | 511 | 43 | **8074** | 27 | 31 | **8697** |
| X-T3 half | | 540 | 46 | 0 | 6 | 6 | **602** |
| X-T3 full | 26.0 MP | 544 | 47 | **8745** | 26 | 27 | **9396** |

(The GX85's make_mem_image is 68 ms against 17 to 20 for the others: its
frame is turned, and the turn is a cache-unfriendly copy.)

**LibRaw's other demosaics** (full size, median of 3, demosaic ms / total):

| | bilinear | VNG | PPG | AHD (default) | DCB | DHT | AAHD |
|---|---|---|---|---|---|---|---|
| GX85 | 74 / 330 | 986 / 1239 | 69 / 322 | 657 / 912 | 481 / 736 | 1059 / 1313 | 1607 / 1859 |
| X-E3 | 109 / 742 | 1428 / 2053 | one pass 3979 / 4621 | three passes 8322 / 8951 | (falls back to three passes) | (same) | (same) |

**Build setting.** The same decodes from a `photobench` built with LibRaw at
`-O3` (`-Xcxx -O3 -Xcc -O3` in a scratch build folder; nothing in the
repository changed), median of 3, back to back with the `-Os` build:

| | Demosaic `-Os` → `-O3` | Total `-Os` → `-O3` |
|---|---|---|
| GX85 | 638 → **216** | 891 → **404** |
| 5D II | 828 → **286** | 1159 → **604** |
| X-E3 | 7981 → 7169 | 8600 → 7788 |

The unpack did not move (62 → 56, 239 → 235, 508 → 510). Whether the
output is byte for byte the same at `-O3` was not checked (no fast-math is
involved, so it should be; the LibRaw tests and goldens would say).

**Bands (#177).** `--mode bands`: N horizontal bands of the visible area
(24 rows of overlap each side, starting on the pattern), each its own LibRaw
instance with a crop box, all at once; each band unpacks the whole file
again (LibRaw's API decodes no part of a file). Wall time, median of 2:

| Bands | 1 | 2 | 4 | 6 | 8 | 10 | 14 |
|---|---|---|---|---|---|---|---|
| X-E3 (ms) | 9033 | 5004 | 2911 | 2194 | **1848** (4.9x) | failed | failed |
| 5D II (ms) | 1171 | 743 | 525 | 451 | **420** (2.8x) | 424 | 512 |

With 10 or more bands, X-E3 bands of 450 rows or fewer failed with
`LIBRAW_IO_ERROR` (−100009) in `dcraw_process`; not investigated (#177
should know: there is a smallest band). Whole decodes of one file at once
(throughput, not latency): X-E3 1, 2, 4, 8, 10 at once took 9.4, 9.6, 9.6,
9.9, 10.6 s wall (1.06 s per decode at 10); 5D II 1.17 to 1.42 s (0.14 s per
decode at 10). Memory bandwidth does not limit LibRaw at 10 at once.

## Question 2: the hybrid (LibRaw unpack, our Metal demosaic, our color step)

**What it does.** `RawMosaic`: `libraw_open_file` and `libraw_unpack` only;
the visible area of `raw_image` copied out, the pattern from `libraw_COLOR`
(the second green folded into green), black per pattern site (LibRaw's
common black, each color's own and its repeating pattern, as LibRaw adds
them), the white span (`maximum` less the common black, which is exactly
what LibRaw's own processing arrives at: GX85 4095 − 143 = 3952, 5D II
15600 − 1023 = 14577, printed by LibRaw after `dcraw_process`) and the same
multipliers `LibRawDecoder` gives LibRaw. On the GPU (`MetalDemosaic.swift`):
a normalize pass ((value − black) / span, clipped, times the multiplier, to a
`r32Float` texture) and the demosaic into `rgba16Float`: camera RGB in the
same scale as `LibRawDecoder`'s output, so `CameraColorStep` takes it
unchanged. Kernels, each from its published description:

- **bilinear**: each missing color the mean of that color's sites in the 3x3
  (5x5 if none); for X-Trans the simplest usable demosaic;
- **mhc**: Malvar, He and Cutler (ICASSP 2004), the paper's four 5x5 filters;
- **ha**: Hamilton–Adams directional green estimates (US 5,629,734), blended
  by inverse squared gradients (after Pekkucuksen and Altunbasak's GBTF,
  simplified) instead of a hard choice; red and blue by bilinear color
  differences (Gunturk et al. 2005). Two passes.

**Check against a CPU reference** (`--mode verify`; CLAUDE.md, "Checking
image code"). `DemosaicReference.swift` is the same arithmetic in plain
Swift `Float`, in the same order; the Metal library is compiled in the safe
math mode with `#pragma clang fp contract(off)`. The bound was derived, not
tuned (`DemosaicVerify.swift`): +, −, × correctly rounded on both, division
up to 2.5 ULP on the GPU (the Metal Shading Language specification), so 3
ULP for bilinear, 1 for MHC, and for HA the blend's sensitivity to its
weights' error. **Result: on a 768 x 768 crop of each of the five files,
every one of 1,769,472 values per kernel was identical**, GPU and CPU (11
kernel-file pairs, 0 over the bound).

**A finding for the project's references:** the pipeline's half-float
output, checked against the Float32 GPU output, **did not meet the 2⁻¹¹
bound of round-to-nearest**: Metal's writes to an `rgba16Float` texture
round toward zero (of the inexact values in a 256 x 256 test, every one
landed below, none above; about half differ from round-to-nearest-even). One
conversion is then off by less than one half-float ULP, **2⁻¹⁰ relative**,
and all values were within that (largest 0.98 to 1.00 of it). Any CPU
reference of a Metal kernel that writes half floats needs 2⁻¹⁰ per write,
not CLAUDE.md's 2⁻¹¹ (Core Image's own conversions were not tested here).

**Cross-check of levels against LibRaw.** Our bilinear on Bayer does what
LibRaw's bilinear does (`user_qual` 0): every third pixel of the whole
frame differs by a median of 0.99/65535 (LibRaw rounds to 16-bit integers
between its steps), 99.9th percentile 7 (E-M5, 5D II) to 15 (GX85); the
rare large differences are LibRaw's own pre-processing (it replaces zero
pixels of Panasonic files, `zero_is_bad`) and clipped highlights. On a
synthetic mosaic (below) the two give identical scores to the second
decimal.

### Speed

`--mode timing`, 6 runs (first, then median of 5 with min–max). "Ours" is
the whole path: open and unpack, copy, upload, GPU passes, the color step
and a render, either a 2560 px preview (Lanczos, 8-bit sRGB) or full size
(half float). Each GPU pass is its own command buffer with a wait, so the
GPU figures are upper bounds.

| File | Ours, ha → full | of which unpack | GPU (normalize + demosaic) | Ours, binned → preview | LibRaw decode (app's fallback) → preview / full | System decoder → preview / full |
|---|---|---|---|---|---|---|
| GX85 16.0 MP | **92** (88–97) | 63 | 12.4 (1.4 + 4.0 + 6.2) | 75 | 911 / 900 | 102 / 121 |
| E-M5 III 20.5 MP | **304** (303–321) | 265 | 13.7 | 287 | 317 / 1214 | 287 / 317 |
| 5D II 21.1 MP | **294** (289–324) | 250 | 14.9 | 272 | 302 / 1205 | 124 / 164 |
| X-E3 24.3 MP | **582** (566–661), bilinear | 525 | 16.8 | 540 (3x3 bins) | 605 / **9772** | no image |
| X-T3 26.0 MP | **609** (601–629), bilinear | 550 | 16.0 | 566 (3x3 bins) | 645 / **9784** | 186 / 532 (253–734) |

Kernel by kernel (GPU ms at 16 MP / 20 to 21 MP / 24 to 26 MP): normalize
1.4 to 2.6 / 1.8 to 2.0 / 2.1 to 2.4; bilinear 8.5 to 9.2 / 9.0 to 12.0 /
13.4 to 14.7 (the generic 3x3 kernel with dynamic indexing; a Bayer-only one
would be faster); MHC 4.1 / 5.3 to 5.6; HA 6.8 to 10.2 / 8.2 to 13.0 (two
passes); 2x2 or 3x3 bins 1.8 / 2.4 to 2.9 / 3.4 to 3.6. The Metal library and
its six pipelines compile in 2 ms, once per process. First runs were within
15% of later ones except the E-M5 III's very first (564 ms against 303), the
first decode of that file in the process. The 3x3 bins of an X-Trans frame
are 2010 to 2082 px wide, under the 2560 px preview.

### Quality

**Against a known truth** (`--mode quality`). Each Bayer raw binned 2x2 on
the GPU (each color from its own sites, nothing interpolated) is a
full-color picture of real detail (and real noise); it is quantized to 16
bits, sampled through an RGGB mosaic, written as a DNG (black 0, white
65535, camera = linear sRGB), and demosaiced by ours, by LibRaw's seven
demosaics and by the system decoder (flat look, its noise reduction at 0, a
gain fitted). CPSNR over the sRGB-encoded values; ΔE76 per pixel in Lab of
linear sRGB; edges are the truth's top 10% of L* gradient; an 8 px border
left out. The noise the truth carries (each of its pixels has its own) sets
a floor no demosaic can go under, so compare columns, not absolute values.

| Truth from | Ours bilinear | Ours MHC | **Ours HA** | LibRaw AHD (default) | LibRaw VNG | LibRaw DHT | LibRaw AAHD | System decoder |
|---|---|---|---|---|---|---|---|---|
| GX85 (2304 x 1732), CPSNR dB | 32.07 | 32.33 | **33.84** | 33.23 | 34.00 | 33.95 | 33.73 | 29.14 |
| GX85, edge chroma error p95 | 20.38 | 19.33 | **16.72** | 17.93 | 16.70 | 17.66 | 16.92 | 18.37 |
| 5D II (2816 x 1876), CPSNR dB | 40.16 | 40.29 | **41.96** | 41.96 | 41.65 | 42.11 | 42.16 | 31.37 |
| 5D II, edge chroma error p95 | 10.58 | 9.44 | **8.27** | 8.34 | 8.75 | 8.38 | 8.04 | 9.58 |
| E-M5 III (smooth subject), CPSNR dB | 48.24 | 47.21 | 47.99 | 47.92 | 48.02 | 47.84 | 47.63 | 31.65 |

LibRaw's PPG and DCB sit between (GX85 33.24 and 32.96; 5D II 41.97 and
41.92). LibRaw's time on these 4 to 5 MP truths: AHD 190 to 253 ms, AAHD
446 to 579 ms; ours HA under 5 ms. The system decoder's low numbers are not
its demosaic: it sharpens and processes even at noise reduction 0 (flat
areas are 2 to 4 ΔE off where every demosaic is under 2.5), so it is not
comparable on this test.

**On the real mosaics** (`--mode real`), the middle 2048 x 2048 of the
frame, through the built-in color step and look. Ours against LibRaw's own
default (both in the same camera RGB):

| File | 16 px blocks ΔE median / p95 (HA) | Edge pixels ΔE median / p95: bilinear, MHC, **HA** |
|---|---|---|
| GX85 | 0.54 / 1.88 | 15.0 / 48.6, 8.2 / 28.7, **4.7 / 19.7** |
| E-M5 III | 0.10 / 0.24 | 1.4 / 4.1, 1.0 / 2.9, **0.6 / 2.4** |
| 5D II | 0.27 / 0.92 | 6.6 / 24.8, 3.4 / 13.3, **1.2 / 8.5** |
| X-E3 (bilinear vs LibRaw's three passes) | 0.20 / 0.77 | 4.6 / 20.9 |
| X-T3 (same) | 0.58 / 1.41 | 8.2 / 23.8 |

At block scale the demosaics agree (colors and levels are the same); at
edges HA is closest to AHD. A no-reference measure of false color (the
high-pass of a* and b* at edge pixels, mean; with the high-pass of L*,
"detail", since blur lowers false color too), each picture on its own edges:

| | LibRaw default | Ours bilinear | Ours MHC | **Ours HA** | System decoder | Lightroom (sharpening 40, color NR 25) |
|---|---|---|---|---|---|---|
| GX85 false color (detail) | 11.31 (7.56) | 19.30 (6.33) | 13.66 (7.97) | **10.06 (7.69)** | 5.41 (8.79) | 4.54 (10.55) |
| 5D II | 4.67 (5.02) | 9.55 (3.81) | 5.63 (5.20) | **4.40 (4.99)** | 3.91 (8.20) | 3.17 (8.18) |
| E-M5 III | 1.73 (0.91) | 2.42 (0.76) | 1.79 (0.93) | **1.53 (0.90)** | 1.23 (1.00) | 0.68 (1.48) |
| X-E3 | 4.09 (2.54), 3 passes | 7.44 (2.32) | | | no image | |
| X-T3 | 8.14 (2.95), 3 passes | 11.05 (2.38) | | | 1.11 (1.38) | |

HA has a little less false color than LibRaw's AHD at the same detail. The
system decoder and Lightroom have much less: they apply color noise
reduction (Lightroom's 25 is on in the exports), which neither LibRaw nor we
do. That is a stage the hybrid would need, not a demosaic difference.

### X-Trans

What it needs: the 6x6 pattern (LibRaw gives it, `idata.xtrans`; 20 of 36
sites green, every row and column has all three colors, no 2x2 structure), so
none of the Bayer kernels apply. Families: generic interpolation over the
pattern (bilinear, as here; VNG, LibRaw's `user_qual` 1, 1.4 s); directional
homogeneity in the manner of AHD, which is what LibRaw's one- and three-pass
X-Trans demosaics are (4.0 s and 8.3 s here); frequency-domain chroma
separation (the X-Trans pattern's chroma sits at known spatial frequencies);
learned demosaics. Measured here: our bilinear X-Trans kernel takes 13 to 15
ms at 24 to 26 MP, matches LibRaw's three passes at block scale (0.20 and
0.58 ΔE) and has 1.4 to 1.8 times its false color. A directional X-Trans
kernel (four directions, a homogeneity choice) is the next step; on the GPU
its cost should stay in tens of milliseconds, not seconds (an estimate, not
measured).

## Question 3: white balance and color with our own decode

**The #89 obstacle** (the system decoder's linear colors are not Adobe's
for the GX85 and E-M5, and it offers no camera-RGB stage to fix them) is
gone with our own decode: we have camera RGB. `--mode color` repeats the
#89 spike's option (c) (the same code: its `.dcp` reader, table math,
alignment and gain fit, copied into this spike) with our demosaic in place
of LibRaw's: Adobe Standard's matrices and hue/sat map, its look table, the
`BaselineLook` curve hue-preserving, gain fitted; ΔE76 of 16 px blocks at
320 px against Lightroom's Adobe Standard export.

| Camera | #89 (c), LibRaw AHD | Hybrid bilinear | Hybrid MHC | **Hybrid HA** | Hybrid HA + lensfun |
|---|---|---|---|---|---|
| GX85 | 0.91 / 2.39 | 0.93 / 2.40 | 0.90 / 2.38 | **0.88 / 2.29** | **0.81 / 2.07** |
| 5D II | 0.57 / 1.40 | 0.65 / 1.79 | 0.65 / 1.79 | **0.62 / 1.80** | (no lens data) |
| E-M5 III | 0.78 / 2.80 | 0.85 / 2.87 | 0.86 / 2.87 | **0.86 / 2.87** | (no lens data) |

The (c) column reproduces #89's numbers exactly. The hybrid is within 0.1
of it; the small loss on the 5D II and E-M5 is the frame (the hybrid keeps
LibRaw's visible area, the alignment needed a 1% scale and a 4 px shift for
the E-M5), not color. With lensfun's 12-32 mm correction (Question 4) the
GX85 lines up with Lightroom's frame without the radial term #89 needed
(NCC 0.979 against 0.959) and gets closer than (c).

**White balance.** As-shot Kelvin and tint each decoder reports, against
Lightroom's:

| Camera | Lightroom | Ours, LibRaw's matrix (built-in) | Ours, Adobe Standard's matrices | System decoder |
|---|---|---|---|---|
| GX85 | 4700 K, +12 | 4698 K, +2.5 | 4688 K, +11.8 | 5388 K, +8.6 |
| 5D II | 5350 K, +10 | 5077 K, +5.9 | 5122 K, +7.1 | 5562 K, +15.3 |
| E-M5 III | 5400 K, +15 | 5698 K, +16.2 | 5714 K, +20.6 | 5560 K, +4.9 |

With Adobe's matrices our numbers are Lightroom's (GX85 within 12 K and 0.2
tint; the others 4% and 6%, as #89 found). The **same Kelvin number renders
differently** in the two decoders: system decoder at 2800, 4000, 5500, 7500
K against ours at the same values (built-in look, blocks of 16 at 320, gain
fitted): ΔE median GX85 2.9, 5.0, 5.1, 5.3; 5D II 6.9, 4.7, 6.5, 7.6; E-M5
III 5.3, 7.0, 8.7, 8.6. Ours is warmer than the system decoder's at the same
number on the GX85 and 5D II (b* +3 to +8 higher from 4000 K up) and cooler
on the E-M5 (b* −6 at 5500 K). A Kelvin copied between photos of the two
decoders does not mean the same light today; with one decoder it would.

**What we gain, concretely:**

- **Profiles** (#89): (c)'s accuracy, at the hybrid's speed.
- **White balance on a kept image**: a change re-runs the color step only.
  Measured live frames at 2560 px (`--mode budget`, 20 frames): ours 7.0 to
  8.9 ms from the kept full-size demosaic, **1.3 to 2.2 ms** from a kept
  preview-size one; the app's `LiveRenderSession` today: **99 to 107 ms**
  (GX85, 5D II) and **173 ms** (X-T3) per white balance frame, because the
  system decoder decodes again; 10 ms for the X-E3 (LibRaw path: already a
  color step). Exposure frames are alike (app 9 to 11 ms, ours 7 to 9).
- **Free Kelvin and tint at decode, on camera RGB**: the color step already
  takes any Kelvin from 2000 to 50000 and tint ±150 (#170); nothing new is
  needed for that, only the camera RGB, which the hybrid gives for every
  camera LibRaw reads.
- **Adobe's Kelvin scale** where we use Adobe-style matrices.

## Question 4: lensfun's corrections, our reader and kernel

**The database** (shallow clone of https://github.com/lensfun/lensfun at
`52cf1a7`, 2026-11-04, in the session's scratch folder, nothing committed):
56 XML files, 5.1 MB, 1059 cameras and 1580 lenses; 1538 lenses with
distortion, 1021 with lateral color (TCA), 717 with vignetting. Models used:
distortion ptlens (5606 entries), poly3 (889), poly5 (5); TCA poly3 (3811),
linear (5); vignetting pa (29817); no `acm` (Adobe) entries (the manual:
the official database accepts none). Our reader (`LensfunData.swift`,
Foundation's `XMLParser`, from the manual's format description) reads all of
it in 141 to 156 ms.

**Matching the three cameras** (our own rules; lensfun's matcher was not
looked at):

| File | Camera in lensfun | Lens in lensfun |
|---|---|---|
| GX85 | **No**: the file says "DMC-GX7MK2"; lensfun has DMC-GX80 and DMC-GX85 (the same camera) but not that name. Crop factor taken from the file's 35 mm equivalent (24 / 12 = 2.0) | LibRaw gives **no lens name** for this RW2 (EXIF and maker-note fields empty); ImageIO has it: "LUMIX G VARIO 12-32/F3.5-5.6" → **Panasonic "Lumix G Vario 12-32mm f/3.5-5.6 Asph. Mega OIS"** (`mil-panasonic.xml`): distortion at 4 focal lengths (ptlens, measured on a GM1), TCA at 4 (poly3), vignetting 50 entries (pa, measured on a GX80), crop factor 2, aspect 4:3 |
| E-M5 III | Yes (Olympus E-M5MarkIII) | "CANON FD 300mm 1:4 L" (typed into the camera): **none**. lensfun has no FD 300 mm f/4 L. A first, naive matcher picked "Canon EF 300mm f/4L IS USM" (same focal length and f-number): wrong mount, wrong lens. Requiring every word of the camera's lens string fixed it |
| 5D II | Yes, after taking the maker into the model (LibRaw: "EOS 5D Mark II"; lensfun: "Canon EOS 5D Mark II") | **None**: no lens recorded (a manual 50 mm, f-number 0) |

At 12 mm f/4 the GX85's numbers are: ptlens a 0.02222, b −0.06354, c
−0.05077; TCA red v 1.0002074, b −0.0000213, blue v 1.0002135, b −0.0000183;
vignetting k1 −0.597, k2 0.231, k3 −0.306 (between f/3.5 and f/4.5,
interpolated linearly in f-number: the manual says the library interpolates,
not how).

**The kernel** (`LensSpike.swift`, a Metal compute pass on the demosaiced
image): each output pixel finds where its green came from through the
distortion model (undistorted to distorted radius, as the manual's "How the
corrections work" orders it), then its red and blue through the TCA model
from there, reads each channel at its own place, and divides it by the
vignetting gain at that place (devignetting first, on the pristine image).
One resampling pass, three samples a pixel. GPU ms, median of 5:

| | 16.0 MP | 20.5 MP | 24.3 MP | 26.0 MP |
|---|---|---|---|---|
| Bilinear (the GPU's sampler) | **1.01** | 1.34 | 1.56 | 1.67 |
| Bicubic (Catmull-Rom, 16 reads a channel) | **3.34** | 5.02 | 5.62 | 5.82 |
| Bilinear demosaic **fused** with the correction | 22.2 | 28.2 | 34.6 | 37.1 |
| The same as separate passes (normalize, demosaic, correction) | 3.3 | 4.3 | 5.1 | 5.5 |

**Merging it into the demosaic does not pay**: each corrected pixel needs
the demosaiced value at 4 (bilinear) or 16 (bicubic) source pixels per
channel, so a fused pass demosaics each source pixel up to 12 times; for
the two-pass HA it would also have to recompute the green pass. A second
pass costs 1 to 6 ms; the bicubic's 4 ms extra over bilinear buys sharper
corners (not measured).

**Accuracy against the camera's own correction** (`--mode lens --sweep`).
Lightroom's export and the system decoder both apply the GX85's RW2
distortion data; they agree with each other to median 0.19, p95 0.52, max
0.80 px. Our render of each variant is matched to them by 64 px patches
(910 on a 128 px grid; NCC of luminance, coarse to fine, sub-pixel by a
parabola), each variant first zoomed to the reference's scale; the residual
is what remains after the best scale and shift. Pixels at full size:

| Variant (against Lightroom) | Median | p95 | Max | Radial residual by radius (0 center … 1 corner) |
|---|---|---|---|---|
| No correction | 16.5 | 38.6 | 91.6 | +13, +20, +12, −17, **−70** |
| lensfun, radius 1 = half the shorter side (the PTLens convention as published) | 17.2 | 30.9 | 52.2 | −15, −23, −15, +7, **+34** |
| lensfun, radius 1 = half the diagonal | 4.1 | 9.3 | 19.7 | +1, +4, +5, −1, −10 |
| **lensfun, radius × 0.68** | **0.89** | **2.1** | **2.9** | −2.1, −0.9, +1.0, +0.3, −1.6 |
| **lensfun, radius × 0.70** | **0.68** | **3.0** | **3.3** | −3.0, −2.2, 0.0, +0.7, +0.6 |
| System decoder (its own correction) | 0.19 | 0.52 | 0.80 | within ±0.25 |

Against the system decoder the figures are the same within 0.3 px. So
**lensfun's 12-32 mm data reproduce Panasonic's own correction to within 3
px over the whole 16 MP frame (0.07% of its width), with the radius
normalized by about 1.45 times half the shorter side**, and they
over-correct about twice under the published PTLens convention. Neither
documented convention (half the shorter side, half the diagonal) is right.
The lensfun documentation we read does not state the normalization or how
the calibration's crop factor and aspect ratio enter it (the manual says
only that the library "needs the aspect ratio internally for correct
application of the distortion parameters"). A third party's issue tracker
(RapidRAW #1688, unverified) says lensfun rescales the coefficients by the
calibration's aspect ratio and crop factor before use; that would explain a
factor like ours, but we did not verify it and did not read lensfun's
coordinate code (see Questions for the owner). One lens cannot separate a
convention from a calibration difference.

**Lateral color** (red and blue against green, patches beyond 0.6 of the
half diagonal, median radial shift, px, outward positive): no correction
red +0.38, blue +0.85; **lensfun TCA red +0.08, blue +0.03**; Lightroom
−0.03, −0.24; system decoder +0.16, +0.19. lensfun's TCA is better than both
references here (the TCA's linear terms do not depend on the radius
question).

**Vignetting**: no reference. Lightroom's export has none (lens profile
off; the camera's shading compensation was off). The system decoder's
linear render over ours uncorrected, by ring from the center (center = 1):
1.00, 0.99, 1.00, 1.01, 1.01, 1.02, 1.03, 0.99, 1.18, 1.22: it does not
correct this lens's vignetting (the last two rings are unreliable: the
frames differ there by the distortion correction). lensfun's 1/V at f/4
with radius 1 at the corner: 1.00, 1.01, 1.04, 1.08, 1.13, 1.20, 1.31,
1.47, 1.74, 2.36 (+1.24 EV in the corner); with radius 1 at half the shorter
side the polynomial goes negative beyond 0.7 of the frame, which no lens
does, so vignetting's radius is 1 at the corner (consistent with the same
third-party note). Whether the amount is right needs a flat-field shot.

**Resampling** is one bilinear or bicubic read per channel from the
`rgba16Float` demosaic; its cost is in the table. It belongs before the
color step (lensfun's models are for linear sensor data; the manual warns
against correcting gamma-encoded data). It could share its pass with the
crop and rotate resampling the renderer already does, so that a corrected
and cropped render resamples once (not tried).

## Question 5: budget for a whole pipeline at 24 MP

From the tables above, at 21 to 26 MP on this Mac (ms):

| Step | Cold (first in process) | Warm |
|---|---|---|
| LibRaw open + unpack (CPU, one thread) | 250 (CR2, ORF) to 525–550 (compressed RAF); 63 for the 16 MP RW2 | same: it is per file |
| Copy and upload | 4–6 | 4–6 |
| Normalize + demosaic (GPU) | 14–17 | 14–17 |
| Lens correction (GPU) | 1.6 bilinear, 5.6 bicubic | same |
| Color step + render to 2560 px | 8–15 | 8–10 |
| **To a preview** | **290–310 at 20 to 21 MP (Bayer; 91 for the 16 MP RW2), 560–600 (X-Trans)** | the same for another photo |
| **Slider frame with the demosaic kept** | — | **7–9** (full size kept), **1.3–2.2** (preview size kept) |

Today, for comparison: the system decoder to a preview 102 to 287 ms
(first runs 106 to 345), full size 121 to 317 ms (X-T3 253 to 734); LibRaw's
fallback 0.6 s to a preview and 9.8 s full size for an X-E3; the app's live
session, first frame 195 to 242 ms (721 for the X-E3), exposure 9 to 11 ms,
white balance 99 to 173 ms. Memory: a kept full-size demosaic in half float
is 8 bytes a pixel (194 MB at 24 MP), plus the normalized mosaic (4 bytes a
pixel) while demosaicing; a kept preview-size one is 35 MB at 2560 x 1707
(not measured in the app).

**Where the floor is:** LibRaw's single-threaded unpack. Our GPU work is 25
to 40 ms of a 300 to 600 ms preview. For the Bayer files the system decoder
reads it is faster than our unpack alone (5D II: 124 ms to a preview against
our 250 ms unpack). Beating it needs parallel decompression: LibRaw with
OpenMP (its Fujifilm and CR3 decoders have OpenMP loops; needs `libomp`, a
new dependency), our own band-parallel decompressors per format (Fujifilm's
compressed RAF is coded in independent strips, which the X-Trans band test's
re-unpack does not exploit), or both.

## Recommendation

**What to build, in order.**

1. **LibRaw at `-O3`** (`cxxSettings` of `CLibRaw` in `Package.swift`): Bayer
   fallback decodes about twice as fast, X-Trans 10%, at no other cost.
   Check the output is unchanged first. Small; independent of the rest.
2. **#177 with numbers**: bands bring an X-E3 full decode from 9.0 to 1.85 s
   (8 bands); find the smallest band that decodes (450 rows failed). Worth
   doing only if item 3 is not.
3. **Our GPU demosaic for raws LibRaw decodes**, X-Trans first (the X-E3
   class #161 added): LibRaw unpacks, our kernel demosaics, the existing
   color step follows. Full size from 9.8 s to about 0.6 s, a preview a
   little faster than today. Needs a directional X-Trans kernel (bilinear
   has 1.4 to 1.8 times LibRaw's false color) and a color noise reduction
   step (Question 2's table: the system decoder and Lightroom have one).
   This replaces #177.
4. **An own decode for Bayer cameras, opt-in per photo or camera**, which is
   what #89's profiles need (option (c), now at the hybrid's speed and
   accuracy), with the HA kernel. The Kelvin scale and live white balance
   come with it.
5. **lensfun corrections** for photos we decode, after the owner settles the
   data licensing and the radius (below): a 1 to 6 ms pass. For Micro Four
   Thirds raws, reading the camera's own distortion data from the RW2 and
   ORF (as #161 did for Fujifilm) may be the safer first source: it is what
   Lightroom and the system decoder apply.

**What replacing the system decoder would lose** (for cameras it reads):
its noise reduction (luminance and color, tuned per camera and ISO) and
macOS 27's machine learning denoise (`ml-denoise`, PR #39); its per-camera baseline
exposure and tuning (#170 measured 0.07 to 0.52 EV between makers; #89
Finding 8 found 1.3 EV for a 5D II), highlight handling and sharpening; the
embedded lens corrections of Micro Four Thirds files (unless we read them);
new cameras arriving with macOS updates (LibRaw updates instead, by us); and
its speed on the files it reads (it is ahead of our unpack). Don't replace it
wholesale; use our decode where it gives something: raws it can't read,
profiles, Adobe-scale white balance, live white balance.

**lensfun data licensing** (for the owner; not a decision, and not legal
advice). The clone's `README.md` says: "The lens database is licensed under
the Creative Commons Attribution-Share Alike 3.0 license (CC BY-SA 3.0). The
database is located under the data/ subdirectory of the source package and
a copy of the license is available in the file data/COPYING.CC_BY-SA_3.0";
that file is the "Creative Commons Legal Code, Attribution-ShareAlike 3.0
Unported" text. The same README puts the libraries and the documentation
(where the model formulas are) under the LGPL 3, the applications under the
GPL 3, and tests and tools in the public domain unless a file says
otherwise. The database files carry no header of their own. The manual says
the database grew from PTLens's with that author's permission. What shipping
data in the app would mean under CC BY-SA 3.0 Unported, as we read it:
attribution to the lensfun project with the license or its URI (an About
and `THIRD_PARTY_NOTICES.md` entry, which `AcknowledgementConsistencyTests`
would then check); share-alike for any **adaptation** of the data (a
converted, filtered or corrected copy, which our own format would likely
be) under BY-SA 3.0 or a compatible license; no technical measures that
restrict recipients (no encrypting it); and a collection that includes the
data unchanged beside our code is not an adaptation, so the app's code
license is not affected. Version 3.0 Unported does not address database
rights as 4.0 does. Alternatives: download it on request like ExifTool is
optional today, or let the user point to a lensfun installation.

**LightCraft** (https://github.com/storytold/lightcraft, README only; every
figure is the README's claim, none verified): its own raw decoders in pure
Rust with no C dependencies (Olympus compressed ORF not decoded; embedded
previews for some CR3 and NEF variants); the develop pipeline as wgpu
compute kernels on Metal, Vulkan or DX12, "checked against the CPU pipeline
to within 1/255"; linear Rec.2020 float, Bradford white balance, gamut
mapping, a filmic shoulder; lens corrections from DNG and embedded maker data
(no lensfun mentioned). Claimed on a 24 MP raw on an M4 Pro: "a slider update
re-renders in ~4 ms, a cold 2.5 MP loupe in ~30 ms, and a full-size export
in ~0.3 s including a parallel JPEG encode"; "Opening a raw shows its
embedded camera preview or cached render within ~0.1 s while the full
render follows (~0.2–0.5 s for 24 MP)"; "stepping through a shoot takes ~50
ms per photo". Against ours on the same chip: our slider frames (1.3 to 9
ms) are in that range; a 0.2 to 0.5 s full render matches our hybrid only
where the unpack is fast (the GX85's 92 ms full; 300 to 600 ms elsewhere,
mostly LibRaw's unpack), so their claim implies decompressors faster than
LibRaw's single thread, which is the part we would have to write.

**Proposed breakdown into issues** (for the main session to file; titles,
labels and bodies under Proposed issues).

## Surprises

1. **SwiftPM builds LibRaw at `-Os`**, and `-O3` makes AHD 3 times as fast.
2. **Metal's half-float texture writes round toward zero**: a reference of
   a Metal kernel needs 2⁻¹⁰ per half write, not 2⁻¹¹.
3. **The system decoder beats LibRaw's unpack alone** on CR2, ORF and RW2:
   Apple's decompression is faster than LibRaw's, so our pipeline's speed
   ceiling for Bayer is decompression, not demosaic.
4. **lensfun's published convention over-corrects the GX85's lens about
   twice**; the measured normalization is about 1.45 times half the shorter
   side.
5. **Names**: the GX85 files say "DMC-GX7MK2", absent from lensfun (as from
   Adobe's profiles in #89); LibRaw gives no lens name for this RW2 (ImageIO
   does); a naive lens match picked an EF lens for an FD lens.
6. **X-Trans bands of 450 rows or fewer fail** in LibRaw (I/O error).
7. LibRaw ignores DCB, DHT and AAHD requests for X-Trans (three passes
   instead) and its one-pass X-Trans takes 4.0 s, half of three passes.
8. The system decoder's X-T3 full-size render varied from 253 to 734 ms run
   to run; every other figure varied by a few percent.

## Questions for the owner

1. **What to build first** from the Recommendation (1 and 2 are small; 3 is
   the one that changes the X-E3 class; 4 unblocks #89)?
2. **lensfun's radius**: may the engineer read lensfun's coordinate code
   (`libs/lensfun/modifier.cpp`, LGPL 3) to learn the convention, writing
   nothing from it, or should it come from measurement only (more lenses
   needed), or from lensfun's maintainers?
3. **lensfun data**: ship it in the app (CC BY-SA 3.0, with what that
   means above), download on request, or user-supplied?
4. **Samples for a second round**: flat-field shots (a white wall or sky
   through a diffuser) with the 12-32 mm at 12 mm, f/3.5, f/4 and f/5.6 for
   vignetting; raws from two or three other lenses in lensfun with the
   camera's own correction available (MFT) for the radius; and an X-Trans
   raw with a Lightroom export for X-Trans color.

## Proposed issues (for the main session to file)

- **enhancement: Build the vendored LibRaw at -O3.** Body: SwiftPM compiles
  `CLibRaw` at `-Os` in release. The #194 spike measured the same decodes
  with LibRaw at `-O3`: AHD demosaic 638 → 216 ms (GX85 RW2), 828 → 286 ms
  (5D II CR2), X-Trans three passes 7981 → 7169 ms; totals 891 → 404, 1159 →
  604, 8600 → 7788 ms. Set it in `Package.swift` (`cxxSettings`), check that
  LibRaw's output is byte for byte unchanged (`LibRawFallbackTests`,
  goldens) and that build time and binary size are acceptable. Slug
  `libraw-o3`.
- **(comment on #177, not a new issue):** the spike's band numbers (X-E3
  9.0 → 1.85 s at 8 bands, 5D II 1.17 → 0.42 s), that bands of 450 rows or
  fewer fail with `LIBRAW_IO_ERROR`, and that the GPU demosaic below would
  replace the need.
- **enhancement: GPU demosaic for raws LibRaw decodes (X-Trans first).**
  Body: LibRaw's unpack, then our Metal demosaic and the existing color
  step, for raws the system decoder gives no image for (#161). The spike
  measured X-Trans full size at about 0.6 s (from 9.8 s), Bayer 85 to 300
  ms; it needs a directional X-Trans kernel (bilinear has 1.4 to 1.8 times
  LibRaw's false color), a CPU reference with the half-write bound of 2⁻¹⁰,
  and a color noise reduction step. Replaces #177. Slug `gpu-demosaic`.
- **enhancement: Own raw decode for chosen Bayer cameras (profiles, Adobe
  Kelvin, live white balance).** Body: with camera RGB from our decode, #89's
  option (c) works (median ΔE 0.62 to 0.88 against Lightroom), white balance
  is a 1.3 to 9 ms color step instead of a 99 to 173 ms re-decode, and Kelvin
  follows Adobe's scale. Opt-in, since it loses the system decoder's noise
  reduction, ML denoise and per-camera tuning. Depends on the GPU demosaic.
  Slug `own-raw-decode`.
- **enhancement: Lens corrections from lensfun data.** Body: our reader and
  a 1 to 6 ms GPU pass reproduce the GX85 12-32 mm's own correction within 3
  px once the radius normalization is right (measured, not documented);
  TCA better than Lightroom's. Blocked on the owner's licensing decision and
  the radius question; needs camera aliases (DMC-GX7MK2 = GX85), a careful
  lens matcher, and flat-field checks of vignetting. Relates to #87, #175,
  #176. Slug `lensfun-corrections`.
- **enhancement (or a note on #87): Read Panasonic and Olympus embedded
  distortion data for raws we decode.** Body: Lightroom and the system
  decoder both apply the RW2's own distortion and lateral color data (they
  agree within 0.8 px); for MFT raws decoded by us this is the reference
  correction and avoids lensfun's licensing and radius questions. Slug
  `mft-embedded-lens-data`.
