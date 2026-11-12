# Rename albums in place: QA

Owner: qa-tester. Date: 2026-11-11. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/rename-albums-in-place` at `44ffc96`, on a Mac16,8, macOS 27.2.1 (26B131), macOS 27.2 SDK
(`vtool -show-build`: minos 15.0, sdk 27.2), Swift 6.4.2.
Issue: #141. Read against [`prd.md`](prd.md) (AC1–AC10), [`design.md`](design.md) (§7, D-RA1, D-RA2),
[`status.md`](status.md), [`code-review.md`](code-review.md) and [`review.md`](review.md).

## Verdict

Passes. Every acceptance criterion passes by test, by script or both, except what needs a key window or
someone looking and listening (the P list). The rename also saves as one "Rename Album" (or "Rename
Project") step that undo restores when the row leaves the list (section hidden or folded, project folded,
sidebar hidden, review on). There are no blocking findings. Q1 is open until a person checks P5(d). Q2 and
Q3 are nits.

`swift test`: 732 tests in 119 suites passed, 1 known issue (`LiveSessionTests`, "Values above white
survive the cached stages", the same as on `develop`). `swift test --filter
'AlbumRenameTests|LibraryOpsRuleTests|renamingOntoAnotherKeywordMergesAndCanBeUndone|LocalizationTests|BrandingTests'`:
31 tests in 5 suites passed. `Scripts/build-app.sh`: built.

## Acceptance criteria

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Test, Script | `AlbumRenameTests.renamingAnAlbum` (stored after reopening, library and project album). S1: File ▸ Rename's action, the row menu's real Rename (`contextmenu at … Rename`, a row that is not selected), Return in the sidebar; each gives a field with the whole name selected; Return saves; name kept after relaunch. Menu bar item itself: P4 | Pass |
| AC2 | Script | S2: Escape keeps the old name; `sidebarfocus` (the keyboard leaves the field) saves; "5" and "p" go into the field and no photo is rated or picked (a "3" in the grid does rate, as a control). A real click in the grid: P2 | Pass |
| AC3 | Test, Script | `albumNameRule`, `innerWhiteSpaceIsKept`, `renamingAnAlbum` (two albums, one name). S3: "  Trip  " saves "Trip"; empty and spaces-only refused, old name kept, announcement posted; same name adds no "Rename Album" step; a duplicate name saves. The alert sound: P2 | Pass |
| AC4 | Script | S3: `undo 'Rename Album'`; undo restores, redo reapplies (also S7 with the row moving). Edit menu titles: P4 | Pass |
| AC5 | Test, Script, search | `renameRoutes`. S4: album row menu `Rename`, `—`, `Delete…`; File title `Rename “‹name›”` (no ellipsis); Rename opens no sheet (`sheet or alert none`). Search: `SidebarSheet` has `renameKeyword`, `newAlbum`, `smartAlbum` only (`develop` had `renameAlbum` and `Button("Rename…")`) | Pass |
| AC6 | Test, Script | `renameRoutes`; `KeywordTests.renamingOntoAnotherKeywordMergesAndCanBeUndone` (unchanged, passes). S4: keyword row menu `Rename…`, `Delete…`, Rename… opens a sheet (`SheetPresentationWindow`); File `Rename “dog”…`, `rename sheet`; smart album menu `Edit…`, `—`, `Delete…`, Edit… opens a sheet; File `Rename…`, `rename none`; Return on either row starts nothing. The sheet's merge note text: P4 | Pass |
| AC7 | Test, Script | `renamingAnAlbumChangesOnlyItsName`. S5: sidecars on, 318 files under the sources (107 sidecars among them) unchanged in size and date, `albumMember` 324 before and after, each album's count unchanged, `sidecarQueue` 0 | Pass |
| AC8 | Script (announcement); reading (label) | S3: `announcement The name can't be empty.` The "Album name" label is SwiftUI's and is not reachable by the script (`status.md` AC8); `SidebarRenameText.fieldLabel(for:)` read. VoiceOver is not put to the owner (PRD A2) | Open (label, not asked) |
| AC9 | Test, Script | `rowPlace`, `renamedAlbumTakesItsPlaceInTheList`, `rowLeavesTheList`. S6: sidebar hidden, Albums hidden, Albums collapsed, all three; a project's album with Projects hidden and collapsed: each gives `sidebar shown`, `hidden sections []`, the field in view. S7: moved row selected and in view; from an unselected row's menu the selection stays and the sidebar scrolls to the renamed row. Accent-colored selection: P3 | Pass |
| AC10 | Read | `docs/USER_GUIDE.md` 146–160 and 468: routes, Rename with no ellipsis, "Right-click an album to rename or delete it, or a smart album to edit or delete it", folding or hiding saves, Undo paragraph lists album renames | Pass |

Design §7 A1–A11 are covered by the rows above (A1 S4, A2 S4 and P4, A3 S1 and S4, A4 S3, A5 S6, A6 S7,
A7 search, A8 S4, A9 S5, A10 AC8, A11 AC10).

**Row leaves the list** (code review C1 and C2, design D-RA2): Script L1–L3. Pass: in every case below the
typed name is saved as one step, `undo` restores the old name, nothing crashes, and the list keeps the
keyboard when the sidebar is still shown.

**Which tests fail without the branch.** `renameRoutes`, `rowPlace`, `renamedAlbumTakesItsPlaceInTheList`
and `rowLeavesTheList` use types that `develop` does not have (`SidebarRenameRoute`, `SidebarRowPlace`,
`SidebarListState`, `isListedBefore`, `InPlaceRename`; `git grep` on `develop` finds none), so they cannot
compile there. `renamingAnAlbum` and `renamingAnAlbumChangesOnlyItsName` call the unchanged
`Catalog.renameAlbum`. They pin AC1's storage and AC7, and they would pass on `develop` too (code review,
Coverage). The routes, endings and undo live in `PhotoApp`, which has no test target, so they rest on the
scripts.

**Known difference, pending a follow-up (RI-RA1).** New Album (and New Smart Album) collapse runs of
spaces inside a name and cut it at 200 characters (`Catalog.normalizedKeywordName`). Renaming in place
keeps inner spaces and has no length limit, the same as for projects (PRD A3, design §2.4). So "Best   of"
becomes "Best of" in New Album but stays "Best   of" when renamed. This is as specified. The product
manager rules on it, and the designer recommends option (b) as a follow-up issue. It is not a finding here.

## Findings

**Q1 (Should, open until P5(d)). Hiding the sidebar during a rename leaves the keyboard on the window.**
Steps: `sidebar album 0; focus 0; renamealbum; text Aardvark; sidebarpane off; print responder; key 3`.
Expected (review M5(d)): the name is saved, and a rating key rates the selected photo. Actual: the name is
saved (`undo 'Rename Album'`), but `print responder` shows `first AppKitWindow` and the "3" rates nothing
(`rating 1` filter: 0 of 107). A project rename does the same. Without a rename open, hiding the sidebar
while its list has the keyboard sends the keyboard to the toolbar's search field (`first NSTextView`; the
"3" is typed into the search). So the two cases differ, and in neither does the keyboard reach the grid.
Caveat: the scripted process has no key window, so the result on screen may differ. `develop` has no
`sidebarpane` command, so I could not compare it there. If P5(d) shows the same result, the reviewer's
suggestion applies (`review.md`, Second pass): when a rename ends with the sidebar hidden, post
`.browserShouldTakeFocus` with the model.

**Q2 (Nit, debug script). Selection commands save an open typed rename outside an undo group, and the app
crashes.** Steps: `sidebar album 0; renamealbum; text Alpine2; project 1`. Expected: the script header
lists every command that ends a rename outside a group, or such commands group while a rename is open.
Actual: the process stops with exit 133 (`EXC_BREAKPOINT` in `+[NSApplication _crashOnException:]`), which
is the ungrouped `registerUndo` that CLAUDE.md describes. With no typed text, or with `sidebarfocus` first,
it does not crash. The header (`DebugScript.swift:128-130`) names only `click` and `loupe`. `project`,
`sidebar` and `keyword` change the sidebar selection and do the same. The app is not affected, because it
groups by event. Either add these three to the header's list or to `endsRename`.

**Q3 (Nit, relayed from code review C5).** `status.md` lines 15 and 236 name the code review's commit as
`227ed46`, which is not on the branch. The commit is `f85a2b1`.

## Scripts

Setup. The scratch folder `$M` was under the session scratchpad and was deleted afterwards:

```
Scripts/build-app.sh
cp -R build/Gus.app $M/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.rename-albums-qa $M/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $M/Gus.app
swift run -c release photobench generate --output $M/src/Iceland --jpeg 5 --dng 1 --videos 0 --pairs 1
swift run -c release photobench generate --output $M/src/Keep --jpeg 3 --dng 0 --videos 0 --pairs 0
swift run -c release photobench import --library-root $M/lib --source $M/src/Iceland
swift run -c release photobench import --library-root $M/lib --source $M/src/Keep
$M/Gus.app/Contents/MacOS/Gus --library-root $M/lib --debug-script "wait 2; project 1; wait 1; selectall; album Best of; album Alps; album Zoo; projectalbum Selects; smartalbum Rated; addkeywords dog, puppy; wait 2; print albums; quit"
```

This gives the projects Keep and Iceland, and the albums 0 Alps, 1 Best of, 2 Selects (in Iceland) and
3 Zoo (107 photos each, Selects empty), the smart album Rated, and the keywords dog and puppy. Each check
ran as `$M/Gus.app/Contents/MacOS/Gus --library-root <copy of lib> --debug-script "…"`. Most started from
a fresh copy of the base library. Row indexes follow `print albums`. `print albums` lists are shortened
below.

- **S1, routes and saving.**
  `wait 2; sidebar album 1; wait 1; renamealbum; wait 1; print albums; print menustate; text Iceland best of; key return; wait 1; print albums; print undo; print responder; print title; quit`
  printed `renaming 1 field 'Best of' selected 0..<7 in view true`, `rename inPlace`, then `Iceland best
  of=107 … selected 1 row in view true`, `File 'Rename “Iceland best of”'`, `undo 'Rename Album'`,
  `first SwiftUIOutlineListView`, and the window title `Iceland best of`. A relaunch with
  `wait 2; print albums; quit` printed `Iceland best of=107`.
  `sidebar album 0; renamealbum 3` printed `selected 0 … renaming 3 field 'Zoo' selected 0..<3`.
  `sidebar album 1; sidebarfocus; key return` printed `renaming 1 field 'Iceland best of' selected 0..<15`.
  The real row menu: `sidebar album 0; contextmenu at 100 350 Rename; print albums; text Trip2; key return; print albums; print undo`
  printed `selected 0 … renaming 1 field 'Iceland best of' selected 0..<15`, then `Trip2=107`, still
  `selected 0` (Alps), and `undo 'Rename Album'`.
- **S2, endings.**
  `sidebar album 0; focus 0; renamealbum; print responder; key 5 p; print albums; key escape; print albums; rating 1; print title; rating any; flag picked; print title`
  printed `first _SystemTextFieldFieldEditor`, then `field '5p'`, then the old name and no rename open.
  Both filters gave `0 of 107`. The control `focus 0; key 3; rating 1; print title` gave `1 of 107`.
  `renamealbum; key escape; print undo` printed `undo ''`, which is the script's empty key group
  (`status.md`), not "Rename Album". `renamealbum; key 5 p; sidebarfocus; print albums; print undo`
  printed `5p=107` and `undo 'Rename Album'`.
- **S3, rules and undo.** `renamealbum; text   Trip  ; key return` saved `Trip`.
  `sidebar album 3; renamealbum; key delete; key return; print albums; print announcement`, then a name of
  spaces, kept `Zoo` and printed `announcement The name can't be empty.` both times.
  `renamealbum; key return; print undo` printed `undo ''`.
  `sidebar album 1; renamealbum; text Zoo; key return` saved `Zoo=107, Zoo=0 in Iceland` (album 1 was
  Selects by then), with `undo 'Rename Album'`. `undo` gave back `Selects` and `redo 'Rename Album'`.
  `redo` gave `Zoo` again. Both names were kept after a relaunch.
- **S4, menus and the other rows.** `contextmenu at 100 <y>` down the sidebar printed, for an album:
  `Rename [image]`, `—`, `Delete…`; the smart album: `Edit…`, `—`, `Delete…`; a keyword: `Rename…`,
  `Delete…`. `keyword 0; print albums; print menustate` printed `File 'Rename “dog”…'` and `rename sheet`.
  `sidebar smart 0` printed `File 'Rename…'` and `rename none`. `sidebarfocus; key return` on either row
  printed no `renaming` and `alert none`. `keyword 0; contextmenu at 100 500 Rename…; print messages`
  printed `sheet or alert SheetPresentationWindow ''`. The album row's `Rename` printed `sheet or alert
  none` and a field. The smart album's `Edit…` printed `SheetPresentationWindow`.
- **S5, catalog only.** `sidecars on` was set first, which wrote 107 sidecars. Then
  `sidecars on; sidebar album 1; renamealbum; text Iceland best of; key return; wait 4; print albums`.
  The size and date of all 318 files under `src` matched before and after (`diff` empty). In the catalog,
  `albumMember` was 324 before and after, each album kept 108 / 108 / 108 / 0 rows, and `sidecarQueue`
  was 0.
- **S6, showing the row.** For each of `sidebarpane off`, `sidebarsection albums hide`,
  `sidebarsection albums collapse` and all three, the script ran
  `sidebar album 1; <that>; print albums; renamealbum; wait 2; print albums; sidebarsection`. Before:
  `row in view false` or `row not in the list`. After: `sidebar shown`, `renaming 1 field 'Iceland best
  of' selected 0..<15 in view true`, `hidden sections []`. For the project's album:
  `sidebar album 2; sidebarsection projects collapse; sidebarsection projects hide; renamealbum` printed
  `row not in the list`, then `field 'Selects' selected 0..<7 in view true`, `hidden sections []`.
- **S7, moving rows.** 45 more albums ("Row 01"…"Row 45") were added, so the list was 1,968 points in an
  808-point sidebar. `sidebar album 0; renamealbum; text Zz moved; key return; print albums` printed
  `selected 48 row in view true` and the sidebar at `919..<1779`, with `first SwiftUIOutlineListView`.
  `undo` printed `selected 0 row in view true` and `redo` printed `selected 48 row in view true`. On a
  fresh copy, `sidebar album 1; renamealbum 48` (Zoo, out of view) scrolled to the field (`919..<1779`,
  `in view true`). After `text Aa moved; key return` it printed `selected 2 row in view true` (Best of was
  still selected) and `191..<1051`, and selecting album 0 showed `Aa moved` in view.
- **S8, one rename at a time.**
  `project 1; renamealbum 0; text Alpine; renamealbum 3; print albums; print undo; text Zebra; renameproject; print albums; print projects; print undo; text Kept; renamealbum 1; print projects; print albums; print undo`
  printed `Alpine` saved with the field on `Zoo`, then `Zebra` saved with the field on `Iceland`, then
  `Kept` saved (`undo 'Rename Project'`) with the field on `Best of`.
- **Project rename, unchanged.** `project 1; renameproject; text   Fjords  ; key return` saved `Fjords`
  with `undo 'Rename Project'`. `sidebarfocus; key return` opened the field and `key escape` kept the
  name. An empty name was refused with the announcement.
- **L1, an album with a typed name whose row leaves the list.** For each of `sidebarsection albums hide`,
  `sidebarsection albums collapse`, `sidebarpane off` and `review on`, the script ran
  `sidebar album 1; focus 0; renamealbum; text Trip; <that>; print albums; print undo; print responder; undo; print albums; print undo`.
  Each time `Trip` was saved, `undo 'Rename Album'` was printed, and `undo` gave back `Best of` with
  `redo 'Rename Album'`. The first responder afterwards was `SwiftUIOutlineListView` for hide and collapse,
  `AppKitWindow` for `sidebarpane off` (Q1), and the loupe for review. For `review on` the album needs
  photos in the grid: `review` does nothing without a focused photo.
- **L2, a project's album.**
  `sidebar album 2; renamealbum; text Picks; sidebarsection projects collapse; print albums; print undo; print responder; undo; print albums`
  printed `Picks=0 in Iceland`, `undo 'Rename Album'`, `first SwiftUIOutlineListView`, and then `Selects`
  back.
- **L3, a project.** For each of `sidebarsection projects hide`, `sidebarsection projects collapse`,
  `sidebarpane off` and `review on`, the script ran
  `project 1; focus 0; renameproject; text Kept; <that>; print projects; print undo; print responder; review off; undo; print projects; renameproject; print projects; sidebarsection`.
  Each time `Kept` was saved with `undo 'Rename Project'`, `undo` gave back `Iceland`, and a second
  `renameproject` showed the field again with `hidden sections []`. Without typed text, the code review's
  Q1 script (`renamealbum; sidebarsection albums hide; print albums; renamealbum; print albums`) showed the
  rename ended, then reopened with the section shown (S6).
- **Q1, Q2** scripts are in Findings.

Not scripted: a real click in the grid, folding a project with its own disclosure triangle (the view's
state, see `status.md`), the menu bar (macOS did not make the test copy the active app: `open -W -n`
still printed `key nil`), sounds, and the field's accessibility label.

After the runs, no copy was running, nothing in `~/Library/Application Support/Gus/Library` was newer than
the start, and the test copies' preferences (`me.sesser.gus.debugtest.rename-albums-qa` and
`…-qa-develop`) and crash report were removed.

## For a person

On the bundled app with a scratch library (the main session gives the command). VoiceOver and macOS
15/26 are not on this list, per the owner's standing instruction.

- **P1 (M1), look.** Start an album rename by File ▸ Rename, the row's context menu and Return. The name
  becomes a field in place with the whole name selected. The symbol and count stay, and the row keeps its
  height. Side by side, it looks like a project rename. Do it once on an album under a project.
- **P2 (M2), endings.** Escape restores the old name. Clicking a photo in the grid saves the typed name.
  Typing "5" and "P" in the field changes no photo. An emptied name plays the alert sound and keeps the old
  name.
- **P3 (M3), moving row.** In a sidebar long enough to scroll, rename the selected album so it sorts
  elsewhere. It moves, stays selected and in view, and keeps the accent-colored (keyboard) selection. Press
  ⌘Z: it moves back and stays in view.
- **P4 (M4), menu bar.** With an album selected, File ▸ Rename “‹name›” has no ellipsis, is enabled and
  starts the field. After a rename, Edit shows "Undo Rename Album", then "Redo Rename Album". With a
  keyword selected the item reads "Rename “‹name›”…" and opens the sheet with its merge note. With a smart
  album it reads "Rename…" and is dimmed.
- **P5 (M5), row folded away during a rename.** Start renaming an album, type a new name, then:
  (a) fold the Albums section; (b) for an album under a project, fold the project with its disclosure
  triangle; (c) hide the Albums section with View ▸ Sidebar Sections. Each time the name is saved, Edit
  shows "Undo Rename Album", and the arrow keys then move the sidebar selection. (d) Hide the sidebar
  during a rename: the name is saved, and pressing "3" rates the selected photo. If "3" does nothing,
  report it: that confirms Q1.
- **P6 (code review Q2), scrolling the field away.** With enough albums to scroll, start a rename, type,
  scroll the row well out of view with the wheel and back. Expected: the field is still there with the
  typed text, and Return saves. If the field is gone, File ▸ Rename on the row brings it back with the
  text. Report that as a follow-up bug, not for this branch (the project rename on `develop` behaves the
  same).

## Follow-up

None yet.
