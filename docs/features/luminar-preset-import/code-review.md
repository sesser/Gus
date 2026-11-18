# Import preset packs (.lnpc): code review

Owner: code-reviewer. Date: 2026-11-17. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/luminar-preset-import`, 05457c6..3ece314 (code as of
923d9fd; 3ece314 is the design review, docs only). Spec: PRD rev 3 (issue
#203 body), `design.md` rev 2, `status.md` with the owner's rulings DQ-1,
DQ-2, RI-E1 to RI-E3 (taken as given). Build and tests: `swift build` clean;
`swift test` 1128 tests in 169 suites, all pass. Opt-in
`LUMINAR_PACKS=… LUMINAR_PROTOTYPE_OUTPUT=… swift test --filter
PresetPackSampleTests` with the owner's four packs (read only) and the
prototype's output: both pass, 40 presets compared, all equal within
rounding; release timing of the table check 0.50 s, as `status.md` says.

## Verdict

Not ready for QA yet, but close. The mapping matches the prototype and the
PRD, the zip reader's bounds hold for what it checks, the concurrent table
check gives the same result in the same order, and nothing that renders or is
stored changed. Two size limits can be got around with a crafted file or
folder (C1, C2), and the zip limits have no tests (C3). All three are small
fixes.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoCore/Presets/Luminar/LuminarPack.swift:181-196`, `:233` | Nothing limits how many presets a pack's `config.json` lists. Every entry in `templates` becomes a row: `entry()` returns `.unreadable` for a folder the archive doesn't have, and the pack still imports as long as one preset can be read. On top of that, `unlisted` calls `listed.contains` on an array for every template folder (O(folders × listed)), and every preset sorts all of the archive's paths again (`files.keys.sorted()` at :233). | A 64 MiB `config.json` (within `maximumMemberSize`, a few KB deflated) with `"templates": ["", "", …]` lists about 22 million entries, next to one real preset. `JSONSerialization`, then `listed`, then 22 million `PackPresetReport`s take several GB, and the Import Report's `List` gets 22 million rows. With 9,999 template folders as well, the `unlisted` filter alone does about 2×10¹¹ string comparisons. The import can't be stopped, and `presetImportChain` holds every later import behind it. | Parsers of outside files: counts checked before allocation (`CLAUDE.md` checklist; R9) |
| C2 | Should fix | `LuminarPack.swift:64-66`; `PresetImport.swift:142-148` | The 256 MiB file limit reads `.fileSizeKey` from the URL as it was given. For a symbolic link that is the size of the link itself, but `Data(contentsOf:)` then reads the file it points to. `files(in:)` lists symbolic links whose names end in `.lnpc`. | I checked this here: a link `link.lnpc` to a 300 MB file reports `fileSize` 7 (`isRegularFile` false), so the guard passes and the whole 300 MB is read. In a folder someone downloaded, a `pack.lnpc` that links to `/dev/zero` makes a folder import read with no end. Fix: resolve the link first and require a regular file (`resolvingSymlinksInPath()`, then `.isRegularFileKey` and `.fileSizeKey`), or read through a `FileHandle` with a cap. | Sizes checked before allocation (R9) |
| C3 | Should fix | `Sources/PhotoCore/Support/ZipArchive.swift:37-39, 66, 98-99, 108-116`; `LuminarPack.swift:11-14, 65, 124`; `Tests/PhotoCoreTests/PresetPackReadingTests.swift` | No test covers these refusals: `maximumMemberSize`, `maximumEntryCount`, the encryption flag, a compression method other than stored or deflate, the 512 MiB read budget, and the 256 MiB file limit. Only the ZIP64 end record is tested. | Deleting the guard at `ZipArchive.swift:99` (member size) or `LuminarPack.swift:124` (read budget) leaves the whole suite green. These guards are the import's protection against zip bombs. Each check is a few lines with `ZipWriter`: patch the central directory's size, flags or method fields, or lower the limits through an internal parameter. | Tests: the bounds a parser relies on |
| C4 | Nit | `PresetImport.swift:250-266`; `docs/features/luminar-preset-import/status.md:177-179` | `status.md` says that when two presets in one pack share a name, "the later replaces the earlier". In fact `deduplicated` keeps the **first**, because both have the same rank, and it compares names without regard to case ("Sunset" and "sunset" also collapse), while the catalog's name rule is case-sensitive. The pack's report still counts both as imported. | A pack with "Sunset" then "sunset" saves only the first. The pack's line says "2 presets" while `added` is 1. RI-E3 was ruled on the description, so correct the record (or the code, so that the later one wins as described). This is not a call to reopen the ruling. | Correctness of the record |
| C5 | Nit | `PresetPackReadingTests.swift:99-101` | The fallback-name test uses `Land_of_the_Rising_Sun.lnpc` / "Land of the Rising Sun", the title of one of the owner's commercial packs. | The PRD's non-goals say "test fixtures are made up in the tests". Any made-up name with underscores tests the same thing. | R11, non-goals |
| C6 | Nit | `PresetImport.swift:303-306, 372-376`; `LuminarMapping.swift:290-294`; `PresetImport.swift:216-223` | When a pack's table doesn't install (not a readable cube), `leaveOutLookUpTable` drops every row for the look-up table tool, including its "approximated (as Contrast and Saturation)" row. The table's Contrast and Saturation stay in the preset's Tone and Presence values. The pack's "N look-up tables" also counts that table. | A preset whose table tool has Contrast 20 and an unreadable `.cube` saves with `tone.contrast` 20, but its report says only "Left out: LUT Mapping", and the pack's line says "1 look-up table" when none was installed. Either keep the approximated row, or take the table's contrast and saturation out with it. | R7: the report says what was carried over |

## Questions

None for the designer or product manager. The design review's F1 (a test that
every extension gives a `UTType`) and F2 (a second sheet) are in
`review.md`. I agree with F1, and I haven't repeated it here.

## For `/security-review`

The branch adds parsers of outside files (zip, JSON, `.strings`, template
values, curve text). The main session should run `/security-review` and look
at:

- `ZipArchive`: bounds arithmetic in the end record and central directory
  walk, overlapping or duplicate members, `compression_decode_buffer` with
  the declared size, CRC, and the per-member and per-file budgets (C1, C3).
- The file-size check and symbolic links or special files (C2). Other
  formats' existing reads (`PresetFile` xz payload, `CameraRawSettings`) have
  no size cap at all. That is older than this branch and may deserve its own issue.
- Memory held across one import: `scan.tables` keeps the data of every pack's
  tables until `run` ends, for up to `fileLimit` (2,000) files in a folder.
  `installTables` now parses up to the core count of tables at once. Each
  parse is several times its table's size, and `CubeLUT` checks the size line
  only after parsing all of it.
- Paths from the archive are used only as dictionary keys. Nothing is written
  from them: tables go to `LUTs/<sha256>.cube`, and the pack's file name is
  stored as text only. I found no path from a file to a write.

I checked parser depth: `JSONSerialization` refuses nesting past 512 levels
and the `.strings` (property list) parser past about 1,000. Neither
overflowed a 512 KB thread stack in a quick check.

## Checked and fine

- **Zip reader.** The end-record search stays in bounds (`count - 22`, comment
  length checked). Every central-directory read is guarded by `<= end`, and
  local header and data ranges by `data.count`. ZIP64 markers (0xFFFF,
  0xFFFFFFFF) are refused as too large, and multi-disk archives as damaged.
  Encryption (bit 0) and other methods are refused when a member is read.
  Stored members must have equal sizes. Deflate output is allocated at the
  declared size after the 64 MiB check. A short or long stream fails the
  length or CRC check. CRC-32 is the reflected 0xEDB88320. `COMPRESSION_ZLIB`
  is raw deflate, as the code says. `Data(data)` doesn't copy (checked), and
  slices are re-based, so indices start at 0. Truncated data that starts with
  `PK\3\4` is reported as damaged, and anything else as not a zip.
- **Pack reading.** Paths are normalized: absolute, `..`, hidden and
  `__MACOSX` paths are dropped. Members are read in memory only (the
  `packCodeWritesNoFiles` guard). The 512 MiB budget is charged before
  decompressing. One unreadable template gives an unreadable entry, not a
  refused pack (design A4), while a damaged member elsewhere refuses the file
  as "damaged" (design §3 table). Names use the system language over English,
  and `placeholderKeys` fall back to the file name.
- **Mapping against the prototype** (`mapping.py`, `curves.py`,
  `template.py`, read only). I compared it handler by handler: Develop
  (non-raw versus raw rule, white balance relative versus Kelvin), the table
  (name order, intensity, contrast and saturation), Color, Color Enhancer,
  split toning, Supercontrast, Matte, Details, Structure, Dramatic, Landscape,
  AI Enhance, black and white (earlier tinting dropped), grain and vignette
  scales, sharpening (summed, the strongest source's radius and masking),
  clamps, 4-decimal rounding, curve parsing, and 17-point composition in tool
  order. The differences are the report's granularity only (matte toning,
  selective color and vignette style folded into "approximated"), which
  `status.md` records. The opt-in comparison confirms all 40 of the owner's
  presets.
- **R10 / AC9.** Every scale is a named `public static let`, and
  `assumedScalesAreTheRecordedOnes` pins each one and checks that two are
  used.
- **R11 / AC10.** One table (`LuminarTool`, 36 cases, owner's RI-E1). Its
  catalog entries are keyed `presetPackTool.<case>` with one comment, and the
  test matches the catalog to the table both ways. Unknown identifiers are
  shown verbatim. No `lnpc` or brand in either `Info.plist`. The Finder's
  open path takes `PresetFile.fileExtensions` only. No catalog string names
  the application or its maker. No binary file, pack, `.lmps`, `.cube` or
  icon from a pack is committed (the fixtures are made up apart from C5's
  name). Nothing from the prototype is copied into the repository.
- **`PresetFile.installTables` (DQ-1).** Results are written by index under a
  `Mutex`, and installation stays one after another in the file's order. The
  identifier map, the files written and the skipped tables are as before, so
  `.guspreset` imports behave the same. `installsTablesAsOneAtATimeWould`
  covers this. The only caller is `PresetImport.run`, which is nonisolated
  async (Swift 6 tools, no `NonisolatedNonsendingByDefault`), so the
  `concurrentPerform` never runs on the main actor. A side observation, not a
  finding: in a debug build on this machine, while it was loaded (Spotlight at
  100%, load 14), the table check took 27 to 35 s. I didn't measure the
  one-at-a-time version under the same load.
- **Concurrency in the app.** `scan` runs detached. `run` is off the main
  actor. The import chain is read and replaced with no suspension in
  between, so imports stay ordered. `pendingPresetImports` is balanced by
  `defer`. `PresetReportText` is `@MainActor`.
- **Existing behavior.** Other formats keep the alert and the
  `readFile`/dedup path. Pack items get a key of their own (`"\u{1}<index>"`),
  so packs never deduplicate against folders or each other. The table
  identifier rewrite for non-pack items is unchanged. Re-import replaces by
  name, keeping the id (AC7 test).
- **Project rules.** No migration, no `currentPipelineVersion` change, no
  golden touched, no `Package.swift` or `Package.resolved` change, no new
  dependency (Compression is an Apple framework). There is no SwiftUI
  `ScrollView` under the toolbar: the report is a `List` in the preset
  manager sheet, as the list page already was. The inspector's import is
  still an `AppKitButton`. Every new UI string has a catalog entry, with
  plural variants where they are needed (`LocalizationTests` and
  `BrandingTests` pass). The debug script's `preset` commands change no
  photos, so they need no undo group.
- **Type checking.** With the local Swift 6.4.2 and
  `-warn-long-expression-type-checking=50`, no expression in the new
  PhotoCore files was flagged. `PresetImportReportPage.body` took 191 ms
  under load, below existing views (`LoupeView` 343 ms). The 6.2.4 floor
  itself can only be checked by CI.

## Follow-up

(After the engineer's fixes: each finding Fixed, Not fixed or Withdrawn, with
the commit.)

### Second pass (2026-11-17)

Reviewed: the fix commits eda06c5 and 7d784f0 (`git diff 3ece314..b8c475d`;
a099e7f and b8c475d are review files only). Build and tests at b8c475d:
`swift build` clean; `swift test` 1134 tests in 169 suites, all pass. Opt-in
`PresetPackSampleTests` with the owner's four packs (read only) and the
prototype's output: both pass, 40 presets equal within rounding, every table
of the four packs still counted (8, 9, 9, 10).

**Verdict: ready for QA once C7 is fixed or ruled on.** Every first-pass
finding is fixed. F2's fix leaves out one of the library window's sheets
(C7). C8 is a nit.

| # | Result | Commit | Notes |
|---|---|---|---|
| C1 | Fixed | eda06c5 | `maximumPresetCount` (1,000) applies to the preset folders the archive holds and to the entries every config lists. Both are counted before any row is made. Rows per file are now at most 2,000 (listed plus unlisted, or the orphans). `unlisted` uses a `Set`, paths are sorted once, and resources are indexed once. The order is the same (listed, then unlisted sorted, then orphans sorted), and the sample comparison confirms it. Real packs hold 10 presets each, far under the cap. Two gaps remain. The guard on preset folders (`LuminarPack.swift:213`) has no test, but the zip's 10,000-member limit bounds it anyway. The parse cost before the count is C8. |
| C2 | Fixed | eda06c5 | `contents(of:limit:)` resolves the link, requires a regular file, checks the size, then reads through a `FileHandle` capped at limit + 1. Folder imports skip links to anything but a regular file, and skip dangling links. The test covers a file, a link to it, a folder, a link to a folder, `/dev/zero` and the folder listing. A link that is swapped for a FIFO between the check and the open could block that one read. That needs a local attacker, so it is not a finding. |
| C3 | Fixed | eda06c5 | Member size, entry count, the encryption flag, an unsupported method, the read budget and the file limit are all tested now. By reading: without the member-size guard, a stored member whose sizes differ is reported `damaged`, not `tooLarge`. Without the budget guard, the 200-byte budget read succeeds. Either way the test fails, as `status.md` says. |
| C4 | Fixed (record) | eda06c5 | `status.md` Known limits now says the first one is kept, names are compared without regard to case, and the count can be one high. |
| C5 | Fixed | eda06c5 | The fixture name is now "Valley of Quiet Lakes". |
| C6 | Fixed | eda06c5 | Only the `mapped` row becomes `leftOut`. The approximated row stays and its values apply (the test checks `tone.contrast` 20). `tableCount` counts only tables in `installed`, which is keyed by the original identifier, as the preset rewrite above it is. Showing a mapped row and an approximated row for one tool is how the mapping already reported it. |
| F1 | Confirmed | eda06c5 | `everyImportExtensionHasAType` passes here. |
| F2 | Partly fixed: see C7 | 7d784f0 | This works for Export and the look-up table sheet. `onDismiss` re-checks both flags, so a sheet reopened in the gap keeps the wait, and every wait is resolved by that sheet's own dismissal. |
| Nits (design) | Confirmed | 7d784f0 | The `PageHeader` comment is corrected, and `.help` is on the unreadable row. |

New findings:

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C7 | Should fix | `Sources/PhotoApp/Model/PresetActions.swift:153-169`; `Sources/PhotoApp/Views/SidebarView.swift:237-240` | The library window has four sheet sources, not three. The fourth is `sidebarSheet`: New Album…, New Smart Album…, Edit Smart Album… and Rename… for a keyword, all from the menu bar, the toolbar and row menus, plus the sidebar's delete `confirmationDialog`. `openPresetSheetWhenFree` and `sheetDidDismiss` check only `showsExportSheet` and `showsLookTableSheet`, and the sidebar sheet has no `onDismiss`. | A pack import ends while File ▸ New Smart Album… is open. This can happen in the 0.5 to 0.7 s after the panel closes, and for longer with a folder of packs (the table check took 28 s in a debug build here). `openPresetSheetWhenFree` sees neither flag set and sets `showsPresetSheet = true` while the smart album sheet is attached. That is the two-sheet state F2 was about, and the wait path cannot apply. I did not launch the app, so what SwiftUI then does is unverified. QA can show it with `sheet smart; preset summary MadeUp.lnpc; preset sheets`, which reports `attached`, and then see whether the smart album sheet survives. Fix: add `sidebarSheet != nil` (and `sidebarDeletion != nil`) to both guards, and `onDismiss: model.sheetDidDismiss` on the sidebar's `.sheet(item:)`. Window-modal alerts (`WindowModal`) are a further, rarer case. | One sheet at a time (UI_REDESIGN §8, design §2.2; F2) |
| C8 | Nit | `LuminarPack.swift:162-169, 217-222` | The count happens after the whole `config.json` is parsed, and JSON, `.strings` and template members are capped only by the 64 MiB member limit, though real ones are a few KB. | I measured a 64 MiB `{"templates":["","",…]}` (22.4 million entries, a few hundred KB deflated) here: `JSONSerialization` takes 1.3 s and peaks at about 1.4 GB, and then the pack is refused. The cost is bounded and passes. However, a folder of 2,000 such files holds the import chain about 45 minutes, and it can't be stopped. A cap of a few MiB on members that are parsed as text would bound it. Optional. Worth a look in `/security-review`. | Sizes checked before allocation (R9) |

Rechecked for the fixes:

- **Concurrency.** `openPresetSheetWhenFree` and `sheetDidDismiss` are on
  the `@MainActor` model and are called from `runPresetImport` and SwiftUI's
  `onDismiss`, both on the main actor. `presetSheetWaits` is plain observable
  state, so there is no new race. The debug script's `preset sheets` only
  reads, so it needs no undo group.
- **Swift 6.2.4 floor.** `onDismiss: model.sheetDidDismiss` is the first
  method reference passed as a SwiftUI closure in the code base. It
  type-checks with no diagnostic in Swift 6 mode with complete checking here
  (6.4.2, macOS 27 SDK; a standalone reproduction). Only CI (Xcode 26.3) can
  confirm it on 6.2.4. If it fails there, `{ model.sheetDidDismiss() }` is
  the fallback. The new test expressions (`patched`'s four-term shift and
  OR, and the byte array) type-check in 15 to 33 ms here, well within reach
  of an older checker.
- **Effect of the cap on real packs.** None: 40 presets in 4 packs, 10 each.
  Folder imports apply the cap per file.
- **Other formats.** The regular-file filter in `files(in:)` now also skips
  `.xmp`, `.lrtemplate`, `.dng` and preset-file links that lead to folders or
  devices. That is a harmless improvement. Those formats' reads are still
  uncapped, which predates this branch (first pass, `/security-review`
  notes).

`/security-review` still applies to the branch (parsers of outside files), now
with C8 and the FIFO note above added to its list.

### Third pass (2026-11-17)

Reviewed: 83bae21 only (`git show 83bae21`), against C7 and C8. Build and
tests at 83bae21: `swift build` clean; `swift test` 1135 tests in 169 suites,
all pass. Opt-in `LUMINAR_PACKS=~/Projects/luminar-presets
LUMINAR_PROTOTYPE_OUTPUT=~/Projects/luminar-presets/gus-presets swift test
--filter PresetPackSampleTests` (packs read only): both pass, 40 presets equal
to the prototype's within rounding, tables 8, 9, 9, 10, all added. The
largest text member in the four real packs is a 75 KB `template.lmps`, about
1/55 of the new 4 MiB cap.

**Verdict: not ready for QA until C9 is fixed or ruled on.** C7 is fixed for
everything it named, and C8 is fixed. One more sheet source in the library
window, the Remove from Library confirmation, is outside `otherSheetIsUp`
(C9). C10 is a nit.

| # | Result | Commit | Notes |
|---|---|---|---|
| C7 | Fixed, as named | 83bae21 | `otherSheetIsUp` (Export, look-up tables, `sidebarSheet`, `sidebarDeletion`) is the only guard, used by `openPresetSheetWhenFree` and `sheetDidDismiss`. The sidebar's `.sheet(item:)` has `onDismiss`. When the item changes from one sheet to another, `onDismiss` runs with the new item already set, so the guard keeps the wait. The delete dialog's `onChange(of: sidebarDeletion == nil)` fires only on a change to nil (no `initial:`), on Delete as well as on Cancel. It calls `sheetDidDismiss` as the dialog begins to close, not after it has closed as `onDismiss` would. `status.md` says the snapshot after `sheet deleteclose` shows the Import Report alone; QA should repeat that check, because it is the one path without `onDismiss`. The swept sources missed one sheet: see C9. |
| 6.2.4 | Confirmed | 83bae21 | No method reference is passed as `onDismiss` anywhere in `Sources/` (all three are `{ model.sheetDidDismiss() }`). The two-parameter `onChange` is macOS 14 API, below the macOS 15 minimum. |
| C8 | Fixed | 83bae21 | `readText` checks the central directory's declared size before any read or budget charge. That size bounds the real output: stored members must match it, and inflate writes into a buffer of exactly that size and fails on any other length. Every JSON, `.strings` and template read goes through `readText`; resources (tables, images) keep the member limit. The test fails without the guard: by reading, with the guard removed the one-byte-over members parse (trailing spaces are valid in all three), so nothing throws. A missing path throws `damaged`, as `read` does, and every caller checks presence first. A correction to my second pass: the cap bounds peak memory, not the time a hostile folder takes. Measured here (release, macOS 27.2), one 4 MiB `{"a":["","",…]}` (1.4 million entries) parses in 37 ms with about 100 MB resident. A config without `templates` is never counted, so one file can hold 128 of them within the 512 MiB read budget: about 5 s per file, and about 2.7 h for a folder of 2,000, which can't be stopped. That is the read budget's bound, accepted in the first pass, so it is not a finding. I have added it to the `/security-review` list. |

New findings:

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C9 | Should fix | `Sources/PhotoApp/Model/PresetActions.swift:156-158`; `Sources/PhotoApp/Views/MainView.swift:52-59`; `Sources/PhotoApp/Model/LibraryOpsActions.swift:139-142, 199` | `otherSheetIsUp` leaves out the library window's other confirmation dialog: `pendingRemoval`, used by File ▸ Remove from Library… (⌘⌫), the grid and sidebar context menus, and Remove Project from Library…. It is the same kind of window sheet as `sidebarDeletion`, which the commit includes. Nothing calls `sheetDidDismiss` when it closes. | `canRemoveFromLibrary` does not look at preset imports (`RemovalAvailability.canStart`: removing, adding folders, copying, duplicating), so ⌘⌫ works while a pack import runs. The import took 25 s in a debug build here, and a folder of packs takes seconds in release. ⌘⌫ sets `pendingRemoval` (:199), and the dialog goes up. The import then ends: `openPresetSheetWhenFree` sees `otherSheetIsUp` false and sets `showsPresetSheet = true` while the removal dialog is attached. That is F2's two-sheet state again, and the report opens over a destructive confirmation. QA can show it with `selectall; removephotos; preset summary MadeUp.lnpc; preset sheets`, which should report `presets true … attached`. Fix: add `pendingRemoval != nil` to `otherSheetIsUp`, and add `.onChange(of: model.pendingRemoval == nil) { _, closed in if closed { model.sheetDidDismiss() } }` beside the dialog. `cancelRemoval` and `confirmRemoval` both set it to nil. | One sheet at a time (UI_REDESIGN §8, design §2.2; F2, C7) |
| C10 | Nit | `PresetActions.swift:233-235`; `MainView.swift:60-66` | The summary alert for imports without a pack (`presetImportSummary`) is a third alert source on the window, also outside the rule. | Imports run in sequence. If the person imports a `.guspreset` with tables (several seconds: the table check), then picks a pack in a second Import Presets… before the first ends, the first import's alert goes up, and the pack's report then opens under it. This needs two imports running at once, so it is rare. The reverse order (an alert over the open preset manager) predates the branch. Either add `presetImportSummary != nil` to the rule with the same `onChange`, or leave it and say so in `status.md`. | One sheet at a time (F2) |

Swept for C7 (every `.sheet`, `.confirmationDialog`, `.alert`, `.popover`,
`beginSheetModal`, `runModal` and `WindowModal` in `Sources/PhotoApp` and
`Sources/PhotoUI`):

- **Covered.** Export, look-up tables, the sidebar's sheet, the sidebar's
  delete dialog. The preset manager itself is the target.
- **Inside a covered sheet.** Export's three alerts and its folder panel,
  the look-up table browser's remove alert and import panels, and the preset
  manager's own alerts and panel.
- **Missed.** `pendingRemoval` (C9) and `presetImportSummary` (C10).
- **Popovers, not sheets.** The keyword entry (⌘K) and Activity. A popover
  can coexist with a sheet.
- **AppKit window-modal sheets** (`WindowModal.run`). The Import Presets
  open panel and Add Folder Without Copying are the likeliest, then the
  comparison refusal alert and the quit question. As in the second pass,
  this is a rarer case and not a finding. AppKit queues a sheet begun on a
  window that already has one, but whether SwiftUI's `sheet` goes through
  that queue is unverified. QA can try the case that matters most: Import
  Presets… again while a folder of packs is still importing.
- **Other windows.** The import window's sheet and alerts are in another
  window.

`/security-review` still applies to the branch (parsers of outside files).
Add to its list: the per-file parse time that the 512 MiB read budget
allows (C8 note above), and the FIFO note from the second pass.
