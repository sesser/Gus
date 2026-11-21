# HDR merge: design review

Reviewer: apple-ui-designer. Date: 2026-11-20. Issue: #150. Branch `feature/hdr-merge`.

**Verdict: passes, with two small fixes (F1, F2) and manual checks M1 to M6 for
the owner.** The built UI follows `design.md` closely: the file menu item and
key, the context item, the sheet's anatomy and refusal order, the Activity job,
the quit question, undo and the landing rule are all as designed, built from
system components with no custom chrome. The engineer's four deviations are
ruled in `design.md` §19 (D-H1 to D-H4); none needs a code change. Nothing
here blocks QA.

**What I read.** `design.md`, `status.md`, `Views/MergeSheet.swift`,
`Model/MergeModel.swift`, `Model/MergeText.swift`, the Merge items in
`Views/LibraryCommands.swift`, `Grid/PhotoContextMenu.swift`,
`Views/LibraryMenuContext.swift`, `Views/ActivityToolbarItem.swift`,
`Views/MainView.swift`, `Model/LibraryModal.swift`, `Model/LibraryOpsActions.swift`,
`PhotoApplication.swift`, `PhotoUI/QuitGuard.swift`,
`PhotoCore/Import/QuitConfirmation.swift`, `PhotoCore/Merge/MergeSelection.swift`
and `MergePreflight.swift`, the merge keys in `Localizable.xcstrings`, and
`docs/USER_GUIDE.md`. I did not run the app (no running bundle here) and I
relied on `status.md`'s recorded debug-script output for behavior. I was not
given a copy of the PRD, so the acceptance criteria are taken from the
engineer's table in `status.md` and from the design's citations of them; I
checked the design's requirements, not the PRD's text.

## Design requirements

| # | Requirement (design section) | Result | Evidence |
|---|---|---|---|
| H1 | File ▸ Merge to HDR…, ⇧⌘L, after Duplicate; enabled by `can` (not `canByKey`); dimmed for under two targets, a merge running, a sheet up (§2.1, §3, §4) | Pass | `LibraryCommands.swift` lines 127-129: item directly after Duplicate, `keyboardShortcut("l", [.command, .shift])`, `.disabled(!can { $0.canMerge })`. `LibraryModel.canMerge` is exactly the three conditions. No other `"l"` shortcut in `Sources/`. Enabled state itself needs a key window: M2 |
| H2 | Context menu: grid only, after Duplicate, left out when it can't act; not in loupe, video loupe or comparison (§2.2) | Pass | `PhotoContextMenu.swift`: `merges = state.mode == .grid && state.canMerge`, item after Duplicate, separator logic includes it |
| H3 | The sheet: header with thumbnail, count title, "From ‹source›", refusal first; Photos table in capture order with the Reference mark; Result section with Format, Name, Folder and captions; Cancel and Merge (§5) | Pass | `MergeSheet.swift` follows §5.1 to §5.4 section by section. Refusal is in the header (`IssueText`, symbol and words). Flagged row: symbol plus accessibility value "Problem", symbol hidden. Format is a segmented `Picker`, the choice kept as a preference. Merge is off until the frames are read, the disk answered and nothing is refused. The DNG writer is built, so the "absent control" variant is rightly not needed. Look: M1 |
| H4 | Name line follows the format and numbering (§5.3) | Pass (by script) | `updateName` asks `HDRMergeJob.resultURL`, so it shares `ExportNaming`/`MasterFiles` numbering; status.md shows `.dng` and `-2`, `-3` |
| H5 | Seven refusals from the selection, in the design's order, flagged rows (§6.1) | Pass | `MergeSelection.refusal` order is count, too many, video, same file, mixed, size, offline, as §6.1. Flagged sets as designed. Texts in `MergeText.refusal` match §13 word for word |
| H6 | Disk refusals, off the main actor, again at Merge, nothing created (§6.2) | Pass | `MergePreflight.disk` reads attributes only. `check` runs in `Task.detached`; the spinner shows after 0.5 s. `HDRMergeJob.run` checks again (line 98) and the failure row carries the §6.2 text. The folder in case 9 is named by its last component only; fine |
| H7 | Job in Activity: determinate, phase detail, Stop in the popover and File ▸ Stop Merge, `StoppableJob.merge` (§7.1) | Pass | `ActivityToolbarItem.swift` job id `merge`, `ToolbarMetrics.statusLine`, `stop: { model.merge.cancel() }`; `stopTitle` has `.merge`. "Never backward" is enforced in `MergeModel.update` |
| H8 | Stopped, done and failed rows and announcements (§7.2, §7.3) | Pass | `MergeModel.start` posts the stopped information row, the failure warning with the reason after the fixed sentence, and the catalog-failed warning without the fixed sentence (it says the file is kept). Every report announces. Texts match §13 |
| H9 | Landing: selected only when untouched (§8.3) | Pass, with D-H2 | `MergeLanding.selects`: grid showing, source holds it, selection is still the started set. Otherwise `replaceItems(..., selecting: now, focusVersionID: focus)` leaves selection and focus alone |
| H10 | Undo "Merge to HDR": row leaves, file stays, Activity names the path; Redo checks the file (§9) | Pass (by script) | `registerUndo` named `MergeText.title`; Undo selects the frames again and posts `removedFromLibrary`; Redo posts `notAddedBack` when `restoreMergedMaster` declines. M6 for real menus |
| H11 | Quit question; removal off while merging (§7.4, §10) | Pass, with D-H1 | `QuitConfirmation.merging`, `QuitGuard.text`, `PhotoApplication.applicationShouldTerminate` passes `isMerging` and cancels the merge on Stop and Quit; `canRemoveFromLibrary` passes `isMerging`. Design §7.4 says closing the window asks too; the shared rule (`QuitConfirmation.needed`) asks only on `.quit` for the library app, as for Export, so the merge follows Export. Not a finding: if closing the window quits the app, add this to M5 |
| H12 | The result is an ordinary photo (§1, R13) | Pass (by test) | `resultIsAPhoto`; no UI of its own, as designed (name and type badge only) |
| H13 | Strings: every key present, plurals where a number is interpolated (§13) | Pass | Plural variations on the title, the limit, the offline count and "Merged N photos". Nothing names the product. One plural number per string. The offline `one` variant is never reached (the count 1 case has its own key); harmless |
| H14 | Sheet is a `LibraryModal` (§5, §16 N1) | Pass | `LibraryModal.merge`, `.sheet(... onDismiss: modalDidClose)` in `MainView`; `canMerge` also checks `otherModalIsUp` |
| H15 | A11y: reading order, header trait, never color alone, announcements (§11) | Pass in code, M3 for a real run | Refusal is in the header before the table; title has `.isHeader`; flagged rows have symbol and "Problem"; the note and refusal carry a symbol and words; system controls throughout. No custom motion |
| H16 | No custom chrome (design preamble) | Pass | Only `Form`, `Table`, `Picker`, `Button`, `Label`, `NSMenu` items and `NSAlert` |
| H17 | User guide terms (§15) | Needs fixes F1 | See F1 |
| H18 | R18 "Show in Library" (a Could) | Not built, accepted | D-H3 |

## Rulings on the engineer's design questions

Recorded in `design.md` §19; summary:

1. **Quit alert buttons: "Keep Merging" and "Stop and Quit". Confirmed (D-H1).**
   Consistency with the importing and exporting alerts, and "Stop and Quit" names
   what happens to the work. The safe button is the default and Esc.
2. **A merge that ends with the loupe showing: nothing moves (D-H2).** The
   selection and the loupe are both left alone; the new photo takes the selection
   only when the grid is showing and the person hasn't changed it. This resolves
   §8.3's two sentences in favor of "the person is looking at something". The
   code already does this (`showsGrid: library.mode == .grid`); §8.3 is edited to
   say so.
3. **R18 not built: accepted (D-H3).** It is a Could and §8.3 allowed leaving it
   out. If the owner finds it thin in use, it is a follow-up enhancement.
4. **DNG caption "16-bit floating point, not tone-mapped. Tone it in the Adjust
   tab." Confirmed (D-H4).** §5.3 and §13 are edited to 16-bit. The PRD's R5,
   Open question 1 and any 32-bit acceptance wording belong to the product
   manager (RI-E1 below).

## Findings for the engineer

**F1 (fix, user guide).** Two sentences in `docs/USER_GUIDE.md` (the
"Merging to HDR" entry, lines 249 to 296) don't match the build.

- Line 265 says a DNG "opens dark and flat". `MergeOutput` sets
  `BaselineExposure` so the DNG opens at the reference's brightness (status.md
  Spike 1: "so the DNG opens as bright as its reference does"). "Flat" is right,
  "dark" is not. Change to what is true after you check M4's look (for example
  "opens flat, with its highlights untoned").
- Lines 277 to 279 say "When the merge ends it becomes the selection, unless you
  have selected something else meanwhile." D-H2 narrows this: it also stays out
  of the way while the loupe, review or comparison is showing. Add that clause,
  as the design's guide term list asks for the landing to be stated.
- Everything else in the entry matches the UI's words (File ▸ Merge to HDR…,
  ⇧⌘L, Reference, Stop Merge, Undo Merge to HDR, "tone-mapped"). Terms the guide
  was not to use ("virtual copy", "version", "stack", "HDR photo", "bracket" as
  a menu word) are absent; "bracketed series" appears once, as allowed. The key
  table row and Activity paragraph are present.

**F2 (nit, optional).** In `MergeForm` the Name row is `Text(merge.resultName
?? "—")` with no line limit. A long master name wraps the row inside the grouped
form. Give it `.lineLimit(1)` and `.truncationMode(.middle)` and keep
`.textSelection(.enabled)` and a `.help` with the full name, as the Folder row
does. The fixed-width sheet (560 pt) makes this a real, if rare, case.

No violation of the HIG or of the design was found. Two things I checked and am
leaving as they are, so they are not "fixed" by accident: Return is the default
button (the action writes one new file and changes nothing existing, so a
Return pressed unread is harmless; design §5.4), and the item is enabled
whichever pane has the keyboard (design §3).

## Requirements issues (for the product manager)

- **RI-E1 (from the engineer; the design agrees with option a).** The DNG is
  16-bit floating point, not 32-bit, because the system RAW decoder reads no
  32-bit float DNG. The PRD's R5, Open question 1 and any acceptance wording
  that says 32-bit need the same change. A UI cost of (b) 32-bit would be a file
  the app's own loupe and other apps can't open: against Consistency, so (a).
  Option (c), a choice between the two, adds a control with no benefit.
- **RI-E2 (from the engineer; the design agrees).** AC4's "a sidecar exactly
  when sidecars are enabled" should read "when sidecars are enabled and the
  photo has values to write", which is how every new master behaves; the UI
  shows nothing about it.
- **RI-H1, RI-H2, RI-H3 of `design.md` §17** stand as raised. The build follows
  the design's defaults (dim only for under two targets, a running merge or a
  sheet up; the copy and different-size refusals; name and type badge as the only
  mark). I was not told of rulings; if the product manager rules differently,
  only the lines §17 names change.

## Improvements (judgment, not violations; none needed for sign-off)

- After the landing rule leaves the new photo unselected, the only ways to it
  are the path in the Activity row and a search for `_HDR`. The "Show in
  Library" button (D-H3) would remove that; it is worth an enhancement issue if
  the owner finds himself searching. Proposed title: "Show in Library action on
  the HDR merge's Activity row". Body: add an optional action to
  `ActivityLog.Message` (title, closure id), shown as a borderless button at the
  row's trailing edge; selects the photo in a source that holds it, All Photos
  if the current one doesn't. Design §8.3 has the spec.
- The DNG caption does not say which apps open it. "Looks right in any app" on
  the TIFF implies the contrast, but a person choosing DNG might expect any
  viewer to open it. Not needed for v1; the guide says it opens in the Adjust
  tab.

## What's working (leave alone)

- The refusal in the header, in reading order, with a symbol and words, and the
  flagged rows doing the same: a dimmed Merge is never unexplained.
- Dimming only for what the selection plainly shows and answering everything
  else in the sheet with the frame named.
- One Stop item for ⌘., titled for the newest job; one Activity row for each
  outcome; no alert for a background failure.
- The sheet closing at once on Merge and the work going on in Activity.
- The landing rule's restraint: nothing is selected or scrolled that the person
  did not ask for.
- Strings that say what happened and what to do, with the plural rules in the
  catalog.

## Manual checks for the owner

VoiceOver, macOS 15 and macOS 26 are not asked (standing ruling). Run the
bundle on a scratch library from `photobench ... --brackets 1`, with
`--library-root`; the commands are in `status.md`'s Debug-script checks.

- **M1. The sheet's look.** Select the three `RAW_10x` frames and press ⇧⌘L.
  Header (thumbnail, "Merge 3 Photos to HDR", "From All Photos"); the table
  inside the grouped form (no doubled background, columns not clipped, the
  Reference mark after the 0 EV frame's name); Format, Name and Folder rows and
  the captions; a long folder path truncated at its head. Then open it on a
  refusal (the video among two JPEGs; the read-only folder): the symbol and text
  in the header, the flagged row's symbol, Merge dimmed. Light and Dark, and
  with Increase Contrast. Note whether Return and Esc do what the buttons say.
- **M2. The key and the menu.** A real ⇧⌘L with a real keyboard, from the grid,
  with the search field focused (it should still open the sheet), and with one
  photo selected (the item is dimmed and the key does nothing). The grid's
  right-click menu lists the item after Duplicate with two or more selected and
  not with one; the loupe's right-click menu does not list it. Menu enabled
  states could not be read in the scripted runs.
- **M3. Keyboard only.** Open the sheet with the key, Tab through Format, Cancel
  and Merge, press Return on Merge, and watch the sheet close and Activity show
  the job, without touching the pointer.
- **M4. The result's look.** Merge the same three frames as TIFF and as DNG.
  Open both in the loupe: the TIFF should look like a normal photo; the DNG
  should look flat but not dark (this settles F1's wording). Open the TIFF in
  another viewer (Preview).
- **M5. Stop and quit.** During a merge, click Stop in the Activity popover with
  the mouse, then start another and press ⌘. (File ▸ Stop Merge); check the
  stopped row and that no file is left in the folder. Start another and press ⌘Q:
  "Quit While Merging?" with **Keep Merging** as the default (Return and Esc) and
  **Stop and Quit**; choose Keep Merging, then confirm the merge finishes. Also
  look at the toolbar's Activity item with a long result name (a long master
  file name).
- **M6. Landing, undo and merge again.** Merge from the grid and wait: the new
  photo is selected and in view. Merge again and, while it runs, click another
  photo: the selection stays on that photo. Merge again and open a photo in the
  loupe while it runs: the loupe stays on its photo (D-H2) and arrow keys reach
  the new one. Then Edit ▸ Undo Merge to HDR (the photo leaves, the frames are
  selected, the file stays), Redo, and a fresh merge that writes `_HDR-2`, all
  from the real menus.

The guide's "Photos of another scene ... Activity names the photo" and the
failed-disk ("not enough space") and deleted-master messages are built but not
run (status.md); they are for QA to attempt or leave to the owner.

## Summary for the issue

Design review of #150: passes. The built UI follows design.md: File ▸ Merge to
HDR… (⇧⌘L) and the grid context item, the sheet with its refusals, the Activity
job with Stop, the quit question, undo, and the landing rule, all system
components. Rulings recorded in design.md §19: quit buttons "Keep Merging" and
"Stop and Quit" (D-H1); with the loupe showing, nothing moves (D-H2); R18
"Show in Library" not built, accepted (D-H3); DNG caption "16-bit floating
point" (D-H4). Fixes for the engineer: F1 (user guide says the DNG opens
"dark" and the landing sentence needs the loupe clause), F2 (nit, Name row
truncation). For the product manager: RI-E1 (PRD says 32-bit DNG) and RI-E2
(AC4 sidecar wording). Manual checks M1 to M6 for the owner. Details:
`docs/features/hdr-merge/review.md`.
