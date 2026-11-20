Issue: #222

# photocli render --input opens the default library: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/photocli-render-input-library`, from `develop` at
`d62cd4d`.

**Status: Done.** Owner's ruling on RI-1 (2026-11-19): option A (see
Rulings). Next: code-reviewer; no UI changed, so no design review; then
qa-tester.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `d62cd4d`; never on the real library, see the test).
1. A library whose catalog is closed (the app has quit), with `catalog.sqlite`,
   `catalog.sqlite-wal` and `catalog.sqlite-shm` in its `Library` folder, at
   the standard location.
2. `photocli render <any image file> --out <new file>.png` with no `--library-root`.

**Expected** (#222, as ruled under RI-1). A render of a file by path with no
`--library-root` never opens a library: nothing in the standard library's
folder is created, written or touched.

**Actual.** The render succeeds, and the standard library's
`catalog.sqlite-shm` gets a new modification time (`catalog.sqlite` and the
WAL keep theirs). Found by the QA of #218 (`docs/features/bw-module/qa.md`,
Q2), and seen in earlier QA runs too (`dehaze-above-white`,
`full-render-main-thread-stall`, `libraw-o3`).

**Root cause.** Not an accident: it is how #166 was fixed, per the owner's
ruling of 2026-11-15 (`docs/features/render-out-overwrites-master/status.md`,
"Owner's ruling"): `--out` always consults a library's catalog, and for a
file rendered without `--library-root` that is the standard library, opened
read-only. `RenderCommands.refuseOriginal` calls
`CommandEnvironment.openLibraryForReading`, which falls back on
`LibraryLocations.standard()` (`CommandEnvironment.libraryLocations`) and
opens it with `Catalog.openForReading` (a read-only GRDB `DatabaseQueue`).
"Read-only" protects the database, not the folder: in WAL mode every SQLite
reader maps the `-shm` file (the WAL index) and writes to it (its read mark,
and the index itself when it rebuilds it after the last connection closed),
and it creates `-wal` and `-shm` if they are missing. The #166 comments and
its test said as much (`catalogBytes` compares the database and the WAL, not
`-shm`); #222 is the owner deciding that even this is too much for a command
that only renders a file.

**Test that fails without the fix.** `RenderInputLibraryTests.fileRenderLeavesTheStandardLibraryAlone`
(`Tests/PhotoCoreTests/RenderInputLibraryTests.swift`, Swift Testing). It
makes a library in a temporary folder, imports one photo, closes the catalog
(its `-wal` and `-shm` stay, as in the owner's library), injects that folder
as the environment's standard library (`CommandEnvironment.hermetic(standardLibrary:)`,
so the real one is never reached), renders another file with no
`--library-root`, and compares every file in the library folder (bytes and
modification time) before and after. Today it fails exactly as reported:
`catalog.sqlite-shm` 32768 bytes, modification time moved; the database and
the WAL unchanged. It was committed inside `withKnownIssue` (`61adc2f`)
while RI-1 was open; the fix removed the wrapper, and the test now also
checks the render succeeded.

A side finding from writing it: in that fixture the import's rows sit in
the WAL (692 KB) and the database file is 4 KB, which rules out reading the
catalog with SQLite's `immutable=1` (it ignores the WAL; option C in RI-1).

## Other photocli commands (same fallback)

Every command that takes `--library-root` falls back on the standard library
through the same `CommandEnvironment.libraryLocations` when it is left out.
For all but a file render this is the documented contract (they act on a
library: USER_GUIDE "Pass `--library-root` as for the app; without it the
standard library is used"), so they are not this bug and are not changed
here. Listed for the follow-up (proposed issue F1):

| Command | Without `--library-root` | What it does to the standard library |
| --- | --- | --- |
| `render <file>` | the #166 check | before the fix: read-only open (`Catalog.openForReading`): `-shm` written, `-wal`/`-shm` created if missing. **This bug.** After: nothing |
| `render <file> --library-root X` | — | `Catalog.open` on X (a writer: migrates X if it is older) |
| `render --version N` | standard library | `Catalog.open` (only when the catalog file exists): runs migrations, writer connection |
| `query projects`, `query images`, `mask list` (reads) | standard library | `Catalog.open`, as above: a read command can migrate the catalog |
| `develop`, `rate`, `flag`, `label`, `export`, `mask add`/`set`/`remove` (writes; `--dry-run` reads) | standard library | `LibraryLock` (`library.lock`) then `Catalog.open`, and the change |
| `adjustments`, `help` | — | nothing |

No one-line change covers the others without changing their contract, so
only `render <file>` is in scope. The main session files the follow-ups
(F1, a guard for `photocli`'s standard-library fallback; F2, read commands
that open the catalog as a writer and migrate it).

## Rulings

- **RI-1, owner, 2026-11-19: option A.** A file render (`render <file>`)
  without `--library-root` reads no library at all; only the file being
  rendered is refused as its own output. `--version` renders and renders
  with `--library-root` keep the full #166 check. This **narrows the owner's
  #166 ruling of 2026-11-15** (`docs/features/render-out-overwrites-master/status.md`,
  "Owner's ruling"): a file rendered without `--library-root` onto a master
  of the standard library is no longer refused. Said in `--out`'s and
  `--library-root`'s help text and in `docs/USER_GUIDE.md` (Scripting).

## The fix

- `RenderCommands.refuseOriginal(_:source:library:)`: refuses the input
  itself as before, then checks a catalog only when the command opened a
  library (`--version`, or `--library-root` for a file). The branch that
  opened the standard library read-only is gone, with its `environment` and
  `arguments` parameters.
- `CommandEnvironment.openLibraryForReading` is removed (its one caller was
  that branch). `Catalog.openForReading` stays, now without a caller in the
  sources: it is tested (`catalogOpenForReading`) and is what F2 (read
  commands without migration) would use; its comment now says every reader
  writes `-shm`. Code review may prefer deleting it until F2.
- Help text: `--library-root` says a file is rendered without reading any
  library unless it names one; `--out` says which library's masters are
  refused and that a file rendered without `--library-root` is checked
  against itself only.
- `docs/USER_GUIDE.md` (Scripting): the `render --out` paragraph and the
  "without it the standard library is used" sentence.
- Tests: `RenderInputLibraryTests.fileRenderLeavesTheStandardLibraryAlone`
  without its wrapper; in `RenderOutputProtectionTests`,
  `standardLibraryAskedForAFileRender` became `fileRenderAsksNoLibrary`
  (with the standard library holding them, another photo's master and a
  byte copy of one are written by a file render, the input itself is
  refused, and the catalog's database, WAL and `-shm` keep their bytes),
  `unreadableStandardLibraryRefuses` became `unreadableStandardLibraryIsNotRead`
  (a damaged standard catalog no longer stops a file render; a `--version`
  render without `--library-root` still reads it and fails, writing
  nothing, and no `-wal`/`-shm` appears beside it), and the new
  `namedLibraryAndVersionRendersStillProtectMasters` (a master and a byte
  copy of one are refused for a file with `--library-root`, and for
  `--version` with and without it). The comments of `inputItselfWithoutLibrary`
  and `CommandEnvironment.hermetic` follow the new rule.

No rendering changed: no pipeline bump, no golden, no migration.

## Requirements issue RI-1 (ruled: option A, see Rulings)

#222 says "never opens a library, or refuses without `--library-root`". The
owner's #166 ruling says a file render without `--library-root` must check
the standard library. Both can't hold. Options:

- **A. A file render opens a library only when `--library-root` names one.**
  Without it no library is read; the file being rendered is still refused
  (by place and identity, as now); any other existing file at `--out` is
  replaced. `render --version N` and any render with `--library-root` keep
  the full #166 check. Cost: small (drop the standard-library branch of
  `refuseOriginal`; rewrite `standardLibraryAskedForAFileRender` and
  `unreadableStandardLibraryRefuses` to the new rule; `--out` help text and
  USER_GUIDE). Gives up one #166 protection: `photocli render a.jpg --out
  <a master in the standard library>` writes over that master.
- **B. A file render without `--library-root` is refused** (usage error,
  exit 2, nothing read), as the app's guard refuses a test launch. Keeps all
  of #166. Cost: small in code, but every existing `render <file>` call
  without the option breaks (QA recipes in `docs/features/*/qa.md`, scripts),
  and a Mac with no library has no way to render a file (`--library-root`
  must name an existing library; `photocli` can't create one). So B needs an
  explicit way out, for example a new `--no-library` flag ("check no
  library; only the file being rendered is refused"): new command-line
  surface, the owner's to approve.
- **C. Keep asking the standard library without touching its files.** Not
  feasible cheaply: `immutable=1` ignores the WAL (a running or recently quit
  app's latest masters live there), and copying the catalog and WAL to a
  temporary folder for each render costs a full copy and races a running
  app. Not recommended.
- **D. Ask a library only when `--out` already exists** (a file that isn't
  there can't be overwritten). Combines with A or B; it would have avoided
  every QA case seen so far, but it still opens the standard library when
  `--out` exists, so on its own it doesn't meet #222.

Recommendation: **A**. It is #222's first expectation and the least
surprise for "render this file": nothing reaches the standard library unless
named, the same principle as the app's launch guard. The #166 repro
(`--version` onto its own master) and every render with `--library-root`
stay protected. It needs the owner's explicit OK because it narrows the
2026-11-15 ruling. If the owner wants that protection kept, B with
`--no-library`.

## Results

| Check | Result |
| --- | --- |
| Baseline `swift build` at `d62cd4d` | Clean |
| Baseline `swift test` at `d62cd4d` | 1240 tests in 176 suites, 1 issue: `DeferredRenderTests` "Core Animation renders an unread deferred image…" (the known flaky #229) |
| `swift test --filter RenderInputLibraryTests` (unfixed, without the wrapper) | Fails: `catalog.sqlite-shm` modification time moved |
| `swift test --filter "HermeticCommandTests\|RenderOutputProtectionTests\|RenderInputLibraryTests"` (with the wrapper, `61adc2f`) | 11 tests in 3 suites passed, 1 known issue (this one) |
| `swift build` after the fix | Clean, no warnings |
| `swift test --filter "HermeticCommandTests\|RenderOutputProtectionTests\|RenderInputLibraryTests\|CommandTests\|MachineLearningNoiseReductionTests"` after the fix | 80 tests in 12 suites passed |
| Full `swift test` after the fix | 1242 tests in 177 suites passed, no issues (the flaky `DeferredRenderTests` passed this run) |

No `photocli` was run against any library for this work: the reproduction is
the test, with an injected library location.

## Bug section mapped to checks

| Item | Check |
| --- | --- |
| A file render without `--library-root` leaves the standard library's folder byte for byte and time for time unchanged | `RenderInputLibraryTests.fileRenderLeavesTheStandardLibraryAlone` (known issue until the fix) |
| A file render without `--library-root` reads no library: standard-library masters are ordinary files to it, the input is still refused, a damaged standard catalog doesn't stop it | `fileRenderAsksNoLibrary`, `unreadableStandardLibraryIsNotRead`, `inputItselfWithoutLibrary` |
| `--version` (with or without `--library-root`) and a file render with `--library-root` still refuse masters by place and content | `namedLibraryAndVersionRendersStillProtectMasters`, `anyMasterByPlace`, `masterByContent`, `versionOntoItsOwnMaster` |
| A `--version` render still reads the standard library when none is named | `unreadableStandardLibraryIsNotRead`, `namedLibraryAndVersionRendersStillProtectMasters` |

## Review fixes

From `code-review.md` (both optional nits):

| # | Finding | Fix |
| --- | --- | --- |
| C1 | `unreadableStandardLibraryIsNotRead`'s `--version` half checked only the exit code | Also expects the code `failed` on standard error |
| C2 | `Catalog.openForReading` has no caller; say why it stays | Its comment says it is kept for #234 (read commands should open the catalog with it instead of migrating) |

Results: `swift build` clean; `swift test --filter "RenderOutputProtectionTests|RenderInputLibraryTests"`: 10 tests in 2 suites passed (no full run: a test assertion and a comment only).

## Open questions

- None. For a person (optional): none; no UI, and `photocli` against the
  real library is what this fix exists to avoid.

## README

No README change needed: its Command line paragraph doesn't describe which
library `render` reads. `photocli render`'s contract changed (a file render
without `--library-root` reads no library); USER_GUIDE says so. `CLAUDE.md`
(owner's): proposed lines are in the engineer's report, not edited here.

## Summary for the issue

Fixed on `bug/photocli-render-input-library` (owner's ruling 2026-11-19,
option A, narrowing #166's): `photocli render <file>` without
`--library-root` reads no library; only the input is refused as its own
output. `--version` renders and renders with `--library-root` keep the full
#166 check. Root cause: #166's check opened the standard catalog read-only,
and SQLite still writes `-shm`. `RenderInputLibraryTests` fails without the
fix; full `swift test`: 1242 passed. No manual checks. Details:
`docs/features/photocli-render-input-library/status.md`.
