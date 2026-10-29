# Profiling

Phase 1 measurements come first; phases 2 and 3 have their own sections below. Measured
on 2026-10-23 with release builds.

**Machine:** Apple M4 Pro (14 cores), 24 GB, macOS 27.0.1.
**Display:** external, 60 Hz, 2× scale. The library window was 1320 × 860 pt.

## Synthetic library

`photobench generate` wrote 10,000 files (6.0 GB) in 18 s:

| files | format | size | notes |
|---|---|---|---|
| 9,800 | JPEG | 2048 × 1365 | every fifth one is portrait via EXIF orientation 6 |
| 100 | DNG | 6000 × 4000 | uncompressed 16-bit RGGB Bayer, decoded by `CIRAWFilter` |
| 100 | HEIC | 4032 × 3024 | |

Every file has unique pixels (the seed is drawn in as a bar code) and an EXIF
capture date. For grid-scale tests, `photobench synthesize` then grew the
catalog to **50,000 versions**. It cloned rows under new content hashes and
hard-linked their cached renditions. The extra 40k have no masters behind them,
so they exercise the catalog, the cache and the grid, not import or rendering.

## Import (10k files)

Times are wall-clock sums per stage. The files had just been written, so reads
came from the OS page cache. Hashing from a cold SSD would be bounded by disk
throughput instead.

| metadata reader | total | files/s | scan | hash (SHA-256) | metadata | catalog |
|---|---|---|---|---|---|---|
| ExifTool, 1 process (first version) | 12.68 s | 789 | 0.13 s | 1.39 s | 10.40 s | 0.63 s |
| **ExifTool, pool of 4 (default)** | **5.54 s** | **1,804** | 0.14 s | 1.61 s | 3.06 s | 0.62 s |
| ImageIO (in process) | 2.01 s | 4,985 | 0.13 s | 0.67 s | 0.47 s | 0.61 s |
| re-import, nothing changed | 0.30 s | 32,909 | 0.14 s | 0 (skipped by path, size and mtime) | 0 | 0.07 s |

## Preview generation (cold cache)

All renditions are generated through `PreviewService`.

| tier | jobs at once | wall | renditions/s | JPEG mean (p95) | HEIC mean | DNG mean |
|---|---|---|---|---|---|---|
| thumbnail, 512 px | 4 | 19.9 s | 503 | 3.7 ms (4.4) | 104 ms | 330 ms |
| preview, 2560 px | 7 | 45.3 s | 221 | 24.6 ms (34.7) | 155 ms | 598 ms |

Cache on disk after both tiers: 1.33 GB (synthetic images compress unusually
well; expect several times that for real photos).

RAW thumbnails (draft decode) scale with parallel jobs, which is why the
default now follows core count (4 to 8; 7 here):

| DNG thumbnail jobs | mean latency | throughput |
|---|---|---|
| 1 | 120 ms | 8.3/s |
| 4 | 262 ms | 15.1/s |
| 8 | 258 ms | 29.8/s |

## Cache reads and the memory cache (warm)

| what | result |
|---|---|
| thumbnail decode at 360 px (180 pt cells), one at a time | 1.39 ms mean, p95 1.68 ms |
| same, through `PreviewService` with 6 load jobs | 4,178 images/s (4,112/s at 50k) |
| thumbnail decode at 200 px | 0.62 ms mean, 12,243 images/s through the service |
| loupe preview decode | 6.4 ms mean |
| memory cache lookup | 0.4–0.6 µs |

## Catalog queries

Queries are async and never run on the main thread.

| query | 10k versions | 50k versions |
|---|---|---|
| all photos (grid rows) | 4.4 ms | 24.6 ms |
| rating ≥ 3 | 1.1 ms | 11.1 ms |
| picked | 0.7 ms | 5.1 ms |
| not rejected (matches all) | 5.5 ms | 53.3 ms |
| one project (10k / 40k rows) | 6.4 ms | 43.1 ms |
| project list with counts | 1.5 ms | 6.7 ms |
| one rating write | p50 0.03 ms, p99 0.14 ms | p50 0.03 ms, p99 0.08 ms |

## Grid scrolling (warm cache)

The app's `--benchmark-scroll` mode scrolls the real window with a display link
at a constant speed for 6 s per configuration. For each frame it records the
interval and the share of visible cells already showing their thumbnail. A
hitch is a frame longer than 1.5 refresh intervals (25 ms at 60 Hz).

| library | cell size | speed | frames | hitches | p95 frame | visible cells filled |
|---|---|---|---|---|---|---|
| 10k | 120 pt | 3,000 pt/s | 360 | 0 | 16.7 ms | 100% |
| 10k | 200 pt | 3,000 pt/s | 360 | 0 | 16.7 ms | 100% |
| 10k | 320 pt | 3,000 pt/s | 360 | 0 | 16.7 ms | 100% |
| 50k | 120 / 200 / 320 pt | 3,000 pt/s | 360 each | 0 | 16.7 ms | 100% (min 96%) |
| 10k | 160 pt | 12,000 pt/s, run alone | 360–720 | 0 | 16.7 ms | 99.9–100% |
| 50k | 120 pt | 8,000 pt/s, run alone | 840 | 0 | 16.7 ms | 100% |
| 10k / 50k | 160 pt | 12,000 pt/s, after other runs | ~280 | 1–40 | 17–60 ms | 91–100% |

3,000 pt/s is about 3.5 screen heights a second. It held every frame in all
runs at both sizes. Extreme flings (8,000–12,000 pt/s, 400–500 new cells a
second) were perfect when run alone. Late in longer sequences they varied from
clean to 40 long frames out of ~300, and identical sequences gave different
results from one run to the next. In the bad runs the main thread spends its
time in `NSCollectionView` creating and recycling item views, not in our code
(under 2% of samples). Visible-cell fill dropped at the same moments, which
points to contention from other load on the machine (it was in use). A
layer-only grid without a view per cell would remove that per-item cost if it
matters in practice.

Fixed along the way: thumbnails used to be handed to Core Animation in Display
P3, and CA converted each one to the screen's profile on the main thread while
committing. They are now converted to the window's color space in BGRA as they
are decoded, off the main thread.

Not measured: a 120 Hz ProMotion display, cold-disk reads (needs `sudo purge`),
real camera RAW files (no embedded-preview fast path yet; compressed RAW decode
costs differ from the synthetic DNGs).

## Phase 2

Measured on 2026-10-23 on the same machine, release builds, with the same 10k
synthetic library (50k versions for queries and scrolling) unless noted.

### Import with the extra metadata

Phase 2 reads about 30 more tags (keywords, rating, label, creator, copyright,
caption, serial, GPS, flash, exposure, white balance, contact, usage terms),
looks for sidecars, and records each master's sidecar baseline.

| metadata reader | phase 1 | phase 2 | metadata | catalog |
|---|---|---|---|---|
| ExifTool pool (default) | 5.54 s | 7.42 s (1,347 files/s) | 3.06 → 4.37 s | 0.62 → 1.18 s |
| ImageIO | 2.01 s | 2.59 s (3,856 files/s) | 0.47 → 0.53 s | 0.61 → 1.12 s |

The extra ExifTool time is spread over the new tags (each group of a few tags
adds 3–7 % on its own; none stands out). In the catalog stage, building the
sidecar baseline from the values being inserted instead of reading them back
took it from 2.35 s to 1.37 s, and listing each folder's `.xmp` files once
instead of checking four names per master took it to 1.18 s.

### Queries (50k versions)

| query | time |
|---|---|
| all photos, no pairs | 29.0 ms (24.6 in phase 1) |
| all photos, 25k pairs grouped (25k rows out of 50k) | 47.6 ms |
| keyword summaries (20 keywords on a third of the library) | 0.7 ms |
| one keyword's photos (834) | 0.9 ms |
| smart album, rating ≥ 3 and camera contains … (7,143 rows) | 14.6 ms; count only 11.0 ms |
| No Keywords count (33,320) | 15.8 ms |
| capture months (Dates tree) | 14.3 ms |
| project summaries, pairs counted once | 7.5 ms (6.7 in phase 1) |

Pairs are resolved in memory from the small pair table: joining them into the
grid query had doubled its time (55 ms without any pairs). Sidebar counts are
refreshed in the background 300 ms after the last change.

### Grid scrolling with labels (warm cache)

| library | cell size | speed | frames | hitches | visible cells filled |
|---|---|---|---|---|---|
| 50k | 120 / 200 / 320 pt | 3,000 pt/s | 360 each | 0 | 100 % |
| 50k | 160 pt | 8,000 pt/s | 357 | 1 | 100 % |
| 50k with 25k pairs grouped (25k items) | 120 / 200 pt | 3,000 pt/s | 360 each | 0 | 100 % |

File names and type badges cost nothing measurable: badges are pre-rendered
per label and positioned without a layout pass.

### Background work

| work | result |
|---|---|
| keyword suggestions (Vision, cached 512 px thumbnail) | 142 photos/s one at a time: 0.8 ms thumbnail, 6.2 ms classify |
| writing sidecars after a change to 10,000 photos | 7.1 s (1,407/s) |
| checking 10,000 masters and sidecars for outside changes | 0.92 s (10,893/s) |

### Copying imports

Copying from the library's SSD to itself, with each copy written, renamed,
re-read around the file cache and hashed:

| files | plain streamed copy | copy, verify, catalog |
|---|---|---|
| 1,000 small JPEGs (122 MB) | 763 MB/s | 206 MB/s (per-file costs dominate) |
| 24 RAW+JPEG pairs and 48 more files (350 MB, 12 MB DNGs) | 1.27 GB/s | 976 MB/s |

SD cards read at 90–300 MB/s, so the card is the limit in practice. Before an
import only files whose size matches a master already in the library are
hashed (to hide duplicates); on a card of new photos that is none.

Not measured in phase 2: real camera cards and RAW files, PTP cameras (not
supported), videos at scale.

## Phase 3: adjustments

Measured on 2026-10-26, same machine, release build, with `photobench edits`
on 6 files per format (DNG 6000 × 4000, HEIC 4032 × 3024, JPEG 2048 × 1365).
The "typical" stack has exposure, all five tone sliders, clarity, dehaze,
vibrance, saturation, a 4-point curve, two grading wheels and sharpening with
masking: nearly the whole graph.

| format | preview, identity | preview, typical stack | live, first frame | live, next frame | live, RAW white balance |
|---|---|---|---|---|---|
| DNG | 104 ms | 125 ms | 119 ms | 36 ms (p95 43) | 87 ms (p95 104) |
| HEIC | 87 ms | 106 ms | 115 ms | 25 ms (p95 30) | — |
| JPEG | 29 ms | 42 ms | 47 ms | 16 ms (p95 17) | — |

- A typical stack adds about 15–20 ms to a 2560 px preview: the cost is in
  decoding, not in the adjustments.
- **Live frames** reuse the decoded master (a half-float copy at 2560 px), so a
  slider drag costs one pass of the graph, the readback and the histogram:
  25–60 frames per second.
- **RAW decode settings** (white balance, profile, noise reduction) decode again,
  at half size in draft mode while dragging: about 11 frames per second on a
  24 MP file. The full-size decode follows on release.
- First frames include the decode of the base; the editor starts one 250 ms
  after a photo is shown, so it is usually ready before the first drag.

## Real camera RAW files and render contexts

Measured on 2026-10-28, same machine, release builds, on 200 files hard-linked
from a real library: 40 each of CR2 (Canon 5D Mark II / 6D), RW2 (Panasonic),
ORF (Olympus E-M5 III), ARW (Sony A7 III) and camera JPEGs, about 20 MP each.

Camera raws are decoded lazily inside the Core Image render that first needs
their pixels, and a `CIContext` runs one render at a time. With a single
context for everything, seven preview jobs ran one after another (the process
sat at about 150 % CPU with the other jobs waiting in `-[CIContext lock]`), and
the loupe's live frames waited behind them. `RenderEngine` now keeps a pool of
contexts (one per generate job) and gives each render the least busy one;
`PreviewService.interactiveGenerator` has two contexts of its own for live
edits, the loupe's 1:1 and HDR renditions, and look and preset previews. Background
work also leaves one generate slot to on-screen requests.

| measurement | one context | pool + interactive contexts |
|---|---|---|
| previews, 2560 px, 7 jobs | 7.6/s, ~150 % CPU | 15.7/s, 375–450 % CPU |
| preview latency, CR2 / RW2 / ORF / ARW / JPEG | 774 / 804 / 1,303 / 1,116 / 548 ms | 360 / 394 / 565 / 741 / 138 ms |
| live next frame while 7 previews render (mean, p95) | 594–1,309 ms, up to 4.4 s | 91–140 ms, 183–246 ms |
| live first frame while previews render | 1.1–4.8 s | 0.17–0.77 s |
| live next frame, idle | 26–52 ms | 26–50 ms (unchanged) |

What remains under load is the decode itself (render threads wait in
`GetSurfaceFromCacheAndFill` for RawCamera) and sharing the GPU and CPU with
the background jobs: live frames are still 3–5 times faster when nothing runs in the background.

```bash
.build/out/Products/Release/photobench edits --library-root $LIB --limit 3 --under-load
```

## Reproducing

Build the tools:

```bash
swift build -c release --product photobench
```

```bash
Scripts/build-app.sh
```

Generate, import, render and read back (`LIB` and `SRC` are any two folders):

```bash
export SRC=/tmp/photolib-src LIB=/tmp/photolib
```

```bash
.build/out/Products/Release/photobench generate --output $SRC --jpeg 9800 --dng 100 --heic 100
```

```bash
.build/out/Products/Release/photobench import --library-root $LIB --source $SRC
```

```bash
.build/out/Products/Release/photobench previews --library-root $LIB --tier thumbnail --fresh
```

```bash
.build/out/Products/Release/photobench previews --library-root $LIB --tier preview
```

```bash
.build/out/Products/Release/photobench read-cache --library-root $LIB --pixel-size 360 --limit 10000
```

```bash
.build/out/Products/Release/photobench query --library-root $LIB
```

```bash
.build/out/Products/Release/photobench synthesize --library-root $LIB --count 50000
```

Phase 2 additions (`--pairs` writes RAW+JPEG pairs, `--videos` short clips):

```bash
.build/out/Products/Release/photobench generate --output $SRC --jpeg 40 --dng 4 --heic 4 --pairs 24 --videos 2
```

```bash
.build/out/Products/Release/photobench suggest --library-root $LIB --limit 1000
```

```bash
.build/out/Products/Release/photobench sidecars --library-root $LIB --limit 10000
```

```bash
.build/out/Products/Release/photobench copy --source $SRC --dest /tmp/copy-bench --limit 1000
```

Phase 3 (adjustments; renders previews and live frames for up to `--limit` files per format):

```bash
.build/out/Products/Release/photobench edits --library-root $LIB --limit 6
```

Scroll benchmark (opens the window for about 40 s, then quits):

```bash
build/*.app/Contents/MacOS/* --library-root $LIB --benchmark-scroll /tmp/scroll.json
```

Run selected configurations only:

```bash
SCROLL_BENCHMARK_RUNS=160x12000,120x3000 build/*.app/Contents/MacOS/* --library-root $LIB --benchmark-scroll /tmp/scroll.json
```
