# CLAUDE.md

Guidance for working in this repository: a native macOS photo DAM and RAW editor.
The product name is a placeholder (see Naming rules); refer to it as "the app".

## Clean-room constraint

This is an original application. Do not copy names, icons, assets, UI strings, or
code from any existing photo application, and do not aim for a pixel-level clone
of any interface. The workflow (projects, albums, stacks, non-destructive
versions, fast culling) is a common genre; the design and code are our own.

## Commands

```bash
swift build
```

```bash
swift test
```

```bash
swift test --filter BrandingTests
```

```bash
Scripts/build-app.sh
```

```bash
Scripts/build-app.sh importer
```

```bash
swift run -c release photobench help
```

```bash
swift run photocli help
```

```bash
UPDATE_GOLDENS=1 swift test --filter GoldenTests
```

```bash
LARGE_RENDER_TESTS=1 swift test --filter "LargeRenderTests|LargeBrushTests"
```

```bash
CAMERA_RAW_SAMPLE=path/to/file.RW2 swift test --filter CameraRAWMaskTests
```

The build does not depend on Xcode: everything goes through SwiftPM, and tests
use Swift Testing (not XCTest). `Scripts/build-app.sh` assembles the `.app`
bundle (Info.plist from `Branding.xcconfig`, String Catalog compiled by the
`catalog-strings` tool, ad-hoc signature); `importer` builds the standalone
importer and `all` builds both.

The app's minimum is macOS 15, but the SDK it links decides its look: linked
with the macOS 26 SDK or later it runs in the current design on 26+, linked
with an older one in the earlier design. `build-app.sh` needs Xcode 26 or
later and fails if the executable records an older SDK. It passes the SDK to
clang as `-isysroot` when linking: SwiftPM's default build system (Swift
Build) gives clang only `--sysroot`, so a plain `swift build` executable
records its minimum (15.0) as its SDK version (`vtool -show-build`). Use the
bundle, not `swift run`, to look at the UI.

To check UI changes without screen recording permission, run the bundle's
executable with `--library-root <folder> --debug-script "wait 2; snapshot /tmp/a.png; quit"`
(see `Sources/PhotoApp/Model/DebugScript.swift` for every command: keywords,
albums, sidecars, the import window, folder drops…). In the current design
`snapshot` leaves the glass panes (sidebar, inspector, toolbar items) blank:
it renders the window's layers, which cannot draw them. The content area
comes out right; check the panes with `buttons`, `hit` and `print`.
`accessibility <role>` lists what the grid and loupe tell VoiceOver and runs
their actions; SwiftUI builds its accessibility tree only for an attached
assistive app, so SwiftUI elements (the import tiles) are not found this way.
The script turns off `groupsByEvent` and opens an undo group only around
commands that change photos (`changing` in `DebugScript`): a new command that
changes photos without one makes `registerUndo` raise an Objective-C
exception, which unwinds through Swift and crashes later. App
launch options must always take a value: AppKit treats a stray argument as a
document and then does not open the main window. A process started from a shell is not the active app, so it has
no key window: scripted keys go straight to the window, and local event
monitors (the video loupe's) never see them. To test those, launch with
`open -W -n --stdout <log> build/*.app --args …`, which activates the app.
macOS may refuse to activate it while you use another app (`print responder`
then shows `key nil`); running `open build/<name>.app` again a few seconds in,
while the script waits, brings it forward. Menu state needs a key window:
`menuitems <text>` prints items as AppKit sees them (after the update an
opening menu gets), `menupress <title>` runs one. `menukey` turns grouping
undo by event on while its posted keys are handled.
A FAT32 disk image (`hdiutil create -fs "MS-DOS FAT32" …`, then `hdiutil
attach`) stands in for a camera card. `docs/PROFILING.md` has the benchmark
commands.

`photocli` renders, queries and edits a library without the app (every
command prints one JSON object; see `docs/PHASE5_PLAN.md`). Its write
commands refuse while the app has that library open (`LibraryLock`), so
quit the app (or use another `--library-root`) before `develop`, `rate`,
`flag` or `label`.

## Checking image code

- **Goldens** (`Tests/PhotoCoreTests/Goldens`, `GoldenTests`) pin every
  module's rendering of the synthetic `TestScene`s. When one fails, open the
  side-by-side image the failure names (expected | actual | 8× difference)
  and say in one sentence what differs before touching code. A change that is
  meant to alter rendering bumps `PreviewCacheKey.currentPipelineVersion` and
  updates the affected goldens (`UPDATE_GOLDENS=1`, which rewrites only goldens
  outside their tolerance and prints each one) in a separate commit with a one-line reason. Never loosen a
  tolerance or update a golden only to make a test pass. `GOLDENS_REPORT=1`
  prints every difference.
- **RAW goldens** are compared only on the macOS build and RAW decoder
  version that made them: each has a `<name>.fingerprint.json` beside it
  (written by `UPDATE_GOLDENS=1`), and elsewhere the test is skipped with
  both named. Apple's decoder changes between releases; `RAWDecodeTests`
  checks each setting's direction or order everywhere instead.
- **CPU references** (`Tests/PhotoCoreTests/Reference`, `ReferenceTests`):
  write the math in plain Swift (no Core Image) in the working space, and
  check the renderer against it with a tolerance derived from the formats
  involved (half float: 2⁻¹¹ per rounding). Derive expected values from the
  reference; do not tune constants by trial and error.
- Goldens render on the GPU: Core Image has no software renderer on Apple
  silicon (the option needs OpenCL).

Commands meant for the user to paste run in zsh: keep scripts POSIX sh or zsh
compatible and never put `#` comment lines inside pasted command snippets.

## Layout

- `Sources/PhotoCore` — library with no AppKit/SwiftUI: branding, catalog
  (GRDB), import, metadata, `Edits/` (edit stack, adjustments, renderer, live
  render session, look-up tables, `Masks/`: local adjustments, mask shapes,
  the brush rasterizer), `Presets/` (preset files, Lightroom preset
  reading and mapping), preview pipeline, `Sidecars/` (XMP),
  `CardImport/` (templates, copying), `Export/` (rendering, naming, metadata
  and watermarks for exports), `Suggestions/` (Vision), `Video/`.
  Everything testable lives here.
- `Sources/PhotoUI` — UI shared by both apps: `Import/` (the import window:
  toolbar, options inspector, the `NSCollectionView` grid of `ImportCell`s
  with check boxes, its model, `ImportCommands` and debug-script commands),
  `Grid/` (`UniformGridLayout` and the cell images: symbols, stars, type
  badges), `TemplateField` (the naming template token field; `TemplateParts`
  and `TemplateToken` in PhotoCore split and read templates), `WindowModal`
  (panels and alerts attached to the key window), `QuitGuard` (asks before
  a quit stops an import or export; the rule is `QuitConfirmation` in
  PhotoCore), `ToolbarMetrics` (custom toolbar items' inset and status
  lines), `Palette` (dynamic colors
  from `PaletteSpec` in PhotoCore), `LaunchOptions`, and the String Catalog
  (`Resources/Localizable.xcstrings`).
- `Sources/PhotoApp` — SwiftUI app shell (one library window with a
  customizable toolbar, `LibraryCommands` on focused values, review mode),
  AppKit grid (`NSCollectionView`) and loupe (with the crop and mask
  overlays), inspector (Info and Adjust tabs, the Masks heading), sidebar,
  smart album editor, and the sheets on the library window: Export, the
  look-up table browser (Import and Manage as pages), the preset manager.
- `Sources/PhotoImporter` — the standalone importer: the same import window
  with no library (copies only; presets and options in its own preferences).
- `Sources/PhotoCore/Commands` — the command registry (`CommandRegistry`: one
  `CommandSpec` per command with a parameter schema and a JSON handler) and
  `CommandLineInterface` (argv parsing and the output contract).
- `Sources/PhotoCLI` — `photocli`, a thin dispatcher over the registry
  (PhotoCore only, no AppKit or SwiftUI).
- `Sources/PhotoFixtures` — synthetic JPEG/HEIC and Bayer DNG writers, and the
  `TestScene`s for goldens and references (tests, benchmarks).
- `Sources/PhotoBench` — synthetic library generator and headless profiling.
- `Sources/StringCatalogCompiler` — `.xcstrings` to `.strings`/`.stringsdict`.
- `Sources/AppIconCompiler` — `Support/AppIcon.png` to an `.iconset` (masked to the
  macOS icon shape); `build-app.sh` turns it into `AppIcon.icns` with `iconutil`.
- `Tests/PhotoCoreTests` — Swift Testing suites; `Goldens/` (16-bit PNGs read
  from the source tree) and `Reference/` (CPU implementations).
- `docs/PHASE1_PLAN.md` … `docs/PHASE6_PLAN.md` — design decisions per phase.
- `THIRD_PARTY_NOTICES.md` — math ported from other projects, with notices.

## Naming rules

- The product name is not a code identifier. Modules and types use neutral,
  role-based names (`PhotoCore`, `PhotoApp`, `Catalog`, `PreviewService`, …).
- `Sources/PhotoCore/Branding/AppBranding.swift` is the only Swift file that may
  contain brand values. `Branding.xcconfig` holds the build-setting copies
  (`PRODUCT_NAME`, `PRODUCT_DISPLAY_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`,
  `PRODUCT_URL_SCHEME`, `PRESET_FILE_EXTENSION`). `BrandingTests` enforces both
  and fails on any leak.
- User-facing strings go through `Sources/PhotoUI/Resources/Localizable.xcstrings`
  and refer to the product name only via a `%@` argument filled from
  `AppBranding.displayName`. Nothing extracts strings automatically: add new
  keys to the catalog by hand; `LocalizationTests` fails on any UI literal
  without an entry.
- Persisted data never embeds the product name: catalog file and folder names,
  table and column names, JSON keys and edit-operation identifiers are generic.
  Only the top-level Application Support and Caches folder names are branded.
- Renaming is documented in `RENAMING.md`; `DataDirectoryMigrator` moves the
  data directory on first launch after a rename.

## Architecture rules

- **Referenced masters only.** Originals are never moved, copied or modified. The
  catalog stores volume, path relative to the volume, SHA-256 content hash, size,
  mtime and metadata.
- **Volumes can go offline.** Masters on external or network volumes that are not
  mounted show as offline; catalog rows are never deleted because a volume is
  missing. Volumes are matched by identity (UUID) so a remount elsewhere is found.
- **Catalog** is SQLite via GRDB with numbered migrations from day one. Tables:
  `volume`, `project`, `image` (master), `version`, `album`, `albumMember`,
  `stack`, `stackMember`, `keyword`, `versionKeyword`, `adjustmentPreset`
  (with `collection` and `groups`, null for all), `lookTableCollection`,
  `lookTableEntry`. Ratings 0–5, flags
  (-1 reject, 0 none, 1 pick) and color labels (0–7) live on versions.
  Never edit an existing migration; add a new one.
- **Edit stack**: each version stores an ordered, versioned JSON list of
  operations. A stored stack this build cannot read (a newer schema, damaged,
  over `MaskLimits`) is never written over: the catalog refuses the write
  and the editor turns editing off. The render hash covers enabled operations only. `Adjustments`
  is the typed view of it: one operation per module, defaults left out (so a
  reset gives back the identity hash), unknown operations kept. A group of
  controls turned off keeps its operations with `isEnabled` false;
  `Adjustments.effective` is what renders.
  `AdjustmentRenderer` renders in a fixed order with built-in Core Image filters
  and generated tables. Custom kernels are possible without a Metal build
  step: `RuntimeKernels` (a spike, not used by the renderer) compiles Metal
  source at run time into `CIImageProcessorKernel`s; see
  `docs/PHASE5_PLAN.md` for its accuracy, speed and the alternatives. Each
  module describes its parameters (`AdjustmentParameters.swift`); keep that
  in step when adding one (`AdjustmentParameterTests`). RAW
  decode settings go to `CIRAWFilter` only when set, so an identity stack
  renders exactly as before; changing that, or any rendering of an existing
  stack, needs a `PreviewCacheKey.currentPipelineVersion` bump.
- **Editing** happens in the loupe: `AdjustmentEditor` renders live frames
  through a `LiveRenderSession` (decoded master reused per frame), saves once
  per gesture as one undo step, and hands the last frame to the memory cache
  as the new edit's preview. Edits are per file (not shared by a RAW+JPEG
  pair) and are not written to XMP sidecars. Look-up tables are copied into
  `Library/LUTs/<sha256>.cube` and listed in flat collections (built-in ones
  generated in code); removing them from the library never deletes a file.
- **Preview cache** is tiered (`thumbnail` for the grid, `preview` for the loupe),
  lives under the Caches folder on the local disk, is keyed by
  content hash + edit-stack render hash + tier + pipeline version, is generated on
  demand, and can be deleted at any time.
- **Rendering**: Core Image with `CIRAWFilter`, one Metal-backed `CIContext`,
  extended linear Rec. 2020 working space, output converted to Display P3.
  Caches are SDR. On EDR displays the loupe swaps in an HDR render from the
  master (half-float extended linear Display P3, tagged with its content
  headroom), memory-only, for HDR content only: floating-point DNGs, gain maps,
  HLG/PQ. Camera raws stay SDR. The layer enables extended range only while it
  shows an HDR image.
- **Concurrency**: Swift 6 strict concurrency. Import and preview work is async
  and cancellable; no image decoding on the main thread. Images are fully
  decoded and converted to the window's color space (BGRA) before they reach
  layers, otherwise Core Animation converts them on the main thread at commit.
- **No SwiftUI `ScrollView` under the toolbar.** On macOS 26+ in the earlier
  design (the app linked with the macOS 15 SDK) such a scroll view (the
  inspector's) swallowed every click. The SDK, not the minimum, chose that
  design, but older systems still get it, so keep `AppKitScrollView`;
  inspector buttons are `AppKitButton`s, which the debug script's `click` can
  drive.
- **Menus** read `LibraryMenuContext` / `ImportMenuContext` through
  `@FocusedValue`, published by the window with `focusedSceneValue`; never a
  model passed into `Commands`, which SwiftUI does not refresh. Bare-key items
  (culling, `Z`, `\`, `C`, ⌫) are shown but the grid and loupe handle the
  keys (AppKit offers an unmodified key to the first responder first); they
  are enabled only while the grid, loupe or video loupe has the keyboard.
  Text fields that hand the keyboard back on Return or Escape post
  `.browserShouldTakeFocus` with their window.
- **Metadata** goes through the `MetadataReader` protocol. ExifTool
  (`-stay_open` subprocess) is the default when installed; ImageIO is the
  in-process fallback; videos always go through AVFoundation.
- **RAW+JPEG pairs** share culling, keywords and albums: every catalog write on a
  pair's default version also reaches the partner (`ImagePairing`). Grid
  queries resolve pairs in memory, never by joining `imagePair`.
- **XMP sidecars**: the catalog is the source of truth. Originals are never
  written, sidecars only (`IMG_1.xmp`, shared by a pair, owned by its RAW).
  SQLite triggers queue every change to synced values in `sidecarQueue`;
  `SidecarSync` writes when the file is unchanged since its baseline and
  otherwise flags it for review. Never overwrite a sidecar another app changed.
- **Undo** uses the window's undo manager. Each step records exactly what it
  changed and runs on the model's ordered write chain (`persist`), so an undo
  runs after the change it reverses.
- **Copying imports** verify every copy (re-read around the file cache, hash
  compared) before it counts; only verified sources may be deleted.
- **Export** renders through the same `PreviewGenerator` at full resolution,
  then resizes, sharpens and watermarks. The library's descriptive fields and
  keywords win over the master's; ratings and labels are never written. File
  names are decided for the whole batch before anything is written, and each
  file is moved into place only when it is complete.
- **Standalone importer** shares the import window, model and `CopyImporter`
  with the library app; never fork them. Without a catalog (`CardImportModel.library`
  nil) it copies only, writes preset metadata into new sidecars (never into
  existing ones), and does not mark duplicates.
- **Dependencies**: GRDB only. Ask before adding anything else. Apple frameworks
  (Vision, AVFoundation, AVKit) are fine.

## Scope so far

Phase 1: importer, grid, loupe, culling (rating, flag, label), sidebar filters,
tests, profiling.

Phase 2: file names and type badges in the grid, RAW+JPEG pairs, keywords
(entry with autocomplete, inspector, sidebar, on-device suggestions), undo,
more metadata columns, albums, smart albums and the Dates tree, XMP sidecars
with review of outside changes, copying imports from cards and folders, videos
(catalogued and played).

Phase 3, first pass: global adjustments in the loupe's Adjust tab (profile,
white balance, exposure with Auto, tone, presence, tone curve with histogram,
sharpening, noise reduction, color grading), an Effects heading (look-up table
collections with a browser window, import and management; vignette; grain),
per-group on/off check boxes, before/after, copy/paste and presets.
Presets, second pass: a Color Mixer (hue, saturation and luminance of eight
hue bands), preset collections, presets that apply only some groups,
preset files with their look-up tables embedded (`PresetFile`: xz-compressed
JSON; the extension is a brand value, declared in Info.plist so the Finder
opens them in the app, which imports them), and
import of Lightroom `.lrtemplate`, `.xmp` and `.dng` presets
(`Sources/PhotoCore/Presets/`: `CameraRawSettings` reads them,
`CameraRawMapping` converts and reports what has no equivalent).
Folders dragged from Finder onto the library window import in place, one
project per folder, queued behind each other (`FolderImportQueue`).

Phase 4, first pass: export (File ▸ Export…, ⇧⌘E) of the selection to a
folder as JPEG or 8/16-bit TIFF in sRGB, Display P3, Adobe RGB or ProPhoto
RGB; templated names; full size, fit, long or short edge or percentage with
output sharpening and PPI; four metadata levels; a PNG watermark placed by
anchor; export presets (`exportPreset` table); background export with
progress.

Crop, rotate and straighten: a `crop` operation (`Edits/Crop.swift`) applied
first: quarter turns, straightening about the center, then a unit rectangle
of the turned frame. Without it a photo keeps its decoder's frame, which for
some raws is the camera's aspect crop; with it raws decode the whole sensor
(`CameraFrame` undoes the Olympus/OM System `AspectFrame` or the Panasonic
RW2 crop tags in an in-memory copy).
`CropGeometry` keeps the rectangle on the straightened image. Editing is a
session in `AdjustmentEditor` shown by `CropOverlayView` over the loupe and
saved on Done. Rotate outside a session commits at once (`Crop.turned`: a
raw without a crop takes its camera frame as the rectangle, since any crop
decodes the whole sensor). Crop is not an `Adjustments.Group`: presets never
carry it. Grid batch commands (paste, presets, Auto Exposure, Reset All,
Rotate) go through `BatchEdit` (videos, offline masters when read) and
`changeAdjustments`, one undo step.

Info tab metadata: title, description, alt text, extended description,
copyright, usage terms and the creator's contact details (IPTC Core and
Extension, `Catalog/Descriptions.swift`), edited for the whole selection as
one undo step each, kept on `image`, synced to sidecars and written on export.
Reading a file again only fills empty descriptive fields; the library's win.

Phase 5: golden-image tests and CPU references for the renderer, `photocli`
over a command registry (render, adjustments, query, develop, rate, flag,
label, export), the library lock, and a spike on runtime-compiled GPU kernels.

Phase 6: local adjustments with masks (linear and radial gradients, brush,
luminance and color ranges; add, subtract, intersect, invert; Amount; local
exposure, tone, white balance, presence and sharpening). Masks live in one
`localAdjustments` operation as objects (`EditParameter.object`, schema 2
for stacks that hold one), in the mask frame (the oriented decode before
crop), read strictly and never written over when unreadable. Presets and
paste leave them out. See `docs/PHASE6_PLAN.md`.

UI redesign (`docs/UI_REDESIGN.md`, steps 1–15): built with the macOS 26
SDK, VoiceOver for the grids and loupe, a menu bar on focused values,
context menus, a customizable toolbar in place of the bottom bars, the loupe
caption, system sidebar and inspector, a dynamic palette with Increase
Contrast variants and dark only in the library window, Export, look-up
tables and presets as sheets, the Import window on a toolbar, an options
inspector and the shared grid, token template fields, and review mode (F).

Not yet: AI masks, healing, lens corrections, DNG export, ML
denoising, `.dcp` profiles, general (hand-made or burst) stacks, hierarchical
keywords, PTP cameras, a second backup destination, writing metadata into
originals.
