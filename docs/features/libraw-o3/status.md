Issue: #195

# LibRaw at -O3: implementation status

Owner: swift-macos-engineer. A build setting, so it takes the bug-fix route
(`docs/WORKFLOW.md` "Bug fixes"): no PRD or design. Branch
`feature/libraw-o3`, cut from `develop` at `7218154`.

**Status: Done.** Next: code-reviewer, then qa-tester. No UI changed, so no
design review.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `7218154`, macOS 27.2.1, Apple M4 Pro).
1. `swift build -c release -v`, or `Scripts/build-app.sh`.
2. Look at a `CLibRaw` compile line: its optimization flag is in the response
   file it names
   (`.build/out/Intermediates.noindex/PhotoWorkspace.build/Release/CLibRaw-t.build/Objects-normal/arm64/*-common-args.resp`).

**Expected.** The vendored LibRaw, which decodes the raws the system decoder
gives no image for (#161), is compiled for speed (`-O3`) in release.

**Actual.** It is compiled at `-Os`, SwiftPM's (Swift Build's) release default
for C and C++ targets. Found by the #194 spike
(`docs/features/decode-pipeline-spike/spike.md` on `feature/decode-pipeline-spike`),
which measured LibRaw's AHD demosaic 3 times as fast at `-O3`.

**Root cause.** `Package.swift` set no optimization level for `CLibRaw`, so
release builds took the size-optimizing default. Debug builds are `-O0`.

**The fix.** `cxxSettings` of `CLibRaw` gains
`.unsafeFlags(["-O3"], .when(configuration: .release))` (the target already
used `unsafeFlags(["-w"])`; SwiftPM has no optimization setting for C targets,
and `-Xcxx` on the command line would apply to every target and every
caller). Swift Build writes `-Os` and the target's flags into one response
file, `-Os` at position 7 and `-O3` at 21; clang takes the last `-O`
(`clang -### -Os -O3` gives `-O3` to the compiler). Debug's response file
still holds only `-O0`.

**The test.** No automated test can see the optimization level without
adding a file to the vendored tree (a C function reading `__OPTIMIZE_SIZE__`),
which `CLAUDE.md` forbids. The checks are: (1) the release response file's
last `-O` is `-O3` (command below); (2) LibRaw's full decode times below; (3)
LibRaw's output is bit for bit unchanged (below), which the existing tests
also cover.

```sh
tr ' ' '\n' < .build/out/Intermediates.noindex/PhotoWorkspace.build/Release/CLibRaw-t.build/Objects-normal/arm64/*-common-args.resp | grep '^-O'
```

After `Scripts/build-app.sh` on this branch it prints `-Os` then `-O3`; on
`develop`, `-Os` alone.

## Output unchanged, bit for bit

A throwaway Swift Testing probe (never committed) decoded each raw with
`LibRawDecoder.decode` at full and half size, the app's settings and the
Fujifilm frame and lens corrections, and recorded the SHA-256 of LibRaw's own
pixels (`Output.rgba16`), the size and frame, the whole `CameraColorStep`
(matrices, tone curve, channel scale, exposure) and of the photo rendered
through the color step to half-float RGBA at full size. Two release builds in
separate scratch folders, `develop`'s `Package.swift` (`-Os`) and this
branch's (`-O3`), all products built from clean; then the same probe in a
debug build (`-O0`).

| File | Camera | LibRaw pixels full / half | Color step, size, frame | Rendered full / half |
|---|---|---|---|---|
| `GX85.RW2` | Panasonic GX85 | same | same | same |
| `Canon5DMkII.CR2` | Canon 5D Mark II | same | same | same |
| `EM5MarkIII.ORF` | Olympus E-M5 III | same | same | same |
| `DSCF5123.RAF` | Fujifilm X-E3 (compressed, system can't read) | same | same | same (see note) |
| `DSCF4583.RAF` | Fujifilm X-T3 | same | same | same |

`-O0`, `-Os` and `-O3` give the same bytes for all of these. Every decode was
also repeated in the same process and compared (equal).

Note: the very first `-Os` run rendered `DSCF5123.RAF` at full size to a
different hash (`d421d3f2…`) from every later render of it, in either build
(`4bc0a835…`: 27 more renders at `-Os` in six processes, 15 at `-O3` in four,
including the same five-file order; an `-Os` and an `-O3` render compared
value by value: 0 of 96,000,000 differ). LibRaw's pixels and color step were
the same in that run, so the difference arose downstream, in Core Image or
the GPU, and was not reproduced; its bytes were not kept, so where and by
how much is unknown. Not caused by this change (LibRaw's output fed to the
render was identical); proposed as a follow-up in the report.

## Existing tests

| Run | Result |
|---|---|
| `swift build` (debug), after | builds, no warnings |
| `swift test` (debug), after | 1047 tests in 156 suites passed |
| `swift test -c release` (full suite, `-O3`) | 1047 tests in 156 suites passed |
| `RAF_SAMPLE=…/DSCF5123.RAF swift test [-c release] --filter LibRawFallbackTests` | 9 of 9 passed at `-Os` and at `-O3` (release) |
| `RAF_SAMPLE=…/DSCF4583.RAF`, same | 2 of 9 fail at the premise (`the system RAW decoder reads this file`): an X-T3 file macOS reads, so not a sample for this suite |
| `RAW_BOTH_SAMPLES=GX85.RW2:Canon5DMkII.CR2:EM5MarkIII.ORF:DSCF4583.RAF swift test -c release --filter LibRawAgainstSystemTests` | fails at `-Os` and at `-O3` with the same 8 issues and the same printed numbers to the last digit (pre-existing; see Observations) |
| `swift test -c release --filter 'GoldenTests\|LibRawDecoderTests\|LibRawFallbackPipeline\|RAWDecode\|LinearRawDecode\|CameraColor'` | 68 tests passed; RAW goldens skipped as fingerprinted on macOS 27.2 (26B123), this Mac is 27.2.1 (26B131) |
| `Scripts/build-app.sh all` | both bundles built; their LibRaw compiled with `-O3` last |

No golden, tolerance or `PreviewCacheKey.currentPipelineVersion` changed.

## Measurements

Release builds, Apple M4 Pro, macOS 27.2.1, Swift 6.4.2. Decode times are
`LibRawDecoder.decode` (open, unpack, process, make image, the copy to RGBA,
the CIImage), raws in the file cache, 5 runs: median of runs 2 to 5, two
sessions each (they agreed within 1.5%; one shown, the second in brackets).

| File | Full `-Os` | Full `-O3` | Change | Half `-Os` | Half `-O3` |
|---|---|---|---|---|---|
| GX85 RW2 (16 MP) | 895 [891] ms | 400 [397] ms | 2.2x | 128 [127] ms | 108 [104] ms |
| 5D II CR2 (21 MP) | 1168 [1154] ms | 622 [614] ms | 1.9x | 294 [290] ms | 291 [290] ms |
| E-M5 III ORF (20 MP) | 1178 [1173] ms | 618 [613] ms | 1.9x | 307 [307] ms | 300 [294] ms |
| X-E3 RAF (24 MP, compressed) | 9141 [9029] ms | 7939 [7898] ms | −13% | 589 [581] ms | 586 [583] ms |
| X-T3 RAF (26 MP) | 9658 [9632] ms | 8346 [8425] ms | −13% | 620 [614] ms | 609 [605] ms |

Half-size decodes (thumbnails and fitted previews) skip the demosaic, so
they barely move. The debug build (`-O0`, unchanged) decodes the GX85 in
4.7 s and the X-E3 in 27.8 s.

| Build | `-Os` | `-O3` | Change |
|---|---|---|---|
| Clean `swift build -c release`, all products, wall | 87.9 s | 89.4 s | +1.5 s |
| Same, CPU (user) | 192.5 s | 197.0 s | +4.6 s |
| `PhotoApp` executable | 25,922,328 B | 26,095,672 B | +173,344 B (+0.67%) |
| `photobench` | 15,378,632 B | 15,552,232 B | +173,600 B (+1.1%) |
| `PhotoImporter` | 16,430,144 B | 16,587,184 B | +157,040 B |
| `photocli` | 14,397,048 B | 14,570,600 B | +173,552 B |

One clean build each, so the build time difference is within noise.

## Observations (not changed here)

- **`LibRawAgainstSystemTests` fails with these samples** on `develop` as on
  this branch, identically: the 5D II at −1.232 EV, tone spread −22.6%, ΔE
  19.5 unedited (the suite's table says −0.45 EV, −12%, 7.4 for its 5D II
  file); the E-M5 III at ΔE 10.6 (table 9.5) and 11.3 at 5500 K (table 6.7);
  the GX85 (a DMC-GX7MK2, not in the table) on Kelvin −12.8% and ΔE 5.7 at
  5500 K; the X-T3 file on ΔE 10.0 at 5500 K. These may be other files than
  the ones the limits were measured on, or a change since #170; not looked
  into.
- **One unreproduced render difference** of `DSCF5123.RAF`, above.

## README

No change to requirements, build commands or the repository layout. Two
timing statements become a little high (product manager, at Ship): the
README's "about 9 s to sharpen such a photo at 100%" (now about 8 s for an
X-E3 or X-T3 file) and `CLAUDE.md`'s #161 entry, "takes about 9 s for an X-E3
file". `docs/PROFILING.md`'s LibRaw table (1.09 to 1.32 s for Bayer files at
full size) predates this and is now about half for the Bayer rows.

## Open questions

None.
