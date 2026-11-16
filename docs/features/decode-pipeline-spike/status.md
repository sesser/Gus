Issue: #194

# Our own GPU raw pipeline: spike status

A spike, not a feature: no PRD, no `design.md`. It ends in a report and a
recommendation for the owner: **`spike.md`** in this folder. Branch
`feature/decode-pipeline-spike`, cut from `develop` at `7218154`.

**Status: Done.** Every question of the issue is answered with numbers in
`spike.md`; nothing was built for the app.

| Question | State | Where |
|---|---|---|
| 1. Where a LibRaw decode's time goes; threads; bands (#177) | Done | `spike.md`, Question 1 |
| 2. Hybrid: LibRaw unpack, our Metal demosaic, our color step: speed and quality, CPU reference | Done (Bayer: bilinear, Malvar–He–Cutler, Hamilton–Adams with gradient weights; X-Trans: bilinear only) | Question 2 |
| 3. White balance and color control with our own decode; #89's finding | Done | Question 3 |
| 4. lensfun data with our own reader and kernel | Done for the GX85 (the only sample whose lens is in the database); vignetting not checkable against a reference | Question 4 |
| 5. Budget, cold and warm, and the live path | Done | Question 5 |
| 6. Recommendation, licensing, issue breakdown, LightCraft | Done | Recommendation |

## Build and tests

Machine: Apple M4 Pro (10 performance, 4 efficiency cores), 24 GB, macOS
27.2.1 (26B131), Swift 6.4.2, Xcode 26 toolchain (MacOSX27.2 SDK).

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline, `develop` at `7218154` (2026-11-16) | green | 1047 tests in 156 suites passed |
| Spike commit (2026-11-16) | green, no new warnings (debug, and `-c release --product photobench`) | 1047 tests in 156 suites passed (no tests added: measurement code only, in `photobench`) |

The spike makes no `CIRAWFilter` (system decodes go through
`PreviewGenerator`'s public API and `RawDefaults`), so the tripwire
`RAWDecodeGraphTests.rawFiltersAreMadeInKnownPlaces` needed no exemption.
No golden, tolerance, migration or `PreviewCacheKey.currentPipelineVersion`
changed; nothing in `PhotoCore`, `PhotoUI` or the apps changed.

One manifest change: `Package.swift` gives `PhotoBench` a dependency on
`CLibRaw` (target, not package: no new dependency), for LibRaw's unpack
without its demosaic. It goes with the spike.

## How to run it

Every mode is a `photobench` subcommand (in neither app bundle). Inputs are
read in place; nothing is written unless `--output` is given (it never is
below). In the commands, `S` is the owner's sample folder
(`~/Desktop/Export/gus-dcp-samples`), `L` a shallow clone of
https://github.com/lensfun/lensfun outside the repository, and `P` the
Lightroom Classic `CameraProfiles` folder.

```zsh
swift build -c release --product photobench
```

```zsh
.build/release/photobench decodespike --mode stages --runs 5 --files $S/GX85.RW2:$S/EM5MarkIII.ORF:$S/Canon5DMkII.CR2:X-E3.RAF:X-T3.RAF
```

```zsh
.build/release/photobench decodespike --mode stages --runs 3 --qualities 0,1,2,3,4,11,12 --files $S/GX85.RW2:X-E3.RAF
```

```zsh
.build/release/photobench decodespike --mode bands --runs 2 --bands 1,2,4,6,8,10,14 --files X-E3.RAF:$S/Canon5DMkII.CR2
```

```zsh
.build/release/photobench decodespike --mode verify --files $S/GX85.RW2:$S/EM5MarkIII.ORF:$S/Canon5DMkII.CR2:X-E3.RAF:X-T3.RAF
```

```zsh
.build/release/photobench decodespike --mode quality --files $S/GX85.RW2:$S/EM5MarkIII.ORF:$S/Canon5DMkII.CR2
```

```zsh
.build/release/photobench decodespike --mode real --lightroom $S --files $S/GX85.RW2:$S/EM5MarkIII.ORF:$S/Canon5DMkII.CR2:X-E3.RAF:X-T3.RAF
```

```zsh
.build/release/photobench decodespike --mode timing --runs 6 --files $S/GX85.RW2:$S/EM5MarkIII.ORF:$S/Canon5DMkII.CR2:X-E3.RAF:X-T3.RAF
```

```zsh
.build/release/photobench decodespike --mode budget --frames 20 --files $S/GX85.RW2:$S/Canon5DMkII.CR2:X-E3.RAF:X-T3.RAF
```

```zsh
.build/release/photobench decodespike --mode lens --sweep --lensfun $L/data/db --lightroom $S --files $S/GX85.RW2
```

```zsh
.build/release/photobench decodespike --mode lens --lens "XF 35mm f/2 R WR" --lensfun $L/data/db --files X-E3.RAF:X-T3.RAF
```

```zsh
.build/release/photobench decodespike --mode color --samples $S --profiles $P --lensfun $L/data/db
```

`SPIKE_LEVELS=1` before `--mode stages` also prints LibRaw's white and black
levels before and after its processing (the white span check of Question 2).

The `-O3` comparison of Question 1 builds `photobench` a second time into a
scratch folder, with LibRaw at `-O3`:

```zsh
swift build -c release --product photobench --scratch-path /tmp/gus-o3 -Xcxx -O3 -Xcc -O3
```

## Spike code: what to keep and what to delete

All of it is throwaway and lives where it cannot ship:
`Sources/PhotoBench/DecodeSpike/`, the `decodespike` lines in
`Sources/PhotoBench/main.swift` and the `CLibRaw` dependency of
`PhotoBench` in `Package.swift`. Delete all three together when the owner
has read the report, or keep the folder until the first issue below is
built, as a reference for its tests:

- **Worth keeping as a starting point (rewritten, not moved, into PhotoCore
  with real tests):** `RawMosaic.swift` (LibRaw's unpack only: visible area,
  pattern, black per site, white span, the same multipliers as
  `LibRawDecoder`), `MetalDemosaic.swift` and `DemosaicReference.swift` (the
  kernels and their CPU reference, bit for bit equal), `DemosaicVerify.swift`
  (the bound's derivation), `LensfunData.swift` (the reader; its matcher is a
  sketch) and the lens kernel in `LensSpike.swift`.
- **Delete:** `LibRawStages.swift`, `HybridTiming.swift`,
  `DemosaicQuality.swift`, `PipeImage.swift`, `ColorSpike.swift`, and the two
  files copied from the #89 spike (`ProfileDCP.swift`, `ProfileColor.swift`;
  the originals live on the unmerged `feature/dcp-profiles`).

## README

Nothing for the README: no requirement, build command or layout of the
shipping app changed.

## Open questions

For the owner, in `spike.md` (Questions for the owner): which first step to
build, whether reading lensfun's coordinate code (not copying it) is
acceptable to settle the distortion radius, the lensfun data licensing, and
the samples a second round would need.
