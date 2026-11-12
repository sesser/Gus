# Rename albums in place: design review

Issue: #141. Reviewer: apple-ui-designer. Date: 2026-11-11.
Branch `feature/rename-albums-in-place` at `df28ab1`, read against
[`design.md`](design.md) (§2–§7), [`prd.md`](prd.md) (AC1–AC10) and
[`status.md`](status.md). Code read, not built: `Views/SidebarView.swift`,
`Model/SidebarRenameActions.swift`, `Model/AlbumActions.swift` (`renameAlbum`),
`Model/LibraryModel.swift` (`revealSidebarRow`, `refreshSidebar`),
`Views/LibraryCommands.swift` (`renameTitle`), `Views/LibraryMenuContext.swift`,
`PhotoCore/Browser/SidebarRename.swift`, the String Catalog entries and
`docs/USER_GUIDE.md`.

## Verdict

**Pass, no fixes.** The album row now renames exactly as a project row does,
by the same three routes and one shared field; the sheet is gone, menu titles
carry an ellipsis only where a sheet follows, and smart albums and keywords are
unchanged apart from the smart album menu's separator. The engineer's open
point is ruled in design.md **D-RA1**: keep it as built. What is left is
looking at it on screen (M1–M4).

## Design requirements

| # | Requirement | Result | Evidence |
|---|---|---|---|
| §2.1 / A1 | Album menu: Rename (system `RenameButton`), separator, Delete… (destructive, ellipsis); same for library and project albums | Pass | `albumRows`: `RenameButton()`, `Divider()`, `Delete…` with `.destructive`; one `albumRows` for both places. S4 |
| §2.2 / A3 | Three routes call one entry point; Return only on project and album rows, ignored while a rename is open | Pass | File item, `.renameAction` and `onKeyPress(.return)` all call `beginSidebarRename`; Return guarded by `renameRoute == .inPlace` and `sidebarRename == nil`. S1, S4 |
| §2.3 | Field in place, whole name selected; symbol and badge stay; Return saves, Escape cancels, focus loss saves; keyboard back to the list after Return/Escape; one rename at a time | Pass (look: M1) | `rowName` swaps only the `Label`'s title; `SidebarNameField` (`onSubmit`, `onExitCommand`, focus change); `listHasKeyboard = true` when `byKey`; open rename saved before a new one starts. S1, S2, S8 |
| §2.3 | Bare keys don't cull while the field has the keyboard | Pass | S2 ("5p" typed, counts unchanged) |
| §2.4 / A4 | Shared rule (trim, empty refused with beep and announcement, unchanged no-op), duplicates allowed, undo "Rename Album" | Pass (sound: M2) | `InPlaceRename.resolve`, `NSSound.beep()`, `AccessibilityText.announce`; `renameAlbum` guards an unchanged name. S3, `albumNameRule` |
| §2.4 / A9 | Catalog only | Pass | `renamingAnAlbumChangesOnlyItsName`; S5 |
| §2.5 / A5 | File ▸ Rename shows the sidebar, turns on and expands the section, expands a project album's project, scrolls | Pass | `beginSidebarRename` (`showsSidebar`, `setSidebarSection`), reveal handler with `opensContainers`. S6 |
| §2.5 / A6 | Moved row in view; selected row stays selected; unselected row's menu leaves the selection (D-L5) | Pass (look: M3) | `renameAlbum` sorts with `isListedBefore` and reveals without opening; `beginSidebarRename` never touches the selection. S7 |
| §2.5 undo | Undo and redo move the row and scroll; not re-selected; don't unfold | Pass | D-RA1 |
| §3 / A2 | Title: project and album `Rename “‹name›”`; keyword `Rename “‹name›”…`; smart album and others `Rename…` dimmed | Pass (menu bar: M4) | `renameTitle(for:)` on `SidebarRenameRoute.titleHasEllipsis`. S4 |
| §4 / A8 | Smart album menu Edit…, separator, Delete…; no Rename; Return does nothing on smart album or keyword rows | Pass | `albumRows` smart `ForEach`; Return guard. S4 |
| §5 / A10 | Field label "Album name" (never "Project name" on an album); same announcement | Pass by reading | `SidebarRenameText.fieldLabel(for:)`, `.accessibilityLabel(label)`. Not verifiable by script (SwiftUI tree); not put to the owner (PRD A2) |
| §6 strings | "Album name" added; comments narrowed on "Rename “%@”", "Rename “%@”…", "The name can't be empty."; album sheet strings gone | Pass | Catalog entries read; context menu "Rename" is the system's |
| A7 | No `SidebarSheet.renameAlbum`, no route to a sheet | Pass | `SidebarSheet` has `renameKeyword` only; search finds no album sheet case |
| §6 / A11 | User guide terms | Pass | See below |

### User guide (AC10)

`docs/USER_GUIDE.md` lines 146–159 and 466–467 match the UI's words:
"**File ▸ Rename “‹name›”**", "press Return while the sidebar has the
keyboard", "right-click it and choose **Rename**" (the system title, no
ellipsis), "Right-click an album to rename or delete it, or a smart album to
edit or delete it", and **File ▸ Edit Smart Album…** for smart albums. The
folder and tooltip sentence is scoped to projects; the album sentence says it
keeps its photos and moves to its place by name. The Undo paragraph lists
"project and album renames". No stale "Rename…" for albums remains.

## Ruling on the open point (D-RA1)

After a save, undo or redo the sidebar scrolls the row into view but does not
turn on or expand a section or a project; only File ▸ Rename does. **That is
right, and design §2.5 now says it explicitly**; no code change. Every route
starts from a visible row, so a row can be folded away at undo time only
because the person folded it after renaming. Undo restores the name, not the
layout, as it already doesn't restore the selection. Edit's "Undo Rename
Album" names the change, and an album that is the current source updates the
window title. Expanding sections on ⌘Z pressed in the grid would change the
sidebar's layout when the person didn't ask for it. Full text in design.md §9.

## Fixes for the engineer

None.

## Improvements (judgment, not required on this branch)

- **The keyword row's menu** is still Rename…, Delete… with no separator,
  while album and smart album rows now separate Delete…. R5 keeps keywords
  unchanged, so this is correctly left alone here. If a later sidebar change
  touches keyword rows, give it the same separator (HIG Menus: keep the
  destructive item apart). Not worth an issue on its own.
- **RI-RA1 (for the product manager).** I agree the branch is right to follow
  §2.4 (option a). From a design view, option (b) is better: the same text
  typed into New Album and into Rename should give the same name
  (Consistency). It is low-impact, since it only shows when someone types
  several spaces in a row, so it can be a follow-up issue.

## What's working

- One field view, one rename state, one reveal path for projects and albums.
  The two row types can't drift apart, and "one rename at a time" comes free.
- The row moves to its sorted place at once rather than after the write.
- Menu titles state what follows: no ellipsis for in-place, an ellipsis for a
  sheet, decided by `SidebarRenameRoute.titleHasEllipsis` in one place.

## Manual checks for a person

At the bundled app on a scratch library (not VoiceOver, not macOS 15/26, per
the owner's standing instruction):

- **M1. Look.** Start an album rename by File ▸ Rename, the context menu and
  Return. The name becomes a field in place with the whole name selected, the
  symbol and count stay, and the row keeps its height. Side by side, it looks
  the same as a project rename. Repeat once on an album under a project.
- **M2. Endings.** Escape restores the old name. Clicking a photo in the grid
  saves. Typing "5" and "P" in the field changes no photo. An emptied name
  plays the alert sound and keeps the old name.
- **M3. Moving row.** In a sidebar long enough to scroll, rename the selected
  album so it sorts elsewhere. It moves, stays selected and in view, and keeps
  the accent-colored (keyboard) selection. Press ⌘Z: it moves back and stays
  in view.
- **M4. Menu bar** (status K1). With an album selected, File ▸ Rename
  “‹name›” has no ellipsis, is enabled and starts the field. After a rename,
  Edit shows "Undo Rename Album", then "Redo Rename Album". With a keyword it
  reads "Rename “‹name›”…" and opens the sheet with its merge note. With a
  smart album it reads "Rename…", dimmed.
