# Rename albums in place in the sidebar

Status: Approved (owner, 2026-11-11)
Issue: #141
Slug: rename-albums-in-place
Roadmap: Next

## Problem
Library operations (#61) made projects rename in place in the sidebar: Return, the context menu's Rename, or File ▸ Rename, with the name becoming a text field in the row. Albums still rename through a sheet ("Rename…" in the context menu and File ▸ Rename “‹name›”…). So the sidebar has two rename styles for two kinds of item that look and behave alike. The library-ops design (§2.1) named this as an optional follow-up; the owner asked for it on 2026-11-10.

## Goal and success
Renaming an album works exactly as renaming a project does: in the row, by the same three routes, with the same save and cancel rules. Success: the album Rename sheet is gone, and someone who has renamed a project already knows how to rename an album with no new learning.

## Users and scenarios
- Primary: I select the album "Best of" in the sidebar, press Return, type "Iceland best of", press Return. The row shows the new name.
- I right-click an album, choose Rename, change my mind, press Esc: the old name stays.
- Edge: I clear the name and press Return: the old name comes back and the Mac beeps.
- Edge: I rename an album, then press ⌘Z: the old name returns.

## Requirements
R1 (Must): An album can be renamed in place in the sidebar: its row's name becomes a text field with the whole name selected. Routes: File ▸ Rename “‹name›” with an album selected in the sidebar, the album row's context menu, and Return while the sidebar has the keyboard and an album row is selected. Same behavior as a project (library-ops design §4): Return saves, Esc cancels, clicking or moving the keyboard elsewhere saves, bare keys do not cull while the field has the keyboard, the sidebar keeps the keyboard afterwards.
R2 (Must): Saving trims leading and trailing white space. An empty or whitespace-only name is refused: the old name stays, editing ends, and the system beep plays. A name equal to the current one saves nothing and adds no undo step. Duplicate album names are allowed, with no warning (as today; the catalog has no uniqueness rule for albums).
R3 (Must): A rename is one undo step named "Rename Album" (as today), and redo reapplies it.
R4 (Must): The Rename sheet for albums is removed: no route opens it. The context menu item and File item no longer end in an ellipsis for albums, since nothing follows.
R5 (Must): Smart albums and keywords are unchanged. Smart albums keep renaming through Edit Smart Album…; keywords keep their sheet, which explains merging when the new name matches another keyword. File ▸ Rename keeps its title “Rename “‹name›”…” for keywords and has no rename title for smart albums, as today.
R6 (Must): Renaming an album changes the catalog only; its photos, membership, and sidecars are untouched.
R7 (Should): Accessibility as for projects: the field's label is "Album name", and a refused empty name posts the same announcement as a project's ("The name can't be empty.").
R8 (Should): If the album's row is not visible when File ▸ Rename runs (sidebar hidden, Albums section hidden or collapsed), the window makes it visible first, as it does for a project.
R9 (Should): After a rename the album's row stays selected and in view, even if the list order changes.

## Acceptance criteria
AC1 (R1): With an album selected, File ▸ Rename “‹name›”, the context menu's Rename, and Return in the sidebar each turn the row's name into a text field with the whole name selected. Return saves, and the row shows the new name after relaunch.
AC2 (R1): Esc restores the old name; clicking elsewhere saves the typed name; typing "5" or "P" in the field does not rate or flag any photo.
AC3 (R2): "  Trip  " saves as "Trip". An empty or whitespace-only name leaves the old name and beeps. Renaming to the same name adds no undo step (Edit shows no "Undo Rename Album" from it). Two albums may share a name.
AC4 (R3): After a rename, Edit shows "Undo Rename Album"; undo restores the old name, redo the new one.
AC5 (R4): No album route opens a sheet: a debug-script check or search shows no `renameAlbum` sheet case remains, and the menu and context menu titles carry no ellipsis for an album.
AC6 (R5): A keyword still opens its Rename sheet with the merge note; a smart album's Rename is absent from File and its context menu offers Edit…; renaming onto an existing keyword still merges.
AC7 (R6): After renaming, the album's membership and count are unchanged and no sidecar changes.
AC8 (R7): The field reports the label "Album name"; a refused empty name posts the announcement. (Checked with the debug script's accessibility listing where possible; the announcement is a person's check, though see assumption A2.)
AC9 (R8, R9): With the sidebar hidden or the Albums section collapsed, File ▸ Rename on the selected album shows it and starts editing; after a rename that moves the row, it stays selected and visible.
AC10 (R1): `docs/USER_GUIDE.md` says albums rename in place by those routes, replacing "Right-click albums to rename".

## Non-goals
Renaming keywords or smart albums in place; merging or duplicate-name warnings for albums; changing what a name may contain; renaming several albums at once; any change to how albums are created (the New Album sheet stays).

## Dependencies and impact
Builds on library-ops' project rename (`beginProjectRename`/`endProjectRename`, `renameAction`, the name field, Return handling, File ▸ Rename in `LibraryCommands`; design §4). The existing `renameAlbum(_:to:)` and undo name stay. `SidebarSheet.renameAlbum` and its sheet are removed. Touches `SidebarView`, `LibraryCommands`, `LibraryMenuContext` (`SidebarItem` rename title), the String Catalog, and `docs/USER_GUIDE.md` (engineer). Shares the generic name-rule with project rename where sensible (engineer's call). No data or migration change; no rendering change.

## Assumptions
Confirmed by the owner on 2026-11-11 (approval with all proposed defaults), except A3's engineering check:
A1 (decided): Albums in every project and the global ("all projects") albums rename the same way.
A2 (decided): As with project rename, the announcement for an empty name is checked by a person only if at all; the owner has said not to ask for VoiceOver checks, so it is Should and unverified by owner.
A3 (decided, engineer to confirm): Same trimming as today's sheet (`Catalog.normalizedKeywordName`). The engineer confirms whether it also collapses inner spaces and whether that matches the project rule; behavior must be the same for both.
A4 (decided): The context menu title is "Rename" (the system's `RenameButton`), as for projects.

## Open questions
Owner questions: none; all answered by the approval.
- Designer (open): the context menu order for an album row (Rename first, then Delete…, separated?); how smart albums sit beside albums given only albums rename in place.
- Engineer (open): whether the project rename's focus and field code can be shared by both row types, and what ("Album name" vs "Project name") labels the field. R7 already requires "Album name" for albums.
