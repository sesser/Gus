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

## Confirmation (second pass, 2026-11-20)

Reviewer: apple-ui-designer. Read: `design.md`, this file, `status.md`,
`Model/MergeText.swift`, `Views/MergeSheet.swift` (Name row),
`PhotoCore/Merge/MergeSelection.swift`, `MergeLimits.swift`,
`HDRMergeJob.swift` (failure cases), `Catalog/MergedMasters.swift`, the four
new keys in `Localizable.xcstrings` and the merge entry of `docs/USER_GUIDE.md`
(lines 249 to 301). I did not run the app or the tests.

**Verdict: passes; one string reworded (F3), two guide additions (F4, F5).**
Rulings are in `design.md` §19 as D-H5a to D-H5c.

**Earlier findings.** F1 confirmed fixed: the guide says the DNG "opens as
bright as the reference but flat" and names the loupe, review and comparison
in the landing sentence. F2 confirmed in code: the Name row is one line,
middle-truncated, selectable, with the full name as its tooltip. The
tooltip is a hover aid only; the name is fully readable in the field's
selection and by VoiceOver, so nothing depends on it.

| # | Requirement | Result | Evidence |
|---|---|---|---|
| S1 | Case 6a "“%@” is too large to merge. A photo can have at most %lld megapixels." (§6.1) | Pass | Names the frame and the rule; used in the sheet and Activity; one number, no plural needed. Catalog value uses positional `%1$@`, `%2$lld`, which matches the call |
| S2 | Case 6b "These photos are too large to merge together on this Mac. Select fewer." (§6.1) | Pass | Names cause and action; "on this Mac" says the limit is the machine's. All rows flagged, as in case 1. Order after case 6 and 6a, before offline, as ruled |
| S3 | Activity: unusable name (§7.3) | Fail until F3 | "has a name or place a merged photo can't be saved beside" is vague and jargon-like |
| S4 | Activity: same content (§7.3) | Pass | Says what was found; the row's first sentence already says nothing was added |
| S5 | Numbering by stem, shown in the Name row before Merge (§5.3, D-H5b) | Pass (by `numbersPastTheStem`, status.md); needs manual check M7 | Name row follows the Format control; the guide gives the reason |
| S6 | Merged DNG beside its own source raws (D-H5c) | Accepted as built; guide sentence F5; needs manual check M8 | Not refused, not flagged; the frame shows by name |
| S7 | Guide lists the refusals (§15) | Fail until F4 | The guide's refusal list (line 287 to 291) omits the two size refusals |

## Rulings on the engineer's questions (second pass)

1. **Strings (1), (2), (4): confirmed as written.** (3) is reworded below.
2. **Numbering results by stem: stands**, with no new caption. A shared sidecar
   is a data fault, and the Name row shows the number before the person commits.
   If a person is confused by `-2` with no `-1`, the answer is a caption naming
   the file in the way; it needs one string and the clashing name from
   `MergeNaming`.
3. **A merged DNG accepted as a frame beside its own sources: neither flagged
   nor refused.** The app has no reliable way to know (no stored link), the
   only signals are heuristics that would block legitimate selections, and the
   cost of the mistake is a poor file, one Undo from gone. The sheet shows the
   frame by name. Detecting our own DNG is raised as RI-H4 for the product
   manager (default: none).

## Findings for the engineer (second pass)

**F3 (fix, one string).** Reword the Activity reason for `.invalidName` in
`MergeText.reason`. Exact text, two sentences:

    A merged photo can't be saved beside “%@”. The library's record of its file name or location isn't valid.

The catalog key is the English text, so replace the key (the old key is
`“%@” has a name or place a merged photo can't be saved beside.`) in
`Localizable.xcstrings` with the new text, keep the same `%@` and the
`comment` ("Activity: why a merge failed; the reference photo's name (a damaged
library)"), and change the `String(localized:)` literal to match so
`LocalizationTests` finds the entry. No other string changes. If a test pins the
old wording, update it.

**F4 (fix, user guide).** In the refusal list of the "Merging to HDR" entry
(the bullet beginning "Only photos merge"), add the two size refusals: a photo
of more than 150 megapixels, and photos that together are too large for the
Mac's memory (the limit is half the Mac's memory, so the same selection may
merge on another Mac; select fewer). Keep the sentence about what the sheet
says, and the guide's words ("too large to merge"), so the terms match the UI.

**F5 (fix, user guide).** Add one sentence after the paragraph that says
nothing links the new photo to its sources: a merged photo is an ordinary photo,
so the app does not stop you selecting one together with its own source photos;
the result then counts that light twice, so select only the original series.
Plain words, no "provenance".

**Not findings (leave as built).** Return as the default button; ⇧⌘L enabled
from any pane; the numbered name without a caption (D-H5b); no flag on a
merged photo among its sources (D-H5c).

## Requirements issues (second pass)

- **RI-H4** (`design.md` §17): a merged photo can't be told from any raw, so it
  can be selected beside its own frames. Default: no detection in v1. If the
  owner wants it, a stored marker (in the file or the catalog) serves this and
  RI-H3 together.
- **RI-H1 to RI-H3, RI-E1, RI-E2** stand as raised above.

## Manual checks added

- **M7. Numbering shown before Merge.** On the scratch library, merge the three
  `RAW_10x` frames as TIFF and wait, then open the sheet again on the same three
  and choose DNG: the Name row reads `‹name›_HDR-2.dng`, and changing to TIFF
  reads `‹name›_HDR-2.tif`. Merge it and check that the two files have separate
  sidecars when sidecars are on.
- **M8. A merged photo among its sources.** Select the three raws and the
  merged DNG and press ⇧⌘L: the sheet opens with four rows and no refusal. Look
  at which row is marked Reference and what the Name row says (it may read
  `…_HDR_HDR`); this is the signal D-H5c relies on, so say if it is unclear.
  Cancel; nothing is written.

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

---

# Revision review, 2026-11-21: the reference choice, Auto-align, De-ghost and the sheet's height

Reviewer: apple-ui-designer. Branch `feature/hdr-merge` at `d9b1461`. Against
`design.md` §5.5 to §5.8, §6.4, §20 (D-H6 to D-H10) and the PRD as revised
2026-11-21 (R3, R9, R10, R14, AC3 to AC3c, AC7a, AC9a, AC12).

**What I read.** `design.md`, `status.md` (to the end of "Revision
2026-11-21", then the tiles bug only for its UI effect: none), the PRD,
`Views/MergeSheet.swift`, `Model/MergeModel.swift`, `Model/MergeText.swift`,
`PhotoCore/Merge/MergeSheetState.swift` and `MergeSelection.swift`,
`Model/DebugMergeCommands.swift` (the `merge sheet` metrics), the new keys in
`Localizable.xcstrings` and the merge entry of `docs/USER_GUIDE.md`. I fetched
the HIG pages for Sheets, Toggles and Lists and tables (2026-11-21).

**What I could not do.** This session has no shell, so I did not build, run the
bundle or run `merge sheet`. Behavior below is read from the code and from the
output `status.md` records for the debug script (run by the engineer on a
scratch copy with its own identifier and `--library-root`); I did not re-run it.
Anything that needs the running sheet is a manual check.

## Verdict

**Passes with one required change (F6, the height, ruled D-H11) and two small
fixes (F7, F8).** The reference choice, the two boxes and the refusals that
follow the reference are built as designed, from system components with no
custom chrome, and the model behind them is tested without views
(`MergeSheetState`). The one real defect is the engineer's own finding: at three
frames the Form scrolls by 116 pt, hiding the Name and Folder lines. Nothing
else blocks QA once F6 is done; QA should run after it, since it changes the
sheet's layout.

## Design requirements

| # | Requirement | Result | Evidence |
|---|---|---|---|
| R1 | The Photos table is a single-selection `Table`; the selected row is the reference, rows keep capture order (§5.5) | Pass in code; M9 | `FramesTable`: `Table(frames, selection: $row)`, `row` follows `merge.referenceID`; no sort, no reordering. `MergeSheetState.chooseReference` ignores `nil`, an unknown id and the same row |
| R2 | Never empty: ⌘-click, a click below the rows, `nil` all leave the reference (§5.5) | Pass in code; M9 for the flicker | `onChange(of: row)` puts `merge.referenceID` back when the table clears. The engineer's script shows `deselectAll` leaving row 1 selected. Whether a real ⌘-click shows one frame of no selection is M9 |
| R3 | The "Reference" mark never truncates; the name gives way first, middle-cut, full name as tooltip (§5.2) | Pass in code; M8 | Mark is `Text(...).fixedSize()` in the HStack, the name has `lineLimit(1)`, `.middle`, `.help` |
| R4 | Default reference is R3's, every open; nothing stored (§5.5, AC3c) | Pass | `begin()` makes a new `MergeSheetState`; `MergeSheetState.init` takes `defaultReference`; the boxes live in the state, not in `UserDefaults`; only Format keeps a preference. Tests `opensWithDefaults`, `reopensWithDefaults` |
| R5 | Every listed row can be chosen, a flagged one, a video and the extremes included (§5.5, A13) | Pass | `choosingReference` accepts any frame; no warning anywhere |
| R6 | Auto-align and De-ghost: two system check boxes in the Photos section under the table, in that order, one-line captions that say what Off does, caption as the hint and hidden from VoiceOver, never dimmed (§5.6) | Pass in code; M8 for the indent | `OptionBox`: `Toggle` with `.checkbox`, `Caption` hidden, `accessibilityHint(caption)`, no `.disabled`. Texts match §5.6 word for word. The 20 pt indent is a constant, not a system metric: M8 |
| R7 | Both boxes independent, none changes a refusal, Name or Folder (§5.6) | Pass | `MergeSheetState.options` is not read by `refusal`, `name` or `canStart`; `boxesAreIndependent` |
| R8 | What follows the reference, at once: table, header thumbnail (old stays until the new is ready), caption, Name, Folder and the several-folders sentence, refusals 6 and 9 (§5.8, §6.4) | Pass, with F8 | `chooseReference` reloads the thumbnail, asks the disk, names again; the old `previewImage` is kept until the new one is ready. Case 6 follows the reference (`MergeSelection.refusal(reference:)`); case 9 is `MergePreflight.unwritable(reference)`. F8 is the thumbnail for a RAW+JPEG pair |
| R9 | Folder checked once per folder; a late answer for a superseded reference decides nothing; Merge off until the folder has answered; spinner only after about 0.5 s (§5.8) | Pass | `folderToAsk`, `askingFolders`, `record(folder:)` returns whether it decides; `canStart` needs `isDiskChecked`; `startSlowTimer` 500 ms. `folderAskedOnce`, `folderRefusalFollows`; the script's `slowdisk` run printed "discarded Open" |
| R10 | One announcement after a change, debounced about 0.3 s, once the folder and the name are known, with the new refusal or "Merge is available."; none at open (§11) | Pass in code; not heard | `scheduleAnnouncement`, `announceIfReady`, `MergeSheetState.messageChange`; `announcedRefusal` seeded at open. VoiceOver is not asked of the owner (standing ruling); the text and rule are unit-tested |
| R11 | Refusals decided again when the reference changes; a refusal that no longer applies goes away; a read-only folder is a legitimate non-reference (§6.4, AC12) | Pass | `refusal` is computed from the selection and the disk answer for the current reference; `unwritable` flags the reference's row only. `folderRefusalFollows`, `MergeReferenceJobTests.readOnlyFollowsTheReference` |
| R12 | With Auto-align off no frame is refused for failing to line up; the other refusals apply (§6.3, AC7a, AC7b) | Pass by tests (read, not re-run) | `unrelatedWithoutAlignment`, `unrelatedMergesWithoutAlignment`, `refusalsWithoutAlignment` |
| R13 | Activity without Auto-align has no "Aligning" phase and the bar still ends at 1 (§7.1) | Pass by the engineer's script | status.md "Merges": details Reading, Merging, Saving, Adding; last fraction 1.000 |
| R14 | The alignment failure text ends "…or turn off Auto-align."; `photocli`'s names `--no-align` (§7.3, D-H10) | Pass | Catalog key present; status.md records the `photocli` text |
| R15 | Strings: new keys present, old three removed, nothing names the product (§13) | Pass | Keys for Auto-align, De-ghost, the captions, "Choose the reference", the announcements and the caption "“%@” names the result and where it is saved…" are in the catalog; "Saved next to" and the old caption are gone. D-H11 replaces one more (the result caption) |
| R16 | The sheet at three frames needs no scrolling (§5.7, H21) | **Fail** | status.md: `sheet 560x600 form content 590 shown 474 scrolls true`. See F6 and D-H11 |
| R17 | Initial focus on Merge or Cancel (§11) | Withdrawn (D-H13) | No code sets focus; the design line was wrong for a Mac sheet |
| R18 | User guide terms match the UI (§15) | Pass | The merge entry (lines 249 to 324) uses File ▸ Merge to HDR…, ⇧⌘L, Reference, Auto-align, De-ghost, Stop Merge, Undo Merge to HDR, "tone-mapped"; "ghost" only inside De-ghost; "bracketed series" once. No guide change needed for D-H11 (it quotes no sheet caption) |

## Findings for the engineer

**F6 (required; ruled D-H11).** The default case scrolls and hides the Name and
Folder lines. The ruling and the exact changes are in `design.md` §20 D-H11:
fold the table's, the Format's and the result caption into their controls' Form
rows, cut the result caption to one line, measure, set `idealHeight` from the
measure (560 to 640), and if still over 640 apply the pre-ruled cuts in order.
Update `status.md` with the measured numbers and `LocalizationTests` for the
replaced key. Not a design violation of the HIG, but the sheet's default state
has to fit (HIG, Sheets: "present a sheet in a reasonable default size").

**F7 (small, ruled D-H12).** In `MergeForm`'s Name row make the name
`.secondary` while a refusal shows as well as while it is provisional:
`name.isFinal && merge.refusal == nil ? .primary : .secondary`. The Name line
showing the reference's name under a refusal is confirmed; this keeps it from
looking like a promise while Merge is off.

**F8 (small, check then fix).** `MergeModel.loadPreview` finds the header
thumbnail with `library.item(versionID: reference)` and falls back to the first
target's item. The library indexes only the version the grid shows. A RAW+JPEG
pair that shows its JPEG has the RAW (the frame) as `partnerVersionID`, so
`item(versionID:)` is nil for the RAW frame and the fallback shows the first
target's thumbnail, whichever reference is chosen: the header thumbnail would
not follow the reference for a series of pairs (§5.1, §5.8). Fix: fall back on
the target item whose `versionID == reference || partnerVersionID == reference`
before the first target. Check on a scratch library with a RAW+JPEG bracket if
the generator makes one; if the grid shows the RAW for pairs, the fault does
not arise and this is a no-op.

**Not findings (leave as built).** The table selection held in view state and
put back on a clear (the design's engineer note, §5.5); the 20 pt caption
indent as a named constant pending M8; the `Reference` mark as text rather
than a column of controls; Return as the default button; the Format picker
remembered while the two boxes reset (the owner's ruling).

## Rulings on the engineer's open items

Recorded in `design.md` §20 as D-H11 to D-H13.

1. **DQ-H11, the height: (b) carried through, with the second half of (d) as
   part of it** (D-H11). Not (a): 716 to 720 pt is 90% of the 800 pt a 13-inch
   laptop offers at default scaling, past Export's 640 (the tallest sheet the
   app ships) and against "a reasonable default size". Not (c): the part
   that scrolls is the Name and Folder, the evidence of the choice the sheet
   exists to ask. Not (d)'s two boxes in one row: two-line captions, a saving of
   one row's padding against four extra lines, and the boxes would stop
   aligning on the leading edge (HIG, Toggles). The miss is row padding (about
   15 pt on each of nine rows), not text, so the fix is to fold each caption into
   the row of the control it explains, the way `OptionBox` already does. A
   Section footer is not the answer: it lands under the section's last row, away
   from the table. Exactly what changes: design §20 D-H11, items 1 to 7. Cap
   640 pt, with ordered cuts if the measure is over it. Estimates only: the
   folds should save about 13 to 19 pt each and the caption cut 14 pt, which
   leaves the sheet near 640 to 660 before the first pre-ruled cut (drop the
   "Photos" section header). The engineer's measure rules.
2. **Name line with a refusal: confirmed** (D-H12), with the one-line refinement
   F7.
3. **Initial focus with a selectable table: not set by code** (D-H13). §11's
   "initial focus on Merge" is withdrawn. The invariant is Return pressed with
   the table focused presses Merge and Esc cancels; whether `NSTableView` lets
   Return through can't be read from the code, so M10 tests it, after a click
   on a row first. If it fails, a design question, not a key handler.

## Checks made from the code and the script

- Read, not run: every row of the table above marked "Pass in code".
- Engineer's recorded script output (`status.md`, "Debug-script checks"),
  consistent with the code I read: opens on the 0 EV frame shot second with
  both boxes on; the Name follows reference and format; one table row always
  held through `deselectAll`; reopening gives defaults; the folder refusal
  appears, flags the reference's row, clears and returns as the reference
  moves; a late answer is "discarded"; merges with the +2 EV frame as reference
  and with Auto-align off behave as designed; and the height numbers above.
- Not possible without a key window or a person: the enabled state of menu
  items, focus and Return behavior, the look.

## Manual checks for the owner

VoiceOver, macOS 15 and macOS 26 are not asked (standing ruling). Use the
scratch library from `photobench generate … --brackets 1` and a copy of the
bundle with its own identifier and `--library-root`. The numbering continues
`design.md` §16; M8 to M14 are there in full, restated here by what to look
for, with M15 new. Run them after F6 is done.

- **M8. The look at the default size.** Three frames: no scrolling; the
  "Reference" mark whole; the check boxes' captions indented to their labels
  and on one line; Light, Dark, Increase Contrast, Reduce Transparency. Nine
  frames: the Form scrolls, header and buttons stay.
- **M9. Choosing by pointer.** Each row; ⌘-click the chosen row; click the empty
  space under the rows (one stays chosen, any flicker?); is it discoverable that
  rows can be clicked, from the caption alone (if not, the pop-up fallback).
- **M10. Choosing by keyboard (Full Keyboard Access on).** Tab order, arrows
  move the reference, Space on a box, and Return and Esc with the table
  focused: after a click on a row, after Tab, on opening. What has the focus
  when the sheet opens? (D-H13: the table is expected.) Reopen: defaults again.
- **M11. The reference and the folder refusal** (`TwoFolders-n`): the refusal
  names the default reference, choosing the frame in the writable folder lifts
  it, the other brings it back; on a slow volume the spinner appears only after
  a pause and the Name is never stale when Merge comes on.
- **M12. A real merge with the +2 EV frame as reference** against the default:
  name, folder, project, Info tab metadata, the walker's place.
- **M13. The two boxes on real files.** Unrelated scenes with Auto-align on
  (refused, Activity ends "or turn off Auto-align") and off (merged, no
  "Aligning"); De-ghost on and off on the walker series.
- **M14. Height on a 13-inch laptop and in a short window:** the sheet fits the
  screen and the window, scrolls with header and buttons in place, with a
  two-line refusal and the same-exposure note.
- **M15. The folded captions (new).** Each caption under its own control inside
  the same group row, no divider between them; the Name line gray while a
  refusal shows and black when Merge is on.
- **M16. The header thumbnail with RAW+JPEG pairs** (F8), if the scratch
  library has a bracket of pairs: choosing another frame changes the thumbnail.

## What's working (leave alone)

- The table doing double duty as the choice and its evidence, with the mark in
  words so the state reads in a gray selection, with Increase Contrast and
  without color.
- The model behind the sheet, in PhotoCore, with the rules (default, never
  empty, per-folder asking, discarded late answers, the announcement text)
  under test and the views thin.
- The refusal staying in the header, first in the reading order, naming the
  chosen reference.
- Captions that say what Off does ("merged as they are", "plain blend") and
  no warning for turning either off.
- A new sheet state on every open, so nothing about the reference or the boxes
  is remembered.

## Summary for the issue

Design review of the #150 sheet revision (branch at `d9b1461`): passes with one
required change. The reference as the table's single selection, the Auto-align
and De-ghost boxes and the refusals that follow the reference are built as
designed from system components. DQ-H11 ruled (D-H11): the default case scrolls
by 116 pt, so fold the table's, the Format's and the result caption into their
controls' Form rows, cut the result caption to one line, set the sheet's height
from the measure (560 to 640, never more), with ordered cuts if still over; not
720 pt, not accepted scrolling. D-H12: the Name line keeps showing the
reference's name under a refusal, gray while a refusal shows. D-H13: initial
focus is not set by code; Return and Esc must work with the table focused (M10).
Fixes: F6 height, F7 Name color, F8 header thumbnail for RAW+JPEG pairs. I did
not run the app (no shell); manual checks M8 to M16 for the owner after F6.
Details: `docs/features/hdr-merge/review.md`, rulings in `design.md` §20.
