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
