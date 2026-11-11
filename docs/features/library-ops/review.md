# Library operations: design review

Owner: apple-ui-designer. Date: 2026-11-10. Issue: #61. Branch:
`feature/library-ops` at `fd00a1f`.

Reviewed by reading, against [`design.md`](design.md) (§1–§14),
[`prd.md`](prd.md) (R1–R18, AC1–AC13) and the HIG (Menus, Context menus,
Alerts, Keyboards, Writing). Nothing was built or run for this review; the
engineer's debug-script results in [`status.md`](status.md) are taken as
evidence for what they cover, and everything that needs a key window or a
real key press is a manual check below.

Code read: `Model/LibraryOpsActions.swift`, `Views/LibraryCommands.swift`,
`Views/LibraryMenuContext.swift`, `Views/SidebarView.swift`,
`Grid/PhotoContextMenu.swift`, `Views/MainView.swift`,
`Views/ActivityToolbarItem.swift`, `PhotoCore/Browser/RemovalConfirmation.swift`,
the new String Catalog keys, and `docs/USER_GUIDE.md`.

## Verdict

**Pass, with two small fixes.** The structure is as designed: every command
is in the File menu in §2.1's order and in the context menus of what it acts
on, the destructive item is last and alone everywhere, the confirmations are
system alerts with no default button, rename is SwiftUI's own in-place
mechanism, and ⌘⌫ is held to the grid and loupe so text fields keep it. The
two fixes are an Activity title that the owner's ruling changes (F1) and one
missing line in the user guide (F2). Everything a key window decides is
unverified and listed as manual checks M1–M14.

## Rulings on the engineer's design questions

The owner accepted every default (2026-11-10). Recorded here as D-L1–D-L7
for the engineer to cite; design.md §15 should point to this section (this
review was asked to edit only `review.md`).

| # | Question (status.md) | Ruling |
|---|---|---|
| D-L1 | Which jobs keep a removal from starting (§8) | The two imports only (folder add, card import). Exports and batch measurements do not block a removal. An import started while a removal is being confirmed or runs is not blocked. As built |
| D-L2 | Activity job titles | **Both jobs are titled with the command, the count under it**: "Remove from Library" / "Removing ‹N› photos…", and "Remove Project from Library" / "Removing ‹N› photos…". This follows the Activity rule that rows are titled with the command's menu title without the ellipsis (UIR §1). The project job is as built; the photo job changes (F1) |
| D-L3 | The message's sentences in one paragraph | One paragraph. As built |
| D-L4 | "The folder …" when a project has no single source folder | Wording as built: the same sentence. The folder of a project with no `sourcePath` is the folders its photos are in; "stay on disk, unchanged" is true of each |
| D-L5 | Rename from the menu of a row that is not selected | The selection stays where it was. As built |
| D-L6 | Destructive role on the sidebar's Remove Project from Library… | Kept, like the Delete… items beside it. The photo menus' item is plain (`NSMenu` has no destructive style); the separator and last place carry the distinction there |
| D-L7 | Show in Finder on a project whose folder has just gone | Nothing opens, the item dims, no message. The folder state is refreshed when the app comes forward, as built |

## Design requirements

"Script" means the engineer's debug-script result (status.md, letter in
brackets). "Read" means confirmed in the code.

| Ref | Requirement | Result | Evidence |
|---|---|---|---|
| §1, §2.1 | File menu order and separators: Rename, Delete, Remove Project from Library…, —, Show in Finder ⇧⌘R, Export… ⇧⌘E, Remove from Library… ⌘⌫, —, Check for Changes on Disk, Stop ⌘. | Pass | Read; script H |
| §2.1 | Both Remove items end in "…"; project Rename has none ("Rename “‹name›”"); albums and keywords keep "Rename “‹name›”…" | Pass | Read (`renameTitle`, catalog keys) |
| §2.1, §1 | File ▸ Delete stays "Delete…" and dimmed for a project | Pass (code); enabled state needs manual check | Read (`isDeletable`); M8 |
| §2.2 | Photo menus: Show in Finder after Export…, before the RAW+JPEG Pair submenu; left out when no target is online | Pass | Read (`addPhotoItems`); scripts H, I |
| §2.2 | Remove from Library… last and alone in the grid, loupe (after Crop) and video loupe (after Show Grid) | Pass | Read (`addRemoveItem`, `defer` in the loupe); script H |
| §2.3 | Project row menu: New Album in Project…, New Smart Album in Project…, —, Rename (`RenameButton`), Show in Finder (left out without a folder), —, Remove Project from Library… | Pass | Read; script K |
| §2.3 | The row menu acts on the right-clicked row | Pass | Read (`summary.id` throughout); script K |
| §2.4 | Nothing in the toolbar or inspector | Pass | Read |
| §3 | ⇧⌘R and ⌘⌫ assigned; no key for Remove Project; Return in the sidebar starts rename | Pass (code) | Read; script E |
| §3 | ⌘⌫ enabled only while the grid, loupe or video loupe has the keyboard (`canByKey`) | Pass (code); needs manual check | Read; M7 |
| §4 | Three routes into one in-place rename; the row shown, Projects section shown and scrolled to | Pass | Read; scripts D, E, L |
| §4 | Field: whole name selected, Return saves, Escape restores, losing the keyboard saves, sidebar keeps the keyboard after Return/Escape | Pass (script); real clicks and Tab need manual check | Script D, E; M2 |
| §4 | Field look: same font and place, symbol and badge stay, row height kept; tooltip still shows the folder path | Needs manual check | `.textFieldStyle(.plain)` inside the `Label` is the right construction; M1 |
| §4 | Trim; empty refused with `NSSound.beep()` and the announcement; unchanged name no step; duplicates allowed | Pass (code and script); sound and VoiceOver need manual check | Read (`endProjectRename`); script E; M3, M11 |
| §4 | One undo step, "Rename Project" | Pass | Read; script D |
| §4 | Row moves if projects are listed by name | Not applicable | Projects are listed by creation date (`Catalog.projectSummaries`); a rename never moves the row |
| §5.1 | Grouped pair reveals the RAW, ungrouped cell its own file, one `activateFileViewerSelecting` call | Pass | Read; script C; Finder windows M4 |
| §5.1 | Enabled when any target is online, with no disk access at validation; skipped photos counted in one Activity information row titled "Show in Finder", "offline" or "offline or missing" | Pass | Read (`canShowTargetsInFinder`, `notShown`); script I |
| §5.2 | File ▸ Show in Finder means the sidebar's project while the sidebar has the keyboard; dimmed for any other sidebar row then | Pass (code); needs manual check | Read (`canShowInFinder`); M5 |
| §5.2 | Project folder: needs `sourcePath`, not a mount point, volume mounted, folder present; checked off the main actor, again when run | Pass | Read (`refreshProjectFolders`, `showProjectInFinder`); script I; D-L7 |
| §6.1 | Remove from Library… enabled with targets and the browser focused; dimmed beside an import (D-L1) and while a removal is asked or runs | Pass (code); menu-bar state needs manual check | Read (`canRemoveFromLibrary`, `askToRemove` sets `isRemoving` at once); script N; M8, M9 |
| §6.2 | Titles: one file name, or "Remove ‹N› photos from the library?" | Pass | Read; script C |
| §6.2 | Message: pair sentence only when files exceed photos, then the consequences sentence; one paragraph (D-L3) | Pass | Read (`RemovalConfirmation.photos`); script C |
| §6.2 | Buttons Remove (destructive) and Cancel, no default; Escape and ⌘. cancel; app icon, no caution symbol; no suppression box | Pass on macOS 27.2 (script A); ⌘., macOS 15 and 26, and the look need manual check | Read (`MainView`); M6 |
| §6.3 | Nothing changes before the write; Activity job after 0.5 s with no Stop | Pass | Read (`confirmRemoval`, `ActivityJob(... stop: nil)`) |
| §6.3 | Activity job title | **Fail** (F1) | `RemovalJob(title: removing(count))`; D-L2 |
| §6.3 | Focus to the following photo, else the previous; loupe follows; empty source returns to the grid | Pass | Read (`RemovalFocus`); scripts B, J |
| §6.3 | Failure: Activity warning titled "Remove from Library" with the error as detail; no alert; nothing changes | Pass | Read (`reportRemovalFailure`); script G |
| §6.3 | Undo stack cleared after success, kept after failure | Pass (code); Edit menu state needs manual check | Read (`removeAllActions` only in `removalDidFinish`); scripts B, G; M10 |
| §7.1 | Remove Project from Library… enabled for a selected project whatever has the keyboard; in every project row's menu; empty projects alike | Pass (code); menu-bar state needs manual check | Read; script F; M8 |
| §7.2 | Title "Remove the project “‹name›” from the library?"; photos or "It has no photos."; pair sentence; album count only when there are some; consequences or "The folder stays on disk, unchanged." | Pass | Read (`RemovalConfirmation.project`); script F |
| §7.3 | Selected project removed: sidebar selects All Photos and keeps the keyboard; failure warning titled "Remove Project from Library"; job "Remove Project from Library" / "Removing ‹N› photos…" | Pass | Read; scripts F, G, Large |
| §8 | Remove items dimmed in the menu bar and left out of context menus while an import runs (D-L1) | Pass (context menus, rule); menu bar needs manual check | Script N; M9 |
| §9 | Every command reachable from the menu bar and a context menu; no new VoiceOver custom actions | Pass | Read |
| §9 | Announcements after a removal (one file by name, several by count), a project, and an empty name; field label "Project name" | Pass (code); hearing them needs manual check | Read (`AccessibilityText.announce`, `.accessibilityLabel`); M11 |
| §10 | Strings: every key in the catalog, plurals as plural variations, no product name, comments naming each use | Pass | Read (catalog). "Project name" shares the Import options row's key; see I2 |
| §11 | User guide terms: Show in Finder (⇧⌘R), Rename (in place, Return), Remove from Library… (⌘⌫), Remove Project from Library…, *remove* versus *delete*; key table rows; never "delete" for a removal | Pass, one omission (F2) | `docs/USER_GUIDE.md` lines 73–74, 149–199, 469 |

## Acceptance criteria (design side)

| AC | Design view |
|---|---|
| AC1 | Routes and naming as designed; look and real keys are M1, M2 |
| AC2 | "Undo Rename Project" / "Redo Rename Project" (action name set) |
| AC3 | The tooltip keeps the folder path, so the UI does not suggest a folder rename |
| AC5 | "2 files in all" for a grouped pair and an ungrouped JPEG |
| AC6 | Album count sentence only with albums |
| AC7 | No default button and Escape on Cancel confirmed on 27.2; ⌘. and macOS 15/26 are M6; Edit ▸ Undo dimmed afterwards is M10 |
| AC11, AC12 | Rules confirmed; the Finder's windows are M4, M5 |
| AC13 | Names, ellipses and placement as listed; "Show in Finder" shares nothing with "Show Original" / "Show Adjustments" |

## Findings for the engineer

**F1. The photo removal's Activity job is titled with its count, not the
command (D-L2).** `removeTargetsFromLibrary` builds
`RemovalJob(title: LibraryOpsText.removing(count))`. Make it
`RemovalJob(title: LibraryOpsText.removeFromLibrary, detail: LibraryOpsText.removing(count))`,
the same shape as the project's. Why: Activity rows are titled with the
command that started them, so a person can tell at a glance which command a
row belongs to, and the two removals then read alike. Update the catalog
comment on "Remove from Library" ("Activity row title: a removal of photos
that failed") to say it is also the job's title. Script check: `removephotos`
on a large selection prints `Activity job 'Remove from Library' detail
'Removing ‹N› photos…'`.

**F2. The user guide's Undo paragraph does not list project renames.**
`docs/USER_GUIDE.md` line 463 lists what ⌘Z undoes; renaming a project is now
one of them. Add "project renames" to that list. (Line 157 already says it is
one undo step; the summary paragraph should agree.)

## Improvements (judgment, not required)

- **I1. Context menus leave the Remove item out during an import, the menu
  bar dims it.** That is the UID P2 rule and correct. The user guide (line
  188) says only "dimmed"; adding "and left out of the context menus" would
  match what people see. Optional.
- **I2. "Project name" is one catalog key for two uses** (the Import options
  row label and VoiceOver's label for the sidebar field). Identical English,
  and the comment names both, so this is fine now; a translator who wants a
  different form for a spoken label would need a second key. Leave it until a
  localization asks.
- **I3. A rename that never gets the keyboard.** `ProjectNameField` ends the
  edit only when it loses focus after having had it. If the focus request
  were ever dropped (the case `WindowReader` guards against), the row would
  stay a field with no keyboard until Return in it. Script L shows the guard
  works; if it ever fails in M2, end the edit when the sidebar selection
  changes as well.

## What's working (keep it)

- One File menu that reads as two groups: commands on the sidebar's selection,
  then commands on the photos' files, with the job items moved away from the
  destructive one.
- The *remove* / *delete* split held everywhere: menus, alerts, Activity,
  announcements and the guide.
- System components throughout: `confirmationDialog`, `RenameButton` with
  `renameAction`, `NSMenu` items built like the existing ones. No custom
  chrome.
- ⌘⌫ gated like a bare key, so text fields keep their editing key.
- The confirmation is read from the catalog before it is shown, so the file
  count includes pair partners the grid doesn't hold, and a second ⌘⌫ cannot
  ask twice.
- Show in Finder's menu validation never touches the disk for photos, and the
  project folder check is off the main actor.

## Manual checks for a person

Run the bundle with `--library-root` on a scratch library, with the app
frontmost (these need a key window). The library should have a project
imported from a folder, one imported from a card's root, a RAW+JPEG pair, a
video, an album and a smart album in a project, and a disk image that can be
detached for offline photos.

- **M1. Rename field look.** Start a rename. The name becomes a field in the
  same font and position; the folder symbol and the count badge stay; the row
  keeps its height; the whole name is selected. Hover the row afterwards: the
  tooltip still shows the folder's path with its old name.
- **M2. Rename routes and endings.** (a) Select a project; File ▸ shows
  "Rename “‹name›”" with no ellipsis, enabled; choose it. (b) Right-click a
  project ▸ Rename. (c) Click a project row, press Return. In each: Return
  saves; Escape restores; Tab saves; clicking a photo in the grid saves and the
  grid keeps the click. After Return or Escape the sidebar selection is in the
  accent color (the sidebar has the keyboard). Edit ▸ shows "Undo Rename
  Project".
- **M3. Empty name.** Delete the whole name and press Return: the alert sound
  plays, the old name comes back, no undo step is added.
- **M4. Show in Finder, photos.** Select three photos from one folder, ⇧⌘R:
  one Finder window with the three files selected. Select photos from two
  folders: two windows. A grouped pair: the RAW is selected. With View ▸ Group
  RAW+JPEG Pairs off, the JPEG cell: the JPEG is selected. Detach the disk
  image, select only its photos: File ▸ Show in Finder is dimmed and absent
  from the context menu; select a mix: the online files open and Activity
  shows one information row.
- **M5. Show in Finder, projects.** Click a project in the sidebar so the
  sidebar has the keyboard, ⇧⌘R: the Finder shows the project's folder
  selected in its parent. Click an album in the sidebar: File ▸ Show in Finder
  is dimmed. Click a photo in the grid with the project still selected in the
  sidebar, ⇧⌘R: the photo is revealed, not the folder. The card-root project
  has no Show in Finder in its row menu and the File item is dimmed for it.
- **M6. Both confirmations, on macOS 27, 26 and 15.** Return does nothing.
  Escape cancels. ⌘. cancels. Start an export, then open a confirmation and
  press ⌘.: the confirmation closes and the export keeps running. Look: the
  title is shown, Remove is red, the app icon (no caution triangle), no "Don't
  ask again" box. If Return removes on any of these systems, design §6.2's
  `NSAlert` fallback applies.
- **M7. ⌘⌫ in text fields.** Type in the toolbar's search field, the ⌘K
  keyword field, an Info tab field (Title) and the project rename field, then
  press ⌘⌫ in each: text before the insertion point is deleted and no
  confirmation appears. With a sidebar row selected and the sidebar focused,
  ⌘⌫ does nothing and File ▸ Remove from Library… is dimmed.
- **M8. File menu states.** Project selected in the sidebar: Rename
  “‹name›” enabled, Delete… dimmed, Remove Project from Library… enabled. Album
  selected: Remove Project from Library… dimmed, "Delete “‹name›”…" enabled.
  Grid focused with a selection: Remove from Library… ⌘⌫ enabled; no
  selection: dimmed.
- **M9. Dimmed while busy.** While the confirmation is up, the library's File
  menu items are dimmed. While a folder add or a card import runs, both Remove
  items are dimmed in the File menu, Remove from Library… is absent from the
  photo menus, and Remove Project from Library… is absent from the project
  row's menu; they come back when it ends.
- **M10. After a photo removal.** Edit ▸ Undo is dimmed. The photo after the
  last removed one is selected; in the loupe, that photo is shown. Remove every
  photo of a project from the loupe: the window returns to the grid with the
  project's empty state.
- **M11. VoiceOver.** The confirmation is read in full (title, message,
  buttons). After a removal VoiceOver says "Removed “‹file›” from the
  library." or "Removed ‹N› photos from the library."; after a project
  removal "Removed the project “‹name›” from the library."; after an empty
  name "The name can't be empty." The rename field is announced as "Project
  name". VO-Shift-M on a project row lists Rename, Show in Finder and Remove
  Project from Library….
- **M12. Project removal and selection.** Remove the selected project: the
  sidebar selects All Photos and keeps the keyboard. Right-click a project that
  is not selected and remove it: the selection stays where it was. Remove a
  project while one of its albums is selected: All Photos is selected.
- **M13. Sidebar menu look.** Right-click a project row: Remove Project from
  Library… is last, after a separator, styled as the album rows' Delete… items
  are (D-L6).
- **M14. Activity during a long removal** (after F1). Remove a few thousand
  photos: the Activity item shows "Remove from Library" with "Removing ‹N›
  photos…" under it, indeterminate, with no Stop button; File ▸ Stop does not
  name it.

## Requirements issues

None from this review. The engineer's two (status.md: whether a removal also
deletes cached previews; a sidecar change still queued at removal is dropped)
go to the product manager as raised.

## Follow-ups

None proposed. The design's optional "rename albums in place" is still the
owner's call (prd.md, Open questions) and is not proposed here.

## Second pass

Date: 2026-11-11. Branch `feature/library-ops` at `38b7f21` (commits
`bef0feb` and `38b7f21` since the first pass). Read, not run: the engineer's
script results in `status.md` are taken as evidence. The owner's rulings on
the code review's Q1–Q3 are recorded in [`design.md`](design.md) §15 as
D-L8–D-L10, with D-L1–D-L7 summarized there; §6.3 is amended for D-L8.

**Verdict: Pass. Both findings are resolved; no new findings.**

| Ref | Earlier finding or change | Result | Evidence |
|---|---|---|---|
| F1 | Photo removal's Activity job titled with the command | **Resolved** | `LibraryOpsActions.swift`: `RemovalJob(title: LibraryOpsText.removeFromLibrary, detail: LibraryOpsText.removing(count))`, the same shape as the project's; catalog comments say "Activity job and row title". Script: "Activity job 'Remove from Library' detail 'Removing 30,000 photos…'" |
| F2 | User guide's Undo paragraph lists project renames | **Resolved** | `USER_GUIDE.md` line 465 lists project renames; line 467 adds that removals cannot be undone, which agrees with §6.3 and the confirmation |
| I1 | Guide says "dimmed" only | **Taken** | Lines 188–190: "dimmed, and left out of the context menus", for both Remove commands |
| I2, I3 | | Left, as the first pass allowed | |
| D-L8 (Q1) | Focus after a removal that did not take the focused photo | **Pass** | `RemovalFocus.index(count:focus:isRemoved:)` returns the focus first when it is in range and not removed, then falls back to §6.3's rule; `removalDidFinish` passes `focusIndex`. Tests `focusSurvivesARemovalElsewhere` and `focusAfterRemoval`; script: the loupe stays on the photo it showed while another project is removed from its row's menu. The rule also covers a grid where the focused cell was ⌘-clicked out of the selection: the person's place is kept, which is the right result |
| D-L9, D-L10 (Q2, Q3) | No change by ruling | **Not applicable** | Follow-ups #143 and #144 |
| User guide terms | Wording after `bef0feb` | **Pass** | Lines 174–200: *remove* for photos and projects, *delete* only for library-only things and for text in a field; menu names and keys match §2.1 and §3 |

**Manual checks.** M1–M14 stand. M14 can now be checked as written (F1 is
in). One added for D-L8:

- **M15. Focus kept when the focused photo survives.** In All Photos, open a
  photo of project A in the loupe. Right-click project B in the sidebar ▸
  Remove Project from Library… ▸ Remove: the loupe still shows the same
  photo, and back in the grid it is the focused cell. Then press ⌘⌫ on that
  photo and confirm: the loupe moves to the photo that followed it.

**Requirements issues:** none. **Follow-ups:** none beyond #143 and #144,
already filed.
