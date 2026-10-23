# Photo workspace

A native macOS photo manager and RAW editor in early development: referenced
masters, projects and albums, non-destructive versions, fast culling. The
current working name is defined in `Sources/PhotoCore/Branding/AppBranding.swift`
and is easy to change (see [RENAMING.md](RENAMING.md)).

Status: **phase 1**. It covers the catalog, importer, thumbnail grid, loupe,
culling and basic filters. Adjustments, export, the stacks and keywords UI, and
sidecars come later.

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
`build/`. It fills `Support/Info.plist` from `Branding.xcconfig`, compiles the
String Catalog, builds the app icon from `Support/AppIcon.png`, and signs ad hoc.
To change the icon, replace that file with any square image (1024 × 1024 is
best) and rebuild; the `app-icon` tool fits it to the macOS icon shape. Use `CONFIGURATION=debug Scripts/build-app.sh`
for a debug build.

## Using it

**Importing from a card**: **File ▸ Import from Card or Folder…** (⌘I) opens the
import window; it also opens by itself when a card (any volume with a `DCIM`
folder) is inserted, unless that is turned off in **Settings**. Pick photos
(click, shift-click, All, None; RAW+JPEG pairs are one tile, photos already in
the library are hidden and never imported), choose the destination folder and
the subfolder and file name templates (tokens such as `{capture:yyyy-MM-dd}`,
`{import:yyyy}`, `{model}`, `{lens}`, `{name}`, `{number}`, `{seq:4}`,
`{counter:5}`, `{job}`; the ⊕ menu inserts them and an example shows the
result), the project (a new one named from a template, or an existing one), a
job code and a metadata preset (creator, copyright such as
`© {capture:yyyy} Your Name`, usage terms, contact; written to sidecars, the
copies stay identical to the originals). Every copy is read back and compared
by hash before it counts. Optionally, the originals that were copied and checked
are deleted from the card (after a confirmation) and the card is ejected.

Choose **File ▸ Import Folder…** (⇧⌘I) to add photos where they are, without
copying: pick a folder. Photos in it and its
subfolders (CR3, CR2, NEF, ARW, DNG, RAF, ORF, RW2, HEIC, JPEG, TIFF, PNG) and
videos (MOV, MP4, M4V) are
added to a new project named after the folder. Duplicates (same content
anywhere in the library) are skipped, and so are files already imported from
the same place. Originals are never moved, copied or modified.

| key | grid | loupe |
|---|---|---|
| arrows | move selection (⇧ extends) | ← → previous / next photo |
| Home, End, Page Up, Page Down | jump | first / last photo |
| Return, Space, double-click | open the loupe | back to the grid |
| Esc | | back to the grid |
| Z, double-click | | toggle fit / 100 % (pinch zooms too; drag pans) |
| 0–5 | set rating | set rating |
| [ and ] | lower / raise rating | lower / raise rating |
| P, X, U | pick, reject, clear flag | pick, reject, clear flag |
| ⌥1–⌥7, ⌥0 | color label red…gray, clear | color label |
| ⌘= and ⌘− | thumbnail size | |
| ⌘Return | switch grid / loupe | switch grid / loupe |
| ⌘K | add keywords | add keywords |
| ⌘I | import from a card or folder | |
| ⌘N, ⌥⌘N | new album, new smart album | |
| ⌫ | remove from the album on screen | |
| ⌘Z, ⇧⌘Z | undo, redo | undo, redo |

Changes are saved to the catalog immediately. In the grid they apply to every
selected photo. **Photo ▸ Advance After Rating** moves on to the next photo after
each change. Rating and flag filters live at the bottom of the sidebar; photos
that stop matching stay visible until the filter changes, so they do not jump
away while you cull.

A RAW file and a JPEG or HEIC with the same name in the same folder are a
pair. **View ▸ Group RAW+JPEG Pairs** shows each pair once, as the RAW unless
**Photo ▸ RAW+JPEG Pair** says otherwise; its badge reads `RAW+JPEG` (the file on
screen first). Ratings, flags, labels, keywords and albums always apply to both
files. **View ▸ Show File Names** toggles the name and type badge under each
thumbnail.

**Keywords**: ⌘K opens a field over the grid or loupe that adds keywords to the
selected photos, completing from the keywords already in the library (↓ ↑ to
choose, Tab or Return to take one, Return to add, Esc to close). The inspector
(**View ▸ Show Inspector**, ⌥⌘I) lists the selection's keywords with counts
("dog, 12 of 30"), removes them, and shows file details. The sidebar lists every
keyword; click one to see its photos, or right-click to rename (renaming onto
an existing keyword merges the two) or delete it. Keywords, ratings and labels
embedded in files by other apps or the camera (IPTC, XMP) are read at import.

**Suggested keywords**: after each import, Apple's on-device image classifier
looks at the new photos (nothing leaves the Mac) and the inspector shows what it
found as chips. Click one to add it to the selected photos it was suggested
for, or × to stop suggesting it for them. **Photo ▸ Suggest Keywords** (⇧⌘K)
analyzes the selection, for photos imported before. The labels are generic
("dog", "beach", "sunset"), not breeds or places.

**Albums and smart albums**: the sidebar's Library section has built-in smart
albums (Last Import, Picks, Rejects, Unrated, No Keywords), and Dates lists
years and months by capture date, in the time zone each photo was taken in.
**File ▸ New Album…** (⌘N) makes an album, in the library or in a project,
optionally with the selected photos; drag photos onto an album (or a keyword)
to add them, and press ⌫ inside an album to take photos out (they stay in the
library). **File ▸ New Smart Album…** (⌥⌘N) opens the rule editor: match all
or any of rules on rating, flag, label, keywords, file type and name, capture
and import dates, project, camera, lens, serial number, ISO, aperture, shutter
speed, focal length, exposure compensation, flash, white balance, location,
artist, copyright and caption, with a live count. Right-click albums to rename,
edit or delete them.

**XMP sidecars**: ratings, flags, labels, keywords, creator, copyright, caption,
usage terms and contact details are written to an `.xmp` file next to each
original a moment after they change (`IMG_0412.xmp`; a RAW+JPEG pair shares
one), so other apps can read them. Existing sidecars are edited in place and
keep everything other apps put in them. Sidecars present at import, or
`IMG_0412.CR3.xmp` ones, are read. Originals are never written, JPEG, HEIC and
DNG included. The library is the source of truth, but nothing another app
changed is overwritten: at launch, when a volume mounts and with **Photo ▸ Check
for Changes on Disk**, sidecars and originals changed outside the app are listed
under **Library ▸ Changed on Disk**, and the inspector compares the library's
values with the file's so you can keep either, or choose per field (keywords can
be merged). Writing can be turned off in **Settings**.

**Videos** (MOV, MP4, M4V) are catalogued like photos by both kinds of import
(the import window has an **Include videos** switch): their poster frame is the
thumbnail, the grid shows their length, and the loupe plays them (space plays
and pauses; the arrow and culling keys still move between and rate items). They
take ratings, keywords, albums and sidecars. There is no video editing or export.

**Undo**: ⌘Z and ⇧⌘Z undo and redo culling, keyword, album and pair changes, including
changes made to many photos at once.

Photos on a volume that is not connected show an offline badge. Their cached
previews still display, and nothing is removed from the catalog.

## Repository layout

| path | contents |
|---|---|
| `Sources/PhotoCore` | catalog (GRDB), importer, metadata, edit stack, preview pipeline, branding |
| `Sources/PhotoApp` | SwiftUI shell, AppKit grid and loupe |
| `Sources/PhotoFixtures` | synthetic JPEG/HEIC and Bayer DNG writers for tests and benchmarks |
| `Sources/PhotoBench` | synthetic library generator and profiling (`photobench`) |
| `Sources/StringCatalogCompiler` | String Catalog compiler used by the build script |
| `Sources/AppIconCompiler` | turns `Support/AppIcon.png` into the app's `.icns` |
| `Tests/PhotoCoreTests` | Swift Testing suites |
| `Branding.xcconfig` | brand-dependent build settings |
| `Support/` | Info.plist template, version numbers, icon artwork |
| `docs/PHASE1_PLAN.md` | schema and architecture decisions |
| `docs/PROFILING.md` | timings with a 10k/50k synthetic library |

## Data locations

- Catalog: `~/Library/Application Support/<app folder>/Library/catalog.sqlite`
- Previews: `~/Library/Caches/<bundle id>/Previews/` (safe to delete; regenerated on demand)

## Development options

Every launch option takes exactly one value (AppKit treats a stray argument as a
document to open, which keeps the main window from appearing).

| option | effect |
|---|---|
| `--library-root <folder>` | use a self-contained catalog and cache in `<folder>` |
| `--benchmark-scroll <report.json>` | run the grid scroll benchmark, write the report, quit |
| `--debug-script "<commands>"` | drive the UI and take window snapshots (see `DebugScript.swift`) |

`photobench` generates synthetic libraries and profiles import, preview
generation, cache reads and catalog queries. See
[docs/PROFILING.md](docs/PROFILING.md) for results and commands.
