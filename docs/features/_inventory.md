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
| Rename project, remove from library, Show in Finder | Rename a project in place (sidebar, File, row menu; one undo step; catalog only). Remove from Library… (⌘⌫) takes photos (a RAW+JPEG pair together) and Remove Project from Library… takes a project, its photos and its own albums, in one transaction, after a confirmation with no default button; no undo; files and sidecars never touched; offline photos can be removed; re-import gives new photos. Show in Finder (⇧⌘R) reveals photos' masters (one window per folder) or a project's source folder. Remove is off while a folder add or card import runs | `library-ops/prd.md`; `Catalog/LibraryRemoval.swift`, `Catalog/ProjectRename.swift`, `Browser/FinderReveal.swift`, `Browser/RemovalConfirmation.swift`; `LibraryRemovalTests`, `LibraryOpsRuleTests`; UG |
| Versions | Ratings, flags, labels and edit stack live on a version; one default version per master | P1 schema; CL |
| Duplicate a version | `Catalog.duplicateVersion` copies a version's stack and culling; no UI or command uses it | `Catalog/Catalog.swift:492` **[inferred from code]** |
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
| Quit guard | Asks before quitting stops an import or export | UIR §8; `PhotoUI/QuitGuard.swift` |
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
| Sharp live frames at 100% | At 100% and above, while a value changes (sliders, curve, wheels, mask handles, brush, hover previews, Show Original, mask overlay) the loupe shows the visible part rendered from full-resolution pixels, matching the render after letting go. RAW white balance, profile and noise reduction are soft while moving, sharp on a pause; a drag may start soft, and may go soft briefly when Exposure or Highlights cross 0. Never blank; histogram stays whole-photo. Full-resolution copy held only at covered zooms, no memory cap. Below 100% unchanged | `viewport-render-1to1/` (PR #49); `viewport-render-qa-findings/`; UG |
| Caption line | Position, stars, flag, label name, Filtered/Original/HDR/Offline badges | UIR §1 |
| Show Original (`\`) | Before/after while editing | P3 sidebar; UIR §4 |
| HDR display | HDR sources (float DNG, gain maps, HLG/PQ) render HDR on EDR screens; View ▸ Hide HDR Highlights | CL Rendering; UG |
| Film strip | The source's photos in a strip between the loupe (or video loupe) and the caption. Clicking a photo focuses it, and the focused photo stays centered. A drag handle resizes it in steps (48–120 pt, capped at 25% of the loupe height). Caption toggle and ⌥⌘B show or hide it with a slide. VoiceOver list and splitter. Never shown in review mode | Issue #25 (closed); UIR §11; `Loupe/FilmStrip*.swift`, `Browser/FilmStripGeometry.swift`. Not yet checked on screen. §11's checklist leaves 7 build items unticked that the code appears to implement |
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
| Light (was Develop) | Profile (Standard/Neutral/Flat, decoder version), white balance (Mode, Kelvin, tint, Auto), exposure with Auto, tone, presence | P3; UIR decision 15 |
| Tone Curve | Point curve on RGB or per channel over the histogram | P3 |
| Color Mixer | Hue, saturation, luminance of eight bands | P3 second pass |
| Color Grading | Shadows, midtones, highlights wheels; balance; blending | P3 |
| Details | Sharpening (amount, radius, detail, masking); noise reduction | P3 |
| Sharpening map | Shows in the loupe where Masking lets sharpening through: live while values change, full resolution once input pauses; "Not Applied" when nothing is sharpened. A view only: not saved, no undo, never in previews or exports | `sharpen-mask-preview/`; UG; `Edits/SharpeningMap.swift`. Manual checks M1–M9 open |
| Machine learning noise reduction | Raw files only, opt-in per photo, in the Noise Reduction group (Luminance is its amount, Color dimmed while it applies). Uses the macOS 27 raw decoder's version 9 (`9.dng` / `9` in the Decoder pop-up); no model shipped or downloaded. Where it can't apply (older macOS, unsupported camera, failed decode) the photo renders classically, keeps the setting, and the caption badge and Activity say why. Carried by paste, presets and batch commands to raws only | `ml-denoise/`; UG; `Edits/MachineLearningNoiseReduction.swift`. A missing model is not detected yet (RI-E6); AC13 and manual checks open |
| Color Fringes | Lens heading. Two slots, filled by picking from the photo or from a short list (Purple, Green); each slot's color turns gray near high-contrast edges only, keeping brightness, with its own Tolerance. Matches on the decoded photo before other adjustments (a raw's White Balance and Profile come first). Off by default; not in masks; photos only | `chromatic-aberration/prd.md`; UG |
| Fringe Map | Shows in the loupe where fringe color is removed; a view only, one map on screen at a time | `chromatic-aberration/prd.md` R6; UG |
| Color Alignment | Lens heading. Align automatically measures red/cyan and blue/yellow edges once and stores the correction, centered on the sensor so crops don't change it; or set by hand. Paste and presets measure each receiving photo; one that can't be measured is left unchanged, and Activity says so | `chromatic-aberration/prd.md`; UG |
| Effects | Look-up table, vignette, grain | P3 |
| Group on/off | Check box per group keeps edits but disables them | P3 sidebar; UIR §4 |
| Copy / Paste Adjustments | Paste carries crop, not masks | UG; P6 |
| Live rendering | Decoded master reused per frame; one save and undo step per gesture; stage cache and adaptive drafts at fit; at 100% and above, frames of the visible area at full resolution (see Sharp live frames at 100%). The loupe loads a photo's edits only after its pending saves land (shows loading meanwhile), and library reloads never put back values older than a change already made | CL Editing; P6 Caching and drafts; `editor-follow-edit-drop/status.md` (PR #43) |
| Runtime GPU kernels (spike) | Compiled at run time; not used by the renderer | P5; `Edits/Kernels/RuntimeKernels.swift` |
| Lens kernels | Stitchable Core Image kernels compiled at run time, used by the Lens heading. If they can't compile, the corrections are skipped with no message (known limitation, RI-CR1) | `chromatic-aberration/prd.md`; `Edits/Kernels/LensKernels.swift` |

## Crop

| Capability | What it does | Source |
|---|---|---|
| Crop, rotate, straighten | Session in the loupe (`C`), aspect presets, quarter turns, ±45° straighten; Rotate ⌘[ / ⌘] commits at once | CL Scope; UG |
| Whole-sensor crop for camera-cropped raws | Olympus/OM System/Panasonic aspect crops can be widened | CL; `Preview/CameraFrame.swift` |

## Masks (local adjustments)

| Capability | What it does | Source |
|---|---|---|
| Shapes | Linear and radial gradients, brush, luminance range, color range | P6 Shapes |
| Combining | Add, subtract, intersect, per-component invert, Amount | P6 decision 4 |
| Local controls | Exposure (exact), tone, temperature/tint, presence, sharpening | P6 decision 5 |
| Masks heading and overlay | List with rename, on/off, reorder, delete; handles, brush cursor, red overlay | P6 UI; UIR §4 |
| Limits | 32 masks, 16 components, 8 color samples, 200 000 brush points | P6 decision 2 |

## Presets and look-up tables

| Capability | What it does | Source |
|---|---|---|
| Adjustment presets | Partial presets by group, collections, hover preview, preview tiles | P3 second pass |
| Preset files | xz-compressed JSON with embedded `.cube` files; Finder double-click imports | P3 second pass; `Support/Info.plist` (exported type) |
| Lightroom preset import | `.lrtemplate`, `.xmp`, `.dng`; report of unmapped settings. Purple and green fringe removal and automatic chromatic aberration removal map to the Lens groups | P3 second pass; `Presets/` |
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
| Naming and conflicts | Original name or template; batch names decided first; keep both / replace / skip asked once | P4 |
| Export presets | `exportPreset` table | P4 |
| Background export | Progress and Stop in the toolbar Activity item. Results (written, failed, skipped) are reported in Activity only, never in an alert. Can reveal the written files in the Finder when done; the only Finder reveal in the app | UIR §1, §8; UG; `Model/ExportModel.swift`; `ui-redesign/status.md` E14 (`ExportActivityReport`) |

## Command line (`photocli`)

| Capability | What it does | Source |
|---|---|---|
| Registry and contract | One JSON object out; exit codes 0/1/2; `--library-root` | P5 Command line |
| Commands | `render`, `adjustments`, `query projects`, `query images`, `develop`, `rate`, `flag`, `label`, `export`, `help`. `develop` sets `colorFringes.*` and `colorAlignment.*` (`colorAlignment.automatic=true` measures the original), and `noiseReduction.machineLearning` on raws only; `render` and `export` JSON say whether it applied | P5 Commands; `Commands/`; `ml-denoise/status.md` AC11 |
| Mask commands | `mask list`, `mask add`, `mask set`, `mask remove` | P6 Results; `Commands/MaskCommands.swift` (not in CL's or UG's command lists) |

## UI shell

| Capability | What it does | Source |
|---|---|---|
| One library window | `NavigationSplitView` with inspector; dark appearance on the library window only | UIR decisions 8–9, §1 |
| Customizable toolbar | Import menu, Export, Grid/Loupe, size/zoom, Activity, Filter, Search, inspector; palette items | UIR §5 |
| Activity item | Progress, Stop, last 20 messages; warnings vs information. Stays while its popover is open; messages count as read when the popover closes, not when it opens | UIR §1; `activity-popover/status.md` |
| Menu bar | File, Edit, View, Photo, Adjust, Window, Help; bare keys shown, enabled only when grid/loupe has focus. One File ▸ Stop (⌘.) names the newest job; one Edit ▸ Deselect All (⇧⌘A) serves both windows; Adjust has Import Look-Up Tables…, Reset Crop, Show / Hide Mask Overlay; View ▸ Info / Adjust are checked; New Mask and Add to Mask dim at their limits. Help has no items in either app (the dead "‹app› Help" item was removed); the menu stays for Help ▸ Search | UIR §6; CL Menus; `ui-redesign/design.md` §6; `ui-redesign/status.md` E4–E11, E26, E28 |
| Context menus | Photos, loupe, video loupe (culling, keywords, albums, Play / Pause, Show Grid), sidebar items, inspector headers, slider rows, presets, masks, import cells | UIR §7; `ui-redesign/status.md` E9 |
| Inspector | Info / Adjust tabs, pinned histogram, Original toggle and ⋯ menu | UIR §4 |
| Sheets and panels | Export, LUT browser, presets as sheets; panels and alerts window-modal | UIR §8 |
| Settings | Card auto-open; write XMP sidecars | `Views/SettingsView.swift`; UG |

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
| Preview cache | Thumbnail and preview tiers, keyed by content hash, render hash, tier, pipeline version (now 8). A rendition is kept only under the hash of the stack it was rendered from (`PreviewService.Failure.staleEditStack`), and the editor shows a new hash only after its write lands. Machine learning fallback renders are kept in memory for the session only, never on disk | CL; `Preview/PreviewCacheKey.swift:30`; `ml-denoise/status.md`; `stale-preview-after-save/status.md` (PR #40) |
| RAW decode graph key | Every RAW decode takes its image from `RAWDecodeGraph.output(of:)`, a pass-through clamp with bounds of its own, so a context never reuses one raw's prepared graph (lens correction regions) for another; stops smeared left and right edges. Rests on undocumented Core Image behavior: run `RAWEdgeSmearTests` on real files on every new macOS | `raw-edge-smear/`; CL Rendering; `Preview/RAWDecodeGraph.swift`. Manual check P2 (macOS 26 and 15) open |

## Quality and tooling

| Capability | What it does | Source |
|---|---|---|
| Goldens and CPU references | 16-bit PNG goldens per module; RAW goldens fingerprinted per macOS build | P5; P6 finding 7; CL Checking image code |
| CI | Build and test on `macos-26` and `macos-15`; CodeQL; golden failure images uploaded; when the test process crashes, a backtrace of every thread goes to the log and the system crash reports are uploaded | P5 Notes; P6 question D; `.github/workflows/` (crash capture: PR #42) |
| `photobench` | Synthetic libraries; import, preview, query, edits, masks, kernels, blend-error benchmarks; `denoise` times machine learning noise reduction; `scenes` writes the chromatic aberration test scenes (fringes, fringe subjects, pixel grid, lateral color) as TIFFs and a DNG | `docs/PROFILING.md`; P6; `ml-denoise/status.md` R14 |
| Debug script | Drives the app for snapshots and checks | CL Commands; `Model/DebugScript.swift` |
| Launch guard | A test launch without `--library-root` is refused before anything in the standard data or cache folders is opened or created: a bundle identifier other than the release one (or none, as with `swift run`), or `--debug-script` / `--benchmark-scroll`. The reason goes to standard error; a launch a person started then shows an alert; either way the app quits with status 64. `photocli`, `photobench` and the standalone importer are not guarded | `library-launch-guard/status.md` (PR #47); UG Development options; `Launch/LibraryLaunchGuard.swift`, `AppLauncher.swift` |
| Branding isolation | Brand values only in `AppBranding.swift` / `Branding.xcconfig`; enforced by tests | CL Naming rules |

## Doc-only claims

None found among the claims I checked. Not checked in code: Vision confidence
floor and label cap (P2 As built), ExifTool pool size, every smart-album
rule field.
