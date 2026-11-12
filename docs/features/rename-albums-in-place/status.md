Issue: #141

# Rename albums in place: status

Owner: swift-macos-engineer. Branch: `feature/rename-albums-in-place`. State: **Done** (2026-11-11).
Every criterion is built; each has a unit test, a debug-script check, or both, except what
needs a key window or a person's eyes and ears (**For a person**). Nothing is blocked. One
requirements issue and one note for the designer are at the end; neither holds the work.

Spec: [`prd.md`](prd.md) (R1–R9, AC1–AC10), [`design.md`](design.md) (§7 A1–A11).
The implementation is commits `ea5a84a` (PhotoCore rules and tests; builds on its own) and
`1f14384` (the app, strings, debug script and user guide).

## Results

| | Baseline (`fcc9058`) | Now |
|---|---|---|
| `swift build` | clean, no warnings | clean, no warnings |
| `swift test` | 724 tests in 118 suites passed, 1 known issue | 731 tests in 119 suites passed, the same 1 known issue |
| `Scripts/build-app.sh all` | not run | both bundles built |

New suite: `AlbumRenameTests` (7 tests). `LibraryOpsRuleTests` calls the name rule by its
new name.

## What was built

- **PhotoCore** (no AppKit or SwiftUI, tested):
  - `Catalog/InPlaceRename.swift`: the name rule, now shared by projects and albums. It is
    `ProjectRename` under a neutral name, unchanged (trim, refuse empty, unchanged is a
    no-op).
  - `Browser/SidebarRename.swift`: `SidebarRenameRoute` (a project or an album renames in
    its row, a keyword in a sheet, a smart album has no Rename; only the sheet's title has
    an ellipsis) and `SidebarRowPlace` (the section, and for a project's album the project,
    to open before the row is edited).
  - `AlbumSummary.isListedBefore` (`Catalog/Albums.swift`): the catalog's album order
    (`name COLLATE NOCASE, id`) in memory, so a renamed album takes its place before the
    write lands.
- **PhotoApp**:
  - `Model/SidebarRenameActions.swift`: `SidebarRename` (the row being renamed and the text
    so far), `beginSidebarRename` and `endSidebarRename` for both kinds of row, replacing
    `beginProjectRename` / `endProjectRename` and `renamingProjectID`. One rename at a time:
    starting another saves the open one (design §2.3).
  - `Model/AlbumActions.swift`: `renameAlbum` shows the name at once, sorts, scrolls the row
    into view, then writes; undo name "Rename Album" as before.
  - `Views/SidebarView.swift`: album rows have `renameAction`, `RenameButton`, a separator and
    Delete…; the smart album menu gained its separator; one name field for both kinds of row
    (`SidebarNameField`, its accessibility label a parameter); Return starts a rename on a
    project or album row only; the reveal handler opens the Albums section, or Projects and
    the album's project.
  - `Views/LibraryCommands.swift`, `LibraryMenuContext.swift`: File ▸ Rename starts the
    in-place rename for an album; its title has no ellipsis for a project or an album.
  - `SidebarSheet.renameAlbum` and its sheet are gone (`SmartAlbumEditor.swift`).
- **String Catalog**: one new key, "Album name". Comments updated on "Rename “%@”" (project
  or album), "Rename “%@”…" (keyword only), "The name can't be empty." and "Rename Album"
  (undo only). No key became unused: "Rename Album" is still the undo name, and "Rename" and
  "Name" are still the keyword sheet's.
- **Debug script** (`Model/DebugLibraryOpsCommands.swift`, `DebugScript.swift`):
  `renamealbum [<n>]`, `print albums`, `projectalbum <name>`, `sidebarpane on|off`,
  `sidebarsection <name> expand|collapse`; `print menustate` gained `rename
  inPlace|sheet|none`.
- **`docs/USER_GUIDE.md`**: the rename paragraph covers projects and albums, the
  albums paragraph's last sentence, and the Undo paragraph (design §6).

## The PRD's questions for the engineer

**A3: does today's album rule collapse inner spaces, and does it match the project rule?**
It does collapse them, and it does not match. The removed sheet used
`Catalog.normalizedKeywordName`, which trims, turns every run of white space inside the name
into one space, and cuts the name at 200 characters. The project rule (`ProjectRename`, now
`InPlaceRename`) only trims. Design §2.4 says the rule is the one the project uses, so both
now use `InPlaceRename`: " Best   of " saves as "Best   of" for an album as for a project
(`innerWhiteSpaceIsKept`). Two differences from the old sheet follow, and one mismatch
remains with New Album; see **Requirements issues**.

**Can the project rename's focus and field code be shared, and what labels the field?**
Yes: one field view serves both rows. Its label is "Project name" on a project row and
"Album name" on an album row (`SidebarRenameText.fieldLabel(for:)`).

## Acceptance criteria

"Script" is a debug-script run against a copy of the bundle (identifier
`me.sesser.gus.debugtest.rename-albums`) on a scratch library; see **Debug-script results**.

| AC | Test | Script | Left for a person |
|---|---|---|---|
| AC1 | `renamingAnAlbum` (stored after reopening, in the library and in a project) | S1: File ▸ Rename's action, the row menu's Rename, Return in the sidebar; whole name selected; Return saves; name kept after relaunch | M1; the menu bar item itself (K1) |
| AC2 | — | S2: Escape keeps the old name; taking the keyboard elsewhere saves; "5" and "p" are typed into the name and no rating or flag changes | M2 (a real click in the grid) |
| AC3 | `albumNameRule`, `innerWhiteSpaceIsKept`, `renamingAnAlbum` (two albums, one name) | S3: "  Trip  " saves "Trip"; empty and white-space-only refused with the announcement; same name adds no "Rename Album" step; a duplicate name saves | M2 (the alert sound) |
| AC4 | — | S3: undo "Rename Album" restores, redo reapplies; S7: the row moves back and forth | K1 (Edit menu's title) |
| AC5 | `renameRoutes` | S4: row menu is Rename, —, Delete…; File title "Rename “‹name›”". Search: no `renameAlbum` case in `SidebarSheet`, no album route to a sheet | K1 |
| AC6 | `renameRoutes`, `renamingOntoAnotherKeywordMergesAndCanBeUndone` (KeywordTests, existing) | S4: keyword row menu Rename…, Delete… and its sheet opens; File title "Rename “dog”…"; smart album menu Edit…, —, Delete…; File title "Rename…"; Return on either row starts nothing | The keyword sheet's text (not readable by the script; its code is unchanged) |
| AC7 | `renamingAnAlbumChangesOnlyItsName` | S5: with sidecar writing on, every file's size and date unchanged, queue 0, members and count unchanged | |
| AC8 | — | The script cannot read the label (see below); the announcement is posted (S3, `print announcement`) | Not asked of the owner (PRD A2) |
| AC9 | `rowPlace`, `renamedAlbumTakesItsPlaceInTheList` | S6: sidebar hidden, Albums hidden, Albums collapsed, all three; a project's album with Projects hidden and collapsed and its project collapsed. S7: moved row selected and in view; unselected row keeps the selection | M3 |
| AC10 | — | — | `docs/USER_GUIDE.md`, read at review |

**AC8, the label.** The field's label is set with SwiftUI's `accessibilityLabel`. It is not
on the AppKit text field (`accessibilityLabel()` is empty there, for the project's field
too), and SwiftUI builds its accessibility tree only for an attached assistive app, so the
debug script's listing finds no element for it. Built, not verified.

## Design §7

| # | State | Check |
|---|---|---|
| A1 | Done | S4; M1 |
| A2 | Done | `renameRoutes`; S4 (the title the item is built from). The item's enabled state and a press need a key window: K1 |
| A3 | Done | S1, S4 |
| A4 | Done | `albumNameRule`; S1, S3 |
| A5 | Done | `rowPlace`; S6 |
| A6 | Done | `renamedAlbumTakesItsPlaceInTheList`; S7 |
| A7 | Done | Search: `grep -rn renameAlbum Sources` finds the model's `renameAlbum`, the catalog's and the debug command, no sheet case |
| A8 | Done | S4 |
| A9 | Done | `renamingAnAlbumChangesOnlyItsName`; S5 |
| A10 | Built, not verifiable by script | see AC8 |
| A11 | Done | `docs/USER_GUIDE.md` |

## Debug-script results

On macOS 27.2. Setup, in a scratch folder `$M`:

```
Scripts/build-app.sh
cp -R build/Gus.app $M/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.rename-albums $M/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $M/Gus.app
swift run -c release photobench generate --output $M/src/Iceland --jpeg 5 --dng 1 --videos 0 --pairs 1
swift run -c release photobench generate --output $M/src/Keep --jpeg 3 --dng 0 --videos 0 --pairs 0
swift run -c release photobench import --library-root $M/lib --source $M/src/Iceland
swift run -c release photobench import --library-root $M/lib --source $M/src/Keep
$M/Gus.app/Contents/MacOS/Gus --library-root $M/lib --debug-script "<script>"
```

Library: projects "Iceland" and "Keep"; library albums "Alps", "Best of", "Zoo"; "Selects"
in Iceland; a smart album "Rated"; keywords "dog" and "puppy"
(`project 1; selectall; album Best of; … projectalbum Selects; smartalbum Rated; addkeywords dog`).
Later 45 more albums ("Row 01" … "Row 45") so the sidebar scrolls. S1–S4 were run again on
the final bundle with a second library made the same way.

**macOS would not make the test copy the active app** (`open -W -n … --args --library-root …`,
then System Events by process id: `print responder` stayed at `key nil`), as in earlier
features. Without a key window every library menu item is dimmed and `menupress` does
nothing, so the scripts drive what the items call (`renamealbum` is File ▸ Rename's action;
`print albums` prints the title from the function the item uses). The menu bar itself is K1.

In a script, `key` and `text` each open an undo group, and an empty group shows as an undo
step with no name (`undo ''`). That is the script's doing: the app groups by event and
records no empty step.

- **S1, routes and saving.** `sidebar album 1; renamealbum; print albums`: `renaming 1 field
  'Best of' selected 0..<7 in view true`. `text Iceland best of; key return`: the row shows
  the new name, `undo 'Rename Album'`, the sidebar's list has the keyboard, the window title
  follows. After a relaunch the name is kept. `contextmenu at 100 300 Rename` on a row that is
  not selected, and `sidebarfocus; key return` on the selected album, start it the same way.
- **S2, endings.** `key escape`: old name, no "Rename Album" step, list keeps the keyboard.
  With the field open, `key 5 p`: field '5p'; Unrated 160 and Picks 0 before and after.
  `sidebarfocus` (the keyboard leaves the field): saved, one "Rename Album" step.
- **S3, rules and undo.** `text   Trip  ; key return` saves "Trip". `key delete; key return`
  and a name of spaces: old name stays, `announcement The name can't be empty.` On a fresh
  launch, `renamealbum; key return` (same name): `undo ''`, not "Rename Album". "Selects" to
  "Zoo" beside the library's "Zoo": both listed. `undo`: "Selects" again, `redo 'Rename
  Album'`; `redo`: "Zoo" again.
- **S4, menus and the other rows.** Album row: `Rename`, `—`, `Delete…`. Smart album row:
  `Edit…`, `—`, `Delete…`; Edit… opens its sheet. Keyword row: `Rename…`, `Delete…`; Rename…
  opens a sheet. `print albums` with an album selected: `File 'Rename “Best of”'`; a keyword:
  `File 'Rename “dog”…'`, `rename sheet`; a smart album: `File 'Rename…'`, `rename none`.
  `sidebarfocus; key return` on the smart album and on the keyword: no field, `alert none`.
- **S5, catalog only.** `sidecars on`, then rename "Best of" (107 photos): the size and date
  of every file under the source folders unchanged, the two existing sidecars unchanged, no
  new one, `sidecarQueue` 0, `albumMember` 155 before and after, the album still 107.
- **S6, showing the row.** With `sidebarpane off`; with `sidebarsection albums hide`; with
  `sidebarsection albums collapse`; with all three: `renamealbum` gives `sidebar shown`,
  `hidden sections []`, `renaming … field 'Best of' selected 0..<7 in view true`. "Selects"
  with `sidebarsection projects collapse; sidebarsection projects hide` and Iceland
  collapsed: before `row not in the list`, after `field 'Selects' … in view true`.
- **S7, moving rows** (49 albums, the list 1,968 points in an 860-point sidebar). "Alpine"
  (first, selected) to "Zz moved": `selected 48 row in view true`, the sidebar scrolled from
  `-52..<808` to `919..<1779`, the list has the keyboard. `undo`: first again and in view;
  `redo`: last again and in view. With "Best of" selected at the top, `renamealbum 48` (out
  of view): the sidebar scrolls to the field; saved as "Aa moved" it is first, the selection
  is still "Best of", and the sidebar scrolled back (`191..<1051`), where selecting the
  renamed album shows its row in view without scrolling.
- **S8, one rename at a time.** `renamealbum; text Alpine; renamealbum 3`: "Alpine" saved
  ("Rename Album"), the field is on "Zoo". `text Zebra; renameproject`: "Zebra" saved, the
  field is on the project. `text Kept; renamealbum 1`: "Kept" saved, the field is on the album.
- **Project rename, unchanged.** `renameproject`, trim, "Rename Project", Return in the
  sidebar, Escape, an empty name refused with the announcement.

## For a person (not checked by me)

- **K1, the menu bar** (needs the app in front). With an album selected: File ▸ Rename
  “‹name›” has no ellipsis, is enabled, and puts the row into editing. After a rename Edit
  shows "Undo Rename Album", then "Redo Rename Album". With a keyword selected the item is
  "Rename “‹name›”…" and opens the sheet with its merge note; with a smart album it is
  "Rename…", dimmed.
- **M1, look** (design §7). Each route turns the name into a field in place, whole name
  selected; the symbol and count stay; the row keeps its height; side by side it matches a
  project rename.
- **M2, endings.** Escape restores; a click on a photo saves; "5" and "P" typed in the field
  change no photo; an emptied name plays the alert sound and keeps the old name.
- **M3, moving row.** Rename an album so it sorts elsewhere: it moves, stays selected and
  visible, and the sidebar keeps the accent-colored selection.

VoiceOver (the field's label, the announcement) is not put to the owner (PRD A2).

## Decisions within the spec

- **One rename state for both rows**, as design §2.3 allows: `LibraryModel.sidebarRename`.
  The typed text lives in it rather than in the field, so that starting a rename on another
  row can save the open one first; a field that is no longer the open rename is ignored,
  which also makes each rename end once.
- **`ProjectRename` became `InPlaceRename`** (PRD: "shares the generic name-rule … engineer's
  call"). The rule did not change.
- **The row moves at once.** `renameAlbum` changes the name in memory and sorts with
  `AlbumSummary.isListedBefore`, which a test holds to the catalog's order; the refresh
  after the write then changes nothing.
- **After a save, undo or redo the sidebar only scrolls.** It does not open a section or a
  project that is folded away: the person folded it, and an undo should not unfold the
  sidebar. Opening is for File ▸ Rename (design §2.5). See the note for the designer.
- **A project rename does not scroll after saving**, as before: projects are listed by
  date, so the row does not move.
- **Album rows are identified by their sidebar selection**, as project rows are, so
  `scrollTo` finds them. Their identity was the album's uuid; both are stable across a rename.

## Noticed, not changed

- At launch the app logs "WARNING: Application performed a reentrant operation in its
  NSTableView delegate. This warning will become an assert in the future." It is not from
  this change: a bundle built from the commit before the app change logs it too, on the same
  library, whichever sidebar row was selected at the last quit. Proposed as a bug below.

## Requirements issues (for the product manager)

- **RI-RA1. New Album and Rename now treat inner white space differently.** PRD A3 asks for
  one behavior for projects and albums and design §2.4 picks the project's rule, so an
  album renamed in place keeps runs of spaces inside its name and has no length limit. The
  removed sheet collapsed inner white space to single spaces and cut names at 200 characters
  (`Catalog.normalizedKeywordName`), and the New Album and New Smart Album sheets still do
  (creation is a non-goal here). So "Best   of" typed into New Album becomes "Best of", and
  the same text typed into Rename stays "Best   of". Options: (a) leave it (no data is
  harmed; names differ only when someone types several spaces); (b) a follow-up that gives
  New Album, New Smart Album and the smart album editor the in-place rule; (c) change the
  in-place rule to collapse and cap for both projects and albums, which changes shipped
  project renaming. I built (a), which is what the spec says, and recommend (b) as a small
  follow-up if the difference matters.

## For the designer (no ruling needed to ship)

- **§2.5, "undo and redo move the row back and forth the same way".** Built as: the row
  moves and is scrolled into view when it is in the list, but a collapsed section or
  project is not opened by a save, an undo or a redo. If the design wants undo to open them,
  it is one argument (`revealSidebarRow(_:opening:)`).

## README

For the product manager at Ship:

- `README.md` line 37 says "Rename a project in place"; albums rename in place too.
- `CLAUDE.md` "Scope so far" (Library operations) names `Catalog/ProjectRename.swift`; the
  file is now `Catalog/InPlaceRename.swift` and the type `InPlaceRename`.
  `docs/features/_inventory.md` names it as well.
- No change to requirements, build commands or the repository layout.

## Follow-ups proposed (for the main session to file)

- **Enhancement: "One white-space rule for album names (New Album and Rename)"**, if the
  product manager takes RI-RA1 option (b).
- **Bug: "NSTableView reentrant-operation warning at launch"**. On macOS 27.2 the library
  app logs AppKit's warning about a reentrant operation in an NSTableView delegate about a
  second after launch (seen with a library that has albums and keywords; not seen in one run
  on a library with neither). AppKit says it will become an assert. Present on `develop`
  (`fcc9058`); the sidebar's SwiftUI `List` is the likely table. Not investigated further.
