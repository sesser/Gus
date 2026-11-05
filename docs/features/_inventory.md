# Capability inventory

What the app does today: `develop` as of 2026-11-04, after the film strip
merged (PR #27). Owned by the product-manager agent; a
reference for spotting duplicates and conflicts before a feature is specified.
It stands in for a `prd.md` for the UI redesign (owner, 2026-11-04);
`ui-redesign/prd.md` adds only the rulings on design.md's requirements issues.

Corrected 2026-11-04 after the UI redesign reconciliation: project rename and
removal (data only), drag and drop, export's reveal in the Finder, the Help
menu, and the metadata reader's visibility.

Markers:

- **[inferred from code]**: no document states it; the claim rests on code alone.
- **[doc only, not found in code]**: a document claims it and I could not find it.
- No marker: a document states it and the code was spot-checked, or it was
  not contradicted.

Abbreviations: P1–P6 = `docs/PHASE1_PLAN.md` … `PHASE6_PLAN.md`; UIR =
`docs/UI_REDESIGN.md`; UG = `docs/USER_GUIDE.md`; CL = `CLAUDE.md`.

## Catalog and library

| Capability | What it does | Source |
|---|---|---|
| Referenced masters | Originals stay where they are; catalog stores volume, relative path, SHA-256, size, mtime | CL Architecture; P1 Catalog schema |
| Offline volumes | Masters on unmounted volumes show offline with cached previews; rows never deleted; volumes matched by UUID | CL; P1; UG |
| Migrations v1–v13 | 21 tables incl. `imagePair`, `importRun`, `keywordSuggestion`, `smartAlbum`, `importPreset`, `metadataSync`, `sidecarQueue`, `exportPreset` | P1–P4; `Catalog/CatalogSchema.swift` (CL's table list omits eight of them) |
| Projects | Each master belongs to one project, named after the imported folder or a template | P1 Import; P2 §7 |
| Rename and remove projects (data only) | `Catalog.renameProject`; `Catalog.deleteProject` removes a project's catalog rows (masters, versions, album memberships) and never touches files. No UI or command uses either; nothing removes single photos | `Catalog/Catalog.swift:152`, `:160`; `CatalogTests.deletingAProjectCascadesToItsCatalogRowsOnly` **[inferred from code]**. Roadmap: rename-project, remove-from-library |
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
| Review mode (F) | Full-screen loupe, panes hidden, toolbar on hover | UIR §2; `Model/ReviewActions.swift` |
| Empty states | `ContentUnavailableView` for empty library, no matches, no selection | UIR §9 |

## Loupe

| Capability | What it does | Source |
|---|---|---|
| Loupe | Fit, 100% and zoom steps 25–800%, pinch and ⌥-scroll, neighbour preloading | P1 App; UIR §6 |
| Caption line | Position, stars, flag, label name, Filtered/Original/HDR/Offline badges | UIR §1 |
| Show Original (`\`) | Before/after while editing | P3 sidebar; UIR §4 |
| HDR display | HDR sources (float DNG, gain maps, HLG/PQ) render HDR on EDR screens; View ▸ Hide HDR Highlights | CL Rendering; UG |
| Film strip | The source's photos in a strip between the loupe (or video loupe) and the caption. Clicking a photo focuses it, and the focused photo stays centered. A drag handle resizes it in steps (48–120 pt, capped at 25% of the loupe height). Caption toggle and ⌥⌘B show or hide it with a slide. VoiceOver list and splitter. Never shown in review mode | Issue #25 (closed); UIR §11; `Loupe/FilmStrip*.swift`, `Browser/FilmStripGeometry.swift`. Not yet checked on screen. §11's checklist leaves 7 build items unticked that the code appears to implement |

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
| Effects | Look-up table, vignette, grain | P3 |
| Group on/off | Check box per group keeps edits but disables them | P3 sidebar; UIR §4 |
| Copy / Paste Adjustments | Paste carries crop, not masks | UG; P6 |
| Live rendering | Decoded master reused per frame; one save and undo step per gesture; stage cache and adaptive drafts | CL Editing; P6 Caching and drafts |
| Runtime GPU kernels (spike) | Compiled at run time; not used by the renderer | P5; `Edits/Kernels/RuntimeKernels.swift` |

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
| Lightroom preset import | `.lrtemplate`, `.xmp`, `.dng`; report of unmapped settings | P3 second pass; `Presets/` |
| Manage Presets sheet | Rename, move, export, delete, change groups | P3; UIR §8 |
| Look-up tables | `.cube` import into flat collections, copied into `Library/LUTs/`; built-ins generated in code; per-table color space | P3 Look-up tables |
| LUT hover preview and browser | Hover in the menu previews; browser sheet with Import and Manage pages; Apply closes, double-click applies and stays | P3; issue #1; UIR §8 Other sheets |

## Export

| Capability | What it does | Source |
|---|---|---|
| Export sheet (⇧⌘E) | Selection or loupe photo to a folder; pair exported once from its RAW; videos skipped | P4; UIR §8 |
| Formats | JPEG (quality), TIFF 8/16-bit (none, LZW, ZIP); sRGB, Display P3, Adobe RGB, ProPhoto | P4; `Export/ExportSettings.swift` |
| Sizing and sharpening | Full, box, long/short edge, percentage; never enlarged; PPI; output sharpening for screen/print | P4 |
| Metadata levels | All, all except location, copyright and contact only, none; ratings/labels never written | P4 |
| Watermark | One PNG, nine anchors, margin, size, opacity; preview in the sheet | P4; UIR §8 |
| Naming and conflicts | Original name or template; batch names decided first; keep both / replace / skip asked once | P4 |
| Export presets | `exportPreset` table | P4 |
| Background export | Progress and Stop in the toolbar Activity item. Can reveal the written files in the Finder when done; the only Finder reveal in the app | UIR §1, §8; UG; `Model/ExportModel.swift:348` |

## Command line (`photocli`)

| Capability | What it does | Source |
|---|---|---|
| Registry and contract | One JSON object out; exit codes 0/1/2; `--library-root` | P5 Command line |
| Commands | `render`, `adjustments`, `query projects`, `query images`, `develop`, `rate`, `flag`, `label`, `export`, `help` | P5 Commands; `Commands/` |
| Mask commands | `mask list`, `mask add`, `mask set`, `mask remove` | P6 Results; `Commands/MaskCommands.swift` (not in CL's or UG's command lists) |

## UI shell

| Capability | What it does | Source |
|---|---|---|
| One library window | `NavigationSplitView` with inspector; dark appearance on the library window only | UIR decisions 8–9, §1 |
| Customizable toolbar | Import menu, Export, Grid/Loupe, size/zoom, Activity, Filter, Search, inspector; palette items | UIR §5 |
| Activity item | Progress, Stop, last 20 messages; warnings vs information | UIR §1 |
| Menu bar | File, Edit, View, Photo, Adjust, Window, Help; bare keys shown, enabled only when grid/loupe has focus. Help has only SwiftUI's default "‹app› Help" item, which says no help is available (both apps); ruled for removal in `ui-redesign/prd.md` R1 | UIR §6; CL Menus; `ui-redesign/design.md` N13, I28 |
| Context menus | Photos, loupe, sidebar items, inspector headers, slider rows, presets, masks, import cells | UIR §7 |
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
| Catalogued and played | MOV, MP4, M4V; poster frames; duration badge; `AVPlayerView` loupe; culling, keywords, albums, sidecars | P2 §8; `Import/FileScanner.swift:9` |
| No editing or export | By design so far | P2; UG |

## Rendering and previews

| Capability | What it does | Source |
|---|---|---|
| Render engine | Core Image, extended linear Rec. 2020 working space, Display P3 output; pool of contexts | CL Rendering; PROFILING "Real camera RAW files" |
| Preview cache | Thumbnail and preview tiers, keyed by content hash, render hash, tier, pipeline version (now 5) | CL; `Preview/PreviewCacheKey.swift:30` |

## Quality and tooling

| Capability | What it does | Source |
|---|---|---|
| Goldens and CPU references | 16-bit PNG goldens per module; RAW goldens fingerprinted per macOS build | P5; P6 finding 7; CL Checking image code |
| CI | Build and test on `macos-26` and `macos-15`; CodeQL; golden failure images uploaded | P5 Notes; P6 question D; `.github/workflows/` |
| `photobench` | Synthetic libraries; import, preview, query, edits, masks, kernels, blend-error benchmarks | `docs/PROFILING.md`; P6 |
| Debug script | Drives the app for snapshots and checks | CL Commands; `Model/DebugScript.swift` |
| Branding isolation | Brand values only in `AppBranding.swift` / `Branding.xcconfig`; enforced by tests | CL Naming rules |

## Doc-only claims

None found among the claims I checked. Not checked in code: Vision confidence
floor and label cap (P2 As built), ExifTool pool size, every smart-album
rule field.
