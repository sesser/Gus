# CLAUDE.md

Guidance for working in this repository: a native macOS photo DAM and RAW editor.
The product name is a placeholder (see Naming rules); refer to it as "the app".

## Workflow
See @docs/WORKFLOW.md

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
swift run -c release photobench scenes --output DIR
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

```bash
RAW_EDGE_SAMPLES=wide.RW2:longer.RW2 swift test --filter RAWEdgeSmearTests
```

```bash
RAF_SAMPLE=path/to/file.RAF swift test --filter LibRawFallbackTests
```

```bash
RAW_CONTEXT_SOAK=12000 swift test --filter RAWContextSoakTests
```

```bash
XTRANS_SAMPLES=a.RAF:b.RAF swift test --filter DemosaicXTransSampleTests
```

```bash
BAYER_SAMPLES=a.RW2:b.CR2 swift test --filter DemosaicTruthTests
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
exception, which unwinds through Swift and crashes later. A command whose
change is saved after an await (a measuring paste) must wait inside its undo
group (`waitForBatchMeasuring`). App
launch options must always take a value: AppKit treats a stray argument as a
document and then does not open the main window. A process started from a shell is not the active app, so it has
no key window: scripted keys go straight to the window, and local event
monitors (the video loupe's) never see them. To test those, launch with
`open -W -n --stdout <log> build/*.app --args --library-root <folder> …`,
which activates the app. Every launch passes `--library-root`: without it
the app opens the real library, whatever its bundle identifier (that only
separates preferences). macOS may refuse to activate it while you use
another app (`print responder` then shows `key nil`); bring the running
process forward by its ID (`pgrep -n -x <executable>`, then System Events:
`set frontmost of (first process whose unix id is <pid>) to true`). Never
run `open` on the bundle again for this: if the scripted copy has already
quit, that starts a new one on the real library. Menu state needs a key window:
`menuitems <text>` prints items as AppKit sees them (after the update an
opening menu gets), `menupress <title>` runs one. `menukey` turns grouping
undo by event on while its posted keys are handled.
A FAT32 disk image (`hdiutil create -fs "MS-DOS FAT32" …`, then `hdiutil
attach`) stands in for a camera card. `docs/PROFILING.md` has the benchmark
commands.

`photocli` renders, queries and edits a library without the app (every
command prints one JSON object; see `docs/archive/PHASE5_PLAN.md`, and
`docs/archive/PHASE6_PLAN.md` for `mask list`, `mask add`, `mask set` and
`mask remove`). Its write commands refuse while the app has that library
open (`LibraryLock`), so quit the app (or use another `--library-root`)
before `develop`, `rate`, `flag`, `label`, `mask add`, `mask set` or
`mask remove` (`--dry-run` on `develop` and the mask commands changes
nothing and needs no lock).

## Claude Code setup

`.claude/` is checked in so every contributor starts from the same baseline:

- `.claude/settings.json` allows the commands above without a prompt
  (`swift build`, `swift test` with its env-var variants, `Scripts/build-app.sh`,
  `swift run photocli`, `swift run -c release photobench`, `vtool -show-build`).
  `UPDATE_GOLDENS=1` always asks first, since it rewrites goldens (see
  Checking image code), and `xcodebuild` is denied. Put personal additions in
  `.claude/settings.local.json`, which is not committed.
- `.claude/agents/` holds five project subagents. Product decides what to
  build, design decides how it looks, engineering builds it, and code review
  and QA check it before the pull request.

| Agent | Use it for | Tools |
| --- | --- | --- |
| `product-manager` | Turning an idea into requirements: a PRD with testable acceptance criteria and non-goals in `docs/features/<slug>/prd.md`. Keeps `docs/roadmap.md` (the order of open GitHub issues; every feature and bug is an issue first, see `docs/WORKFLOW.md`). As the last commit on the feature branch, after the owner's sign-off and before the pull request (Ship mode), marks the feature shipped and updates `README.md` and this file's "Scope so far" and "Not yet". Does not design UI or write code. | Read, Write, Edit, Grep, Glob, WebSearch, WebFetch. Never builds. |
| `apple-ui-designer` | Designing or reviewing windows, toolbars, sidebars, menus, inspectors and sheets against the HIG; deciding where a command lives (menu bar, toolbar, context menu, shortcut). Writes `docs/features/<slug>/design.md` and, after implementation, `review.md`. | Read, search, web, edit docs. Never builds. |
| `swift-macos-engineer` | Implementing against the PRD and design, bug fixes, refactors and tests. Keeps `docs/features/<slug>/status.md` and `docs/USER_GUIDE.md`. Builds and tests after each step. | Full: read, edit, shell, web. |
| `code-reviewer` | Reviewing a branch before its pull request for correctness, concurrency and this file's rules. Writes `docs/features/<slug>/code-review.md`; says when `/security-review` should also run. Never edits code. | Read, search, shell (git, build, test), edit its own file. |
| `qa-tester` | Mapping each acceptance criterion to a test or a debug-script check, running them against a copy of the bundle, and listing what only a person can check. Writes `docs/features/<slug>/qa.md`. Never edits code. | Read, search, shell, edit its own file. |

How to work with them, who owns which file, and how questions go back to
their owner: see `docs/WORKFLOW.md`. Work done before that workflow was
recorded in `docs/UI_REDESIGN.md` and the phase plans
(`docs/archive/PHASE1_PLAN.md` … `docs/archive/PHASE6_PLAN.md`); they stay
the historical record of those decisions.

This file's rules win over anything in an agent's prompt: GRDB is the only
package dependency (LibRaw is vendored source: see Dependencies), goldens are updated only on purpose, brand values stay in
`AppBranding.swift`, and work goes on a branch off `develop`.

Commits must be signed: branch rules on `develop` require it, and an unsigned
commit blocks the merge. Every agent that commits keeps the repository's
signing on: never `--no-gpg-sign` or `-c commit.gpgsign=false`. Rewriting
history (`filter-branch`, `rebase`, `commit --amend`) drops or invalidates
signatures, so after any rewrite re-sign the commits (`git rebase -r -f -S
<base>`) and check that GitHub shows them verified before pushing.

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
  the brush rasterizer; `Spots/`: heal and clone spots, their renderer and
  automatic source), `Presets/` (preset files, Lightroom preset
  reading and mapping), preview pipeline, `Sidecars/` (XMP),
  `CardImport/` (templates, copying), `Export/` (rendering, naming, metadata
  and watermarks for exports), `Suggestions/` (Vision), `Video/`.
  Everything testable lives here.
- `Sources/CLibRaw` — LibRaw 0.22.3, vendored (LGPL 2.1, `THIRD_PARTY_NOTICES.md`):
  upstream's `src`, `internal` and `include/libraw`, built by `Package.swift` and
  called only from `Preview/LibRawDecoder.swift`, for raws the system's RAW
  decoder gives no image for. Never edit it.
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
- `docs/WORKFLOW.md` — the agent workflow and who owns which file;
  `docs/roadmap.md` — Now, Next, Later (links to GitHub issues), Dropped; closed issues are the Shipped record;
  `docs/features/<slug>/` — each feature's PRD, design, status and reviews.
- `docs/archive/PHASE1_PLAN.md` … `docs/archive/PHASE6_PLAN.md` — design
  decisions per phase, before the workflow (historical).
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
  `smartAlbum`, `stack`, `stackMember`, `keyword`, `versionKeyword`,
  `keywordSuggestion`, `imagePair`, `importRun`, `importPreset`,
  `metadataSync`, `sidecarQueue`, `adjustmentPreset`
  (with `collection` and `groups`, null for all), `lookTableCollection`,
  `lookTableEntry`, `exportPreset`. Ratings 0–5, flags
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
  `AdjustmentRenderer` renders in a fixed order, the Lens heading's alignment
  and fringe removal first, on the decoded image before the crop, with built-in
  Core Image filters and generated tables. Custom kernels are stitchable Core
  Image kernels compiled from Metal source at run time
  (`Kernels/LensKernels.swift`; `StitchableKernels` is the spike), each in a
  Metal library of its own: Core Image ran one kernel of a library for another.
  `RuntimeKernels` stays a spike; see `docs/archive/PHASE5_PLAN.md` for its
  accuracy, speed and the alternatives. Each
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
  shows an HDR image. Every `CIRAWFilter` whose image is rendered takes it
  from `RAWDecodeGraph.output(of:)`, which gives each decode a render graph
  of its own: the decoder's lens correction reads a table that is not in Core
  Image's graph digest, and a context reusing one decode's prepared graph for
  another smeared its edges. This rests on Core Image behavior observed on
  macOS 27.2 only, so run `RAWEdgeSmearTests` (two real wide-angle raws) on
  every new macOS.
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
- **Dependencies**: GRDB, and LibRaw 0.22.3 vendored in `Sources/CLibRaw` (LGPL 2.1;
  `THIRD_PARTY_NOTICES.md`; never edit the vendored tree), which decodes only raws
  the system's RAW decoder gives no image for (`LibRawDecoder`, the fallback in
  `PreviewGenerator.decode`; `SystemRAWDecoder.reads` is the one test of which
  decoder a raw gets).
  Ask before adding anything else. Apple frameworks (Vision, AVFoundation,
  AVKit) are fine.

## Scope so far

Phase 1: importer, grid, loupe, culling (rating, flag, label), sidebar filters,
tests, profiling.

Phase 2: file names and type badges in the grid, RAW+JPEG pairs, keywords
(entry with autocomplete, inspector, sidebar, on-device suggestions), undo,
more metadata columns, albums, smart albums and the Dates tree, XMP sidecars
with review of outside changes, copying imports from cards and folders, videos
(catalogued and played).

Phase 3, first pass: global adjustments in the loupe's Adjust tab (a profile
group, removed later by #219; white balance, exposure with Auto, tone, presence, tone curve with histogram,
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
paste leave them out. See `docs/archive/PHASE6_PLAN.md`.

UI redesign (`docs/UI_REDESIGN.md`, steps 1–15): built with the macOS 26
SDK, VoiceOver for the grids and loupe, a menu bar on focused values,
context menus, a customizable toolbar in place of the bottom bars, the loupe
caption, system sidebar and inspector, a dynamic palette with Increase
Contrast variants and dark only in the library window, Export, look-up
tables and presets as sheets, the Import window on a toolbar, an options
inspector and the shared grid, token template fields, and review mode (F).

Loupe film strip (`docs/UI_REDESIGN.md` §11, issue #25, PR #27): the
source's photos in a strip between the loupe and its caption, the focused
photo centered, resized in steps by a drag handle, View ▸ Show / Hide Film
Strip (⌥⌘B), never shown in review (`Loupe/FilmStrip*.swift`,
`FilmStripGeometry`).

UI reconciliation (`docs/features/ui-redesign/`, design.md §6 E1–E28, PR
#34): each source's own empty state, Adjust tab states as content-unavailable
views, Export enabled only when the targets include a photo, export results
in Activity only (no alert), one File ▸ Stop (⌘.) naming the newest job, one
Edit ▸ Deselect All (⇧⌘A) shared with the import window, View ▸ Play / Pause
and a video loupe context menu, Adjust ▸ Import Look-Up Tables…, Reset Crop
and Show / Hide Mask Overlay, one set of field labels (`FieldLabel`), delete
confirmations for presets, and no dead Help item (Help ▸ Search stays).

Sharpening map (`docs/features/sharpen-mask-preview/`, PR #37): the loupe
shows where Sharpening's Masking lets sharpening through, as a live estimate
while values change and at full resolution once input pauses
(`Edits/SharpeningMap.swift`). A view only: never saved, never in previews
or exports.

Machine learning noise reduction for raws (`docs/features/ml-denoise/`, PR
#39): `noiseReduction.machineLearning` in the Noise Reduction group decodes
with the macOS 27 RAW decoder's version 9 (`9.dng` for DNG, `9` for camera
raws; no model shipped, and the app never starts the model's download). Off
by default; stacks that don't ask for it decode with the pinned pre-9
default, so no existing render changed. Where it can't apply (before macOS
27, camera not supported, decode failed) the photo renders classically,
keeps the setting and says why (`MachineLearningNoiseReduction`); those
fallback previews stay in memory only. A missing model can't be told apart
from a failed decode yet (RI-E6).

Library launch guard (`docs/features/library-launch-guard/`, bug fix, PR
#47): a test launch without `--library-root` is refused before anything in
the standard data or cache folders is opened or created. A test launch is
a bundle whose identifier isn't `AppBranding.bundleIdentifier` (no bundle,
as with `swift run`, included) or one with `--debug-script` or
`--benchmark-scroll`. Refused: the reason on standard error, an alert
unless the launch is scripted, then exit 64 (`Launch/LibraryLaunchGuard.swift`
in PhotoCore, asked first by `AppLauncher`, the app's `@main`;
`LibraryModel.open` checks again). `photocli`, `photobench` and the
standalone importer are not guarded.

Chromatic aberration and color fringes (`docs/features/chromatic-aberration/`,
PR #48): a Lens heading in the Adjust tab with two groups, applied to the
decoded image before the crop (`Edits/LensCorrections.swift`,
`LensRenderer.swift`, `Kernels/LensKernels.swift`). Color Fringes
(`colorFringes`) grays up to two colors near high-contrast edges, each with a
Tolerance, filled by picking from the photo (`FringePicker`) or from a short
list, with a Fringe Map. Color Alignment (`colorAlignment`) measures red/cyan
and blue/yellow edges once and stores the result, or takes hand-set values;
paste and presets measure each receiving photo, and one that can't be measured
is left unchanged. Off by default, so no existing render changed. The Pixel
Magnifier (`Edits/PixelMagnifier.swift`, `PixelMagnifierTool`;
`Loupe/PixelMagnifierView.swift`) shows the sampled image's full-resolution
pixels while picking, the pixel a click takes and its values, at a level kept
as a preference. A view only, built for other tools; only the fringe eyedropper
uses it so far. If the Lens kernels can't compile, the corrections are skipped
with no message (RI-CR1, a known limitation).

Sharp live frames at 100% (`docs/features/viewport-render-1to1/`, PR #49,
and the bug fix `docs/features/viewport-render-qa-findings/`): at 100% and
above, live frames are the visible area rendered from the full-resolution
decode at the photo's own scale, matching the render after letting go,
for every live change (sliders, curve, wheels, mask handles, brush, hover
previews, Show Original, mask overlay). RAW decode settings are soft while
moving and sharp on a pause; a drag may start soft, or go soft briefly while
a mid-drag decode change (Exposure or Highlights crossing 0) decodes. Never
blank; the histogram stays whole-photo. The full-resolution copy is held
only at covered zooms, with no memory cap. Below 100% nothing changed; no
rendering changed.

Edit history (`docs/features/edit-history/`, branch `feature/edit-history`):
a History panel at the foot of the inspector in the loupe (both tabs;
View ▸ Show / Hide History, ⌥⌘3; not in the grid or review mode) lists the
open photo's saved edits, newest first, with a label (the undo action name,
stored as text) and a time, the current state marked. Choosing an earlier
entry writes its snapshot back as a new entry and one undo step; nothing is
erased, and reverting to a state the photo already has does nothing. Stored
per version in `editHistory` (migration v14; the stack as LZFSE-compressed
JSON, at most 100 entries and 4 MiB per version, the newest always kept; no
clear command), written in the same transaction as the stack by
`setEditStack` and the batch writers (`historyLabel` is required), so undo,
redo, revert, batch actions and `photocli` edits all record entries. Edits
only; each file of a RAW+JPEG pair has its own history; a copied version
starts empty; history is gone with its version; unreadable stacks, videos
and offline masters have none (`Catalog/EditHistory.swift`,
`EditHistoryPanel.swift`; `Views/HistoryPanel.swift`). No rendering changed.
Manual checks P1–P6 are open (`docs/features/edit-history/qa.md`).

RAW edge smear (`docs/features/raw-edge-smear/`, bug fix, issue #55, branch
`bug/raw-edge-smear`): a fault in Core Image's RAW decoder made some raws
(4 of 54 in one Panasonic folder, by decoding order) come out with their
left and right edges smeared, because a context reused what it prepared for
an earlier raw whose lens correction table differed. Every RAW decode now
takes its image from `RAWDecodeGraph.output(of:)`, a pass-through clamp with
bounds of its own per decode (`Preview/RAWDecodeGraph.swift`), so the shared
contexts never reuse one decode's graph for another. Previews, live frames,
the 100% region, resized exports and Color Alignment's automatic measurement
are right whatever was rendered before. `PreviewCacheKey.currentPipelineVersion`
is 8: only so previews cached smeared are made again. No golden moved; healthy
photos are not byte for byte as before (about a quarter of cached previews
differ by 1 to 4 levels in a few thousandths of a percent of their values,
float rounding). Rests on undocumented Core Image behavior observed on macOS
27.2: run `RAWEdgeSmearTests` on real files on every new macOS. Shipped,
checks pending: P2 (macOS 26 and 15, whether the fault and the fix hold
there) in `docs/features/raw-edge-smear/qa.md`. Color Alignment values
measured automatically before the fix may be slightly wrong until measured
again.

Activity popover (`docs/features/activity-popover/`, bug fix, issue #56,
branch `bug/activity-popover-anchor`): clicking the toolbar's Activity item
with nothing running and unread messages made the item vanish and the
messages count as read, so its popover never opened. Now the item stays while
its popover is open and the messages are read when it closes, not when it
opens; while a job runs nothing changed. The rule is `ActivityLog.showsItem`
and `setPopoverShown` in PhotoCore (`Browser/ActivityLog.swift`; the app's
`ActivityToolbarItem` binds to `isPopoverShown`). The debug script gained
`activity open|close|snapshot|click`. No rendering changed. Shipped, checks
pending: P7 and P8 (overflow menu and window close; VoiceOver), P9 (second
click with a real mouse while a job runs) and P10 (macOS 15 and 26) in
`docs/features/activity-popover/qa.md`.

Library operations (`docs/features/library-ops/`, issue #61): rename a
project in place (sidebar, File ▸ Rename, row menu; one undo step; catalog
only, `Catalog/InPlaceRename.swift`); File ▸ Remove from Library… (⌘⌫)
removes the selected photos, either file of a RAW+JPEG pair taking both, an
original taking its copies and a copy removed alone leaving its original and
the master, and Remove Project from Library… removes a project, its photos and its own albums
and smart albums (`Catalog/LibraryRemoval.swift`: one transaction, all or
nothing, the sidecar queue paused around it). Both ask first, with no default
button (Return does nothing), say how many files go and that edits are lost,
and cannot be undone; files and sidecars are never touched, offline photos
can be removed, and a re-import gives new photos. Both are off while a folder
add or card import runs. File ▸ Show in Finder (⇧⌘R) reveals photos' masters
(one window per folder) or a project's source folder (`Browser/FinderReveal.swift`).
Cached previews of removed photos stay (#142). Shipped, checks pending: macOS
15 and 26 (confirmation keys, look) not checked by a person, in #82 and
`docs/features/library-ops/qa.md`.

Rename albums in place (`docs/features/rename-albums-in-place/`, issue #141):
albums rename in the sidebar row the way projects do (File ▸ Rename, the row's
context menu, Return; Return saves, Esc cancels, leaving the field saves; one
undo step, "Rename Album"). Projects and albums share one rename state and one
name rule (`Catalog/InPlaceRename.swift`: trims only, empty refused, no
length limit). A row that leaves the list during a rename (section hidden or
folded, sidebar hidden, review on) saves the typed name as one step. A renamed
row that moves stays selected and in view. The album Rename sheet is removed;
keywords keep their sheet (with the merge note) and smart albums keep Edit
Smart Album…. Catalog only: no migration, no pipeline bump. Known difference:
New Album still collapses inner spaces and cuts names at 200 characters, a
rename in place does not. Shipped, checks pending: P1–P6 (look, endings,
moving row, menu bar, row folded away during a rename including hiding the
sidebar, scrolling the field out of view) in #82 and
`docs/features/rename-albums-in-place/qa.md`.

Virtual copies (`docs/features/virtual-copies/`, issue #62): Duplicate makes a
copy of each selected photo (videos skipped and counted in Activity): another
version of the same master (not its default) with the original's edit stack as
a snapshot, one undo step, no migration, no pipeline bump. A copy has its own
edits, history, rating, flag, label, keywords and albums (seeded from the
original, then independent), is its own marked item in the grid, loupe, film
strip and review, is placed after its original when made, then sorts by its
own values, and counts everywhere photos are counted. A copy is stackless,
never joins a RAW+JPEG pair (copies are per file) and never touches a sidecar
or the sidecar review; export names it apart from its original; the smart
album rule "is a copy" finds them. Removing an original takes its copies (the
confirmation says how many); removing a copy leaves the original and the
master. Descriptive Info fields live on the image, so they are shared with the
original (editing one on a copy queues the original's sidecar), and keyword
suggestions are per master. Naming a copy, making it the default version and
`photocli duplicate` are not built. Shipped, checks pending: P1 to P5 in #82
and `docs/features/virtual-copies/qa.md`. Known and left: removing from the
library right after undoing Duplicate asks about copies already gone and
clears undo.

Side by side comparison (`docs/features/side-by-side-comparison/`, issue #63):
a state of the loupe, also in review mode (Esc leaves review first), not a
mode of its own. S (View ▸ Compare Side by Side / Stop Comparing) shows two
different photos, each with its saved edits, from two selected photos, from one
(with the photo last compared with, else the next comparable) or from the
loupe's photo; S again leaves and selects the pair on screen, and S once more
brings the same pair back. Exactly one photo is active (ring), A switches;
culling, keywords, albums, export and Show in Finder act on the active photo
with undo. Zoom and pan are linked by default (View ▸ Link Zoom and Position,
a preference); arrow keys or a film strip click replace the active side's
photo. Refused with an alert: a video, an offline photo, the two files of one
RAW+JPEG pair shown separately. No editing while comparing (the Adjust tab says
so; Remove, Paste, Apply Preset and Duplicate are off, Duplicate also gone from
the pane menu). A photo and its copy (#62) compare as two photos, with no
shortcut to compare with a copy; a copy shows its own name and the Copy badge in
the caption and VoiceOver. Undo or redo of a Duplicate never moves the focus
off the panes: an undo that removes a compared copy ends the comparison on the
remaining photo (on the active copy's original if both go); redo never changes
a comparison. Two photos only. Code in
`Browser/Comparison.swift`, `Loupe/ComparisonView.swift` and
`Model/ComparisonActions.swift`, rules in PhotoCore. Debug script: `compare`,
`compareclick`, `compare panbench`; `photobench compare` times and measures two
full-resolution renders. No migration, no pipeline bump, no rendering changed.
Known limitation #153 (linked, after ⌘= twice and a drag, the fitted photo's
zoom state can flip and Z goes to fit instead of 100%). Shipped, checks
pending: the AC7 hitch count (zero dropped frames panning two 24 MP raws, never
measured: display asleep), animations, a real mouse and trackpad, menus and
refusal-alert keys, looks, P7 (a copy beside its photo in a narrow window) and
P8 (Duplicate while comparing: keys, menus, undo and redo), in #82 and
`docs/features/side-by-side-comparison/qa.md`. The owner acknowledged the
merged result with #155 and #62 on 2026-11-12.

Export never overwrites a master (`docs/features/export-overwrites-masters/`,
bug fix, issue #160, branch `bug/export-overwrites-masters`): Replace in the
sheet and `photocli export --policy overwrite` could write an export over a
catalogued original (the project's own folder, a RAW's name matching its
pair's JPEG, a link to the folder, `IMG_1.JPG` against `IMG_1.jpg`). Now a name
that is a master's is never given to an export, and an existing file with a
master's size and SHA-256 is never replaced: the photo gets the next free
numbered name (`IMG_1-2.jpg`), written without replacing anything. Masters are
known by place (the whole catalog, each volume at its recorded mount and
wherever it is mounted now; folders resolved through links, names compared
as the file system does, a missing master's place kept) and by content (for
volumes the catalog can't recognize; an exact copy of an original is left
alone too). Ordinary existing files are still replaced; Keep Both and Skip
are as before. If the catalog can't be read, nothing is written. The
alert says how many of the files in the way are originals (four wordings);
title and buttons are unchanged. `photocli export` prints
`protectedMasters`. Rule in PhotoCore (`Catalog/MasterFiles.swift`,
`Export/ExportNaming.swift`, `ExportJob`), shared by the app and `photocli`.
Hashing reads one reused 1 MiB buffer. No migration, no pipeline bump, no
rendering changed. Known limits: a master another app changed since the
catalog last hashed it, on a volume the catalog can't recognize, is an
ordinary file and is replaced; a 0-byte master protects every empty file;
network volumes untimed; a file that becomes a master's between the check and
the write is replaced (accepted); Activity doesn't say when Replace numbered
photos. Open follow-ups: double Return can start two exports, and the count
before the alert can't be stopped; `photocli render --out` can overwrite a
master; the importer's hashing loops may hold whole files in memory;
`photocli` reads masters at the recorded mount path.

Raws macOS can't decode (`docs/features/raf-not-rendering/`, bug fix, issue
#161, branch `bug/raf-not-rendering`): on macOS 27.2 the system's RAW decoder
gave no image for some Fujifilm files (the X-E3's lossless compressed RAFs: a
black loupe, grey tiles, `undecodable` from `photocli`). Now, when and only
when the system decoder gives no image for a raw, `PreviewGenerator.decode`
falls back to the vendored LibRaw (`Preview/LibRawDecoder.swift`; order of
decoders in `PreviewGenerator.rawImage`). Raws the system decodes are
untouched, byte for byte, and nothing got slower. The one test of which kind a
file is, `SystemRAWDecoder.reads`, decides everywhere (Adjust tab, Auto White
Balance, live session, 100% renderer, fringe picker, Color Alignment). A LibRaw
photo is a rendered image like a JPEG: it renders, edits, exports and saves
history, but flatter than the system's, with White Balance As Shot, Auto and
Custom only and Temperature and Tint relative (a Kelvin value pasted onto it
is kept and does nothing, and the reverse) and no Color noise reduction; Use machine learning is dimmed ("Not available for this
camera."), and a pasted setting says it isn't applied and Luminance applies
instead. Fujifilm RAFs LibRaw decodes get the camera's own frame (6000x4000
for the X-E3) and the lens corrections the camera stored in the file
(distortion, lateral color, corner shading: `Preview/FujifilmRAF.swift`,
`EmbeddedLensCorrection.swift`, kernel `embeddedLens` in
`Kernels/LensKernels.swift`; math after darktable, GPL 3 or later), applied on
LibRaw's image before the crop, automatically, with no control. Other files
keep LibRaw's inset crop and get no corrections. Half-size decodes serve
thumbnails and previews (about 0.6 s); a full decode, for 100%, large exports
and tight crops, takes about 9 s for an X-E3 file (single-threaded). No
migration, no pipeline bump, no golden moved. Limits that are the owner's: a
raw over 150,000,000 sensor pixels is refused (`LibRawDecoder.maximumSensorPixels`);
the corrections are about 3 full-size pixels off the camera's own JPEG in the
outer quarter of the radius with the 35mm; files in a 1.25x crop mode are shown
uncorrected, in their frame (no sample to check); LibRaw's white level depends
on the frame's content (up to 0.4 EV between two frames of a scene); previews
cached by earlier builds of this branch stay until the preview cache is
deleted; the bundles carry no LGPL notices yet; no deflate or lossy DNGs (no
zlib or JPEG support in LibRaw here); no decoder badge or `photocli` field says
which decoder rendered. Shipped; the owner checked P1 to P7 (the window frame
and corners, the note's look, White Balance and Noise Reduction by hand, a
paste from an X-T3, switching photos, Custom from the Mode pop-up) by eye on
2026-11-15, everything fine (#82, `docs/features/raf-not-rendering/qa.md`).

About window (`docs/features/about-gus-dedication/`, issue #179, branch
`feature/about-gus`): the app menu's About and Help ▸ About open one window of
our own in both apps, replacing the system panel (`Sources/PhotoUI/About/`;
`AboutCommands` on `.appInfo` and `.help`, `AboutScenes`). It shows the version
and build from the bundle (left out with no bundle), a dedication naming the
project (Gus, also in the importer, whose menus, title and header keep its own
name), five entries (LibRaw, darktable, LightCraft, GRDB, ExifTool) each with a
sentence worded by what the project is to Gus (included, studied,
reimplemented, optional and not included), its license and a link (reported,
never opened, under the debug script; no network code), and Gus's copyright and
GPL 3-or-later statement. The one record is `Acknowledgements.all` in PhotoCore
(`About/`); `AcknowledgementConsistencyTests` fails when it disagrees with
`THIRD_PARTY_NOTICES.md`, the README's Credits or the package and vendored
source. View License buttons open a window with the project's section of
`THIRD_PARTY_NOTICES.md` or the whole `LICENSE`, read from the bundle's
`Contents/Resources` (`BundledLicenses`), byte for byte, never typed into Swift
or the String Catalog; with the files absent there are no buttons. Today's
bundles don't carry the files: #172 puts them there (this feature's packaging
test). The quit question now goes on the key or main window, never an About or
license window, and on the front-most sheet of a window that shows one
(`QuitConfirmation.host`, `frontSheet`). The notices gained GRDB (with its
second MIT notice and a note on three Swift.org-derived files whose Apache 2.0
text is not reproduced: the owner's open question) and ExifTool, and the
Credits an ExifTool line. No migration, no pipeline bump, no rendering changed.
Known: LibRaw's View License shows its notice, not the LGPL text (RI-E1); the
`Info.plist`s have no `NSHumanReadableCopyright`. Shipped; the owner checked P1
to P9 (look in light and with Increase Contrast, Keyboard Navigation, no
network, a real link click, resizing, menus by eye, Esc, ⌘W and ⌘F with a real
keyboard, a real ⌘Q during an export from About and with a sheet up, ⌘F on a
non-Latin layout) by eye on 2026-11-15, everything fine (#82,
`docs/features/about-gus-dedication/qa.md`). AC7's and AC13's packaging halves
still wait on #172.

White balance and baseline look across decoders
(`docs/features/white-balance-across-decoders/`, issue #170, covers #171,
branch `feature/libraw-color-pipeline`): a raw the system decoder gives no
image for now has the White Balance of any raw (the nine modes, Kelvin and
Tint, Auto), and an unedited one comes out close to a raw the system decodes.
This replaces #161's relative White Balance and flatter look above. LibRaw
decodes to camera RGB (balanced for the camera's neutral, not clipped at it,
no matrix, the file's white level), and a color step after the decode
(`Sources/PhotoCore/CameraColor/`: `ColorTemperature`, `CameraColor`,
`CameraProfile`, `CameraColorTransform`, `CameraColorStep`; Core Image
filters, no custom kernel) turns that into the working space for the stack's
Kelvin and Tint by the DNG specification's method (one or two matrices, forward
matrices, Bradford to D50), with a built-in profile and a baseline look
measured against the system decoder. A Kelvin or Tint alone takes the other
from as shot; Custom keeps the numbers shown (sliders' ranges 2000 to 50000 K,
±150); Kelvin pastes and presets work both ways between decoders and relative
values never render on a raw (`RenderContext.balancedByDecoder`); a raw with
no usable color data renders as shot and the tab says White Balance is
unavailable. A white balance change re-runs the step over the kept decode, at
fit and at 100%, never a new decode. Fujifilm's held-back exposure (dynamic
range 200% and 400%) is added. The stack may name a `cameraProfile`
(`Adjustments.cameraProfile`): kept and written back unchanged, not used yet.
`PreviewCacheKey.currentPipelineVersion` is 9, with version 8's previews
written before 2026-11-13 carried over at launch (`PreviewDiskCache.carryOver`),
so the library's previews survive and no LibRaw photo shows its old look. No
migration, no golden moved; photos the system decodes and JPEGs render byte for
byte as before. AC5 is measured and accepted by the owner 2026-11-14, not met
for the X-T3: as-shot Kelvin is 14% to 30% under the system decoder's (X-E3
1.5% under), partly LibRaw's matrix against the camera itself, and the user
guide says so. Rulings of 2026-11-14: the three functions that followed
Adobe's DNG SDK were written again from published sources and measurement of
the system decoder (C1, option b), AC5 accepted as measured, and Custom
storing the numbers shown, clamped to the sliders' ranges (DQ-1, design
§17.1). The 150 million pixel cap is as recorded in the #161 entry. Known: one baseline
exposure (the X-E3's) for every maker, so a Sony, Olympus or Canon raw opens
0.25 to 0.45 EV darker than the system decoder shows it; hue/saturation and
look tables are carried by the profile value and not applied. Shipped; the
owner checked P1 to P10 (the X-E3 beside the X-T3, the note, White Balance by
hand, Auto's wait, paste with real menus or keys, switching photos and Custom
with no extra undo step, the unavailable and not-applied captions, a live drag
with the mouse, light beyond the sliders' ends, the new look across a cached
library) by eye on 2026-11-15, everything fine (#82,
`docs/features/white-balance-across-decoders/qa.md`).

GPU demosaic for raws LibRaw decodes (`docs/features/gpu-demosaic/`, issue #196,
branch `feature/gpu-demosaic`; follows #195, LibRaw built with -O3, PR #197):
for a raw the system decoder gives no image for, LibRaw now only unpacks
(`Demosaic/SensorMosaic.swift`: the visible area in page-aligned memory Metal
uses in place, the pattern, per-site blacks, white span and multipliers) and
our own Metal kernels demosaic (`Demosaic/DemosaicKernels.swift`,
`GPUDemosaic.swift`, `DemosaicTables.swift`; compiled at run time in safe math
with `fp contract(off)`): Bayer by Hamilton-Adams green and color differences,
X-Trans by four directional green estimates (taps derived from the pattern, so
the same derivation gives Hamilton and Adams' on a Bayer one), blended by
inverse squared variation. The Fujifilm frame and lens corrections, the
orientation and the color step follow as before, and a white balance change
still re-runs only the color step. A fixed baseline color noise step follows
the demosaic (edge-avoiding a trous smoothing of R-G and B-G against a noise
model the file gives, in place in bands of 256 rows; `NoiseModel.swift`): no
control, no stored setting, and the Noise Reduction group is as before. Any
other pattern, any GPU failure (no device, compile, allocation, execution) and
the debug switch give LibRaw's own decode, unchanged, with a log notice naming
the reason. Written from published papers and measurement only (the list is in
`status.md`); nothing derived from another project's code. An X-E3 file at full
size is ready in 0.62 s (LibRaw's demosaic: 7.7 s; X-T3 0.65 s against 8.4 s),
a 24 MP decode peaks at about 300 MB above its start (LibRaw's own: about 550
MB), GPU time 78 to 85 ms; Bayer files 0.10 to 0.31 s against 0.40 to 0.63 s;
half-size decodes are no slower. Raws the system decodes are untouched.
`PreviewCacheKey.currentPipelineVersion` is 12, a plain bump: every cached
preview is made again once. `photocli render` prints `decoder` (`systemRAW`,
`libRaw`, `imageIO`) and, for LibRaw's, `demosaic` (`method`, `pattern` or
`reason`). Hidden switch for comparing, never a setting: launch option
`--demosaic libraw`, `RAW_DEMOSAIC=libraw` for every tool and the tests,
`photocli render … --demosaic libraw`. Checks with the owner's files (never
committed): `XTRANS_SAMPLES=a.RAF:b.RAF swift test --filter
DemosaicXTransSampleTests`, `BAYER_SAMPLES=a.RW2:b.CR2 swift test --filter
DemosaicTruthTests`, `swift run -c release photobench demosaic --mode timing
--files a.RAF` (modes `truth`, `real`, `timing`, `live`, `memory`, `pattern`).
No migration, no stack change, no golden moved. Accepted by the owner as
measured, 2026-11-16: the X-Trans kernel alone is 0.26 to 1.09 dB under
LibRaw's three passes against binned truths (AC3; the sharper kernel is #199);
AC4's per-pixel agreement with LibRaw's output is held only at ISO 800 or
lower, with three files just outside (high ISO is judged by false color,
detail and the system-decoder cross-check); AC6's detail is 0.92x to 0.94x on 5
of 28 real files (false color is 0.17x to 0.82x of LibRaw's on all 28); AC2's
edge chroma error on the E-M5 III is 1.04x LibRaw's. Known: the sample suites
record those files rather than expect them; LibRaw's own X-Trans demosaic
fails with an I/O error on frames of 450 rows or fewer (fallback path only, no
camera's frame is that small); the macOS 15 job of CI has not built the new
tests (Swift 6.2 has no `Test.cancel`; they avoid it). Shipped, checks
pending: macOS 15 and 26 (CI is the first run there). The owner checked P1 to
P4 (X-E3, X-T3 and X100S files at ISO 200 to 12800 beside `--demosaic libraw`,
high-ISO look, stopping an export, first launch with an empty cache) by eye on
2026-11-17: "no noticeable difference in rendering at 100% against the old
look; previews for X-E3 files generate a lot faster, no lag"
(`docs/features/gpu-demosaic/qa.md`).

Luminar preset packs (`docs/features/luminar-preset-import/`, issue #203,
branch `feature/luminar-preset-import`): the preset manager's Import (Adjust ▸
Import Presets… and the Presets heading's Import…) takes `.lnpc` packs, several
at once, beside the other formats. Each pack becomes one preset collection and
one look-up table collection of the pack's name (never a folder's), presets in
the pack's order, named in the system language when the pack has it, English
otherwise. Importing a pack again replaces its presets by name in the same
collection (the existing rule of `saveAdjustmentPresets`, ids kept) and lists
no table twice (by SHA-256); a renamed collection is not recognized. A converted
preset sets only the groups it has, and one with nothing carried over imports
with none. The conversion is approximate and the owner's (Skylum documents
neither the format nor its scales): `Presets/Luminar/` (`LuminarPack`,
`LuminarTemplate`, `LuminarCurves`, `LuminarMapping`, `LuminarTool`) reads a
pack from memory with our own zip reader (`Support/ZipArchive.swift`, Apple's
Compression framework for deflate, no new package; nothing is extracted or
written), and `PresetImport` scans, converts and saves. Assumed scales are
named constants in `LuminarMapping` (Exposure ±100 = ±2 EV, Color Balance 0.2,
Warmth 0.1, Structure to Clarity 0.75, Details to Clarity 1.0, Supercontrast
gain 0.5, and the rest), pinned by `assumedScalesAreTheRecordedOnes`, with no
setting. Tools with no equivalent (Accent AI, Sky Enhancer, masks and the
rest of the left-out list) set nothing and are listed. After a pack import the
manager opens on its Import Report page (a button reopens the last one): per
pack and per preset what was mapped, approximated or left out, what is not
recognized (shown by the pack's identifier, verbatim) and which files were not
imported and why; one file that can't be read never stops the others. A table
tool that also sets contrast or saturation is listed under both Mapped and
Approximated (design §13). The report waits while any other sheet, dialog or
alert of the library window is up (`LibraryModal`, `LibraryModalTests`). The
one Luminar name list is the identifier-to-display-name table (36 tools,
`LuminarTool.swift`, each with a keyed `presetPackTool.<case>` catalog entry,
checked against the table by `PresetPackTableTests`); there is no file type,
UTI or `Info.plist` entry for `.lnpc`, so the Finder never opens it in the app,
and no Luminar asset ships. `PresetFile.installTables` now checks cubes
concurrently (an import of 40 presets and 36 tables takes about 0.7 s; `.guspreset`
imports behave as before, only faster). Limits: a pack's file at most 256 MiB, 512
MiB decompressed, 64 MiB per member (4 MiB for text), 1,000 presets, no ZIP64 or
encryption, regular files only (links followed). Known: two presets with the same
name in one pack collapse to one, the first kept, compared without regard to case,
and the report still counts both (RI-E3, kept by the owner, no suffix);
Develop's Brightness shows as "Not recognized"; a table two packs share is
listed in the first's collection; C11 (⌘⌫ pressed while a pack import ends, in
the one catalog read before the removal confirmation, can open the manager
before the confirmation) and C12 (`LibraryModalTests` reads `MainView` and
`SidebarView` only and doesn't count `.fileImporter`, `.fileExporter` or
`.fileMover`) are accepted. The code review lists what `/security-review`
should read (the zip reader's bounds, CRC and budgets; the file-size and
symbolic link checks; memory held across an import; the table checks run in
parallel): the branch adds parsers of outside files, and the other formats'
existing reads have no size cap (older than this work). No migration, no
`PreviewCacheKey.currentPipelineVersion` bump, no golden moved, no rendering
changed. Shipped; the owner checked P1 to P5 (the open panel and the three
ways in, the page's look and keys, the Finder not opening packs, the report
beside other sheets and the Importing… state, the eye comparison of his four
packs' presets with the prototype's output) by eye on 2026-11-18, everything
fine (#82, `docs/features/luminar-preset-import/qa.md`). The opt-in
`PresetPackSampleTests` (`LUMINAR_PACKS`, `LUMINAR_PROTOTYPE_OUTPUT`; the
packs are never committed) finds all 40 presets of the four packs equal to the
prototype's within rounding.

Spot healing and cloning (`docs/features/healing/`, issue #86, branch
`feature/healing`): a Spots heading in the Adjust tab (Edit Spots, `H`; Adjust
▸ Spots, palette toolbar item) places circular Heal or Clone spots by clicking
the photo, each with a size, feather and opacity. Heal copies the source's
texture and blends it into the surroundings (the source plus a harmonic
membrane of the boundary differences); Clone copies as it is. The source is
chosen automatically on placement (a clean nearby patch clear of the spot,
every other spot and the edges, scored by context match; deterministic) and
can be dragged elsewhere; Adjust ▸ Spots ▸ Choose Source Automatically (one
undo step) asks the same question again, for keyboard and VoiceOver users.
Select, move, resize, change mode and delete, with the keyboard too (⌥-arrows
move, ⌥⌘-arrows move the source; bare `V` shows or hides the overlay, in
Adjust ▸ Spots); one undo step and History entry each. The heading's check
box turns every spot off and on without losing them (Turn Off / On Spots;
`spots` is an `Adjustments.Group`, off renders byte for byte as no spots).
One `spots` operation, schema 2 like masks, strict read, never written over
when unreadable, at most 100 spots (`SpotLimits.spots`; the 101st is refused
with a message). Positions are in the mask frame (oriented decode before the
crop), so spots stay on the same picture content under crop, turns and
Straighten; a raw with spots decodes its whole sensor. Rendered first among
the adjustments, after the Lens heading's steps and before white balance,
tone, masks and the crop, in `AdjustmentRenderer.spotStep` (one renderer for
loupe, live frames at 100%, previews, export and `photocli render`; every
decoder alike). Paste, presets and sync leave spots and their on/off out
(`Group.presetGroups`); spots are per file (a RAW+JPEG pair's other file is
unchanged; a virtual copy starts with the original's and is independent), are
never written to sidecars or originals, and can't be edited while comparing.
Kernels are written from published sources only (Pérez et al. 2003, Farbman et
al. 2009, Criminisi et al. 2004 for the source match; the list is in
`status.md`), compiled at run time. Code in PhotoCore `Edits/Spots/`
(`Spots.swift`, `SpotGeometry.swift`, `SpotRenderer.swift`,
`SpotSourceFinder.swift`) and PhotoApp (`Model/SpotEditing.swift`,
`SpotActions.swift`, `DebugSpotCommands.swift`; `Loupe/SpotOverlayView.swift`;
`Views/SpotsSection.swift`). A CPU reference agrees within a derived tolerance;
three new goldens (`spots-heal-dustySky`, `spots-clone-dustySky`,
`spots-healCropTurn-dustySky`); `photobench scenes` writes the dusty sky. No
migration, no pipeline bump, no existing golden moved; photos without spots
render byte for byte as before. Debug script: `spots`, `spot …`. Rulings: DQ-1
(Show / Hide Spot Overlay stays in Adjust ▸ Spots as bare `V`), DQ-2 (one 10 pt
grab distance for every event, touch included). Known: many spots are slow (100
spots cost about 102 ms of render at 2560 × 1707, a drag at 100% 44 to 56 ms
a frame with 93; accepted, one-pass render is #211); a nudge chosen from the
menu with a key still held shares one ⌘Z with the next change (C1 residual);
a spot's center held inside the crop can sit a hair off at an extreme aspect
ratio (C7, nit); a VoiceOver press on empty canvas adds no spot (adding needs a
pointer, R-3; Add Spot at Center of View is #210); if the spot kernels can't
compile, spots are skipped with no message (as RI-CR1); no `photocli spot`
commands; spot names wait for #92 (presets and paste of spots). Not built:
Remove brush (#208), Visualize Spots (#209). Shipped; the owner signed off
2026-11-18, P1 to P7 done, 15 of 15 criteria pass (`docs/features/healing/qa.md`).
VoiceOver, macOS 15 and macOS 26 are covered by CI only.

Profile group removed (`docs/features/remove-profile-group/`, issue #219,
branch `feature/remove-profile-group`): the Adjust tab has no Profile group (no
Look pop-up, no Decoder pop-up, no note for raws LibRaw decodes), and the
Light heading starts at White Balance. No render uses a stored `look`: the
decoder's boost amount is never set, so every photo renders with its decoder's
default (`RawDecode.storedLook`, read as stored text; `AdjustmentRenderer`
sets no boost). A photo saved with Look Neutral or Flat renders with more
contrast than before; its value is kept and written back unchanged by every
write (edit, undo, history revert, paste, batch, `photocli develop`), and only
Reset All Adjustments (`Adjustments.resettingAll()`, the loupe's menu and ⋯
command and the grid batch) clears it, by removing the whole `rawDecode`
operation with its decoder version. A stored `decoderVersion` that is not the
machine learning one is still honoured; machine learning noise reduction is
chosen only with Use machine learning and works as before. Profile is no
preset group: an old preset or `.guspreset` with `rawDecode` values imports
without error, keeps them in its stored data and applies nothing from `look`
(a legacy machine learning decoder in a preset still turns machine learning
on; the owner accepted that an old preset whose Profile was unticked in
Include now does so too, C1). Lightroom import maps no profile to a Look; a
name outside the Standard family (Standard, Adobe Color, Adobe Standard,
default, embedded) is reported as "Profiles and creative looks", the family
is not. `photocli adjustments` lists `rawDecode` with `decoderVersion` only,
and `--set rawDecode.look=…` fails as an unknown parameter (the owner kept
`decoderVersion` settable, RI-E1). `RawDefaults.offeredDecoderVersions` and the
editor's `chooseDecoder` are gone. The render hash still covers a stored Look
(unchanged, so the corpus hashes hold), but its render changed, so
`PreviewCacheKey.currentPipelineVersion` is 13, a plain bump: every preview is
made again once. The `raw-lookNeutral` and `raw-lookFlat` goldens were deleted
in a commit of their own; no other golden moved. No catalog migration, no
stored stack rewritten. Shipped, checks pending: P2 and P5 (a photo with a
stored Flat Look, seeded with the command in `qa.md`: its History and Reset
All Adjustments by hand) in #82 and `docs/features/remove-profile-group/qa.md`.
The owner signed off by eye on 2026-11-19 (P1, P3, P4, P6 and P7 checked, fine).
Covered by CI only: VoiceOver, macOS 15 and macOS 26.

Black & White module (`docs/features/bw-module/`, issue #218, branch
`feature/bw-module`): a Black & White heading in the Adjust tab between Color
Mixer and Color Grading, with a check box that is always shown (checking it on a
fresh photo stores an explicit `on`, so an all-zero group that is on is itself an
edit and turns the photo gray), a segmented quick-set (Yellow, Orange, Red, Green,
Blue: that filter at 100, the other four at 0, one undo step) and five 0 to 100
sliders. The conversion is a normalised channel mix: Rec. 709 luminance weights
times the filters' transmittance (`t^(amount/100)`, filters multiply), divided by
their sum so a neutral gray keeps its level; a `CIColorMatrix` in the working
space with no clipping (`Edits/BlackAndWhite.swift`,
`AdjustmentRenderer.blackAndWhite`). The filter strengths are the engineer's
estimates from published filter pass bands, accepted by the owner at sign-off
(`status.md`), and if too strong the table changes, not the quick-set value. It
renders right after the Color Mixer and before Vibrance, Saturation and Color
Grading (owner ruling RI-1: the Color Mixer runs after the tone table, so it can't
also come before the Tone Curve; a per-channel Tone Curve therefore acts like an
extra filter, and Saturation and Vibrance leave the grays unchanged). Masks, the
look-up table, vignette, noise reduction, sharpening and grain render after it, so
a mask's White Balance tints the gray (DQ-1) and grain stays neutral. Color
Fringes swatches keep their true colors (`LensRenderer.swatch` leaves the group
out). A normal group: per-group on/off, paste, presets, batches, virtual copies,
RAW+JPEG files separately, reset to a stack with no operation (history labels
"Turn On / Off Black & White", "Black & White Filter", "Reset Black & White");
every decoder alike; videos skipped. Adjust ▸ Black & White ▸ submenu (loupe
only; dimmed in the grid, while comparing and while cropping). A gray file shows
a caption saying the filters change nothing (`Edits/SourceColorModel.swift`).
`photocli develop` takes `blackAndWhite.*` (an explicit `on` wins; a filter set
means on). No migration, no `PreviewCacheKey.currentPipelineVersion` bump, no
existing golden moved, three new goldens (`blackAndWhite-noFilter-patchChart`,
`-red-hazyLandscape`, `-yellowGreen-hueRamp`). A fix found at sign-off:
`AppKitSegmented.fillsWidth` (off by default, on for the quick-set) keeps five
segments from widening the Adjust column past the inspector, and the debug script
gained `print inspectorwidth` (visible width, how far the controls reach, `fits`
or `overflow`). Shipped; the owner signed off by eye on 2026-11-19, no checks left
open. Covered by CI only: VoiceOver, macOS 15 and macOS 26. Known: the Tone Curve,
Color Grading and Spots mode controls are 276 pt wide and would overflow the
narrowest inspector (256 pt of content), as before this branch (follow-up).

Lens corrections (`docs/features/lens-corrections/`, issue #87, branch
`feature/lens-corrections`): Distortion and Lens Vignetting, two groups under
the Adjust tab's Lens heading (`lensDistortion` and `lensVignetting`
operations, explicit on value, off by default; `Edits/LensCorrections.swift`,
`LensRenderer`, `Kernels/LensKernels.swift`). Each has a Source, Auto or
Manual, and a signed Amount that works on any photo. Auto reads the camera's
own table from the file: Fujifilm RAF tables (vignetting; distortion where
the table has it) and DNG `WarpRectilinear` and `FixVignetteRadial`. Auto is
inert where the system decoder already corrects the raw, or Fujifilm's
built-in table does (raws LibRaw decodes): nothing is applied, the caption
says so, and Manual works on top of the camera's correction. A non-raw file
(and a RAW+JPEG pair's JPEG) has no Auto and starts in Manual; a raw with no
readable table says "No distortion table was found." The manual Amount is kept
while Source is Auto and not applied. Constrain to image (on by default)
scales the corrected photo to fill its frame. Order: distortion first in the
Lens heading, before Color Fringes and Color Alignment, all before the crop;
lens vignetting before exposure and tone, not after Effects' Vignette. The
fringe picker and Color Alignment's measurement see the corrected image (the
Pixel Magnifier plate reads "After lens correction"). R15: clicking a Source
segment while its group is off turns the group on, one step. The mask and
spot frame is the corrected frame, so a change that really moves it on a
photo with spots or masks asks first, in a narrow alert (Change default,
Cancel): once per visit to the photo, at commit for a slider drag, once with
counts for a paste or preset on several photos, never for Undo, Redo, History
or Reset All (`Adjustments.choosingLensSource` and the frame rule in
PhotoCore). A newer paste or preset ends a pending file read. Paste and
presets carry both groups, each receiving photo reading its own table; one
that can't be corrected is left unchanged and Activity says so. Reset Lens
returns the four groups to their start. Kernels that can't compile or a
corrupt table are said on the group (Color Fringes and Color Alignment still
skip silently, RI-CR1). No migration, `PreviewCacheKey.currentPipelineVersion`
stays 13 (a stack without the groups renders byte for byte as before; one that
turns them on has a new render hash), five new goldens, CPU references in
`Reference/LensCorrectionReference.swift`, no existing golden moved. Rulings
2026-11-19: RI-1 (Auto inert, Manual on top), RI-3 (the frame alert), RQ-1
(Fujifilm and DNG now; other makers follow-ups), RQ-2 (DNG `GainMap` deferred),
DQ-2 (R15), DQ-3 (the "No table found" caption stays on makers not read).
Known: ⌘Z during a grid paste's file read undoes the step before the paste;
the only real DNG with `WarpRectilinear` has a no-op green plane, so
distortion read from a table has no by-eye check on real files (the XF14 and
XF23 distortion tables are zeros): it rests on the CPU references, goldens and
synthetic opcode tests; Panasonic, Olympus and Sony ARW readers (#227 Sony)
and DNG `GainMap` are follow-ups; `DeferredRenderTests` flakes now and then
(#229); Color Alignment's lensAlign kernel can read a stale area (#228). Shipped, checks pending: P5 (the frame question with real keys: Return,
Esc, ⌘., Cancel after a real slider drag, once per visit, keys with the sheet
up) in #82 and `docs/features/lens-corrections/qa.md`; the owner checked the
rest, including Lens Vignetting Auto on the XF14 and XF23 files against the
camera JPEG, by eye on 2026-11-19, everything fine. VoiceOver, macOS 15 and
macOS 26 are covered by CI only.

Not yet: local Black & White through masks, Lightroom Black & White mapping on
import, Black & White items for a grid selection, AI masks, automatic dust detection, a Remove brush, automatic lens corrections from tables other than
Fujifilm RAF and DNG ones (Sony, Panasonic, Olympus; DNG GainMap), lens profiles
(no lensfun or `.lcp`), perspective and keystone, DNG export, `.dcp` profiles
and built-in look profiles (dropped 2026-11-18, #89 and #216; a profile's
hue/saturation and look tables are not applied), a Profile group or any
Neutral or Flat base look (#219 removed it; the loss is accepted),
a sharper X-Trans demosaic (#199),
general (hand-made or burst) stacks, hierarchical
keywords, PTP cameras, a second backup destination. Writing metadata into
originals was dropped (2026-11-04, `docs/roadmap.md`): originals are never
written.
