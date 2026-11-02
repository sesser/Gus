# UI redesign: window, navigation, menus and inspector

Status: **proposed** (2026-11-02). The decisions below were approved,
with three Import questions still open (see "Open"). Nothing is
implemented yet.

The library window grew one feature at a time, and it shows: the sidebar
and the inspector are built from two different hand-made heading styles,
the bottom of the window is three or four unrelated strips, many commands
exist only as bare keys or inspector buttons, and the grid is invisible to
VoiceOver. This file records an audit against Apple's Human Interface
Guidelines (HIG) and the redesign that answers it. The architecture,
naming and clean-room rules in `CLAUDE.md` still apply: the data model,
existing shortcuts and existing features do not change.

Screenshots of the starting point: `docs/screenshots/` (library window,
Import and Export).

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
   Import (in both apps) and Settings follow the system.
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
16. **Export is a sheet; Import stays a window.** Export is a 560 pt wide
    sheet on the library window whose preview appears only with a
    watermark. Import is a window with a toolbar and an options inspector,
    shared unchanged by the standalone importer. One form idiom for both
    (section 8).

## Open

- **New keys in the Import window:** ⌘O Choose Folder…, ⌘R Rescan, ⇧⌘A
  Deselect All, ⌘. Stop Import. None clash with the library app.
- **Shared grid code:** `UniformGridLayout` and the `Badges` renderer move
  from PhotoApp into PhotoUI so the Import grid uses the library grid's
  machinery. The fallback is a SwiftUI grid with focus and keys added,
  which would look less alike.
- **Template fields:** bezeled text with an Insert menu, or token pills
  (`NSTokenField`) later.

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

Import and Export windows (reviewed after the first audit, from
`gus-import.png` and `gus-export.png`):

20. **F20 Import grid without keyboard or VoiceOver [High].** Tiles in a
    `LazyVGrid` respond only to `.onTapGesture`; no focus, keys or
    accessibility action; All / None have no shortcut, ⌘A does nothing.
21. **F21 Import has no toolbar or commands [Medium].** Source and
    selection controls sit in a bar in the content; Import N Photos is at
    the bottom of the options column; no menu items in either app; open
    panels are app-modal.
22. **F22 Import inclusion by color [Medium].** An accent fill and a round
    accent check, unlike the library grid's border; the whole grid is
    tinted by default; already-imported shots are a seal at 50%.
23. **F23 Template fields [Medium].** Bezel-less, right-aligned monospaced
    tokens, selected in the red accent on open, read as an error; the token
    menu is unlabeled; the example is 10 pt right-aligned.
24. **F24 Export fields and sliders [Medium].** Length, Resolution and Box
    fields have no bezel; Quality, Scale and watermark sliders draw a tick
    per step (about 90 on Quality).
25. **F25 Export over a frozen selection [Medium].** A free-standing window
    over the selection copied when it opened; only the button shows the
    count.
26. **F26 Export preview [Medium].** Half the window shows the first photo
    whether or not a watermark is on, far from the Watermark section.
27. **F27 Import options [Medium].** Videos is a one-switch section, and
    toggling it rescans and re-includes every shot (the user's picks are
    lost); After Importing is below the fold; "Apply / No metadata"; three
    meanings of "Preset".
28. **F28 Import states [Low-Medium].** Blank grid while scanning; empty
    states without actions; progress, errors and results as small text in
    the options footer.
29. **F29 Shutter count [Low].** "Sony ILCE-7M3 - 4,374" in a permanent
    status bar, with no label.
30. **F30 Wording [Low].** "Choose…", "Choose Folder…", "Choose PNG…";
    "Preset / Preset"; three loose preset buttons in Export.
31. **F31 Export footer [Low].** "Show in Finder when done" among the
    buttons; errors as orange text.
32. **F32 Forced dark in Import and Export [Low].** Including the standalone
    importer.

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

**Import window** (shared `ImportCommands`, enabled while an Import window
is key, in both apps): File ▸ Choose Folder… ⌘O (N) · Rescan ⌘R (N) ·
Import Selected Photos (Return) · Stop Import ⌘. (N); Edit ▸ Select All ⌘A ·
Deselect All ⇧⌘A (N); View ▸ Show Videos · Show Photos Already in Library ·
Show / Hide Options ⌥⌘I. (F21)

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
| Import cell | Select / Deselect · Select All · Deselect All |

## 8. Secondary windows

### The rule

A task that works on the library window's current selection or photo and
ends in Cancel / OK is a **sheet** on that window: the parent is frozen
while the sheet is up, so what the sheet acts on cannot change under it. A
long task that can start on its own (a card is inserted, the standalone
importer launches) is a **window**. Only one sheet is shown at a time; a
step inside a sheet (importing look-up tables, managing them) is a page in
the sheet with a Back button, not a second sheet. Open and save panels and
alerts attach to their window (`beginSheetModal(for:)`, `.fileImporter`,
`.fileExporter`, `.alert`). (HIG: Sheets, "Display only one sheet at a
time"; Modality. F16, F25)

| Surface | Kind | Default size (pt) | Appearance |
|---|---|---|---|
| Import | window, shared with the standalone importer | 1200 × 780, minimum 900 × 600 | system |
| Export | sheet on the library window | 560 wide, 640 high (480 minimum) | inherits dark |
| Look-up table browser | sheet, with Import and Manage as pages | 760 × 560 | inherits dark |
| Preset manager | sheet | 560 × 480 | inherits dark |
| New / rename album, rename keyword, smart album | sheets (already) | content | inherits dark |
| Metadata preset editor | sheet on the Import window | 460 × 560 | system |
| ⌘K keyword entry | `.popover` on the content's top edge | 420 wide | inherits dark |
| Settings | `Settings` scene | 480 wide | system |

On a 13" laptop (about 1470 × 850 pt usable) the Import window fits at its
default size, and the Export sheet on a 1320 × 860 library window covers
about 42% of its width and 74% of its height, leaving the toolbar, sidebar
and window edges visible. (HIG: Sheets, "Present a sheet in a reasonable
default size")

### Form conventions (Import options, Export, preset editors, Settings)

| Element | Convention | Why |
|---|---|---|
| Container | `Form` with `.formStyle(.grouped)`, regular control size | one system idiom (F16) |
| Sections | `Section("Title")`; no section for a single control; no header that repeats its only row | hierarchy (F27, F30) |
| Text and number fields | `.textFieldStyle(.roundedBorder)`; numbers right-aligned in 72 pt with the unit after | fields must look editable (HIG: Text fields; F23, F24) |
| Templates | a full-width bezeled monospaced field, left-aligned, with an **Insert** pull-down (`Menu`, items like "Capture year  {capture:yyyy}"); the example directly under it in 11 pt monospaced secondary text, left-aligned, wrapping | readable, never red (F23) |
| On / off options | `Toggle` with `.toggleStyle(.checkbox)`; no switches | HIG: Toggles (F27) |
| Choices | segmented only when the choice changes the rows below (Name, Format); pop-up otherwise; a radio group for up to five long labels (Metadata) | HIG: Toggles, Pop-up buttons |
| Sliders | continuous (no `step:`; round in the binding), value text 44 pt, monospaced digits | no tick-mark noise (HIG: Sliders; F24) |
| Choose buttons | name the object: "Choose Folder…", "Choose Image…"; panel prompts "Choose Folder", "Use Image" | HIG: Writing (F30) |
| Presets | one pop-up whose menu also holds New / Save as Preset…, Update "‹name›", Edit "‹name›"…, Delete "‹name›"… | fewer loose controls (F27, F30) |
| Captions and errors | 11 pt secondary text under the row they explain; errors with `exclamationmark.triangle` and text, next to the field they concern | color is never the only signal (F31) |
| Buttons | `.cancellationAction` and `.confirmationAction` placements; in a window, the main action goes in the toolbar | HIG: Sheets, Toolbars |

### Import window

```
┌ [▣ Untitled ▾] [⟳] │ Import · 6 of 412 selected · Sony ILCE-7M3, shutter count 4,374 │ ⟳ Copying │ [☑▾] [◨] [Import 6 Photos] ┐
├──────────────────────────────────────────────────────┬──────────────────────────┤
│ Grid: library cell style, a check box per shot       │ Options (inspector)      │
│ (no header bar, no duplicates strip)                 │ Destination · Project    │
│                                                      │ Metadata · After Import  │
└──────────────────────────────────────────────────────┴──────────────────────────┘
   no footer, no status bar
```

The source bar, the footer and the status bar are removed; their contents
move to the toolbar, the subtitle and the menus. (HIG: Toolbars; decision 7.
F21, F28, F29)

Toolbar (fixed, not customizable; three groups):

| Item | Placement | Notes |
|---|---|---|
| Source pop-up: mounted cards (`sdcard`), chosen folders (`folder`), a divider, Choose Folder… ⌘O | `.navigation` | replaces "From", the pop-up and the Choose Folder… button |
| Rescan (`arrow.clockwise`) ⌘R | `.navigation` | |
| Title and subtitle | system | title "Import" in the library app, the importer's name in the importer; subtitle "6 of 412 selected · Sony ILCE-7M3, shutter count 4,374" (F29) |
| Activity | `.status` | while scanning, a spinner and "Reading ‹source›…"; while copying, a 160 pt progress bar and "12 of 412 files · 1.2 of 18 GB", the current file name as its tooltip |
| Selection pull-down (`checklist`) | trailing | Select All ⌘A · Deselect All ⇧⌘A · Show Videos (checkmark) · Show Photos Already in Library (library app only); replaces All / None, the Videos section and the duplicates strip |
| Show / Hide Options (`sidebar.trailing`) ⌥⌘I | trailing | toggles the options inspector |
| **Import N Photos** (`.borderedProminent`, Return); **Stop** (⌘.) while copying | `.primaryAction`, far trailing | the window's one prominent action (HIG: Toolbars) |

Show Videos keeps the user's picks when it rescans: shots that were left out
stay left out, and new videos come in included. Today `rescan()` resets the
selection to every new shot. (F27)

Grid: it shares the library grid's machinery and look. `UniformGridLayout`
and the `Badges` renderer move into PhotoUI, and an `NSCollectionView` hosts
an `ImportCell` built to the library cell's measurements. (Consistency; F20,
F22)

| Part | Spec | Same as library |
|---|---|---|
| Layout | `NSCollectionView` and `UniformGridLayout`, 180 pt target cell, the library's spacing | yes |
| Cell | corner radius 6, padding 6, `Palette.cell` fill (dynamic) | yes |
| Name and type | 11 pt name; 10 pt bold type badge from `Badges` | yes |
| Date | 10 pt secondary line under the name | Import only |
| Included | a system check box (14 pt) at top-leading on a 20 pt dark rounded backing; checked = will import; unchecked = left out, image at 50% | Import only; replaces the accent fill and round check |
| Already in library | shown only when asked; no check box; 10 pt text badge "In Library"; image at 50% | Import only |
| Focus | the system focus ring on the keyboard-focused cell; no accent border (the check box is the selection) | — |
| Mouse | click toggles a shot; ⇧-click toggles the range (as today) | — |
| Keys | arrows move focus; Space toggles; ⌘A / ⇧⌘A select all / none; Return imports | — |
| VoiceOver | each cell is a check box: label "DSC00328, RAW plus JPEG, Oct 30, 10:46 AM", value checked or unchecked, press toggles; imported shots say "already in library" | — |
| Context menu | Select / Deselect · Select All · Deselect All | — |

Options inspector: `.inspector` with `.inspectorColumnWidth(min: 300,
ideal: 320, max: 400)`, a grouped `Form` following the conventions above, in
the order the decisions are made. It fits the default 780 pt height without
scrolling once the Videos section and the footer are gone.

| Section | Rows |
|---|---|
| Destination | Folder: path (truncated at the head, full path as tooltip) and Choose Folder… · Subfolders: template · File Names: template · Example: the whole relative path |
| Project (library app) / Job (importer) | Add To pop-up (library app) · Project Name template (for a new project) · Job Code, bezeled, with the recent-codes `clock` menu |
| Metadata | Metadata Preset pop-up: None · presets · New Preset… · Edit "‹name›"…; a caption when one is chosen |
| After Import | ☐ Delete originals from "‹card›" · ☐ Eject "‹card›" (disabled for folders); caption: "Originals are deleted only after every copy is verified, and you're asked first." |

| State | Shown |
|---|---|
| No source | `ContentUnavailableView` "Insert a Card or Choose a Folder" (`sdcard`) with Choose Folder… |
| Scanning | the toolbar activity, and a centered `ProgressView` "Reading ‹source›…" in the grid until the first shots appear |
| No photos | "No Photos on ‹source›" with Choose Folder… |
| All already imported | "All 412 Photos Are Already in the Library" with Show Them |
| Read error | "Can't Read ‹source›", the error text, and Rescan |
| Copying | toolbar activity; Import becomes Stop |
| Done | subtitle "Imported 412 files"; the delete confirmation (existing) as a window-modal alert |
| Cancelled, failures, eject failure | a window-modal alert with the existing message text |

Commands: a shared `ImportCommands` in PhotoUI, used by both apps and enabled
while an Import window is key (`focusedSceneValue`); see section 6.
(HIG: The menu bar. F21)

The standalone importer uses the same `ImportWindow`, model and commands,
never a fork:

| Aspect | Library app | Standalone importer |
|---|---|---|
| Window | `Window` opened by ⌘I or a card | the only window; closing it quits (as now) |
| Title | "Import" | the importer's name |
| Second section | Project: Add To, Project Name, Job Code | Job: Job Code |
| Already in library | marked; menu item to show them | absent |
| Appearance | system | system |

### Export sheet

Export is a sheet: it acts on the library window's selection, which a sheet
freezes (F25); it is a scoped task ending in Cancel / Export (HIG: Sheets);
and with its preview inside the Watermark section it fits a 13" laptop with
the library still in view. The cost is that the library can't be browsed
while the sheet is up; presets carry settings between exports. The export
runs after the sheet closes, with progress in the library toolbar's Activity
item.

Size: 560 pt wide (520 pt of form), 640 pt high by default, 480 minimum,
never taller than the library window minus 40 pt; the form scrolls between a
fixed header and the buttons. `.presentationSizing` (macOS 15) sets this;
check whether it lets people resize the sheet vertically.

| Part | Contents |
|---|---|
| Header (fixed) | a 44 pt thumbnail of the first photo; "Export 24 Photos" in 13 pt semibold; "From All Photos · 3 videos are skipped" in 11 pt secondary |
| Preset (first row, no section) | pop-up: None · presets · Save as Preset… · Update "‹name›" (when changed) · Delete "‹name›"… |
| Destination | Folder: path and Choose Folder… · ☐ Show in Finder when done (F31) · errors about the folder shown here |
| File Names | Name: Original Name \| Template (segmented) · template field and Insert menu · example |
| File Type | Format: JPEG \| TIFF · Quality slider (continuous) or Bit Depth and Compression · Color Space; the ProPhoto warning with an icon |
| Size | Size pop-up · Length, Box or Scale with bezeled 72 pt fields · Resolution (bezeled) · "Photos are never enlarged." · Output Sharpening · Sharpen For |
| Metadata | radio group (as now) and its caption |
| Watermark | ☐ Add a watermark · Image: name and Choose Image… · Position (anchor grid) · Size, Margin, Opacity · **Preview**: the first photo with the watermark, fitted within 520 × 220 pt, shown only while a watermark is on (F26) |
| Buttons | Cancel (Esc) · Export 24 Photos (Return, default); the name-conflict alert appears on the sheet before it closes |

### Other sheets

The look-up table browser (760 × 560): a header row with the Collection
pop-up, Import… and Manage…; the tiles as today; buttons Remove from Photo
(leading), Cancel, Apply. Import and Manage become pages inside the sheet
(a `NavigationStack` with Back), not sheets on the sheet. Without a photo in
the loupe it shows a note and Apply is disabled.

The preset manager (560 × 480): the list by collection; Import… and Export
All… on the leading side, Done on the trailing side (edits apply at once).
Album, keyword, smart album and metadata preset sheets use the form
conventions, with Delete on the leading side where it exists. The Save
Preset name becomes an `.alert` with a `TextField`; masks rename inline.

### Appearance

The library window is dark through `NSWindow.appearance`, so its sheets and
popovers inherit it and nothing leaks into other windows. Import (in both
apps) and Settings follow the system; the Import grid background uses the
dynamic `Palette`. (HIG: Dark Mode. F32, F14)

### macOS 15

Everything in this section uses macOS 14 or 15 APIs: `.inspector`,
`ToolbarItem` `.status`, `.borderedProminent`, `ContentUnavailableView`,
`.toggleStyle(.checkbox)`, `.presentationSizing`. On macOS 26 the toolbar
and its prominent Import button pick up Liquid Glass; nothing else differs.

## 9. First run and empty states

All `ContentUnavailableView`. Empty library: "No Photos Yet", a sentence on
copying vs. using photos in place, a primary Import from Card or Folder…
(or "Import from ‹card name›…" when a card is mounted), a secondary Add
Folder Without Copying…, and a hint that folders can be dropped. Also: "No
Photos Match" with Clear Filter; "No Selection" in the inspector; the Import
window's states (section 8); the catalog-failure view with selectable
text. (F11, F16, F28)

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
| Import button | prominent tinted glass in the toolbar | bordered prominent button |
| Sheet sizing | `.presentationSizing` | the same (macOS 15 API) |
| Everything else | sidebar sections, badges, `ContentUnavailableView`, inspector, customizable toolbar, full-screen toolbar visibility | the same (macOS 14 or 15 APIs) |

## Steps

Each step ships on its own, adds its strings to `Localizable.xcstrings`,
and updates the debug-script commands for views it removes.

1. **Build with the macOS 26 SDK** (minimum stays 15). Needs an Xcode 26
   toolchain on the build machine. Check the inspector's scrolling and
   clicks under the toolbar on 26 and on 15. (F19)
2. **Grid, loupe and Import grid accessibility:** labels, values and
   actions; the Import tiles get check-box semantics before the grid is
   rebuilt. (F4, F20)
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
10. **Import fix:** Show Videos keeps the user's picks when it rescans.
    Can ship first. (F27)
11. **Export sheet:** single column, preview inside Watermark, bezeled
    number fields, continuous sliders, the preset pop-up, Show in Finder
    under Destination. (F16, F24–F26, F30, F31)
12. **Import window:** toolbar, options inspector, `ImportCommands`, the
    grid on `NSCollectionView` with check boxes, states, system appearance;
    the standalone importer gets it unchanged. (F11, F20–F23, F27–F29, F32)
13. **Other sheets and panels:** the look-up table browser and Presets as
    sheets with in-sheet pages, window-modal panels, the keyword popover.
    (F16)
14. **Review mode.**

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
- [HIG: Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [SwiftUI: presentationSizing(_:)](https://developer.apple.com/documentation/swiftui/view/presentationsizing(_:))
- [Apple Developer Forums: UIDesignRequiresCompatibility and SDK versions](https://developer.apple.com/forums/thread/838637)
