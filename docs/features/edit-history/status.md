# Edit history: status

Owner: swift-macos-engineer. Feature: `edit-history`. Branch: `feature/edit-history`.
Spec: [`prd.md`](prd.md) (Approved), [`design.md`](design.md) (Designed; §14 owner rulings).

**State: Done** (2026-11-09; review fixes 2026-11-10, below). Every acceptance criterion is built and has a test
or a named check. Open for others: the designer's manual checks (AC14, D7, D13),
listed under "For a person" below, and the optional palette toolbar item, not built.

## Baseline and latest results

- Baseline on `feature/edit-history` before any change: `swift build` clean.
- Latest: `swift build` clean, no warnings. `swift test`: 672 tests in 111
  suites passed, 1 known issue (the one the baseline already carries). No golden
  moved and `UPDATE_GOLDENS` was never used; `PreviewCacheKey.currentPipelineVersion`
  is untouched (AC16).
- `Scripts/build-app.sh` (release bundle) builds; debug-script checks below ran
  against a copy of that bundle with its own bundle identifier
  (`test.edithistory.scratch`) and a scratch library from `photobench`, always with
  `--library-root`, never the owner's library or preferences.
- `Scripts/build-app.sh` itself is not changed.

## What changed

PhotoCore (no AppKit or SwiftUI):
- `Catalog/CatalogSchema.swift`: migration `v14`, table `editHistory`
  (`id`, `versionId` → `version` ON DELETE CASCADE and indexed, `label`,
  `createdAt`, `stack` as an LZFSE-compressed BLOB). Generic names.
- `Catalog/EditHistory.swift` (new): `EditHistory.maxEntries = 100`, the
  command-line labels, `EditHistoryEntry`, `Catalog.editHistory(forVersion:)`
  (newest first, reads no snapshots), `Catalog.editHistoryStack(entryID:forVersion:)`,
  the in-transaction `recordHistory` (insert, then trim to the newest 100 of that
  version) and `EditStack.hasSameContent(as:)`.
- `Catalog/EditHistoryPanel.swift` (new): `EditHistoryPanelState` (the rule for
  absent, loading, empty, entries, unavailable by reason) and `EditHistoryTime`
  (row, spoken and tooltip time text), so both are testable without the window.
- `Catalog/Catalog.swift`, `Edits/AdjustmentPresets.swift`: `setEditStack`,
  `setEditStacks` and both `changeEditStacks` take a required `historyLabel` and
  write the entry in the same transaction as the stack. A required parameter, so
  a new route cannot forget it. The old `refuseUnreadableStacks` is folded into
  `setEditStacks` (one read of the stored stacks serves the refusal and the
  "changed?" test) and is gone.
- `Commands/LibraryCommands.swift` (`develop`), `Commands/MaskCommands.swift`:
  pass the command labels (Q2).

PhotoApp:
- `Model/HistoryText.swift` (new): `Undo %@`, `Redo %@`, `Revert to “%@”` as whole
  catalog strings, and the rule for which label a write gets.
- `Model/AdjustmentEditor.swift`: `apply` labels its write (undo/redo read from the
  undo manager's `isUndoing` / `isRedoing`), bumps `historyRevision` once written;
  new `revert(toHistoryEntry:ofVersion:)`.
- `Model/AdjustmentActions.swift`: batch writes and their undo/redo pass labels and
  bump `historyRevision`.
- `Model/HistoryActions.swift` (new): the list value, `historyPanelState`,
  `toggleHistory`, `loadHistory` (off the main thread, own read), `revertHistory`.
- `Model/LibraryModel.swift`: `showsHistory` (`inspector.showsHistory`, default
  false), `history`, `historyRevision`, `historyWantsKeyboard`.
- `Views/HistoryPanel.swift` (new): the panel (`AppKitDisclosure` and `AppKitButton`
  header, 28 pt), the `NSTableView` in an `NSScrollView` (24 pt rows, check mark
  slot, semibold current row, tooltip, type-to-select off, Return/Space revert,
  Esc leaves, first row as the cursor's start), `HistoryCell` (VoiceOver label,
  value with ", current state", press action and a "Revert to This State" custom
  action).
- `Views/InspectorView.swift`: hosts the panel below the tab content and passes the
  column height (body = 40 % of it, 96 to 192 pt).
- `Views/AppKitButton.swift`: `accessibilityValue`, `accessibilityHint`,
  `leadingAligned` (additive; other buttons unchanged).
- `Views/LibraryCommands.swift`, `Views/LibraryMenuContext.swift`: View ▸ Show /
  Hide History, ⌥⌘3.
- `Model/DebugScript.swift`, `Model/DebugHistoryCommands.swift` (new): `history`,
  `history wait|open|close|revert <n>`.
- `PhotoUI/Resources/Localizable.xcstrings`: 19 keys added by hand (see
  `LocalizationTests`).
- `docs/USER_GUIDE.md`: shortcut table row, a History paragraph (including the RI-1
  sentence: no entry for the photo's unedited state, use Reset All Adjustments, Undo
  or the Original toggle), the `photocli` note.

## Decisions on the open items

**Q4: what an entry stores.** The label (text), the time, and the full edit stack
JSON as it was after the change (a snapshot). A snapshot makes a revert exact with
no replay and no dependence on the stack's future schema upgrades (the entry is
decoded with `EditStack.decode` like the live stack, so an old snapshot is upgraded
the same way). Nothing derived is stored: the render hash is recomputed from the
snapshot when it is written back.

Cost, measured with the same stack JSON the app writes (`jsonData()`):

| stack | JSON | 100 snapshots | LZFSE (not adopted) |
|---|---|---|---|
| typical (exposure, tone, presence, curve, sharpen) | 771 B | 77 KB | 525 B |
| plus one brush mask, 5,000 dabs | 75 KB | 7.5 MB | 17.5 KB per snapshot (4.3x) |

A library of 20,000 photos with ten entries each at the typical size is about
150 MB; at the cap for every photo, 1.5 GB (not a realistic library). Brush work is
what makes a stack large: at `MaskLimits`' ceiling (200,000 points per mask, 32
masks) one snapshot could in theory reach about 100 MB, so the cap alone does not
bound a pathological photo; real brushwork stays in the tens to hundreds of KB.
Decision (superseded by the owner's ruling on code-review C1, 2026-11-10, below):
plain JSON.

**C1 (owner ruling): compress snapshots and add a byte budget.** Same migration
`v14` (not shipped, so edited in place; no extra migration). `stack` is a BLOB
holding the stack JSON compressed with LZFSE (`NSData.compressed(using: .lzfse)`,
`EditHistory.compress` / `decompress`). After each insert, `recordHistory` keeps the
newest 100 entries and, within them, as many newest ones as fit in
`EditHistory.maxBytes` = **4 MiB** of stored (compressed) bytes per version; older
ones are deleted in the same transaction. The newest entry always survives, even if
it alone is over the budget.

Why 4 MiB: ordinary work never meets it (100 typical stacks are under 100 KB; 100
snapshots of a tidy 5,000-dab brush path about 1.8 MB), while a scribbled 50,000-dab
brush photo, about 380 KB a snapshot, keeps about 10 entries (measured in
`EditHistoryTests.defaultBudget`: 30 edits kept 10 entries, 3.8 MB). At the budget a
version costs at most ~4 MiB plus its newest snapshot, so 20,000 maxed-out photos
would be 80 GB at the very worst, but only photos with heavy brushwork get anywhere
near it; the typical library stays near the 150 MB figure above. Past the budget the
person loses the oldest states of that one photo, never the current one.

The write cost per edit is one extra INSERT of the same JSON the stack write already
produces, in the same transaction, plus one DELETE bounded by the cap.

**AC15 measure.** Two parts. (1) Structure: the loupe's own read
(`catalog.version(id:)` in `AdjustmentEditor.follow`, `details(forVersion:)`) never
touches `editHistory`, and the list is a separate task (`loadHistory`) with its own
read that selects `id, label, createdAt` and never the snapshot column, so its cost
does not grow with stack size and cannot delay the photo. (2) Timing, in
`EditHistoryTests.longHistoryReads`: a version with 100 entries of ~75 KB stacks
(7.5 MB of snapshots): listing took 0.35 ms, the photo's own `details` read
0.45 ms (in-memory catalog, debug build). The test asserts the list takes under
250 ms and prints both numbers.

**Q2: photocli.** `develop`, `mask add`, `mask set` and `mask remove` write through
`setEditStack` and so record an entry when the stack changed (not for `--dry-run`,
not when the result equals the stored stack). Labels are English constants
(`"Develop (command line)"`, `"Mask (command line)"`): PhotoCore and photocli have no
String Catalog. Verified for `develop` in `EditHistoryTests.developRecordsAnEntry`;
the mask commands use the same call.

**RI-2: undo names.** Confirmed: every edit route names its undo step. The loupe
editor funnels every control, crop, rotate, reset and auto measurement through
`AdjustmentEditor.change(_ actionName:…)` (slider titles such as "Exposure", "Crop",
"Reset Adjustments"…), and the batch routes pass their `actionName`
("Paste Adjustments", presets, "Auto Exposure", "Rotate", "Reset Adjustments"). No
route lacked a name. Added: `Revert to “%@”`, `Undo %@`, `Redo %@`
(`HistoryText`). The entry label is built by the same function that names the
undo step, so the two cannot drift.

## Decisions made where the spec was not explicit (no ruling needed, say if you disagree)

- **Same content, not same bytes.** "No entry for a photo the change leaves
  unchanged" (R10) compares operations and settings but not operation ids:
  rebuilding a stack from the same values mints new ids (so a paste of equal values
  made an entry under a byte comparison). `EditStack.hasSameContent(as:)`.
- **Revert to a state the photo already has does nothing**, beyond A5's "the current
  entry": after a revert to entry X, clicking X again (or any entry equal to the
  current stack) adds no entry and no undo step.
- **Entry text is stored as written.** An entry keeps the label in the language it
  was made in; a later language change does not retranslate old rows (see
  Requirements issues).
- **The video loupe does not hand its video to the editor**, so the panel decides
  "video" from the focused item, not from the editor's state.
- **Keyboard on Show History** is taken only when there are entries to move in;
  with an empty list the keyboard stays where it was.
- Writes that find the stack unchanged still update `version.modifiedAt` as they
  always did; only the history entry is skipped.

## Acceptance criteria

| AC | State | Test or check |
|---|---|---|
| AC1 | Done | `EditHistoryTests.twoEntries` (catalog); debug script: `adjust exposure`, `adjust contrast`, crop Done gave rows "Debug exposure", "Debug contrast", "Crop" with times (the debug commands name steps "Debug …"; real controls pass "Exposure") |
| AC2 | Done | `EditHistoryTests.entriesSurviveReopen`; debug script: quit, relaunch on the same scratch library, `history` listed the same two rows |
| AC3 | Done (scroll by hand) | AppKit table in an `NSScrollView` with overlay scroller; `history` shows the table with rows. Scrolling past eight rows is a manual check |
| AC4 | Done | debug script `history`: check mark on row 0 after every edit, revert, undo and redo (it is always the newest entry) |
| AC5 | Done | `EditHistoryTests.revertKeepsEarlierEntries`; debug script: `history revert 2` gave 4 entries ("Revert to “Debug exposure”" on top), earlier three unchanged |
| AC6 | Done | same test, fifth entry |
| AC7 | Done | debug script (launched with `open -W -n` for the key responder chain): after a revert, `print undo` read `Revert to “Debug exposure”`; `undo` then `redo` ran. ⇧⌘Z unchanged, no ⌘Y bound |
| AC8 | Done | `EditHistoryTests.undoIsLogged`; debug script: `undo` added "Undo Revert to “Debug exposure”", `redo` added "Redo Revert to “Debug exposure”" |
| AC9 | Done | `EditHistoryTests.pairsKeepSeparateHistories` |
| AC10 | Done | `EditHistoryTests.batchRecordsOnlyChanges` (three photos, one already equal: entries on two) |
| AC11 | Done | `EditHistoryTests.capDropsTheOldest` (101 writes: 100 rows, "Edit 1" gone, another version's rows untouched); there is no clear command |
| AC12 | Done | `EditHistoryTests.panelStates`, `revertAvailability`; debug script: video showed `unavailable(video)`, a library whose volume identity was changed showed `unavailable(offline)`, grid and review showed `absent` (no panel, no control) |
| AC13 | Done | `EditHistoryTests.unreadableStackHasNoHistory` (newer and damaged: nothing recorded, bytes and hash identical), `refusedBatchRecordsNothing`; debug script: opening a photo with a schema-99 stack showed `unavailable(unreadable)` and its `editStack` text was byte-identical afterwards, no `editHistory` rows |
| AC14 | Manual (designer) | The rows expose label, value (`Today at 8:46 PM`, `, current state` on the newest) and a "Revert to This State" action (`accessibility AXTable` / `any`); the list is a single Tab stop with arrows, Return/Space, Esc. VoiceOver reading and keyboard use are the designer's check |
| AC15 | Done | See "AC15 measure" above; `EditHistoryTests.longHistoryReads` |
| AC16 | Done | Full `swift test` passes with goldens untouched; `setEditStack` stores the same JSON and hash as before (`EditHistoryTests.snapshotIsExactAndStorageUnchanged`); no render code touched; pipeline version unchanged |

Also covered: A6 (`historyGoesWithTheVersion`), schema (`CatalogTests`:
tables, applied migrations, no brand in the schema), time text
(`timeText`, `relativeWords`), strings (`LocalizationTests`, `BrandingTests`).

## Debug-script results (bundle copy, scratch libraries)

- Edit, edit, crop: three rows newest first, check mark on the top one.
- Revert, undo, redo: entries 4, 5, 6 with the labels above; the undo name after the
  revert is `Revert to “…”`.
- Crop session open: the table reports `enabled false`, rows `(dimmed)`, a revert
  does nothing; after `adjust crop cancel` the same revert adds its entry.
- States: empty, entries, video, offline, unreadable, grid and review absent.
- Relaunch persistence and the unreadable stack's bytes as in AC2 and AC13.
- Not possible here: the menu's enabled state and title. No key window is available to a
  process started from this session (`print responder` shows `key nil`, even after
  activating by process ID), so `menuitems History` showed the item disabled and
  `menupress` could not run it. `View ▸ Show / Hide History` is a manual check.
  `toggleHistory` itself ran through `history open` and `history close`.
- `snapshot` was not used: the panel is in a glass pane (blank in snapshots).

## For a person (what only a human can check)

Run the bundle with `--library-root` on a scratch library. Look at:
1. The History panel at the bottom of the inspector, in the loupe: collapsed by
   default; the header ("History", a disclosure triangle, the count on the right).
2. Expand it (click the title, or View ▸ Show History, ⌥⌘3): the body grows upward
   in 0.25 s (instantly with Reduce Motion), the tab content above shortens. The
   rows: check mark and semibold on the top row, time right-aligned, tooltip with
   seconds, last row clear of the pane's rounded corner on macOS 26.
3. Click an earlier row: the photo changes, a "Revert to “…”" row slides in at the
   top, the keyboard returns to the loupe, Edit ▸ Undo reads "Undo Revert to “…”".
4. With the list focused: arrows move the cursor without changing the photo,
   Return/Space revert, Esc returns to the loupe; letters do nothing.
5. VoiceOver: header (button, expanded/collapsed, "12 entries" hint), "Edit History"
   table, rows read label and "Today at …", the announcement "Reverted to …".
6. A crop session dims the rows. Grid and review show no panel.
7. View ▸ Show / Hide History title and ⌥⌘3, dimmed in the grid and review.
8. Contrast in Light/Dark and Increase Contrast; no glass on the panel.
9. A video, an offline photo and a photo with unreadable edits each show their line.

## Design questions

None blocking. Two notes for the designer:
- The time text comes from the system's formatters, so another day this year reads
  "Nov 2 at 4:10 PM" on macOS 26/27 (en_US), not the "Nov 2, 4:10 PM" in §5's example.
  The locale decides; the structure (relative for yesterday, no year this year) is
  as designed.
- The palette-only toolbar item (§8, marked optional) is not built; the menu item
  and the panel header are the paths. Say if the owner wants it.

## Requirements issues (for the product manager)

- **RI-3 (low).** An entry's label is stored text, written in the language of the
  session that made it (A4: "the undo action name"). After a language change old
  rows keep the old language, and `photocli` rows are English. If that matters, the
  entry would store a key and arguments instead of text; I did not, since the app is
  English only today.
- **RI-4 (information).** `docs/features/edit-history/prd.md` AC15 asked for a
  measure; it is a structural guarantee plus the timing above, not a loupe-open
  stopwatch, because the loupe never reads the table.

## README

- Nothing changes in requirements, build commands or repository layout.
- Suggested for the product manager at Ship: `CLAUDE.md`'s catalog table list gains
  `editHistory` (migration v14), and "Scope so far" gains one entry for this feature.
  `docs/features/ui-redesign/design.md`'s command map gains the Show / Hide History
  row (design.md §8 says so).

## Not done

- The palette-only History toolbar item (optional in design §8).
- R16 (Could): the per-row summary of what changed.
- I1 (inset selection style): not done. It changes cell geometry and I cannot see
  the result here; left for the designer's M6 check.

## Review findings (second pass, 2026-11-10)

Code review (`code-review.md`) and design review (`review.md`) of 4db535f.

| # | State | What was done |
|---|---|---|
| C1 | Fixed | LZFSE-compressed snapshots and a 4 MiB per-version byte budget, newest always kept, in migration v14 (owner ruling). Tests: `snapshotsAreCompressed` (stored size under half of the JSON, same stack back), `byteBudgetTrimsTheOldest` (oldest dropped first, survivors revert exactly), `newestEntryAlwaysSurvives` (budget of 10 bytes keeps the newest), `defaultBudget` (bounds a scribbled brush photo) |
| C2 | Fixed | An entry whose snapshot can't be read or decoded now reports in Activity as a warning ("“…” can't be restored: its saved state can't be read.", action "Revert"); a nil result (entry trimmed meanwhile) stays silent. My call: a message over disabling the row, since the row can't be known bad until its snapshot is read, and the list never reads snapshots |
| C3 | Fixed | A failed list read is logged and sets the list failed; the panel shows `unavailable(.failed)` ("History is unavailable. It could not be read from the library.") instead of loading forever. Test: `panelStates` |
| C4 | Recorded (owner ruling) | A copied version stays empty, no seed entry; the guide says so |
| F1 | Fixed | The keyboard request is set only when the panel state has entries (`canTakeKeyboard`, tested), cleared on collapse and when the focused photo changes, and cleared from a task, not inside the view update |
| F2 | Fixed | A click on the current or a dimmed row gives the keyboard back to the loupe |
| F3 | Fixed | `HistoryCell.configure` sets `toolTip` (label, exact time, the crop hint when dimmed); the dead delegate method is removed |
| F4 | Fixed (needs M3) | The body stays in the hierarchy with a frame height of 0 or the body height and `.clipped()`, so the frame animates; collapsed it refuses first responder, hit tests and VoiceOver |
| F5 | Fixed (needs M4) | Home, End, Page Up and Page Down move the cursor and scroll it into view |
| F6 | Fixed | The guide now says "it begins with the first recorded change: there is no entry for the photo as it was before that change"; it also mentions the size limit and that a copied version starts empty |
| I3 | Fixed | `setAccessibilityChildren([])` on the cell; the probe lists one `AXCell` per row |
| I4 | Fixed | While the next photo's list loads, the header keeps the previous count |
| I1 | Not done | See "Not done" |

Checks: `swift build` clean; `swift test` 672 passed (1 known issue); debug script on the
bundle copy: edit, edit, revert, collapse all behaved as before, rows are `AXCell`s.
Not verifiable here: animation (F4), Home/End/Page keys (F5), the keyboard fixes F1
and F2 (no key window), the tooltip (F3): the designer's M2 to M4, M7.
