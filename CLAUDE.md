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
swift run -c release photobench help
```

The build does not depend on Xcode: everything goes through SwiftPM, and tests
use Swift Testing (not XCTest). `Scripts/build-app.sh` assembles the `.app`
bundle (Info.plist from `Branding.xcconfig`, String Catalog compiled by the
`catalog-strings` tool, ad-hoc signature).

To check UI changes without screen recording permission, run the bundle's
executable with `--library-root <folder> --debug-script "wait 2; snapshot /tmp/a.png; quit"`
(see `Sources/PhotoApp/Model/DebugScript.swift`). App launch options must always
take a value: AppKit treats a stray argument as a document and then does not
open the main window. `docs/PROFILING.md` has the benchmark commands.

Commands meant for the user to paste run in zsh: keep scripts POSIX sh or zsh
compatible and never put `#` comment lines inside pasted command snippets.

## Layout

- `Sources/PhotoCore` — library with no AppKit/SwiftUI: branding, catalog
  (GRDB), import, metadata, edit stack, preview pipeline. Everything testable lives here.
- `Sources/PhotoApp` — SwiftUI app shell, AppKit grid (`NSCollectionView`) and loupe.
- `Sources/PhotoFixtures` — synthetic JPEG/HEIC and Bayer DNG writers (tests, benchmarks).
- `Sources/PhotoBench` — synthetic library generator and headless profiling.
- `Sources/StringCatalogCompiler` — `.xcstrings` to `.strings`/`.stringsdict`.
- `Sources/AppIconCompiler` — `Support/AppIcon.png` to an `.iconset` (masked to the
  macOS icon shape); `build-app.sh` turns it into `AppIcon.icns` with `iconutil`.
- `Tests/PhotoCoreTests` — Swift Testing suites.
- `docs/PHASE1_PLAN.md` — schema, module and pipeline decisions for phase 1.

## Naming rules

- The product name is not a code identifier. Modules and types use neutral,
  role-based names (`PhotoCore`, `PhotoApp`, `Catalog`, `PreviewService`, …).
- `Sources/PhotoCore/Branding/AppBranding.swift` is the only Swift file that may
  contain brand values. `Branding.xcconfig` holds the build-setting copies
  (`PRODUCT_NAME`, `PRODUCT_DISPLAY_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`,
  `PRODUCT_URL_SCHEME`). `BrandingTests` enforces both and fails on any leak.
- User-facing strings go through `Sources/PhotoApp/Resources/Localizable.xcstrings`
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
  `stack`, `stackMember`, `keyword`, `versionKeyword`. Ratings 0–5, flags
  (-1 reject, 0 none, 1 pick) and color labels (0–7) live on versions.
  Never edit an existing migration; add a new one.
- **Edit stack**: each version stores an ordered, versioned JSON list of
  operations. The render hash covers enabled operations only. Phase 1 renders
  with `PassThroughRenderer`.
- **Preview cache** is tiered (`thumbnail` for the grid, `preview` for the loupe),
  lives under the Caches folder on the local disk, is keyed by
  content hash + edit-stack render hash + tier + pipeline version, is generated on
  demand, and can be deleted at any time.
- **Rendering**: Core Image with `CIRAWFilter`, one Metal-backed `CIContext`,
  extended linear Rec. 2020 working space, output converted to Display P3.
- **Concurrency**: Swift 6 strict concurrency. Import and preview work is async
  and cancellable; no image decoding on the main thread. Images are fully
  decoded and converted to the window's color space (BGRA) before they reach
  layers, otherwise Core Animation converts them on the main thread at commit.
- **Metadata** goes through the `MetadataReader` protocol. ExifTool
  (`-stay_open` subprocess) is the default when installed; ImageIO is the
  in-process fallback.
- **Dependencies**: GRDB only. Ask before adding anything else.

## Phase 1 scope

In: importer, grid, loupe, culling (rating, flag, label), sidebar filters
(rating, flag, project), catalog/importer/cache/branding tests, profiling.
Out: adjustments, brushes, healing, export, stacks UI, keywords UI, smart albums,
XMP sidecar writing.
