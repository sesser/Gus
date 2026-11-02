# UI redesign: window, navigation, menus and inspector

Status: **proposed** (2026-11-02). The decisions below were approved.
Nothing is implemented yet.

The library window grew one feature at a time, and it shows: the sidebar
and the inspector are built from two different hand-made heading styles,
the bottom of the window is three or four unrelated strips, many commands
exist only as bare keys or inspector buttons, and the grid is invisible to
VoiceOver. This file records an audit against Apple's Human Interface
Guidelines (HIG) and the redesign that answers it. The architecture,
naming and clean-room rules in `CLAUDE.md` still apply: the data model,
existing shortcuts and existing features do not change.

Screenshots of the starting point: `docs/screenshots/`.

## Decisions

1. **macOS 15 stays the minimum.** The project is open source and not
   everyone runs the latest macOS. The design targets macOS 26 and builds
   with the macOS 26 SDK; 26-only APIs go behind `#available(macOS 26, *)`
   with the fallbacks listed under "macOS 15 fallback".
2. **Liquid Glass only through system components.** Toolbar, sidebar,
   inspector, menus and popovers pick it up from the SDK. No custom glass.
   In the loupe the photo never sits under glass; system panes may sit
   beside the neutral surround, at least 24 pt from the photo's edge.
   Review mode hides both panes.
3. **Existing shortcuts keep their meaning;** new ones are allowed. The
   culling keys are shown in menus, switched off while text is being edited.
4. **The right-hand pane is an inspector,** not a second sidebar: visually
   distinct, built from the same parts. Info and Adjust stay two tabs.
5. **Sliders stay in the loupe.** Presets, paste adjustments and Auto become
   batch commands on the grid selection.
6. **Filters and search belong to each sidebar source,** live in the
   toolbar, persist across relaunches, and are not shown in the loupe
   (only a Filtered badge).
7. **No permanent status bar.** Progress lives in a toolbar Activity item.
8. **Dark appearance on the library window only.** Its sheets (Export, the
   look-up table browser, Presets) inherit it; that is accepted.
   Import and Settings follow the system.
9. **One library window** plus a full-screen review mode. A second loupe on
   another display is deferred.
10. **Sizing:** a 13" laptop is the minimum, a large external display the
    usual case. VoiceOver: every control has a label and value, and culling
    works with it.
11. **Toolbar customization: yes.** Sidebar sections can be collapsed and
    hidden but not reordered.
12. **English only;** side labels leave about 30% room for longer text.
13. **New keys approved:** `F` review, `C` crop, ⌘[ / ⌘] rotate, ⌥⌘1 / ⌥⌘2
    Info and Adjust, ⌘F find, ⌃⌘S sidebar. ⌘= / ⌘− zoom the loupe while it
    is open (they resize thumbnails in the grid, as now).
14. **Inspector controls stay AppKit-backed** (`AppKitButton`, `SliderRow`…)
    so the debug script's `click` keeps driving them, but become real system
    controls (disclosure buttons, check boxes, bezeled fields).
15. **Renames:** "Import Folder…" → "Add Folder Without Copying…"; the
    "Tone" section → "Tone Curve"; White Balance's "Preset" pop-up → "Mode";
    the "Develop" section → "Light", and its "Light" group → "Tone" (free
    once the old Tone section is Tone Curve). Only UI strings change: edit
    operation identifiers, keypaths and `photocli` command names stay.

## Audit (most severe first)

Severity in brackets. File references are as of `f828cb9`.

1. **F1 Bottom of the window [High].** `FilterBar` (30 pt) and `StatusBar`
   (28 pt) cover only the content column (`MainView.swift:103–109`); the
   loupe adds `LoupeInfoBar` (48 pt, opaque) above them; the inspector ends
   with its own Copy/Paste bar at another height. About 107 pt of chrome on
   three backgrounds, no edge lines up, the file name shows twice, and the
   filter's stars sit under the photo's rating stars.
2. **F2 Sidebar and inspector grammar [High].** Sidebar headings are
   disabled rows with a trailing chevron; inspector headings have a leading
   chevron, a check-box slot and a reset. Disclosure on opposite sides,
   counts in two columns, three neutral backgrounds side by side.
3. **F4 Grid accessibility [High].** `PhotoCell` draws with layers and sets
   no accessibility label, role or value.
4. **F5 Commands missing from menus [High].** Crop, rotate, Show Original,
   Zoom, Auto, Reset All, masks and the look-up table browser have no menu
   item; rating, flag and label items show no keys; no inspector toolbar
   button; no `SidebarCommands`.
5. **F3 Heading styles [Medium-High].** At least nine heading or caption
   treatments across the inspector and the secondary windows.
6. **F6 Slider rows [Medium].** Label above a full-width track: 46 pt per
   slider. Bipolar sliders fill from the minimum, so an untouched one looks
   half applied. Value fields have no bezel or focus ring. Pop-ups and
   sliders use two alignment lines. Turned-off groups fade to 45%.
7. **F7 Round check boxes [Medium].** `circle` / `checkmark.circle.fill`
   read as radio buttons; VoiceOver gets no state.
8. **F8 Custom controls [Medium].** Hand-made disclosure, chips and value
   fields lose accessibility roles; many hit areas are 14–18 pt.
9. **F9 Type scale [Medium].** Info values (`.title2`) outrank section
   headings; tertiary captions fall below 4.5:1; the grid's type badge is
   8.5 pt; mixed formats ("2.8" vs "ƒ/2.8").
10. **F10 Toolbar [Medium].** Import sits in the navigation slot and is the
    in-place import; the thumbnail slider stays (disabled) in the loupe and
    reuses the Grid symbol; no search, inspector button or customization.
11. **F11 "Import" means three things [Medium].** Copy (⌘I), reference in
    place (⇧⌘I), and the toolbar button (in place).
12. **F12 Context menus [Medium].** None on photos; thin in the sidebar.
13. **F13 Sidebar structure [Medium].** Keywords below an unbounded project
    list; three levels in places; smart albums use `gearshape`; the
    selection is not restored.
14. **F14 Appearance [Medium].** Dark forced on every window; hard-coded
    grays ignore Increase Contrast; color labels are color only.
15. **F15 Adjust layout [Medium-Low].** "Tone" holds only the curve;
    Presets at the bottom; the inactive Crop button looks disabled; masks
    rename through an app-modal alert.
16. **F16 Window idioms [Medium-Low].** SwiftUI forms in some windows, small
    AppKit controls in others; Export is a window with dialog buttons; open
    panels and alerts block the whole app; a hand-made keyword popover.
17. **F17 Duplication [Low].** Stars drawn three ways; the same details in
    three places with different formats.
18. **F18 Menu wording [Low].** Checkmark "Show …" items instead of
    Show/Hide; ⌘= / ⌘− invisible in the loupe.
19. **F19 The SDK, not the minimum, decides the look [Medium].** The build
    links the macOS 15 SDK (`LC_BUILD_VERSION sdk 15.0`), which is why
    macOS 26 shows the earlier design. Building with the 26 SDK switches the
    app to the new design on 26 regardless of the minimum, and all custom
    chrome carries over unchanged.

Working well and to keep: `NavigationSplitView` with `.inspector`, the
AppKit grid and loupe with their keyboard navigation, one culling keymap
for grid and loupe, undo, SF Symbols, tooltips, folder drops, and the
confirmation dialogs.

## 1. Window anatomy

```
┌ toolbar ─────────────────────────────────────────────────────────────────┐
│ ◧ Title/subtitle │ Import▾ Export │ Grid|Loupe Size/Zoom │ ⟳ │ Filter▾ [Search] ◨ │
├────────────┬────────────────────────────────────────┬────────────────────┤
│ Sidebar    │ Content                                │ Inspector          │
│            │  grid: scrolls under the toolbar       │ [Info | Adjust]    │
│            │  loupe: neutral surround, 24 pt inset, │ histogram (pinned) │
│            │         one caption line under photo   │ sections (scroll)  │
│            │  no bottom bars                        │ no bottom bar      │
└────────────┴────────────────────────────────────────┴────────────────────┘
```

- `NavigationSplitView` with `.inspector`, every pane running to the bottom
  edge. Sidebar 200 / 220 / 320 pt; inspector 280 / 300 / 420 pt. On a 13"
  laptop that leaves about 950 pt of content. (F1, F2)
- The bottom strips go:

  | Today | Goes to |
  |---|---|
  | FilterBar: rating, flag, sort | Toolbar Filter menu |
  | FilterBar: search | Toolbar search field (grid only) |
  | StatusBar: progress | Toolbar Activity item (`.status`), popover with jobs and Stop |
  | StatusBar: file name | Window title in the loupe |
  | StatusBar: messages | Alerts when action is needed, else the Activity popover |
  | LoupeInfoBar | Title and subtitle, the loupe caption line, the Info tab |
  | Inspector Copy/Paste bar | Adjust ⋯ menu, Adjust menu, context menus |

  The toolbar, not a sidebar footer, because the HIG advises against
  actions at the bottom of a sidebar and the toolbar stays visible when the
  sidebar is hidden. Previews and suggestions show in Activity only after
  about 5 s.
- Title and subtitle: in the grid, the source name and "4,623 photos" /
  "12 selected of 4,623" / "87 of 4,623 · Filtered"; in the loupe, the file
  name and "All Photos · 12 of 87".
- Loupe: a neutral dynamic gray inside the safe area (never under the
  toolbar), the photo fitted within a 24 pt margin. A 28 pt caption line on
  the surround, no bar or divider, 11 pt secondary text: position on the
  left; stars (SF Symbols), flag and the label dot *with its name* in the
  middle; Filtered, Original, HDR and Offline badges on the right. (F1, F14,
  F17)
- Grid: the scroll view extends under the toolbar for the system scroll-edge
  effect (26 only).

## 2. Navigation

- The sidebar selection drives the grid. Filter and sort are stored per
  source in `UserDefaults` (JSON keyed by the sidebar selection); the
  catalog does not change. The selection is restored at launch. (F13)
- Grid ⇄ loupe keys are unchanged: double-click, Return, Enter, Space, ⌘↩,
  the toolbar control; out with Esc, Return, Space, ⌘↩.
- **Review (View ▸ Enter Review, `F`)**: opens the loupe on the focused
  photo, records the layout, hides sidebar and inspector, enters full screen
  if needed and hides the toolbar until hover
  (`.windowToolbarFullScreenVisibility(.onHover)`). Culling keys, arrows and
  `Z` keep working; ⌥⌘I brings the inspector back. Esc or `F` restores the
  layout and stays in the loupe, so Esc still backs out one level.
- Info / Adjust stay tabs, remembered per mode; View ▸ Info ⌥⌘1, Adjust ⌥⌘2.

## 3. Sidebar

- `List(selection:)` with `.listStyle(.sidebar)`; each section is
  `Section(title, isExpanded:)` (system header and hover chevron); rows are
  `Label` with `.badge(count)` (aligned counts); nesting uses
  `DisclosureGroup` (leading triangle, system indent). No custom fonts.
  Replaces `SidebarHeader`, `CountBadge` and the trailing chevrons. (F2, F13)
- Sections, bounded ones first:

  | Section | Contents | Depth | Default | Can hide |
  |---|---|---|---|---|
  | Library | All Photos, Last Import, Picks, Rejects, Unrated, No Keywords, Changed on Disk (when any) | 1 | expanded | no |
  | Albums | albums and smart albums with no project | 1 | expanded | yes |
  | Dates | year ▸ months | 2 | collapsed | yes |
  | Keywords | keywords | 1 | collapsed | yes |
  | Projects | project ▸ its albums | 2 | expanded | yes |

  Hide through View ▸ Sidebar Sections or the section header's context menu.
- Icons: smart albums get a stack-with-badge symbol instead of `gearshape`
  (pick it in the SF Symbols app); Changed on Disk keeps a fixed orange
  `exclamationmark.triangle`.
- Empty sections show one secondary line and a link button ("No albums ·
  New Album…"). No footer.

## 4. Inspector

### Shared grammar

Pinned at the top (not scrolling): the Info | Adjust segmented control,
full width; the histogram, 88 pt, corner radius 8; in the loupe's Adjust tab
an **Original** toggle (`\`) on the left and a ⋯ pull-down on the right
(Copy Adjustments, Paste Adjustments, Save Adjustments as Preset…, Reset All
Adjustments). (F1, F15)

Controls stay AppKit-backed but become system controls: `NSButton` with
`.disclosure` bezel, `NSButton(checkboxWithTitle:)` with mixed state, bezeled
`NSTextField`. `AppKitScrollView` stays (the minimum is still 15). (F7, F8)

Dimensions (inspector padding 12, so 276 pt of content at the ideal width):

| Element | Spec |
|---|---|
| Section header | 28 high; triangle in a 16 slot; title at x 20, 13 pt semibold primary; check box at right − 36, reset (`arrow.counterclockwise`, 20×20 hit) at right − 16 |
| Between sections | 1 pt separator, 8 above and below |
| Group label | 20 high, 10 above; 11 pt semibold secondary, mixed case; optional trailing control (Auto); check box in the section column |
| Check boxes | shown only when the group or section has edits (slot always reserved); checked = applied, unchecked = kept but off, mixed = some groups off |
| Slider row | 22 high, 24 pitch: label 80 (11 pt secondary), gap 6, `.small` `NSSlider` (140 at 300 wide, 120 at 280), gap 6, value field 44 (small rounded bezel, 11 pt monospaced digits, focus ring; primary when changed, secondary at default; ↑/↓ step, ⇧ ×10) |
| Slider fill | from the default value, so untouched sliders show no fill (26: `neutralValue`, availability to confirm; 15: neutral gray fill) |
| Pop-up row | the same 80 pt label column; pop-up starts where slider tracks start |
| Group turned off | controls stay enabled; labels and values go secondary, fill hidden (no 45% fade) |
| Reset | double-click label or knob (as now), plus a row context menu |

The Light section (was Develop) goes from about 750 pt to about 480 pt. (F3, F6, F7, F8)

### Info tab

1. Changed on Disk, when present, with a warning icon.
2. Summary, no header: camera 13 pt semibold, lens 11 pt secondary; a 3 × 2
   grid of exposure tiles (10 pt label, 13 pt monospaced value) in the
   loupe's formats ("ƒ/2.8", "1/400 s"); Captured, File, Folder, Volume on
   the 80 pt label column. (F9, F17)
3. Keywords, with a count; Suggested becomes a group label. (F3)
4. Metadata: labels above fields (they are long), one bezel style.
5. Contact as its own collapsed section.

### Adjust tab

Order follows the workflow (render order is unchanged): Presets
(collapsed) · Crop & Straighten (the toggle is accent-tinted only while
active, never tertiary) · Light (was Develop) with Profile, White Balance
(pop-up "Mode"), Tone (was Light; with Auto), Presence · Tone Curve · Color Mixer ·
Color Grading · Details · Masks (rows: check box, name, ⋯ menu with Rename,
Move Up, Move Down, Delete; double-click to rename inline) · Effects.

In the grid: `ContentUnavailableView` "Open a Photo to Adjust It" with an
Open in Loupe button, then Presets, which apply to the selection. (F15)

## 5. Toolbar

`.toolbar(id: "library")` with `ToolbarCommands()`; three groups separated
by `ToolbarSpacer(.fixed)` on 26.

| Item | Placement | Default | Customizable |
|---|---|---|---|
| Sidebar toggle (system) | leading | yes | no |
| Title / subtitle | leading | yes | no |
| Import: `Menu` with primary action (click = Import from Card or Folder… ⌘I; menu adds Add Folder Without Copying… ⇧⌘I) | automatic | yes | yes |
| Export… | automatic | yes | yes |
| Grid / Loupe segmented (`square.grid.2x2` / `rectangle`) | automatic | yes | yes |
| Size: thumbnail slider in the grid (`photo` icons); Fit / 100% in the loupe | automatic | yes | yes |
| Activity: progress and label, popover; only while jobs run | `.status` | when running | no |
| Filter menu (`line.3.horizontal.decrease.circle`, `.fill` when active): rating, flag, sort, Clear Filter; grid only | trailing | yes | yes |
| Search: hosts the existing `NSSearchField`; grid only; ⌘F | trailing | yes | yes |
| Show/Hide Inspector (`sidebar.trailing`) | far trailing | yes | no |
| Palette only: Crop, Rotate Left/Right, Original, Auto, Copy/Paste Adjustments, Add/Suggest Keywords, Enter Review, New Album | automatic | no | yes |

Search is a custom item rather than `.searchable` because it has to be
absent in the loupe. (F10, F1, F5)

## 6. Menu bar

E = existing shortcut, unchanged. S = an existing view key now shown in a
menu. N = new.

Bare keys in menus are real key equivalents, disabled while the key window's
first responder is a text view, and enabled only while the library window is
key (`focusedSceneValue`). The view-level handlers stay as a fallback.
**Verify first** that a disabled item lets the keystroke reach a text field.

**File:** Import from Card or Folder… ⌘I (E) · Add Folder Without Copying…
⇧⌘I (E, renamed) · New Album… ⌘N (E) · New Smart Album… ⌥⌘N (E) · Edit
Smart Album… · Rename "…"… / Delete "…"… · Export… ⇧⌘E (E) · Check for
Changes on Disk (moved from Photo) · Close ⌘W.

**Edit:** Undo / Redo (E) · Cut, Copy, Paste, Select All (Select All selects
in the grid) · Find ▸ Find… ⌘F (N; in the loupe it returns to the grid) ·
Find ▸ Clear Filter.

**View:** Show Grid / Show Loupe ⌘↩ (E) · Enter / Exit Review `F` (N) ·
Zoom to 100% / Zoom to Fit `Z` (S) · Show Original / Show Adjustments `\`
(S) · Larger / Smaller Thumbnails ⌘= / ⌘− (E; zoom in the loupe) · Show /
Hide File Names · Group RAW+JPEG Pairs (checkmark) · Show / Hide HDR
Highlights · Filter ▸ … · Sort By ▸ … · Show / Hide Sidebar ⌃⌘S (N,
`SidebarCommands`) · Sidebar Sections ▸ · Show / Hide Inspector ⌥⌘I (E) ·
Info ⌥⌘1 / Adjust ⌥⌘2 (N) · Show / Hide Toolbar, Customize Toolbar… ·
Enter Full Screen.

**Photo:** Rating ▸ No Rating 0, ★–★★★★★ 1–5, Raise ] / Lower [ (S) ·
Flag ▸ Pick P / Reject X / Clear U (S) · Color Label ▸ ⌥0–⌥7 (S) · Advance
After Rating · Add Keywords… ⌘K (E) · Suggest Keywords ⇧⌘K (E) · Add to
Album ▸ · Remove from Album ⌫ (S) · RAW+JPEG Pair ▸.

**Adjust (new):** Copy Adjustments ⇧⌘C (E, moved) · Paste Adjustments ⇧⌘V
(E, moved) · Apply Preset ▸ (moved) · Auto Exposure · Reset All
Adjustments… · Crop `C` (N) · Rotate Left ⌘[ / Rotate Right ⌘] (N) · New
Mask ▸ · Save Adjustments as Preset… · Import Presets… · Manage Presets… ·
Browse Look-Up Tables….

**Window:** system items, Library, Import. (F5, F11, F18)

## 7. Context menus

The grid gets `menu(for:)` on its collection view; right-clicking outside
the selection selects the clicked item first. (F12)

| Target | Items |
|---|---|
| Grid photos | Open in Loupe · Rating ▸ · Flag ▸ · Color Label ▸ · Add Keywords… · Suggest Keywords · Add to Album ▸ · Remove from Album · Copy / Paste Adjustments · Apply Preset ▸ · Auto Exposure · Reset All Adjustments… · Export… · RAW+JPEG Pair ▸ |
| Loupe | the same minus Open in Loupe, plus Zoom · Show Original · Crop |
| Album / keyword | Rename… · Delete… |
| Smart album | Edit… · Delete… |
| Project | New Album in Project… · New Smart Album in Project… |
| Sidebar section header | Collapse / Expand · Hide Section |
| Inspector section header | Turn Off / On · Reset · Collapse All · Expand All |
| Slider row | Reset "…" |
| Preset tile | Apply · Manage Presets… |
| Mask row | Rename · Move Up · Move Down · Delete |

## 8. Secondary windows

A task tied to the library window that ends in Cancel / OK is a sheet
(grouped `Form`, `.cancellationAction` / `.confirmationAction`). A task that
can open on its own is a window. Open and save panels attach to their window
(`beginSheetModal(for:)` or `.fileImporter` / `.fileExporter`); the Save
Preset name becomes an `.alert` with a `TextField`. (F16)

| Surface | Becomes |
|---|---|
| Export | sheet; the export then runs in the background with progress in Activity |
| Look-up table browser | sheet; Import and Manage stack as sheets on it |
| Preset manager | sheet |
| Album, keyword and smart album sheets | already sheets; moved onto the same idiom |
| ⌘K keyword entry | `.popover` |
| Import | window, shared with the standalone importer: a real toolbar (source, Choose Folder…, Rescan, count or progress, Import N Photos), options in an `.inspector`, camera info in the subtitle, no footer |
| Settings | `Settings` scene, system appearance |

Dark is applied to the library window itself (`NSWindow.appearance`), so it
does not leak into Import or Settings; its sheets inherit it.

## 9. First run and empty states

All `ContentUnavailableView`. Empty library: "No Photos Yet", a sentence on
copying vs. using photos in place, a primary Import from Card or Folder…
(or "Import from ‹card name›…" when a card is mounted), a secondary Add
Folder Without Copying…, and a hint that folders can be dropped. Also: "No
Photos Match" with Clear Filter; "No Selection" in the inspector; the Import
window's "Insert a Card or Choose a Folder"; the catalog-failure view with
selectable text. (F11, F16)

## 10. Accessibility

- Grid cells are accessibility elements: label "DSC00231, RAW plus JPEG",
  value "3 stars, Picked, Red label, Offline", custom actions (Open in
  Loupe, Raise / Lower Rating, Pick, Reject, Clear Flag). The loupe canvas
  is an image element with the same label, value and actions. (F4)
- Each culling action posts a value change and an announcement.
- Sliders announce formatted values; value fields are labeled; icon buttons
  use their help text as the label.
- `Palette` becomes dynamic colors with high-contrast variants (in code;
  SwiftPM does not compile asset catalogs). No tertiary text for labels;
  10 pt minimum (the grid badge goes from 8.5 pt to 10 pt); color labels
  carry their name in the label, tooltip and loupe caption. (F9, F14)
- Default focus rings; Tab order sidebar → content → inspector; the grid
  fade is skipped with Reduce Motion; every icon-only hit area at least
  20 × 20 pt.

## macOS 15 fallback

| Area | macOS 26 | macOS 15 |
|---|---|---|
| Look | system Liquid Glass components | the earlier design |
| Inspector scroll | `AppKitScrollView` (unchanged) | the same |
| Toolbar groups | `ToolbarSpacer(.fixed)` | plain grouping |
| Slider fill | `neutralValue` (confirm availability) | neutral `trackFillColor` |
| Grid under the toolbar | system scroll-edge effect | plain toolbar background |
| Everything else | sidebar sections, badges, `ContentUnavailableView`, inspector, customizable toolbar, full-screen toolbar visibility | the same (macOS 14 or 15 APIs) |

## Steps

Each step ships on its own, adds its strings to `Localizable.xcstrings`,
and updates the debug-script commands for views it removes.

1. **Build with the macOS 26 SDK** (minimum stays 15). Needs an Xcode 26
   toolchain on the build machine. Check the inspector's scrolling and
   clicks under the toolbar on 26 and on 15. (F19)
2. **Grid and loupe accessibility.** (F4)
3. **Menu bar:** the Adjust menu, `SidebarCommands`, `ToolbarCommands`,
   shown culling keys with the typing guard, new keys, state-based titles,
   the import rename. Prototype one guarded bare-key item first. (F5, F11,
   F18)
4. **Context menus.** (F12)
5. **Toolbar and removal of the bottom bars:** customizable toolbar, Import
   menu button, inspector button, Activity, mode-aware size and zoom,
   search and Filter with per-source state, title and subtitle; delete
   `FilterBar` and `StatusBar`. (F1, F10)
6. **Loupe caption line:** remove `LoupeInfoBar`, SF Symbol stars
   everywhere. (F1, F17)
7. **Sidebar rebuild.** (F2, F13)
8. **Inspector:** pinned header, system disclosure and check boxes, the
   slider row, Adjust order and names, Info typography. (F2, F3, F6–F9, F15)
9. **Color and appearance.** (F14, F9)
10. **Secondary windows:** sheets, the Import window's toolbar and
    inspector, window-modal panels, empty states, the keyword popover.
    (F16, F11)
11. **Review mode.**

## References

- [HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [HIG: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [HIG: Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- [HIG: Sliders](https://developer.apple.com/design/human-interface-guidelines/sliders)
- [HIG: Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles)
- [HIG: Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)
- [HIG: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- [HIG: Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)
- [HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Apple Developer Forums: UIDesignRequiresCompatibility and SDK versions](https://developer.apple.com/forums/thread/838637)
