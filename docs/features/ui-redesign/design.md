# UI redesign: current design

Owner: apple-ui-designer. Date: 2026-11-04. Feature status: Shipped
(roadmap); this document reconciles what shipped with what the app does.

**Purpose.** One current design for the library window, the Import window
(both apps), menus, toolbar, context menus, inspector and sheets. It records
where every capability lives, rules on conflicts between surfaces, and lists
the code changes needed to match.

**Inputs.**

- Requirements: the capability inventory, `docs/features/_inventory.md`
  (stands in for `prd.md`, owner 2026-11-04). Cited as "Inv ▸ Section ▸ Row".
- Base plan: `docs/UI_REDESIGN.md`, cited as "UIR §n". It stays the historical
  record and is not edited. Everything in it stands unless this document
  overrides it. This document restates only what changes or what has to be
  in one place (the command map, §4).
- Code checked read-only at `463b44a` (`develop`), mainly
  `Sources/PhotoApp/Views/LibraryCommands.swift`, `LibraryToolbar.swift`,
  `Grid/PhotoContextMenu.swift`, `SidebarView.swift`, `InspectorView.swift`,
  `AdjustView.swift`, `MasksSection.swift`, `PresetsSection.swift`,
  `CropControls.swift`, `MainView.swift`, `SettingsView.swift`,
  `Loupe/VideoLoupe.swift`, `Sources/PhotoUI/Import/ImportCommands.swift`,
  `ImportWindow.swift`, `Sources/PhotoImporter/ImporterApplication.swift`,
  and `docs/USER_GUIDE.md` (UG).
- HIG pages read 2026-11-04 (markdown versions): Writing, The menu bar,
  Keyboards.

## Placement rules applied

| # | Rule | Basis |
|---|---|---|
| P1 | The menu bar holds every command that starts from the library or Import window. Items stay listed and are dimmed when they can't act. Commands that only make sense inside a sheet stay in the sheet, because menus are off while a sheet is up (UIR §6). | HIG The menu bar: "Always show the same set of menu items… disable the action instead of hiding it". Roadmap principle 5 |
| P2 | Toolbar items, context menus, inspector buttons and keys are second paths to the same command. They use the same title (toolbar labels drop the ellipsis) and the same enablement. A context menu leaves out what can't act (UIR §7). | HIG Writing: "Build language patterns" |
| P3 | One key, one item. When the library app and `ImportCommands` want the same key, there is one item, titled and acting for the key window. This is the ⌥⌘I precedent (UIR §6), needed because AppKit matches the first item with that key equivalent even when it is disabled. | UIR §6 |
| P4 | Report where the task is. While a task's window is open and in front, its alert goes on that window. Background tasks (an export after its sheet closes, folder adds, a card copy after its window closes) report in Activity. Information that needs no action never gets an alert. | UIR §1, §8; HIG Alerts |
| P5 | One term for each thing, with a fixed capitalization per element type. Row labels, check boxes and radio buttons are sentence-style. Menus, buttons, pop-up items and section titles are title-style. | HIG Writing: "Create a list of common terms… Choose a style for each UI element type"; UIR §8 Form conventions |

## 1. Capabilities the plan doesn't place

### 1a. New placements

| # | Capability (inventory) | Today | Ruling | Basis | Change |
|---|---|---|---|---|---|
| N1 | Inv ▸ Catalog ▸ "Unreadable edit stacks protected"; Inv ▸ Catalog ▸ "Offline volumes"; Inv ▸ Video ▸ "No editing or export" | UIR §4 covers only the grid's "Open a Photo to Adjust It". In the loupe the Adjust tab shows plain centered text for video, offline, unreadable and no photo (`AdjustView.message`) | Each of these states becomes a `ContentUnavailableView`: **No Adjustments for Videos**; **Original Offline**, described "Connect its volume to adjust this photo."; **Can't Edit This Photo**, described by the existing `AdjustText.unreadableMessage`. Loading keeps its small spinner. The pinned Original toggle and ⋯ menu stay hidden, as now | Consistency with the grid's state; HIG Writing, empty states | E2 |
| N2 | Inv ▸ Import ▸ "Auto-open on card insert"; Inv ▸ Metadata ▸ "XMP sidecars"; Inv ▸ UI shell ▸ "Settings" | UIR §8 names the Settings scene but not what is in it | Settings is one 480 pt pane, a grouped `Form` with two sections. **Importing** has "Open the import window when a card is inserted". **Metadata** has "Write XMP sidecar files when photos change" and its caption. Both are **check boxes** (see I10). The standalone importer has no Settings window: it is the import window and always follows cards | UIR §8 Form conventions | E3 |
| N3 | Inv ▸ Grid ▸ "Empty states" | UIR §9 covers an empty library and "No Photos Match". **Code:** an empty album, smart album, keyword, date or built-in source (Picks, Last Import…) shows "No Photos Yet" with Import buttons (`EmptyLibraryView` tests only `itemCount` and `isFiltered`), which is wrong for a library that has photos | Three cases. (1) The library is empty (`libraryCount == 0`): "No Photos Yet", as UIR §9. (2) A filter is on: "No Photos Match" with Clear Filter. (3) Otherwise: **No Photos in “‹source›”**. An album adds "Drag photos onto the album in the sidebar, or choose Photo ▸ Add to Album." A smart album adds "No photo meets this smart album's rules." and an **Edit Smart Album…** button. Other sources get no description and no button | HIG Writing: "Provide clear next steps on any blank screens" | E1 |
| N4 | Inv ▸ Grid ▸ "Albums and smart albums" (UG: drag photos onto an album or keyword) | Built (`SidebarView` `onDrop`), not in UIR | Keep. These drops are second paths for Add to Album and Add Keywords (§4). The drop highlight comes from the system list | P2 | none |
| N5 | Inv ▸ Presets and LUTs ▸ "Look-up tables" (import) | Reachable only through Browse Look-Up Tables…, then the Import… page. Activity already titles the job "Import Look-Up Tables" after a menu command that doesn't exist (UIR §1 derives row titles from menu titles) | **Adjust ▸ Import Look-Up Tables…** after Import Presets…. It opens the browser sheet directly on its Import page, where Back goes to Tables | P1 | E4 |
| N6 | Inv ▸ Crop ▸ "Crop, rotate, straighten" (Reset Crop) | Only on the Crop & Straighten heading's reset button | **Adjust ▸ Reset Crop**, after Crop / Finish Cropping. It is loupe only (the heading is loupe only), enabled when the photo has a crop or the session has changed it, dimmed for video, and one undo step | P1 | E5 |
| N7 | Inv ▸ Masks ▸ "Masks heading and overlay" (overlay) | Only on the eye button in the Masks heading | **Adjust ▸ Show Mask Overlay / Hide Mask Overlay**, after New Mask ▸. The title follows state. Enabled while a mask is selected in the loupe | P1; HIG The menu bar, show/hide titles reflect state | E6 |
| N8 | Inv ▸ Masks ▸ "Limits" | New Mask and Add to Mask stay enabled. Going past a limit posts an Activity warning afterwards | At 32 masks, Adjust ▸ New Mask ▸ and the heading's shape buttons are dimmed, with the tooltip "A photo can have up to 32 masks." At 16 components the "Add to Mask:" buttons are dimmed, with "A mask can combine up to 16 shapes." The brush-point limit can't be predicted, so its Activity warning stays | Prevent the error rather than report it (HIG Writing, errors) | E7 |
| N9 | Inv ▸ Video ▸ "Catalogued and played" | Play/Pause exists only as Space and a VoiceOver action. The video loupe has **no context menu**, though the photo loupe has one (UIR §7 "Loupe") | **View ▸ Play / Pause** shows Space as its key; the title follows state. It is enabled only while the video loupe has the keyboard (a bare-key item, UIR §6). The video loupe gets a context menu with the loupe's photo items (Rating, Flag, Color Label, keywords, albums), then Play / Pause and Show Grid. That matches its VoiceOver actions (UIR §10). It has no adjustment items and no Export, because videos aren't exported | P1, P2 | E8, E9 |
| N10 | Inv ▸ Masks ▸ "Combining", "Local controls"; brush and color sampling | Component rows (operation pop-up, invert, remove), Amount, local sliders, Paint / Done Painting, Pick Colors / Done Picking. UIR §4 lists only the mask rows | Keep as built, inspector only. These are parameters and tool modes of the selected mask (like slider values), not commands, so they have no menu items | Judgment: the HIG doesn't ask for parameter values in menus | none |
| N11 | Inv ▸ Crop (aspect presets, Straighten) | Inspector and the crop overlay | Keep inspector only, for the same reason as N10 | Judgment | none |
| N12 | Inv ▸ Grid ▸ "RAW+JPEG pairs" (Info tab) | The Info tab's File row shows a "RAW + JPEG" pill (code); UIR §4 omits it | Keep as built | none | none |
| N13 | (no capability) Help menu; prd.md R1, R2 | SwiftUI's default "‹app› Help" item, which says no help is available | Per prd.md R1 and R2: remove the dead "‹app› Help" item from both apps, and keep the Help menu with its system search field, which finds menu commands. Help content is new scope (`in-app-help`) | HIG The menu bar: Help menu; principle 5, every command can be found in a menu | E28 |

### 1b. Every inventory row

Rows already placed by UIR, rows placed above, and rows that need no
surface. Together they cover every inventory row.

| Inventory section | Rows | Status | Where / why |
|---|---|---|---|
| Catalog and library | Referenced masters | Placed | Info tab File, Folder, Volume rows (UIR §4). Nothing else to show |
| | Offline volumes | Placed + N1 | Offline badge in the caption and grid values (UIR §1, §10), Activity warnings (UIR §1), Adjust tab state (N1) |
| | Migrations v1–v13; Versions; Data directory migration | No surface needed | Storage internals. A rename migrates silently |
| | Projects | Placed | Sidebar Projects (UIR §3), Import options Project (UIR §8) |
| | Rename and remove projects (data only) | Deferred | `Catalog.renameProject` and `Catalog.deleteProject` exist with no UI or command (the inventory row is corrected). Their UI belongs to `rename-project` and `remove-from-library`, each with its own PRD (RI-2). Until then File ▸ Rename and Delete stay dimmed for projects |
| | Duplicate a version | Deferred | `virtual-copies`. No UI until specified |
| | Stacks (data only) | Deferred | `stacks` |
| | Keyword hierarchy (data only) | Deferred | `hierarchical-keywords` |
| | Library lock | No surface needed | The app takes the lock silently; `photocli` reports a refusal itself |
| | Unreadable edit stacks protected | Placed + N1 | Activity sentence (UIR §1), Adjust tab state (N1) |
| Import | Add Folder Without Copying…; Folder drops; Card and folder import; Duplicate hiding; Naming templates; Metadata presets; Keep picks on rescan; Shutter count; Keeps running after close; Quit guard; Delete from card, eject; Copy and verify | Placed | UIR §5, §6, §8, §9, decision 19. Copy and verify shows only as progress and results (UIR §8) |
| | Auto-open on card insert | N2 | Settings |
| | Metadata reading (ExifTool / ImageIO / AVFoundation) | No surface needed | Internal. Showing which reader is in use is new scope (RI-4, `metadata-reader-status`) |
| Standalone importer | Importer app; Close confirmation | Placed | UIR §8 |
| Grid, browsing and culling | AppKit grid; RAW+JPEG pairs; Culling keys; Filter, sort, search; Sidebar; Albums and smart albums; Batch edit commands; Undo / redo; Review mode | Placed (+ N4, N12) | UIR §2, §3, §5–§7, §10 |
| | Empty states | Placed + N3 | UIR §9 and N3 |
| Loupe | Loupe; Caption line; Show Original; HDR display; Film strip | Placed | UIR §1, §4, §6, §11 |
| Metadata, keywords and sidecars | Keywords; Keyword suggestions; Info tab; Descriptive fields; Changed on Disk review; Masters changed outside | Placed | UIR §3, §4, §6, §7 (terms fixed by I8, I9) |
| | XMP sidecars | N2 | Settings toggle |
| | `name.ext.xmp` on stem clash | No surface needed | File-naming internal |
| Editing (global) | Light; Tone Curve; Color Mixer; Color Grading; Details; Effects; Group on/off; Copy / Paste Adjustments | Placed | UIR §4, §6, §7 |
| | Edit stack; Live rendering; Runtime GPU kernels (spike) | No surface needed | Rendering internals |
| Crop | Crop, rotate, straighten | Placed + N6, N11 | UIR §4, §6 |
| | Whole-sensor crop for camera-cropped raws | No surface needed | Shows as the crop frame being able to widen. No control of its own |
| Masks | Shapes; Masks heading and overlay | Placed + N7 | UIR §4, §6 |
| | Combining; Local controls | N10 | Inspector only |
| | Limits | N8 | |
| Presets and look-up tables | Adjustment presets; Preset files (Finder double-click); Lightroom import; Manage Presets; LUT hover and browser | Placed | UIR §4, §6, §8 |
| | Look-up tables (import) | N5 | |
| Export | Export sheet; Formats; Sizing; Metadata levels; Watermark; Naming and conflicts; Export presets; Background export | Placed | UIR §1, §8 (results reporting: I3) |
| Command line | Registry and contract; Commands; Mask commands | No surface needed | `photocli` only |
| UI shell | One library window; Customizable toolbar; Activity item; Menu bar; Context menus; Inspector; Sheets and panels | Placed | UIR §1, §4–§8 |
| | Settings | N2 | |
| Accessibility | VoiceOver; Contrast | Placed | UIR §10 |
| | VoiceOver speech never heard | Deferred | `ui-redesign-onscreen-check` |
| Video | Catalogued and played | Placed + N9 | |
| | No editing or export | Placed | Adjust tab state (N1). Export skips videos (UIR §8 header) |
| Rendering and previews | Render engine; Preview cache | No surface needed | The cache can be deleted in the Finder (UG Data locations) |
| Quality and tooling | Goldens; CI; `photobench`; Debug script; Branding isolation | No surface needed | Developer tooling |

## 2. Parts of the plan no capability needs

| # | Plan element | Why no capability needs it | Ruling |
|---|---|---|---|
| X1 | UIR status table, Steps 1–15, Audit F1–F32, "Prototype one guarded bare-key item first" (step 3) | Finished work | Keep as history. This document is the current design |
| X2 | UIR "Not yet checked on screen" list; §11 checklist (7 build items open, plus the on-screen item); §8 Export "check whether `.presentationSizing` lets people resize the sheet vertically" | Verification, not design | Defer to `ui-redesign-onscreen-check`. Build status belongs in `status.md` (the engineer ticks per the roadmap) |
| X3 | Decision 9: second loupe on another display | Not a capability | Defer to `second-loupe-display` (already on the roadmap) |
| X4 | §11 Persistence: mapping sizes stored by the slider build; §11 Strings: "Removed with the slider" | Tied to the dropped `film-strip-size-slider` | Keep the mapping, which is invisible and protects stored values. The strings note is history only |
| X5 | §6 Edit: "Cut, Copy, Paste, Select All" listed as if they act in the grid | No capability copies photos to the pasteboard | Keep Cut, Copy and Paste as the system's text items only, dimmed in the grid and loupe. A photo pasteboard is new scope (RI-7, `photo-pasteboard`); X5 stands until it ships |
| X6 | §6 Filter: the model's `exactly` rating rule "gets no control" | No capability | Keep it in the model with no UI |
| X7 | §6 Edit ▸ Find ▸ Clear Filter | Duplicates View ▸ Filter ▸ Clear Filter | Remove (I18; owner ruling D1, 2026-11-04) |
| X8 | Decision 12 (English only, 30% room); decision 14 (AppKit-backed inspector controls) | Not a capability, but a constraint the tooling (Inv ▸ Debug script) and the macOS 15 click bug (CLAUDE.md) depend on | Keep |

## 3. Inconsistencies between surfaces

Ordered by impact. "Code" means what `develop` does today.

| # | Surfaces | Conflict | Ruling | Change |
|---|---|---|---|---|
| I1 | File ▸ Export…, toolbar Export, context Export… | Enabled when the **source** has items (`itemCount > 0`). The toolbar help says "Export the selected photos", but the sheet can open on 0 photos, or on videos only (all skipped) | Enabled (context: shown) only when the targets include a photo and no export runs. Pairs count once, as in the sheet | E12 |
| I2 | File ▸ Add Folder Without Copying…, toolbar Import ▸ menu, empty-library button vs folder drops | The three commands are disabled during an in-place import, but drops at the same moment are queued (Inv ▸ Import ▸ "Folder drops") | Always enabled. The chosen folder joins the same queue as a drop and shows in Activity as "Folder N of M" (UIR §1) | E13 |
| I3 | Export results vs UIR §1 and §8 | Code (and UG) shows an alert after a background export when files failed or were skipped by choice. UIR §1 sends warnings to Activity and keeps alerts for "when action is needed". The Import window uses window-modal alerts (UIR §8) | P4. The Import window keeps its alerts while it is open. Export, which reports after its sheet has closed, reports in Activity only: failures as a **warning** whose detail lists up to 10 files with reasons ("And N more."), and files skipped by the person's choice as **information**. No alert. UG is updated in the same change (E27). Owner ruling D2, 2026-11-04 | E14 |
| I4 | ⌘. Stop | The Import window has File ▸ Stop Import ⌘.. The library window's Activity Stop (export, folder adds, a card copy whose window is closed) has no menu item or key. In the library app `ImportCommands`' disabled Stop Import ⌘. would also take the key first | One File item, ⌘., per P3. With the Import window key: "Stop Import", as now. With the library window key: "Stop Export", "Stop Adding Folders" or "Stop Import", naming the newest running job in Activity, and dimmed when nothing runs. Other jobs keep their Stop in the Activity popover | E11 |
| I5 | Edit ▸ Deselect All ⇧⌘A | The Import window has it; the library grid doesn't. The HIG lists ⇧⌘A as the standard "Deselect all" | One item per P3. In the grid it collapses a multiple selection to the focused photo (commands then act on that photo, as after a plain click). Enabled in the grid while two or more are selected, dimmed in the loupe | E10 |
| I6 | Video loupe vs photo loupe; Space | No context menu in the video loupe (N9). Space plays and pauses in the video loupe (code, UG) while UIR §2 lists Space as a way out of the loupe | Space is Play / Pause in the video loupe, following the media convention. Return, Esc and ⌘↩ leave it. Recorded here and in the map; plus N9 | E8, E9 |
| I7 | Photo ▸ Suggest Keywords ⇧⌘K, context menu, palette item | They show the inspector but not the Info tab, and the suggestion chips appear only when Keywords is expanded. From the Adjust tab nothing visible happens | Also switch to Info and expand Keywords. The Activity row appears as UIR §1 says | E15 |
| I8 | Info tab vs Import metadata preset editor, Changed on Disk, smart album rule field | One field (`caption`) is called **Description** in the Info tab and **Caption** in the other three | **Description** everywhere (the IPTC Core name, and the name used where people edit it). Data and keys don't change | E16 |
| I9 | Info tab Metadata and Contact vs metadata preset editor vs Changed on Disk | The same fields have different names and cases: "Alt Text" / "Usage Terms" / "Postal Code" / "E-Mail" / "State/Province" / "Country/Region" in the Info tab, but "Usage terms" / "Postal code" / "Email" / "Region" / "Country" in the preset editor | One shared label set (P5, row labels sentence-style): Title, Description, Alt text, Extended description, Copyright, Usage terms, Creator, Job title, Address, City, State/Province, Postal code, Country/Region, Phone, Email, Website. Changed on Disk rows use the same set, plus "Rating", "Flag", "Color label", "Keywords", "Contact". Menu and pop-up items, such as the smart album rule fields, stay title-style | E17 |
| I10 | Settings vs UIR §8 Form conventions | Code uses `Toggle` in a grouped `Form`, which macOS draws as **switches**. UIR §8 says check boxes, no switches, and lists Settings under that rule | Check boxes (`.toggleStyle(.checkbox)`) | E3 |
| I11 | Deleting presets | Deleting an export preset asks first (UIR §8). Deleting an adjustment preset (Manage Presets ▸ row ⋯ ▸ Delete) and a metadata preset (editor ▸ Delete Preset) happens at once, though neither can be undone. Deleting a collection asks | Every deletion that can't be undone asks once, in one form: "Delete the preset “‹name›”?", a detail line, Delete (destructive) and Cancel. Their menu and button titles gain the ellipsis: "Delete…", "Delete Preset…" | E18 |
| I12 | Reset All Adjustments: Adjust menu, context menu vs Adjust ⋯ | ⋯ dims it when the photo has no adjustments; the menu and context menu don't | In the loupe the menu item is dimmed (and left out of the context menu) when the photo's adjustments are at their defaults. In the grid it is enabled when any target has a non-default stack, if the grid's items can tell that without a query; otherwise it stays as now | E19 |
| I13 | Save Adjustments as Preset…: Adjust menu, ⋯, Presets ▸ Save… | Enablement differs: the menu checks only for a focused item (videos too), Save… checks the same, and ⋯ is always on | All three are enabled only when the focused item is a photo whose adjustments can be read (grid: focused photo; loupe: editor ready) | E20 |
| I14 | Photo ▸ RAW+JPEG Pair ▸ vs context menu | The menu is enabled for any focused item while pairs are grouped; the context menu shows it only for pairs. Neither shows which file is on screen | Enabled only when the targets include a pair. Its two items carry a checkmark for the file shown (mixed state for a mixed selection) | E21 |
| I15 | Toolbar palette Crop and Original vs inspector toggles | Both toolbar buttons toggle a mode but show no on state. The inspector's Crop and Original are push-on/push-off (UIR §4) | The toolbar items show their on state the same way (selected bezel). Labels stay "Crop" and "Original" | E22 |
| I16 | Import window Selection pull-down vs Edit menu | Select All and Deselect All in the pull-down stay enabled while copying; the menu items are disabled | Same enablement, read from `ImportMenuState` | E23 |
| I17 | Add Folder Without Copying… open panel | The panel's prompt says "Import", which is the third meaning of "Import" UIR F11 removed | Prompt "Add Folder". The message stays | E24 |
| I18 | Edit ▸ Find ▸ Clear Filter vs View ▸ Filter ▸ Clear Filter | The same command is in two menus | Keep it in View ▸ Filter (also the toolbar Filter menu and "No Photos Match"). Remove it from Find. Find holds find commands, and clearing rating or flag rules isn't one (owner ruling D1, 2026-11-04) | E25 |
| I19 | View ▸ Info ⌥⌘1 / Adjust ⌥⌘2 | No state is shown | A checkmark on the current tab while the inspector is shown | E26 |
| I20 | UIR §5 "Export…" vs toolbar label "Export" | The plan text has an ellipsis; code doesn't | Code is right: toolbar labels name the item (customization palette, label under the icon) and carry no ellipsis (judgment; the HIG is silent). The menu and context items keep "Export…" | none |
| I21 | Adjust ▸ Crop (bare `C`) vs toolbar Crop | The menu item needs the grid or loupe to have the keyboard; the toolbar button doesn't | Keep. This is the 2026-11-02 bare-key rule (UIR §6), and a click always has a target | none |
| I22 | Grid context menu vs Adjust ▸ Crop | Crop works from the grid through the menu, key and toolbar, but isn't in the grid's context menu | Keep. The context menu acts on the clicked selection; Crop acts on one photo and opens the loupe | none |
| I23 | "Show Loupe" (menu) vs "Open in Loupe" (context, inspector, VoiceOver) | Two names | Keep. The menu item is a view toggle with a state title (HIG: show/hide titles). The others name an action on a photo | none |
| I24 | ⌘[ / ⌘] Rotate vs bare `[` `]` rating; HIG standard ⌘[ / ⌘] is left/right align | Possibly "adding a modifier… for an unrelated command" | Keep. The app has no text alignment (the HIG allows reuse when the standard meaning doesn't apply), and both pairs step a photo attribute down or up. Shipped and documented | none |
| I25 | Export preset pop-up vs Import metadata preset pop-up | Different items (Save as Preset…, Update, Delete… vs New Preset…, Edit…) | Keep (UIR §8 Presets convention). An export preset captures the sheet; a metadata preset is edited in its own sheet. Confirmation per I11 | none |
| I26 | Inv ▸ Metadata ▸ Keywords "merge" vs UI | No Merge command | Keep. Renaming onto an existing name merges, the rename sheet says so, and it can be undone | none |
| I27 | Inv ▸ Import ▸ "Auto-open … Settings toggle" vs standalone importer | The importer has no Settings and always follows cards | Keep. The importer is the import window | none |
| I28 | Inv ▸ UI shell ▸ "Menu bar: File, Edit, View, Photo, Adjust, Window" vs app | Help is missing from the inventory, and the app shows an empty Help item | Remove the dead item; keep the Help menu and its search (prd.md R1, R2; N13) | E28 |
| I29 | macOS 15 vs 26 | None found beyond the intended differences in UIR "macOS 15 fallback" (slider fill, toolbar spacers, glass, scroll edge) | Keep. On-screen check under `ui-redesign-onscreen-check` | none |
| I30 | UG vs app | UG says the Import window has an "Include videos switch" (it is Show Videos in the Selection menu and View menu). Its key table leaves the loupe column blank for ⌘= / ⌘− (they zoom). It says export problems raise an alert (changes with I3) | The engineer updates the UG in the same change as the behavior; the designer reviews its terms (RI-5, owner ruling) | E27 |
| I31 | UIR §11 checklist vs code | 7 build items unticked that the code appears to implement (inventory) | No design change. Status goes in `status.md`; the engineer ticks per the roadmap | none |
| I32 | Review mode vs loupe | Consistent: film strip hidden, caption kept, toolbar on hover, ⌥⌘I brings the inspector back. Play / Pause in review is covered by N9 | Keep | none |

## 4. Command map (current, with rulings applied)

Legend: **bare** = a bare-key item, enabled only while the grid, loupe or video
loupe has the keyboard in the key library window with no sheet (UIR §6). All
library items are dimmed while another window is key. **new** = added by this
document. Toolbar "palette" = off by default and added through Customize
Toolbar.

### Library app

| Command | Menu | Key | Toolbar | Context menu | Other surfaces | Enabled when |
|---|---|---|---|---|---|---|
| Settings… | App | ⌘, | — | — | — | always |
| Quit | App | ⌘Q | — | — | Quit guard (UIR §8) | always |
| Import from Card or Folder… | File | ⌘I | Import (click) | — | empty library primary button ("Import from ‹card›…" when a card is mounted); Projects empty link; card insert (Settings) | library key |
| Add Folder Without Copying… | File | ⇧⌘I | Import ▸ menu | — | empty library button; folder drop on the browser or Projects; panel prompt "Add Folder" (I17) | library key; **always, queues** (I2) |
| New Album… | File | ⌘N | palette New Album | Project: New Album in Project… | Albums empty link | library key |
| New Smart Album… | File | ⌥⌘N | — | Project: New Smart Album in Project… | — | library key |
| Edit Smart Album… | File | — | — | Smart album: Edit… | empty smart album state (N3) | a smart album selected |
| Rename “‹name›”… | File | — | — | Album, keyword: Rename… | — | album or keyword selected |
| Delete “‹name›”… | File | — | — | Album, smart album, keyword: Delete… | confirmation | sidebar item selected |
| Export… | File | ⇧⌘E | Export | grid, loupe: Export… | — | targets include a photo, no export running (I1) |
| Check for Changes on Disk | File | — | — | — | also runs at launch and when a volume mounts | not already checking |
| Stop ‹job› **new** | File | ⌘. | — | — | Activity popover Stop | a job runs (I4) |
| Close | File | ⌘W | — | — | — | system |
| Undo / Redo | Edit | ⌘Z / ⇧⌘Z | — | — | — | undo manager |
| Cut / Copy / Paste | Edit | ⌘X / ⌘C / ⌘V | — | — | text fields only (X5) | system |
| Select All | Edit | ⌘A | — | — | grid | system / grid |
| Deselect All **new** | Edit | ⇧⌘A | — | — | — | grid with 2+ selected (I5) |
| Find… | Edit ▸ Find | ⌘F | Search field (grid) | — | in the loupe returns to the grid. Find holds only Find… (Clear Filter removed, D1) | library key |
| Show / Hide Toolbar; Customize Toolbar…; Show / Hide Sidebar | View | ⌥⌘T; —; ⌃⌘S | sidebar toggle | — | — | system |
| Show Grid / Show Loupe | View | ⌘↩ | Grid \| Loupe | grid: Open in Loupe | Return, Space, double-click; inspector "Open in Loupe"; VoiceOver action | source has items |
| Enter / Exit Review | View | `F` (bare) | palette Review | — | Esc exits | focused item |
| Zoom to 100% / Zoom to Fit | View | `Z` (bare) | Fit \| 100% (loupe) | loupe | click, pinch, ⌥-scroll | loupe shows a photo |
| Larger / Smaller Thumbnails; Zoom In / Zoom Out | View | ⌘= / ⌘− | size slider (grid) | loupe: Zoom In / Zoom Out | — | grid; loupe within the zoom steps |
| Show Original / Show Adjustments | View | `\` (bare) | palette Original (shows on state, I15) | loupe | inspector Original toggle | editable loupe photo, not cropping |
| Show / Hide Film Strip | View | ⌥⌘B | — | — | caption toggle | loupe, not reviewing |
| Play / Pause **new** | View | Space (bare) | — | video loupe | AVKit controls; VoiceOver action | video loupe has the keyboard |
| Show / Hide File Names | View | — | — | — | — | library key |
| Group RAW+JPEG Pairs (checkmark) | View | — | — | — | — | library key |
| Show / Hide HDR Highlights | View | — | — | — | — | library key |
| Filter ▸ Rating, Flag; Clear Filter | View | — | Filter and Sort | — | "No Photos Match": Clear Filter. View ▸ Filter is Clear Filter's only menu-bar home (D1) | rules: grid; Clear: while filtered |
| Sort By ▸ | View | — | Filter and Sort | — | — | grid |
| Sidebar Sections ▸ | View | — | — | section header: Hide Section; Collapse / Expand | — | library key |
| Show / Hide Inspector | View | ⌥⌘I | inspector button | — | (Import window: Show / Hide Options, same item) | library key |
| Info / Adjust (checkmark **new**) | View | ⌥⌘1 / ⌥⌘2 | — | — | inspector segmented control | library key |
| Enter Full Screen | View | ⌃⌘F | — | — | — | system |
| Rating ▸ No Rating, ★…★★★★★, Raise, Lower | Photo | 0–5, `]`, `[` (bare) | — | grid, loupe, video loupe (new) | VoiceOver Raise / Lower | targets |
| Flag ▸ Pick, Reject, Clear Flag | Photo | P, X, U (bare) | — | grid, loupe, video loupe | VoiceOver actions | targets |
| Color Label ▸ No Label…Gray | Photo | ⌥0–⌥7 (bare) | — | grid, loupe, video loupe | — | targets |
| Advance After Rating (checkmark) | Photo | — | — | — | — | library key |
| Add Keywords… | Photo | ⌘K | palette Add Keywords | grid, loupe, video loupe | inspector keyword field; Keywords empty link; drop on a keyword row (N4) | targets |
| Suggest Keywords | Photo | ⇧⌘K | palette Suggest Keywords | grid, loupe, video loupe | inspector "Suggest Keywords for N Photos"; shows Info ▸ Keywords (I7) | targets |
| Add to Album ▸ | Photo | — | — | grid, loupe, video loupe (when albums exist) | drop on an album row (N4) | targets and an album exists |
| Remove from Album | Photo | ⌫ (bare) | — | grid, loupe, video loupe (in an album) | — | targets in the album |
| RAW+JPEG Pair ▸ Show the RAW File / Show the JPEG or HEIC File (checkmarks) | Photo | — | — | grid, loupe (pairs) | — | targets include a pair (I14) |
| Copy Adjustments | Adjust | ⇧⌘C | palette | grid, loupe | Adjust ⋯ | focused photo |
| Paste Adjustments | Adjust | ⇧⌘V | palette | grid, loupe | Adjust ⋯ | copied, and targets include a photo |
| Apply Preset ▸ | Adjust | — | — | grid, loupe | Presets tiles (click; tile context Apply) | presets exist, and targets include a photo |
| Auto Exposure | Adjust | — | palette | grid, loupe | Tone group "Auto" | grid: photo targets; loupe: editable, not cropping |
| Reset All Adjustments | Adjust | — | — | grid, loupe | Adjust ⋯ | as Auto Exposure, and not at defaults (I12) |
| Crop / Finish Cropping | Adjust | `C` (bare) | palette Crop (on state) | loupe | inspector Crop toggle and Done; Return finishes, Esc cancels | grid: focused photo; loupe: editable |
| Reset Crop **new** | Adjust | — | — | — | Crop & Straighten heading reset | loupe photo with a crop (N6) |
| Rotate Left / Rotate Right | Adjust | ⌘[ / ⌘] | palette | grid, loupe | Crop heading arrows | grid: photo targets; loupe: editable |
| New Mask ▸ shapes | Adjust | — | — | — | Masks heading shape buttons | editable loupe photo, not cropping, under 32 masks (N8) |
| Show / Hide Mask Overlay **new** | Adjust | — | — | — | Masks heading eye | a mask selected (N7) |
| Save Adjustments as Preset… | Adjust | — | — | — | Adjust ⋯; Presets "Save…" | focused photo with readable edits (I13) |
| Import Presets… | Adjust | — | — | — | Presets "Import…"; Preset manager Import…; Finder double-click | library key |
| Manage Presets… | Adjust | — | — | preset tile: Manage Presets… | Presets "Manage…" | library key |
| Import Look-Up Tables… **new** | Adjust | — | — | — | LUT browser Import… page | library key |
| Browse Look-Up Tables… | Adjust | — | — | — | Effects "Browse…" | library key |
| Minimize, Zoom; Library; Import | Window | ⌘M | — | — | — | system |
| Help ▸ Search (system field that finds menu commands) | Help | ⌘? | — | — | The dead "‹app› Help" item is removed in both apps (prd.md R1, R2; E28) | always |

Inspector and sidebar local menus (unchanged from UIR §7): inspector section
header (Turn Off / On, Reset, Collapse All, Expand All); slider row (Reset
"…"); mask row ⋯ and context (Rename, Move Up, Move Down, Delete).
Commands inside sheets (Export, look-up table browser pages, preset
manager) stay in the sheets (P1).

### Import window (library app and standalone importer, `ImportCommands`)

| Command | Menu | Key | Toolbar | Context (cell) | Other | Enabled when |
|---|---|---|---|---|---|---|
| Choose Folder… | File | ⌘O | Source pop-up ▸ Choose Folder… | — | empty states | not importing |
| Rescan | File | ⌘R | Rescan | — | read-error state | has a source, not importing |
| Import Selected Photos | File | Return | Import N Photos (prominent) | — | — | source, selection, not importing |
| Stop Import | File | ⌘. (shared item, I4) | Stop | — | quit and close guards | importing |
| Select All | Edit | ⌘A | Selection ▸ Select All | Select All | — | not importing (I16) |
| Deselect All | Edit | ⇧⌘A (shared item, I5) | Selection ▸ Deselect All | Deselect All | — | selection, not importing (I16) |
| Select / Deselect (one shot) | — | Space | — | Select / Deselect | click, ⇧-click | — |
| Show Videos (checkmark) | View | — | Selection ▸ | — | — | not importing |
| Show Photos Already in Library (checkmark; library app only) | View | — | Selection ▸ | — | "Show Them" in the all-imported state | library app |
| Show / Hide Options | View | ⌥⌘I (shared item) | Show / Hide Options | — | — | Import window key |
| Metadata preset New / Edit / Delete… | — | — | — | — | Options ▸ Metadata pop-up and editor; delete asks (I11) | — |

## 5. Requirements issues (for the product manager)

The product manager ruled on 2026-11-04 in [`prd.md`](prd.md) on RI-1 to
RI-4, RI-6 and RI-7. The owner answered RI-5 the same day. All seven are
answered.

| RI | Status | Ruling |
|---|---|---|
| RI-1 | Answered | prd.md R1 and R2: remove the dead item and keep Help ▸ Search (N13, E28). Help content is roadmap `in-app-help` (Later) |
| RI-2 | Answered | In scope, files are never touched, and each needs its own PRD: roadmap `remove-from-library` and `rename-project` (Next). §1b is corrected |
| RI-3 | Answered | Wanted; roadmap `show-in-finder` (Next). Its title must not clash with Show Original |
| RI-4 | Answered | New scope, passive if built, never an alert; roadmap `metadata-reader-status` (Later) |
| RI-5 | Answered (owner, 2026-11-04: "Engineer, designer reviews") | prd.md Q1. The engineer updates `docs/USER_GUIDE.md` in the same change as the behavior it describes, and the designer checks its terms at review. Recorded in `docs/WORKFLOW.md`'s Ownership table. E27 no longer waits |
| RI-6 | Answered | The edit-history PRD states the need only. ⌘Y and the left sidebar from issue #26 are proposals for design; ⇧⌘Z stays redo. This is the roadmap `edit-history` row (Next) and its intake notes |
| RI-7 | Answered | New scope; roadmap `photo-pasteboard` (Later). X5 stands until it ships |

The issues as raised:

- **RI-1 Help menu.** The app shows SwiftUI's default Help ▸ "‹app› Help"
  item, which only says help isn't available. The inventory lists no help
  capability, though `docs/USER_GUIDE.md` exists. Decide whether to ship help
  or remove the item. If help ships, decide its form (a bundled Help Book,
  the guide shown in the app, or a web page; a URL is a brand value under the
  Naming rules) and whether it also points to `photocli`. The design
  placement is ready either way: Help ▸ ‹app› Help (⌘?).
- **RI-2 Renaming projects; removing photos and projects from the library.**
  No capability renames a project or removes photos or projects from the
  catalog (Inv ▸ Catalog ▸ Projects). File ▸ Rename and Delete exist for
  albums and keywords but are dimmed for projects, and the project context
  menu has only New Album / New Smart Album. Mac users expect both. Is
  removing from the catalog (never the files) in scope? If so, what happens
  to edits, albums, pairs and sidecars? This needs a PRD before design.
- **RI-3 Show in Finder.** No capability reveals a photo's original, or a
  project's folder, in the Finder, a standard Mac file-management
  integration. Is it wanted? If so, it can't be titled "Show Original",
  which is taken by before/after. Design would place it in File, with the
  key decided then.
- **RI-4 Which metadata reader is in use is invisible.** When ExifTool isn't
  installed, metadata falls back to ImageIO without saying so (Inv ▸ Import
  ▸ Metadata reading). That changes what the Info tab, smart albums and
  sidecar comparisons see. Should the app tell people (for example, a line
  in Settings)? There is no design until this is decided.
- **RI-5 `docs/USER_GUIDE.md` has no owner** in `docs/WORKFLOW.md`, and it is
  stale in three places (I30), with E14 adding a fourth. Who updates it, and
  in which change?
- **RI-6 edit-history intake (roadmap Next).** Issue #26 asks for ⌘Y redo and
  a left-sidebar placement. Both conflict with this design: ⇧⌘Z is the HIG
  standard redo, and the sidebar holds sources (UIR §3). The PRD should state
  the need and leave placement to design.
- **RI-7 A photo pasteboard.** No capability copies photos (files or
  rendered images) for pasting into other apps, so Edit ▸ Copy is dimmed in
  the grid (X5). Mac users may expect ⌘C on a photo to work. Is it in scope,
  and does it overlap `export-extras` or `publishing-engine`?

## 6. Implementation notes for the engineer

No code here: what changes and where it shows in the UI. Strings are added
by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings` (§7), and
`LocalizationTests` must pass. Glass panes don't snapshot (CLAUDE.md), so
checks on the toolbar, sidebar or inspector use `print`, `buttons`,
`menuitems` and `menupress`, or are manual on-screen checks under
`ui-redesign-onscreen-check`.

| # | Priority | Change | Acceptance |
|---|---|---|---|
| E1 | High | Empty-source states in the browser (N3): "No Photos Yet" only when the library is empty; "No Photos Match" while filtered; otherwise "No Photos in “‹source›”", with the album description, or the smart album description and an Edit Smart Album… button. Write the choice as a pure rule (inputs: library count, source kind, filtered) | Unit test of the rule for each kind. Debug script: select an empty album and an empty smart album, then `snapshot` (content area) shows the right title and no Import buttons |
| E2 | Medium | Adjust tab states (N1) as `ContentUnavailableView`s | Debug script on a video, an offline master and an unreadable stack, then `print` the inspector. Manual on-screen check |
| E3 | Medium | Settings: both options become check boxes (I10). No other change | Manual: open Settings (⌘,) and see two check boxes, no switches |
| E4 | Medium | Adjust ▸ Import Look-Up Tables… opens the LUT browser sheet on its Import page (N5) | `menupress "Import Look-Up Tables…"`, then the sheet shows the Import page; Back goes to Tables; Activity row title unchanged |
| E5 | Medium | Adjust ▸ Reset Crop (N6), the same action as the heading's reset | `menuitems "Reset Crop"`: dimmed in the grid and on an uncropped photo, enabled on a cropped one. `menupress` then ⌘Z restores |
| E6 | Low | Adjust ▸ Show / Hide Mask Overlay (N7), the same state as the eye button | `menuitems "Mask Overlay"`: dimmed with no mask selected; the title flips after `menupress` |
| E7 | Medium | Dim New Mask (menu and shape buttons) at the mask limit and "Add to Mask:" at the component limit, with tooltips (N8). Put the "can add" checks beside `MaskLimits` in PhotoCore | Unit tests at 31/32 masks and 15/16 components. `menuitems "New Mask"` on a 32-mask photo is dimmed |
| E8 | Medium | View ▸ Play / Pause with Space as a bare-key item, title by state, enabled only while the video loupe has the keyboard (N9, I6) | Launch with `open -W -n` (the local monitor needs an active app). `menuitems Play` on a video is enabled and on a photo dimmed; Space still opens the loupe from the grid and plays in the video loupe |
| E9 | Medium | Video loupe context menu (N9): the photo items, then Play / Pause and Show Grid. It opens on right-click or Control-click over the picture, not over AVKit's controls (same hit rule as the double-click) | Debug script's context-menu probe on the video loupe lists the items. Manual right-click |
| E10 | Medium | Edit ▸ Deselect All ⇧⌘A as one item shared with `ImportCommands` (P3): grid collapses the selection to the focused photo; Import as now (I5) | `menuitems "Deselect All"` with each window key; `menukey` ⇧⌘A in both; ⇧⌘A in a text field still works for text |
| E11 | Medium | File ▸ Stop ‹job› ⌘. as one item shared with `ImportCommands`' Stop Import (P3), titled for the newest running job in the library window (I4) | During a debug-script export, `menuitems Stop` shows "Stop Export" enabled and `menupress` stops it; with the Import window key it is "Stop Import" |
| E12 | High | Export enablement: menu, toolbar and context use "targets include a photo and no export running" (I1) | `menuitems Export…` dimmed with only videos selected; the context menu has no Export… |
| E13 | High | Add Folder Without Copying… stays enabled during in-place imports and enqueues through the same queue as drops, in the menu, toolbar menu and empty state (I2) | Debug script: add a folder, then add another while the first runs; Activity shows "Folder 2 of 2"; `menuitems` enabled throughout |
| E14 | High | Export results go to Activity only: failures as a warning listing up to 10 files and "And N more.", skips by choice as information; remove the export report alert (I3; owner ruling D2, 2026-11-04) | Debug-script export including an offline photo: no alert; `print activity` shows a warning row with the file. Export with Skip chosen: information row |
| E15 | Medium | Suggest Keywords (menu, context, palette) also selects the Info tab and expands Keywords (I7) | From the Adjust tab, `menupress "Suggest Keywords"`, then `print` shows the Info tab with Keywords expanded |
| E16 | Medium | "Caption" becomes "Description" in the metadata preset editor, Changed on Disk and the smart album rule field (I8) | `LocalizationTests`; grep finds no UI use of "Caption"; manual check of the preset editor |
| E17 | Medium | One shared field-label set in PhotoUI, used by the Info tab, Changed on Disk and the metadata preset editor, with sentence-style row labels (I9) | A unit test that each `DescriptiveField` and preset field maps to one label; `LocalizationTests` |
| E18 | Medium | Delete confirmations for adjustment presets (manager ⋯ "Delete…") and metadata presets (editor "Delete Preset…") (I11) | Manual: each asks; Cancel keeps the preset; Delete removes it |
| E19 | Low | Reset All Adjustments enablement (I12) | `menuitems "Reset All Adjustments"` dimmed on an unedited photo in the loupe; context menu omits it |
| E20 | Low | Save Adjustments as Preset… enablement in the menu, ⋯ and Save… (I13) | `menuitems` dimmed with a video focused |
| E21 | Low | RAW+JPEG Pair ▸ enabled only for pairs, with checkmarks for the shown file (I14) | `menuitems "Show the RAW File"`: dimmed on a single file, checked on a pair showing its RAW |
| E22 | Low | Toolbar Crop and Original show their on state (I15) | `buttons` reports the state. Manual on-screen check (glass) |
| E23 | Low | Import Selection pull-down Select All / Deselect All use the menu's enablement (I16) | Import debug commands during a copy: both dimmed |
| E24 | Low | Add Folder open panel prompt "Add Folder" (I17) | Manual: the panel's button reads Add Folder |
| E25 | Low | Remove Edit ▸ Find ▸ Clear Filter (I18; owner ruling D1, 2026-11-04). View ▸ Filter ▸ Clear Filter, the toolbar Filter menu and "No Photos Match" keep it | `menuitems "Clear Filter"` lists one menu-bar item |
| E26 | Low | View ▸ Info / Adjust show a checkmark on the current tab while the inspector is shown (I19) | `menuitems Info` shows the state |
| E27 | Low | Update `docs/USER_GUIDE.md` (owner ruling on RI-5: the engineer updates, the designer reviews). Fix each stale spot in the same change as the behavior it describes. With E14: export problems reported in Activity, not an alert. With E16: the Export metadata paragraph's "caption" becomes Description. Independent of other changes: the Import window's "Include videos switch" becomes Show Videos (Selection menu and View menu), and the key table's loupe column gets ⌘= / ⌘− zoom (I30). Every other E change that alters a described behavior updates the guide in the same change | Designer review of each change checks the guide's terms against this document (P5; §4 command map titles) |
| E28 | Medium | Help menu (N13; prd.md R1, R2): remove SwiftUI's default "‹app› Help" item in the library app and the standalone importer, keeping the Help menu and its search field. **Engineer question (prd.md Q2):** if removing the item also removes the menu or its search field, R1 wins: ship without the dead item and report the loss in `status.md` and back to the product manager. Do not keep the dead item | AC1: `menuitems Help` in the library app lists no "‹app› Help" item, and a manual check finds none in the importer. AC2, manual in each app: open Help and type "Export" (library app) or "Rescan" (importer); the matching File item is offered and highlighted |

## 7. Strings (catalog keys)

New keys, added by hand. Keys that already exist and are reused are marked.

- Menus: "Import Look-Up Tables…"; "Show Mask Overlay"; "Hide Mask
  Overlay"; "Stop Export"; "Stop Adding Folders". Reused: "Reset Crop",
  "Play", "Pause", "Deselect All", "Stop Import".
- Empty states: "No Photos in “%@”"; "Drag photos onto the album in the
  sidebar, or choose Photo ▸ Add to Album."; "No photo meets this smart
  album's rules."; "No Adjustments for Videos"; "Original Offline"; "Connect
  its volume to adjust this photo."; "Can't Edit This Photo". Reused: "Edit
  Smart Album…".
- Mask limits (plural): "A photo can have up to %lld masks."; "A mask can
  combine up to %lld shapes."
- Preset deletion: "Delete the preset “%@”?"; "Delete Preset…"; "Photos it
  was applied to keep their adjustments."; "Copies already imported keep
  their metadata." Reused: "Delete…", "Delete", "Cancel".
- Field labels: "Alt text"; "Extended description"; "Job title"; "Postal
  code"; "Email"; "Color label". Reused: "Description", "Usage terms",
  "State/Province", "Country/Region".
- Open panel prompt: reuse "Add Folder", with a comment for the prompt.
- Remove keys left without a use after E16 and E17 ("Caption", "Alt Text",
  "Extended Description", "Usage Terms", "Postal Code", "E-Mail", "Job
  Title", "Region", "Country"), if `LocalizationTests` allows.

## 8. Owner rulings

Both were accepted by the owner on 2026-11-04 ("Accept both"). Nothing in
this document waits on the owner.

- **D1 (ruled 2026-11-04).** Edit ▸ Find ▸ Clear Filter is removed. This
  overrides UIR §6. View ▸ Filter keeps the command, as do the toolbar
  Filter menu and "No Photos Match". See X7, I18, E25.
- **D2 (ruled 2026-11-04).** Export problems are reported in Activity, not
  in an alert. Failures are a warning; files skipped by the person's choice
  are information. This changes shipped behavior that the UG describes
  (updated in the same change as E14, per E27). See I3, E14.
