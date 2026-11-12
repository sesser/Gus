Issue: #63

# Side by side comparison: design

Status: Complete (apple-ui-designer, 2026-11-11). Requirements issues RI-1 to
RI-3 are open with the product manager; the design works with the default
recommended for each, so implementation need not wait on them. The new
bare keys (§4) need the owner's OK, as earlier new keys had (UI_REDESIGN
decision 13).

Against `prd.md` (approved 2026-11-11). Builds on `docs/UI_REDESIGN.md`:
§1 (loupe surround, caption), §2 (review), §6 (menu bar and bare keys),
§7 (context menus), §10 (accessibility) and §11 (film strip). Where this
file is silent, those rules apply unchanged.

## 1. Model: comparison is a state of the loupe

Comparison is not a third browser mode. It is the loupe showing two photos
(`mode == .loupe`, plus a comparison state holding the left and right
version IDs, which side is active, and whether the views are linked). It
can be on in review too.

Why: the loupe already owns the keys, zoom, the film strip, the caption and
review. Comparing is "the loupe, twice", and every existing loupe rule
(Esc backs out one level, Return goes to the grid, culling goes to the
photo on screen) keeps its meaning. A third mode would need a third answer
to each of them. (HIG Consistency.)

- **Active photo = the focused photo.** `focusIndex` follows the active
  side, so everything that already targets "the loupe's photo" (culling,
  menus, the Info tab, the window title, undo names) targets the active
  photo with no second rule. **Every command acts on the active photo
  only**, except the comparison commands themselves (§4).
- **Selection** while comparing is the two photos on screen, focus on the
  active one. Leaving comparison leaves that selection, so Show Grid
  afterwards shows the pair still selected (ready for Add to Album, say).
  When nobody walked a side (§6), that is exactly the selection the
  comparison started from. See RI-1.
- **Versions, not images.** The state holds version IDs, so comparing two
  versions of one master (#62) needs no change in this design, only in the
  entry rule that today refuses one master twice (§3).
- **Two panes is the slice (R9 is a Could).** Panes are indexed (0 left,
  1 right) and the active marker, captions, keys and VoiceOver are written
  per pane, so three or four at fit later is a layout change, not a new
  model. The switch key (§4) cycles, so it scales.

## 2. Anatomy

```
┌ loupe (content column) ─────────────────────────────────────────────────┐
│┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐                                       │
│╎ ┌──────────────────────────┐   ╎ ┌───────────────────────────┐         │  4 pt gutter round each pane;
│╎ │                          │   ╎ │                           │         │  the active pane's ring is
│╎ │   left photo (active)    │   ╎ │   right photo             │         │  drawn in its gutter
│╎ │   fitted within 24 pt    │   ╎ │                           │         │
│╎ └──────────────────────────┘   ╎ └───────────────────────────┘         │
│└╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘                                       │
│                                   ━━━━                                  │  film strip handle
│ ▢ ▢ ▢ ▢ ▢ ▢ ▢ [▣] ▣ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢                                     │  strip, full width
│ DSC00231 · 12 of 87  ★★★ ⚑ ● Red  [🔗] DSC00232  ★★ ● Red   Filtered [▭]│  caption row, 28 pt
└─────────────────────────────────────────────────────────────────────────┘
```

Top to bottom, as in the single loupe (UI_REDESIGN §11 stacking): the
panes, the film strip, the caption row at the bottom edge. Everything
draws on `Palette.loupeBackground`: no bar, divider, material or glass.
The panes and the strip are content; Liquid Glass belongs to the toolbar,
sidebar and inspector only (UI_REDESIGN decision 2; HIG Materials).

| Element | Spec |
|---|---|
| Panes | Two equal columns across the loupe's width, side by side at every window width (§8). Each is a loupe canvas (scroll view, image view) of its own, with the single loupe's 24 pt fit margin inside it |
| Gutter | 4 pt round every pane's canvas, active or not, so making a pane active never moves anything. Between the two canvases: 8 pt (two gutters). At fit the photos are 56 pt apart (8 + 2 × 24) |
| Seam | Nothing drawn: the surround is the separator. A divider line would read as a draggable split view, and the panes are not resizable |
| Corners | Canvases are clipped to radius 4; the ring (below) has radius 8 on its outer edge, so the two are concentric (8 − 4 pt gutter = 4). HIG Harmony |
| Inactive pane | Drawn exactly like the active one, minus the ring. **Never dimmed, tinted or blurred**: the person is judging exposure and color, and any treatment of the inactive photo would bias that judgment |
| Entering | The single loupe's photo refits into the left pane (the loupe's existing 0.15 s fit animation) while the right pane's photo fades in (0.15 s). Reduce Motion: both appear at once |
| Leaving | The active photo refits to the whole loupe, animated the same way; the other pane disappears. Reduce Motion: at once |

## 3. Entering

### Which two photos

| Where | What is compared | Left / right | Active |
|---|---|---|---|
| Grid, two items selected | Those two | Source order: the earlier one left, so the panes match the grid | The grid's focused photo if it is one of the two, else the left |
| Grid, one item selected | The focused photo and its **partner** (below) | Focused left, partner right | Left |
| Loupe (photo or video loupe) | The loupe's photo and its partner | Loupe photo left, partner right | Left |
| Grid, 0 or 3+ selected | Nothing: the command is dimmed | | |

Active starts on the photo the keys acted on a moment ago, so entering
comparison never changes what the next culling key hits (HIG: user
control; predictability).

**Partner:** the photo this one was last compared with, if that happened
in this loupe session and it is still in the source and can be compared;
otherwise the next photo in the source that can be compared; at the end of
the source, the previous one. So `S` (§4) toggles between the single
loupe and the same pair, and an accidental `S` costs one more `S`.

"Choosing a second photo" from the loupe (R2) is: enter comparison (the
partner appears), then walk the right side with the arrows or click any
film strip thumbnail to put it there (§6, §7). See RI-2.

### What can be compared (AC6)

A photo can be compared when it is a still image whose original is online.
Videos and offline photos cannot (PRD Users and scenarios). A RAW+JPEG pair
shown as one item is one photo and compares like any other; for the two
halves of one pair shown as two items see RI-3.

The command is **dimmed** only for counts (0 or 3+ selected; a source with
one item), where there is nothing to explain (HIG Menus: dim unavailable
items). With the right count, it is **enabled**, and if a photo cannot be
compared, choosing it does not enter comparison and shows a window-modal
alert on the library window (`WindowModal`), because the person explicitly
asked for something that did not happen and the reason is not visible
anywhere (HIG Alerts). An Activity message would not do: review mode hides
the toolbar, and the Activity item appears only as an icon.

| Case | Alert title | Informative text |
|---|---|---|
| One of them is a video | Can’t Compare These Photos | “‹name›” is a video. Only photos can be compared. |
| One of them is offline | Can’t Compare These Photos | The original of “‹name›” is offline. Connect “‹volume›” to compare it. |
| Both fail | Can’t Compare These Photos | the first reason that applies, for the first photo |
| Loupe or one selected, no partner can be compared | Can’t Compare This Photo | There’s no other photo in “‹source›” that can be compared with it. |
| Halves of one RAW+JPEG pair (RI-3, recommended) | Can’t Compare These Photos | “‹raw›” and “‹jpeg›” are the RAW and JPEG files of one photo. |

One button, **OK** (default, Return and Esc). No beep in addition: the
alert is the feedback.

Entering also, like entering review: turns Show Original off, hides the
sharpening and fringe maps, and cancels a fringe pick. Compare is
**dimmed during a crop session**, which holds unsaved work; finish or
cancel it first.

## 4. Menu bar, keys and context menus

### Keys

Bare keys, like `F`, `Z`, `C` and the culling keys: shown in the menus,
handled by the loupe and grid first, enabled only while the grid, loupe or
video loupe has the keyboard (UI_REDESIGN §6). Checked against the
CullingKeymap, NavigationKey, the loupe's handler (`\`, `C`, `-`, `=`) and
`LibraryCommands`: neither letter is taken, bare or as a menu key.

| Key | Item | Why this key |
|---|---|---|
| **S** | View ▸ Compare Side by Side / Stop Comparing | "S" for side by side, the words in its title. A bare key because it is a view mode entered from the grid and the loupe, like `F` for review |
| **A** | View ▸ Switch to Right Photo / Switch to Left Photo | "A" for active. One key, no modifier: switching is the most frequent comparison action (rate one, switch, rate the other), so it gets a single key. It **cycles** to the next pane, so it scales to R9 |

Rejected, and why:

- **⌘← / ⌘→** (spatial, appealing): reserved by the system for switching
  the keyboard layout between Roman and system scripts (HIG Keyboards,
  standard shortcuts). Never use them.
- **Tab / ⇧Tab**: the window's key-view loop (sidebar → content →
  inspector, UI_REDESIGN §10) and Full Keyboard Access. Consuming Tab in
  the loupe would trap keyboard users in the content column.
- **⌃ arrows**: Mission Control and the standard "move focus within a
  view"; the HIG says to avoid Control.
- **⌥← / ⌥→**: possible, but the HIG keeps Option for less common
  commands, and a chord for the most frequent action is slower than one
  key.
- **Plain ← / →**: kept for walking the active side (§6), which is what
  they do in the loupe now and what R6 asks for.
- **⌥⌘C, ⇧⌘-anything with C**: adds modifiers to Copy / Copy Adjustments
  for an unrelated command (HIG Keyboards).

Link Zoom and Position gets **no shortcut**: it is rarely changed, and the
HIG asks for custom shortcuts only for frequent commands. Full Keyboard
Access reaches it in the View menu.

`A` and `S` are neighbors on a QWERTY keyboard. An accidental `A` only
switches sides (visible, harmless); an accidental `S` leaves comparison and
the next `S` brings the same pair back (§3, partner).

### View menu

After Enter / Exit Review (UI_REDESIGN §6), as a group:

| Item | Key | Enabled | Title |
|---|---|---|---|
| Compare Side by Side / Stop Comparing | S | by key (§6 of UI_REDESIGN): grid with 1 or 2 selected; loupe or video loupe with 2+ items in the source; comparing. Dimmed while cropping | follows state |
| Switch to Right Photo / Switch to Left Photo | A | by key, while comparing | names the side it will make active |
| Link Zoom and Position | none | while comparing, window key (a menu-only item, like Group RAW+JPEG Pairs) | checkmark toggle |

Existing items while comparing:

| Item | While comparing |
|---|---|
| Zoom to 100% / Zoom to Fit `Z`, Zoom In / Zoom Out ⌘= ⌘−, the toolbar's Fit / 100% | act on the active pane (and the other one too while linked, §5). Titles and the toolbar's segment follow the active pane |
| Enter / Exit Review `F` | as now; comparison stays on through it |
| Show Grid ⌘↩ (and Return, Space, double-click on a pane) | ends comparison and review, shows the grid, as "anything that shows the grid" does now |
| Show / Hide Film Strip ⌥⌘B | as now (§7) |
| Show Original `\`, Show / Hide History ⌥⌘3 | dimmed (non-goals: before/after, editing) |
| Photo ▸ Rating, Flag, Color Label, Advance After Rating | the active photo (§6 for Advance) |
| Add Keywords… ⌘K, Suggest Keywords, Add to Album, Export…, Show in Finder, RAW+JPEG Pair, Copy Adjustments | the active photo. Not edits of the image, so allowed |
| Remove from Album ⌫, Remove from Library… ⌘⌫ | **dimmed**: they take a compared photo out from under the comparison. Stop comparing (S) first |
| Adjust menu (Paste, presets, Auto, Reset All, Crop `C`, Rotate, masks, maps, Save as Preset) | dimmed (non-goal: no editing while comparing). Import Presets, Manage Presets and the look-up table items stay, as they edit no photo |

### Context menus (HIG Context menus: leave out what can't act)

| Target | Change |
|---|---|
| Grid photos | **Compare Side by Side** after Open in Loupe, when 1 or 2 items are selected |
| Loupe | **Compare Side by Side** after Zoom to 100% / Zoom to Fit |
| Video loupe | **Compare Side by Side** after Play / Pause (choosing it shows the video alert, §3) |
| A comparison pane | Right-click first makes that pane active (as a grid right-click selects). Then: the loupe menu's photo items for the active photo (culling, keywords, albums, Copy Adjustments, Export…, Show in Finder, RAW+JPEG Pair) · Zoom In / Zoom Out · Zoom to 100% / Zoom to Fit · Link Zoom and Position (checkmark) · Stop Comparing. No adjust items, no Remove items |

### Toolbar

One palette-only item (not shown by default; UI_REDESIGN §5), **Compare**:
a toggle (`.toggleStyle(.button)`, bezel on while comparing, like Crop and
Original), symbol `rectangle.split.2x1`, enabled as the menu item is,
tooltip "Compare two photos side by side". Confirm the symbol resolves on
macOS 15 in a test (`NSImage(systemSymbolName:)`); if it does not, use
`square.split.2x1` only if Original is not in the toolbar, else
`rectangle.split.3x1`. Not a third segment in Grid | Loupe: the default
toolbar is already full on a 13" display, and comparison is a state of the
loupe, not a peer of it. The Grid | Loupe control shows Loupe while
comparing.

## 5. Zoom and pan, linked and unlinked (R4, AC3)

**Linked (the default):** both panes always show the same place at the same
scale.

| Gesture or command, on either pane | Linked result |
|---|---|
| Click on the **active** pane, `Z`, the toolbar's Fit / 100% | Both go to 100% (each at one photo pixel per device pixel, as the loupe does) centered on the same unit point (the clicked point; the active pane's center for keys), or both to fit |
| ⌘= / ⌘−, Option-scroll, pinch | Both take the same magnification; at the low end each stops at its own fit |
| Drag, scroll, scroller | The other pane's visible center goes to the same unit point (x and y as fractions of the photo), clamped to its own bounds |
| A side walks to another photo (§6) | The new photo opens at the other pane's magnification and unit center, so walking a burst at 100% stays on the face |

Unit coordinates make same-size frames (the usual burst) line up pixel for
pixel, and keep differently sized photos on the same relative point (AC3
wording). Follow per frame, with no animation, during a drag or scroll
(direct manipulation); the 0.15 s animation only where the loupe animates
now (click, `Z`, steps).

**Unlinked:** each pane zooms and pans alone. A newly walked photo opens at
fit.

**Relinking:** the inactive pane jumps to the active pane's magnification
and unit center (0.15 s; at once with Reduce Motion). The active pane is
the one the person is working in, so it leads.

**Pointer and activation (HIG Pointing devices; Mac click-to-activate
convention):** a mouse-down on the inactive pane makes it active.

- A click there does only that: it does not also zoom, as a first click in
  an inactive window brings it forward without acting. The next click
  zooms.
- A drag that starts there makes it active and pans.
- Scrolling, Option-scrolling and pinching act on the pane under the
  pointer without changing the active side, as scrolling an inactive
  window does not activate it.
- A double-click on either pane shows the grid, as in the single loupe.

**The switch:** View ▸ Link Zoom and Position (checkmark), the pane context
menu, and a toggle at the seam of the caption row (§9). Remembered across
launches (`UserDefaults`, `compare.linksViews`, true when absent). The
owner's default is linked (PRD decision 4); keeping a person's choice is
assumed, not specified, and costs nothing if they never change it.

## 6. The active photo (R3)

### Marker

| Aspect | Spec |
|---|---|
| Ring | A rounded rectangle in the active pane's 4 pt gutter: 2 pt wide (3 pt with Increase Contrast; `PaletteSpec.selectedBorderWidth`), outer radius 8, in the accent color the grid and film strip use for "this photo" (one look, one meaning; UI_REDESIGN §11) |
| Window not key | The ring turns neutral (`NSColor.secondaryLabelColor`), as selections do in inactive windows, so the key window stays obvious |
| Not color alone | The ring is there or not there; its shape, not its hue, carries the state. The active caption's name is also primary and semibold, the other's secondary and regular (§9) |
| Never | No dimming of the other photo, no badge or label over either photo, nothing on the photo itself (UI_REDESIGN decision 2: the photo never sits under chrome) |
| Changing sides | The ring moves at once, no animation: state, not motion, and a fast `A`-rate-`A` run must never show a ring in between |

### Switching and walking

- `A` (§4) or a click on a pane makes it active. VoiceOver hears it (§10).
- **Walking (R6):** ← → (and ↑ ↓, which equal them in the loupe now),
  Home and End move **the active side** through the source, as they move
  the single loupe. The other side stays. Walking skips photos that can't
  be compared (videos, offline) and the photo on the other side, so a side
  never lands on something it can't show and the two sides are never the
  same photo. At either end, the key does nothing, as in the loupe.
- **Advance After Rating** moves the active side to the next photo it can
  show, by the same rule, after the culling action, with the combined
  announcement the loupe already makes. This is the "reject the weaker one,
  bring in the next" loop of the PRD's primary scenario.
- Culling keys, undo and redo act as in the loupe, on the active photo.
  Both captions update from the model (an undo may change the inactive
  photo; its caption shows it).
- **Filters:** a photo that stops matching the filter after a culling key
  stays in place until the filter changes, as it does now in the loupe
  (USER_GUIDE), so rejecting never pulls a photo out of the comparison.

### When a compared photo goes away

- Its original goes offline mid-comparison: it stays, shows its cached
  preview and the Offline badge in its caption, and its 100% falls back as
  the loupe's does now.
- It leaves the source (the sidebar source changes, another process
  removes it, a reload drops it): comparison ends, and the loupe shows the
  remaining photo alone; if neither remains, the loupe behaves as it does
  now when its photo goes.

## 7. Film strip while comparing

The strip stays (unless review hides it, unchanged), one strip across the
full width under both panes. It still mirrors what the keys do, and the
keys now walk the active side, so:

| Aspect | Spec |
|---|---|
| Centered on | The active photo. Recentering rules unchanged (UI_REDESIGN §11), with "focus change" now including a change of active side |
| Active photo's cell | Unchanged focused look: `Palette.cellSelected` fill and the accent border |
| Other compared photo's cell | `Palette.cellSelected` fill, **no** border: "on screen, not active". Fill is a luminance step, not a hue, and the border is the distinction |
| Click a cell | Puts that photo in the **active** side, as walking does (link rules apply, §5) |
| Click the other side's cell | Makes that side active (never the same photo twice) |
| Click the active cell | Nothing, as now |
| Click a video or offline cell | Nothing changes; `NSSound.beep()`, the system's "can't do that" for a direct action, since the cell's marks already say why |
| Tooltip | Unchanged |
| VoiceOver | Active cell `isAccessibilitySelected` (as now); both compared cells add "left photo" or "right photo" to their value. Press does what a click does, then the walk announcement (§10) |

No new strip controls, no multi-selection, no context menu: §11 decision 6
stands (see RI-2 for why this is enough for R2).

## 8. Narrow windows

Panes stay **side by side at every width**. Considered and rejected:
stacking top and bottom when the loupe is narrow. On a 13" laptop with
both panes shown (about 950 × 630 pt of loupe under the toolbar, strip and
caption), side by side gives a 3:2 landscape photo about 427 × 285 pt each,
stacked about 400 × 267: no better, and switching layout during a window
resize would move both photos and break "left" and "right" in the menus.

- With sidebar and inspector shown on a 13" display, each pane is about
  470 pt wide: both photos usable at fit, and 100% shows a 430 pt wide
  piece of each, enough for a face. That meets the PRD edge case.
- **Review (`F`)** is the answer for more room: it hides both panes and
  goes full screen (about 735 pt per pane on a 13" display), and
  comparison works in it unchanged. The user guide says so.
- Entering comparison never hides the sidebar or inspector by itself: the
  window's layout is the person's (HIG: Windows; user control).
- The film strip's 25% height cap and steps are unchanged.
- The caption row degrades in a fixed order (§9).

## 9. Caption row (R7)

One 28 pt row at the bottom edge, as now, split at the panes' seam: a
caption per pane, each aligned to its pane, with the link toggle centered
on the seam.

| Part | Spec |
|---|---|
| Name | Leading in each caption: the file name (in the single loupe it is the window title, which can't show two). Active pane: `.primary`, semibold; other: `.secondary`, regular. 11 pt (`.subheadline`, as the caption is now) |
| Position | After the name, " · 12 of 87", monospaced digits, secondary |
| Marks | `CullingMarks` (stars with reserved width, flag, label dot with its name), centered in the pane's caption |
| Badges | Trailing: HDR, Offline per photo. Filtered (about the source) once, in the right caption only. Original, maps and machine-learning badges can't occur (§3, §4) |
| Film strip toggle | Unchanged, at the right caption's trailing end; hidden in review |
| Link toggle | Centered on the seam: SwiftUI `Toggle` with `.toggleStyle(.button)`, bordered (not borderless) and `.controlSize(.small)`, so the bezel shows the on state (the strip toggle needs no bezel because the strip shows its state; nothing else shows the link). Symbol `link`, no text. Hit area at least 20 × 20 pt. Tooltip "Zoom and scroll both photos together" when off, "Zoom and scroll each photo on its own" when on (it says what a click will do). Shown in review too |

**When a caption is short of room**, in this order (`ViewThatFits`): drop
the position; then middle-truncate the name, down to about six characters
around the ellipsis; then drop the HDR badge (its tooltip information is
also in the Info tab). The marks, with the label's name, never go: they
are what R7 is for, and §10 of UI_REDESIGN requires the label's name next
to its color. On a 13" display with both side panes shown, everything
fits (about 470 pt per caption against about 330 pt needed).

## 10. VoiceOver and accessibility

| Element | Spec |
|---|---|
| Comparison | A group, label "Comparison", containing the two panes in reading order (left, right), then the strip and the caption row (order otherwise as UI_REDESIGN §11) |
| Each pane | An image element as the loupe canvas is: label `PhotoAccessibility.label`; value starts "Left photo, active" / "Right photo" then the loupe value ("3 stars, Picked, 12 of 87"); `isAccessibilitySelected` on the active one |
| Pane actions | The canvas's culling actions (performing one makes that pane active first, as `performAccessibilityAction` selects first now), Make Active (inactive pane only), Zoom to 100% / Zoom to Fit, Link / Unlink Zoom and Position, Stop Comparing, Show Grid |
| Entering | Announces "Comparing DSC00231 and DSC00232. Left photo active." |
| `A`, a click on a pane | Announces "Right photo active: DSC00232, 2 stars, Picked." (high priority, so a fast run speaks only the latest) |
| Walking, a strip click | Announces "Right photo: DSC00233, RAW, 13 of 87" (the loupe's move announcement with the side first) |
| Culling | As now: one photo's value ("Rejected") |
| Link toggle | Label "Link Zoom and Position", a toggle with value on or off; toggling announces "Zoom and position linked" / "Zoom and position not linked" |
| Leaving | The loupe's photo announcement for the photo now shown alone |
| Keyboard focus | The comparison host is one key view in the Tab loop where the canvas is now; Tab and ⇧Tab move past it unchanged (§4) |
| Contrast | The ring against the 0.09 surround at 3:1, 4.5:1 with Increase Contrast (non-text element); add both ring colors (accent and neutral) to `PaletteContrastTests` |
| Reduce Motion | Entering, leaving and relinking happen at once |

## 11. Inspector, title and other surfaces

- **Info tab** shows and edits the active photo, as it shows the loupe's
  photo now; capture details help the comparison.
- **Adjust tab:** a `ContentUnavailableView`, title "Not Available While
  Comparing", description "Stop comparing to adjust the active photo.",
  button **Stop Comparing**. The tab stays selectable (the person's choice
  of tab is kept); it never switches tabs by itself.
- **History panel:** hidden while comparing (it reverts edits; non-goal),
  back after.
- **Window title:** the active photo's file name; subtitle "Comparing ·
  All Photos" (· Filtered when filtered).
- **No new windows or sheets.** Comparison on a second display is #102.

## 12. Strings (to `Localizable.xcstrings` by hand)

"Compare Side by Side" · "Stop Comparing" · "Switch to Left Photo" ·
"Switch to Right Photo" · "Link Zoom and Position" · "Unlink Zoom and
Position" (VoiceOver action) · "Compare" (toolbar item) · "Compare two
photos side by side" · "Zoom and scroll both photos together" · "Zoom and
scroll each photo on its own" · "Comparison" · "Left photo" · "Right photo"
· "Left photo, active" · "Right photo, active" · "Make Active" ·
"Comparing %@ and %@. Left photo active." · "Left photo active: %@" /
"Right photo active: %@" · "Left photo: %@" / "Right photo: %@" · "Zoom and
position linked" · "Zoom and position not linked" · "Comparing · %@"
(subtitle) · "Not Available While Comparing" · "Stop comparing to adjust
the active photo." · "Can’t Compare These Photos" · "Can’t Compare This
Photo" · "“%@” is a video. Only photos can be compared." · "The original
of “%@” is offline. Connect “%@” to compare it." · "There’s no other photo
in “%@” that can be compared with it." · "“%@” and “%@” are the RAW and
JPEG files of one photo." (if RI-3 goes that way).

## 13. Debug script (so review and QA can check without a person)

Proposed for the engineer; names are theirs to settle. The panes and ring
are content, not glass, so `snapshot` draws them.

- `compare on|off|toggle` (the menu command's path, alerts included;
  `print alert` or the existing alert reporting shows the refusal).
- `compare active left|right|switch`; `compareclick left|right [x y]` (a
  click on a pane through the mouse path, unit point optional).
- `compare link on|off`.
- `print compare`: the two version IDs, the active side, linked, each
  pane's magnification and visible unit rect, whether the ring is drawn
  and in which color, and each caption's text as laid out.
- Existing `key`, `filmstripclick`, `menuitems Compare` and `menupress`
  must work while comparing.

## 14. Requirements issues (for the product manager)

- **RI-1 (R5: "grid selection as it was").** If the person walked a side,
  the pair on screen differs from the pair selected at the start. This
  design leaves the **current** pair selected on leaving (§1), which is
  what the person last looked at and lets them act on it in the grid.
  The alternative is to restore the selection exactly as it was when
  comparison began. Which does R5 mean? Default if unanswered: the current
  pair.
- **RI-2 (R2: "from the loupe by choosing a second photo").** This design
  chooses the second photo by entering comparison (the partner appears)
  and then walking the right side or clicking a film strip thumbnail
  (§3, §7). It does not add a "pick a second photo" gesture to the strip
  (⌘-click, a context menu), because UI_REDESIGN §11 decision 6 (the
  owner's) keeps the strip to plain focus clicks. Confirm this meets R2.
  If a direct gesture is wanted, it is a change to that owner decision.
- **RI-3 (Edge: "a pair counts as one photo").** With Group RAW+JPEG Pairs
  off, the RAW and the JPEG of one pair are two items and can both be
  selected. They share culling, so rating one would change both captions,
  and comparing a file with its own JPEG is before/after, which is a
  non-goal. Recommended: refuse with the alert in §3. The PRD leaves pair
  resolution to the engineer; this asks the product manager to confirm
  the behavior, not the mechanism.

## 15. Assumptions (stated, not blocking)

- The new keys `S` and `A` (§4) need the owner's approval, as earlier new
  keys did.
- Commands other than culling (keywords, albums, export, Show in Finder)
  act on the active photo; Remove from Album and Remove from Library are
  dimmed while comparing (§4). The PRD is silent.
- Advance After Rating advances the active side (§6). The PRD is silent.
- The link switch is remembered across launches (§5).
- From the grid, one selected photo can be compared with its partner, as
  in the loupe (§3). R2 names two selected photos; this adds the
  one-photo case for consistency with the loupe and changes nothing for
  two.
- AC7's number is the engineer's (PRD Assumptions); nothing here depends
  on it, except that linked panning must follow per frame (§5). If two
  100% views can't keep up, the engineer says so as a Design question
  rather than dropping the link.

## References

- HIG: [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)
  (standard shortcuts: ⌘← / ⌘→ are the system's; Option sparingly; avoid
  Control; don't add a modifier to an unrelated shortcut), checked
  2026-11-11.
- HIG: [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar),
  [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus),
  [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts),
  [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles),
  [Materials](https://developer.apple.com/design/human-interface-guidelines/materials),
  [Pointing devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices),
  [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
- `docs/UI_REDESIGN.md` §1, §2, §6, §7, §10, §11.
