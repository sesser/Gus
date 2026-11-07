# User guide

How to use the app day to day: importing, culling, keywords, albums,
sidecars, videos and HDR. See the [README](../README.md) to build it.

## Importing and culling

**Importing from a card**: **File ▸ Import from Card or Folder…** (⌘I) opens the
import window; it also opens by itself when a card (any volume with a `DCIM`
folder) is inserted, unless that is turned off in **Settings**. The source
pop-up in the toolbar lists cards and chosen folders (⌘O chooses another,
⌘R rescans); the subtitle shows how many shots are picked and the newest
photo's camera with its shutter count. Each shot has a check box: click a
tile, or Space on the focused one, to include or leave it out; shift-click
sets a range; ⌘A and ⇧⌘A (or the toolbar's Selection menu) pick all or none,
and the same menu shows videos and the photos already in the library (marked
In Library and never imported). RAW+JPEG pairs are one tile. The options
inspector (⌥⌘I) sets the destination folder and
the subfolder and file name templates (tokens such as `{capture:yyyy-MM-dd}`,
`{import:yyyy}`, `{model}`, `{lens}`, `{name}`, `{number}`, `{seq:4}`,
`{counter:5}`, `{job}`, shown in the field as named pills such as Capture
Year; the Insert menu adds them, typing `{…}` makes one when you leave the
field, copy and paste keep the `{…}` form, and an example under the field
shows the result), the project (a new one named from a template, or an existing one), a
job code and a metadata preset (creator, copyright such as
`© {capture:yyyy} Your Name`, usage terms, description, contact; written to sidecars, the
copies stay identical to the originals). **Import N Photos** in the toolbar
(or Return) starts; it becomes **Stop** (⌘.) while copying, with progress
beside it. Every copy is read back and compared by hash before it counts. Optionally, the originals that were copied and checked
are deleted from the card (after a confirmation) and the card is ejected.

Choose **File ▸ Add Folder Without Copying…** (⇧⌘I) to add photos where they are, without
copying: pick a folder. Photos in it and its
subfolders (CR3, CR2, NEF, ARW, DNG, RAF, ORF, RW2, HEIC, JPEG, TIFF, PNG) and
videos (MOV, MP4, M4V) are
added to a new project named after the folder. Duplicates (same content
anywhere in the library) are skipped, and so are files already imported from
the same place. Originals are never moved, copied or modified.

You can also drag one or more folders from Finder onto the browser (grid or
loupe) or the sidebar's Projects list. Each folder is imported the same way, in
place, as its own project named after it; several import one after another,
with the folder and its place in the batch shown in the toolbar's Activity item. Folders
dropped, or chosen with **Add Folder Without Copying…**, while an import runs join the queue. Files and packages among the
dropped items are ignored (Activity says how many), and a folder inside
another dropped folder is imported with it. A project of the same name already
in the library is left alone: the import makes a new project holding only the
photos the library does not have yet, and a folder with nothing new makes none.

| key | grid | loupe |
|---|---|---|
| arrows | move selection (⇧ extends) | ← → previous / next photo |
| Home, End, Page Up, Page Down | jump | first / last photo |
| Return, Space, double-click | open the loupe | back to the grid |
| Esc | | hides the sharpening map, else leaves review, else back to the grid |
| F | review the focused photo | enter or leave review |
| Z, click | | toggle fit / 100 % at the clicked point (⌥-scroll and pinch zoom too; drag pans) |
| 0–5 | set rating | set rating |
| [ and ] | lower / raise rating | lower / raise rating |
| P, X, U | pick, reject, clear flag | pick, reject, clear flag |
| ⌥1–⌥7, ⌥0 | color label red…gray, clear | color label |
| ⌘= and ⌘− | thumbnail size | zoom in / out |
| ⌘Return | switch grid / loupe | switch grid / loupe |
| ⌥⌘B | | show / hide the film strip |
| ⇧⌘A | keep only the focused photo selected | |
| ⌘. | stop the newest export, folder add or import (**File ▸ Stop Export**, **Stop Adding Folders** or **Stop Import**) | same |
| ⌘K | add keywords | add keywords |
| ⌘I | import from a card or folder | |
| ⌘N, ⌥⌘N | new album, new smart album | |
| ⌫ | remove from the album on screen | |
| ⌘Z, ⇧⌘Z | undo, redo | undo, redo |

**Review** (View ▸ Enter Review, F): the loupe on the focused photo with the
sidebar and inspector hidden, full screen, and the toolbar shown only when
the pointer reaches the top. Culling keys, arrows and Z keep working; ⌥⌘I
brings the inspector back. F or Esc puts the window back as it was and stays
in the loupe; Return or Space goes back to the grid.

**Film strip**: the loupe shows the current source's photos, filtered and
sorted as in the grid, in a row between the photo and the caption line, with
the photo on screen in the middle and outlined. Each thumbnail shows the
photo's flag and color label, and a mark for videos and offline photos;
rejected photos are dimmed. Pointing at one shows its name, rating, flag and
label. Click a thumbnail to move to that photo, as the arrow keys do; the
strip centers on whatever photo the loupe moves to. Scrolling the strip
(trackpad, mouse wheel or scroller) only scrolls it and never changes the
photo. The **Film Strip** button at the end of the caption line, or **View ▸
Show Film Strip** / **Hide Film Strip** (⌥⌘B), shows and hides it; it is shown
at first, and the app remembers your choice. Drag the handle on its top edge
to make the thumbnails larger or smaller: when you let go it settles on the
nearest of five sizes, kept across launches and separate from the grid's
thumbnail size. Double-click the handle to go back to the largest size that
fits. The strip never takes more than a quarter of the loupe's height, so a
short window shows smaller thumbnails, which grow back with the window. Review
hides the strip and its button; leaving review brings them back. The video
loupe has it too.

Changes are saved to the catalog immediately. In the grid they apply to every
selected photo. **Photo ▸ Advance After Rating** moves on to the next photo after
each change. Rating and flag filters, the sort order and the search field are
in the toolbar (the Filter and Sort menu, and **View ▸ Filter** and **Sort
By**); each sidebar source keeps its own, and the source selected last is
selected again at launch. Photos that stop matching stay visible until the
filter changes, so they do not jump away while you cull. The toolbar's
Activity item shows imports, exports and other work in progress, with Stop,
and the latest messages.

A RAW file and a JPEG or HEIC with the same name in the same folder are a
pair. **View ▸ Group RAW+JPEG Pairs** shows each pair once, as the RAW unless
**Photo ▸ RAW+JPEG Pair** says otherwise; its badge reads `RAW+JPEG` (the file on
screen first). Ratings, flags, labels, keywords and albums always apply to both
files. **View ▸ Show / Hide File Names** toggles the name and type badge under each
thumbnail.

**Keywords**: ⌘K opens a popover at the top of the grid or loupe that adds keywords to the
selected photos, completing from the keywords already in the library (↓ ↑ to
choose, Tab or Return to take one, Return to add, Esc to close). The inspector
(**View ▸ Show Inspector**, ⌥⌘I; **View ▸ Info** ⌥⌘1 and **Adjust** ⌥⌘2 pick the tab) lists the selection's keywords with counts
("dog, 12 of 30"), removes them, and shows file details. The sidebar lists every
keyword; click one to see its photos, or right-click to rename (renaming onto
an existing keyword merges the two) or delete it. Keywords, ratings and labels
embedded in files by other apps or the camera (IPTC, XMP) are read at import.

**Suggested keywords**: after each import, Apple's on-device image classifier
looks at the new photos (nothing leaves the Mac) and the inspector shows what it
found as chips. Click one to add it to the selected photos it was suggested
for, or × to stop suggesting it for them. **Photo ▸ Suggest Keywords** (⇧⌘K)
analyzes the selection, for photos imported before, and shows the inspector's
Info tab with Keywords open, where the chips appear. The labels are generic
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
artist, copyright and description, with a live count. Right-click albums to rename,
edit or delete them.

**XMP sidecars**: ratings, flags, labels, keywords, creator, copyright, description,
usage terms and contact details are written to an `.xmp` file next to each
original a moment after they change (`IMG_0412.xmp`; a RAW+JPEG pair shares
one), so other apps can read them. Existing sidecars are edited in place and
keep everything other apps put in them. Sidecars present at import, or
`IMG_0412.CR3.xmp` ones, are read. Originals are never written, JPEG, HEIC and
DNG included. The library is the source of truth, but nothing another app
changed is overwritten: at launch, when a volume mounts and with **File ▸ Check
for Changes on Disk**, sidecars and originals changed outside the app are listed
under **Library ▸ Changed on Disk**, and the inspector compares the library's
values with the file's so you can keep either, or choose per field (keywords can
be merged). Writing can be turned off in **Settings**.

**Videos** (MOV, MP4, M4V) are catalogued like photos by both kinds of import
(in the import window, **Show Videos** in the Selection menu or the View menu
lists them): their poster frame is the
thumbnail, the grid shows their length, and the loupe plays them (Space, or
**View ▸ Play / Pause**, plays and pauses; the arrow and culling keys still move between and rate items, a
double-click on the picture goes back to the grid, and a right-click or
Control-click on it shows the rating, flag, label, keyword and album commands,
**Play** / **Pause** and **Show Grid**). They
take ratings, keywords, albums and sidecars. There is no video editing or export.

**HDR**: on a display with extended dynamic range, the loupe shows HDR photos
with highlights above white: floating-point DNGs (such as Lightroom's HDR
merges) and HEIC and JPEG files with a gain map or HLG or PQ encoding. An **HDR**
badge in the caption line under the photo says so. Camera raws stay SDR. The loupe first shows the
cached preview, then the HDR render from the original, so offline originals stay
SDR. Thumbnails and cached previews are always SDR. **View ▸ Hide HDR Highlights** turns it off.

**Crop & Straighten** follows **Presets** at the top of the Adjust tab. **Crop** shows
the whole photo in the loupe under a crop frame with a rule-of-thirds grid: drag
inside the frame to move it, a corner or an edge to resize it, and outside it to
straighten. The buttons under it hold the frame to 1:1, 3:2, 4:3 or 16:9 (pick
the same one again to swap portrait and landscape) or free it; the arrows turn
the frame a quarter turn; the **Straighten** slider tilts it up to 45° either
way, over a finer grid, and the image grows so it always fills the frame.
**Done** (or Return, or `C` again) saves the crop as one undo step and folds
the heading; Esc cancels. `C` (**Adjust ▸ Crop**) starts cropping, from the
grid too. **Adjust ▸ Reset Crop** (or the heading's reset button) gives the photo
in the loupe its own frame back, without turns or straightening, as one undo step. **Adjust ▸ Rotate Left / Right** (⌘[ / ⌘]) and the heading's arrows,
outside a crop, turn the photo at once as one undo step; in the grid they turn
every selected photo. **Auto Exposure**, **Reset All Adjustments**, **Paste
Adjustments** and **Apply Preset** also act on every selected photo in the
grid, as one undo step; videos are left out. Moving to another photo keeps the crop. Copy and Paste Adjustments
carry the crop; presets never do. Photos shot at 1:1, 3:2 or 16:9 on a camera
with a 4:3 sensor show the camera's crop; on Olympus, OM System and Panasonic
raw files, cropping starts from that frame over the whole sensor, so it can be
widened. Other raw formats are cropped within the frame their decoder gives.

**Sharpening Map**: Masking (Details ▸ Sharpening) holds sharpening back where
the photo is smooth, such as skies and skin, and keeps it on edges. To see where
it goes, turn on the **Sharpening Map** toggle under Masking, or choose
**Adjust ▸ Show Sharpening Map** (also in the loupe's context menu, which, like
the menu item, shows the inspector with Masking in view). The loupe then shows
the sharpening map in place of the photo, in the same frame and at any zoom:
white areas are sharpened, gray areas in part, and black areas not at all. A
**Sharpening Map** badge in the caption says so. The map follows Masking and
the other controls as you change them; once you pause, it is replaced by the map
of the full-size photo, which is what an export sharpens (a small spinner in the
caption shows while that takes more than half a second). With Amount at 0 or
Sharpening turned off, the map still shows where sharpening would go; the badge
reads **Sharpening Map · Not Applied** when nothing at all is sharpened, and the
text under the toggle says why. Masks with Sharpness still sharpen the areas they
cover. Press Esc, click the toggle, or choose **Adjust ▸ Hide Sharpening Map** to see
the photo again. While the map is shown, hovering a preset or look-up table
shows the map with it. The map is only a view: it is not saved, has no undo step, and never
reaches thumbnails, previews or exports. It ends when you move to another photo,
crop, paint, pick colors, add a mask, show the original or the mask overlay,
enter review or go back to the grid. Hiding it brings back the mask overlay if
it was on, and the original if it was on and no value changed meanwhile.

**Machine learning noise reduction** (raw files only): select **Use machine
learning** at the top of Details ▸ Noise Reduction to decode the photo with the
machine learning model in the macOS raw decoder, which reduces noise while
keeping edges. It runs on this Mac, and the app never downloads anything for
it. It is off unless you turn it on, photo by photo, and selecting or
deselecting it is one undo step. While it applies, **Luminance** sets its
amount and **Color** is dimmed: its value is kept and applies again when you
deselect **Use machine learning**. The Decoder pop-up (Light ▸ Profile) shows
the same setting as **9.dng (machine learning)** (or **9** for camera raw
files); choosing it turns machine learning on, and choosing another version
turns it off and uses that version. Rendering with it takes longer, often a
second or more: the photo you see stays on screen, a small spinner in the
caption shows after half a second, and you can keep moving between photos and
culling meanwhile. Copy and Paste Adjustments, presets that include Noise
Reduction and Reset All carry it or clear it; pasting onto files that are not
raw leaves it off for them, and Activity says how many. It needs macOS 27 or
later and a camera the decoder supports. Elsewhere the check box is dimmed and
says why. A photo that asks for it where it cannot apply (on an older Mac, for
an unsupported camera, or when the decode fails) keeps the setting, renders
with Luminance and Color instead, and shows a **Machine Learning Not Applied**
badge in the caption, whose tooltip gives the reason. Exports say in Activity
how many photos were written without it, and why.

**Presets** (the Adjust tab's first heading, and **Adjust ▸ Apply Preset**)
apply saved adjustments to the photo in the loupe or to every selected photo.
The heading shows the focused photo with each preset, by collection; in the
loupe, hovering a picture shows the photo with that preset, and clicking it
applies the preset. Its **Save…**, **Import…** and **Manage…** buttons match
the menu commands below. **Copy Adjustments**, **Paste Adjustments** and
**Reset All Adjustments** are in the ⋯ menu at the top of the Adjust tab, next
to **Original** (`\`). **Save Adjustments as
Preset…** asks for a name, a collection and the groups of controls to include
(those the photo changes are checked): applying the preset replaces only those
and leaves the photo's other settings alone. **Import Presets…** reads this
app's preset files and Lightroom presets (`.lrtemplate`, `.xmp`, and
`.dng` mobile presets), or folders of them. A folder becomes a collection unless
its presets name their own, and a pack that holds a preset in several formats
gives one copy. Lightroom settings with no equivalent here (calibration,
masks, texture, crop, lens corrections and the like) are left out, and the
import lists them. **Manage Presets…** opens a sheet that renames, moves,
exports and deletes presets and collections, and changes what each includes;
changes apply at once (deleting a preset or a collection asks first), and Done
closes it. An exported preset
file carries the look-up tables its presets use, so it looks the same in
another library; double-clicking one in the Finder imports it.

**Export** (**File ▸ Export…**, ⇧⌘E) writes the selected photos, or the one in
the loupe, to a folder with their adjustments. A RAW+JPEG pair is exported once,
from its RAW; videos are not exported. A sheet on the library window sets:

- **File names**: the original name, or a template with the import tokens, plus
  `{export:yyyy-MM-dd}` for today and `{seq:4}` for the position in the export.
- **File type**: JPEG with a quality setting, or TIFF at 8 or 16 bits per
  channel with no compression, LZW or ZIP. Color space: sRGB (the default),
  Display P3, Adobe RGB (1998) or ProPhoto RGB.
- **Size**: full size, fit within a box, long edge, short edge or a percentage.
  Photos are never enlarged. Pixels per inch only change the print size. Resized
  exports can get output sharpening for screen or print.
- **Metadata**: all of it, all except location (GPS and place names), copyright
  and contact only, or none. Keywords, description, creator and copyright come from
  the library. Ratings and labels are never included.
- **Watermark**: a PNG (transparent areas stay see-through), placed in one of
  nine positions with a margin, size and opacity, with a preview of the first photo
  while a watermark is on.

Settings can be saved as **presets**. When files with the same names are
already in the folder, the sheet asks once whether to keep both (the new files
get numbered names), replace them or skip them. The export runs in the
background, with progress and Stop in the toolbar's Activity item. When it
ends, Activity reports the result; there is no alert. If any photos could not
be exported (an offline volume, for instance), the report is a warning that
lists up to ten of them with the reason for each. Photos skipped because you
chose to skip existing files get a note of their own. The Finder can show the
files when it is done.

**Undo**: ⌘Z and ⇧⌘Z undo and redo culling, keyword, album and pair changes,
adjustments, crop and rotation, and the Info tab's descriptive fields (title,
description and the like), including changes made to many photos at once.

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

A test launch must name its library with `--library-root`: a copy of the app
with a bundle identifier other than the release one (such as
`<release id>.debugtest`), a launch with `--debug-script` or
`--benchmark-scroll`, and `swift run` (which has no bundle identifier).
Without it the app writes the reason to standard error and quits with status
64, before it opens or creates anything in the data locations above. Unless
the launch has `--debug-script` or `--benchmark-scroll`, it first shows an
alert that says so; a scripted launch ends at once, without one. The
bundle identifier only separates preferences, so without this a test copy
would open your library.

`photobench` generates synthetic libraries and profiles import, preview
generation, cache reads and catalog queries. See
[PROFILING.md](PROFILING.md) for results and commands.

## Scripting

`photocli` (built with `swift build --product photocli`) works on a library
from the terminal: `render` a file or a version to PNG, JPEG or TIFF with
adjustments, `query projects` and `query images` (smart-album rules as JSON),
`develop` (set and reset adjustments; `--dry-run` only shows the result),
`rate`, `flag`, `label`, `export`, and `mask list`, `mask add`, `mask set` and
`mask remove` (a version's local adjustments; `--dry-run` only shows the
result). `noiseReduction.machineLearning=true` turns on machine learning noise
reduction; `render` and `export` report in their JSON whether it was applied,
and why not. `photocli adjustments` lists every adjustment and its range;
`photocli help` lists the commands. Each prints one JSON object. Pass
`--library-root` as for the app; without it the standard library is used.

It can read a library at any time, but it changes one only while the app has
it closed: while the app is open, `develop`, `rate`, `flag`, `label`,
`mask add`, `mask set` and `mask remove` refuse and say so. Changes made from
the terminal cannot be undone in the app.
