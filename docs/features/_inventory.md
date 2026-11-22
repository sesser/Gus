# Capability inventory

What the app does today: `develop` as of 2026-11-06, after machine learning
noise reduction merged (PR #39). Owned by the product-manager agent; a
reference for spotting duplicates and conflicts before a feature is specified.
It stands in for a `prd.md` for the UI redesign (owner, 2026-11-04);
`ui-redesign/prd.md` adds only the rulings on design.md's requirements issues.

Corrected 2026-11-04 after the UI redesign reconciliation: project rename and
removal (data only), drag and drop, export's reveal in the Finder, the Help
menu, and the metadata reader's visibility.

Updated 2026-11-06 (Ship pass) for what merged since: the sharpening map
(PR #37), ui-redesign-reconcile E1–E28 (PR #34) and machine learning noise
reduction (PR #39). Rows changed from those features' `status.md` and
`docs/USER_GUIDE.md`; their manual checks are still open (roadmap Shipped).

Updated 2026-11-06 (Ship pass) for PR #43 (editor-follow-edit-drop and
reload-items-stale-hash: Live rendering row) and PR #42 (CI crash capture: CI
row). `develop` as of 520d479.

Updated 2026-11-07 (Ship pass) for PR #47 (library-launch-guard: Launch
guard row under Quality and tooling), from its `status.md` and
`docs/USER_GUIDE.md` "Development options". Its person checks passed the
same day (qa.md Follow-up).

Updated 2026-11-08 (Ship pass) for PR #48 (chromatic-aberration: the Lens rows
under Editing, Pixel Magnifier under Loupe, and the Lightroom import, `develop`
and `photobench` rows), from its `status.md` and `docs/USER_GUIDE.md`.

Updated 2026-11-09 (Ship pass) for PR #49 (viewport-render-1to1: Sharp live
frames at 100% under Loupe, the Live rendering row) and the bug fix
viewport-render-qa-findings, from their `status.md` and `prd.md`.

Updated 2026-11-12 (Ship pass) for side-by-side-comparison (#63: Side by side
comparison under Loupe, the `photobench` row), from its `status.md`, `qa.md` and
`docs/USER_GUIDE.md`; the comparison row again the same day after the merge
with develop (Duplicate off while comparing, copies compare as photos).

Updated 2026-11-13 (Ship pass) for about-gus-dedication (#179: About window row
under UI shell, the Menu bar, Quit guard and Debug script rows), from its
`status.md` and `qa.md`.

Updated 2026-11-14 (Ship pass) for white-balance-across-decoders (#170, covers
#171: the LibRaw fallback, Color step, Preview cache and `photobench` rows),
from its `status.md`, `qa.md` and `docs/USER_GUIDE.md`.

Updated 2026-11-17 (Ship pass) for gpu-demosaic (#196: the GPU demosaic row
under Rendering and previews; the LibRaw fallback row's decode times and the
Preview cache row's pipeline version, now 12 with no carry-over), from its
`status.md` and `qa.md`.

Updated 2026-11-19 (Ship pass) for bw-module (#218: the Black & White row under
Editing), from its `status.md`, `qa.md` and `docs/USER_GUIDE.md`.

Updated 2026-11-19 (Ship pass) for lens-corrections (#87: the Distortion and Lens
Vignetting rows under Editing), from its `status.md`, `qa.md` and
`docs/USER_GUIDE.md`.

Updated 2026-11-21 (Ship pass) for preset-list-view (#241: the Presets list view
row under Presets and look-up tables), from its `status.md`, `qa.md` and
`docs/USER_GUIDE.md`.

Updated 2026-11-22 (Ship pass) for hdr-merge (#150: the Merge to HDR row under
Export and the `merge` command), from its `status.md`, `qa.md` and
`docs/USER_GUIDE.md`.

Markers:

- **[inferred from code]**: no document states it; the claim rests on code alone.
- **[doc only, not found in code]**: a document claims it and I could not find it.
- No marker: a document states it and the code was spot-checked, or it was
  not contradicted.

Abbreviations: P1–P6 = `docs/archive/PHASE1_PLAN.md` … `PHASE6_PLAN.md`; UIR =
`docs/UI_REDESIGN.md`; UG = `docs/USER_GUIDE.md`; CL = `CLAUDE.md`.

## Catalog and library

| Capability | What it does | Source |
|---|---|---|
| Referenced masters | Originals stay where they are; catalog stores volume, relative path, SHA-256, size, mtime | CL Architecture; P1 Catalog schema |
| Offline volumes | Masters on unmounted volumes show offline with cached previews; rows never deleted; volumes matched by UUID | CL; P1; UG |
| Migrations v1–v13 | 21 tables incl. `imagePair`, `importRun`, `keywordSuggestion`, `smartAlbum`, `importPreset`, `metadataSync`, `sidecarQueue`, `exportPreset` | P1–P4; `Catalog/CatalogSchema.swift` (CL's table list omits eight of them) |
| Projects | Each master belongs to one project, named after the imported folder or a template | P1 Import; P2 §7 |
| Rename project or album, remove from library, Show in Finder | Rename a project or an album in place (sidebar, File ▸ Rename, row menu, Return; one undo step; catalog only; the album Rename sheet is gone; keywords keep their sheet, smart albums Edit…; a row that leaves the list during a rename saves it). Remove from Library… (⌘⌫) takes photos (a RAW+JPEG pair together) and Remove Project from Library… takes a project, its photos and its own albums, in one transaction, after a confirmation with no default button; no undo; files and sidecars never touched; offline photos can be removed; re-import gives new photos. Show in Finder (⇧⌘R) reveals photos' masters (one window per folder) or a project's source folder. Remove is off while a folder add or card import runs. An original removed takes its copies (the confirmation says how many); a copy removed alone leaves its original and the master (`virtual-copies/prd.md` R6) | `library-ops/prd.md`; `Catalog/LibraryRemoval.swift`, `Catalog/InPlaceRename.swift`, `Browser/FinderReveal.swift`, `Browser/RemovalConfirmation.swift`; `LibraryRemovalTests`, `LibraryOpsRuleTests`, `AlbumRenameTests`; `rename-albums-in-place/prd.md`; UG |
| Versions | Ratings, flags, labels and edit stack live on a version; one default version per master | P1 schema; CL |
| Virtual copies | Duplicate photos (one undo step; photos only, videos skipped): a copy is another version of the same master with the original's edit stack as a snapshot, then its own edits, history, rating, flag, label, keywords and albums. Shown as its own marked item in the grid, loupe, film strip and review, placed after its original when made, counted everywhere; RAW+JPEG copies are per file and unpaired; a copy never touches a sidecar; export names copies apart; smart album rule "is a copy". Descriptive Info fields and keyword suggestions are shared with the original. Not yet: naming a copy or making it the default, `photocli duplicate` | `virtual-copies/prd.md`; `Catalog/Catalog.swift` (`duplicateVersion`), `Catalog/LibraryRemoval.swift`; `VirtualCopiesTests`; UG |
| Stacks (data only) | `stack`/`stackMember` tables and `Catalog.createStack`; no UI | `Catalog/Catalog.swift:536` **[inferred from code]**; P1 schema lists the tables |
| Keyword hierarchy (data only) | `keyword.parentId` and `Catalog.keyword(named:parentID:)`; always NULL in practice | P2 Catalog changes; `Catalog/Catalog.swift:558` |
| Library lock | Advisory `flock`; CLI writes refuse while the app holds the library | P5 Command line |
| Unreadable edit stacks protected | Newer, damaged or over-limit stacks are never written over; editing turns off with a message | P6 Step 0, question C; CL |
| Data directory migration on rename | Moves the Application Support folder after a product rename | CL Naming rules; `RENAMING.md` |

## Import

| Capability | What it does | Source |
|---|---|---|
| Add Folder Without Copying… (⇧⌘I) | Imports a folder in place as a new project; duplicates by hash skipped | P1 Import; UG; UIR decision 15 (rename) |
| Folder drops | Folders dragged from Finder onto the browser or Projects list import in place, queued | P3 As built; UG |
| Card and folder import with copying (⌘I) | Import window: source pop-up, check box per shot, templates, project, job code, metadata preset | P2 §7; UIR §8 Import window; UG |
| Auto-open on card insert | Volume with `DCIM` opens the Import window; Settings toggle | P2 §7; `Views/SettingsView.swift` |
| Copy and verify | Copy to temp name while hashing, rename, re-read with `F_NOCACHE`, re-hash; only verified files count | P2 §7, As built; CL |
| Delete from card, eject | Deletes only verified copies after confirmation; eject remembered | P2 §7 |
| Duplicate hiding | Only size-matched files hashed before import; "Show Photos Already in Library" | P2 §7; UIR §8 |
| Naming templates as token fields | `{capture:…}`, `{import:…}`, `{make}`, `{seq:4}`, `{counter:5}`, `{job}` … shown as pills | P2 §7; UIR decision 19 |
| Metadata presets on import | Creator, copyright with tokens, usage terms, contact; written to sidecars only | P2 §7; `CardImport/MetadataPresets.swift` |
| Keep picks on rescan | Toggling videos or Rescan keeps shots the user left out | Issue #19; UIR step 10; `CardImport/ImportSelection.swift` |
| Shutter count in subtitle | Newest photo's camera and shutter count | UIR §8; `CardImport/CameraSummary.swift` |
| Import keeps running after window closes | Shown in library window's Activity item | UIR §8 states table |
| Quit guard | Asks before quitting stops an import or export. The question goes on the key window, else the main one, never the About or a license window, and on the front-most sheet when that window shows one (`QuitConfirmation.host`, `frontSheet`), with the host brought forward. Open observation Q1: a real ⌘Q with a sheet up showed no question in a script run, on `develop` too (P8(b)) | UIR §8; `PhotoUI/QuitGuard.swift`; `about-gus-dedication/status.md` C6, F4 |
| Metadata reading | ExifTool `-stay_open` process pool when installed; ImageIO fallback; AVFoundation for video. Nothing in the app says which reader is in use | CL; P1 Profiling; README. Roadmap: metadata-reader-status |

## Standalone importer

| Capability | What it does | Source |
|---|---|---|
| Importer app | Same Import window, model and commands with no library: copies only, no duplicate marking, preset metadata into new sidecars | CL; UIR §8; `Sources/PhotoImporter` |
| Close confirmation | Window-modal alert while copying (`WindowCloseGuard`); known risk if SwiftUI replaces the window delegate | UIR status |

## Grid, browsing and culling

| Capability | What it does | Source |
|---|---|---|
| AppKit grid | `NSCollectionView` with uniform layout, thumbnail size slider, file names and type badges | P1 App; P2 §1; UIR §5 |
| RAW+JPEG pairs | One cell per pair (View ▸ Group RAW+JPEG Pairs); culling, keywords, albums reach both files | P2 §2; CL |
| Culling keys | 0–5, `[` `]`, P/X/U, ⌥0–⌥7; Advance After Rating | P1; UIR §6; UG |
| Filter, sort, search per source | Toolbar Filter and Sort menu, search field (⌘F), remembered per sidebar source | UIR decision 6, §2 |
| Sidebar | Library (built-in smart albums, Changed on Disk), Albums, Dates, Keywords, Projects; sections collapse and hide; selection restored | UIR §3; P2 §5 |
| Albums and smart albums | Albums library-wide or in a project; smart albums with ~25 rule fields, match all/any, live | P2 §5; UG |
| Drag and drop of photos | Grid photos drag onto album and keyword rows in the sidebar. The drag carries a private type, so nothing can be dropped into other apps or the Finder; Edit ▸ Copy does not copy photos | `Grid/GridController.swift:130`, `Views/SidebarView.swift:43` **[inferred from code]**; UG. Roadmap: photo-pasteboard |
| Batch edit commands in the grid | Paste, Apply Preset, Auto Exposure, Reset All, Rotate on the selection as one undo step | UIR decision 5; CL |
| Undo / redo | ⌘Z / ⇧⌘Z for culling, keywords, albums, pairs, edits, crop, descriptive fields | P2 §3, As built; CL Undo |
| Edit history | History panel at the inspector's foot in the loupe (View ▸ Show / Hide History, ⌥⌘3): a photo's saved edits, newest first, label and time, current state marked; click an entry to revert to it (a new entry, one undo step). Stored per photo (table `editHistory`, migration v14, LZFSE snapshots, 100 entries and 4 MiB per photo); undo, redo, revert and `photocli` edits are logged; edits only; each file of a RAW+JPEG pair has its own; a copied version starts empty. Not shown in the grid or review. Manual checks P1–P6 open | `edit-history/`; UG; `Catalog/EditHistory.swift`, `Views/HistoryPanel.swift` |
| Review mode (F) | Full-screen loupe, panes hidden, toolbar on hover | UIR §2; `Model/ReviewActions.swift` |
| Empty states | `ContentUnavailableView` for empty library, no matches, no selection; an empty album, smart album or built-in source shows its own state with its sidebar symbol (smart albums offer Edit Smart Album…) | UIR §9; `ui-redesign/status.md` E1 (`EmptySourceState`) |

## Loupe

| Capability | What it does | Source |
|---|---|---|
| Loupe | Fit, 100% and zoom steps 25–800%, pinch and ⌥-scroll, neighbour preloading | P1 App; UIR §6 |
| Sharp live frames at 100% | At 100% and above, while a value changes (sliders, curve, wheels, mask handles, brush, hover previews, Show Original, mask overlay) the loupe shows the visible part rendered from full-resolution pixels, matching the render after letting go. RAW white balance and noise reduction are soft while moving, sharp on a pause; a drag may start soft, and may go soft briefly when Exposure or Highlights cross 0. Never blank; histogram stays whole-photo. Full-resolution copy held only at covered zooms, no memory cap. Below 100% unchanged | `viewport-render-1to1/` (PR #49); `viewport-render-qa-findings/`; UG |
| Caption line | Position, stars, flag, label name, Filtered/Original/HDR/Offline badges | UIR §1 |
| Show Original (`\`) | Before/after while editing | P3 sidebar; UIR §4 |
| HDR display | HDR sources (float DNG, gain maps, HLG/PQ) render HDR on EDR screens; View ▸ Hide HDR Highlights | CL Rendering; UG |
| Film strip | The source's photos in a strip between the loupe (or video loupe) and the caption. Clicking a photo focuses it, and the focused photo stays centered. A drag handle resizes it in steps (48–120 pt, capped at 25% of the loupe height). Caption toggle and ⌥⌘B show or hide it with a slide. VoiceOver list and splitter. Never shown in review mode | Issue #25 (closed); UIR §11; `Loupe/FilmStrip*.swift`, `Browser/FilmStripGeometry.swift`. Not yet checked on screen. §11's checklist leaves 7 build items unticked that the code appears to implement |
| Side by side comparison | A state of the loupe (and review mode): two different photos side by side, each with its saved edits. `S` (View ▸ Compare Side by Side / Stop Comparing) enters from two selected photos, from one selected photo (with its partner: the one last compared with, else the next comparable) or from the loupe's photo; `S` again leaves and `S` once more brings the same pair back. Exactly one photo is active, marked by a ring; `A` switches; culling, keywords, albums, export and Show in Finder act on the active photo, with undo. Zoom and pan are linked by default (View ▸ Link Zoom and Position, remembered across launches). Arrow keys or a film strip click replace the active side's photo. Leaving selects the pair on screen. Refused with an alert: a video, an offline photo, the two files of one RAW+JPEG pair shown separately. No editing while comparing; Remove, Paste, Apply Preset and Duplicate are off (Duplicate is dimmed and absent from the pane menu). A photo and its copy (virtual copies) compare as two photos, with no shortcut to compare with a copy; a copy shows its own name and the Copy badge in the caption and in VoiceOver. Undo or redo of a Duplicate never moves the focus off the panes: an undo that removes a compared copy ends the comparison on the remaining photo (or on the active copy's original if both go); redo never changes a comparison. Two photos only (R9 not built). Known limitation #153 (linked zoom state can flip after ⌘= twice and a drag). No migration, no pipeline bump. Checks pending: AC7 hitch count, animations, real mouse and trackpad, menus, looks, a copy beside its photo in a narrow window (P7), Duplicate while comparing (P8) | `side-by-side-comparison/`; UG; `Browser/Comparison.swift`, `Loupe/ComparisonView.swift`, `Model/ComparisonActions.swift` |
| Pixel Magnifier | While a fringe slot picks, a round view beside the pointer shows the photo's own full-resolution pixels before edits, outlines the pixel a click takes and gives its R, G, B and L (0–255, Display P3). Levels 100–1600%, remembered as a preference. A view only. Built for other tools; only the fringe eyedropper uses it so far | `chromatic-aberration/prd.md` R19–R36; UG; `Edits/PixelMagnifier.swift` |

## Metadata, keywords and sidecars

| Capability | What it does | Source |
|---|---|---|
| Keywords | ⌘K popover with autocomplete; inspector counts; sidebar rename, merge, delete | P2 §3; UG |
| Keyword suggestions | Vision classifier on the 512 px thumbnail, on device; chips; dismissed ones stay gone | P2 §4; `Suggestions/KeywordSuggester.swift` |
| Info tab | Camera, lens, exposure tiles, size, dates, file, folder, volume | P3 As built; UIR §4 |
| Descriptive fields | Title, description, alt text, extended description, copyright, usage terms, contact (IPTC Core/Extension), batch-edited | CL Scope; `Catalog/Descriptions.swift`; migration v13 |
| XMP sidecars | Write `IMG.xmp` (shared by a pair) after changes, preserving foreign content; Settings toggle | P2 §6; UG |
| `name.ext.xmp` on stem clash | When two unpaired masters share a stem, each gets `name.ext.xmp` | `Sidecars/SidecarFiles.swift:21` **[inferred from code]** (P2 §6 says such sidecars are "never created") |
| Changed on Disk review | Three-way comparison; per-field choice; keyword merge; not undoable | P2 §6, As built |
| Masters changed outside | Re-hashed, previews regenerated, embedded values compared, never written back | P2 §6, As built |

## Editing (global)

| Capability | What it does | Source |
|---|---|---|
| Edit stack | Versioned JSON operations; render hash over enabled ops; defaults left out; unknown ops kept | P1; P3 Edit stack; CL |
| Light (was Develop) | White balance (Mode, Kelvin, tint, Auto), exposure with Auto, tone, presence. No Profile group (removed by #219: every photo renders with its decoder's default; see Stored Look) | P3; UIR decision 15; `remove-profile-group/` |
| Stored Look kept, never rendered | A photo saved earlier with Look Neutral or Flat keeps the value in its stack (`RawDecode.storedLook`, read as stored, written back unchanged by every write) and renders with the decoder's default, with more contrast than before. Only Reset All Adjustments clears it (it removes the whole `rawDecode` operation, the stored decoder version with it). A stored non-machine-learning `decoderVersion` is still honoured. Presets, paste and batch carry no Profile group; an old preset's stored decode stays in its data and applies nothing (except a legacy machine learning decoder, which turns machine learning on). Lightroom import maps no profile to a Look: a name outside the Standard family (Standard, Adobe Color, Adobe Standard, default, embedded) is reported. `photocli adjustments` lists `rawDecode` with `decoderVersion` only; `--set rawDecode.look=…` fails as unknown. Pipeline version 13 (plain bump); `raw-lookNeutral` and `raw-lookFlat` goldens deleted. Owner signed off by eye 2026-11-19; checks P2 and P5 (a photo with a stored Flat) pending | `remove-profile-group/` (#219); `Adjustments.resettingAll()`; `StoredLookTests` |
| Tone Curve | Point curve on RGB or per channel over the histogram | P3 |
| Color Mixer | Hue, saturation, luminance of eight bands | P3 second pass |
| Black & White (film filters) | Heading between Color Mixer and Color Grading, with an always-shown check box (checking it on a fresh photo is an explicit "on": the photo turns gray, Rec. 709 luminance), a segmented quick-set (Yellow, Orange, Red, Green, Blue: that filter at 100, the rest 0, one undo step) and five 0 to 100 sliders. The mix is Rec. 709 weights times the filters' transmittance, normalised so neutral grays keep their level; the strengths are the engineer's estimates from published filter data, accepted by the owner at sign-off. Rendered right after the Color Mixer, before Vibrance, Saturation and Color Grading, in the working space with no clipping, so a per-channel Tone Curve acts like an extra filter; masks render after it (a mask's White Balance tints the gray); grain and vignette stay neutral; Color Fringes swatches keep their true colors. A normal group (paste, presets, batch, virtual copies, RAW+JPEG files separately, reset to identity, history labels); every decoder alike; videos skipped. Adjust ▸ Black & White ▸ submenu (loupe only). A gray file shows a caption saying the filters change nothing. Local B&W, Lightroom B&W mapping and grid-selection menu items are not built. No migration, no pipeline bump, three new goldens | `bw-module/` (#218); UG; `Edits/BlackAndWhite.swift`, `Views/BlackAndWhiteSection.swift`, `Model/BlackAndWhiteActions.swift` |
| Color Grading | Shadows, midtones, highlights wheels; balance; blending | P3 |
| Details | Sharpening (amount, radius, detail, masking); noise reduction | P3 |
| Sharpening map | Shows in the loupe where Masking lets sharpening through: live while values change, full resolution once input pauses; "Not Applied" when nothing is sharpened. A view only: not saved, no undo, never in previews or exports | `sharpen-mask-preview/`; UG; `Edits/SharpeningMap.swift`. Manual checks M1–M9 open |
| Machine learning noise reduction | Raw files only, opt-in per photo, in the Noise Reduction group (Luminance is its amount, Color dimmed while it applies). Uses the macOS 27 raw decoder's version 9 (`9.dng` / `9`; chosen only with Use machine learning, there is no Decoder pop-up since #219); no model shipped or downloaded. Where it can't apply (older macOS, unsupported camera, failed decode) the photo renders classically, keeps the setting, and the caption badge and Activity say why. Carried by paste, presets and batch commands to raws only | `ml-denoise/`; UG; `Edits/MachineLearningNoiseReduction.swift`. A missing model is not detected yet (RI-E6); AC13 and manual checks open |
| Color Fringes | Lens heading. Two slots, filled by picking from the photo or from a short list (Purple, Green); each slot's color turns gray near high-contrast edges only, keeping brightness, with its own Tolerance. Matches on the decoded photo before other adjustments (a raw's White Balance comes first). Off by default; not in masks; photos only | `chromatic-aberration/prd.md`; UG |
| Fringe Map | Shows in the loupe where fringe color is removed; a view only, one map on screen at a time | `chromatic-aberration/prd.md` R6; UG |
| Color Alignment | Lens heading. Align automatically measures red/cyan and blue/yellow edges once and stores the correction, centered on the sensor so crops don't change it; or set by hand. Paste and presets measure each receiving photo; one that can't be measured is left unchanged, and Activity says so | `chromatic-aberration/prd.md`; UG |
| Distortion | Lens heading, first in the render (before Color Fringes and Color Alignment, all before the crop). Source Auto or Manual: Auto reads the camera's table from the file (Fujifilm RAF; DNG `WarpRectilinear`), Manual takes a signed Amount (barrel/pincushion) on any photo. Constrain to image (on by default) fills the frame with no empty edge. Auto is inert where the system decoder or Fujifilm's built-in table already corrected; Manual then works on top. No Auto on non-raw files or a RAW+JPEG pair's JPEG. Clicking a Source segment while the group is off turns it on. Off by default | `lens-corrections/`; UG; `Edits/LensCorrections.swift`. Sony, Panasonic and Olympus table readers not built (#227 Sony) |
| Lens Vignetting | Lens heading, own group; lightens or darkens corners by Source Auto (Fujifilm RAF vignetting table; DNG `FixVignetteRadial`) or Manual Amount; applied before exposure and tone, not the same as Effects' Vignette. Same Auto-inert rule as Distortion. The Fujifilm XF14 and XF23 check against the camera JPEG was done by eye | `lens-corrections/`; UG. DNG `GainMap` not built |
| Lens frame question | When a change moves the corrected frame on a photo with spots or masks, a narrow alert (Change default, Cancel) asks, once per visit; at commit for a slider drag; once with counts for paste or preset on several photos; never for Undo, Redo, History or Reset All | `lens-corrections/design.md` §6; UG. Known: ⌘Z during a grid paste's file read undoes the step before. Manual check P5 (real keys) open |
| Effects | Look-up table, vignette, grain | P3 |
| Group on/off | Check box per group keeps edits but disables them | P3 sidebar; UIR §4 |
| Copy / Paste Adjustments | Paste carries crop, not masks | UG; P6 |
| Live rendering | Decoded master reused per frame; one save and undo step per gesture; stage cache and adaptive drafts at fit; at 100% and above, frames of the visible area at full resolution (see Sharp live frames at 100%). The loupe loads a photo's edits only after its pending saves land (shows loading meanwhile), and library reloads never put back values older than a change already made | CL Editing; P6 Caching and drafts; `editor-follow-edit-drop/status.md` (PR #43) |
| Runtime GPU kernels (spike) | Compiled at run time; not used by the renderer | P5; `Edits/Kernels/RuntimeKernels.swift` |
| Embedded lens corrections (Fujifilm RAF, LibRaw path only) | Distortion, lateral color and corner shading from the tables the camera stored in the file, applied automatically on LibRaw's image before the crop; no control. Used only when the file's frame matches the tables and the crop mode is not 1.25x; else uncorrected with a log line. Math after darktable (GPL 3 or later). Lens kernel `embeddedLens` | `raf-not-rendering/status.md`; `Preview/FujifilmRAF.swift`, `EmbeddedLensCorrection.swift`; `THIRD_PARTY_NOTICES.md` |
| Lens kernels | Stitchable Core Image kernels compiled at run time, used by the Lens heading. If they can't compile, the corrections are skipped with no message (known limitation, RI-CR1) | `chromatic-aberration/prd.md`; `Edits/Kernels/LensKernels.swift` |

## Crop

| Capability | What it does | Source |
|---|---|---|
| Crop, rotate, straighten | Session in the loupe (`C`), aspect presets, quarter turns, ±45° straighten; Rotate ⌘[ / ⌘] commits at once | CL Scope; UG |
| Whole-sensor crop for camera-cropped raws | Olympus/OM System/Panasonic aspect crops can be widened | CL; `Preview/CameraFrame.swift` |
| Camera frame for Fujifilm RAFs decoded by LibRaw | The frame is the camera's own (`RawImageCropTopLeft`, `RawImageCroppedSize`: 6000x4000 for the X-E3), cut from LibRaw's visible area; other LibRaw files keep its inset crop; Super CCD files get no crop | `raf-not-rendering/status.md`; `Preview/LibRawDecoder.swift`, `FujifilmRAF.swift` |

## Masks (local adjustments)

| Capability | What it does | Source |
|---|---|---|
| Shapes | Linear and radial gradients, brush, luminance range, color range | P6 Shapes |
| Combining | Add, subtract, intersect, per-component invert, Amount | P6 decision 4 |
| Local controls | Exposure (exact), tone, temperature/tint, presence, sharpening | P6 decision 5 |
| Masks heading and overlay | List with rename, on/off, reorder, delete; handles, brush cursor, red overlay | P6 UI; UIR §4 |
| Limits | 32 masks, 16 components, 8 color samples, 200 000 brush points | P6 decision 2 |
| AI components: Subject, People, Background | A wand pull-down at the end of the New Mask and Add to Mask rows (Adjust ▸ New Mask, mask ⋯ menu) detects with Apple's Vision on the Mac (nothing leaves it, no model bundled) from a 2560 px render of the mask frame; a transient Detecting line with Cancel, and the component enters the stack when the result lands (one undo step, one History entry). Subject: every foreground instance; People: up to four people; Background: its own kind, Subject inverted, may share Subject's row. Add, subtract, intersect, invert and Amount as any component; no feather or refine. The stored low-resolution result (8-bit gray PNG) is scaled to the render with a guided filter (He, Sun and Tang). Stored, never silently recomputed (differs across compute devices); only Update Detection (Adjust, mask ⋯ and context menus) recomputes. Empty, Failed, Unavailable and Missing states say why and select nothing; the photo renders as without. Left out of paste, presets and sync; Duplicate shares the stored result | `ai-masks/` (#88); UG; `Edits/Masks/` (`MaskRaster`, `MaskRasterStore`, `GuidedMaskFilter`), `Suggestions/MaskDetector.swift` |
| Mask rasters (`maskRaster`) | Migration v15: table `maskRaster` keyed by SHA-256 of the stored bytes (width, height, instances, provenance; rows never updated), and `editHistory.maskRasters`. Rows no stack or history entry names are deleted at launch (`removeUnreferencedMaskRasters`, on the write chain). Limits: side at most 1024 px, 2 MiB per row; a row that fails a check is Missing | `ai-masks/status.md`; `Catalog/MaskRasters.swift` |
| `photocli mask add --shape subject\|people\|background` | Detects on the original and stores the result (`--dry-run` reports `detection` and stores nothing); `mask list` shows each detection's state and instances | `ai-masks/status.md`; `Commands/MaskCommands.swift` |
| AI component limits | People stops at four and can select a non-person (the flower close-up); a stored result is never recomputed on another OS; C14 (identical twin components and a running Update); previews cached before a row went missing still show the mask until the cache is deleted (Q1); Vision on macOS 15 and 26 is checked by CI only (AC11) | `ai-masks/qa.md`, `status.md` |

## Spots (healing and cloning)

| Capability | What it does | Source |
|---|---|---|
| Heal and Clone spots | Circular spots placed by clicking in the loupe (Edit Spots, `H`); each has a size, feather, opacity and mode. Heal blends the source's texture into the surroundings; Clone copies it. Rendered first among adjustments, before white balance and the crop, in the mask frame, so they stay on picture content under crop and turns. Every decoder alike | `healing/` (#86); UG; `Edits/Spots/` |
| Automatic source | A clean nearby patch clear of the spot, others and the edges; deterministic. Drag the source to override; Adjust ▸ Spots ▸ Choose Source Automatically picks again (one undo step) | `healing/status.md`; `Edits/Spots/SpotSourceFinder.swift` |
| Spots heading and overlay | List and controls in the Adjust tab, on/off check box (Turn Off / On Spots), overlay of spots and sources (`V`), keyboard moves (⌥-arrows, ⌥⌘-arrows), VoiceOver buttons per spot | `healing/design.md`; `Views/SpotsSection.swift`, `Loupe/SpotOverlayView.swift` |
| Limits and rules | 100 spots; a `spots` group left out of paste, presets and sync; per file; never in sidecars; not editable while comparing; unreadable stacks never written over. Many spots are slow (#211). Manual-check and follow-ups: #208, #209, #210, #211 | `healing/status.md` |

## Presets and look-up tables

| Capability | What it does | Source |
|---|---|---|
| Adjustment presets | Partial presets by group, collections, hover preview, preview tiles | P3 second pass |
| Presets list view | The Presets heading shows a list (default) or thumbnails, chosen by an icon-only two-segment switch at the right of the Save…, Import… and Manage… row; the choice is an app-wide preference (`adjust.presetsView`). List: same collections, headings and order, one row per preset (name only, tooltip with its groups, check mark when the photo has it), no thumbnails rendered while it shows. A row applies like a thumbnail (same context menu; Return, keypad Enter, Space). Hover previews in the loupe in both views through the unchanged `previewAdjustmentPreset` path (live, not saved; nothing in the grid). The button row wraps in three arrangements, so at the default inspector width Manage… sits under Save…. No migration, no pipeline bump. Owner checked P1 to P5 on 2026-11-21 | `preset-list-view/` (#241); UG; `Presets/PresetsViewChoice.swift`, `Browser/PresetsBarGeometry.swift`, `Views/PresetsSection.swift`, `Views/PresetList.swift` |
| Preset files | xz-compressed JSON with embedded `.cube` files; Finder double-click imports | P3 second pass; `Support/Info.plist` (exported type) |
| Lightroom preset import | `.lrtemplate`, `.xmp`, `.dng`; report of unmapped settings. Purple and green fringe removal and automatic chromatic aberration removal map to the Lens groups | P3 second pass; `Presets/` |
| Luminar preset pack import | `.lnpc` packs (several at once) through Import Presets…; one preset collection and one look-up table collection per pack; approximate conversion with named assumed scales; Import Report page (mapped, approximated, left out, not recognized, not imported); re-import replaces by name; no Finder registration | `luminar-preset-import` (#203); `Presets/Luminar/`, `Support/ZipArchive.swift` |
| Manage Presets sheet | Rename, move, export, delete, change groups | P3; UIR §8 |
| Look-up tables | `.cube` import into flat collections, copied into `Library/LUTs/`; built-ins generated in code; per-table color space | P3 Look-up tables |
| LUT hover preview and browser | Hover in the menu previews; browser sheet with Import and Manage pages; Apply closes, double-click applies and stays | P3; issue #1; UIR §8 Other sheets |

## Export

| Capability | What it does | Source |
|---|---|---|
| Export sheet (⇧⌘E) | Selection or loupe photo to a folder; pair exported once from its RAW; videos skipped. Enabled only when the targets include a photo | P4; UIR §8; `ui-redesign/status.md` E12 (`ExportTargets.canExport`) |
| Formats | JPEG (quality), TIFF 8/16-bit (none, LZW, ZIP); sRGB, Display P3, Adobe RGB, ProPhoto | P4; `Export/ExportSettings.swift` |
| Sizing and sharpening | Full, box, long/short edge, percentage; never enlarged; PPI; output sharpening for screen/print | P4 |
| Metadata levels | All, all except location, copyright and contact only, none; ratings/labels never written | P4 |
| Watermark | One PNG, nine anchors, margin, size, opacity; preview in the sheet | P4; UIR §8 |
| Naming and conflicts | Original name or template; batch names decided first; keep both / replace / skip asked once. A catalogued master is never replaced, whatever the policy: by place (any current mount, links and case followed) or by size and SHA-256 content; the photo gets a numbered name. The alert says how many files in the way are originals | P4; `export-overwrites-masters/` (issue #160); `Catalog/MasterFiles.swift`, `Export/ExportNaming.swift` |
| Merge to HDR (⇧⌘L) | 2 to 9 selected photos of one scene (all raws, or all non-raw; a RAW+JPEG pair counts once) become one new, tone-mapped photo: 16-bit Display P3 TIFF or a 16-bit float linear DNG, written beside the reference frame and catalogued as a new master in its project with its metadata and rating (one undo step, "Merge to HDR"; the file stays). The sheet's table chooses the reference (default the 0 EV frame, else the first by time), which names the result, its folder and project and is what frames align to and win where something moved; Auto-align and De-ghost check boxes, both on at every open. Every refusal shows in the sheet before anything runs. Numbered names, never replaces a file or master; written hidden then moved into place; Stop and Quit leave nothing. Same frames again make another photo. Limits: 9 frames, 150 MP a frame, half the Mac's memory. JPEG brackets are rougher (no response curve); de-ghosting near black can read noise as movement (#257); no link, mark or smart album rule for merged photos. No migration, no pipeline bump | `hdr-merge/` (issue #150: PRD in the issue, `design.md`, `status.md`); `Merge/`, `Catalog/MergedMasters.swift`; UG |
| Export presets | `exportPreset` table | P4 |
| Background export | Progress and Stop in the toolbar Activity item. Results (written, failed, skipped) are reported in Activity only, never in an alert. Can reveal the written files in the Finder when done; the only Finder reveal in the app | UIR §1, §8; UG; `Model/ExportModel.swift`; `ui-redesign/status.md` E14 (`ExportActivityReport`) |

## Command line (`photocli`)

| Capability | What it does | Source |
|---|---|---|
| Registry and contract | One JSON object out; exit codes 0/1/2; `--library-root` | P5 Command line |
| Commands | `render`, `adjustments`, `query projects`, `query images`, `develop`, `rate`, `flag`, `label`, `export`, `help`. `develop` sets `colorFringes.*` and `colorAlignment.*` (`colorAlignment.automatic=true` measures the original), and `noiseReduction.machineLearning` on raws only; `render` and `export` JSON say whether it applied; `export` JSON has `protectedMasters` (photos given a numbered name to spare a master) and `--policy overwrite` never replaces one | P5 Commands; `Commands/`; `ml-denoise/status.md` AC11 |
| `merge` | `merge --version N --version N … [--format tiff\|dng] [--reference N] [--no-align] [--no-deghost]` writes the HDR merge and prints its path, format, frames, reference, `align`, `deghost` and the new version ID; refused while the app has the library open; `--reference` must be one of the `--version`s (a pair's JPEG means its raw); a frame that doesn't line up fails naming `--no-align`. Debug builds are slow (about 35 s for three 1536 x 1024 frames): time release | `hdr-merge/status.md`; `Commands/`; `MergeCommandTests`; `docs/PROFILING.md` |
| Mask commands | `mask list`, `mask add`, `mask set`, `mask remove` | P6 Results; `Commands/MaskCommands.swift` (not in CL's or UG's command lists) |

## UI shell

| Capability | What it does | Source |
|---|---|---|
| One library window | `NavigationSplitView` with inspector; dark appearance on the library window only | UIR decisions 8–9, §1 |
| Customizable toolbar | Import menu, Export, Grid/Loupe, size/zoom, Activity, Filter, Search, inspector; palette items | UIR §5 |
| Activity item | Progress, Stop, last 20 messages; warnings vs information. Stays while its popover is open; messages count as read when the popover closes, not when it opens | UIR §1; `activity-popover/status.md` |
| Menu bar | File, Edit, View, Photo, Adjust, Window, Help; bare keys shown, enabled only when grid/loupe has focus. One File ▸ Stop (⌘.) names the newest job; one Edit ▸ Deselect All (⇧⌘A) serves both windows; Adjust has Import Look-Up Tables…, Reset Crop, Show / Hide Mask Overlay; View ▸ Info / Adjust are checked; New Mask and Add to Mask dim at their limits. Help has one item in either app, About ‹name› (the dead "‹app› Help" item was removed; the menu stays for Help ▸ Search) | UIR §6; CL Menus; `ui-redesign/design.md` §6; `ui-redesign/status.md` E4–E11, E26, E28 |
| Context menus | Photos, loupe, video loupe (culling, keywords, albums, Play / Pause, Show Grid), sidebar items, inspector headers, slider rows, presets, masks, import cells | UIR §7; `ui-redesign/status.md` E9 |
| Inspector | Info / Adjust tabs, pinned histogram, Original toggle and ⋯ menu | UIR §4 |
| Sheets and panels | Export, LUT browser, presets as sheets; panels and alerts window-modal | UIR §8 |
| Settings | Card auto-open; write XMP sidecars | `Views/SettingsView.swift`; UG |
| About window | One window in both apps, opened by the app menu's About ‹name› and Help ▸ About ‹name› (the system About panel is replaced; a second use brings the same window forward; works with the main window closed or a sheet up; not in the Window menu). Shows the app's version and build from the bundle (left out with no bundle), a dedication naming the project, five entries from one record (LibRaw, darktable, LightCraft, GRDB, ExifTool) each with a sentence worded by relationship (included, studied, reimplemented, optional and not included), its license and a link to its page (reported, never opened, under the debug script; no network code), and Gus's copyright (© 2026 Randy Sesser) with the GPL 3-or-later statement. **View License** buttons (LibRaw, LightCraft, GRDB, Gus) open a license window of the file's text from `THIRD_PARTY_NOTICES.md` (the project's section) or `LICENSE` in the bundle's `Resources`, byte for byte, with find; they appear only when those files are there, which needs #172 (none in today's bundles). In the importer the dedication and statement name the project (Gus), the menus, title and header the importer. `Acknowledgements.all` is the one record; `AcknowledgementConsistencyTests` fails when it, the notices, the README Credits and the package or vendored source disagree; no license text in Swift or the catalog. Known: LibRaw's section points to `Sources/CLibRaw/LICENSE.LGPL`, which isn't in the bundle (RI-E1). Checks pending: P1–P9, and the packaging halves of AC7 and AC13 (#172) | `about-gus-dedication/` (#179); UG; `PhotoCore/About/`, `PhotoUI/About/` |

## Accessibility

| Capability | What it does | Source |
|---|---|---|
| VoiceOver for grid, loupe, video loupe, import cells | Labels, values, custom actions, announcements of culling results | UIR §10; `Grid/PhotoAccessibility.swift` |
| Contrast | Dynamic palette with Increase Contrast variants; WCAG ratios asserted in tests | UIR §10; `PaletteContrastTests` |
| VoiceOver speech | Never heard with an assistive app attached | UIR status ("not yet checked on screen") |

## Video

| Capability | What it does | Source |
|---|---|---|
| Catalogued and played | MOV, MP4, M4V; poster frames; duration badge; `AVPlayerView` loupe; culling, keywords, albums, sidecars; View ▸ Play / Pause (Space) | P2 §8; `Import/FileScanner.swift:9`; `ui-redesign/status.md` E8 |
| No editing or export | By design so far | P2; UG |

## Rendering and previews

| Capability | What it does | Source |
|---|---|---|
| Render engine | Core Image, extended linear Rec. 2020 working space, Display P3 output; pool of contexts | CL Rendering; PROFILING "Real camera RAW files" |
| Preview cache | Thumbnail and preview tiers, keyed by content hash, render hash, tier, pipeline version (now 13, a plain bump by #219 after 12 by #196: every cached preview is made again once; the earlier carry-over from 8 to 9 is no longer there). A rendition is kept only under the hash of the stack it was rendered from (`PreviewService.Failure.staleEditStack`), and the editor shows a new hash only after its write lands. Machine learning fallback renders are kept in memory for the session only, never on disk | CL; `Preview/PreviewCacheKey.swift:30`; `ml-denoise/status.md`; `stale-preview-after-save/status.md` (PR #40) |
| RAW decode graph key | Every RAW decode takes its image from `RAWDecodeGraph.output(of:)`, a pass-through clamp with bounds of its own, so a context never reuses one raw's prepared graph (lens correction regions) for another; stops smeared left and right edges. Rests on undocumented Core Image behavior: run `RAWEdgeSmearTests` on real files on every new macOS | `raw-edge-smear/`; CL Rendering; `Preview/RAWDecodeGraph.swift`. Manual check P2 (macOS 26 and 15) open |
| LibRaw fallback decoder | Vendored LibRaw 0.22.3 (LGPL 2.1, `Sources/CLibRaw`) decodes a raw only when the system decoder gives no image (`SystemRAWDecoder.reads` is the one test). Such a photo renders, edits and exports like a raw, with the same White Balance (nine modes, Kelvin, Tint, Auto: see Camera color step); no Color noise reduction, machine learning dimmed. Decodes to camera RGB (not clipped at the camera's white; the file's white level, so it does not depend on content). Half-size decode for thumbnails and previews (about 0.6 s); a full decode takes 0.62 s for an X-E3 since the GPU demosaic (below; 7.7 s with LibRaw's own demosaic, still the fallback). Refused above 150,000,000 sensor pixels; no deflate or lossy DNGs. Raws the system decodes are untouched, byte for byte. Manual checks P1 to P7 open | `raf-not-rendering/` (issue #161); `Preview/LibRawDecoder.swift`, `SystemRAWDecoder.swift` |
| Camera color step (LibRaw raws) | After the decode: the stack's Kelvin and Tint by the DNG specification's method (Robertson's Kelvin and tint scale, matrices read between two calibration lights, forward matrices, Bradford to D50, then Rec. 2020), a built-in profile (`CameraProfile`: matrices, tone curve, baseline exposure) and a baseline look measured against the system decoder (X-E3's exposure, one tone curve). Built as Core Image filters (no custom kernel); a white balance change re-runs the step over the kept decode, never a new decode, at fit and at 100%. A Kelvin or Tint alone takes the other from as shot. Nine modes, Auto (Kelvin and tint), Custom keeps the numbers shown; a paste, a preset and `photocli` carry Kelvin both ways between decoders; relative values never render on a raw. A raw with no usable color data renders as shot and the tab says White Balance is unavailable (or not applied, if a Kelvin was pasted). The stack may name a `cameraProfile` reference (kept, written back unchanged, not used). Fujifilm's held-back exposure (dynamic range 200%/400%) is added. Measured against the system decoder: X-E3 as-shot Kelvin 1.5% under, X-T3 14% to 30% under (accepted by the owner 2026-11-14), unedited look within 0.3 EV for Fujifilm; other makers' baseline exposure is the X-E3's (0.25 to 0.45 EV darker). Not applied: a profile's hue/saturation and look tables (#89). No migration. Checks P1 to P10 open | `white-balance-across-decoders/` (#170); UG; `Sources/PhotoCore/CameraColor/`, `Preview/LibRawDecoder.swift`, `Preview/SystemRAWDecoder.swift`; `CameraColorTests`, `CameraColorStepTests`, `BaselineLookMeasurementTests`, `LibRawAgainstSystemTests` (sample-gated) |
| GPU demosaic (LibRaw raws) | For a raw the system decoder gives no image for, LibRaw only unpacks and our Metal kernels demosaic: Bayer (Hamilton-Adams green, color differences) and X-Trans (four directional green estimates blended by inverse squared variation), then a fixed baseline color noise step (edge-avoiding smoothing of R-G and B-G against the file's own noise model; no control, nothing stored; the Noise Reduction group is as before). Other patterns, any GPU failure and the debug switch use LibRaw's own demosaic, logged with the reason. Frame, lens corrections and the color step follow as before; a white balance change re-runs only the color step. X-E3 full size 0.62 s (LibRaw 7.7 s), X-T3 0.65 s, Bayer 0.10 to 0.31 s; peak about 300 MB at 24 MP. Pipeline version 12 then (plain bump: previews made again once; 13 now, #219). Debug switch `--demosaic libraw` / `RAW_DEMOSAIC=libraw` / `photocli render --demosaic libraw`; `photocli render` prints `decoder` and `demosaic`. Accepted as measured: X-Trans kernel 0.26 to 1.09 dB under LibRaw's three passes (#199 for a sharper one), AC4 only at ISO 800 or lower, detail 0.92x to 0.94x on 5 of 28 files, E-M5 III edge chroma 1.04x. Known: LibRaw's X-Trans demosaic fails on frames of 450 rows or fewer (fallback only). Checks pending: macOS 15 and 26 (CI) | `gpu-demosaic/` (#196); `Sources/PhotoCore/Demosaic/`, `Preview/LibRawDecoder+GPU.swift`; `DemosaicKernelTests`, `ColorNoiseReductionTests`, `GPUDemosaicDecodeTests`, sample-gated `DemosaicXTransSampleTests`, `DemosaicTruthTests` |

## Quality and tooling

| Capability | What it does | Source |
|---|---|---|
| Goldens and CPU references | 16-bit PNG goldens per module; RAW goldens fingerprinted per macOS build | P5; P6 finding 7; CL Checking image code |
| CI | Build and test on `macos-26` and `macos-15`; CodeQL; golden failure images uploaded; when the test process crashes, a backtrace of every thread goes to the log and the system crash reports are uploaded | P5 Notes; P6 question D; `.github/workflows/` (crash capture: PR #42) |
| `photobench` | Synthetic libraries; import, preview, query, edits, masks, kernels, blend-error benchmarks; `denoise` times machine learning noise reduction; `compare` times and measures two full-resolution renders; `scenes` writes the chromatic aberration test scenes (fringes, fringe subjects, pixel grid, lateral color) as TIFFs and a DNG; `generate --dng-without-color N` writes DNGs with no usable color data (a file for the unavailable White Balance state; at the default 6000x4000 the system decoder reads it, so use `--dng-size 256x192`) | `docs/PROFILING.md`; P6; `ml-denoise/status.md` R14 |
| Debug script | Drives the app for snapshots and checks; `compare` and `compareclick` drive comparison, `compare panbench` counts hitches while panning; `about …` (open, print, menus, link, license, snapshot, click, quithost, quitask…) drives the About window and its license windows in both apps | CL Commands; `Model/DebugScript.swift`; `PhotoUI/About/AboutDebugCommands.swift` |
| Launch guard | A test launch without `--library-root` is refused before anything in the standard data or cache folders is opened or created: a bundle identifier other than the release one (or none, as with `swift run`), or `--debug-script` / `--benchmark-scroll`. The reason goes to standard error; a launch a person started then shows an alert; either way the app quits with status 64. `photocli`, `photobench` and the standalone importer are not guarded | `library-launch-guard/status.md` (PR #47); UG Development options; `Launch/LibraryLaunchGuard.swift`, `AppLauncher.swift` |
| Branding isolation | Brand values only in `AppBranding.swift` / `Branding.xcconfig`; enforced by tests | CL Naming rules |

## Doc-only claims

None found among the claims I checked. Not checked in code: Vision confidence
floor and label cap (P2 As built), ExifTool pool size, every smart-album
rule field.
