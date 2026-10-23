# Photo workspace

A native macOS photo manager and RAW editor in early development: referenced
masters, projects and albums, non-destructive versions, fast culling. The
current working name is defined in `Sources/PhotoCore/Branding/AppBranding.swift`
and is easy to change (see [RENAMING.md](RENAMING.md)).

Status: **phase 1** — catalog, importer, thumbnail grid, loupe, culling and basic
filters. Adjustments, export, stacks/keywords UI and sidecars come later.

## Requirements

- macOS 15 or later on Apple Silicon
- Swift 6 toolchain (Command Line Tools are enough; Xcode is optional)
- Optional: [ExifTool](https://exiftool.org) on `PATH` or in `/opt/homebrew/bin`
  for richer metadata. Without it, metadata is read in-process with ImageIO.

## Build, test, run

```bash
swift build
```

```bash
swift test
```

```bash
Scripts/build-app.sh
```

```bash
open build/*.app
```

`Scripts/build-app.sh` builds in release mode and assembles the `.app` bundle in
`build/`. Use `CONFIGURATION=debug Scripts/build-app.sh` for a debug build.

## Repository layout

| path | contents |
|---|---|
| `Sources/PhotoCore` | catalog (GRDB), importer, metadata, edit stack, preview pipeline, branding |
| `Sources/PhotoApp` | SwiftUI shell, AppKit grid and loupe |
| `Sources/PhotoBench` | synthetic library generator and profiling |
| `Sources/StringCatalogCompiler` | String Catalog compiler used by the build script |
| `Tests/PhotoCoreTests` | Swift Testing suites |
| `Branding.xcconfig` | brand-dependent build settings |
| `Support/` | Info.plist template, version numbers |
| `docs/PHASE1_PLAN.md` | schema and architecture decisions |

## Data locations

- Catalog: `~/Library/Application Support/<app folder>/Library/catalog.sqlite`
- Previews: `~/Library/Caches/<bundle id>/Previews/` (safe to delete)

Originals are never moved, copied or modified.
