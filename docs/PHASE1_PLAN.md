# Phase 1 plan

Short design record for phase 1. The architecture rules themselves live in
`CLAUDE.md`; this file explains the concrete choices made to satisfy them.

## Toolchain reality

The build machine has the Command Line Tools only (no Xcode.app). That means:

- `swift build` / `swift test` are the build entry points (no `xcodebuild`).
- Tests use **Swift Testing** (`import Testing`); XCTest is not shipped with the CLT.
- `xcstringstool` is missing, so SwiftPM cannot compile `.xcstrings`. The String
  Catalog is still the source of truth; a small in-repo tool
  (`StringCatalogCompiler`) converts it to `.lproj/Localizable.strings` when the
  app bundle is assembled.
- SwiftPM does not produce `.app` bundles, so `Scripts/build-app.sh` assembles one,
  filling `Support/Info.plist` from `Branding.xcconfig` the way Xcode would.

If Xcode is installed later, nothing here breaks; the xcconfig and Info.plist
template can be dropped straight into an Xcode project.

## Module layout

```
Package.swift                 package "PhotoWorkspace"
Branding.xcconfig             PRODUCT_NAME, PRODUCT_DISPLAY_NAME, PRODUCT_BUNDLE_IDENTIFIER, PRODUCT_URL_SCHEME
Support/Info.plist            template with $(VARIABLE) references only
Sources/
  PhotoCore/                  library, no AppKit/SwiftUI
    Branding/                 AppBranding (the only Swift file with brand literals), LibraryLocations, DataDirectoryMigrator
    Catalog/                  GRDB schema + migrations, records, Catalog store, grid queries
    Import/                   FileScanner, ContentHasher, VolumeResolver, Importer
    Metadata/                 MetadataReader protocol, ExifTool (stay_open subprocess) + ImageIO readers
    Edits/                    EditStack model, canonical hashing, EditStackRenderer + PassThroughRenderer
    Preview/                  RenderEngine (Metal CIContext), PreviewGenerator, PreviewCache, CacheKey, PreviewService
  PhotoApp/                   SwiftUI shell + AppKit grid/loupe; Resources/Localizable.xcstrings
  PhotoBench/                 synthetic library generator + headless profiling
  StringCatalogCompiler/      build helper: .xcstrings -> .strings
Tests/PhotoCoreTests/         Swift Testing suites
Scripts/                      POSIX sh helpers (build-app.sh, …)
```

## Catalog schema (SQLite via GRDB, migration `v1`)

| table | key columns |
|---|---|
| `volume` | `id`, `identity` (volume UUID or fallback) UNIQUE, `name`, `mountPath` (last seen), `isRemovable`, `isNetwork`, `lastSeenAt` |
| `project` | `id`, `uuid`, `name`, `sourcePath`, `createdAt` |
| `image` (master file) | `id`, `volumeId`, `relativePath`, `fileName`, `fileSize`, `modifiedAt` (mtime), `contentHash` UNIQUE (SHA-256), `format`, `projectId`, `captureDate`, `pixelWidth`, `pixelHeight`, `orientation`, camera/lens/exposure fields, `importedAt`; UNIQUE(`volumeId`,`relativePath`) |
| `version` | `id`, `uuid`, `imageId` (cascade), `versionNumber`, `name` (nullable, user rename), `isDefault`, `rating` CHECK 0…5, `flag` CHECK -1/0/1, `colorLabel` CHECK 0…7, `editStack` (JSON), `editStackHash`, `createdAt`, `modifiedAt` |
| `album` | `id`, `uuid`, `name`, `projectId` (nullable), `createdAt` |
| `albumMember` | (`albumId`, `versionId`) PK, `position` |
| `stack` | `id`, `uuid`, `pickVersionId`, `createdAt` |
| `stackMember` | `stackId`, `versionId` UNIQUE, `position` |
| `keyword` | `id`, `name`, `parentId` (hierarchy), UNIQUE(`parentId`,`name`) |
| `versionKeyword` | (`versionId`, `keywordId`) PK |

Indexes for the grid: `image(projectId)`, `image(captureDate)`, `version(imageId)`,
`version(rating)`, `version(flag)`. A master belongs to exactly one project; albums,
stacks and keywords attach to versions. Table, column, file and JSON names are all
generic, and a test asserts no brand token appears in the schema.

Offline volumes: `VolumeAvailability` matches catalog volumes against
`FileManager.mountedVolumeURLs` by identity, updates `mountPath` when a volume
remounts elsewhere, and reports the offline set. Rows are never deleted.

## Import

Scan (recursive, hidden files and packages skipped, extension allow-list) →
chunks of 64 files: skip known paths whose size+mtime are unchanged, SHA-256 in
parallel (bounded task group, cancellable between 4 MB reads), drop duplicates
by hash (catalog plus files already seen in this run, with `INSERT OR IGNORE`
on the unique hash as a backstop), read metadata for the chunk in one batch, then
insert images + default versions in one transaction. The project is created
lazily on the first new file and named after the imported folder. Progress
goes out through a callback; cancellation goes through the owning `Task`.

## Edit stack

`EditStack { schemaVersion, operations: [EditOperation{ id, kind, kindVersion, isEnabled, parameters }] }`
stored as JSON on `version`. `renderHash` is SHA-256 over canonical JSON of the
enabled operations only (sorted keys, ids excluded), so equal-looking stacks share
previews. Phase 1 ships `PassThroughRenderer` only.

## Preview pipeline

- `RenderEngine`: one Metal-backed `CIContext`, working space extended linear
  Rec. 2020 at half float, output Display P3.
- Decode: RAW via `CIRAWFilter` (draft mode + `scaleFactor` for small tiers),
  other formats via ImageIO downsampled decode. Edit stack applied in linear
  space, then rendered to P3 8-bit and encoded to JPEG.
- Tiers: `thumbnail` (512 px long edge) for the grid, `preview` (2560 px) for the
  loupe; 100 % zoom renders the master on demand (not cached).
- `CacheKey` = SHA-256(pipelineVersion, tier, contentHash, editStackRenderHash),
  sharded on disk under `~/Library/Caches/<cacheDirectoryName>/previews/`. The
  whole directory can be deleted at any time.
- `PreviewService` (actor): memory cache → disk cache → generate. LIFO priority
  queue so newly visible cells win, cancellation when cells scroll away, bounded
  concurrency, all decoding off the main thread (images are force-decoded
  before being handed to layers).

## App

SwiftUI `NavigationSplitView` shell. The grid is an `NSCollectionView` with a
custom arithmetic uniform-grid layout (O(visible) layout) and layer-backed
cells; the loupe is an `NSScrollView` with magnification, fit and 1:1 modes,
neighbor preloading. Culling keys (0–5, P/X/U, ⌥0–⌥7) are handled by the
grid/loupe views so they never steal typing from text fields; menu items call
the same actions. Writes go to the catalog immediately and update the in-memory
snapshot in place.

## Branding

- `Sources/PhotoCore/Branding/AppBranding.swift`: displayName, bundleIdentifier,
  appSupportDirectoryName, cacheDirectoryName, sidecarNamespace (+ prefix),
  urlScheme, and the list of previous directory names for migration.
- `Branding.xcconfig`: PRODUCT_NAME, PRODUCT_DISPLAY_NAME,
  PRODUCT_BUNDLE_IDENTIFIER, PRODUCT_URL_SCHEME. A test parses it and fails if
  it disagrees with `AppBranding`.
- `Localizable.xcstrings` refers to the name only through `%@` arguments.
- Tests: brand-token scan of `Sources/` (excluding the allowed files),
  xcconfig/`AppBranding` consistency, generic catalog file and schema names,
  data directory migration.

## Profiling

`PhotoBench` generates a synthetic library (10k+ JPEGs with EXIF dates plus a set
of synthetic Bayer DNGs to exercise `CIRAWFilter`), then measures import, preview
generation, cache hits and catalog queries headlessly, including a 50k-row
catalog. The app has a `--benchmark-scroll` mode that scrolls the grid at a
fixed speed and records frame pacing.
