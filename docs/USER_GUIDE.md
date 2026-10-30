# User guide

How to use the app day to day: importing, culling, keywords, albums,
sidecars, videos and HDR. See the [README](../README.md) to build it.

## Importing and culling

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

You can also drag one or more folders from Finder onto the browser (grid or
loupe) or the sidebar's Projects list. Each folder is imported the same way, in
place, as its own project named after it; several import one after another,
with the folder and its place in the batch shown in the status bar. Folders
dropped while an import runs join the queue. Files and packages among the
dropped items are ignored (the status bar says how many), and a folder inside
another dropped folder is imported with it. A project of the same name already
in the library is left alone: the import makes a new project holding only the
photos the library does not have yet, and a folder with nothing new makes none.

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

**HDR**: on a display with extended dynamic range, the loupe shows HDR photos
with highlights above white: floating-point DNGs (such as Lightroom's HDR
merges) and HEIC and JPEG files with a gain map or HLG or PQ encoding. An **HDR**
badge in the info bar says so. Camera raws stay SDR. The loupe first shows the
cached preview, then the HDR render from the original, so offline originals stay
SDR. Thumbnails and cached previews are always SDR. **View ▸ Show HDR** turns it off.

**Crop, Rotate, Straighten** is the Adjust tab's first heading. **Crop** shows
the whole photo in the loupe under a crop frame with a rule-of-thirds grid: drag
inside the frame to move it, a corner or an edge to resize it, and outside it to
straighten. The buttons under it hold the frame to 1:1, 3:2, 4:3 or 16:9 (pick
the same one again to swap portrait and landscape) or free it; the arrows turn
the photo a quarter turn; the **Straighten** slider tilts it up to 45° either
way, over a finer grid, and the image grows so it always fills the frame.
**Done** (or Return) saves the crop as one undo step and folds the heading;
Esc cancels. Moving to another photo keeps the crop. Copy and Paste Adjustments
carry the crop; presets never do. Photos shot at 1:1, 3:2 or 16:9 on a camera
with a 4:3 sensor show the camera's crop; on Olympus, OM System and Panasonic
raw files, cropping starts from that frame over the whole sensor, so it can be
widened. Other raw formats are cropped within the frame their decoder gives.

**Presets** (the Adjust tab's **Presets** heading, at its bottom, and **Photo ▸ Apply Preset**)
apply saved adjustments to the photo in the loupe or to every selected photo.
The heading shows the focused photo with each preset, by collection; in the
loupe, hovering a picture shows the photo with that preset, and clicking it
applies the preset. Its **Save…**, **Import…** and **Manage…** buttons match
the menu commands below. **Copy Adjustments** and **Paste Adjustments** sit
at the bottom of the Adjust tab. **Save Adjustments as
Preset…** asks for a name, a collection and the groups of controls to include
(those the photo changes are checked): applying the preset replaces only those
and leaves the photo's other settings alone. **Import Presets…** reads this
app's preset files and Lightroom presets (`.lrtemplate`, `.xmp`, and
`.dng` mobile presets), or folders of them. A folder becomes a collection unless
its presets name their own, and a pack that holds a preset in several formats
gives one copy. Lightroom settings with no equivalent here (calibration,
masks, texture, crop, lens corrections and the like) are left out, and the
import lists them. **Manage Presets…** renames, moves, exports and deletes
presets and collections, and changes what each includes. An exported preset
file carries the look-up tables its presets use, so it looks the same in
another library; double-clicking one in the Finder imports it.

**Export** (**File ▸ Export…**, ⇧⌘E) writes the selected photos, or the one in
the loupe, to a folder with their adjustments. A RAW+JPEG pair is exported once,
from its RAW; videos are not exported. The window sets:

- **File names**: the original name, or a template with the import tokens, plus
  `{export:yyyy-MM-dd}` for today and `{seq:4}` for the position in the export.
- **File type**: JPEG with a quality setting, or TIFF at 8 or 16 bits per
  channel with no compression, LZW or ZIP. Color space: sRGB (the default),
  Display P3, Adobe RGB (1998) or ProPhoto RGB.
- **Size**: full size, fit within a box, long edge, short edge or a percentage.
  Photos are never enlarged. Pixels per inch only change the print size. Resized
  exports can get output sharpening for screen or print.
- **Metadata**: all of it, all except location (GPS and place names), copyright
  and contact only, or none. Keywords, caption, creator and copyright come from
  the library. Ratings and labels are never included.
- **Watermark**: a PNG (transparent areas stay see-through), placed in one of
  nine positions with a margin, size and opacity, with a preview of the first photo.

Settings can be saved as **presets**. When files with the same names are
already in the folder, the window asks once whether to keep both (the new files
get numbered names), replace them or skip them. The export runs in the
background, with progress and a stop button in the status bar. If anything
could not be exported (an offline volume, for instance), an alert says why. The
Finder can show the files when it is done.

**Undo**: ⌘Z and ⇧⌘Z undo and redo culling, keyword, album and pair changes, including
changes made to many photos at once.

Photos on a volume that is not connected show an offline badge. Their cached
previews still display, and nothing is removed from the catalog.

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
[PROFILING.md](PROFILING.md) for results and commands.
