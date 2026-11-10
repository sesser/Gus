# Edit history: design

Owner: apple-ui-designer. Date: 2026-11-09. Feature: `edit-history`
(PRD Approved: [`prd.md`](prd.md)).

**Inputs.** `prd.md`; `CLAUDE.md`; `docs/UI_REDESIGN.md` (UIR §1 window
anatomy, §3 sidebar, §4 inspector, §6 menus, §10 accessibility, §11 film
strip); `docs/features/ui-redesign/design.md` (command map §4, D-Q3 idle
rule). HIG areas applied: Sidebars, Inspectors, Menus, The menu bar,
Keyboards, Motion, Accessibility, Writing, Materials. I did not re-fetch the
live HIG pages for this document; where I rely on a HIG sentence I quote it
from the precedent documents above, and everything else is labeled judgment.

**Summary of rulings.**

| # | Ruling |
|---|---|
| H1 | The history lives in a **collapsible History panel at the bottom of the inspector column**, in the loupe only, not in the sidebar. The owner's sidebar preference is departed from (§2) |
| H2 | **Newest on top.** The current state is always row 1 (§4) |
| H3 | A row is label + time; the current state has a check mark and semibold label; one click reverts (§5, §6) |
| H4 | **View ▸ Show History / Hide History, ⌥⌘3** (§8) |
| H5 | The panel is absent in the grid and in review; for videos, offline masters and unreadable stacks it stays and says why (§6) |

## 1. Task and shape

The person is in the loupe, trying looks with the Adjust tab's sliders. They
want to glance at what they have done to this photo, and go back to a state
they liked, without losing the later states. The list is therefore
**companion material to the Adjust tab**: it is read and used while the
inspector is in use, and it must not take the photo's space.

```
┌ inspector column (loupe) ───────────┐
│ [ Info | Adjust ]                   │  pinned, as UIR §4
│ histogram                           │
│ Original            ⋯               │
│ ─ sections (AppKitScrollView) ────  │  gets shorter when History opens
│  ...                                │
│ ───────────────────────────────────│  1 pt separator
│ ▾ History                      12   │  28 pt header, disclosure
│ ✓ Exposure                  2:41 PM │  newest, semibold
│   Crop                      2:39 PM │
│   Revert to “Exposure”     Yesterday, 4:10 PM │
│   ...                  (scrolls)    │  220 pt cap
└─────────────────────────────────────┘
```

## 2. Placement (departing from the owner's preference)

**Ruling H1: a panel docked at the bottom of the inspector column, below
whichever tab is showing, collapsed by default. Not in the sidebar.**

The owner asked for a collapsed tab in the left sidebar that slides a panel
up. The idea is sound in two ways: a collapsed header that expands upward
costs nothing until used, and a panel with a scrolling list is the right
size of thing. I keep both. I depart from the *column*, for these reasons:

1. **The sidebar is for navigation between sources, and this is not a
   source.** HIG Sidebars: a sidebar is for navigating to top-level
   content; UIR §3 and RI-6 already ruled that this sidebar holds sources
   only. Selecting a source changes what the grid shows. Clicking a history
   entry changes one photo's pixels. Putting both in one list makes one
   column mean two things, and a person who learned "sidebar click = go
   there" gets an edit.
2. **Cause and effect would sit on opposite sides of the photo.** The
   sliders are in the right-hand inspector; the log of what the sliders did
   would be on the far left, with the whole photo between. Every glance
   costs a pointer trip across the window. Next to the sliders it costs
   none. (HIG Inspectors: show details and controls about the selected
   item beside the content.)
3. **The sidebar goes away exactly when the history is wanted.** Review
   mode hides it, and many people hide it in the loupe (⌃⌘S) to give the
   photo room. The inspector is where the person already is while editing.
4. **A bottom-docked panel in a sidebar collides with sidebar rules.** UIR
   §1 keeps actions out of a sidebar's bottom (HIG advises against it) and
   moves them to the toolbar. A panel growing from the sidebar's bottom
   edge would take height from the source list, which already scrolls with
   five sections, and on macOS 15 it would need a source-list material
   treatment of a table of rows that are not sources.
5. **Width.** The sidebar is 200 pt ideal; the inspector 300. A row of
   label plus time fits in 276 pt and not comfortably in 176.

Why not the alternatives:

| Option | Verdict |
|---|---|
| Third inspector tab (Info \| Adjust \| History) | Rejected as the primary placement: tabs are exclusive, so the list could not be seen while adjusting, and getting back to editing after a revert costs a second click. It is the fallback if the panel proves too cramped |
| Section heading inside the Adjust tab | Rejected: it scrolls away, and sits at the end of the longest list in the app |
| Toolbar item with a popover | Rejected as primary: it covers the photo, closes when the person works, and a toolbar item cannot show the list while the sliders move. It stays allowed as a palette-only item (§8) |
| Sheet or separate window | Rejected: modal for a glance; the HIG asks for less modality on the large display |

**If the owner still wants the sidebar.** It can be done: the same panel
(§3, unchanged) at the bottom of the sidebar column. The costs, so the
choice is informed: it is unreachable in review and with the sidebar hidden;
it takes height from the sources; it is narrower (the time must move to a
second line, so rows become 36 pt); it needs a menu path to show the sidebar
first (the item would show the sidebar, then the panel); and VoiceOver and
Tab order put the history before the photo, away from the Adjust controls
that produce its entries. I would still advise against it. Recorded as
D-Q1 for the owner to confirm or overrule.

**Coexistence with the inspector's existing content.**

- The panel shows in the loupe, in both tabs (Info and Adjust), whenever
  the loupe is open and not in review. It is the same photo's history either
  way. It is absent in the grid (the grid's inspector acts on a selection,
  and the history is of one photo; R12), absent in review, and not part of
  `ReviewLayout`.
- It **stays present** for videos, offline masters and unreadable stacks,
  with a one-line reason (§6), so the inspector's layout does not jump as
  the person moves between photos with the arrow keys. (The same reasoning
  as the caption's reserved star width, UIR §1.)
- The inspector's own show/hide (⌥⌘I, toolbar button) hides the panel with
  it. Show History shows the inspector first when it is hidden, the way
  Suggest Keywords does.

## 3. Anatomy and dimensions

| Element | Spec |
|---|---|
| Position | the bottom of the inspector column, full width, below the tab content. The tab content (pinned header and its `AppKitScrollView`) takes the remaining height |
| Separator | 1 pt, `NSColor.separatorColor`, above the header; none when the panel is not shown |
| Header | 28 pt high, the inspector's section-header grammar (UIR §4): `AppKitButton` with `.disclosure` bezel in a 16 pt slot, title "History" 13 pt semibold primary at x 20, and on the right the entry count (11 pt secondary, monospaced digits, hidden for 0 and for unavailable states). The whole header row is the hit area, not only the triangle (a Mac user clicks the title) |
| Body (expanded) | an `NSTableView` in an `NSScrollView`: one column, no header, no grid lines, no alternating rows, `selectionHighlightStyle = .regular`, overlay auto-hiding scroller. Row height 24 pt (above the 20 pt minimum hit area), full-width hit area |
| Heights | expanded body = clamp(40% of the inspector column's height, 96 pt, 192 pt), so the panel with its header is at most 220 pt: about eight rows on a 13" laptop. Not user-resizable in this version (judgment: a drag handle is a second resize affordance to explain, and eight rows with scrolling meets AC3; revisit if the owner finds it cramped) |
| Insets | 12 pt leading and trailing, like the inspector's padding. On macOS 26 the pane has rounded bottom corners: keep 12 pt below the last visible row so the list never meets the corner (HIG concentricity; Harmony) |
| Surface | none of its own. It draws on the inspector's surface, which on macOS 26 is the system pane and on macOS 15 the ordinary inspector background. No material, no custom fill, no fake blur. Scrolling rows are content and never glass (Liquid Glass rule: glass is for the controls layer; no glass on glass) |

**Why custom chrome is justified.** SwiftUI has no collapsible bottom pane
for an inspector. The parts are all system: an AppKit table view, a
disclosure button, a separator, a scroll view. The only custom behavior is
the fixed-height expand and collapse. `VSplitView` was considered; it
brings a draggable divider (not wanted, above) and no animated collapse.

**Why AppKit, not SwiftUI `List` or `ScrollView`.** CLAUDE.md: a SwiftUI
`ScrollView` under the toolbar swallowed clicks in the earlier design, and
the inspector runs under the toolbar. The panel is below the toolbar, but
the inspector column's click handling is the thing that broke, and a table
view gives row-level VoiceOver, keyboard navigation and reuse for 100 rows
without extra work. The header button is an `AppKitButton` (CLAUDE.md).

## 4. Order: newest on top (ruling H2)

**Recommendation: newest at the top.** Reasons:

1. **The current state is always row 1** and always in view. By PRD R6 and
   R8, every write, including a revert, records a new entry, so the current
   state is *always the newest entry*. With newest on top the marker sits
   at the scroll origin and never needs scrolling to.
2. **No scroll management.** A new entry inserts at the top of a list at
   offset 0. With newest at the bottom the list must be scrolled to the end
   on every edit and on every photo change, and must decide what to do when
   the person has scrolled up to read (scroll them back down, or leave a
   new entry out of sight). Both are bugs waiting to happen and neither is
   needed.
3. **The cap drops the oldest from the far end.** At 100 entries the
   dropped row falls off the bottom, out of sight and out of the way. With
   newest at the bottom, the oldest row vanishes from the top of what the
   person is reading.
4. **Convention.** The newest-first reading order is the one people already
   use for recent items (Activity's popover in this app keeps its newest
   messages first, UIR §1). A revert reads naturally as "this just
   happened" at the top.
5. **VoiceOver** starts on the most useful row, the current state, instead
   of reading 99 older rows first.

**What the alternative costs** (oldest on top, scrolled to the end): the
list reads like a story, top to bottom, which suits "how did I get here"
review; that is the only advantage. It costs the autoscroll logic above, a
current row that can be off-screen right after opening the panel until the
scroll lands (visible jump), and an unstable layout while the list loads
(rows arrive, then scroll). If the owner prefers it, the change is local
(reverse the data source, scroll to end after each load and insert); the
rest of this document does not depend on the order, except row 1 ↔ last row
wherever "top" is said.

## 5. Entry row

```
 ✓  Exposure                          2:41 PM
    Crop                              2:39 PM
    Revert to “Exposure”     Yesterday, 4:10 PM
```

| Element | Spec |
|---|---|
| Marker slot | 16 pt, leading. The current entry shows the SF Symbol `checkmark` (11 pt, primary). Other rows leave the slot empty so labels align. The marker is a shape, not color alone |
| Label | 11 pt, primary, tail truncation. The current entry is semibold. Text is the entry's label (the undo action name, PRD R2, A4), for example "Exposure", "Paste Adjustments", "Crop", "Reset All Adjustments", **"Undo Exposure"**, **"Redo Exposure"**, **"Revert to “Exposure”"** (the last three are what Edit shows after Undo, Redo, and for a revert; the engineer must make the undo name and the entry label the same string, PRD A4) |
| Time | 11 pt, secondary, trailing, monospaced digits, never truncated (the label gives way). Today: the short time ("2:41 PM"). Another day: the system's relative-aware form ("Yesterday, 4:10 PM", "Nov 2, 4:10 PM", with the year when it is not this year), from one `DateFormatter` with `doesRelativeDateFormatting` and the user's locale and 12/24-hour setting. Computed when the list loads and when it changes; no running timer, so a list left open overnight keeps "2:41 PM" until it reloads (acceptable; the tooltip is exact) |
| Tooltip | the full label, then the full date and time with seconds ("Nov 9, 2026 at 2:41:07 PM"), for truncation and for telling apart two "Exposure" rows |
| Hover / press | the system table's hover-free regular highlight when it is the keyboard cursor; no custom hover effect (UIR §11: no hover-dependent affordances; a Mac with touch has none) |
| Colors | semantic only (`labelColor`, `secondaryLabelColor`); the 4.5:1 floor holds in every appearance, and Increase Contrast strengthens the secondary color by itself. The panel is not in `Palette` because it needs no custom color |
| R16 | The "tiny summary" (Could) is not designed. If it ships, rows grow a 24-pt second line in secondary 10 pt; nothing here prevents it |

**Observation for the owner.** Because a revert records a new entry (R6),
the marker never moves to an older row: after a revert the photo's state
equals the chosen older entry, and the new top row ("Revert to …") records
that. This is correct and makes the list a complete log, but the marker
alone carries no information beyond "top row". The row label ("Revert to
“Exposure”") carries it. I considered also marking older entries whose
stack equals the current one and rejected it: it doubles the markers for a
rare state and needs a second symbol. Recorded, not a requirements issue.

## 6. Behavior and states

### Revert (H3)

- **Click** an entry that is not current: the photo goes to that entry's
  state immediately (the same path as an edit, saved once, one undo step
  named "Revert to “‹label›”", one new entry; PRD R6, R7). Click on the
  current entry does nothing (A5): no beep, no alert; it is already marked.
- **Feedback** (the photo is the main feedback, as with every edit):
  1. the loupe renders the state (live path, as undo does);
  2. the new row slides in at the top and the list scrolls to offset 0, so
     the marker and "Revert to …" are visible;
  3. VoiceOver says "Reverted to ‹label›" (§10);
  4. Edit ▸ Undo now reads "Undo Revert to “‹label›”".
  There is no confirmation: the action is reversible by Undo and loses
  nothing (HIG Alerts: no alert for what can be undone).
- **Keyboard focus after a revert** returns to the loupe
  (`.browserShouldTakeFocus`, the pattern text fields use), so the arrow
  keys go on moving between photos and a click in the list does not leave
  the person typing "right arrow" into a table.
- **Show Original (`\`)** is turned off by a revert, so the person sees
  the state they chose.
- **Open sessions.** During a **crop session** the rows are dimmed and not
  clickable (tooltip "Finish cropping to go back to an earlier state."),
  because a half-made crop is not a stack state and a revert would silently
  discard it. In a **mask** session (a selected mask, a brush stroke being
  painted) a revert does whatever Undo does today to that session; the
  engineer uses the same path, not a new rule.
- **Batch and other-photo writes** do not touch the list of the open photo
  unless they changed it (R10). The list reloads for the focused photo when
  focus moves (arrow keys, film strip click); the scroll position resets to
  the top, the expanded state is kept.

### States

| State | Header | Body |
|---|---|---|
| Loading | "History", no count | empty, no spinner and no text (D-Q3 idle rule: a word that flashes is noise; a list of 100 loads in a frame, and R15 requires it never delay the photo) |
| Empty (no entries yet) | "History", no count | two centered lines, secondary: **"No Edits Yet"** (11 pt semibold) and **"Each change you make to this photo is listed here."** (11 pt). A text pair, not a `ContentUnavailableView`: the body is 96 to 192 pt, and a symbol, title and description do not fit. The app's sidebar uses the same secondary-line empty states (UIR §3) |
| Entries | "History" and the count | the list |
| Video | "History", no count | centered secondary line: **"Videos have no edit history."** |
| Offline master | "History", no count | **"History is unavailable while the original is offline."** (a voice that matches the Adjust tab's "Connect its volume…") |
| Unreadable stack | "History", no count | **"History is unavailable. This version can't read this photo's edits."** The stored stack and history are not touched (R13) |
| Grid | panel absent | not shown (R12) |
| Review | panel absent | not shown (R12); leaving review brings it back in its remembered state |
| Inspector hidden | panel absent with it | |

The header stays enabled and expandable in the video, offline and
unreadable states so the reason can be read; the panel's presence never
depends on the photo (§2).

Plain secondary text is selectable by no one and has no actions. The
reasons are sentences, so they are sentence-style (P5).

### Expand and collapse

- Collapsed is the default. The state is remembered across launches (§12).
  Opening the loupe does not expand it.
- Expanding: the body grows upward from the header, 0.25 s ease-out; the tab
  content above shortens by the same amount (its scroll view's frame
  changes; its content is not re-laid-out). Collapsing: 0.2 s ease-in. The
  same timings as the film strip (UIR §11), so panels in this window move
  alike. The list's own content is pinned to the header edge so rows are
  revealed, not stretched.
- **Reduce Motion:** both happen at once, with no animation, and row
  insertions and the scroll to the top are immediate (the system's
  `accessibilityDisplayShouldReduceMotion`). Motion is never needed to
  understand state: the check mark and the order carry it.
- Interruptible: a click during an animation retargets it from where it is.
- Row insertion on a new entry: `NSTableView` slide-down insertion, 0.2 s,
  skipped with Reduce Motion.

## 7. macOS 26 and the earlier design

- **macOS 26 (linked with the 26 SDK).** The inspector is the system pane.
  The panel is content inside it: no glass of its own, no bar background to
  remove, nothing to tint. The header is not a toolbar item. The one
  Liquid Glass concern is the pane's rounded bottom corners: the 12 pt
  inset in §3. The loupe's surround and the film strip are unaffected.
  `snapshot` leaves the glass panes blank (CLAUDE.md), so this panel is
  checked with `print`, `buttons` and `accessibility`, and by hand.
- **Earlier design (linked with an older SDK, macOS 15 minimum).** The same
  panel on the ordinary inspector background. Everything used exists on 15:
  `NSTableView`, `NSButton` `.disclosure` bezel, the separator, SF Symbol
  `checkmark`. No change is needed for the earlier design. The AppKit-only
  rule above is already the earlier design's rule.
- Appearance: the library window is dark through `preferredColorScheme`;
  only semantic colors are used, so Light and Increase Contrast follow.

## 8. Menu bar, key, toolbar (H4)

**View ▸ Show History / Hide History, ⌥⌘3** (new). Placed after Info /
Adjust (⌥⌘1 / ⌥⌘2) and before Show Film Strip, grouping the inspector items.
Not a checkmark item: the title follows state, as for Show Film Strip and
Show Inspector.

| Aspect | Spec |
|---|---|
| Title | "Hide History" while the panel is shown and expanded; otherwise "Show History" |
| Action | Show: shows the inspector if hidden, expands the panel, moves keyboard focus into the list so the arrows work (the person asked for the list, and Full Keyboard Access has no other way in). Hide: collapses it and returns focus to the loupe. It never changes the current tab |
| Enabled | in the loupe, not reviewing, no sheet open, wherever focus is in the key library window (a Command-key item, UIR §6; no bare-key handling needed). Dimmed in the grid and in review |
| Key | ⌥⌘3. Judgment: the pane items use Option-Command plus one character (⌥⌘I, ⌥⌘T, ⌥⌘B, ⌥⌘1, ⌥⌘2). It is free in this app (`LibraryCommands` has no ⌥⌘3) and on every keyboard layout, not a system key (Screenshot is ⇧⌘3, unrelated to Option-Command). I rejected: **⌘Y** (PRD non-goal; also Safari's "History" key, and misread as redo), **⌥⌘H** (Hide Others), **⌥⌘Y** (one letter from ⌘Y, same confusion) |
| ⇧⌘Z | stays redo, ⌘Z stays undo; no ⌘Y anywhere |
| Toolbar | not in the default set. A palette-only item, **History** (`clock.arrow.circlepath`), with the same title, enablement and state as the menu item (UIR §5 P2). Optional: the engineer may leave it out; the menu item and the panel header are the required paths |
| Revert | has **no menu item**. It is a choice among up to 100 parameter values, like a slider value (ui-redesign N10: not commands in menus); the list is the command surface and is fully reachable by keyboard and VoiceOver. Judgment, not a HIG rule |
| Context menu | none on a row: its only item would be the click's action |
| Edit ▸ Undo / Redo | unchanged (the window's undo manager); a revert is named "Revert to “‹label›”" |

The command map (ui-redesign §4) gains one row: Show / Hide History | View |
⌥⌘3 | palette History | — | panel header | loupe, not reviewing.

## 9. Keyboard

The list is reachable by Tab (inspector order, last in the inspector) and by
⌥⌘3. It is a single Tab stop; its rows are moved among by arrows.

| Key | In the list |
|---|---|
| Up / Down | move the row cursor (the table's selection highlight) without reverting; the table scrolls to keep it visible |
| Home / End, Page Up / Down | first (newest) / last, a page |
| Return or Space | revert to the row's entry (as a click); then focus returns to the loupe |
| Esc | return focus to the loupe and nothing else. Esc in the list does not leave the loupe for the grid: it backs out one level, the first level being the list |
| Tab / ⇧Tab | next / previous control as usual |
| Type-to-select | off |

The row cursor is only visible while the list has focus (a regular
selection highlight, accent when key, gray otherwise). It starts on the
current entry when the list gains focus. It is a cursor, not a state:
**the current state is the check mark**, so moving the cursor changes
nothing in the photo. (A native table ties selection to action; here it is
deliberately not, because arrow keys that revert would make browsing the
list rewrite the photo, and R6 logs every revert.)

The disclosure header is in the Tab loop before the list; Space or Return
on it expands or collapses. With Full Keyboard Access every row and the
header are reachable.

Culling keys (0-5, P, X, `Z`, `\`, `F`, `C`) and the loupe's arrows are not
handled while the list has focus: they belong to the first responder, so the
list never changes ratings by accident. Esc is the way back.

## 10. VoiceOver

- **Header**: the disclosure button, label "History", value "collapsed" or
  "expanded", plus the count as a hint: "12 entries" (plural string). It is
  a button with the standard expand/collapse action.
- **List**: role table/list with the label **"Edit History"**; rows in
  display order (newest first), so VoiceOver reads the current state first.
- **Row**: label = the entry's label; value = the time spoken in full
  ("Today at 2:41 PM", from the same formatter's long style); the current
  entry's value adds ", current state". Default action (VO-Space,
  `accessibilityPerformPress`) is **"Revert to This State"**, a no-op on the
  current row. The row is not "selected" for VoiceOver (the cursor is not a
  state).
- **After a revert** the app posts a high-priority announcement: "Reverted
  to ‹label›" (reusing the culling announcements' approach, UIR §10, so a
  fast run speaks only the latest). After a revert from the list focus moves
  to the loupe, whose canvas value change is also posted; the announcement
  covers what changed.
- **After any other edit** the list announces nothing: edits already
  announce through the controls.
- **Unavailable states**: the reason text is one static-text element, read
  when the list is reached.
- **Dimmed rows** (crop session): `isEnabled` false, hint "Finish cropping
  to go back to an earlier state."
- The panel is not in the tree when absent (grid, review, hidden inspector).
- Reading order: the Adjust/Info controls, then the History header and list.

## 11. Strings (keys in `Localizable.xcstrings`)

No brand name appears. Added by hand; `LocalizationTests` must pass.

- Menu and toolbar: "Show History"; "Hide History"; "History" (header,
  palette item; its catalog comment names both uses).
- Count and VoiceOver (plural): "%lld entries" (one: "%lld entry").
- States: "No Edits Yet"; "Each change you make to this photo is listed
  here."; "Videos have no edit history."; "History is unavailable while the
  original is offline."; "History is unavailable. This version can't read
  this photo's edits."
- List accessibility: "Edit History" (table label); "Revert to This State"
  (row action); "current state" (value suffix, used as ", current state");
  "Reverted to %@" (announcement); "Finish cropping to go back to an
  earlier state." (tooltip and hint).
- Entry labels come from the undo action names. Added, because they are new
  undo actions: "Revert to “%@”" (the revert's undo name and entry label),
  plus "Undo %@" and "Redo %@" for entries recorded by undo and redo (the
  Edit menu's own "Undo ‹name›" text is the system's; the entry label is
  this app's string and must not be a concatenation done at display time, or
  it cannot be localized). Existing names ("Exposure", "Paste Adjustments",
  "Crop", "Reset All Adjustments"…) are reused unchanged (PRD A4).
- Time text is formatted by the system's `DateFormatter`, not catalog
  strings.
- Sentence-style for descriptions and states, title-style for the menu
  items and the header (P5).

The Settings and menu terms in `docs/USER_GUIDE.md` that change: the View
menu list (Show / Hide History, ⌥⌘3) and a History paragraph under Adjust or
the loupe; the engineer updates it, and review checks these terms.

## 12. Persistence and implementation notes

- **Preference:** `inspector.showsHistory` in `UserDefaults` (Bool, false
  when absent), on `LibraryModel` beside `showsInspector`. Not part of
  `ReviewLayout`: review hides the panel without changing it.
- **Menu state:** `LibraryMenuContext` gains `showsHistory` and
  `canShowHistory` (loupe, not reviewing, no sheet). Never a model passed
  to `Commands`; focused values, as everywhere.
- **Where:** a new `HistoryPanel` in `Sources/PhotoApp/Views/` (or
  `Loupe/`), hosted by the inspector column below `InspectorView`'s tab
  content. The tab content keeps its `AppKitScrollView`; the panel is an
  `NSViewRepresentable` over the `NSTableView`, the header an
  `AppKitButton`. The entry data and the 100 cap are PhotoCore and the
  catalog (not UI); the UI reads a `[HistoryEntry]` for the focused version
  and its current marker (always the newest).
- **Loading:** the list reads entries off the main thread for the focused
  version and never delays the photo (R15); the table holds up to 100 rows,
  so rows are view-recycled, not virtualized further. Entries need only the
  label, time and id for display; a revert uses the stored stack by id.
- **Revert** goes through the same write path as an edit and the write chain
  (CLAUDE.md `persist`), one undo group, one new entry (R6, R7). Click and
  Return share one function. A stack that can't be read or written never
  reaches it (rows are not shown; R13).
- **Tests:** pure rule for panel state (grid / review / video / offline /
  unreadable / empty / entries) and for the row's time text and a11y value;
  `LocalizationTests`. Debug script (the engineer adds commands): `history`
  to print the panel state and rows, `history revert N`, and
  `menupress "Show History"`; the panel is checked with `print` and
  `accessibility`, not `snapshot` (glass pane).
- **README** is not affected.

## 13. Review checklist (for step 4)

| # | Requirement | How checked |
|---|---|---|
| D1 | Panel at the inspector's bottom, collapsed by default, in the loupe only; none in the grid or review | debug script `print`; manual |
| D2 | Newest on top; check mark and semibold on row 1 | `history` print; AC4 |
| D3 | Row: label, time (today short; other days relative), tooltip with seconds | unit test + manual |
| D4 | Click reverts; current-row click does nothing; focus returns to loupe; Show Original off | AC5, AC7; manual |
| D5 | Crop session dims the rows | manual |
| D6 | States: empty, video, offline, unreadable text | debug script; AC12, AC13 |
| D7 | Expand/collapse animation 0.25 / 0.2 s; none with Reduce Motion | manual M-series |
| D8 | View ▸ Show / Hide History ⌥⌘3; dimmed in grid and review; shows the inspector | `menuitems History`, `menukey` |
| D9 | Keyboard: arrows move cursor only; Return/Space revert; Esc returns focus | manual; AC14 |
| D10 | VoiceOver: header, "Edit History" list, row label and value, announcement | `accessibility`; manual AC14 |
| D11 | Strings in the catalog, no brand | `LocalizationTests`, grep |
| D12 | No SwiftUI `ScrollView`/`List` in the panel; header is an `AppKitButton` | code read |
| D13 | Contrast and Increase Contrast; no glass on the panel | manual |
| D14 | Terms in `docs/USER_GUIDE.md` | read |

## 14. Design questions (owner rulings, 2026-11-09)

**D-Q1 (placement): closed.** The owner confirmed the inspector-bottom
panel (§2), not the sidebar.

**D-Q2 (order): closed.** The owner confirmed newest on top (§4).

## 15. Requirements issues (for the product manager)

**RI-1 (low, information; proceed unless ruled otherwise).** With no seed
entry (owner ruling 2, A1) the list begins *after* the first recorded
change, so the photo's unedited state is not a row. A person who wants the
unedited photo back from the list cannot click it; the paths are Reset All
Adjustments (itself an entry, so revertible), Undo, or the Original toggle
for viewing. If the owner expects "go back to the very start" from the
list, the PRD needs a seed entry or an explicit non-goal. My default: leave
as ruled and add one sentence to the user guide. No design change needed
either way.

**RI-2 (low).** R2 and A4 label entries with the undo action name. The undo
names for the revert, and for undo and redo entries (§5, §11), do not exist
yet, and whether every edit route already names its undo step (AC1 expects
"Exposure" and "Crop") is for the engineer to confirm. The PRD may want to
say who owns those strings; here I specified them.
