# photocli render --out overwrites a master: code review

Owner: code-reviewer. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/squash-top-10`, 4cf2107..e2f148d (the #166 commit; branch head
8d87d90). Build and tests: `swift build` clean; full `swift test` at 8d87d90:
1030 tests in 152 suites passed, 1 known issue (`LiveSessionTests`, as on
`develop`).

## Verdict
The fix is correct and covers every case in the Bug section. It is ready for QA
once C1 is fixed: one existing test now makes the full suite read the owner's
real library. `/security-review` should also run, because this changes the guard
on file writing outside the library and opens the standard catalog from `photocli`.

## Findings
| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Should fix | `Tests/PhotoCoreTests/MachineLearningNoiseReductionTests.swift:644` | `flatAreasAreQuieter` builds `CommandEnvironment(currentDirectory: folder)` without `defaultLibraryRoot` and runs `render <file> --out …` without `--library-root`. With this fix, `refuseOriginal` now opens the **standard** library for that render (`openLibraryForReading` → `LibraryLocations.standard()`), so the test suite reads the owner's real catalog | Seen on this Mac: the test ran in my full `swift test` (macOS 27, so it is enabled), and `~/Library/Application Support/Gus/Library/catalog.sqlite-shm` changed at 10:42:12, during the run, with no app process running. The catalog and its `-wal` were not touched (07:09). The test's result now depends on the developer's library: a damaged catalog, or one this build can't query, makes the render fail with `failed`, so the test fails for a reason unrelated to the feature. On CI (no library) it passes. Fix: pass `defaultLibraryRoot:` a folder inside the test's temporary directory, or `--library-root` | Checks never touch the owner's library (`docs/WORKFLOW.md` Build); tests deterministic |
| C2 | Nit | `Sources/PhotoCore/Catalog/Catalog.swift:17-21`; `RenderCommands.swift:250-251` | The comments say a read-only open creates nothing. If the WAL catalog has no `-wal`/`-shm` files (the app quit and SQLite removed them), the read-only open creates both and leaves them | Scratch check with Python's sqlite3, `mode=ro`, on a closed WAL database: `db.sqlite-shm` and `db.sqlite-wal` appear and are still there after close. The catalog's contents are untouched, so the user guide's "changes nothing in it" holds. Reword to "no catalog is created and nothing in it is written; SQLite may create its `-wal`/`-shm` files" | Accuracy of the contract |

## Questions
- For the owner (the engineer asked the same): when there is no catalog at the
  standard location, the render goes ahead with only the input refused, rather
  than requiring a library. I think this fits the command's contract: a file
  render needs no library today. Please confirm.
- By the ruling, a render that names a library (`--library-root A`, or
  `--version`) asks that library only, not the standard one as well. A master
  of the standard library can still be written through `--library-root
  <another library>`. Recorded so the owner knows; I'm not reporting it as a
  defect.

## Checked and fine
- The refusal order: the input itself (by place through `MasterFiles([source])`,
  folded name, resolved folder; by identity through `fileResourceIdentifier`
  after following links, so hard links count). Then the opened library, or the
  standard one, by place (recorded mount plus current mounts, `mounted:` passed
  explicitly) and by content (`holdsContent`, which says yes when it can't tell).
- Checked before rendering, so a refused output costs no render. A refusal is
  `outputIsMaster` (exit 1, not a usage error), and nothing is written.
- `openLibraryForReading`: a missing catalog gives nil (input-only rule).
  Missing standard location, unopenable catalog or unreadable masters give
  `failed` with nothing written. The `do throws(CommandError)` block's
  `return` leaves `refuseOriginal` as intended.
- `Catalog.openForReading`: a read-only `DatabaseQueue`, no migration (a
  private init that skips the migrator), no directory created. Its
  `prepareDatabase` runs only `PRAGMA synchronous`, which is allowed on a
  read-only connection. A write throws (`catalogOpenForReading`).
- Existing `CommandTests`/`LensCommandTests`/`UnreadableStackTests` renders
  all pass `--library-root` (`TemporaryLibrary.run`); only the test in C1
  does not.
- `ordinaryFilesStillReplaced`: export-like replacement of non-master files is
  unchanged. `write`'s temporary-then-move is unchanged.
- No pipeline bump needed (no rendering change), no migration, no UI string
  (CLI messages are not localized), no product name in `outputIsMaster`.
- User guide's Scripting paragraph matches the behavior.

## Follow-up

### Second pass (2026-11-15, `7047bad`)

Reviewed only `7047bad`. `swift build` clean; full `swift test` at `7047bad`:
1032 tests in 153 suites passed, 1 known issue (`LiveSessionTests`, as on
`develop`). The real library's `catalog.sqlite`, `-wal` and `-shm` had the
same modification times before and after the run (the `-shm` still at
10:42:12, the time of the first pass's run), with no app running.

| # | Status | Commit | Note |
| --- | --- | --- | --- |
| C1 | Fixed | `7047bad` | Every test environment is now `CommandEnvironment.hermetic` (`Tests/PhotoCoreTests/Support/HermeticCommands.swift`), whose standard library is the given folder or a temporary path that is never created, so `openLibraryForReading` returns nil instead of opening the real catalog. `flatAreasAreQuieter`, `MachineLearningCommandTests`, `CommandTests` and `RenderOutputProtectionTests` use it. No other construction of `CommandEnvironment` or `CommandLineInterface` remains in `Tests/`; no test calls a command handler directly. `BrandingTests` and the new test call `LibraryLocations.standard()` only to compute the path (it creates the system's Application Support and Caches folders if missing, never the app's). |
| C2 | Fixed | `7047bad` | `Catalog.openForReading`, `openLibraryForReading` and `refuseOriginal` now say no catalog is created and nothing in it written, and that SQLite may add `-wal`/`-shm`. `status.md` and the test name match. |
| C3 | Nit, new | `Tests/PhotoCoreTests/HermeticCommandTests.swift:13` | The scan looks for the text `CommandEnvironment(`, so `CommandEnvironment.init(…)` or an inferred `.init(currentDirectory:)` (as in `CommandLineInterface(environment: .init(currentDirectory: x))`) would get past it. Nothing does that today. Optional: also match `.init(currentDirectory:`. Not blocking. |

The scan itself: 107 Swift files under `Tests/`, 0.07 s run alone (the
50 s in the full run is wall time under parallel load). It is not vacuous
(it requires the helper to be found and to contain the construction) and
it uses the existing `RepositoryFiles` root from `#filePath`, as
`BrandingTests` does. A comment that quotes the construction would fail
it, which is the safe way round.
