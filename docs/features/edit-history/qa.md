# Edit history: QA

Owner: qa-tester. Date: 2026-11-10. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/edit-history` at 572c74c, on a Mac running macOS 27 (Darwin 27.2.0), Xcode 26+ SDK (`Scripts/build-app.sh` passed its SDK check).

## Verdict
Passes, with no findings against the feature. Every AC has a test or a script check; the visual, motion, VoiceOver and menu-state checks are left to a person (P1 to P7). One note on the debug script's `history revert` (Q1, not a product bug) and one housekeeping note on the owner's library (below).

Housekeeping: at the end of the run `/Applications/Gus.app` (pid 55909, started 06:11:34) was running and the owner's library folder had files newer than my start (`catalog.sqlite-wal`, `-shm`, `library.lock`). I never launched `/Applications/Gus.app`: every launch I made was the scratch copy `Gus.app` (bundle id `me.sesser.gus.debugtest`) with `--library-root` on a scratch library, and no instance of mine was left running. I did not touch or quit that process; the owner should confirm it is theirs.

## Acceptance criteria
| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Test + Script | `EditHistoryTests` "AC1: an edit and a crop are two entries…"; Script A: exposure, contrast, crop Done gave three rows (newest first) with labels and times | Pass |
| AC2 | Test + Script | "AC2: the entries are there after the catalog is closed and opened again"; Script A then a second launch on the same library (Script B) listed the same four rows | Pass |
| AC3 | Person | P2 (scroll with more rows than fit) | Open |
| AC4 | Script | Script A: check mark on row 0 after every edit and after the revert | Pass |
| AC5 | Test + Script | "AC5, AC6: a revert is a new entry…"; Script A: `history revert 2` gave 4 rows, "Revert to “Debug exposure”" on top, earlier three unchanged | Pass |
| AC6 | Test | same test (fifth entry, first three still there) | Pass |
| AC7 | Script + Person | Script A: `print undo` read `Revert to “Debug exposure”`; Edit menu showed Undo ⌘Z and Redo ⇧⌘Z, no ⌘Y item (Script H). Menu enabled state needs a key window: P5 | Pass (menu state Open, P5) |
| AC8 | Test | "AC8: an undo write adds an entry whose stack equals the stack before the edit" | Pass |
| AC9 | Test | "AC9: an edit on the RAW of a pair adds no entry to the JPEG" | Pass |
| AC10 | Test | "AC10: pasting onto three photos, one already the same, adds an entry to two" | Pass |
| AC11 | Test | "AC11: 101 saved changes leave 100 entries and the first one is gone"; no clear command exists (grep of Sources: none) | Pass |
| AC11a | Test | "A byte budget drops the oldest entries first…", "The newest entry is never trimmed…", "Snapshots are stored LZFSE compressed and read back as the same stack", "The default budget bounds…" | Pass |
| AC11b | Test + Script | "AC11b: a copied version starts with an empty history…"; "revert guard" test; Script A/C: reverting to a row equal to the current stack added no entry (4 entries before and after) | Pass (see Q1 for the undo step) |
| AC12 | Script + Test | Script D: video `unavailable(video)`, offline `unavailable(offline)`, grid and review `absent`, no table; "The panel is absent in the grid and in review…" | Pass |
| AC13 | Test + Script | "AC13: an unreadable stack records nothing…"; Script D: schema-99 stack, panel `unavailable(unreadable)`, an exposure change refused, `editStack` text byte-identical in SQLite afterwards, no entry | Pass |
| AC14 | Person | P4 | Open |
| AC15 | Test | "AC15: reading 100 entries of large stacks…" (list read excludes snapshots; the loupe's own read never touches `editHistory`, by code reading of `AdjustmentEditor.follow`) | Pass |
| AC16 | Test | Full `swift test`: 674 passed, 1 known issue (the baseline's), no golden moved, `UPDATE_GOLDENS` never run; "An entry stores the stack as saved, and the stored stack and hash are what they were before this feature" | Pass |

Items the reviews left to QA:

| Item | How | Result |
|---|---|---|
| Revert to an equal state: no entry, no undo step | Script A, C | Entry: Pass. Undo step: the editor's guard returns before `apply` (code) and the predicate is tested; in the script a no-op `history revert` still leaves one empty undo group, see Q1 |
| Unreadable-entry Activity warning (deliberately damaged row) | Script E | Pass: Activity `[Revert to “Debug contrast”] Its saved state can't be read. The photo is unchanged.`, warning true; photo hash unchanged, no entry added |
| Relaunch persistence | Script B | Pass |
| Byte budget trimming | Tests (AC11a); not scripted: the debug script has no way to make a large stack cheaply | Pass |
| States: empty, video, offline, unreadable | Script A (empty first), D | Pass |
| Absent in grid and review | Script D | Pass |
| `photocli develop` records an entry | Script F, and "Q2: photocli develop records an entry…" | Pass: dry run none, a change one ("Develop (command line)"), the same value again none, `--reset all` one |

Counts (18 ACs): passed by test 14 (AC1, AC2, AC5, AC6, AC8, AC9, AC10, AC11, AC11a, AC11b, AC12, AC13, AC15, AC16; six of them also by script); passed by script only 2 (AC4, AC7, whose menu state is P5); open for a person 2 (AC3, AC14); failed 0.

## Findings
Q1 (low, for the engineer; harness, not product). `DebugScript` wraps every `history revert <n>` in an undo group (`words.first == "history" && …revert`). When the revert does nothing (a row equal to the current stack, or a bad row), the empty group still becomes an undo step: `print undo` then shows `undo ''` and one `undo` pops it with no change. Control: after one real edit, `history revert 99` (prints "expects a row number", changes nothing) also gives `undo ''`. So the script cannot show "no undo step" for the no-op revert; the proof rests on the guard in `AdjustmentEditor.revert` returning before `apply` and on the tests. Optional fix: skip the group when the revert is a no-op, or have `history revert` report the undo depth. Not a blocker.

## Scripts
Setup, repeated for each run (scratch under the session scratchpad, `$S`):

```
Scripts/build-app.sh
cp -R build/Gus.app $S/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $S/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $S/Gus.app
swift run -c release photobench generate --output $S/src --jpeg 6 --dng 2 --videos 1 --pairs 1
swift run -c release photobench import --library-root $S/lib --source $S/src
$S/Gus.app/Contents/MacOS/Gus --library-root $S/lib --debug-script "<script>"
```

Script A (library `lib`; AC1, AC4, AC5, AC8, AC11b):
```
wait 2; focus 0; loupe; wait 1; tab adjust; history wait; history; adjust exposure 0.5; adjust contrast 20; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; history wait; history open; history; history revert 2; history; print undo; history revert 3; history; print undo; history revert 0; history; print undo; undo; history wait; history; print undo; redo; history wait; history; quit
```
Showed: empty list first; then Crop, Debug contrast, Debug exposure with the check mark on Crop; after `history revert 2` four rows with "Revert to “Debug exposure”" on top and checked; `revert 3` (equal state) and `revert 0` (current) left 4 rows. `print undo` went from `Revert to “Debug exposure”` to `''` (Q1). The `undo` that followed added no row: the script's undo ran on the empty group.

Script B (same library, second launch; AC2):
```
wait 2; focus 0; loupe; wait 1; history wait; history; quit
```
Showed the same four rows and times.

Script C (control for Q1, copy of `lib`):
```
wait 2; focus 2; loupe; wait 1; tab adjust; history wait; adjust exposure 0.5; history wait; print undo; history revert 99; print undo; history; quit
```
Showed `undo 'Debug exposure'` then `undo ''` after a revert that changed nothing.

Script D (copy `lib4`: the schema-99 stack set with sqlite3 on image 3's version; AC12, AC13; `lib5`: `update volume set identity='uuid:0000…'` for offline):
```
wait 2; focus IMG_00003; loupe; wait 1; tab adjust; history wait; history; adjust exposure 0.3; wait 1; history; focus MVI_00110; wait 2; history; grid; wait 1; history; review on; wait 1; history; review off; quit
wait 2; checkdisk; focus IMG_00001; loupe; wait 1; history wait; history; print selection; quit
```
Showed `unavailable(unreadable)` (twice; the edit changed nothing, stored `editStack` text identical afterwards, no new entry), `unavailable(video)`, `absent` in grid and review, and `unavailable(offline)` with no table.

Script E (copy `lib3`, `update editHistory set stack=X'DEADBEEF0102' where label='Debug contrast'`; C2, F7):
```
wait 2; focus 0; loupe; wait 1; tab adjust; history wait; print adjustments; history revert 2; print activity; history; print adjustments; quit
```
Showed the warning in Activity and an unchanged hash `4dee610a65b9` and four rows.

Script F (copy `lib6`, no app running; `photocli` takes `--library-root` as two array words):
```
swift run photocli develop --version 5 --set exposure.ev=0.7 --dry-run --library-root $S/lib6
swift run photocli develop --version 5 --set exposure.ev=0.7 --library-root $S/lib6
swift run photocli develop --version 5 --set exposure.ev=0.7 --library-root $S/lib6
swift run photocli develop --version 5 --reset all --library-root $S/lib6
sqlite3 $S/lib6/Library/catalog.sqlite "select id,versionId,label from editHistory where versionId=5"
```
Showed no row after the dry run, one "Develop (command line)" after the first write, still one after the repeat, two after the reset.

Script H (launched with `open -W -n --stdout $S/open.log Gus.app --args --library-root $S/lib7 --debug-script "…menuitems History; menuitems Undo; menuitems Redo…; quit"`): the process had no key window (`key nil`), so View ▸ Show History, Undo and Redo all read disabled; their keys were ⌥⌘3, ⌘Z and ⇧⌘Z, and no item had ⌘Y. Enabled state and title are P5.

Tests: `swift test`: 674 tests in 111 suites passed, 1 known issue (baseline). `swift test --filter EditHistoryTests`: 25 passed.

## For a person
Run `Scripts/build-app.sh`, then the bundle with `--library-root` on a scratch library (`photobench generate` then `import`). One short list; the designer's M-numbers and the engineer's list are folded in.

- P1 (M1, M3, M6, M8; engineer 1, 2, 8). Look: the History panel at the inspector's foot in both tabs, collapsed on first launch (header, triangle, count; no count while loading or empty). Expand by title, triangle and ⌥⌘3: body grows upward about 0.25 s, tab content above follows without a jump, a click mid-animation retargets; with Reduce Motion on it is instant. Check mark and semibold on the top row, time right-aligned; yesterday reads "Yesterday", older dates month and day; 24-hour setting is followed. Light, Dark, Increase Contrast: label and time readable, also on the highlighted row, key and not key. Selection bar shape against the rounded pane on macOS 26 and, if available, a macOS 15 / older-SDK build (I1 under M6); the last row clears the rounded corner.
- P2 (M4; AC3; engineer 3). With more than eight entries the list scrolls with the overlay scroller. With the list focused: Up and Down move the cursor without changing the photo; Home, End, Page Up, Page Down move the cursor; letters do nothing; Return and Space revert; Esc returns the keyboard to the loupe.
- P3 (M2, M7; engineer 3, 6). Hover a row about a second: tooltip with label and exact time with seconds. Start a crop: rows dim and do nothing, tooltip adds the crop hint; cancel the crop: rows work. Click the current row and a dimmed row, then press an arrow key: the photo must change. Press ⌥⌘3 on a photo with no edits, make one edit, arrow to another photo with history: the keyboard stays in the loupe. Click an earlier row: the photo changes, "Revert to “…”" appears at the top, the keyboard returns to the loupe.
- P4 (M5; AC14; engineer 5). VoiceOver: header reads "History, button, collapsed/expanded" with the "N entries" hint; the list is "Edit History"; rows read label, "Today at …" and ", current state" on the top row, once each (no duplicates); "selected" on the cursor row; VO-Space on an earlier row reverts and says "Reverted to …"; the current row offers no action. Full Keyboard Access reaches the header and every row.
- P5 (M9; AC7; engineer 7). View menu: "Show History" / "Hide History" follow the panel; ⌥⌘3 dimmed in the grid, review mode, and in the loupe with a sheet open; with the inspector hidden (⌥⌘I) it brings the inspector back, expands the panel and puts the cursor on the top row; Hide History returns the keyboard to the loupe. After a revert Edit ▸ Undo reads "Undo Revert to “…”", ⇧⌘Z redoes, ⌘Y does nothing. Also in a real click: revert to a state equal to the current one and confirm Edit ▸ Undo is unchanged (the no-op revert, Q1).
- P6 (engineer 9; AC12). A video, an offline photo and a photo with unreadable edits each show their own line in the panel; grid and review show no panel or control.
- P7 (F7; optional). With a photo whose entry you damaged (`update editHistory set stack=X'DEADBEEF' …` on a scratch copy), click that row: the Activity row reads "Revert to “…”" with "Its saved state can't be read. The photo is unchanged."

Not built, not checked: the palette-only toolbar item (optional in design §8) and R16.

## Follow-up
No fixes since this run; no reruns.

Owner's sign-off: signed off in chat on 2026-11-10 at commit 572c74c (relayed by the main session).
- P7 (Activity row from a damaged entry): the owner reproduced it and found a separate bug: the Activity toolbar item shows an alert icon after an unreadable history entry, but clicking it shows no popover until photos change (the icon then disappears). The branch does not touch `ActivityToolbarItem.swift` and the owner recalls the same after an import, so it is tracked separately as `bug/activity-popover`, not part of this branch. The warning text itself was verified by Script E.
- P1 to P6 (M1 to M9, AC3, AC14, AC7 menu state): not individually reported by the owner. They stay open checks carried by the sign-off, not recorded as done.
- Q1 (debug script, optional): not addressed.
