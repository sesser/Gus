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

The build does not depend on Xcode: everything goes through SwiftPM, and tests
use Swift Testing (not XCTest). `Scripts/build-app.sh` assembles the `.app`
bundle (Info.plist from `Branding.xcconfig`, String Catalog compiled by the
`catalog-strings` tool, ad-hoc signature); `importer` builds the standalone
importer and `all` builds both.

To check UI changes without screen recording permission, run the bundle's
executable with `--library-root <folder> --debug-script "wait 2; snapshot /tmp/a.png; quit"`
(see `Sources/PhotoApp/Model/DebugScript.swift` for every command: keywords,
albums, sidecars, the import window, folder drops…). App launch options must always take a
value: AppKit treats a stray argument as a document and then does not open the
main window. A process started from a shell is not the active app, so it has
no key window: scripted keys go straight to the window, and local event
monitors (the video loupe's) never see them. To test those, launch with
`open -W -n --stdout <log> build/*.app --args …`, which activates the app.
A FAT32 disk image (`hdiutil create -fs "MS-DOS FAT32" …`, then `hdiutil
attach`) stands in for a camera card. `docs/PROFILING.md` has the benchmark
commands.

Commands meant for the user to paste run in zsh: keep scripts POSIX sh or zsh
compatible and never put `#` comment lines inside pasted command snippets.

## Layout

- `Sources/PhotoCore` — library with no AppKit/SwiftUI: branding, catalog
  (GRDB), import, metadata, `Edits/` (edit stack, adjustments, renderer, live
  render session, look-up tables), `Presets/` (preset files, Lightroom preset
  reading and mapping), preview pipeline, `Sidecars/` (XMP),
  `CardImport/` (templates, copying), `Export/` (rendering, naming, metadata
  and watermarks for exports), `Suggestions/` (Vision), `Video/`.
  Everything testable lives here.
- `Sources/PhotoUI` — UI shared by both apps: `Import/` (the import window, its
  model and its debug-script commands), `Palette`, `LaunchOptions`, and the
  String Catalog (`Resources/Localizable.xcstrings`).
- `Sources/PhotoApp` — SwiftUI app shell, AppKit grid (`NSCollectionView`) and
  loupe, inspector (Info and Adjust tabs), sidebar, smart album editor.
- `Sources/PhotoImporter` — the standalone importer: the same import window
  with no library (copies only; presets and options in its own preferences).
- `Sources/PhotoFixtures` — synthetic JPEG/HEIC and Bayer DNG writers (tests, benchmarks).
- `Sources/PhotoBench` — synthetic library generator and headless profiling.
- `Sources/StringCatalogCompiler` — `.xcstrings` to `.strings`/`.stringsdict`.
- `Sources/AppIconCompiler` — `Support/AppIcon.png` to an `.iconset` (masked to the
  macOS icon shape); `build-app.sh` turns it into `AppIcon.icns` with `iconutil`.
- `Tests/PhotoCoreTests` — Swift Testing suites.
- `docs/PHASE1_PLAN.md`, `docs/PHASE2_PLAN.md`, `docs/PHASE3_PLAN.md`,
  `docs/PHASE4_PLAN.md` — design decisions per phase.

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
  operations. The render hash covers enabled operations only. `Adjustments`
  is the typed view of it: one operation per module, defaults left out (so a
  reset gives back the identity hash), unknown operations kept. A group of
  controls turned off keeps its operations with `isEnabled` false;
  `Adjustments.effective` is what renders.
  `AdjustmentRenderer` renders in a fixed order with built-in Core Image filters
  and generated tables (no custom kernels: SwiftPM has no Metal step). RAW
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
- **No SwiftUI `ScrollView` under the toolbar.** Because the app supports macOS 15,
  macOS 26+ runs it in the earlier design, where such a scroll view (the
  inspector's) swallows every click. Use `AppKitScrollView`; inspector buttons
  are `AppKitButton`s, which the debug script's `click` can drive.
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

Info tab metadata: title, description, alt text, extended description,
copyright, usage terms and the creator's contact details (IPTC Core and
Extension, `Catalog/Descriptions.swift`), edited for the whole selection as
one undo step each, kept on `image`, synced to sidecars and written on export.
Reading a file again only fills empty descriptive fields; the library's win.

Not yet: brushes and masks, healing, cropping, lens corrections, DNG export, ML
denoising, `.dcp` profiles, general (hand-made or burst) stacks, hierarchical
keywords, PTP cameras, a second backup destination, writing metadata into
originals.
