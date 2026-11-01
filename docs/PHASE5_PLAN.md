# Phase 5 plan: golden images, a headless command line, custom GPU kernels

Status: **first pass done**. Golden-image harness and CPU references, `photocli`
over a command registry, and the custom-kernel spike (Option A works).

Image-algorithm work compiles and moves sliders long before anyone can tell
whether its math is right. This phase builds the feedback loop that masks,
healing and lens corrections will need: render without the UI, compare with
stored images and with plain CPU implementations, and get the difference as an
image. The architecture and naming rules in `CLAUDE.md` still apply; this file
records the decisions and why.

Out of scope: an MCP server, masks, brushes, healing, lens corrections, UI
changes, and any change to the output of existing adjustments. No rendering
output changed in this phase, so `PreviewCacheKey.currentPipelineVersion` is
unchanged.

## Decisions: golden images

- **Scenes** (`PhotoFixtures/TestScenes.swift`, `TestScene`): a grey ramp
  (perceptually even steps over the top three quarters, a linear 0 … 4 strip
  below for headroom), every hue across the width (saturated, then fading to
  grey), a 6 × 4 patch chart of our own colors, a hazy landscape (sky, hills,
  textured foreground under the haze model I = J·t + A·(1 − t)) and an edge
  target (step and 5° slanted edges, 1-, 2- and 3-pixel line pairs, a
  24-sector star, 4 × 4 supersampled). 256 × 192 by default; any size draws
  the same scene. Colors are picked in the renderer's perceptual encoding and
  stored as linear Rec. 2020 floats (`LinearImage`), so they reach the
  renderer unconverted. The only random input is the landscape's texture,
  `SplitMix64` with a fixed seed.
- **Goldens** (`Tests/PhotoCoreTests/Goldens`, 35 files, 1.5 MB): exposure
  (−1, +1, +0.5), relative white balance (warmer, magenta, cooler and
  greener), tone (contrast ±, highlight recovery over the headroom strip,
  brighter highlights, shadows, whites and blacks), clarity ±, dehaze ±,
  vibrance ±, saturation ±, tone curve (S curve; red and blue channels),
  color mixer (two sets), color grading (split tone; midtones with balance
  and blending), vignette (dark ellipse, light circle, rectangle), sharpening
  (default; detail and masking), grain (default; coarse color) and crop (crop
  with straighten; quarter turn with straighten). They pin today's output and
  claim nothing about its correctness. RAW decode settings (profile, Kelvin
  white balance, decoder noise reduction) need a RAW master and are not
  covered; neither are look-up tables and non-RAW noise reduction.
- **Format**: 16-bit PNG in the perceptual encoding (Rec. 2020 primaries, sRGB
  curve, tagged so Preview shows it). Values outside 0 … 1 clip the same way
  in the golden and in the render it is compared with. Goldens load from the
  source tree through `#filePath`; `Package.swift` only excludes the folder
  (no resources entry). A written PNG reads back bit for bit
  (`GoldenHarnessTests`).
- **Comparison** (`ImageDifference`): largest absolute difference per
  channel, PSNR over the three channels (peak 1), and mean and largest
  OkLab ΔE (Ottosson's published definition; L runs 0 … 1).
- **Tolerance**: max channel 0.002, PSNR ≥ 60 dB, ΔE mean ≤ 0.0005 and max ≤
  0.004. The machine that made the goldens reproduces them bit for bit. Two
  Metal contexts of different priority on the same Mac differed by at most
  0.0005 (dehaze, whose airlight is an area reduction) and 0.00003 (the
  rectangular vignette), identical elsewhere; the tolerance is four times the
  larger. It is half an 8-bit step and a fifth of a visible OkLab difference,
  so a change to a module's math or constants still fails.
- **Failure output**: a mismatch writes expected | actual | 8 × |difference|
  as one PNG to `$TMPDIR/golden-failures/<name>.png` and names it in the
  failure with all four measures and the tolerance's reason.
  `UPDATE_GOLDENS=1 swift test` rewrites only goldens whose pixels changed and
  prints each path; otherwise a missing golden fails. `GOLDENS_REPORT=1`
  prints every case's difference, for comparing machines.
- **Determinism: no software renderer.** Core Image's header says the
  software renderer option "has no effect if the platform does not support
  OpenCL". On this Apple silicon Mac a context created with it describes
  itself as `(metal 3)` and renders a 4000 × 3000 blur as fast as the GPU
  context; goldens rendered "both ways" were identical, in 0.27 s each. So
  goldens render through a Metal context with the app's options, and the
  tolerance allows for another GPU. `RenderEngine(softwareRenderer:)` still
  asks for it and `RenderEngine.softwareRendererIsAvailable` says whether it
  exists (from the context's description, as Core Image has no API for it).
- **Grain** repeats exactly: `CIRandomGenerator` is a fixed pattern, so the
  same render gives the same bytes in one process and across runs
  (`rendersAreRepeatable` checks every case). Grain therefore has goldens,
  not noise statistics.
- **Other Macs: unchecked.** Goldens were made and checked on one Apple M4
  Pro with macOS 27.2. The CI runner (macOS 26, a virtual GPU) will be the
  first other machine; if it differs, `GOLDENS_REPORT=1` says by how much.

## Decisions: CPU references

`Tests/PhotoCoreTests/Reference` holds plain Swift implementations of the math,
in the same working space, with no Core Image: `ColorMath` (sRGB curve, Rec.
2020 to XYZ, OkLab), `ExposureReference`, `OutputReference` (Rec. 2020 to
Display P3) and `BlurReference`. `ReferenceTests` checks the renderer against
them; each test states its tolerance and why.

- **Exposure**: input × 2^EV in linear Rec. 2020, on the grey and hue ramps
  and the chart, five EVs. Tolerance: two half-float roundings (2⁻¹⁰ relative)
  plus 2⁻²⁴, since the working format is `RGBAh` and the input and the result
  are each rounded once. Applying the gain to encoded values instead fails
  every case by far (checked).
- **Output**: a matrix from Rec. 2020 to Display P3 primaries, then the sRGB
  curve, 16-bit; within 0.001 (a quarter of an 8-bit step).
- **Perceptual encoding**: `CILinearToSRGBToneCurve` is exactly the sRGB curve
  within half-float rounding.

The renderer's color chain, as checked:

1. **Decode.** JPEG, HEIC and TIFF masters are decoded by ImageIO; Core
   Image converts from the file's profile into the working space. RAW masters
   come out of `CIRAWFilter` already linear in the working space.
2. **Working space**: extended linear Rec. 2020 (`RenderEngine.workingColorSpace`),
   half float (`CIFormat.RGBAh`), values below 0 and above 1 kept.
3. **Linear steps**: relative white balance, exposure, the local tone gain
   (looked up from luminance to the ¼ power), dehaze, vibrance, saturation
   (Core Image's filters see working-space values), the vignette gain.
4. **Perceptual steps**: the same Rec. 2020 primaries with the sRGB curve
   (`AdjustmentRenderer.perceptualSpace`): the tone table, the color mixer
   and grading cubes (through the filters' color space), and clarity,
   sharpening and grain (through `CILinearToSRGBToneCurve` and back).
   Look-up tables use their own color space (sRGB by default).
5. **Output**: matrix to the output primaries and that space's curve: Display
   P3 for previews and the loupe, the chosen space for export, extended linear
   Display P3 at half float for HDR renditions.

## Decisions: command line

- **Registry** (`Sources/PhotoCore/Commands`): each command is one
  `CommandSpec` with a dotted id, a summary, an access level, a parameter
  schema (name, type, required, repeatable, positional) and a handler that
  takes JSON arguments and returns a JSON value or throws a `CommandError`
  (code and message). `CommandRegistry.standard` lists them; `run` validates
  arguments against the schema, takes the library lock for writes, and never
  prints. An MCP server or the debug script can dispatch the same commands;
  neither is built, and the app's debug script is unchanged. The design
  follows LightCraft's (one spec per command, a parameter description, a
  flag for writes versus queries); no code was taken from it.
- **`photocli`** (`Sources/PhotoCLI`, product `photocli`): a ten-line
  dispatcher. `CommandLineInterface` in PhotoCore turns argv into a command
  and arguments (`--kebab-case` options, `--name=value`, repeatable options,
  positional arguments, `query images` for `query.images`), runs it and keeps
  the output contract. It depends on PhotoCore only; arguments are parsed by
  hand. Help takes the product name from `AppBranding.displayName`.
- **Output contract**: exactly one JSON object on stdout (pretty-printed,
  sorted keys) and exit 0; on failure one object `{"error", "code"}` on stderr,
  exit 2 for usage errors (unknown command or option, missing or invalid
  value, conflicting options) and 1 otherwise. Nothing else is printed; logs
  go to the unified log.
- **Library**: `--library-root`, as for the app; without it the app's
  standard library (no data-directory migration). Commands never create a
  library: a missing catalog is `libraryNotFound`.
- **Writes** go through the same `Catalog` calls as the app
  (`setEditStack`, `setRating`, `setFlag`, `setColorLabel`), one transaction
  each. Ratings, flags and labels reach the other file of a RAW+JPEG pair, as
  in the app. They are not undoable: undo belongs to the app's window.
- **Not surprising the app.** The catalog is a WAL database, so another
  process can always read it, but the running app does not notice another
  process's writes. `LibraryLock` is an advisory `flock` on
  `Library/library.lock`: the app takes it when it opens a library (waiting up
  to two seconds for a command-line write to finish; if another copy of the
  app holds it, it opens anyway and logs, as before) and keeps it while open.
  Write commands try it without waiting and refuse with `libraryLocked`, naming
  the holder's process id; reads never take it. The system drops the lock
  when its holder exits or crashes, so it is never left behind. `flock` may
  not work on network volumes; libraries live on the local disk. A later step
  could let the app pick up outside writes instead (polling SQLite's
  `data_version`, or a Darwin notification posted by the command), which
  would allow writes while it is open.
- **Adjustment descriptions** (`Edits/AdjustmentParameters.swift`): each
  module declares its parameters (`AdjustmentModule.parameterDescriptions`:
  name, type, range, default) next to the modules, since ranges and defaults
  were spread over the modules and the Adjust tab. `adjustments` prints them
  and `--set` checks values against them. `AdjustmentParameterTests` sets every
  described parameter and checks that the module writes exactly those back,
  and that each default is left out.
- **Edits** (`Edits/AdjustmentEdits.swift`): `--set kind.parameter=value` and
  `--reset kind.parameter | kind | all` change the raw operation, then the
  stack goes once through `Adjustments`, so defaults are left out as when the
  app saves, and editing a module that is turned off turns it on. A crop's
  edges can be set one at a time; a value that does not end up in the stack
  (one edge alone) is `invalidEdit`.

### Commands

| command | access | does |
|---|---|---|
| `render <file> \| --version N` | read | renders through `PreviewGenerator` (the preview and export path) to `--out` (PNG 16-bit, JPEG, TIFF 16-bit by extension); `--long-edge`, `--stack file.json`, `--set …`, `--original`, `--color-space`, `--software` |
| `adjustments` | read | every module: kind, group, section, parameters with type, range, choices, default |
| `query projects` | read | projects with photo counts |
| `query images [<rules>]` | read | versions matching smart-album rules (JSON); `--project`, `--limit` (1000) |
| `develop --version N` | write (read with `--dry-run`) | `--reset …` then `--set …` on the stored stack |
| `rate`, `flag`, `label` | write | `--version N…` and the value (positional or named) |
| `export --version N… --to dir` | read | `ExportJob` with `--preset` (name or id) and/or `--settings` (JSON over it), `--policy` |
| `help [command]` | | the commands and their usage, or one command's schema |

Output shapes (abridged):

```json
{"output": "/tmp/a.png", "source": "…/IMG_0001.jpg", "format": "png", "width": 2048, "height": 1365,
 "bitsPerComponent": 16, "colorSpace": "sRGB", "renderer": "metal", "renderSeconds": 0.14,
 "renderHash": "d748…", "editStack": {"schemaVersion": 1, "operations": […]}, "versionID": 12}
```

```json
{"count": 1, "truncated": false, "images": [{"versionID": 2, "imageID": 2, "projectID": 1,
 "versionNumber": 1, "fileName": "IMG_0002.jpg", "path": "…", "online": true,
 "captureDate": "2026-10-02T10:00:00Z", "rating": 4, "flag": "picked", "colorLabel": "blue",
 "keywords": ["beach"], "editStack": {…}, "renderHash": "…"}]}
```

```json
{"versionID": 2, "editStack": {…}, "renderHash": "…", "changed": true, "written": false, "dryRun": true}
```

```json
{"code": "libraryLocked", "error": "The library is open in another process (process 18919), probably the app. …"}
```

Smart-album rules use the stored format (`SmartAlbumRules`), leniently:
`{"match": "any", "rules": [{"field": "rating", "comparison": "atLeast",
"value": {"number": 4}}]}`; an array of rules means "all"; ids are optional
and a missing comparison takes the field's first. Both files of a pair are
listed.

A session (zsh):

```zsh
photocli query images '[{"field": "fileName", "comparison": "contains", "value": {"text": "IMG_0002"}}]' --library-root ~/Pictures/Test
photocli develop --version 2 --set exposure.ev=0.7 --set toneCurve.rgb=0,0,0.3,0.25,0.7,0.8,1,1 --dry-run --library-root ~/Pictures/Test
photocli render --version 2 --out /tmp/v2.png --long-edge 1600 --library-root ~/Pictures/Test
```

## Decisions: custom GPU kernels (spike)

`CLAUDE.md` said no custom kernels because SwiftPM has no Metal step. Masks,
texture, healing and lens corrections need per-pixel and neighborhood math the
stock filters cannot express, so the spike checked what fits that constraint.

**Toolchain here**: the developer directory is Xcode 27.1 (no standalone
Command Line Tools install). `xcrun -find metal` finds Xcode's `metal`, but
running it fails: the Metal Toolchain is a separate component that is not
installed (`xcodebuild -downloadComponent MetalToolchain`). The spike needs
neither: it uses `swiftc` and Metal.framework's runtime compiler, which every
Mac has.

**Option A works**: `RuntimeKernels` (`Edits/Kernels/RuntimeKernels.swift`).

- Two `CIImageProcessorKernel` subclasses run Metal compute functions compiled
  from a Swift string with `MTLDevice.makeLibrary(source:options:)`; the
  library and pipeline states are cached per device behind a mutex.
- `GainKernel` is pointwise (2^EV on color). `BlurPassKernel` is one pass of
  a separable Gaussian (σ, taps to ceil(3σ)); `roi(forInput:arguments:outputRect:)`
  widens the output rectangle by the radius along its axis. The horizontal
  pass covers the extent plus the rows the vertical pass reads; edges repeat
  through `clampedToExtent`.
- Both declare 32-bit float input and output (`RGBAf`); the textures' rows
  run top down, so the offset from output to input uses the regions' max y.
- **Correctness**: against `ExposureReference` and `BlurReference` on a
  263 × 197 image (a multiple of no tile size), σ 0.8, 3 and 6, and eight odd
  rectangles (1 × 1 up to 255 × 6, touching every edge) rendered alone so that
  the region of interest decides the input, as for tiles. Largest blur
  difference 2.4e-7; tolerance 1e-5 from float32 sums. Dropping the halo from
  the region of interest fails both blur tests (0.44 and 0.87). Not checked:
  renders big enough that Core Image tiles them itself.
- **Speed** (`photobench kernels`, Apple M4 Pro, source on the GPU, render
  into a GPU texture; first call, then the median of seven):

  | | preview 2560 × 1707 | full 6000 × 4000 |
  |---|---|---|
  | source only | 6.5 / 2.2 ms | 10.9 / 6.7 ms |
  | gain, runtime kernel (`RGBAf`) | 6.6 / 4.1 ms | 25.5 / 21.9 ms |
  | gain, `CIExposureAdjust` | 1.3 / 1.2 ms | 6.9 / 6.7 ms |
  | blur σ 4, runtime kernel (`RGBAf`) | 9.0 / 7.0 ms | 44.9 / 39.1 ms |
  | blur σ 4, `CIGaussianBlur` | 5.9 / 2.6 ms | 22.6 / 15.3 ms |

  Compiling the source and both pipelines: 134 ms the first time on this Mac,
  1.2 ms afterwards (Metal keeps compiled shaders on disk). With half-float
  formats (`RGBAh`, measured once, not kept) the full-size gain took 12.7 ms
  and the blur 24.4 ms.
- **What the numbers mean**: a processor kernel is its own pass with its own
  intermediate texture; Core Image cannot fuse it with neighboring filters as
  it does `CIExposureAdjust` (whose time is the source's). So pointwise math
  costs a full read and write of the image, about twice that in `RGBAf`. The
  naive blur reads 2r + 1 taps per pass; Core Image's own is cleverer
  (fewer, bilinear taps; reduced copies for large radii). For neighborhood
  work (masks, healing, lens warps), Option A is usable now: half-float
  formats where precision allows, tiled threadgroup memory for wide
  kernels. Processor kernels need a Metal-backed context (they get no texture
  otherwise), which is every context on Apple silicon.

**Option B: not built**, since A works and starts fast. Only the Core Image
Kernel Language string API is deprecated (`kernelWithString:`, since macOS
10.14). `CIKernel.kernels(withMetalString:)` (macOS 12+) is not; its header
says such kernels need a Metal context on a device that supports dynamic
libraries. They are Core Image kernels, so Core Image can fuse them into its
passes, which is what pointwise kernels lack under Option A. Worth a probe if
that pass cost matters; untested here.

**Option C, fallback only**: compiling `.metal` files with the Core Image flags
into a `.metallib` in `Scripts/build-app.sh` and loading them with
`CIKernel(functionName:fromMetalLibraryData:)` needs the Metal Toolchain
(missing here), contradicts building with the Command Line Tools, and `swift
test` would never see the library.

**CI**: `.github/workflows/build.yml` runs on `macos-26`. The existing
`renderEngineIsMetalBackedAndOutputsDisplayP3` test passes there, so the runner
has a Metal device and the kernel tests will run rather than skip. Whether its
virtual GPU compiles and runs them is unverified until this branch runs in CI.
Without a device the suite is skipped with "No Metal device: runtime-compiled
kernels need one" (`.enabled(if:)`), never passed silently.

No kernel is wired into `AdjustmentRenderer`.

## Code

- `Sources/PhotoFixtures/TestScenes.swift`: `TestScene`, `LinearImage`.
- `Tests/PhotoCoreTests/Support/Goldens.swift`: `EncodedImage`, `ImageDifference`,
  `GoldenTolerance`, `Goldens`. `GoldenTests.swift`, `GoldenHarnessTests.swift`,
  `Goldens/`.
- `Tests/PhotoCoreTests/Reference/`: `ColorMath`, `ExposureReference`
  (and `OutputReference`), `BlurReference`. `ReferenceTests.swift`,
  `RuntimeKernelTests.swift`.
- `Sources/PhotoCore/Commands/`: `JSONValue`, `CommandRegistry` (with
  `CommandSpec`, `CommandParameter`, `CommandArguments`, `CommandEnvironment`,
  `CommandError`), `CommandLineInterface`, `RenderCommands`, `LibraryCommands`.
- `Sources/PhotoCore/Edits/AdjustmentParameters.swift`, `AdjustmentEdits.swift`,
  `Kernels/RuntimeKernels.swift`; `Catalog/LibraryLock.swift`;
  `Preview/RenderEngine.swift` (software renderer request and check).
- `Sources/PhotoCLI/main.swift`; `Sources/PhotoBench/KernelBenchmark.swift`.
- `Sources/PhotoApp/Model/LibraryModel.swift`: holds the lock.
- Tests: `CommandTests.swift` (with `AdjustmentParameterTests`).

## Suite time

Whole suite: 319 tests in about 9.4 s (8.9 … 10.1 s over ten runs). New
suites, run alone: goldens 0.27 s, harness
1.0 s (it renders every case twice), references 0.11 s, kernels 0.98 s
(mostly the CPU blur reference in a debug build), commands 0.16 s.

## Notes

- The CPU-heavy reference tests made an existing timing test
  (`reservedSlotsStartOnlyUrgentJobs`) fail about once in ten runs; it now
  waits for its jobs to start instead of sleeping a fixed 50 ms.
- With the Swift Build backend, changing a public initializer's parameters
  left a stale object in `PhotoApp` (an undefined `RenderEngine.init` symbol
  at link time). Deleting that target's folder under
  `.build/out/Intermediates.noindex/PhotoWorkspace.build/Debug` fixed it.
- Third-party code: none. LightCraft (MIT or Apache-2.0) was read, in a
  scratch folder outside the repository, for its command registry and its
  CPU-against-GPU equivalence tests; nothing was ported, so there is no
  `THIRD_PARTY_NOTICES.md`.
