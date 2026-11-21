# Preset list view: design

Owner: apple-ui-designer. Date: 2026-11-20. Status: Designed. Nothing is
open for the owner; §15 lists two PRD wording notes for the product manager.

**Inputs.**

- Requirements: the issue #241 body (PRD, Draft), cited as R1-R12, AC1-AC10
  and A1-A7.
- Code read on this branch: `Views/PresetsSection.swift`,
  `Model/PresetPreviewModel.swift`, `Model/PresetActions.swift`
  (`previewAdjustmentPreset`, `applyAdjustmentPreset`, `PresetText.groups`),
  `Views/AppKitButton.swift`, `Views/CurveEditor.swift` (`AppKitSegmented`),
  `Views/AdjustControls.swift` (`ImageTile` and its `HoverButton`,
  `InspectorMetrics`, `SectionHeader`), `Views/AdjustView.swift` (where the
  section is shown), `Views/LookTableBrowserSheet.swift` (the applied marker),
  `Model/AdjustmentEditor.swift` (`preview`, `endPreview`),
  `Model/DebugScript.swift` (`buttons`, `print inspectorwidth`),
  `PhotoCore/Browser/Comparison.swift` (`ComparisonLink`, the preference
  pattern), `USER_GUIDE.md` (Presets paragraph).
- HIG read 2026-11-20 (markdown): Segmented controls. Its macOS section says
  to use a segmented control "to help people switch views in a toolbar or
  inspector pane" and, "if your app includes tooltips, provide one for each
  segment". It also says to use text or images, not a mix, and to consider
  introductory text or labels under symbols (see §2.4 for why I don't add
  them).

**Clean-room note.** Two SF Symbols and a name list. Nothing here comes from
another photo application.

## 1. Decisions at a glance

| # | Decision |
| --- | --- |
| 1.1 | The view switch is **one two-segment `NSSegmentedControl`** (`AppKitSegmented` with symbols), not two separate buttons: `square.grid.2x2` (Thumbnails) and `list.bullet` (List). |
| 1.2 | It is right-aligned on the Save... / Import... / Manage... row. When the push buttons wrap, it stays on the first row with Save... and Import...; below that, with Manage.... It never overlaps a push button. |
| 1.3 | A list row is a 22 pt, full-width AppKit button: name only, tail-truncated, with a hover highlight and, for the preset the photo already has, an accent `checkmark.circle.fill` at the trailing edge. |
| 1.4 | Rows reuse `ImageTile.HoverButton` for hover, and `PresetPreviewModel.hover(_:isInside:)` unchanged for the preview. No new preview mechanism, no new guard. |
| 1.5 | The choice is `LibraryModel.presetsView` (`.list` default), stored under `adjust.presetsView` in `UserDefaults`, parsed by a PhotoCore function like `ComparisonLink.isLinked(stored:)`. |
| 1.6 | List view builds no `PresetGrid`, so its render task never starts. `PresetPreviewModel` is not changed. |

## 2. The view switch

### 2.1 Why a segmented control

The two views are mutually exclusive presentations of the same content. That
is what a segmented control is for, and it is how the Finder's icon and list
switch reads, so the symbols and the idiom are already familiar to Mac users.
Its advantages over two separate buttons:

- Exactly one segment is selected by construction. Two `AppKitButton(.toggle)`
  buttons (`pushOnPushOff`, the Original and Crop precedent) can both be off,
  need exclusivity code, and read as two unrelated on/off switches. In the
  existing uses a toggle stands for one state that is on or off; here the
  state is a choice of one of two.
- It stays one group at any width (HIG: segmented controls "preserve their
  grouping regardless of the view size"), which is what the wrapping rule in
  §3 needs.
- VoiceOver gets one control with a selected segment, not two buttons that
  must each say whether they are pressed.

A SwiftUI `Picker(.segmented)` is ruled out by `CLAUDE.md` ("No SwiftUI
`ScrollView` under the toolbar", and the debug script's `click` can't drive
it). So it is AppKit, in the existing wrapper.

### 2.2 `AppKitSegmented` change

Add an optional `symbols: [String] = []`. When it is non-empty,
`makeNSView` builds the control with `NSSegmentedControl(images:...)` instead
of `labels:`, and `labels` then serves as each segment's VoiceOver name (the
image's `accessibilityDescription`), never drawn. Keep `.selectOne`,
`controlSize = .small`, and set each segment's width to a fixed 28 pt
(`setWidth(28, forSegment:)`) so the two segments are equal; do not use
`fillsWidth` (the control keeps its own width, about 56 pt). Tooltips go
through the existing `toolTips` array. Symbols use the system rendering at the
control's size; no custom weight, no tint, no `selectedSegmentBezelColor`: the
system draws the selected segment, in both the current and the earlier
design, with Increase Contrast included.

Two follow-on edits in `DebugScript`: `drawSegmented(like:)` builds its copy
from `labels` and must copy the segments' images when there are no labels;
`printButtons` should print each segment's accessibility label as well as
`selected N` (§10).

### 2.3 Content

| | Segment 0 | Segment 1 |
| --- | --- | --- |
| Symbol | `square.grid.2x2` | `list.bullet` |
| VoiceOver name | Thumbnails | List |
| Tooltip | Show presets as thumbnails | Show presets as a list |

The control's own VoiceOver label is "Presets view". Names are nouns (HIG:
"nouns or noun phrases for segment labels"); the tooltips are the longer
statement of what clicking does, as the other inspector tooltips are (for
example "Show the crop frame on the photo"). The selected segment is the
chosen view; nothing else shows the choice.

Both symbols exist since SF Symbols 1 and need no availability check on
macOS 15.

### 2.4 Why icon-only

The PRD asks for icons only (R1), and the row is short of width (§3). The
HIG suggests labels under symbols on macOS, but a label row would double the
control's height and make it taller than the push buttons it sits beside. The
mitigation is the HIG's other one: a tooltip on each segment, plus the fact
that both symbols are the Finder's. Judgment, not Apple policy.

## 3. The button row

Today `buttons` is a `ViewThatFits(in: .horizontal)` of two variants (Save,
Import, Manage on one line; or Save and Import over Manage). Add the control
to each variant and a third:

1. `HStack { Save  Import  Manage  Spacer(minLength: 8)  switch }`
2. `VStack(alignment: .leading, spacing: 6) { HStack { Save  Import  Spacer(minLength: 8)  switch }  Manage }`
3. `VStack(alignment: .leading, spacing: 6) { HStack { Save  Import }  HStack { Manage  Spacer(minLength: 8)  switch } }`

`ViewThatFits` takes the first that fits, so the push buttons wrap as they do
today and the switch never moves onto them. Variant 3 is the safety net for a
legacy scroller (visible content 239 pt, 17 pt less than the 256 pt the narrowest
inspector gives otherwise) and for longer translations; variant 2 is
what the narrowest column normally gets, since Save..., Import..., Manage...
(small push buttons) plus the control come to roughly 260 pt by my estimate.
Measure, don't trust the estimate: the engineer reads the real widths (§10,
`print presetsbar`).

- The row's items are centered vertically on each line (the small segmented
  control and the small push buttons are within a point of each other in height).
- The control shows in every state, including with no presets and in the grid
  tab: the choice is app-wide (R3), so it is useful before the first import,
  and a control that appears only sometimes moves the buttons.
- It is never dimmed: switching views is always possible.
- The Save/Import/Manage buttons and their tooltips are unchanged.

## 4. The list

### 4.1 Structure

Same data and order as `PresetGrid`: `model.adjustmentPresetCollections`, the
unnamed collection's presets first with no heading, each named collection
under `PresetCollectionSection`'s existing disclosure heading (collapsed by
default, state remembered under the existing `adjust.presets.<name>` key,
shared by both views, so a collection opened in one is open in the other: AC3).
`PresetCollectionSection` and the unnamed-collection branch choose between
`PresetGrid` and a new `PresetList` by `model.presetsView`. `PresetList` is a
`LazyVStack(alignment: .leading, spacing: 0)` of `PresetRow`s. Do not promise
laziness: inside the inspector's AppKit scroll view SwiftUI may build every
row, as `LazyVGrid` does today. Rows are cheap, so that is acceptable.

### 4.2 Row anatomy

`PresetRow` is an `NSViewRepresentable` over `ImageTile.HoverButton`
(the same hover tracking and the same "leaving the window ends the hover"
behavior), configured as:

| Part | Specification |
| --- | --- |
| Height | 22 pt, full column width, no gap between rows. 40 presets take 880 pt, against about 2,180 pt as thumbnails at the narrowest width (each tile about 124 x 101 pt plus 8 pt, two per line): well under half. |
| Hit target | The whole row, edge to edge. This also covers a touch-display Mac: the visual density is tuned for the pointer and the target is the full row width. |
| Name | `NSFont.preferredFont(forTextStyle: .callout)` (12 pt on the Mac, as the collection heading buttons use), `labelColor`, left aligned, single line, `byTruncatingTail` (a list is scanned from its leading edge; the thumbnails' middle truncation is for captions under a picture). 8 pt inset from the row's edges. The tooltip gives the full name. |
| Indent | A row under a collection heading starts its text where the heading's title starts: measure the heading button once, no magic number. An unnamed collection's rows are flush with the push buttons' edge (the highlight uses the full column; the text inset is 8 pt). |
| Applied marker | `checkmark.circle.fill` at 12 pt in `controlAccentColor`, at the trailing edge, 8 pt in. The name's room always excludes the marker's 20 pt, so a row doesn't re-truncate when the marker comes and goes. It is the marker the look-up table browser already uses for the applied table (same symbol, same color), so one meaning has one look. Shape and color together: the check carries the meaning, so color is not the only signal. |
| Hover | A rounded-rect fill of `NSColor.tertiarySystemFill`, corner radius 4 (the thumbnails' selection outline uses 4), inset 0 from the row's edges. Appears on enter, goes on exit, no animation. Drawn in `updateLayer` or by resolving the color under `performAsCurrentDrawingAppearance`, so Light, Dark and Increase Contrast follow. |
| Pressed | `secondarySystemFill`, while the mouse is down (`isHighlighted`). |
| Focus | The system focus ring when the row has keyboard focus, shaped to the highlight's rounded rectangle (not a hover substitute: a focused row shows the ring, a hovered one the fill). |
| Other | No icon, no thumbnail, no count, no badge, no collection name, no group summary (R10, A2). |

The hover fill is a pointer affordance: it shows even in the grid tab, where
hover previews nothing, because the row is still clickable there.

The checked state follows the same rule as the thumbnails'
outline, from `PresetGrid`: in the loupe with a ready editor, `preset.applied(onto: saved) == saved`
using `editor.savedAdjustments` (not the live values, so a drag doesn't
redraw 40 rows); otherwise nothing is marked (the grid tab marks nothing,
today and in list view alike). Move the expression into one helper both
views call.

### 4.3 Custom chrome: justification

`CLAUDE.md` and `WORKFLOW.md` require a written reason for custom chrome.
The row is custom because no system component does the job in this place:
`NSTableView` or SwiftUI `List` would nest a second scroller in the inspector's
scroll view (a list that must grow to its full height to sit between a
heading and the next), and SwiftUI buttons and gestures in that scroll view
swallow clicks in the earlier design (`CLAUDE.md`, the debug script can't
drive them). The row uses only system parts: `NSButton`, system fills, system
colors, the callout text style and an SF Symbol. `ImageTile` is the
precedent in the same file.

### 4.4 Context menu and tooltip

Same as `PresetGrid`'s tiles, attached with `.contextMenu` on the row: **Apply**
(`model.applyAdjustmentPreset(preset)`) and **Manage Presets...**
(`model.showsPresetSheet = true`). The tooltip is
`"\(preset.name)\n\(PresetText.groups(preset))"`, the same as a tile's. Both
come from one helper so they can't drift.

## 5. Hover and click

- **Hover.** `PresetRow` sets `onHover = { previews.hover(preset, isInside: $0) }`:
  the same call a tile makes. That keeps everything R6 and R7 ask for without
  new code: loupe only (`library.mode == .loupe`), straight to
  `previewAdjustmentPreset` on enter (live, unsaved, no undo step, no History
  entry), and a 120 ms hold on exit through `hoverCount`, so moving from one
  row to the next never ends the preview in between (the next row's enter
  bumps the count before the hold ends). Contiguous rows (no gap) make that
  the normal case. `previewAdjustmentPreset` and `endPreview` are not touched
  (they are shared with the Color Mixer and mask hovers).
- **Limits that carry over unchanged.** In the grid tab nothing previews
  (`mode != .loupe`). While comparing, the Adjust tab shows "Not Available
  While Comparing" and no Presets heading, so there is nothing to guard (§15,
  note 2). During a crop session `PresetPreviewModel.hover` and
  `editor.preview` behave as they do for thumbnails today: the engineer copies
  no rule and adds none. Where hover does nothing, click applies as it does
  today.
- **Click.** `model.applyAdjustmentPreset(preset)`: the photo on screen in the
  loupe, the selection in the grid, one undo step. After a click the pointer is
  still on the row: the row stays highlighted and the preview shows the preset
  the photo now has, as for a thumbnail.
- **A row that disappears under the pointer** (collection collapsed, view
  switched by keyboard, section hidden): `HoverButton.viewWillMove(toWindow:)`
  already reports exit, which ends the preview after the 120 ms hold.
- **A row that scrolls under a still pointer** begins or ends a preview when
  AppKit sends the enter or exit, as a tile does today. Accepted; no code.
- **A fast sweep down 40 rows** starts 40 previews and the editor's render
  request collapses them (A6); no queueing is added.

## 6. Persistence

- `enum PresetsViewChoice: String { case list, thumbnails }` in PhotoCore
  next to the other pure rules (the `ComparisonLink` pattern), with
  `defaultsKey = "adjust.presetsView"` and
  `static func choice(stored: Any?) -> PresetsViewChoice`, which returns
  `.list` for nothing stored, an unknown string or any other type. The key is
  `adjust.presetsView`, not `adjust.presets.view`: collection headings store
  under `adjust.presets.<collection name>`, so a collection named "view"
  would have shared the key.
- `LibraryModel.presetsView`, `didSet` writes `defaultsKey`, initialized from
  `choice(stored: UserDefaults.standard.object(forKey:))` like
  `linksComparison`. One app-wide value (R3, A1): not per photo, per library
  or per collection. Nothing resets it.
- No animation on switching; the content below the control is replaced.
- Existing users, who see thumbnails today, will see the list on first launch
  after this ships (R2). The user guide says so (§11).

## 7. Rendering (R8)

`PresetGrid` owns the `.task(id: renderKey)` that renders thumbnails. In
list view it isn't built, so no render starts, and one running when the
person switches stops at its next `Task.isCancelled` check (the frame in
flight finishes). Switching back builds `PresetGrid`, whose task renders
after its 250 ms settle as it does today. `PresetPreviewModel` needs no
change: it keeps its small previews and session while the list is shown, so
switching back with the photo unchanged is instant. It re-renders when the
photo's key has changed, as it already does.

For AC7 add one counter to `PresetPreviewModel` (`debugRenderedCount`,
frames rendered since launch) for the debug script (§10).

## 8. Accessibility

- **Order.** The control is after Manage... in reading order, in every layout
  variant (set it explicitly if `ViewThatFits` changes the order).
- **Control.** One element, label "Presets view", two segments named
  Thumbnails and List, the chosen one selected. Confirm AppKit speaks the
  image descriptions of image-only segments; if it doesn't, return a Design
  question.
- **Rows.** Each is a button named for the preset (`setAccessibilityLabel(name)`,
  as `ImageTile` does) with `accessibilityValue` "Applied to this photo" when
  marked (the existing catalog string, used by the look-up table browser).
  Pressing the row applies. Group each collection's rows in a container
  labeled with the collection's name when that is cheap; not required.
- **Keyboard.** The control and each row are reachable with Full Keyboard
  Access like every other inspector button; Space or Return on a focused row
  applies. Left and right arrows move between the segments. A 40-row list is 40
  Tab stops, as 40 thumbnails are today; an arrow-key roving focus would be an
  improvement, outside this slice (R11, Non-goals).
- **Color.** The marker is a symbol plus color. The name stays in
  `labelColor`: not accent-colored text, which can't meet contrast with every
  accent color the user may pick.
- **Contrast and motion.** System fills and colors only, so Increase Contrast
  and Dark apply. Nothing animates, so Reduce Motion needs no path. No glass
  is used (the inspector pane is the system's).
- **Hover has no keyboard equivalent** (PRD non-goal); stated, not hidden.

## 9. Localization

Add to `Sources/PhotoUI/Resources/Localizable.xcstrings` by hand (the
`LocalizationTests` rule), each with a `comment`:

| Key | Use |
| --- | --- |
| `Presets view` | VoiceOver label of the view switch |
| `Thumbnails` | VoiceOver name of segment 0 |
| `List` | VoiceOver name of segment 1 |
| `Show presets as thumbnails` | tooltip of segment 0 |
| `Show presets as a list` | tooltip of segment 1 |

Reused: `Applied to this photo` (extend its comment to say the Presets list
uses it as VoiceOver's value, as well as the look-up table browser's tooltip),
`Apply`, `Manage Presets…` (with the real ellipsis character, as in the catalog
and the strings above in prose as three dots), `Collapse`, `Expand`.

Check before adding that `List` and `Thumbnails` aren't already keys with a
different comment; none was found on 2026-11-20. Sentence-style capitalization
for the tooltips, title-style for the segment names (HIG: segment labels).

## 10. Debug script

The inspector's glass panes don't snapshot in the current design
(`CLAUDE.md`), so checks use `buttons`, `hit`, `print`.

- `preset view list|thumbnails|print`: sets `model.presetsView` as the
  segment does, waits 600 ms, prints
  `debug-script: preset view <list|thumbnails> thumbnailRenders <N> rows <M> tiles <K>`
  (N is `debugRenderedCount`; rows and tiles count the visible
  `PresetRow`s and `ImageTile`s). AC2 and AC7 read this; the stored value is
  checked by relaunching with the same `--library-root` and printing again.
- `hover <x> <y>` and `hover end`: hit-tests the view at the point, and if it
  is an `ImageTile.HoverButton` (a tile or a row) calls a new
  `simulateHover(_ inside: Bool)` that does what `mouseEntered` and
  `mouseExited` do, so the real wiring runs, `previews.hover` and the 120 ms
  hold included. It prints `hover '<row name>' preview <on|off>`
  (`editor.isPreviewing`), after the hold for `end`. AC5 uses it with `print`
  for the History and undo counts. (`preset preview <name>` stays: it
  bypasses the rows.)
- `buttons` prints a segmented control's segments' accessibility labels, and
  for a row its accessibility value, so the marker and VoiceOver names show.
- `print presetsbar`: for the visible Presets button row, which variant is
  showing (1, 2 or 3), each control's frame, and `overlap` or `clear`. As
  the script can't set the inspector's width (as with `inspectorwidth`), it
  also prints each variant's needed width and the content width at the
  narrowest column (`InspectorMetrics.minimumColumnWidth` less its padding,
  less 17 pt with a legacy scroller), so the narrow case is checked without
  dragging.
- `print inspectorwidth` already covers the row: it must still say `fits`.

## 11. User guide

Terms the engineer writes (and the designer checks at review): the heading's
view switch is the **Presets view** control with **Thumbnails** and **List**;
the default is the list; the choice is kept; hovering shows the preset in
the loupe in both views; list view doesn't render pictures, so it is also
lighter on the photo; the check mark means the photo already has the
preset's settings; context menu **Apply** and **Manage Presets...**.
The sentence "The heading shows the focused photo with each preset, by
collection" is replaced, and the change of default is stated for people
used to thumbnails.

## 12. macOS 15 and the earlier design

No availability branch. On macOS 15 (and an app linked with an older SDK) the
segmented control, system fills and symbols draw in the earlier design; the
selected segment looks different but works the same. Both symbols exist on
macOS 15. Covered by CI only (the owner's standing ruling): no manual check
is asked for there.

## 13. Not changed

Catalog, migrations, stored edits, presets, rendering, goldens and
`PreviewCacheKey.currentPipelineVersion` (R12). `previewAdjustmentPreset`,
`endPreview` and `PresetPreviewModel.hover` (shared). Save, Import, Manage,
the manager sheet and Adjust > Apply Preset. Thumbnail view's look and
behavior (R2).

## 14. Tests and checks to expect

- PhotoCore: `PresetsViewChoice.choice(stored:)`: nothing stored, "list",
  "thumbnails", a garbage string and a number give `.list`, `.list`,
  `.thumbnails`, `.list`, `.list`.
- Debug script: AC2 (`preset view print` on a fresh `--library-root` and
  defaults domain, then after a choice and a relaunch), AC3 (`buttons` after
  expanding a collection in each view), AC4 (`click` on a row, then undo and
  History counts), AC5 and AC6 (`hover`), AC7 (`preset view` and its
  counter), AC8 (`buttons` shows the value before and after a slider change),
  AC9 (`buttons`, the segment labels).
- For a person at the bundle (the designer's `review.md` will number them
  M1...): the look of the row in Light, Dark and Increase Contrast (hover fill,
  marker, focus ring, 22 pt density); the control's look beside the push
  buttons; the inspector at its narrowest, dragged, with and without a
  legacy scroller; a real mouse sweep down a long list with the loupe watching;
  scrolling the list under a still pointer.

## 15. Design questions and PRD notes

**Design questions.** None open. One thing to verify while building, which
becomes a question only if it fails: that AppKit gives image-only segments
their VoiceOver names (§8).

**Requirements issues** (wording only, nothing blocks):

1. R1 and AC1 say "two icon-only buttons". The design is one two-segment
   control (§2.1), which is two segment-buttons as far as VoiceOver and the
   keyboard go. If the owner wants separate buttons, say so; the cost is the
   exclusivity glue and a both-off state.
2. AC6 says "while cropping or comparing, hover does what it does today".
   While comparing, the Adjust tab shows no Presets heading, so there is no
   hover to test; only cropping applies. Suggested rewording: "While cropping,
   hover does what it does today for thumbnails."
