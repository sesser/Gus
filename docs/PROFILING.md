# Phase 1 profiling

Measured on 2026-10-23 with release builds.

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

Scroll benchmark (opens the window for about 40 s, then quits):

```bash
build/*.app/Contents/MacOS/* --library-root $LIB --benchmark-scroll /tmp/scroll.json
```

Run selected configurations only:

```bash
SCROLL_BENCHMARK_RUNS=160x12000,120x3000 build/*.app/Contents/MacOS/* --library-root $LIB --benchmark-scroll /tmp/scroll.json
```
