# Phase 2 plan

Design record for phase 2: grid labels, RAW+JPEG pairs, keywords, smart albums
and albums, XMP, and importing from cards. The architecture rules in `CLAUDE.md`
still apply; this file records the decisions made for phase 2 and why.

Out of scope for phase 2: adjustments, brushes, healing, export, general
(hand-made or burst) stacks, hierarchical keywords, PTP cameras, a second
backup destination during import, video editing or export, and writing
metadata into original files.

## Build order

Each step lands as its own commits, with tests, before the next starts.

1. Grid labels
2. RAW+JPEG pairs
3. Keywords, the inspector, undo
4. On-device keyword suggestions
5. More metadata columns, smart albums, albums
6. XMP sidecars: read, write, review outside changes
7. Import from cards and folders (copying)
8. Videos: catalogued and playable, no editing or export

## Catalog changes (migration `v2`, then one migration per step as needed)

| table / column | purpose |
|---|---|
| `image.pairingKey` | lowercased `folder/stem` of the file, indexed with `volumeId`, used to find RAW+JPEG partners |
| `imagePair` (`rawImageId` UNIQUE, `companionImageId` UNIQUE, `showsCompanion`) | one row per RAW+JPEG (or RAW+HEIC) pair; `showsCompanion` picks which file represents the pair when grouped |
| `importRun` (`id`, `startedAt`, `sourcePath`, `projectId`) and `image.importRunId` | “Last Import”, and the history of card imports |
| `image.localDate` | capture date as `YYYY-MM-DD` in the capture's own time zone, indexed; drives the Dates tree |
| `image` metadata columns | `artist`, `copyright`, `caption`, `cameraSerial`, `latitude`, `longitude`, `flashFired`, `exposureCompensation`, `whiteBalance`, `exposureProgram`, `meteringMode`, `focalLength35mm`, `metadataRevision` |
| `keywordSuggestion` (`imageId`, `name`, `confidence`, `state`) and `image.analysisRevision` | on-device suggestions per master; `state` is open, accepted or dismissed so dismissed ones do not come back |
| `smartAlbum` (`uuid`, `name`, `projectId` nullable, `rules` JSON) | user smart albums, library-wide or limited to one project |
| `importPreset` (`name`, `kind`, `settings` JSON) | saved metadata presets and import templates |
| `metadataSync` (per master) | sidecar bookkeeping for XMP: file name, size, mtime and digest when last read or written, the field values at that moment (the baseline), and a status |

Keywords stay flat: `keyword.parentId` is always NULL in phase 2 (the column
stays for later). Rows that existed before `v2` are backfilled in the
migration (pairing keys, pairs, local dates); new metadata columns are filled
by a background re-read of online masters, tracked by `metadataRevision`, so
offline volumes catch up when they are mounted.

## 1. Grid labels

Under each thumbnail: the star strip (as in phase 1), then the file name
without extension and a type badge: `RAW`, `JPEG`, `HEIC`, `TIFF`, `PNG`, or
`RAW+JPEG` / `RAW+HEIC` for a grouped pair. Badges are pre-rendered images
cached per label, so scrolling cost stays flat. Labels hide below a cell size of
about 120 pt; **View ▸ Show File Names** turns them off.

## 2. RAW+JPEG pairs

- Two masters pair when they are on the same volume, in the same folder, with
  the same file name ignoring extension and case, one RAW and one JPEG or HEIC.
  Pairing runs at the end of each import over the folders it touched, and once
  over the existing library in the migration.
- **View ▸ Group RAW+JPEG Pairs** (global, remembered) shows one cell per pair,
  the RAW by default. **Photo ▸ Show JPEG for Pair / Show RAW for Pair** switches
  the selected pairs.
- Ratings, flags, labels, keywords and album membership apply to both files: the
  catalog expands every write on a pair's default version to the partner's
  default version in the same transaction, so the two files never disagree
  whether they are shown grouped or apart.
- A pair is not a general stack. General stacks can later include a pair as one
  unit through the version that represents it.

## 3. Keywords, inspector, undo

- **Add keywords**: ⌘K opens a field over the grid or loupe. It autocompletes
  from the library's keywords (case-insensitive prefix, then substring), takes
  several comma-separated keywords, and applies them to every selected photo.
- **Inspector** (⌥⌘I, right side): for the selection, each keyword with a count
  (“dog, 12 of 30”) and a remove button; the add field; the suggestion chips
  (step 4); and file details for the focused photo.
- **Sidebar ▸ Keywords**: every keyword with its count. Clicking one shows its
  photos. Context menu: rename (renaming onto an existing keyword merges), merge
  into…, delete (with confirmation).
- **Keywords already in files** are read at import: IPTC Keywords and XMP
  `dc:subject` (embedded or in a sidecar), plus rating and label (step 6 covers
  sidecars).
- **Undo**: ⌘Z / ⇧⌘Z for culling, keyword, pair and album changes, including
  changes to many photos at once. Phase 1 had none. Undo goes through the grid
  and loupe responders, so text fields keep their own undo.

## 4. Keyword suggestions

Apple's Vision image classifier (`VNClassifyImageRequest`) runs on-device on the
cached 512 px thumbnail, in the background after each import and on demand
(**Photo ▸ Suggest Keywords**). It returns generic labels (“dog”, “beach”,
“sunset”), not breeds or places. Labels above a confidence threshold become
suggestions, shown as chips in the inspector. Clicking a chip applies it to the
selected photos that have that suggestion; dismissing it hides it for good.
Nothing is applied automatically, nothing leaves the Mac, and no dependency is
added.

## 5. Metadata, smart albums, albums

- **More metadata** (the fixed set above), read by ExifTool or ImageIO.
- **Built-in smart albums** in the sidebar: a Dates tree (year ▸ month, with
  counts, from the capture date in the capture's own time zone), Last Import,
  Picks, Rejects, Unrated, No Keywords.
- **User smart albums**: a name, an optional project scope, “match all” or
  “match any” of a flat list of rules. Rule fields: rating, flag, color label,
  keyword (has / does not have), has any keywords, file type, file name,
  capture date (before / after / between / within the last N days), import date,
  project, camera, lens, camera serial, ISO, aperture, shutter speed, focal
  length, exposure compensation, flash, white balance, artist, copyright,
  caption, has location. Rules are stored as JSON with generic identifiers and
  compiled to SQL in `PhotoCore`; contents update live.
- **Albums**: library-wide or inside a project. Create from the sidebar or with
  **New Album from Selection**; add photos by dragging them onto the album or
  with **Photo ▸ Add to Album**; remove with ⌫ inside the album (the photos stay
  in the library).

## 6. XMP

The catalog is the source of truth and is always what the app shows. Files on
disk are read at import and kept in step with the catalog, but nothing written
by another app is overwritten or discarded without asking.

- **Read at import**: sidecar if present (`IMG_0412.xmp` or `IMG_0412.CR3.xmp`),
  otherwise metadata embedded in the file: rating, label, pick/reject, keywords,
  creator, contact info, copyright, usage terms, caption.
- **Write**: after a change (debounced, in the background) the app writes the
  sidecar. Existing sidecars are edited in place: only the properties the app
  owns change; everything else (other apps' develop settings, hierarchical
  keywords, history) is preserved. Writes go to a temporary file in the same
  folder and are renamed over the old one. Read-only or offline volumes keep
  the write pending until they come back.
- **Change detection**: before every write, and on launch, mount and
  **Check for Changes on Disk**, the app compares each sidecar's size, date and
  digest (and each master's size and date) with what it last read or wrote.
- **Three-way comparison** per field: baseline (last read or written), library,
  file.
  - File unchanged: the library's values are written.
  - File changed: the photo goes to **Library ▸ Changed on Disk** with a
    per-field comparison (“Rating: library ★★★, file ★★★★★”; “Keywords: file
    added heeler, removed dog”), and writes to that file pause.
  - Actions, for one photo or the selection: **Use Library Values** (overwrite
    the file), **Use File Values** (update the library), or per-field choices,
    with keywords offered as a merge.
- **Masters changed by another app** (for example metadata embedded into a JPEG):
  the file is re-hashed, its catalog hash, size and date updated (previews
  regenerate), and its embedded values go through the same comparison.
- **Field mapping**: `xmp:Rating` (a reject is also written as -1, the common
  convention), `xmp:Label` as a color name, `dc:subject`, `dc:creator`,
  `dc:rights`, `xmpRights:UsageTerms`, `Iptc4xmpCore:CreatorContactInfo`,
  `dc:description`; pick/reject, the exact rating and the label number also go in
  the app's own namespace (`AppBranding.sidecarNamespace`), which never changes
  across renames.
- **Sidecars only.** Originals are never written, JPEG, HEIC and DNG included.
  Lightroom reads only embedded metadata for those formats, so it will not see
  the app's changes to them; RAW sidecars are read everywhere.
- **Naming**: `IMG_0412.xmp`, the Adobe / Capture One / Photo Mechanic
  convention. A RAW+JPEG pair shares one sidecar, which matches pairs sharing
  their metadata. `IMG_0412.CR3.xmp` sidecars (darktable, digiKam) are read but
  never created.
- **Always review**: even an outside change that conflicts with nothing in the
  library waits in Changed on Disk until you choose; bulk actions keep that
  quick for many photos.

## 7. Import from cards and folders

A separate import window. Card imports copy files; **File ▸ Import Folder…**
keeps importing in place as in phase 1.

- **Source**: any mounted card or camera that appears as a disk, or any folder.
  The window opens by itself when a volume with a `DCIM` folder mounts
  (**Settings ▸ Open the import window when a card is inserted**).
- **Browsing**: thumbnails from each file's embedded preview (fast, no RAW
  decode), pairs shown as one tile, checkboxes with Select All / None and
  shift-click ranges.
- **Duplicates are hidden** and never imported. Only files whose size matches a
  master already in the library can be duplicates, so only those are hashed
  before the import (usually a handful); every other file is new by
  definition. During the copy each file is hashed anyway, which catches the
  rest.
- **Destination**: a base folder, a folder template and a file name template,
  with a live example. Tokens: `{capture:<date pattern>}` and
  `{import:<date pattern>}` (Unicode patterns such as `yyyy-MM-dd`, `MMMM`),
  `{make}`, `{model}`, `{serial}`, `{lens}`, `{name}` (original name without
  extension), `{number}` (the digits in the original name), `{ext}`,
  `{ext:lower}`, `{ext:upper}`, `{seq:4}` (this import, zero-padded), `{counter:5}`
  (persistent across imports), `{job}`. Both files of a pair get the same name
  stem and sequence number. Name clashes get `-1`, `-2`; an identical file
  already at the destination is skipped.
- **Project**: an existing one, or a new one named from a template (default
  `{capture:yyyy-MM-dd} {job}`).
- **Metadata on import**: artist, contact info, copyright (with tokens, e.g.
  `© {capture:yyyy} Name`), usage terms, from saved presets. Applying metadata
  always writes a sidecar; the copies stay byte-identical to the card.
- **Copy and verify**: each file is copied to a hidden temporary name while
  being hashed, renamed into place, its modification date set to the
  original's, then re-read without the file cache and hashed again. Only files
  whose two hashes match the source are catalogued as verified.
- **Delete from card** (checkbox, with a confirmation at the end): deletes only
  files copied and verified in this import. Duplicates that were hidden are never
  deleted.
- **Eject** (checkbox, remembered) after the import and any deletion.
- **Testing**: FAT32 disk images built with `hdiutil` stand in for cards (they
  mount, contain `DCIM`, and eject), so the whole flow runs without hardware.

## 8. Videos

- MOV, MP4 and M4V (plus whatever AVFoundation can open among MTS/M2TS) are
  catalogued like photos when **Include videos** is checked in the import window
  (remembered) and by **Import Folder…**. They take part in projects, albums,
  smart albums, keywords, ratings, flags and labels, and get sidecars like
  photos.
- New `image` columns: `mediaKind` (photo / video) and `duration`. Thumbnails
  and previews are poster frames from `AVAssetImageGenerator`, cached like
  photo previews. The grid shows a duration badge; the loupe plays the video
  with `AVPlayerView`.
- No trimming, editing or export. Videos are copied, verified, deduplicated and
  deleted from the card by the same rules as photos.

## Testing

`PhotoCore` tests for: pairing (including the migration backfill), pair-wide
writes, keyword add/remove/rename/merge, smart album rule compilation against a
fixture catalog, the Dates tree in several time zones, template rendering and
sanitizing, the size-prefiltered duplicate check, copy-and-verify (including a
corrupted copy), XMP reading (embedded and sidecar), XMP writing that preserves
foreign content, and the three-way comparison. App behavior is checked with
`--debug-script` snapshots. Profiling repeats the 10k/50k runs for the grid with
labels and pairs, keyword and smart album queries, and the card import.
