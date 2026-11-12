# Library operations: rename project, remove from library, show in Finder

Status: Shipped, checks pending (2026-11-11): macOS 15 and 26 not checked by a person (confirmation keys, look); see [`qa.md`](qa.md)
Slug: library-ops
Issue: #61
Roadmap: none (shipped; the issue closes with the pull request)

## Problem
Someone who keeps photos in their own folders has no way to tidy the library. A wrong or unwanted import can never be taken out of the catalog. Projects keep the folder or template name they were imported with. There is no way to jump from a photo or project to its file in the Finder. The catalog already has `renameProject` and `deleteProject` (no UI), and File ▸ Rename and Delete are dimmed for projects.

## Goal and success
Four operations, all touching the catalog only and never the files on disk: rename a project, remove photos from the library, remove a project from the library, and show originals in the Finder. Success: a mistaken import can be removed in a few steps and the files are still where they were; a project can be renamed; a photo or project can be revealed in the Finder.

## Users and scenarios
- Primary: I imported the wrong card. I select the project, choose Remove Project from Library, read the confirmation, confirm. The project and its photos are gone from the app; the files and sidecars are untouched, and I can import them again.
- I cull a project and want to drop 12 rejects from the library: select them, Remove from Library.
- I rename "100OLYMP" to "Iceland 2026".
- I select a photo and Show in Finder to see its file.
- Edge: a RAW+JPEG pair, an offline photo, a project with no single folder.

## Requirements
Show in Finder and Rename Project are the small first slice; Remove is the risky part.

R1 (Must): Rename a project from the sidebar (inline), File ▸ Rename and the project context menu. The name is saved in the catalog only.
R2 (Must): An empty or whitespace-only project name is refused (the old name stays). Duplicate names are allowed.
R3 (Must): Rename is one undo step.
R4 (Must): Rename never renames a folder on disk or changes any sidecar.
R5 (Must): "Remove from Library" removes the selected photos from the catalog. Never moves, deletes or modifies a master or a sidecar file.
R6 (Must): Removing photos deletes everything the catalog holds for the photo: versions, edits, edit history, rating, flag, label, keyword links, album and smart-album membership, stack and pair links, and its pending sidecar queue entries. Keywords and albums themselves stay, even if empty (removing a project is different: R8).
R6 note (virtual-copies, #62, D10): a copy (a second version of a master, made by File ▸ Duplicate) removed on its own removes only that version; its original and the master stay. Removing an original takes its copies with it.
R7 (Must): Removing either file of a RAW+JPEG pair removes both. The confirmation states the file count (for example "2 files").
R8 (Must): "Remove Project from Library" removes the project and all its photos by the same rule as R5-R7, and also deletes the project's own albums and smart albums. The confirmation says how many albums and smart albums go with it (shown only when there are some).
R9 (Must): Both removals ask for confirmation first, stating the number of photos (files), that files on disk are not touched, and that edits are lost. The confirmation has no default button: Return does nothing, and Escape or ⌘. cancels.
R10 (Must): Removal cannot be undone. The confirmation says so. No Trash or "recently removed" area.
R11 (Must): Offline photos can be removed, with no extra warning.
R12 (Must): After removal, the same files can be imported again as new photos. Duplicate detection does not remember removed photos.
R13 (Must): Removal is all or nothing: if it fails part way, the catalog is unchanged and the failure is reported in Activity.
R14 (Must): Show in Finder on photos reveals each selected photo's master, with all files sent to the Finder together: one window per folder involved, no limit on the number of windows. A grouped RAW+JPEG cell reveals the RAW; with pairs ungrouped, the JPEG cell reveals the JPEG. (Removal still takes both files, R7.)
R15 (Must): Show in Finder on a project reveals its source folder when `sourcePath` is set and the folder exists.
R16 (Must): Show in Finder is dimmed for an offline photo, for a project with no source folder, or whose folder is missing. It never opens a volume's mount point.
R17 (Must): Names are File ▸ Show in Finder, File ▸ Remove from Library… and Remove Project from Library… (the ellipsis marks the confirmation that follows). "Show in Finder" must not clash with Show Original. Keys are the designer's to propose.
R18 (Should): Every command is in a menu and the context menus of the grid, loupe and sidebar, and works with VoiceOver.

## Acceptance criteria
AC1 (R1, R2): Rename a project by each route; the sidebar shows the new name after relaunch. An empty name keeps the old one. Two projects may share a name.
AC2 (R3): Undo restores the old name; redo reapplies it.
AC3 (R4): After a rename, the project's folder and sidecars are unchanged.
AC4 (R5, R6): After removing a photo that had edits, keywords, an album, and a rating, no catalog row refers to it; keywords and albums still exist; its file and `.xmp` have the same hash and mtime.
AC5 (R7): Removing the JPEG of a pair removes the RAW too; the confirmation says 2 files.
AC6 (R8): Removing a project leaves no project, photo or version rows for it, and none of its albums or smart albums; files untouched. Albums of other projects, and keywords, remain. The confirmation names the album count only when there is one.
AC7 (R9, R10): Both commands show the confirmation described, with no default button: Return does nothing, Escape and ⌘. cancel; Cancel changes nothing; Edit ▸ Undo is not offered for the removal.
AC8 (R11): An offline photo is removed with no volume access.
AC9 (R12): Re-importing a removed folder gives its photos back as new, with no edits.
AC10 (R13): A forced failure during removal leaves the catalog unchanged and Activity reports it.
AC11 (R14): Selecting three photos in one folder and Show in Finder opens one Finder window with the three files selected; photos in several folders open one window per folder. A grouped pair selects the RAW; with pairs ungrouped, the JPEG cell selects the JPEG.
AC12 (R15, R16): A project with a folder reveals it; an offline photo, a project with no folder, or a missing folder has the command dimmed.
AC13 (R17, R18): Each command appears in the menu named (the two removals with an ellipsis) and context menus listed, and its title differs from Show Original.

## Non-goals
Deleting or moving files, folders or sidecars; undo of removal; Trash; "remove all offline photos"; remembering removed photos; renaming folders on disk; `photocli` commands; opening a volume's mount point.

## Dependencies and impact
`Catalog.renameProject` and `deleteProject` exist (cascade tested); single-photo removal does not and is new, including pair and sidecar queue handling. Touches albums, keywords, RAW+JPEG pairs (`ImagePairing`), edit history (`editHistory` goes with its version), sidecar sync, and the sidebar and menus (`LibraryMenuContext`). The engineer updates `docs/USER_GUIDE.md`. Principle 1 and the "volumes can go offline" rule: a person's choice to remove is not the automatic removal that rule forbids.

## Assumptions
Confirmed by the owner (defaults accepted, 2026-11-10): the answers above. Also: no batch remove-offline command, no Trash, no `photocli` commands, one PRD with Rename and Show in Finder as the first slice.

## Open questions
- Designer: keys for each command, and whether a project's Show in Finder lives in the sidebar context menu only.
- Engineer: whether the removal can be a single transaction (R13) and how pending sidecar queue entries are dropped.
- Owner: file the optional follow-up issue "rename albums in place" (raised by the design)? Not assumed; no issue is filed until you say.

## Owner rulings (2026-11-10)
1. Remove has no undo; confirmation states count, files untouched, edits lost.
2. Everything in the catalog goes with a photo; keywords and albums stay; sidecar files on disk are never touched.
3. Pairs are removed together.
4. Removed files can be re-imported, nothing remembered.
5. Offline photos can be removed.
6. Show in Finder as in R14-R16.
7. Rename as in R1-R4.
8. One PRD; command names as in R17.

Design rulings (2026-11-10, "Defaults are fine", design.md §13):
9. RI-L1: removing a project deletes its own albums and smart albums; the confirmation says how many.
10. RI-L2: the confirmation has no default button; Return does nothing, Escape and ⌘. cancel.
11. RI-L3: no limit on Finder windows; one window per folder.
12. RI-L4: grouped pairs reveal the RAW, an ungrouped JPEG cell reveals the JPEG; removal still takes both files.

## Revisions
- 2026-11-10: R6 scoped to photo removal; R8 adds the project's own albums and smart albums and the count in the confirmation; AC6 matches (RI-L1). R9 and AC7: no default button, replacing "default Cancel" (RI-L2). R14 and AC11: one window per folder, ungrouped JPEG reveals the JPEG (RI-L3, RI-L4). R17 and AC13: ellipsis on the two removal commands. Status stays Approved.
