<p align="center">
  <img src="Support/AppIcon.png" width="256" height="256" alt="Gus app icon">
</p>

<h1 align="center">Gus - A Swift native, non-destructive photo editor and library</h1>

<p align="center">
  Cull fast, organize everything, edit without ever touching an original.<br>
  Built from the ground up in Swift for macOS and Apple Silicon.
</p>

---

## Highlights

**Your files stay yours.** Gus references your photos where they live. Originals
are never moved, copied or rewritten, and every edit is a recipe stored in the
library, so you can always go back to exactly what the camera saw.

**Built for speed.** A native AppKit grid and loupe, a tiered preview cache and
fully asynchronous decoding keep scrolling smooth through tens of thousands of
photos. Rate, flag and label with single keys and move on to the next shot
without waiting.

**Import that you can trust.** Pop in a card and the import window appears.
Name folders and files with templates, attach copyright and contact presets,
and let Gus verify every copy by hash before it counts. Only verified originals
are ever offered for deletion. Already have a folder of photos? Drag it in from
Finder and it becomes a project, in place.

**Serious RAW editing.** Crop, rotate and straighten, white balance, exposure
with Auto, tone, presence, a tone curve with live histogram, a color mixer,
sharpening, noise reduction and color grading, plus look-up tables, vignette
and grain. Everything renders live through Core
Image in a wide-gamut linear working space, with before/after, copy/paste and
presets.

**HDR, done right.** On an EDR display, HDR photos (floating-point DNGs, gain
map HEIC and JPEG, HLG and PQ) show highlights above white.

**Organize your way.** Projects, albums, smart albums with dozens of rules,
keywords with autocomplete, and a Dates tree by capture time. On-device Vision
suggests keywords after each import, and nothing leaves your Mac.

**RAW+JPEG pairs as one photo.** Shoot both, cull once: ratings, flags,
keywords and albums reach both files.

**Plays well with others.** Ratings, keywords and IPTC details go to standard
XMP sidecars. If another app changes a sidecar, Gus never overwrites it; it
shows you the difference and lets you choose.

**Offline volumes welcome.** Photos on an unplugged drive keep their previews
and their place in the library, and come back when the drive does.

**Export ready to share.** JPEG or 16-bit TIFF in sRGB, Display P3, Adobe RGB
or ProPhoto RGB, resized with output sharpening, named by template, with the
metadata you choose and an optional watermark. Save the settings as presets.

**Videos too.** MOV, MP4 and M4V are catalogued alongside your photos, rated,
keyworded and played in the loupe.

**Scriptable.** `photocli` renders photos and edit stacks, lists and queries
the library with smart-album rules, sets adjustments, ratings, flags and
labels, and runs exports, all from the terminal and all as JSON. It reads a
library at any time and changes it only while the app has it closed.

**Also included:** a standalone Gus Importer for copying cards on a machine
without a library, full undo and redo, and ExifTool support for the richest
metadata when it is installed.

## Status

Gus is in active development and has no stable release yet. The `develop`
branch has the latest work; `master` will hold releases.

On the roadmap: masks and brushes, healing, lens corrections, DNG export, ML
denoising, stacks and hierarchical keywords.

See the [user guide](docs/USER_GUIDE.md) for how everything works, and the
phase plans in [docs](docs) for design decisions.

## Requirements

- macOS 15 or later on Apple Silicon
- Swift 6 toolchain (Command Line Tools are enough; Xcode is optional)
- Optional: [ExifTool](https://exiftool.org) on `PATH` or in `/opt/homebrew/bin`
  for richer metadata. Without it, metadata is read in-process with ImageIO.

## Build and run

Clone the repository and build the app bundle:

```bash
git clone git@github.com:sesser/Gus.git
```

```bash
cd Gus
```

```bash
Scripts/build-app.sh
```

```bash
open build/*.app
```

`Scripts/build-app.sh` builds in release mode and assembles the `.app` bundle in
`build/`: it fills `Support/Info.plist` from `Branding.xcconfig`, compiles the
String Catalog, builds the app icon from `Support/AppIcon.png` and signs ad hoc.
Pass `importer` to build the standalone importer, or `all` for both. Use
`CONFIGURATION=debug Scripts/build-app.sh` for a debug build.

To build and test without packaging:

```bash
swift build
```

```bash
swift test
```

The command line builds the same way (`swift run photocli help` lists its
commands):

```bash
swift build --product photocli
```

Everything goes through SwiftPM; GRDB is the only third-party dependency.

## Repository layout

| path | contents |
|---|---|
| `Sources/PhotoCore` | catalog (GRDB), import, metadata, edit stack and renderer, previews, sidecars, branding |
| `Sources/PhotoUI` | UI shared by both apps: the import window, palette, String Catalog |
| `Sources/PhotoApp` | SwiftUI shell, AppKit grid and loupe, inspector, sidebar |
| `Sources/PhotoImporter` | the standalone importer |
| `Sources/PhotoFixtures` | synthetic JPEG/HEIC and Bayer DNG writers for tests and benchmarks |
| `Sources/PhotoCLI` | the command line (`photocli`) over PhotoCore's command registry |
| `Sources/PhotoBench` | synthetic library generator and profiling (`photobench`) |
| `Sources/StringCatalogCompiler` | String Catalog compiler used by the build script |
| `Sources/AppIconCompiler` | turns `Support/AppIcon.png` into the app's `.icns` |
| `Tests/PhotoCoreTests` | Swift Testing suites, golden images and CPU reference implementations |
| `Branding.xcconfig` | brand-dependent build settings (see [RENAMING.md](RENAMING.md)) |
| `docs/` | user guide, design plans per phase, profiling results |

## License

Copyright © 2026 Randy Sesser.

Gus is free software: you can redistribute it and/or modify it under the terms
of the [GNU General Public License, version 3](LICENSE) or (at your option) any
later version. It is distributed in the hope that it will be useful, but
without any warranty; see the license for details.
