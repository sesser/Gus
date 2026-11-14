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
added to a new project named after the folder. Files already in the library
(same content anywhere in it) are skipped, and so are files already imported
from the same place. Originals are never moved, copied or modified.

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
| Esc | | cancels picking a fringe color, else hides the fringe or sharpening map, else leaves review, else back to the grid |
| F | review the focused photo | enter or leave review |
| S | compare the one or two selected photos side by side | compare the photo with another, or stop comparing |
| A | | while comparing, make the other photo the active one |
| - and = | | while picking a color, pixel magnifier zoom out / in |
| Z, click | | toggle fit / 100% at the clicked point (⌥-scroll and pinch zoom too; drag pans) |
| 0–5 | set rating | set rating |
| [ and ] | lower / raise rating | lower / raise rating |
| P, X, U | pick, reject, clear flag | pick, reject, clear flag |
| ⌥1–⌥7, ⌥0 | color label red…gray, clear | color label |
| ⌘= and ⌘− | thumbnail size | zoom in / out |
| ⌘Return | switch grid / loupe | switch grid / loupe |
| ⌥⌘B | | show / hide the film strip |
| ⌥⌘3 | | show / hide the History panel (**View ▸ Show History**) |
| ⇧⌘A | keep only the focused photo selected | |
| ⌘. | stop the newest export, folder add or import (**File ▸ Stop Export**, **Stop Adding Folders** or **Stop Import**) | same |
| ⌘K | add keywords | add keywords |
| ⌘I | import from a card or folder | |
| ⌘N, ⌥⌘N | new album, new smart album | |
| ⌫ | remove from the album on screen | |
| ⌘D | make a copy of each selected photo (**File ▸ Duplicate**) | make a copy of the photo |
| ⇧⌘R | show the originals in the Finder (**File ▸ Show in Finder**) | same |
| ⌘⌫ | remove from the library, after a confirmation (**File ▸ Remove from Library…**) | same |
| ⌘Z, ⇧⌘Z | undo, redo | undo, redo |

**Review** (View ▸ Enter Review, F): the loupe on the focused photo with the
sidebar and inspector hidden, full screen, and the toolbar shown only when
the pointer reaches the top. Culling keys, arrows and Z keep working; ⌥⌘I
brings the inspector back. F or Esc puts the window back as it was and stays
in the loupe; Return or Space goes back to the grid.

**Comparing two photos** (View ▸ Compare Side by Side, S): the loupe shows two
photos next to each other, each as the loupe shows it alone. Select two
photos in the grid and press S; the earlier one is on the left, and the one
you were on is the active one (see below). With one photo selected, or from
the loupe, S keeps that photo on the left and puts the next photo in the
source beside it (the previous one at the end). The photo beside it is then
the active one, so the arrow keys and the film strip choose the second photo
right away while the photo you came with stays put; press A to rate the
photo you came with. Videos and photos whose originals are offline can't be
compared, and neither can the RAW and the JPEG of one pair shown as two
items; an alert says why.

One photo is the *active* one: its side has a ring round it and its name is
bold in the caption line. Everything acts on it only: the rating, flag and
label keys, keywords, albums, Export, Show in Finder, the Info tab and the
window's title. **A** (View ▸ Switch to Right Photo / Switch to Left Photo)
or a click on the other photo makes that one active; that click does nothing
else. The arrow keys, Home and End move the active side to another photo
while the other side stays, skipping videos, offline photos and the photo on
the other side; so does a click on a film strip thumbnail, and a click on the
other side's thumbnail makes that side active. In the strip the active photo
is outlined as usual, and the other one is highlighted without an outline. With **Advance After Rating**
on, the active side moves to the next photo after each change, so you can
reject the weaker photo and get the next one in its place.

Zoom and position are linked: Z, a click, ⌘= and ⌘−, pinching, scrolling and
dragging on either photo move both to the same place at the same size, so two
frames of a burst line up at 100%. Zoom to Fit fits each photo to its own
side. ⌘= and ⌘− take both photos to the same size; a photo stops at its own
fit when the step would make it smaller than that, ⌘− goes on working until
both are fitted, and ⌘= takes them back up. **View ▸ Link Zoom and Position**,
or the link button in the middle of the caption line, turns that off so each
photo zooms and scrolls on its own; the app remembers your choice. Turning it
back on puts the other photo where the active one is. At 100% each photo is
sharp once its full-size picture has been rendered, a moment after zooming in
or moving to another photo.

Nothing is edited while comparing: the Adjust tab says so and offers **Stop
Comparing**, and the Adjust menu's editing commands, Show Original, the
History panel, Duplicate, Remove from Album and Remove from Library are off. S again (or
**Stop Comparing**) goes back to the loupe on the active photo, with the two
photos still selected in the grid. S once more brings the same two back as
they were: each on the side it was on, with the same one active. The app
remembers that until you go back to the grid.
Return, Space, a double-click or Esc go back to the grid. Review (F) works
while comparing and gives the two photos the whole screen, which helps on a
small display; Esc there leaves review first.

**Film strip**: the loupe shows the current source's photos, filtered and
sorted as in the grid, in a row between the photo and the caption line, with
the photo on screen in the middle and outlined. Each thumbnail shows the
photo's flag and color label, and a mark for videos, offline photos and copies;
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
artist, copyright and description, and whether the photo is a copy, with a live count. Right-click an album to
rename or delete it, or a smart album to edit or delete it.

**Renaming a project or an album**: select it in the sidebar and choose **File ▸
Rename “‹name›”**, press Return while the sidebar has the keyboard, or
right-click it and choose **Rename**. Its name becomes a text field in place,
with the whole name selected: Return saves, Esc puts the old name back, and
clicking elsewhere saves too, as does folding or hiding the row away (its
section, its project, the sidebar). Spaces around the name are dropped, an empty
name is refused (the old one stays), and two projects, or two albums, may have
the same name. The name is the library's only, and no sidecar changes. A
project's folder on disk keeps its name (the row's tooltip still shows its
path). An album keeps its photos, and moves to its place in the list, which
is by name. Renaming is one undo step. A smart album is renamed in its editor
(**File ▸ Edit Smart Album…**).

**Copies**: **File ▸ Duplicate** (⌘D, and **Duplicate** in the grid's and the
loupe's context menus) makes a copy of each selected photo, or of the photo in
the loupe, so that one photo can have two or more treatments (color and black
and white, two crops) without importing its file twice. No file is copied: a
copy is another item in the library for the same original. It starts with the
original's adjustments, rating, flag, color label, keywords and albums as they
are at that moment, and from then on these are its own, as is its edit
history, which starts empty: changing the copy never changes the original, and
changing the original never changes the copy. A copy appears right after its
original (and after that photo's earlier copies) and becomes the selection; in
the loupe, the loupe moves to it. Afterwards it sorts by its own values, so
under **Sort By ▸ Rating** a copy rated differently moves away from its
original; by capture date and by file name the two stay together. Copies count
as photos in the window's subtitle and in the sidebar.

A copy is named after its original, the way the Finder names duplicates:
`IMG_0412 copy`, then `IMG_0412 copy 2`, `IMG_0412 copy 3`. The grid and the
film strip mark a copy with two overlapping squares at the top-right corner of its
picture, the loupe's caption shows a **Copy** badge, and the window title
shows the copy's name. The Info tab still describes the file, which is the
original's, and **Show in Finder** reveals that file. A copy can be duplicated
too; the result is one more copy of the same original. Videos are not
duplicated: with only videos selected the command is dimmed, and videos in a
mixed selection are left out, which the toolbar's Activity item reports. For a
RAW+JPEG pair, Duplicate copies the one file the cell shows (the RAW, unless
**Photo ▸ RAW+JPEG Pair** says otherwise); the copy is not part of the pair, so
its rating, flag, label, keywords and albums are not shared with the other
file. Photos on a volume that is not connected can be duplicated. Duplicate is
dimmed while a crop is being edited (finish or cancel it first), and ⌘D acts
only while the grid or the loupe has the keyboard. All the copies of one
Duplicate are one undo step: **Edit ▸ Undo Duplicate** takes them away and
goes back to the originals, and Redo brings the same copies back. A copy's
values are kept in the library only: its rating, flag, label and keywords are
never written to a sidecar file, which holds the original's.

**Show in Finder** (**File ▸ Show in Finder**, ⇧⌘R, and the context menus of
the grid, the loupe and a video) reveals the originals of the selected photos,
or of the photo in the loupe, in the Finder: photos in one folder open one
Finder window with all of them selected, and photos in several folders open
one window per folder. A grouped RAW+JPEG pair shows its RAW; with **View ▸
Group RAW+JPEG Pairs** off, each file shows itself. Photos whose originals are
offline or no longer where the library has them are left out, and the
toolbar's Activity item says how many; when every selected photo is offline
the command is dimmed. While the sidebar has the keyboard, the same command
reveals the selected project's folder instead (also **Show in Finder** in the
project's context menu). It is dimmed, and left out of the context menu, for a
project that was not imported from one folder, whose folder is gone or on a
volume that is not connected, or whose folder is a whole card or disk: the app
never opens a volume itself.

**Removing photos from the library**: **File ▸ Remove from Library…** (⌘⌫,
and the last item of the photo context menus) takes the selected photos, or
the photo in the loupe, out of the library. It asks first, and Return does not
confirm: click **Remove**, or cancel with Esc or ⌘.. The files and their
sidecar files stay on disk, unchanged; what goes is what only the library
holds: the photos' edits and edit history, and their ratings, flags, labels,
keywords and album memberships in the library. Keywords and albums themselves
stay, empty if need be. Removing either file of a RAW+JPEG pair removes both,
and the confirmation says how many files that makes. Removing a photo also
removes its copies (**File ▸ Duplicate**), and the confirmation says how many
go with it. Removing a copy removes only the copy: the original, its edits and
its file are not affected. Photos on a volume that
is not connected can be removed like any other. A removal cannot be undone,
and it empties Edit ▸ Undo, since earlier steps may be about photos that are
gone. The same files can be imported again later; they come in as new photos,
without their edits (ratings and keywords the app wrote to sidecars are read
back at import). ⌘⌫ removes photos only while the grid or the loupe has the
keyboard, so in a text field it deletes text as usual. While an import or a
folder add is running, the command is dimmed, and left out of the context
menus, until it ends; so is **Remove Project from Library…**.

**Removing a project**: select it and choose **File ▸ Remove Project from
Library…**, or right-click it. The project goes with all its photos, by the
same rule, and so do the albums and smart albums made inside it (the
confirmation says how many); albums of the library and of other projects stay,
without those photos. The folder, its files and their sidecar files stay on
disk. This cannot be undone either. *Remove* is the word for photos and
projects, whose files stay on disk; *delete* is for things that exist only in
the library (albums, smart albums, keywords, presets). File ▸ Delete stays
dimmed for a project.

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

**Editing at 100%**: at 100% and closer (`Z`, or **View ▸ Zoom to 100%**),
the loupe shows the photo's own pixels while you change a value, so you can
judge fine detail without letting go. A heavy edit updates less often but keeps
its detail. When you start a change, pan or zoom, part of the photo can look
soft for a moment. On raw files, White Balance, Profile and Noise Reduction
stay soft while the value moves, and the detail arrives once you hold still,
even with the control still held. If that takes more than half a second, a
small spinner shows in the caption. The histogram always describes the whole
photo, and at these zooms it can lag until you pause.

**Raw files macOS can't decode**: when the macOS raw decoder has no image for a
raw file (on macOS 27.2, the Fujifilm X-E3's lossless compressed files), the app decodes it with its own
decoder (LibRaw) instead of showing nothing. Such a photo has the camera's white
balance but not the macOS decoder's profile and contrast, so it starts out
flatter and darker than a raw macOS decodes. A Fujifilm file gets the camera's
own frame (6000 x 4000 for an X-E3) and the lens corrections the camera stored
in it, as the macOS decoder applies them to the raws it reads: distortion
(straight lines are straight), color fringing toward the corners, and corner
shading. There is no control for them; they line up with the camera's own JPEG
to within a pixel or two of the full-size photo, a little more in the far
corners. Blown highlights stay white right to the corners. A file shot in a
camera's 1.25x crop mode, or one from an old Super CCD camera, is shown
uncorrected in the frame its decoder gives, as are files of other makers. You adjust it like any other photo; what differs is what differs for a
JPEG. In the Adjust tab a note stands in place of **Profile**. White Balance
offers **As Shot**, **Auto** and **Custom**, with Temperature and Tint relative
to the camera's setting (no Kelvin scale and no Daylight to Flash). Noise
Reduction has **Luminance** only, and **Use machine learning** is dimmed unless
a paste or preset turned it on; it then says it isn't applied, and Luminance
applies instead. Tone, Presence, Tone Curve, Color Mixer, Color Grading, masks,
Lens, Effects, Sharpening and crop work as usual. Pasted adjustments or presets from a raw macOS decodes keep their Kelvin
white balance, Profile and Color noise reduction, which do nothing here. These
photos take longer to open, most of all at 100% or with a crop that needs the
whole frame (several seconds for a 24-megapixel Fujifilm file). If a later macOS
decodes the camera, macOS decodes these photos from then on: they look
different, a Temperature or Tint set meanwhile no longer applies, and thumbnails
made before keep the old look until the photo is edited or the cache is deleted.

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

**Lens** (after Details) removes the colored fringes a lens leaves along
high-contrast edges. It has two groups, each with its own check box: **Color
Fringes** and **Color Alignment**. Both are off until you use them, and a photo
you never touch renders exactly as before.

**Color Fringes** turns a fringe's color gray where it lines a high-contrast
edge: purple or green halos along branches against the sky, window frames,
backlit hair, and the soft rims of out-of-focus highlights. It has two slots,
**Color 1** and **Color 2**, because purple and green fringes often appear
together. To fill a slot, click its eyedropper and click a colored fringe in
the photo: the pointer is a crosshair over the photo, and the **pixel magnifier**
beside it shows the photo's own pixels, with an outline around the one a click
takes and that pixel's R, G, B and L values (0–255, Display P3). At 100% and
closer that is the pixel under the pointer; zoomed out further, the most colorful
pixel under it. The slot then shows a swatch and the color's name. A drag still pans while
the eyedropper is on, and Esc cancels. A spot with almost no color is not taken;
the text under the slots says so and the eyedropper stays on. If the original
can't be read when you click the eyedropper, picking ends and the text under the
slots says so; make it available and click the eyedropper again. When the magnifier
reads **Almost no color**, a click there won't be taken. It shows the photo before
your edits, so its colors can differ from the photo around it and from the slot's
swatch. Change its zoom with the **Pixel magnifier** pop-up under the slots,
**View ▸ Pixel Magnifier**, the photo's context menu, or `-` and `=` while picking;
the app remembers it. Or, without
pointing at the photo, choose **Purple** or **Green** under **Common Fringe
Colors** in the slot's ⋯ menu (or the row's context menu); a slot filled this
way behaves exactly like one filled by picking. **Pick from Photo** in the same
menu arms the eyedropper, and **Clear** empties the slot. Each pick, choice or
clear is one undo step. Picking again for a filled slot hides that slot's
effect while you pick, so you can find the fringe again.

Under each filled slot, **Tolerance** widens or narrows the colors it grays:
colors at the middle of the range lose their color fully, colors toward its edge
less and less. A new color starts at a Tolerance that grays a typical fringe of
its kind; double-click the slider to go back to it. Graying keeps each pixel's
brightness, so edges gain no dark or light outline. Colors away from
high-contrast edges keep theirs, so a purple flower or a green leaf stays as it
is even when its color is in a range; only its outline can be grayed if it is a
high-contrast edge. The colors are matched on the photo as it comes from the
file, before the other adjustments, so changing Saturation, a look-up table or
any later adjustment does not change what is grayed. (For a raw file, White
Balance and Profile are applied as the file is decoded, before that point.
After a large White Balance change or a different Profile, show the Fringe Map:
if the fringe no longer shows white, pick or choose its color again.)

**Fringe Map** (the toggle under the slots, **Adjust ▸ Show Fringe Map**, or the
loupe's context menu) shows where fringe color is removed, in place of the
photo: white loses its color, gray in part, black keeps it. It works like the
sharpening map: a **Fringe Map** badge in the caption, the full-size map once you
pause, Esc to see the photo again. With Color Fringes turned off it still shows
the slots' reach and the badge reads **Fringe Map · Not Applied**. Clicking an
eyedropper while it is shown suspends it until the pick or Esc. Only one map is
on screen at a time; showing one replaces the other.

**Color Alignment** removes red/cyan and blue/yellow outlines that widen toward
the corners. Select **Align automatically**: the photo is measured (a small
spinner shows meanwhile), and the measured correction is saved with it, so every
rendering of the photo, in previews, exports and `photocli`, applies the same
correction. It is centered on the middle of the sensor, so cropping, rotating or
straightening never changes it. **Red/cyan** and **Blue/yellow** show the
correction; moving either sets it by hand from there and clears **Align
automatically**. Deselecting it removes the correction. Paste Adjustments and
presets measure each photo that receives automatic alignment for itself, with
progress in Activity; photos whose original is offline or can't be read are
left completely unchanged, and Activity says so. Hand-set values are copied as
they are. Lightroom presets that remove purple or green fringes, or remove
chromatic aberration automatically, import as Color Fringes (Purple, Green) and
Align automatically.

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
and leaves the photo's other settings alone. A preset with all settings,
including one saved before Color Fringes and Color Alignment existed, also
replaces those two (clearing a photo's fringe colors and alignment); **Manage
Presets…** can take them out of it. **Import Presets…** reads this
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
  A copy (**File ▸ Duplicate**) is exported under its name in the library, with
  the original name and through `{name}`: `IMG_0412 copy.jpg`, so an original
  and its copies exported together get different names.
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
get numbered names), replace them or skip them. An export never replaces an
original in the library. When you export into a folder that holds originals (a
project's own folder, say) and some of the files in the way are originals, the
sheet says how many, and **Replace** writes those photos under numbered names
(`IMG_0412-2.jpg`) while replacing the other files as asked; exporting there
again adds `-3`, and so on. When all of them are originals, the sheet says so,
and the new files are written under numbered names. This covers every original in
the library, not only those of the photos you are exporting, and holds when the
folder is reached through a symbolic link, a name differs only in case, or the
original's volume is mounted at another place than last time. A file that is
byte for byte an original in the library is not replaced either, wherever it is
and whatever it is called: that is how an original is known on a disk the
library no longer recognizes, and it means an exact copy of an original (a
backup) is left alone too and counted with the originals. The export runs
in the background, with progress and Stop in the toolbar's Activity item. When it
ends, Activity reports the result; there is no alert. If any photos could not
be exported (an offline volume, for instance), the report is a warning that
lists up to ten of them with the reason for each. Photos skipped because you
chose to skip existing files get a note of their own. The Finder can show the
files when it is done.

**History**: in the loupe, the **History** panel at the bottom of the inspector
(under the Info and Adjust tabs) lists the changes made to the open photo's
adjustments, newest first, each with its name ("Exposure", "Crop", "Paste
Adjustments"…) and the time. It is collapsed until you open it: click its
heading, or choose **View ▸ Show History** (⌥⌘3, which also brings the
inspector back if it is hidden and puts the keyboard in the list). The entry
with the check mark and the heavier type is the photo's current state; it is
always the top one. Click an earlier entry, or choose it with the arrow keys
and press Return or Space, to put the photo in the state it had then. That is a
change like any other: it is saved, **Edit ▸ Undo** takes it back ("Undo Revert
to “Exposure”"), it adds a new entry at the top ("Revert to “Exposure”"), and
no earlier entry is removed. Undo and redo are listed too ("Undo Exposure",
"Redo Exposure"), so the list is a complete log of what happened to the photo.
Esc in the list returns the keyboard to the loupe. One entry is added per
saved change: a slider drag, a crop saved with **Done**, and a paste or preset
are one entry each (a paste adds one to every photo it changes, and none to a
photo that already had those values). Each photo, and each file of a RAW+JPEG
pair, has its own list. A list keeps the latest 100 entries, dropping the
oldest (fewer when the edits are very large, such as long brush work: the list
also has a size limit, and the newest entry is always kept), and cannot be
cleared. A copy (**File ▸ Duplicate**) starts with an empty list. History is kept in the library and is there
after you quit and open the app again, but it begins with the first recorded change:
there is no entry for the photo as it was before that change, so to get back to the start use **Reset All Adjustments**, **Undo** or the
**Original** toggle (which only shows the original). While a crop is being
edited the rows are dimmed and do nothing: finish cropping first. The panel
says so instead of listing when the photo is a video, when its original is
offline, when its adjustments were made by a newer version of the app and
cannot be read (they are never written over), or when the list could not be read.
An earlier state whose saved copy is damaged or from a newer version reports it
in Activity and leaves the photo unchanged. It is not shown in the grid or in
review mode. History is not written to sidecars or exports. Edits made with
`photocli` are listed too, as "Develop (command line)" or "Mask (command line)".

**Undo**: ⌘Z and ⇧⌘Z undo and redo culling, keyword, album and pair changes,
project and album renames, adjustments, crop and rotation, and the Info tab's descriptive
fields (title, description and the like), including changes made to many photos
at once. Removing photos or a project from the library cannot be undone.

Photos on a volume that is not connected show an offline badge. Their cached
previews still display, and the app never removes them from the catalog by
itself (you can, with **File ▸ Remove from Library…**).

**About**: the first item of the app menu, **About** followed by the app's
name, opens the About window; **Help ▸ About** is the same item and opens the
same window (there is only ever one). It shows the app's version and build,
then a thank-you to the projects the app relies on: LibRaw, darktable,
LightCraft, GRDB and ExifTool, each with a sentence on what it gave, its
license, and a link to its page. A link opens in your browser; the app itself
contacts nothing, and the window works without a network. Below the list are
the app's own copyright and its license (the GNU General Public License,
version 3 or later). **View License**, beside LibRaw, LightCraft and GRDB and
under the app's own license statement, opens that text in a window of its
own, where it can be selected, copied and searched (⌘F, then ⌘G and ⇧⌘G);
several can be open at once. The button is there only when this copy of the
app carries the text: a copy built before the license files are packaged into
it shows the license names and links only. The version line is left out when
the app runs without a bundle (`swift run`). Esc or ⌘W closes the About
window; it can be made taller, not wider. The standalone importer has the
same window under its own name.

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
and why not. `export --policy overwrite` replaces existing files but never an
original in the library: such a photo is written under a numbered name and
counted in the result's `protectedMasters`. `colorFringes.color1=purple` (or `green`, or OkLab `L,a,b`) fills a
fringe slot, `colorFringes.tolerance1=40` sets its Tolerance, and
`colorAlignment.automatic=true` measures the original and stores the
correction (`colorAlignment.red` and `blue` set it by hand), and
`colorAlignment.automatic=false` alone removes it, as unchecking does. `photocli adjustments` lists every adjustment and its range;
`photocli help` lists the commands. Each prints one JSON object. Pass
`--library-root` as for the app; without it the standard library is used.

It can read a library at any time, but it changes one only while the app has
it closed: while the app is open, `develop`, `rate`, `flag`, `label`,
`mask add`, `mask set` and `mask remove` refuse and say so. Changes made from
the terminal cannot be undone in the app, but `develop`, `mask add`, `mask set`
and `mask remove` add an entry to the photo's History, which can be reverted to there.
