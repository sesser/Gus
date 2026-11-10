# Edit history: code review

Owner: code-reviewer. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/edit-history`, develop..4db535f (prd.md, design.md, roadmap.md uncommitted, used as the spec). Build and tests: `swift build` clean; `swift test` 668 tests in 111 suites passed, 1 known issue (the baseline's). App bundle and debug script not run (qa-tester's job).

## Verdict
Ready for the next step (second pass: C1 to C3 fixed, one new test-gap nit N1). No blockers. One Should fix (snapshot size has no byte bound) and three nits; the engineer's two unspecified decisions are sound.

## Findings
| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoCore/Catalog/EditHistory.swift:55-62` | The cap is 100 rows, not bytes, and each row is the full stack JSON, uncompressed. | A brush-heavy photo (status.md's own measure: 75 KB per snapshot for one 5,000-dab mask) stores about 7.5 MB of history after 100 edits, in the same write transaction as each edit. A user who retouches 200 photos this way adds about 1.5 GB to `catalog.sqlite` (and its WAL, backups), with no way to clear it (R: no clear command). Worst case under `MaskLimits` is far higher. The size is easy to bound now, hard to claw back once libraries hold it (a shrink needs a new migration). | Robustness; Catalog |
| C2 | Nit | `Sources/PhotoApp/Model/AdjustmentEditor.swift` (`revert`, the `try? await catalog.editHistoryStack`) | A failed read or decode of the snapshot (damaged row, a schema this build cannot read) is swallowed: the click does nothing, no message. | An entry whose snapshot cannot be decoded looks like a dead row. Rare; a one-line announcement or log would make it findable. | `try?` on a failure a user would care about |
| C3 | Nit | `Sources/PhotoApp/Model/HistoryActions.swift` (`loadHistory`, the `catch { return }`) | A failed list read leaves `history.versionID` stale, so the panel stays in its loading state indefinitely. | Only on a database error; the panel never says it failed. | same |
| C4 | Nit | `Sources/PhotoCore/Catalog/Catalog.swift` (new-version-from-copy route) | A version created by copying another's stack starts with an empty history, so the panel says "No Edits Yet" for a photo that has edits. | Same shape as RI-1 (no entry for the unedited or inherited state); confirm the product manager is content, and mention it in the user guide if so. | PRD R-scope |

Suggested fix for C1 (engineer's choice): compress `stack` (LZFSE, about 4x on brush data per status.md) in `recordHistory` and `editHistoryStack`, and/or also trim by a byte budget per version (for example drop the oldest while the sum of `length(stack)` exceeds a few MB, always keeping the newest). Both are local to `EditHistory.swift`, but the storage format must be fixed before this migration reaches users, since changing it later costs a migration. If the owner rules the risk acceptable (see Questions), record the ruling in `status.md` and mark C1 Not fixed.

## Questions
- For the product manager/owner (C1): is an unbounded-bytes history acceptable for brush-heavy photos, or should the cap also be by size? The PRD fixes only the 100-entry cap.
- For the product manager (C4): should a copied version start with a first history entry for its inherited stack?

## Checked and fine
- Migration: `v14` added after `v13`, no old migration edited; table `editHistory` and its columns are generic (the `CatalogTests` schema-name test covers it); `versionId` is indexed and `ON DELETE CASCADE`; tests cover the cascade.
- Atomicity and cap: the entry is inserted in the same `database.write` as the stack and hash update (`setEditStacks`), then trimmed to the newest 100 of that version only (`recordHistory`; `capDropsTheOldest`). A refused write (unreadable stack) throws before any update or insert, so nothing is recorded and bytes and hash are untouched. Folding `refuseUnreadableStacks` into the same read is equivalent to the old check.
- A required `historyLabel` parameter on `setEditStack`, `setEditStacks` and both `changeEditStacks` means no write route can skip history. No other code writes the `editStack` column (grep).
- Equal-stack comparison ignoring operation ids: correct. It compares kind, kind version, enabled flag and parameters in order, so toggling a group off (render hash unchanged, content changed) still records an entry, and a rebuilt stack with fresh ids does not.
- Revert to a state equal to the current stack is a no-op and adds no undo step: consistent with R10 and A5. The revert goes through the same `apply` as an edit, with `undoingTo: committed.editStack`, so it is one undo step and one entry; stale or trimmed entries return nil and do nothing.
- Undo and redo logging: the label is read from `undoManager.isUndoing`/`isRedoing` synchronously in `apply`, and passed as `isUndo`/`!isUndo` into the batch undo closure, so it does not depend on state when the chain later runs. Writes stay on the `persist` chain; `historyChanged()` is bumped after the write lands.
- Debug script: `history revert` opens an undo group (`DebugScript.swift`); the other `history` commands change no photos. The revert's Task runs inside the awaited group.
- Concurrency: the list read (`loadHistory`) is an async catalog read of `id, label, createdAt` only, never the snapshot column; the loupe's own read does not touch `editHistory`. Snapshot decode happens in the catalog actor's read, not on the main actor. Stale loads are guarded by cancellation and the version check. No new `@unchecked Sendable` or `nonisolated(unsafe)`.
- No render change: no code under rendering touched, `PreviewCacheKey.currentPipelineVersion` untouched, no golden changed, `UPDATE_GOLDENS` not used (diff has no files under `Goldens/`).
- UI rules: AppKit `NSTableView` in `NSScrollView` and `AppKitButton`/`AppKitDisclosure` header, no SwiftUI `ScrollView`; the menu item reads `LibraryMenuContext` (`canShowHistory`, `historyIsOpen`) and not a model; ⌥⌘3 is unused elsewhere.
- Localization: 19 keys added, `LocalizationTests` and `BrandingTests` pass; "Collapse"/"Expand" already existed.
- photocli: `develop` and the mask commands record entries through `setEditStack`, so they use the existing `LibraryLock` write path; `--dry-run` writes nothing. English-only labels are noted as RI-3 and are acceptable.
- Tests: `EditHistoryTests` covers the acceptance criteria that are testable at the catalog level (entries, persistence, revert, undo logging, pairs, batch, cap, panel states, unreadable stacks, snapshot exactness, long history). Existing tests were adjusted only for the new parameter; no tolerance loosened.

## Follow-up
Second pass, 2026-11-10, commit e54ceeb. `swift build` clean; `swift test` 672 tests in 111 suites passed, 1 known issue (the baseline's).

| # | Result | Notes |
|---|---|---|
| C1 | Fixed (e54ceeb) | Snapshots are LZFSE blobs in the same `v14` (the migration exists only on this branch: `git branch --contains 4db535f` lists only it, and `develop...HEAD` shows it as one added migration, so nothing shipped was edited). Write path: compress in `recordHistory`; read path: `editHistoryStack` fetches `Data`, decompresses, decodes, so `revert` and `hasSameContent` still see a decoded `EditStack` (tests compare the read-back stack equal). Budget logic checked by trace: rows newest first, running total of stored `length(stack)`; index 0 is always kept; an older row is kept only while index < 100 and total <= budget; the loop breaks at the first miss, so the kept set is a contiguous newest run and `DELETE ... id < oldestKept` removes exactly the rest, for this version only. Same transaction as the edit. Tests: compression ratio and exact round trip, oldest-first trim to 4 survivors with exact revert of the oldest survivor, newest kept at budget 10, default budget on 30 scribbled 50,000-dab edits. |
| C2 | Fixed (e54ceeb) | A thrown read or decode now posts a warning to Activity with the entry's label and VoiceOver announcement; a nil (trimmed entry) stays a silent no-op, which is right. String added to the catalog. Not covered by a test (UI path; qa-tester can check with a damaged row). |
| C3 | Fixed (e54ceeb) | A failed list read sets `history.failed`, logs through `Logger` with a public error description, and the panel shows `.unavailable(.failed)`; cancellation is checked before it, so a cancelled load does not mark failure. Covered by `State.make(... listFailed: true)`. |
| C4 | Withdrawn | Owner ruling recorded in status.md (C4: copied version stays empty; guide says so). |

New code:
- Keyboard request: `tookKeyboard()` now runs in the `@MainActor` task, not inside `updateNSView`, so no state is mutated during a view update. `historyWantsKeyboard` is cleared on collapse and on a photo change, and set on open only when `canTakeKeyboard` (a list with rows), so a stale request cannot fire later. `refusesFirstResponder = isCollapsed` keeps the clipped list out of the key loop. Correct.
- F2 focus return: a click on the current or dimmed row now calls `leaveList()`; `activate` returns whether a revert was requested. Correct.
- Animated height: the content stays in the hierarchy with frame 0 when collapsed, `clipped`, hit testing and accessibility off; `reduceMotion` disables the animation. Fine. One cost: a collapsed panel keeps its table alive, which is cheap.
- Keys: Home, End, Page Up, Page Down (key codes 115, 119, 116, 121) move the cursor only, clamped to the list, with a page of at least one row; `numberOfRows > 0` guarded; `selectedRow` -1 with no selection gives Page Down from -1 + page, which lands inside the list after clamping. Fine.
- Tooltip moved onto the cell (`toolTip`), correct for a view-based table; the dead delegate method was removed. Cell accessibility children emptied so a row is read once.
- Strings: 3 keys added (failed state, the Activity message, "Revert"); `LocalizationTests` and `BrandingTests` pass in the full run.
- Count in the header persists while the next photo loads: only cosmetic.

Open (Nit, N1): AC11b is only half covered at the test level. "A copied version (`duplicateVersion`) starts with an empty history" has no assertion in `EditHistoryTests` (the ruling is recorded and the guide says it, but nothing would fail if `duplicateVersion` began copying history). "Reverting to a state the photo already has adds no entry" is covered only at the catalog (`unchangedWriteRecordsNothing`); the editor's `!hasSameContent(as: committed.editStack)` guard in `revert` is UI-model code with no test, so it is a qa-tester check. A three-line catalog test (`duplicateVersion` after an edit, then `editHistory(forVersion: copy).isEmpty`) would close the first half. AC11a is fully covered.

Findings by severity in this pass: 0 Blocker, 0 Should fix, 1 Nit (N1).

Third pass, 2026-11-10, commit 572c74c only. `swift build` clean; `swift test` 674 tests in 111 suites passed, 1 known issue (the baseline's). No finding.

| # | Result | Notes |
|---|---|---|
| N1 | Fixed (572c74c) | `copiedVersionStartsEmpty` edits a photo (one entry), duplicates it, and asserts the copy has no entries, the original still has one, and the copy carries the same stack content; it would fail if `duplicateVersion` copied history. `revertGuardIgnoresOperationIDs` pins the comparison the editor's guard relies on (`hasSameContent` ignores operation ids, still sees different settings). It tests the predicate, not the guard line in `AdjustmentEditor.revert`, so the guard itself stays a qa-tester check; acceptable for a nit. |

Copy and catalog: the failed-read Activity message now has the row title `Revert to “label”` from `HistoryText.revert(toLabel:)`, the same string as the undo name, so no separate "Revert" key is needed. Removed keys ("Revert", the "“%@” can't be restored..." message) have no remaining uses in `Sources` (grep); added keys ("Its saved state can't be read. The photo is unchanged.", "History is unavailable. It can't be read from the library.") match their `String(localized:)` literals exactly, and the renamed key kept its comment and value. `LocalizationTests` and `BrandingTests` pass. USER_GUIDE matches the behavior.

Cosmetic, not a finding: the VoiceOver announcement for this warning is now the message alone ("Its saved state can't be read. The photo is unchanged."), without the entry's label, since `report(_:action:warning:)` announces `text`. The Activity row still shows the label in its title. If the label matters for VoiceOver, use the `announcing:` overload.

Findings by severity in this pass: 0 Blocker, 0 Should fix, 0 Nit. All earlier findings are closed.
