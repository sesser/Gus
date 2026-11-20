# photocli render --input opens the default library: code review

Owner: code-reviewer. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md` (bug fix).
Reviewed: `bug/photocli-render-input-library`, d62cd4d..279d5ec (61adc2f
reproduction, 279d5ec fix; both commits signed). Build and tests: `swift build` clean; full `swift test`
1242 tests in 177 suites passed, no issues (the flaky `DeferredRenderTests`,
#229, passed this run).

## Verdict

Ready for QA. The cause is right, the fix is exactly the owner's ruling of
2026-11-19 (option A on RI-1) and nothing wider: a file render without
`--library-root` now reaches no library path at all, and `--version` renders
and renders with `--library-root` keep every #166 check unchanged. No
Blocker or Should fix; two Nits.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Nit | `Tests/PhotoCoreTests/RenderOutputProtectionTests.swift:133-134` | The `--version` half of `unreadableStandardLibraryIsNotRead` checks exit 1 only, where the test it replaces checked the code `failed`. | A `--version` render on a damaged standard catalog that failed for another reason with exit 1 (say `versionNotFound`, if `Catalog.open` someday tolerated the garbage file and the query found nothing) would still pass, so the test would no longer pin "an unreadable catalog refuses with `failed`". Add `#expect(version.standardError.contains("\"failed\""))`. | Tests check the behavior they describe |
| C2 | Nit | `Sources/PhotoCore/Catalog/Catalog.swift:17-26` | `Catalog.openForReading` now has no caller in `Sources/`; its comment says so but not why it stays. | None at run time. A later reader may delete it as dead code, or use it believing a read-only open leaves the folder alone (the comment does now say `-shm` is written, which is right). Recommendation: keep it (tested by `catalogOpenForReading`, and #234 names it as the open the read commands should move to) and add "kept for #234" to the comment. | Clarity; no rule |

## Questions

None. The narrowing of the #166 ruling is the owner's (RI-1, option A,
2026-11-19, `status.md` Rulings); see "Security" below for what it gives up.

## Checked and fine

- **Cause.** Before the fix `refuseOriginal` with no library called
  `CommandEnvironment.openLibraryForReading`, which fell back on
  `defaultLibraryRoot` / `LibraryLocations.standard()` and opened the catalog
  with `Catalog.openForReading` (read-only `DatabaseQueue`). A WAL reader
  maps and writes `-shm` (read marks; and the first connection after the last
  one closed rebuilds the wal-index), and creates `-wal`/`-shm` when absent.
  That is the reported `-shm` modification time with database and WAL
  unchanged. Matches `status.md`'s Bug section.
- **Test fails without the fix** (by reading; no stash). At 61adc2f
  `fileRenderLeavesTheStandardLibraryAlone` injects a closed library (database,
  `-wal`, `-shm` all `#require`d present) as `defaultLibraryRoot`; the old
  path opens exactly that catalog and reads `masterFiles`, which writes
  `-shm`, so `FolderState` (bytes and modification time of every regular file
  under the library root, catalog and preview folders both) differs. The
  test was committed inside `withKnownIssue` and the engineer's run at
  61adc2f recorded the known issue (an unrecorded known issue would itself
  fail), so the failure was observed, not assumed. If a future SQLite deleted
  the WAL on close, the `#require`s fail rather than the test passing
  vacuously.
- **A file render without `--library-root` opens nothing under the standard
  paths.** Every step of `runRender` for `(input?, nil)` with no
  `libraryRoot`: `library` stays nil; `refuseOriginal` returns after the
  input check (`guard let library else { return }`); `--stack` reads only the
  named file; `AdjustmentRenderer(lookTables: nil)`, so no `LookTableStore`
  and no `Library/LUTs`; `PreviewGenerator.rendering` uses no disk cache;
  `write` creates its `.partial` beside `--out` only. The only calls into
  `LibraryLocations.standard()` in PhotoCore are
  `CommandEnvironment.libraryLocations` (now reached by a file render only
  through `openLibrary` with `--library-root`, which never falls back) and
  the app's own launch code; `CommandLineInterface` does no library work
  before dispatch; `photocli`'s `main.swift` builds the environment with no
  default root and nothing else.
- **Input refused as its own output**: unchanged code (`MasterFiles([source])`
  by place and case, `isSameFile` by identity through links and hard links);
  `inputItselfWithoutLibrary` and the new `expectRefused(cli, out: input, …)`
  in `fileRenderAsksNoLibrary` cover it.
- **`--version` and `--library-root` keep #166 in full.** `library` is set
  exactly for `--version` (standard or named, `Catalog.open`) and for a file
  with `--library-root`; `refuseOriginal` then runs the same
  `masterFiles(mounted:)` / `contains` / `holdsContent(ofFileAt:)` code as
  before, and a failure to read masters is still `failed` with nothing
  written. A named or standard catalog that can't be opened is still `failed`
  from `openLibrary` (untouched). Covered by `versionOntoItsOwnMaster`,
  `anyMasterByPlace`, `masterByContent`, `ordinaryFilesStillReplaced` and the
  new `namedLibraryAndVersionRendersStillProtectMasters` (place and byte copy,
  file with `--library-root`, `--version` with and without it), and the
  `--version` half of `unreadableStandardLibraryIsNotRead` (damaged standard
  catalog: exit 1, nothing written, no `-wal`/`-shm` created).
- **No other command changed.** The diff touches only `render`'s
  `refuseOriginal` and its call, `render`'s help text, the removal of
  `openLibraryForReading` (one caller, gone; `grep` finds no other) and a
  comment on `Catalog.openForReading`. `openLibrary`, `lockLibrary` and
  `libraryLocations` are byte for byte as on `develop`.
- **Security: the narrowing is exactly the ruling.** What is given up:
  `photocli render <file> --out <a master of the standard library, or a byte
  copy of one>` with no `--library-root` now writes over it (exit 0), as
  `fileRenderAsksNoLibrary` asserts. Nothing else: the write path (`write`,
  temporary file then `replaceItemAt`/`moveItem`) is unchanged, no parser,
  subprocess, network or new write location is added, and the
  unreadable-catalog refusal still holds wherever a library is read. This
  departs from `CLAUDE.md`'s "originals are never written" for that one
  invocation by the owner's explicit choice; the help text and USER_GUIDE
  tell the user to name the library to have its originals protected.
- **Tests hermetic and deterministic.** Every environment is
  `.hermetic(…standardLibrary:)` with a temporary folder
  (`RepositoryFiles.withTemporaryDirectory`, `CommandTests.withLibrary`), so
  `HermeticCommandTests` still holds and the real library is never reached;
  `ImageIOMetadataReader`, no ExifTool; no sleeps or timing; `catalogBytes`
  now includes `-shm`, a stronger check.
- **Help text and USER_GUIDE.** `--library-root` ("With --version, the app's
  standard library when left out; a file is rendered without reading any
  library unless this names one") and `--out` match the code; the
  USER_GUIDE Scripting paragraph and the "without it the standard library is
  used (except by `render` of a file…)" sentence are accurate. README's
  command-line paragraph says nothing on this, so no change there.
- No migration, no pipeline bump, no golden, no rendering change; no new
  dependency; no brand value or UI string.

## Security review

Not needed for this diff: it removes a library read and adds no parser,
subprocess, network code or new place written. The one security-relevant
effect (a file render without `--library-root` can overwrite a standard
library master) is the owner's ruling, recorded above.

## Follow-up

(After the engineer's fixes.)
