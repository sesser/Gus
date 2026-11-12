# Rename albums in place: design

Owner: apple-ui-designer. Date: 2026-11-11.
Issue: #141. Status: complete. No requirements issues; three assumptions
stated in §8.

**Inputs.**

- Requirements: [`prd.md`](prd.md), R1–R9 and AC1–AC10 (approved
  2026-11-11). Cited as "R‹n›" and "AC‹n›".
- The project rename this matches: [`../library-ops/design.md`](../library-ops/design.md)
  §2.1, §2.3, §3 and §4 (cited as "LO"), and its review's rulings
  (D-L5: renaming from a row that isn't selected leaves the selection).
- Code read on `feature/rename-albums-in-place` at `66f3c64`:
  `Views/SidebarView.swift` (`albumRows`, `projectRow`, `ProjectNameField`,
  the Return handler), `Views/LibraryCommands.swift` (`renameTitle`, the
  Rename item), `Views/LibraryMenuContext.swift` (`SidebarItem`),
  `Model/LibraryOpsActions.swift` (`beginProjectRename`, `endProjectRename`),
  `Catalog/Albums.swift` (albums and smart albums are listed by name,
  `COLLATE NOCASE`, then id), `docs/USER_GUIDE.md` lines 136–157.
- HIG areas relied on: Menus (the ellipsis means more input follows),
  Sidebars, Keyboards, Alerts (don't alert for information alone), as read
  for LO on 2026-11-10. Nothing here depends on guidance newer than that.

**No custom chrome.** Every surface is the one the project rename already
uses: a SwiftUI `List` row whose label becomes a plain `TextField`,
SwiftUI's `renameAction(_:)` and `RenameButton`, and the File menu item.
The album sheet goes away, so this feature removes a surface and adds none.

## 1. Principle

One rename gesture for every sidebar item that is a plain name the library
owns and nothing else depends on: projects and albums. Someone who learned
it on a project already knows it for an album (PRD Goal). This is the HIG's
Consistency principle applied inside the app: two rows that look alike
(symbol, name, count badge) and sit in the same list must answer the same
gesture the same way.

Keywords and smart albums keep their own routes because their names are not
plain names (§4): a keyword rename can merge, and a smart album's name lives
with its rules in its editor. That is a difference in *what renaming means*,
which justifies a different surface; a difference in *which table the row
comes from* would not.

## 2. Album row (R1, R4)

### 2.1 Context menu (designer question 1)

```
Rename
─────────────
Delete…
```

- **Rename first, then a separator, then Delete…** Rename is SwiftUI's
  `RenameButton`, reading the row's `renameAction`; its title is the
  system's "Rename" with no ellipsis, since nothing follows (HIG Menus;
  R4, A4).
- **Delete… alone after a separator.** It is the one destructive item; LO
  §2.2–§2.3 put every destructive sidebar and photo item last and apart, and
  the album row follows the same rule. It keeps its ellipsis (it asks for
  confirmation) and its destructive role.
- The menu acts on the row that was right-clicked, whether or not it is the
  selected one (as today, and as LO §2.3).
- Album rows in the Albums section and album rows under a project are built
  by the same `albumRows`, so they get the same menu (A1).

### 2.2 The three routes (R1, AC1)

Exactly LO §4's, applied to an album row:

1. **File ▸ Rename “‹album›”**, enabled when an album is selected in the
   sidebar, whatever has the keyboard. No ellipsis (§3).
2. **The row's context menu ▸ Rename.**
3. **Return** while the sidebar has the keyboard and an album row is
   selected. A view key, the same `onKeyPress(.return)` handler as the
   project's, extended to `.album`; ignored when a rename is already open.

All three call one "begin album rename" entry point and put the row into
editing. Build it as the project row is built: `.renameAction { … }` on the
album row, `RenameButton()` in its menu, the File item and Return calling
the same action.

### 2.3 Editing

Identical to LO §4 "Editing":

- The label's text becomes a plain text field in the row, same font and
  position, holding the current name with **all of it selected**. The
  `rectangle.stack` symbol and the count badge stay; the row keeps its height.
- **Return** saves. **Escape** cancels and the old name stays. Clicking or
  moving the keyboard elsewhere (Tab, a click in the grid) **saves**.
- Bare keys don't cull while the field has the keyboard (AC2: "5" and "P"
  are typed into the name).
- When it ends by Return or Escape, the sidebar keeps the keyboard with the
  album row selected; a click elsewhere has already moved the keyboard where
  the person clicked.
- **One rename at a time** in the sidebar. Starting a rename on another row
  (album or project) while one is open ends the open one first, by the
  "keyboard moved elsewhere" rule, so it saves. The engineer may generalize
  the project's "renaming" state into one "renaming sidebar item" value to
  get this for free; that is an implementation choice, not a design one.
- The row stays a drop target while being renamed; photos dropped on it are
  added to the album as usual. Nothing to design: the field doesn't accept
  photo drags.

### 2.4 Saving (R2, R3, R6)

Identical to LO §4 "Saving", with the album's names:

- Leading and trailing white space is trimmed. The rule is the one the
  project uses, so both behave the same (PRD A3: the engineer confirms
  whether today's album rule, `Catalog.normalizedKeywordName`, also
  collapses inner spaces; whichever is chosen, projects and albums share
  it).
- Empty or white-space-only: refused. The old name stays, editing ends, and
  `NSSound.beep()` plays. No alert (HIG Alerts: the person sees the result
  and can rename again).
- Unchanged name: nothing saved, no undo step.
- Duplicate names: allowed, no warning.
- A change is one undo step named **"Rename Album"** (unchanged), so Edit
  shows "Undo Rename Album" / "Redo Rename Album".
- Catalog only. Membership, counts and sidecars don't change, and nothing in
  the row suggests otherwise.

### 2.5 Showing the row (R8, R9)

**Before editing (File ▸ Rename with the row out of view).** The window
makes the row visible, then starts editing, as LO §4 does for a project:

- Shows the sidebar if it is hidden.
- **A library album** (Albums section): turns the Albums section back on if
  it was hidden with View ▸ Sidebar Sections, expands it, scrolls to the row.
- **A project's album** (under its project in Projects): turns the Projects
  section on, expands it, expands the album's project, scrolls to the row.
  The PRD names only the Albums section; this is the same rule where the
  row actually lives (§8, A-R1).

The context menu and Return start from a visible row, so they need none of
this.

**After saving.** Albums are listed by name, so a rename can move the row.
It moves to its new place at once (the sidebar shows the new name before the
write finishes, as the project rename does) and is **scrolled into view**.
Selection:

- Renamed from the selected row (File, Return, or the context menu on the
  selected row): it **stays selected** (R9). The sidebar keeps the keyboard
  when the rename ended by Return or Escape (§2.3).
- Renamed from the context menu of a row that isn't selected: the selection
  stays where it was (D-L5, as for projects). The renamed row is still
  scrolled into view, so the person sees where it went. Judgment: R9 is
  written for the selected row; moving the selection to a row the person
  didn't select would contradict D-L5.

Undo and redo move the row back and forth the same way; the row is not
re-selected by undo (undo restores the name, not the selection).

## 3. File ▸ Rename title (designer question 3)

The title follows the sidebar selection, as LO §2.1 set it up:

| Sidebar selection | Title | State |
|---|---|---|
| Project | `Rename “‹name›”` | enabled; renames in place |
| **Album** | **`Rename “‹name›”`** (was `Rename “‹name›”…`) | enabled; renames in place |
| Keyword | `Rename “‹name›”…` | enabled; opens the keyword sheet (R5) |
| Smart album, anything else, no window | `Rename…` | dimmed (as today) |

- An album uses the project's string, `"Rename “%@”"` (LO §10), not a new
  one. The `"Rename “%@”…"` string remains for keywords only; its catalog
  comment changes from "the album or keyword" to "the keyword".
- The dimmed `Rename…` placeholder keeps its ellipsis, as today. It never
  acts, and a title that changed to match an unknown future target would be
  guessing. R5 ("no rename title for smart albums, as today") is met: a
  smart album gets the dimmed placeholder, never its own name.
- The item's place in the File menu is unchanged (LO §2.1).

## 4. Smart albums beside albums (designer question 2)

Smart albums and albums share a section and a sort, and they will now
answer Rename differently. The design keeps that difference legible rather
than hiding it:

- **The rows already look different.** The smart album's
  `square.stack.3d.up.badge.automatic` symbol says "made from rules", next to
  the album's `rectangle.stack`. Nothing more is needed in the row.
- **The context menus say what each can do.** A smart album's menu offers
  **Edit…** (its name is the first field of the editor), never Rename, so
  no one picks Rename and gets a sheet instead of a field. An album's offers
  **Rename**. Each title tells the truth about what follows: Edit… has an
  ellipsis because a sheet follows, Rename has none (HIG Menus).
- **Same menu shape.** To make the two menus read as a pair, the smart
  album's menu gets the same separator before Delete…:

  ```
  Edit…
  ─────────────
  Delete…
  ```

  A separator only; no item, title or behavior changes, so R5 holds.
  Judgment (HIG Menus: group related items; keep the destructive one
  apart), and it matches §2.1.
- **Return on a smart album row does nothing**, as today; it is not routed
  to Edit Smart Album…. Return in a sidebar means "rename in place" on the
  Mac; making it open a sheet on some rows would turn a predictable key into
  one whose result depends on the row's type. Edit Smart Album… stays in the
  File menu and the context menu. The same holds for keyword rows (R5).
- **Sorting.** Unchanged: albums first, then smart albums, each by name. A
  renamed album moves only among albums.

Considered and rejected: renaming smart albums in place too. It would be the
more consistent end state, but it is a non-goal of this PRD; if wanted,
it's a follow-up that also needs a ruling on whether the editor keeps its
name field.

## 5. Accessibility (R7)

- The field's accessibility label is **"Album name"** (a new catalog key
  beside "Project name"). The shared field view takes its label as a
  parameter; it must never announce "Project name" on an album.
- A refused empty name posts the same announcement as a project's, "The
  name can't be empty." (existing key).
- VoiceOver users reach Rename with VO-Shift-M on the row; Full Keyboard
  Access users with Return or the File menu. Every route works without a
  pointer.
- When the edit ends, VoiceOver reads the row as usual; if it moved, the
  scroll into view (§2.5) keeps the focused row on screen.
- Per the owner's standing instruction and PRD A2, the announcement and the
  field label are not put to the owner as manual checks; the debug script's
  accessibility listing covers the label where it can.

## 6. Strings and the user guide

**Catalog** (`Sources/PhotoUI/Resources/Localizable.xcstrings`):

- Add: "Album name" (accessibility label of the album rename field).
- Reuse: "Rename “%@”" (File menu; now project or album: update its
  comment), "The name can't be empty.", "Rename Album" (undo).
- Keep, comment narrowed to keywords: "Rename “%@”…".
- Remove if nothing else uses it once the album sheet is gone: the album
  rename sheet's own strings (its title or prompt). The keyword sheet's
  strings stay. `LocalizationTests` will say which keys are unused only if
  it checks that direction; otherwise the engineer checks by search.
- The context menu's "Rename" comes from `RenameButton` (system); the
  album row's literal "Rename…" goes.

**`docs/USER_GUIDE.md`** (engineer; AC10). Terms the review checks:

- The "Renaming a project" paragraph becomes "Renaming a project or an
  album" (or an album sentence is added to it): select it and choose
  **File ▸ Rename “‹name›”**, press Return while the sidebar has the
  keyboard, or right-click it and choose **Rename**. The rest of the
  paragraph applies to both, except the folder and tooltip sentence, which
  is about projects only. Add for albums: membership and photos don't
  change, and the album moves to its place in the list.
- Line 146–147, "Right-click albums to rename, edit or delete them",
  becomes: right-click an album to rename or delete it, or a smart album to
  edit or delete it.
- The Undo paragraph (line 465) lists "album renames" if it doesn't
  already.

## 7. Implementation and acceptance

Glass panes don't snapshot (CLAUDE.md): sidebar checks use `print`,
`buttons`, `menuitems`, `menupress` and the accessibility listing, or are
manual.

| # | Change | Acceptance |
|---|---|---|
| A1 | Album row: `renameAction`, `RenameButton`, separator, Delete… (§2.1); the name becomes the shared name field while renaming (§2.3) | Debug script: right-click probe or `print` of the album row's menu lists Rename, —, Delete…. Manual M1 |
| A2 | File ▸ Rename on an album starts the in-place rename; title `Rename “‹name›”` (§3) | `menuitems Rename` with an album selected: "Rename “‹name›”", no ellipsis, enabled; with a keyword: "Rename “‹name›”…"; with a smart album: "Rename…" dimmed (AC5, AC6) |
| A3 | Return in the sidebar on an album row starts it; ignored on smart album and keyword rows (§2.2, §4) | Debug script key Return with an album selected, then `print`: the row is a field. Same on a smart album: no field, no sheet |
| A4 | Save rules, undo name, beep and announcement (§2.4) | Unit test of the shared name rule (trim, empty refused, unchanged no-op) covering albums. Debug script: rename via `menupress`, relaunch, `print` shows the new name (AC1); ⌘Z / ⇧⌘Z and Edit's "Undo Rename Album" (AC4); same-name rename leaves Edit's undo title unchanged (AC3); two albums with one name (AC3) |
| A5 | Showing the row first (§2.5): library album in a hidden or collapsed Albums section; project album in a collapsed project; hidden sidebar | Debug script: hide the section / collapse it / hide the sidebar, `menupress` Rename, `print` shows the field (AC9) |
| A6 | After a rename that moves the row: selected and in view; from an unselected row's menu, selection unchanged and the row in view (§2.5) | Debug script: rename "A" to "Z" among enough albums to scroll, `print` the selection and visible rows (AC9) |
| A7 | Album sheet removed: no `SidebarSheet.renameAlbum` case and no route to it | Search (AC5) |
| A8 | Smart album menu gains the separator only (§4) | Menu probe lists Edit…, —, Delete… (AC6) |
| A9 | Catalog only (§2.4) | Unit or script check: membership and count unchanged, sidecar queue empty after a rename (AC7) |
| A10 | "Album name" label (§5) | Debug script accessibility listing where it reaches the field (AC8) |
| A11 | User guide (§6) | Read at review (AC10) |

**Manual checks** the review will number for a person (no VoiceOver, per the
owner's standing instruction):

- **M1. Look.** Start an album rename by each route. The name becomes a
  field in place, whole name selected; symbol and count stay; the row
  doesn't change height. Matches a project rename side by side.
- **M2. Endings.** Escape restores; clicking a photo saves; typing "5" and
  "P" in the field changes no photo; an emptied name beeps and keeps the old
  one.
- **M3. Moving row.** Rename an album so it sorts elsewhere; it moves,
  stays selected and visible, and the sidebar keeps the accent-colored
  selection (it has the keyboard).

## 8. Assumptions (stated, not raised)

- **A-R1.** R8's "Albums section hidden or collapsed" extends to a project's
  albums as "Projects section hidden or collapsed, or the project
  collapsed" (§2.5). PRD A1 says every album renames the same way, so this
  is the same requirement where the row lives.
- **A-R2.** R9 ("stays selected") applies to the selected album. A rename
  from the menu of an unselected row leaves the selection alone, per D-L5,
  but scrolls the renamed row into view (§2.5).
- **A-R3.** The separator added to the smart album's menu (§4) is
  presentation, within R5's "unchanged", since no smart album item, title
  or behavior changes.

## 9. Design questions from implementation

None yet. Rulings go here, numbered D-RA‹n›.
